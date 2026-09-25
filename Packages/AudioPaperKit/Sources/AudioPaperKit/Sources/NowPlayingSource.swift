import Foundation

/// Plugin that reports what a music player is doing. Add a player by conforming and registering it.
public protocol NowPlayingSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// False when the player isn't installed; unavailable sources are hidden and never started.
    var isAvailable: Bool { get }
    /// Playback changes, starting with the current state when it can be determined.
    func events() -> AsyncStream<PlaybackEvent>
}

/// The set of compiled-in now-playing plugins, merged into a single event stream.
public struct SourceRegistry: Sendable {
    public var sources: [any NowPlayingSource]

    public init(sources: [any NowPlayingSource]) {
        self.sources = sources
    }

    public static let standard = SourceRegistry(sources: [AppleMusicSource()])

    public var available: [any NowPlayingSource] {
        sources.filter(\.isAvailable)
    }

    /// Events from every enabled, available source. When several players are active the most recent event wins.
    public func events(enabled: Set<String>) -> AsyncStream<PlaybackEvent> {
        let active = available.filter { enabled.contains($0.id) }
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
