import Foundation

/// Artist fan-art backgrounds from TheAudioDB. Works out of the box with the public free key (`123`,
/// 30 requests/minute); a personal key from Settings is used instead when present.
///
/// Images are artist-level (not per song) backgrounds, 1280×720.
/// The artist is looked up by MusicBrainz ID; a name search is only a fallback and must match exactly,
/// accents included, because the free search returns a single hit ("Rose" for "ROSÉ").
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

    enum Match {
        /// Looked up by MusicBrainz ID: the identity is already certain.
        case byID
        /// Name search: the name must match exactly, accents included.
        case byName
    }

    actor ArtistMemo {
        private var results: [String: [ArtworkCandidate]] = [:]
        func get(_ key: String) -> [ArtworkCandidate]? { results[key] }
        func set(_ key: String, _ value: [ArtworkCandidate]) { results[key] = value }
    }

    public func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate] {
        let artistKey = MusicBrainz.identityKey(track.artist)
        if let known = await Self.memo.get(artistKey) { return known }
        let key = secrets.value(for: .theAudioDBAPIKey) ?? Self.freeKey
        let mbid = try? await MusicBrainz.artistID(for: track, http: http)
        let url = if let mbid {
            URL.api("https://www.theaudiodb.com/api/v1/json/\(key)/artist-mb.php", ["i": mbid])
        } else {
            URL.api("https://www.theaudiodb.com/api/v1/json/\(key)/search.php", ["s": Normalizer.searchTerm(track.artist)])
        }
        try await Self.limiter.wait()
        let response = try await http.json(Response.self, from: URLRequest(url: url))
        let found = Self.candidates(from: response, for: track, match: mbid == nil ? .byName : .byID)
        await Self.memo.set(artistKey, found)
        return found
    }

    static func candidates(from response: Response, for track: Track, match: Match) -> [ArtworkCandidate] {
        guard let artist = response.artists?.first else { return [] }
        if match == .byName, MusicBrainz.identityKey(artist.strArtist) != MusicBrainz.identityKey(Normalizer.searchTerm(track.artist)) {
            return []
        }
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
                matchScore: 0.8
            )
        }
    }
}
