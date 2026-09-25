import Foundation

/// Shared MusicBrainz access: one rate limiter for every caller (their etiquette is 1 request/second)
/// and track → artist MBID resolution, which ID-keyed art services (fanart.tv, TheAudioDB) need.
public enum MusicBrainz {
    static let limiter = RateLimiter(interval: .milliseconds(1100))
    static let artistIDs = ArtistIDMemo()

    /// Remembers resolved artist IDs so repeat artists don't cost MusicBrainz lookups — in memory, and on disk
    /// once the app calls `rememberArtistIDs(in:)`. Unresolved names expire after a week so newly catalogued
    /// artists are found; resolved IDs are kept until the cache is cleared.
    actor ArtistIDMemo {
        struct Entry: Codable {
            var id: String?
            var date: Date
        }

        static let unresolvedLifetime: TimeInterval = 7 * 24 * 3600
        private var entries: [String: Entry] = [:]
        private var file: URL?

        func persist(at file: URL) {
            self.file = file
            if let data = try? Data(contentsOf: file),
               let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
                entries.merge(saved) { current, _ in current }
            }
        }

        func get(_ key: String) -> String?? {
            guard let entry = entries[key] else { return nil }
            if entry.id == nil, entry.date.timeIntervalSinceNow < -Self.unresolvedLifetime { return nil }
            return .some(entry.id)
        }

        func set(_ key: String, _ id: String?) {
            entries[key] = Entry(id: id, date: .now)
            guard let file else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
        }
    }

    struct ArtistRelations: Decodable {
        struct Relation: Decodable {
            struct Link: Decodable { var resource: String }
            var type: String
            var url: Link?
        }
        var relations: [Relation]?
    }

    static let wikidataIDs = WikidataMemo()

    actor WikidataMemo {
        private var ids: [String: String?] = [:]
        func get(_ mbid: String) -> String?? { ids[mbid] }
        func set(_ mbid: String, _ qid: String?) { ids[mbid] = .some(qid) }
    }

    /// The artist's Wikidata item (e.g. "Q60964"), from MusicBrainz's curated links — an exact identity,
    /// no name matching. Remembered per session.
    static func wikidataID(forArtist mbid: String, http: any HTTPClient) async throws -> String? {
        if let known = await wikidataIDs.get(mbid) { return known }
        try await limiter.wait()
        let url = URL.api("https://musicbrainz.org/ws/2/artist/\(mbid)", ["inc": "url-rels", "fmt": "json"])
        let response = try await http.json(ArtistRelations.self, from: URLRequest(url: url))
        let qid = wikidataID(in: response)
        await wikidataIDs.set(mbid, qid)
        return qid
    }

    static func wikidataID(in response: ArtistRelations) -> String? {
        response.relations?
            .first { $0.type == "wikidata" }?
            .url?.resource.split(separator: "/").last.map(String.init)
    }

    /// Keeps resolved artist IDs on disk (the app passes a file inside its cache, so Clear Cache removes it).
    public static func rememberArtistIDs(in file: URL) async {
        await artistIDs.persist(at: file)
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

    /// The artist credited on confident recording matches, when they all agree on one artist. Any credit on
    /// the recording counts, so a featured artist (j-hope on LE SSERAFIM's "SPAGHETTI") resolves too.
    static func resolve(_ response: RecordingSearch, artist: String) -> String? {
        let ids = response.recordings.compactMap { recording -> String? in
            guard (recording.score ?? 0) >= 90,
                  let credit = recording.artistCredit?.first(where: { Normalizer.key($0.name) == Normalizer.key(artist) })
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
