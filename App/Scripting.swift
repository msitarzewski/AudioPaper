import AppKit
import AudioPaperKit

// AppleScript support, defined in AudioPaper.sdef: read what's showing, pick an image from the strip, pause.
// Nothing here controls playback. macOS asks the person before any other app may send these (Automation).
// Apple events are handled on the main thread, so these run on the main actor.

extension AppDelegate {
    static let scriptKeys: Set<String> = [
        "scriptCurrentSong", "scriptImageCount", "scriptCurrentImage", "scriptCurrentCredit", "scriptPaused",
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
        guard let showing = coordinator.showing?.candidate else { return "" }
        return [showing.creatorCredit, showing.creditLine].compactMap { $0 }.joined(separator: " · ")
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

/// `next image`: the same as Next Image in the Mini Player.
@objc(NextImageCommand)
final class NextImageCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated { AppModel.shared.coordinator.showNext() }
        return nil
    }
}
