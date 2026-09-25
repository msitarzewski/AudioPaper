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
    public var enabledSources: Set<String> {
        didSet { defaults.set(Array(enabledSources), forKey: "enabledSources") }
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
        enabledSources = Set(defaults.stringArray(forKey: "enabledSources") ?? ["apple-music"])
        disabledFanArtSources = Set(defaults.stringArray(forKey: "disabledFanArtSources") ?? [])
    }
}
