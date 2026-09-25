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
        enabledSources = Set(defaults.stringArray(forKey: "enabledSources") ?? ["apple-music"])
        disabledFanArtSources = Set(defaults.stringArray(forKey: "disabledFanArtSources") ?? [])
    }
}
