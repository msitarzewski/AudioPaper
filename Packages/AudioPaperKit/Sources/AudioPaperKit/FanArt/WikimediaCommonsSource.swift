import Foundation

/// Freely licensed artist photos from Wikimedia Commons, found by exact identity: MusicBrainz ID →
/// the artist's Wikidata item → its Commons category. No key or quota. Every image carries its
/// photographer and license, which the credit shows (CC BY and BY-SA require it).
///
/// Originals up to 4000 px wide are used as they are (full quality on Retina displays); larger ones, often
/// 10–20 MB, as Commons' 1920 px rendition (Commons only serves renditions at standard widths — asked for
/// 2560 it returns the original). Commons appends `utm_*` tracking parameters to file URLs; they're removed.
public struct WikimediaCommonsSource: FanArtSource {
    static let memo = ArtistMemo()
    static let maxOriginalWidth = 4000
    static let renditionWidth = 1920
    /// Wikimedia asks API clients to pace themselves; one request at a time, a little apart.
    static let limiter = RateLimiter(interval: .milliseconds(500))

    public let id = "wikimedia"
    public let displayName = "Wikimedia Commons"
    public let isConfigured = true

    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    actor ArtistMemo {
        private var results: [String: [ArtworkCandidate]] = [:]
        func get(_ key: String) -> [ArtworkCandidate]? { results[key] }
        func set(_ key: String, _ value: [ArtworkCandidate]) { results[key] = value }
    }

    struct EntityResponse: Decodable {
        struct Entity: Decodable {
            struct Claim: Decodable {
                struct Snak: Decodable {
                    /// Wikidata values are strings, dates, quantities or coordinates depending on the property;
                    /// only strings are needed (the Commons category), so anything else decodes as nil.
                    struct Value: Decodable {
                        var value: String?

                        enum CodingKeys: String, CodingKey { case value }

