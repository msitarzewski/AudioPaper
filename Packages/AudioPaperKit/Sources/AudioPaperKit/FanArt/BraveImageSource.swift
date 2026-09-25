import Foundation

/// Fan art from the Brave Search image API (`X-Subscription-Token`), safe search forced to strict.
public struct BraveImageSource: FanArtSource {
    public let id = "brave"
    public let displayName = "Web search (Brave)"

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
        // For artists without fan art, "fan art wallpaper" drifts to namesakes (Ray Noir → the cartoon
        // Chat Noir), so "{artist} press photo" follows when relevant results are still short: it finds
        // large promo shots. ("4k" was tried and found film-noir Blu-ray listings.)
        let queries = ["\(artist) \(song) fan art wallpaper", "\(artist) fan art wallpaper", "\(artist) press photo"]
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
            // Song-specific results rank ahead of artist-wide ones, fan art ahead of photos.
            results += Self.candidates(from: response, for: track).map { candidate in
                var candidate = candidate
                candidate.matchScore *= [1, 0.8, 0.6][index]
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
        let titleText = phraseText(title ?? "")
        let slugText = phraseText((pageURL?.path(percentEncoded: false) ?? "").replacing(/[-_\/]/, with: " "))
        let words = Set("\(titleText) \(slugText)".split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init))
        /// The name as a whole phrase, not scattered words: "Blu-ray Noir" must not count as "Ray Noir".
        /// In titles a hyphen binds words ("blu-ray"); in page slugs hyphens separate them.
        func mentions(_ name: String) -> Bool {
            let phrase = phraseText(Normalizer.searchTerm(name))
            guard !phrase.isEmpty else { return false }
            let variants = phrase.hasPrefix("the ") ? [phrase, String(phrase.dropFirst(4))] : [phrase]
            return variants.contains { variant in
                containsPhrase(variant, in: titleText) || containsPhrase(variant.replacingOccurrences(of: "-", with: " "), in: slugText)
            }
        }
        guard mentions(track.artist) else { return nil }
        // Accents distinguish artists ("ROSÉ" vs "Rose"): when the name has them, the result must too.
        if track.artist.unicodeScalars.contains(where: { !$0.isASCII }),
           !"\(title ?? "") \(pageURL?.path(percentEncoded: false) ?? "")".lowercased().contains(Normalizer.searchTerm(track.artist).lowercased()) {
            return nil
        }
        if !track.title.isEmpty, mentions(track.title) { return 1 }
        if !track.album.isEmpty, mentions(track.album) { return 0.8 }
        if !words.isDisjoint(with: musicWords) { return 0.6 }
        // A multi-word name ("Nine Inch Nails") is specific enough on its own; a single word is not.
        if Normalizer.key(track.artist).split(separator: " ").count >= 2 { return 0.5 }
        return nil
    }

    /// Case- and accent-folded text with "&" as "and" and punctuation as spaces, keeping hyphens.
    static func phraseText(_ string: String) -> String {
        let folded = string.decodingHTMLEntities()
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
        let spaced = String(folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? Character($0) : " " })
        return spaced.split(separator: " ").joined(separator: " ")
    }

    /// Whether `phrase` appears in `text` as whole words (letters, digits and hyphens bind a word).
    /// NSRegularExpression, because Swift's `Regex` has no look-behind.
    static func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}-])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}-])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func candidates(from response: Response, for track: Track) -> [ArtworkCandidate] {
        var seen = Set<String>()
        return response.results.compactMap { result in
            let pageURL = result.url.flatMap(URL.init(string:))?.webLink
            let title = result.title?.decodingHTMLEntities()
            guard let raw = result.properties?.url, let imageURL = URL(string: raw).flatMap(Self.secure),
                  imageURL.isAllowedRemote, let host = imageURL.host()?.lowercased(),
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
                    // Named from the page's real address, not the result's self-reported `source`, so a
                    // page can't label its link as some other site.
                    sourceName: Self.siteName(pageURL?.host() ?? host)
                ),
                matchScore: matchScore
            )
        }
    }

    /// Web results often link images over plain http; most of those sites serve the same file over https,
    /// which is the only way AudioPaper fetches anything.
    static func secure(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        if components?.port == 80 { components?.port = nil }
        return components?.url
    }

    /// "www.example.com" → "example.com", for credits.
    static func siteName(_ host: String) -> String {
        let host = host.lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
