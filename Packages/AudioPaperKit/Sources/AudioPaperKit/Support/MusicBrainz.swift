import Foundation

/// Shared MusicBrainz access: one rate limiter for every caller (their etiquette is 1 request/second)
/// and track → artist MBID resolution, which ID-keyed art services (fanart.tv, TheAudioDB) need.
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

    struct RecordingSearch: Decodable {
        struct Recording: Decodable {
            struct Credit: Decodable {
                struct Artist: Decodable { var id: String }
                var name: String
                var artist: Artist
            }
            var score: Int?
            var artistCredit: [Credit]?

            enum CodingKeys: String, CodingKey {
                case score
                case artistCredit = "artist-credit"
            }
        }
        var recordings: [Recording]
    }

    /// Memo key that keeps accents: "ROSÉ" and "Rose" are different artists.
    static func identityKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The artist's MBID, or nil when there's no confident answer — a wrong artist is worse than none.
    ///
    /// The song is the strongest clue: a recording search for title + artist pins down which of several
    /// same-named artists is playing. A plain artist search is the fallback, and refuses ambiguity.
    static func artistID(for track: Track, http: any HTTPClient) async throws -> String? {
        let key = identityKey(track.artist)
        if let known = await artistIDs.get(key) { return known }
        var id: String?
        if !track.title.isEmpty {
            let title = Normalizer.searchTerm(track.title).replacingOccurrences(of: "\"", with: "")
            let artist = Normalizer.searchTerm(track.artist).replacingOccurrences(of: "\"", with: "")
            let url = URL.api("https://musicbrainz.org/ws/2/recording", [
                "query": "recording:\"\(title)\" AND artist:\"\(artist)\"", "fmt": "json", "limit": "10",
            ])
            try await limiter.wait()
            // A failed recording search isn't fatal; the artist search below still runs.
            if let response = try? await http.json(RecordingSearch.self, from: URLRequest(url: url)) {
                id = resolve(response, artist: track.artist)
            }
        }
        if id == nil {
            let term = Normalizer.searchTerm(track.artist).replacingOccurrences(of: "\"", with: "")
            let url = URL.api("https://musicbrainz.org/ws/2/artist", ["query": "artist:\"\(term)\"", "fmt": "json", "limit": "5"])
            try await limiter.wait()
            id = resolve(try await http.json(ArtistSearch.self, from: URLRequest(url: url)), name: track.artist)
        }
        await artistIDs.set(key, id)
        return id
    }

    /// The artist credited on confident recording matches, when they all agree on one artist.
    static func resolve(_ response: RecordingSearch, artist: String) -> String? {
        let ids = response.recordings.compactMap { recording -> String? in
            guard (recording.score ?? 0) >= 90,
                  let credit = recording.artistCredit?.first,
                  Normalizer.key(credit.name) == Normalizer.key(artist)
            else { return nil }
            return credit.artist.id
        }
        return Set(ids).count == 1 ? ids.first : nil
    }

    /// A unique exact-name artist. An accent-exact match wins over accent-folded ones, so "ROSÉ" isn't
    /// confused with "Rose"; several candidates still count as ambiguous.
    static func resolve(_ response: ArtistSearch, name: String) -> String? {
        let confident = response.artists.filter { ($0.score ?? 0) >= 90 }
        let exact = confident.filter { identityKey($0.name) == identityKey(name) }
        if exact.count == 1 { return exact[0].id }
        let folded = confident.filter { Normalizer.key($0.name) == Normalizer.key(name) }
        return exact.isEmpty && folded.count == 1 ? folded[0].id : nil
    }
}
