import Foundation
import Observation

public enum ArtworkMode: String, CaseIterable, Sendable, Identifiable {
    case albumOnly
    case albumThenFanArt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .albumOnly: "Album cover"
        case .albumThenFanArt: "Album cover, then fan art"
        }
    }
}

/// What the desktop shows while a podcast episode plays.
public enum PodcastWallpaper: String, CaseIterable, Sendable, Identifiable {
    case myWallpaper
    case podcastCover

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .myWallpaper: "My wallpaper"
        case .podcastCover: "Podcast cover art"
        }
    }
}

/// User settings, persisted to UserDefaults and observable from SwiftUI.
@MainActor
@Observable
public final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    public var mode: ArtworkMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode") }
    }
    /// Seconds each fan-art image stays up before the next one fades in.
    public var rotationInterval: Double {
        didSet { defaults.set(rotationInterval, forKey: "rotationInterval") }
    }
    public var fanArtFraming: FanArtFraming {
        didSet { defaults.set(fanArtFraming.rawValue, forKey: "fanArtFraming") }
    }
    /// Most the artwork cache may use on disk; least-recently-used images are removed beyond it.
    public var cacheLimitBytes: Int {
        didSet { defaults.set(cacheLimitBytes, forKey: "cacheLimitBytes") }
    }
    public static let cacheLimitChoices = [250_000_000, 500_000_000, 1_000_000_000, 2_000_000_000]

    /// HIG: people, not the app, decide whether the menu bar extra is shown.
    public var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar") }
    }
    /// Mini Player window options, as in Music's MiniPlayer.
    public var miniPlayerFloatsOnTop: Bool {
        didSet { defaults.set(miniPlayerFloatsOnTop, forKey: "miniPlayerFloatsOnTop") }
    }
    /// Whether the Mini Player shows the large picture of the wallpaper. Off by default: the desktop already
    /// shows it, and the strip marks which image is up.
    public var miniPlayerShowsArtwork: Bool {
        didSet { defaults.set(miniPlayerShowsArtwork, forKey: "miniPlayerShowsArtwork") }
    }
    /// Whether the Mini Player was open, so it comes back after relaunch.
    public var miniPlayerOpen: Bool {
        didSet { defaults.set(miniPlayerOpen, forKey: "miniPlayerOpen") }
    }
    public var miniPlayerOnAllDesktops: Bool {
        didSet { defaults.set(miniPlayerOnAllDesktops, forKey: "miniPlayerOnAllDesktops") }
    }
    public var restoreWhenStopped: Bool {
        didSet { defaults.set(restoreWhenStopped, forKey: "restoreWhenStopped") }
    }
    public var podcastWallpaper: PodcastWallpaper {
        didSet { defaults.set(podcastWallpaper.rawValue, forKey: "podcastWallpaper") }
    }
    /// Stored as the players turned *off*, so newly added players start enabled.
    public var disabledSources: Set<String> {
        didSet { defaults.set(Array(disabledSources), forKey: "disabledSources") }
    }
    /// Stored as the sources turned *off*, so newly added sources start enabled.
    public var disabledFanArtSources: Set<String> {
        didSet { defaults.set(Array(disabledFanArtSources), forKey: "disabledFanArtSources") }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: "mode").flatMap(ArtworkMode.init(rawValue:)) ?? .albumThenFanArt
        rotationInterval = defaults.object(forKey: "rotationInterval") as? Double ?? 45
        fanArtFraming = defaults.string(forKey: "fanArtFraming").flatMap(FanArtFraming.init(rawValue:)) ?? .automatic
        restoreWhenStopped = defaults.bool(forKey: "restoreWhenStopped")
        showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        cacheLimitBytes = defaults.object(forKey: "cacheLimitBytes") as? Int ?? 500_000_000
        miniPlayerFloatsOnTop = defaults.bool(forKey: "miniPlayerFloatsOnTop")
        miniPlayerOnAllDesktops = defaults.bool(forKey: "miniPlayerOnAllDesktops")
        miniPlayerOpen = defaults.bool(forKey: "miniPlayerOpen")
        miniPlayerShowsArtwork = defaults.bool(forKey: "miniPlayerShowsArtwork")
        podcastWallpaper = defaults.string(forKey: "podcastWallpaper").flatMap(PodcastWallpaper.init(rawValue:)) ?? .myWallpaper
        disabledSources = Self.migratedDisabledSources(defaults)
        disabledFanArtSources = Set(defaults.stringArray(forKey: "disabledFanArtSources") ?? [])
    }

    /// Before 0.1.4 the enabled players were stored, and Apple Music was the only one: if it had been turned
    /// off, it stays off. Every other player, Spotify included, starts enabled.
    private static func migratedDisabledSources(_ defaults: UserDefaults) -> Set<String> {
        if let stored = defaults.stringArray(forKey: "disabledSources") { return Set(stored) }
        guard let enabled = defaults.stringArray(forKey: "enabledSources") else { return [] }
        let disabled: Set<String> = enabled.contains("apple-music") ? [] : ["apple-music"]
        defaults.set(Array(disabled), forKey: "disabledSources")
        defaults.removeObject(forKey: "enabledSources")
        return disabled
    }
}
