import AppKit
import AudioPaperKit

// AppleScript support, defined in AudioPaper.sdef: read what's showing, pick an image from the strip, pause.
// Nothing here controls playback. macOS asks the person before any other app may send these (Automation).
// Apple events are handled on the main thread, so these run on the main actor.

extension AppDelegate {
    static let scriptKeys: Set<String> = [
        "scriptCurrentSong", "scriptImageCount", "scriptCurrentImage", "scriptCurrentCredit", "scriptCurrentSourcePage", "scriptImageCredits", "scriptImageSourcePages", "scriptArtistImageSourcePages",
        "scriptPaused",
    ]

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        Self.scriptKeys.contains(key)
    }

    private var coordinator: NowPlayingCoordinator { AppModel.shared.coordinator }

    @objc var scriptCurrentSong: String {
        guard let track = coordinator.track else { return "" }
        return "\(track.title) — \(track.artist)"
    }

    @objc var scriptImageCount: Int { coordinator.slides.count }

    @objc var scriptCurrentImage: Int {
        guard let showing = coordinator.showing, let index = coordinator.slides.firstIndex(of: showing) else { return 0 }
        return index + 1
    }

    @objc var scriptCurrentCredit: String {
        coordinator.showing.map { Self.credit($0.candidate) } ?? ""
    }

    @objc var scriptImageCredits: [String] { coordinator.slides.map { Self.credit($0.candidate) } }

    @objc var scriptImageSourcePages: [String] {
        coordinator.slides.map { $0.candidate.attribution.pageURL?.absoluteString ?? "" }
    }

    @objc var scriptArtistImageSourcePages: [String] {
        coordinator.pooled.compactMap { $0.candidate.attribution.pageURL?.absoluteString }
    }

    private static func credit(_ candidate: ArtworkCandidate) -> String {
        [candidate.creatorCredit, candidate.creditLine].compactMap { $0 }.joined(separator: " · ")
    }

    /// Only ever a web page (credit links are filtered to http and https when they're read).
    @objc var scriptCurrentSourcePage: String {
        coordinator.showing?.candidate.attribution.pageURL?.absoluteString ?? ""
    }

    @objc var scriptPaused: Bool {
        get { coordinator.isSuspended }
        set { coordinator.isSuspended = newValue }
    }
}

/// `show image 3`: puts the third image in the strip on the desktop.
@objc(ShowImageCommand)
final class ShowImageCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let position = directParameter as? Int
        let error: String? = MainActor.assumeIsolated {
            let slides = AppModel.shared.coordinator.slides
            guard let position, slides.indices.contains(position - 1) else {
                return slides.isEmpty ? "There are no images to show yet." : "Choose an image from 1 to \(slides.count)."
            }
            AppModel.shared.coordinator.show(slides[position - 1])
            return nil
        }
        if let error {
            scriptErrorNumber = errAENoSuchObject
            scriptErrorString = error
        }
        return nil
    }
}

/// `show image from page "https://commons.wikimedia.org/wiki/File:…"`: an exact image, found by where it came from.
@objc(ShowImageFromPageCommand)
final class ShowImageFromPageCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let page = (directParameter as? String).flatMap(URL.init(string:))
        let shown = MainActor.assumeIsolated { page.map { AppModel.shared.coordinator.show(page: $0) } ?? false }
        if !shown {
            scriptErrorNumber = errAENoSuchObject
            scriptErrorString = "No image found for this artist came from that page."
        }
        return nil
    }
}

/// `restore original wallpaper`: the same as Restore Original Wallpaper in the menu.
@objc(RestoreWallpaperCommand)
final class RestoreWallpaperCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated { AppModel.shared.coordinator.restoreOriginalWallpaper() }
        return nil
    }
}

/// `next image`: the same as Next Image in the Mini Player.
@objc(NextImageCommand)
final class NextImageCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated { AppModel.shared.coordinator.showNext() }
        return nil
    }
}
