import Foundation

/// Album covers from MusicBrainz release groups via the Cover Art Archive (no key; 1 request/s etiquette).
public struct CoverArtArchiveProvider: AlbumArtworkProvider {
    public let id = "coverartarchive"
    public let displayName = "MusicBrainz / Cover Art Archive"

    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    struct Response: Decodable {
        struct ReleaseGroup: Decodable {
            struct Credit: Decodable { var name: String }
            var id: String
            var title: String
            var artistCredit: [Credit]?

            enum CodingKeys: String, CodingKey {
                case id, title
                case artistCredit = "artist-credit"
            }
        }
        var releaseGroups: [ReleaseGroup]

        enum CodingKeys: String, CodingKey {
            case releaseGroups = "release-groups"
        }
    }

    public func albumArtwork(for track: Track) async throws -> ArtworkCandidate? {
        let album = Normalizer.searchTerm(track.album).replacingOccurrences(of: "\"", with: "")
        let artist = Normalizer.searchTerm(track.primaryArtist).replacingOccurrences(of: "\"", with: "")
        let url = URL.api("https://musicbrainz.org/ws/2/release-group", [
            "query": "releasegroup:\"\(album)\" AND artist:\"\(artist)\"", "fmt": "json", "limit": "5",
        ])
        try await MusicBrainz.limiter.wait()
        let response = try await http.json(Response.self, from: URLRequest(url: url))
        return Self.bestMatch(in: response, for: track)
    }

    static func bestMatch(in response: Response, for track: Track) -> ArtworkCandidate? {
        let scored = response.releaseGroups.map { group -> (Double, Response.ReleaseGroup) in
            let artist = group.artistCredit?.map(\.name).joined(separator: " ") ?? ""
            let score = MatchScorer.albumScore(
                artist: track.primaryArtist, album: track.album,
                candidateArtist: artist, candidateAlbum: group.title
            )
            return (score, group)
        }
        guard let (score, best) = scored.max(by: { $0.0 < $1.0 }), score > 0 else { return nil }
        return ArtworkCandidate(
            imageURL: URL(string: "https://coverartarchive.org/release-group/\(best.id)/front-1200")!,
            kind: .albumCover,
            providerID: "coverartarchive",
            attribution: Attribution(
                title: best.title,
                creatorName: best.artistCredit?.first?.name,
                pageURL: URL(string: "https://musicbrainz.org/release-group/\(best.id)"),
                sourceName: "MusicBrainz"
            ),
            matchScore: score
        )
    }
}
