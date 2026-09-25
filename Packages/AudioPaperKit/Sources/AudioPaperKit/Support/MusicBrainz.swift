import Foundation

/// Shared MusicBrainz access: one rate limiter for every caller (their etiquette is 1 request/second)
/// and artist-name → MBID resolution, which ID-keyed art services like fanart.tv need.
public enum MusicBrainz {
    static let limiter = RateLimiter(interval: .milliseconds(1100))
    static let artistIDs = ArtistIDMemo()

    actor ArtistIDMemo {
        private var ids: [String: String?] = [:]
        func get(_ key: String) -> String?? { ids[key] }
        func set(_ key: String, _ id: String?) { ids[key] = .some(id) }
    }

    struct ArtistSearch: Decodable {
        struct Artist: Decodable {
            var id: String
            var name: String
            var score: Int?
        }
        var artists: [Artist]
    }

    /// The MBID for `name`, or nil when there's no confident match. Several artists sharing the exact
    /// name (common for everyday words) count as ambiguous, since a wrong artist is worse than none.
    static func artistID(for name: String, http: any HTTPClient) async throws -> String? {
        let key = Normalizer.key(name)
        if let known = await artistIDs.get(key) { return known }
        let term = Normalizer.searchTerm(name).replacingOccurrences(of: "\"", with: "")
        let url = URL.api("https://musicbrainz.org/ws/2/artist", ["query": "artist:\"\(term)\"", "fmt": "json", "limit": "5"])
        try await limiter.wait()
        let response = try await http.json(ArtistSearch.self, from: URLRequest(url: url))
        let id = resolve(response, name: name)
        await artistIDs.set(key, id)
        return id
    }

    static func resolve(_ response: ArtistSearch, name: String) -> String? {
        let exact = response.artists.filter { Normalizer.key($0.name) == Normalizer.key(name) && ($0.score ?? 0) >= 90 }
        return exact.count == 1 ? exact[0].id : nil
    }
}
