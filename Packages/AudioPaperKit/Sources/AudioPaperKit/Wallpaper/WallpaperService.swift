import AppKit
import QuartzCore

/// Where rendered wallpapers go. The coordinator only talks to this, so tests can substitute a recorder.
@MainActor
public protocol WallpaperDisplay: AnyObject {
    var screens: [ScreenDescriptor] { get }
    /// Shows one file per screen, cross-fading from what is on screen now when `animated`.
    func show(_ files: [UInt32: URL], animated: Bool) async
    /// Puts back whatever wallpaper each screen had before AudioPaper changed it. False when a screen's
    /// wallpaper couldn't be put back (it was one AudioPaper can't set again), so people can be told.
    @discardableResult
    func restoreOriginals() -> Bool
}

/// Sets the real desktop picture through NSWorkspace, with a photo-slideshow style cross-fade.
///
/// The fade is drawn by a click-through window just above the desktop picture (below icons). Once the new
/// image is fully visible the real wallpaper is set underneath, and the window is removed — so the result
/// persists after quit and appears normally in Mission Control.
@MainActor
public final class WallpaperService: WallpaperDisplay {
    private static let originalsKey = "originalWallpapers"
    /// Each screen's original scaling options (fill, fit, …), kept so a restored picture looks as it did.
    private static let optionsKey = "originalWallpaperOptions"
    /// Which covering session recorded each Space's wallpaper. A session starts when AudioPaper first covers
    /// the desktop after it was clear; a Space's own record is trusted only from the current one, because with
    /// "Show on all Spaces" AudioPaper's image reaches every Space at once and older records go stale.
    private static let sessionsKey = "originalWallpaperSessions"
    private static let sessionKey = "originalWallpaperSession"
    private let defaults: UserDefaults
    private let ownDirectory: URL
    public var fadeDuration: TimeInterval = 1.6

    /// Last files shown, re-applied when the user switches Spaces (macOS sets only the current Space).
    private var current: [UInt32: URL] = [:]
    /// Set by a restore: Spaces not visible then still show AudioPaper's image, so each is put back when
    /// it's next visited (macOS can only change the Space on screen).
    private var restoringOtherSpaces = false
    private var spaceObserver: (any NSObjectProtocol)?

