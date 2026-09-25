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

    /// Identity of the album, used to skip redundant cover lookups.
    public var albumKey: String {
        "\(Normalizer.key(primaryArtist))|\(Normalizer.key(album))"
    }

    /// Identity of the song, used to key fan-art lookups.
    public var songKey: String {
        "\(Normalizer.key(artist))|\(Normalizer.key(title))"
    }
}

public enum PlaybackEvent: Hashable, Sendable {
    case playing(Track)
    case paused(Track?)
    case stopped
}
