import Foundation

/// Fan art from DeviantArt's API (OAuth2 client credentials). Keeps artist metadata so the UI can link to profiles.
public struct DeviantArtSource: FanArtSource {
    public let id = "deviantart"
    public let displayName = "DeviantArt"

    private let http: any HTTPClient
    private let secrets: any SecretStore
    private let tokens: TokenCache

    public init(http: any HTTPClient = URLSessionHTTPClient(), secrets: any SecretStore) {
        self.http = http
        self.secrets = secrets
        self.tokens = TokenCache()
    }

    public var isConfigured: Bool {
        secrets.value(for: .deviantArtClientID) != nil && secrets.value(for: .deviantArtClientSecret) != nil
    }

    struct TokenResponse: Decodable {
        var access_token: String
        var expires_in: Int
    }

    struct BrowseResponse: Decodable {
        struct Deviation: Decodable {
            struct Author: Decodable {
                var username: String
                var usericon: String?
            }
            struct Content: Decodable {
                var src: String
                var width: Int?
                var height: Int?
            }
            var deviationid: String
            var url: String?
            var title: String?
            var is_mature: Bool?
            var author: Author?
            var content: Content?
        }
        var results: [Deviation]
    }

    actor TokenCache {
        private var token: String?
        private var expiry = Date.distantPast

        func token(fetch: @Sendable () async throws -> TokenResponse) async throws -> String {
            if let token, expiry > .now { return token }
            let response = try await fetch()
            token = response.access_token
            expiry = .now.addingTimeInterval(TimeInterval(response.expires_in - 60))
            return response.access_token
        }
    }

    public func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate] {
        guard let clientID = secrets.value(for: .deviantArtClientID),
              let secret = secrets.value(for: .deviantArtClientSecret)
        else { return [] }
        let http = self.http
        let token = try await tokens.token {
            var request = URLRequest(url: URL(string: "https://www.deviantart.com/oauth2/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = [
                .init(name: "grant_type", value: "client_credentials"),
                .init(name: "client_id", value: clientID),
                .init(name: "client_secret", value: secret),
            ]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            return try await http.json(TokenResponse.self, from: request)
        }

        let artist = Normalizer.searchTerm(track.artist)
        let song = Normalizer.searchTerm(track.title)
        let perPage = String(min(limit, 24))
        // Song-specific search first; the artist tag widens the pool when the song has little art.
        let requests = [
            URL.api("https://www.deviantart.com/api/v1/oauth2/browse/popular", [
                "q": "\(artist) \(song)", "limit": perPage, "mature_content": "false", "timerange": "alltime",
            ]),
            URL.api("https://www.deviantart.com/api/v1/oauth2/browse/tags", [
                "tag": Self.tag(for: artist), "limit": perPage, "mature_content": "false",
            ]),
        ]

        var results: [ArtworkCandidate] = []
        for url in requests {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let response = try await http.json(BrowseResponse.self, from: request)
                results += Self.candidates(from: response, song: song)
            } catch {
                log.error("DeviantArt \(url.path(), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        var seen = Set<URL>()
        return results.filter { seen.insert($0.imageURL).inserted }
    }

    /// DeviantArt tags are single lowercase words: "Nine Inch Nails" → "nineinchnails".
    static func tag(for artist: String) -> String {
        Normalizer.key(artist).replacingOccurrences(of: " ", with: "")
    }

    static func candidates(from response: BrowseResponse, song: String) -> [ArtworkCandidate] {
        response.results.compactMap { deviation in
            guard deviation.is_mature != true,
                  let content = deviation.content, let imageURL = URL(string: content.src)
            else { return nil }
            let username = deviation.author?.username
            let titleScore = deviation.title.map { MatchScorer.similarity(song, $0) } ?? 0
            return ArtworkCandidate(
                imageURL: imageURL,
                width: content.width,
                height: content.height,
                kind: .fanArt,
                providerID: "deviantart",
                attribution: Attribution(
                    title: deviation.title,
                    creatorName: username,
                    creatorProfileURL: username.flatMap { URL(string: "https://www.deviantart.com/\($0)") },
                    creatorAvatarURL: deviation.author?.usericon.flatMap(URL.init(string:)),
                    pageURL: deviation.url.flatMap(URL.init(string:)),
                    sourceName: "DeviantArt"
                ),
                // Song-titled pieces rank ahead of general artist art.
                matchScore: 0.6 + 0.4 * titleScore
            )
        }
    }
}
