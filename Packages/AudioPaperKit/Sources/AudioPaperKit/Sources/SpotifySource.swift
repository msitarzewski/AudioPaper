import AppKit
import Foundation

/// Spotify via the `com.spotify.client.PlaybackStateChanged` distributed notification it posts on every
/// change, on free and paid accounts alike.
///
/// Items are told apart by their ID: `spotify:track:` is a song and `spotify:episode:` a podcast episode.
/// Everything else is ignored — ads (`spotify:ad:`, which Spotify doesn't announce anyway, but which the
/// startup query can return) and any kind Spotify adds later. The state at launch is read once over Apple
/// Events, like Music's.
public struct SpotifySource: NowPlayingSource {
    public static let bundleID = "com.spotify.client"
    static let notification = Notification.Name("com.spotify.client.PlaybackStateChanged")

    public let id = "spotify"
    public let displayName = "Spotify"
    public var playsPodcasts: Bool { true }
    public var appBundleID: String? { Self.bundleID }

    public init() {}

    public var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil
    }

    public func events() -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            let center = DistributedNotificationCenter.default()
            let observer = ObserverToken(center.addObserver(forName: Self.notification, object: nil, queue: nil) { note in
                // Any process can post this name; one arriving while Spotify isn't running is someone else's.
                guard Self.isRunning else { return }
                if let event = Self.event(from: note.userInfo ?? [:]) {
                    continuation.yield(event)
                }
            })
            let initial = Task { @MainActor in
                if let event = Self.currentState() { continuation.yield(event) }
            }
            continuation.onTermination = { _ in
                initial.cancel()
                center.removeObserver(observer.value)
            }
        }
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Maps the notification's user info to an event. Items that aren't songs or episodes are ignored
    /// entirely, pauses included, so an ad never stops the slideshow.
    static func event(from info: [AnyHashable: Any]) -> PlaybackEvent? {
        switch info["Player State"] as? String {
        case "Playing":
            return track(from: info).map(PlaybackEvent.playing)
        case "Paused":
            return track(from: info).map { .paused($0) }
        case "Stopped":
            return .stopped
        default:
            return nil
        }
    }

    static func track(from info: [AnyHashable: Any]) -> Track? {
        let field = { PlayerInfo.string(info, $0) }
        guard let id = field("Track ID"), let kind = kind(of: id),
              let title = field("Name"), !title.isEmpty
        else { return nil }
        switch kind {
        case .song:
            guard let artist = field("Artist"), !artist.isEmpty else { return nil }
            return Track(
                title: title, artist: artist, album: field("Album") ?? "",
                albumArtist: field("Album Artist"), persistentID: id, sourceID: "spotify"
            )
        case .podcastEpisode:
            // Spotify leaves the artist empty for episodes and puts the show in the album field.
            guard let show = field("Album"), !show.isEmpty else { return nil }
            return Track(title: title, artist: show, album: show, persistentID: id, sourceID: "spotify", kind: .podcastEpisode)
        }
    }

    /// What a Spotify ID names, or nil for anything that isn't a song or episode with a well-formed ID.
    static func kind(of id: String) -> MediaKind? {
        if id.wholeMatch(of: /spotify:track:[0-9A-Za-z]{1,64}/) != nil { return .song }
        if id.wholeMatch(of: /spotify:episode:[0-9A-Za-z]{1,64}/) != nil { return .podcastEpisode }
        return nil
    }

    /// The item's page on Spotify's web player, for the credit link.
    static func pageURL(for id: String) -> URL? {
        let parts = id.split(separator: ":")
        guard parts.count == 3, kind(of: id) != nil else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }

    /// Asks Spotify what's playing right now. Only runs if Spotify is already open, so it never launches it.
    @MainActor
    static func currentState() -> PlaybackEvent? {
        guard isRunning else { return nil }
        let source = """
        tell application id "com.spotify.client"
            if player state is not playing then return {}
            set t to current track
            return {name of t, artist of t, album of t, album artist of t, id of t}
        end tell
        """
        guard let values = PlayerInfo.query(source, count: 5, player: "Spotify") else { return nil }
        return event(from: [
            "Player State": "Playing", "Name": values[0], "Artist": values[1],
            "Album": values[2], "Album Artist": values[3], "Track ID": values[4],
        ])
    }
}

/// The cover Spotify itself shows for the item playing now (640 px, from Spotify's image server): the only
/// source for podcast covers, and a last resort for songs neither online catalog knows.
public struct SpotifyArtworkProvider: AlbumArtworkProvider {
    public let id = "spotify-artwork"
    public let displayName = "Spotify artwork"
    public var handlesPodcasts: Bool { true }

    /// Spotify's image server; a cover link anywhere else is ignored.
    static let imageHost = "i.scdn.co"

    public init() {}

    public func albumArtwork(for track: Track) async throws -> ArtworkCandidate? {
        guard track.sourceID == "spotify", let itemID = track.persistentID,
              let imageURL = await MainActor.run(body: { Self.currentArtworkURL(matching: itemID) })
        else { return nil }
        return Self.candidate(for: track, itemID: itemID, imageURL: imageURL)
    }

    static func candidate(for track: Track, itemID: String, imageURL: URL) -> ArtworkCandidate? {
        guard imageURL.scheme == "https", imageURL.host() == imageHost else { return nil }
        return ArtworkCandidate(
            imageURL: imageURL,
            kind: track.isPodcast ? .podcastCover : .albumCover,
            providerID: "spotify-artwork",
            attribution: Attribution(
                title: track.album,
                creatorName: track.isPodcast ? nil : track.primaryArtist,
                pageURL: SpotifySource.pageURL(for: itemID),
                sourceName: "Spotify"
            ),
            matchScore: 1
        )
    }

    /// The cover link for the current item, but only while that item is still the one asked about.
    @MainActor
    static func currentArtworkURL(matching itemID: String) -> URL? {
        guard SpotifySource.isRunning else { return nil }
        let source = """
        tell application id "com.spotify.client"
            set t to current track
            return {id of t, artwork url of t}
        end tell
        """
        guard let values = PlayerInfo.query(source, count: 2, player: "Spotify"), values[0] == itemID else { return nil }
        return URL(string: values[1])
    }
}
