import Foundation

/// Artist backgrounds from fanart.tv: fan-made 1920×1080 and 4K wallpapers, keyed by MusicBrainz ID.
///
/// Terms honoured here: users are told where images come from (attribution links to fanart.tv), a
/// user's personal key is sent alongside the project key, and requests are the minimum needed
/// (one per artist per session).
public struct FanartTVSource: FanArtSource {
    static let memo = ArtistMemo()

    public let id = "fanarttv"
    public let displayName = "fanart.tv"

    private let http: any HTTPClient
    private let secrets: any SecretStore

    public init(http: any HTTPClient = URLSessionHTTPClient(), secrets: any SecretStore) {
        self.http = http
        self.secrets = secrets
    }

    public var isConfigured: Bool { secrets.value(for: .fanartTVProjectKey) != nil }

    struct Response: Decodable {
        struct Image: Decodable {
            var id: String
            var url: String
            var likes: String?
        }
        var name: String?
        var artistbackground: [Image]?
        var artist4kbackground: [Image]?
    }

    actor ArtistMemo {
        private var results: [String: [ArtworkCandidate]] = [:]
        func get(_ key: String) -> [ArtworkCandidate]? { results[key] }
        func set(_ key: String, _ value: [ArtworkCandidate]) { results[key] = value }
    }

    public func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate] {
        guard let projectKey = secrets.value(for: .fanartTVProjectKey) else { return [] }
        let artistKey = MusicBrainz.identityKey(track.artist)
        if let known = await Self.memo.get(artistKey) { return known }
        guard let mbid = try await MusicBrainz.artistID(for: track, http: http) else {
            await Self.memo.set(artistKey, [])
            return []
        }
        var query = ["api_key": projectKey]
        if let personal = secrets.value(for: .fanartTVClientKey) { query["client_key"] = personal }
        let found: [ArtworkCandidate]
        do {
            let response = try await http.json(Response.self, from: URLRequest(url: URL.api("https://webservice.fanart.tv/v3/music/\(mbid)", query)))
            found = Self.candidates(from: response, mbid: mbid)
        } catch HTTPError.status(404, _) {
            found = []  // fanart.tv has no page for this artist yet.
        }
        await Self.memo.set(artistKey, found)
        return Array(found.prefix(limit))
    }

    static func candidates(from response: Response, mbid: String) -> [ArtworkCandidate] {
        func mostLiked(_ images: [Response.Image]?) -> [Response.Image] {
            (images ?? []).sorted { Int($0.likes ?? "") ?? 0 > Int($1.likes ?? "") ?? 0 }
        }
        let artist = response.name ?? "Artist"
        let page = URL(string: "https://fanart.tv/artist/\(mbid)/")
        let sized = mostLiked(response.artist4kbackground).map { ($0, 3840, 2160, 1.0) }
            + mostLiked(response.artistbackground).map { ($0, 1920, 1080, 0.9) }
        return sized.compactMap { image, width, height, score in
            guard let url = URL(string: image.url) else { return nil }
            return ArtworkCandidate(
                imageURL: url,
                width: width, height: height,
                kind: .fanArt,
                providerID: "fanarttv",
                attribution: Attribution(title: "\(artist) background", pageURL: page, sourceName: "fanart.tv"),
                matchScore: score,
                isCurated: true
            )
        }
    }
}
