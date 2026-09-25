import AppKit
import Foundation

/// Apple Music via the `com.apple.Music.playerInfo` distributed notification Music posts on every change.
///
/// The notification needs no permission. The state at launch is read once over Apple Events, which asks
/// the user for Automation access; if declined, the source simply waits for the next change.
public struct AppleMusicSource: NowPlayingSource {
    public static let bundleID = "com.apple.Music"
    static let notification = Notification.Name("com.apple.Music.playerInfo")

    public let id = "apple-music"
    public let displayName = "Apple Music"

    public init() {}

    public var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil
    }

    public func events() -> AsyncStream<PlaybackEvent> {
        AsyncStream { continuation in
            let center = DistributedNotificationCenter.default()
            let observer = ObserverToken(center.addObserver(forName: Self.notification, object: nil, queue: nil) { note in
                // Any process can post this notification name. Music always posts it while running, so one
                // arriving while Music isn't running is someone else's, and is ignored.
                guard Self.isMusicRunning else { return }
                if let event = Self.event(from: note.userInfo ?? [:]) {
                    continuation.yield(event)
                }
            })
            // NSAppleScript is main-thread only; the query is a one-off at startup.
            let initial = Task { @MainActor in
                if let event = Self.currentState() { continuation.yield(event) }
            }
            continuation.onTermination = { _ in
                initial.cancel()
                center.removeObserver(observer.value)
            }
        }
    }

    /// Maps the notification's user info to an event. Radio streams without an artist are ignored.
    static func event(from info: [AnyHashable: Any]) -> PlaybackEvent? {
        let state = info["Player State"] as? String
        let track = track(from: info)
        switch state {
        case "Playing":
            return track.map(PlaybackEvent.playing)
        case "Paused":
            return .paused(track)
        case "Stopped":
            return .stopped
        default:
            return nil
        }
    }

    static var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Longest title, artist or album kept; real ones are far shorter, and every field ends up in search
    /// queries and on screen.
    static let maxFieldLength = 256

    static func track(from info: [AnyHashable: Any]) -> Track? {
        func field(_ key: String) -> String? {
            (info[key] as? String).map { String($0.prefix(maxFieldLength)) }
        }
        guard let title = field("Name"), !title.isEmpty,
              let artist = field("Artist"), !artist.isEmpty
        else { return nil }
        let persistentID: String? = switch info["PersistentID"] {
        case let number as NSNumber: String(UInt64(bitPattern: number.int64Value), radix: 16, uppercase: true)
        case let string as String: string
        default: nil
        }
        return Track(
            title: title,
            artist: artist,
            album: field("Album") ?? "",
            albumArtist: field("Album Artist"),
            persistentID: persistentID,
            sourceID: "apple-music"
        )
    }

    /// Asks Music what's playing right now. Only runs if Music is already open, so it never launches it.
    static func currentState() -> PlaybackEvent? {
        guard isMusicRunning else { return nil }
        let source = """
        tell application id "com.apple.Music"
            if player state is not playing then return {}
            set t to current track
            return {name of t, artist of t, album of t, album artist of t, persistent ID of t}
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), result.numberOfItems == 5 else {
            if let error { log.info("Music state query unavailable: \(error, privacy: .public)") }
            return nil
        }
        let field = { (index: Int) in result.atIndex(index)?.stringValue ?? "" }
        let info: [AnyHashable: Any] = [
            "Player State": "Playing", "Name": field(1), "Artist": field(2),
            "Album": field(3), "Album Artist": field(4), "PersistentID": field(5),
        ]
        return event(from: info)
    }
}

/// NotificationCenter observer tokens are safe to remove from any thread.
struct ObserverToken: @unchecked Sendable {
    let value: any NSObjectProtocol
    init(_ value: any NSObjectProtocol) { self.value = value }
}

/// Last-resort cover: the artwork Music itself has for the current track (typically 600–800 px).
/// Used when neither online catalog knows the release. Only answers for the track that is playing now.
public struct AppleMusicArtworkProvider: AlbumArtworkProvider {
    public let id = "apple-music-local"
    public let displayName = "Music app artwork"

    private let directory: URL

    public init(directory: URL = URL.cachesDirectory.appending(path: "AudioPaper/player-artwork", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    public func albumArtwork(for track: Track) async throws -> ArtworkCandidate? {
        guard track.sourceID == "apple-music",
              let (data, isPNG) = await MainActor.run(body: { Self.currentArtwork(matching: track) })
        else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(ArtworkCache.hash(track.albumKey)).\(isPNG ? "png" : "jpg")")
        try data.write(to: file, options: .atomic)
        return ArtworkCandidate(
            imageURL: file,
            kind: .albumCover,
            providerID: id,
            attribution: Attribution(title: track.album, creatorName: track.primaryArtist, sourceName: "Music"),
            matchScore: 1,
            isLocal: true
        )
    }

    @MainActor
    static func currentArtwork(matching track: Track) -> (Data, isPNG: Bool)? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: AppleMusicSource.bundleID).isEmpty else { return nil }
        let source = """
        tell application id "com.apple.Music"
            set t to current track
            if (count of artworks of t) is 0 then return {}
            return {name of t, artist of t, raw data of artwork 1 of t}
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), result.numberOfItems == 3,
              result.atIndex(1)?.stringValue == track.title, result.atIndex(2)?.stringValue == track.artist,
              let data = result.atIndex(3)?.data, !data.isEmpty
        else { return nil }
        return (data, data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
