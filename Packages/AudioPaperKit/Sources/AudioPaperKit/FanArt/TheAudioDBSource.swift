import Foundation

/// Artist fan-art backgrounds from TheAudioDB. Works out of the box with the public free key (`123`,
/// 30 requests/minute); a personal key from Settings is used instead when present.
///
/// Images are artist-level (not per song), 1280×720, and made as backgrounds, so they're marked curated.
/// TheAudioDB's terms ask that the data source is credited and linked, which `Attribution` carries.
public struct TheAudioDBSource: FanArtSource {
    public static let freeKey = "123"
    /// 30 requests per minute on the free tier.
    static let limiter = RateLimiter(interval: .milliseconds(2100))
    /// One lookup per artist per session; songs by the same artist reuse it.
    static let memo = ArtistMemo()

    public let id = "theaudiodb"
    public let displayName = "TheAudioDB"
    public let isConfigured = true

    private let http: any HTTPClient
    private let secrets: any SecretStore

    public init(http: any HTTPClient = URLSessionHTTPClient(), secrets: any SecretStore) {
        self.http = http
        self.secrets = secrets
    }

    struct Response: Decodable {
        struct Artist: Decodable {
            var idArtist: String
            var strArtist: String
            var strArtistFanart: String?
            var strArtistFanart2: String?
            var strArtistFanart3: String?
            var strArtistFanart4: String?
        }
        var artists: [Artist]?
    }

    actor ArtistMemo {
        private var results: [String: [ArtworkCandidate]] = [:]
        func get(_ key: String) -> [ArtworkCandidate]? { results[key] }
        func set(_ key: String, _ value: [ArtworkCandidate]) { results[key] = value }
    }

    public func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate] {
        let artistKey = Normalizer.key(track.artist)
        if let known = await Self.memo.get(artistKey) { return known }
        let key = secrets.value(for: .theAudioDBAPIKey) ?? Self.freeKey
        let url = URL.api("https://www.theaudiodb.com/api/v1/json/\(key)/search.php", ["s": Normalizer.searchTerm(track.artist)])
        try await Self.limiter.wait()
        let response = try await http.json(Response.self, from: URLRequest(url: url))
        let found = Self.candidates(from: response, for: track)
        await Self.memo.set(artistKey, found)
        return found
    }

    static func candidates(from response: Response, for track: Track) -> [ArtworkCandidate] {
        // Free search returns the single best hit; only trust it when it's clearly the same artist.
        guard let artist = response.artists?.first,
              MatchScorer.similarity(track.artist, artist.strArtist) >= 0.9
        else { return [] }
        let images = [artist.strArtistFanart, artist.strArtistFanart2, artist.strArtistFanart3, artist.strArtistFanart4]
        return images.compactMap { $0.flatMap(URL.init(string:)) }.map { imageURL in
            ArtworkCandidate(
                imageURL: imageURL,
                width: 1280, height: 720,
                kind: .fanArt,
                providerID: "theaudiodb",
                attribution: Attribution(
                    title: "\(artist.strArtist) fan art",
                    pageURL: URL(string: "https://www.theaudiodb.com/artist/\(artist.idArtist)"),
                    sourceName: "TheAudioDB"
                ),
                matchScore: 0.8,
                isCurated: true
            )
        }
    }
}