                        init(from decoder: any Decoder) throws {
                            value = try? decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .value)
                        }
                    }
                    var datavalue: Value?
                }
                var mainsnak: Snak
            }
            var claims: [String: [Claim]]
        }
        var entities: [String: Entity]
    }

    struct CategoryResponse: Decodable {
        struct Query: Decodable {
            struct Page: Decodable {
                struct Info: Decodable {
                    struct Metadata: Decodable {
                        struct Field: Decodable { var value: String? }
                        var Artist: Field?
                        var LicenseShortName: Field?
                    }
                    var url: String
                    var width: Int
                    var height: Int
                    var thumburl: String?
                    var descriptionurl: String?
                    var extmetadata: Metadata?
                }
                var title: String
                var imageinfo: [Info]?
            }
            var pages: [Page]?
        }
        var query: Query?
    }

    public func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate] {
        let artistKey = MusicBrainz.identityKey(track.artist)
        if let known = await Self.memo.get(artistKey) { return known }
        var found: [ArtworkCandidate] = []
        if let mbid = try await MusicBrainz.artistID(for: track, http: http),
           let qid = try await MusicBrainz.wikidataID(forArtist: mbid, http: http),
           let category = try await commonsCategory(of: qid) {
            // Only images big enough for a wallpaper count toward the limit (Commons reports sizes up front),
            // so a category full of thumbnails and portraits doesn't use up the search.
            found = try await files(in: category, artist: track.artist, limit: limit).filter(Self.isWallpaperSized)
            if found.count < limit {
                found += try await filesInSubcategories(of: category, artist: track.artist, limit: limit - found.count)
            }
        }
        await Self.memo.set(artistKey, found)
        return found
    }

    private func commonsCategory(of qid: String) async throws -> String? {
        try await Self.limiter.wait()
        let url = URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json")!
        return Self.category(in: try await http.json(EntityResponse.self, from: URLRequest(url: url)))
    }

    /// The artist's Commons category (Wikidata property P373).
    static func category(in response: EntityResponse) -> String? {
        response.entities.values.first?.claims["P373"]?.first?.mainsnak.datavalue?.value
    }

    private func files(in category: String, artist: String, limit: Int) async throws -> [ArtworkCandidate] {
        try await Self.limiter.wait()
        let url = URL.api("https://commons.wikimedia.org/w/api.php", [
            "action": "query", "format": "json", "formatversion": "2",
            "generator": "categorymembers", "gcmtitle": "Category:\(category)", "gcmtype": "file",
            "gcmlimit": String(min(limit, 50)),
            "prop": "imageinfo", "iiprop": "url|size|extmetadata", "iiurlwidth": String(Self.renditionWidth),
            "iiextmetadatafilter": "Artist|LicenseShortName",
        ])
        return Self.candidates(from: try await http.json(CategoryResponse.self, from: URLRequest(url: url)), artist: artist)
    }

    struct SubcategoryResponse: Decodable {
        struct Query: Decodable {
            struct Member: Decodable { var title: String }
            var categorymembers: [Member]
        }
        var query: Query?
    }

    /// Many artists' photos are filed a level or two down — "Aespa (musical group)" → "Aespa by year" →
    /// "Aespa in 2025". Only subcategories named after the artist's own category are followed, so other
    /// people filed under it ("Chris Greatti (songwriter)" under Poppy) aren't; logos and media are skipped.
    /// Newest first, and at most `maxSubcategoryRequests` requests per artist.
    static let maxSubcategoryRequests = 6

    private func filesInSubcategories(of category: String, artist: String, limit: Int) async throws -> [ArtworkCandidate] {
        var queue = try await subcategories(of: category, root: category)
        var requests = 1
        var found: [ArtworkCandidate] = []
        var seen = Set<URL>()
        while let next = queue.first, found.count < limit, requests < Self.maxSubcategoryRequests {
            queue.removeFirst()
            requests += 1
            if Self.isGrouping(next) {
                queue = try await subcategories(of: next, root: category) + queue
            } else {
                for candidate in try await files(in: next, artist: artist, limit: 50)
                where Self.isWallpaperSized(candidate) && found.count < limit && seen.insert(candidate.imageURL).inserted {
                    found.append(candidate)
                }
            }
        }
        return found
    }

    private func subcategories(of category: String, root: String) async throws -> [String] {
        try await Self.limiter.wait()
        let url = URL.api("https://commons.wikimedia.org/w/api.php", [
            "action": "query", "format": "json", "formatversion": "2",
            "list": "categorymembers", "cmtitle": "Category:\(category)", "cmtype": "subcat", "cmlimit": "50",
        ])
        let response = try await http.json(SubcategoryResponse.self, from: URLRequest(url: url))
        return Self.relevantSubcategories(response.query?.categorymembers.map(\.title) ?? [], of: root)
    }

    /// Subcategories worth searching, newest first: named after the artist's own category `root` (minus any
    /// "(musical group)"-style qualifier), and not logos, sounds or video.
    static func relevantSubcategories(_ titles: [String], of root: String) -> [String] {
        let base = root.replacing(/\s*\([^)]*\)\s*$/, with: "").lowercased()
        // "Members of …" leads to categories named after each member, which wouldn't be followed anyway.
        let skipped = ["logo", "audio", "sound", "video", "signature", "album cover", "discograph", "members of"]
        return titles
            .map { $0.hasPrefix("Category:") ? String($0.dropFirst(9)) : $0 }
            .filter { name in
                let lower = name.lowercased()
                return lower != root.lowercased() && lower.contains(base) && !skipped.contains { lower.contains($0) }
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
    }

    /// "Aespa by year": a category of categories, listed rather than searched for files.
    static func isGrouping(_ category: String) -> Bool {
        category.lowercased().contains(" by ")
    }

    static func isWallpaperSized(_ candidate: ArtworkCandidate) -> Bool {
        SizeFilter().accepts(width: candidate.width, height: candidate.height)
    }

    static func candidates(from response: CategoryResponse, artist: String) -> [ArtworkCandidate] {
        (response.query?.pages ?? []).compactMap { page in
            guard let info = page.imageinfo?.first,
                  ["jpg", "jpeg", "png", "webp", "tif", "tiff"].contains(page.title.split(separator: ".").last?.lowercased() ?? "")
            else { return nil }
            let useRendition = info.width > maxOriginalWidth && info.thumburl != nil
            let scale = useRendition ? Double(renditionWidth) / Double(info.width) : 1
            guard let imageURL = withoutTracking(useRendition ? info.thumburl! : info.url) else { return nil }
            return ArtworkCandidate(
                imageURL: imageURL,
                width: Int((Double(info.width) * scale).rounded()),
                height: Int((Double(info.height) * scale).rounded()),
                kind: .fanArt,
                providerID: "wikimedia",
                attribution: Attribution(
                    title: artist,
                    creatorName: info.extmetadata?.Artist?.value.flatMap(plainText),
                    pageURL: info.descriptionurl.flatMap(URL.init(string:)),
                    sourceName: "Wikimedia Commons",
                    license: info.extmetadata?.LicenseShortName?.value
                ),
                matchScore: 0.8
            )
        }
    }

    /// The file URL without the query (Commons adds `utm_source`/`utm_campaign` tracking; files need none).
    static func withoutTracking(_ string: String) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        components.query = nil
        return components.url
    }

    /// Commons' "Artist" field is HTML (links, lists); the credit needs plain text.
    static func plainText(_ html: String) -> String? {
        let text = html
            .replacing(/<[^>]+>/, with: " ")
            .decodingHTMLEntities()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(80))
    }
}
