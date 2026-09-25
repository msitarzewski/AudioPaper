import Foundation

/// Album covers from the public iTunes Search API (no key). Artwork URLs are rewritten to 3000×3000.
public struct ITunesSearchProvider: AlbumArtworkProvider {
    public let id = "itunes"
    public let displayName = "Apple Music Catalog"

    private let http: any HTTPClient
    private let country: String

    public init(http: any HTTPClient = URLSessionHTTPClient(), country: String = Locale.current.region?.identifier ?? "US") {
        self.http = http
        self.country = country
    }

    struct Response: Decodable {
        struct Result: Decodable {
            var collectionName: String?
            var artistName: String?
            var artworkUrl100: String?
            var collectionViewUrl: String?
        }
        var results: [Result]
    }

    public func albumArtwork(for track: Track) async throws -> ArtworkCandidate? {
        let term = "\(Normalizer.searchTerm(track.primaryArtist)) \(Normalizer.searchTerm(track.album))"
        let url = URL.api("https://itunes.apple.com/search", [
            "term": term, "entity": "album", "limit": "10", "country": country,
        ])
        let response = try await http.json(Response.self, from: URLRequest(url: url))
        return Self.bestMatch(in: response, for: track)
    }

    static func bestMatch(in response: Response, for track: Track) -> ArtworkCandidate? {
        let scored = response.results.compactMap { result -> (Double, Response.Result)? in
            guard let name = result.collectionName, let artist = result.artistName, result.artworkUrl100 != nil else { return nil }
            let score = MatchScorer.albumScore(
                artist: track.primaryArtist, album: track.album,
                candidateArtist: artist, candidateAlbum: name
            )
            return (score, result)
        }
        guard let (score, best) = scored.max(by: { $0.0 < $1.0 }),
              let small = best.artworkUrl100,
              let imageURL = URL(string: small.replacingOccurrences(of: "100x100bb", with: "3000x3000bb"))
        else { return nil }
        return ArtworkCandidate(
            imageURL: imageURL,
            width: 3000, height: 3000,
            kind: .albumCover,
            providerID: "itunes",
            attribution: Attribution(
                title: best.collectionName,
                creatorName: best.artistName,
                pageURL: best.collectionViewUrl.flatMap(URL.init(string:)),
                sourceName: "Apple Music"
            ),
            matchScore: score
        )
    }
}