    public init(defaults: UserDefaults = .standard, ownDirectory: URL = WallpaperComposer.defaultOutputDirectory) {
        self.defaults = defaults
        self.ownDirectory = ownDirectory
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        }
    }

    public var screens: [ScreenDescriptor] { NSScreen.descriptors }

    public func show(_ files: [UInt32: URL], animated: Bool) async {
        if current.isEmpty { defaults.set(defaults.integer(forKey: Self.sessionKey) + 1, forKey: Self.sessionKey) }
        captureOriginals()
        restoringOtherSpaces = false
        current = files
        let targets = NSScreen.screens.compactMap { screen -> (NSScreen, URL)? in
            guard let id = screen.displayID, let file = files[id] else { return nil }
            return (screen, file)
        }
        guard animated else {
            for (screen, file) in targets { setDesktop(file, on: screen) }
            return
        }
        let windows = targets.compactMap { screen, file -> FadeWindow? in
            guard let image = NSImage(contentsOf: file) else { return nil }
            return FadeWindow(screen: screen, image: image)
        }
        await withTaskGroup(of: Void.self) { group in
            for window in windows {
                group.addTask { await window.fadeIn(duration: self.fadeDuration) }
            }
        }
        for (screen, file) in targets { setDesktop(file, on: screen) }
        // Give the Dock a moment to draw the new desktop before uncovering it.
        try? await Task.sleep(for: .milliseconds(700))
        windows.forEach { $0.orderOut(nil) }
    }

    /// Puts back the wallpaper of the Space each display is showing now; other Spaces follow when visited.
    @discardableResult
    public func restoreOriginals() -> Bool {
        current = [:]
        restoringOtherSpaces = true
        return restore(NSScreen.screens)
    }

    /// Hands the desktop back without replacing anything the person set themselves: only displays showing an
    /// AudioPaper image now get their own wallpaper back, and other Spaces follow when visited.
    public func releaseDesktop() {
        current = [:]
        restoringOtherSpaces = true
        let ours = NSScreen.screens.filter { NSWorkspace.shared.desktopImageURL(for: $0).map(isOwn) ?? false }
        if !ours.isEmpty { restore(ours) }
    }

    @discardableResult
    private func restore(_ screens: [NSScreen]) -> Bool {
        let saved = defaults.dictionary(forKey: Self.originalsKey) as? [String: String] ?? [:]
        let options = defaults.dictionary(forKey: Self.optionsKey) as? [String: [String: Any]] ?? [:]
        let sessions = defaults.dictionary(forKey: Self.sessionsKey) as? [String: Int] ?? [:]
        let session = defaults.integer(forKey: Self.sessionKey)
        var restoredAll = true
        for screen in screens {
            guard let keys = Self.keys(for: screen) else { continue }
            let exact = keys.exact.flatMap { sessions[$0] == session ? $0 : nil }
            guard let key = Self.originalKey(in: saved, exact: exact, display: keys.display, legacy: keys.legacy),
                  let path = saved[key]
            else {
                // Nothing recorded for this display, yet it shows AudioPaper's image: macOS's default wallpaper
                // beats leaving ours up.
                if NSWorkspace.shared.desktopImageURL(for: screen).map(isOwn) ?? false,
                   FileManager.default.fileExists(atPath: Self.systemDefault.path(percentEncoded: false)) {
                    log.info("No original recorded for \(keys.display, privacy: .public); using macOS's default wallpaper")
                    setDesktop(Self.systemDefault, on: screen, options: [:])
                }
                continue
            }
            // Empty: the wallpaper was one AudioPaper recognised but can't set again.
            guard !path.isEmpty else { restoredAll = false; continue }
            let url = URL(filePath: path)
            // macOS's own wallpapers (.madesktop) keep their own framing; pictures get the options they had.
            let chosen = url.pathExtension == "madesktop" ? [:] : Self.desktopOptions(from: options[key] ?? [:])
            log.info("Restoring \(key, privacy: .public): \(url.lastPathComponent, privacy: .public)")
            if !setDesktop(url, on: screen, options: chosen) { restoredAll = false }
        }
        // Kept, not cleared: a wallpaper is recorded afresh whenever AudioPaper covers it, and until then the
        // record is still the one to go back to.
        return restoredAll
    }

    /// macOS's own default wallpaper, used when there's no record of what a display showed before.
    static let systemDefault = URL(filePath: "/System/Library/CoreServices/DefaultDesktop.heic")

    /// Where a screen's wallpaper is recorded: per display and Space when the Space is known, and per
    /// display (the latest seen) as the fallback. `legacy` is the key versions before 0.1.8 used.
    static func keys(for screen: NSScreen) -> (exact: String?, display: String, legacy: String)? {
        guard let id = screen.displayID else { return nil }
        let display = Spaces.displayUUID(id) ?? String(id)
        let exact = Spaces.currentSpace(onDisplay: display).map { "\(display)|\($0)" }
        return (exact, display, String(id))
    }

    /// The best record to restore from: this display and Space, else the latest for the display.
    nonisolated static func originalKey(in saved: [String: String], exact: String?, display: String, legacy: String) -> String? {
        [exact, display, legacy].compactMap { $0 }.first { saved[$0] != nil }
    }

    private func spaceChanged() {
        if !current.isEmpty {
            // Music is on: record this Space's own wallpaper before AudioPaper's image covers it.
            captureOriginals()
            reapplyCurrent()
        } else if restoringOtherSpaces {
            // The music stopped earlier: a Space still showing AudioPaper's image gets its own back.
            let ours = NSScreen.screens.filter { screen in
                NSWorkspace.shared.desktopImageURL(for: screen).map(isOwn) ?? false
            }
            if !ours.isEmpty { restore(ours) }
        }
    }

    private func isOwn(_ url: URL) -> Bool {
        url.standardizedFileURL.path(percentEncoded: false).hasPrefix(ownDirectory.standardizedFileURL.path(percentEncoded: false))
    }

    /// Records each screen's own wallpaper whenever AudioPaper is about to cover it — so a wallpaper chosen
    /// between songs is the one that comes back. AudioPaper's own images are never recorded.
    private func captureOriginals() {
        var saved = defaults.dictionary(forKey: Self.originalsKey) as? [String: String] ?? [:]
        var options = defaults.dictionary(forKey: Self.optionsKey) as? [String: [String: Any]] ?? [:]
        var sessions = defaults.dictionary(forKey: Self.sessionsKey) as? [String: Int] ?? [:]
        let session = defaults.integer(forKey: Self.sessionKey)
        for screen in NSScreen.screens {
            guard let keys = Self.keys(for: screen),
                  let url = NSWorkspace.shared.desktopImageURL(for: screen), !isOwn(url)
            else { continue }
            let restorable = Self.restorableWallpaper(for: url)
            if restorable == nil { log.info("Original wallpaper can't be restored: \(url.path(percentEncoded: false), privacy: .public)") }
            let value = restorable?.path(percentEncoded: false) ?? ""
            let chosen = Self.storableOptions(NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
            log.info("Recorded original wallpaper for \(keys.exact ?? keys.display, privacy: .public): \(url.lastPathComponent, privacy: .public)")
            for key in [keys.exact, keys.display].compactMap({ $0 }) {
                saved[key] = value
                options[key] = chosen
                sessions[key] = session
            }
        }
        defaults.set(saved, forKey: Self.originalsKey)
        defaults.set(options, forKey: Self.optionsKey)
        defaults.set(sessions, forKey: Self.sessionsKey)
    }

    /// What to put back for a wallpaper macOS reports at `url`: the file itself when it exists. macOS's own
    /// wallpapers (Catalina, Big Sur, the newer landscapes) are reported as a file in
    /// `com.apple.mobileAssetDesktop` that doesn't exist; those map back to their descriptor in Desktop
    /// Pictures, which can be set again, dynamic behaviour included. Nil when there's nothing to put back.
    nonisolated static func restorableWallpaper(
        for url: URL,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        systemPictures: [URL] = [URL(filePath: "/System/Library/Desktop Pictures"), URL(filePath: "/Library/Desktop Pictures")]
    ) -> URL? {
        if fileExists(url.path(percentEncoded: false)) { return url }
        let name = url.deletingPathExtension().lastPathComponent
        return systemPictures
            .map { $0.appending(path: name + ".madesktop") }
            .first { fileExists($0.path(percentEncoded: false)) }
    }

    /// The scaling options as plain values UserDefaults can store (the fill colour, an NSColor, is left out).
    nonisolated static func storableOptions(_ options: [NSWorkspace.DesktopImageOptionKey: Any]) -> [String: Any] {
        var stored: [String: Any] = [:]
        if let scaling = options[.imageScaling] as? NSNumber { stored["imageScaling"] = scaling }
        if let clipping = options[.allowClipping] as? NSNumber { stored["allowClipping"] = clipping }
        return stored
    }

    nonisolated static func desktopOptions(from stored: [String: Any]) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = stored["imageScaling"] as? NSNumber { options[.imageScaling] = scaling }
        if let clipping = stored["allowClipping"] as? NSNumber { options[.allowClipping] = clipping }
        return options
    }

    private func reapplyCurrent() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let file = current[id],
                  NSWorkspace.shared.desktopImageURL(for: screen) != file
            else { continue }
            setDesktop(file, on: screen)
        }
    }

    /// AudioPaper's own renders fill the screen; restored wallpapers pass the options they had.
    @discardableResult
    private func setDesktop(_ file: URL, on screen: NSScreen, options: [NSWorkspace.DesktopImageOptionKey: Any]? = nil) -> Bool {
        do {
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: options ?? [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
            return true
        } catch {
            log.error("Setting wallpaper failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// Borderless, click-through window sitting just above the desktop picture on every Space.
@MainActor
final class FadeWindow: NSWindow {
    init(screen: NSScreen, image: NSImage?) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        alphaValue = 0

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resizeAspectFill
        view.layer?.backgroundColor = NSColor.black.cgColor
        contentView = view
        setFrame(screen.frame, display: false)
    }

    /// Shows `image`: fading the window in the first time, and cross-fading from the current image after.
    func show(_ image: NSImage, duration: TimeInterval) async {
        guard let layer = contentView?.layer else { return }
        if !isVisible || alphaValue == 0 {
            layer.contents = image
            await fadeIn(duration: duration)
            return
        }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "contents")
        layer.contents = image
        try? await Task.sleep(for: .seconds(duration))
    }

    func fadeOut(duration: TimeInterval) async {
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        }
        close()
    }

    func fadeIn(duration: TimeInterval) async {
        orderFrontRegardless()
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 1
        }
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
