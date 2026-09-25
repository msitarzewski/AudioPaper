import Foundation

/// A track reported by a now-playing source.
public struct Track: Hashable, Sendable, Codable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String?
    /// Source-specific stable identifier, when the player provides one.
    public var persistentID: String?
    public var sourceID: String

    public init(
        title: String,
        artist: String,
        album: String,
        albumArtist: String? = nil,
        persistentID: String? = nil,
        sourceID: String
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.persistentID = persistentID
        self.sourceID = sourceID
    }

    /// The artist credited for the album as a whole (falls back to the track artist).
    public var primaryArtist: String {
        if let albumArtist, !albumArtist.isEmpty { return albumArtist }
        return artist
    }

    /// Identity of the album, used to skip redundant cover lookups. The artist part keeps accents,
    /// because they can distinguish artists ("ROSÉ" vs "Rose").
    public var albumKey: String {
        "\(MusicBrainz.identityKey(primaryArtist))|\(Normalizer.key(album))"
    }

    /// Identity of the song, used to key fan-art lookups.
    public var songKey: String {
        "\(MusicBrainz.identityKey(artist))|\(Normalizer.key(title))"
    }

    /// The individual artists in a collaboration credit — "LE SSERAFIM & j-hope", "A feat. B", "A, B & C",
    /// "A x B" — or an empty array for a single name. Some real names contain these separators
    /// ("Simon & Garfunkel"), so callers try the full credit first and use the parts only as a fallback.
    public var creditedArtists: [String] {
        let parts = artist
            // "x" only in lowercase, so the capital X in "Lil Nas X" isn't read as a separator.
            .split(separator: /\s*[,&]\s*|\s+(?i:feat\.?|ft\.?|featuring|with)\s+|\s+[x×]\s+/)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.count > 1 ? parts : []
    }

    /// Featured artists named in the title — "Move Bitch (feat. Ludacris, Mystikal & I-20)" — which Music
    /// leaves out of the artist field. Used when the credited artist has no art of their own.
    public var featuredArtists: [String] {
        guard let match = title.firstMatch(of: /[\(\[]\s*(?i:feat\.?|ft\.?|featuring|with)\s+([^\)\]]+)[\)\]]/) else { return [] }
        return String(match.output.1)
            .split(separator: /\s*[,&]\s*|\s+(?i:and)\s+/)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Artists to try, in order, when the full credit finds no art: the collaboration's credited artists,
    /// then the featured artists from the title.
    public var fallbackArtists: [String] {
        var seen = Set([MusicBrainz.identityKey(artist)])
        return (creditedArtists + featuredArtists).filter { seen.insert(MusicBrainz.identityKey($0)).inserted }
    }

    /// This track credited to one artist of a collaboration, for per-artist lookups.
    public func crediting(_ artist: String) -> Track {
        var track = self
        track.artist = artist
        track.albumArtist = nil
        return track
    }
}

public enum PlaybackEvent: Hashable, Sendable {
    case playing(Track)
    case paused(Track?)
    case stopped
}
