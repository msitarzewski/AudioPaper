import Foundation

/// Plugin that reports what a music player is doing. Add a player by conforming and registering it.
public protocol NowPlayingSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// False when the player isn't installed; unavailable sources are hidden and never started.
    var isAvailable: Bool { get }
    /// Playback changes, starting with the current state when it can be determined.
    func events() -> AsyncStream<PlaybackEvent>
    /// Whether this player can report podcast episodes (it decides whether Settings shows the podcast option).
    var playsPodcasts: Bool { get }
    /// The player app's bundle ID, so the interface can show its icon; nil when there's no app to show.
    var appBundleID: String? { get }
    /// Brings the player forward showing this track. False when it can't.
    @MainActor func open(_ track: Track) -> Bool
}

extension NowPlayingSource {
    public var playsPodcasts: Bool { false }
    public var appBundleID: String? { nil }
    @MainActor public func open(_ track: Track) -> Bool { false }
}

/// Reads fields from a player's change notification. Any process can post one, so values are length-capped.
enum PlayerInfo {
    /// Longest title, artist or album kept; real ones are far shorter, and every field ends up in search
    /// queries and on screen.
    static let maxFieldLength = 256

    static func string(_ info: [AnyHashable: Any], _ key: String) -> String? {
        (info[key] as? String).map { String($0.prefix(maxFieldLength)) }
    }

    /// Runs a one-off AppleScript that returns a list of strings, or nil (not running, not allowed, or a
    /// different shape). Main-thread only, like NSAppleScript itself.
    @MainActor
    static func query(_ source: String, count: Int, player: String) -> [String]? {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), result.numberOfItems == count else {
            if let error { log.info("\(player, privacy: .public) query unavailable: \(error, privacy: .public)") }
            return nil
        }
        return (1...count).map { result.atIndex($0)?.stringValue ?? "" }
    }
}

/// The set of compiled-in now-playing plugins, merged into a single event stream.
public struct SourceRegistry: Sendable {
    public var sources: [any NowPlayingSource]

    public init(sources: [any NowPlayingSource]) {
        self.sources = sources
    }

    public static let standard = SourceRegistry(sources: [AppleMusicSource(), SpotifySource()])

    public var available: [any NowPlayingSource] {
        sources.filter(\.isAvailable)
    }

    /// Events from every available source that isn't turned off. When several players are active the most
    /// recent event wins.
    public func events(disabled: Set<String>) -> AsyncStream<PlaybackEvent> {
        let active = available.filter { !disabled.contains($0.id) }
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    for source in active {
                        group.addTask {
                            for await event in source.events() {
                                continuation.yield(event)
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
