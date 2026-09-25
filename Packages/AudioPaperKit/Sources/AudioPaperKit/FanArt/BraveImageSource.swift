import Foundation

/// Fan art from the Brave Search image API (`X-Subscription-Token`), safe search forced to strict.
public struct BraveImageSource: FanArtSource {
    public let id = "brave"
    public let displayName = "Brave Image Search"

    /// Sites whose images are almost always merch mockups, thumbnails, or lyric cards.
    /// Matched against both the image host and the page it was found on.
    static let blockedHosts = [
        "etsy.com", "etsystatic.com", "redbubble.com", "redbubble.net", "teepublic.com", "zazzle.com",
        "society6.com", "pixels.com", "fineartamerica.com", "amazon.com", "media-amazon.com", "ebay.com",
        "ebayimg.com", "discogs.com", "ytimg.com", "youtube.com", "genius.com", "musixmatch.com",
    ]

    /// Brave's free plan allows one request per second; shared so concurrent lookups queue politely.
    static let limiter = RateLimiter(interval: .milliseconds(1100))

    private let http: any HTTPClient
    private let secrets: any SecretStore

    public init(http: any HTTPClient = URLSessionHTTPClient(), secrets: any SecretStore) {
        self.http = http
        self.secrets = secrets
    }

    public var isConfigured: Bool { secrets.value(for: .braveAPIKey) != nil }
    /// Web search is metered (the free tier is 2,000 queries/month), so it only fills gaps.
    public var isFallback: Bool { true }

    struct Response: Decodable {
        struct Result: Decodable {
            struct Properties: Decodable {
                var url: String?
                var width: Int?
                var height: Int?
            }
            var title: String?
            var url: String?
            var source: String?
            var properties: Properties?
        }
        var results: [Result]
    }

    public func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate] {
        guard let key = secrets.value(for: .braveAPIKey) else { return [] }
        let artist = Normalizer.searchTerm(track.artist)
        let song = Normalizer.searchTerm(track.title)
        // "wallpaper" steers results toward desktop-sized images; the artist-wide query widens the pool.
        let queries = ["\(artist) \(song) fan art wallpaper", "\(artist) fan art wallpaper"]
        var results: [ArtworkCandidate] = []
        for (index, query) in queries.enumerated() {
            let url = URL.api("https://api.search.brave.com/res/v1/images/search", [
                "q": query, "count": "50", "safesearch": "strict",
            ])
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
            try await Self.limiter.wait()
            let response: Response
            do {
                response = try await http.json(Response.self, from: request)
            } catch where !results.isEmpty {
                // Keep what the first query found if a later one is throttled or fails.
                log.error("Brave query failed: \(error.localizedDescription, privacy: .public)")
                break
            }
            // Song-specific results rank ahead of artist-wide ones.
            results += Self.candidates(from: response, for: track).map { candidate in
                var candidate = candidate
                candidate.matchScore *= index == 0 ? 1 : 0.8
                return candidate
            }
            if results.count >= limit { break }
        }
        var seen = Set<URL>()
        return Array(results.filter { seen.insert($0.imageURL).inserted }.prefix(limit))
    }

    static func isBlocked(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return blockedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// Words that tie a result to music when it names the artist but not the song or album.
    static let musicWords: Set<String> = ["music", "band", "album", "song", "single", "ep", "tour", "musician", "singer", "rapper", "dj"]

    /// How clearly a result is about this artist, from its title and page URL; nil when it isn't.
    ///
    /// Single-word artist names are often ordinary words ("Sleepover", "Cake"), so for those naming the artist
    /// isn't enough: the result must also mention the song, the album, or something musical.
    static func relevance(title: String?, pageURL: URL?, track: Track) -> Double? {
        let slug = (pageURL?.path(percentEncoded: false) ?? "").replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let words = Set(Normalizer.key("\(title ?? "") \(slug)").split(separator: " ").map(String.init))
        func mentions(_ name: String) -> Bool {
            let tokens = Normalizer.key(name).split(separator: " ").map(String.init)
            return !tokens.isEmpty && tokens.allSatisfy(words.contains)
        }
        guard mentions(track.artist) else { return nil }
        // Accents distinguish artists ("ROSÉ" vs "Rose"): when the name has them, the result must too.
        if track.artist.unicodeScalars.contains(where: { !$0.isASCII }),
           !"\(title ?? "") \(slug)".lowercased().contains(Normalizer.searchTerm(track.artist).lowercased()) {
            return nil
        }
        if !track.title.isEmpty, mentions(track.title) { return 1 }
        if !track.album.isEmpty, mentions(track.album) { return 0.8 }
        if !words.isDisjoint(with: musicWords) { return 0.6 }
        // A multi-word name ("Nine Inch Nails") is specific enough on its own; a single word is not.
        if Normalizer.key(track.artist).split(separator: " ").count >= 2 { return 0.5 }
        return nil
    }

    static func candidates(from response: Response, for track: Track) -> [ArtworkCandidate] {
        var seen = Set<String>()
        return response.results.compactMap { result in
            let pageURL = result.url.flatMap(URL.init(string:))
            let title = result.title?.decodingHTMLEntities()
            guard let raw = result.properties?.url, let imageURL = URL(string: raw),
                  let host = imageURL.host()?.lowercased(),
                  !isBlocked(host), !isBlocked(pageURL?.host()), !isBlocked(result.source),
                  let matchScore = relevance(title: title, pageURL: pageURL, track: track),
                  seen.insert(raw).inserted
            else { return nil }
            return ArtworkCandidate(
                imageURL: imageURL,
                width: result.properties?.width,
                height: result.properties?.height,
                kind: .fanArt,
                providerID: "brave",
                attribution: Attribution(
                    // Wallpaper sites title pages with SEO filler ("Colorful Glasses Singer Pose Wallpaper"),
                    // so the credit names the artist the result was matched to; the page stays one click away.
                    title: track.artist,
                    pageURL: pageURL,
                    sourceName: result.source ?? host
                ),
                matchScore: matchScore
            )
        }
    }
}
