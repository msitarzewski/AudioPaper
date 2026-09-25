import AppKit
import QuartzCore

/// Where rendered wallpapers go. The coordinator only talks to this, so tests can substitute a recorder.
@MainActor
public protocol WallpaperDisplay: AnyObject {
    var screens: [ScreenDescriptor] { get }
    /// Shows one file per screen, cross-fading from what is on screen now when `animated`.
    func show(_ files: [UInt32: URL], animated: Bool) async
    /// Puts back whatever wallpaper each screen had before AudioPaper changed it.
    func restoreOriginals()
}

/// Sets the real desktop picture through NSWorkspace, with a photo-slideshow style cross-fade.
///
/// The fade is drawn by a click-through window just above the desktop picture (below icons). Once the new
/// image is fully visible the real wallpaper is set underneath, and the window is removed — so the result
/// persists after quit and appears normally in Mission Control.
@MainActor
public final class WallpaperService: WallpaperDisplay {
    private static let originalsKey = "originalWallpapers"
    private let defaults: UserDefaults
    private let ownDirectory: URL
    public var fadeDuration: TimeInterval = 1.6

    /// Last files shown, re-applied when the user switches Spaces (macOS sets only the current Space).
    private var current: [UInt32: URL] = [:]
    private var spaceObserver: (any NSObjectProtocol)?

    public init(defaults: UserDefaults = .standard, ownDirectory: URL = WallpaperComposer.defaultOutputDirectory) {
        self.defaults = defaults
        self.ownDirectory = ownDirectory
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapplyCurrent() }
        }
    }

    public var screens: [ScreenDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            let scale = screen.backingScaleFactor
            return ScreenDescriptor(
                id: id,
                pixelWidth: Int((screen.frame.width * scale).rounded()),
                pixelHeight: Int((screen.frame.height * scale).rounded())
            )
        }
    }

    public func show(_ files: [UInt32: URL], animated: Bool) async {
        captureOriginals()
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

    public func restoreOriginals() {
        current = [:]
        guard let saved = defaults.dictionary(forKey: Self.originalsKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let path = saved[String(id)] else { continue }
            setDesktop(URL(filePath: path), on: screen)
        }
        defaults.removeObject(forKey: Self.originalsKey)
    }

    /// Records each screen's wallpaper the first time AudioPaper replaces it.
    private func captureOriginals() {
        var saved = defaults.dictionary(forKey: Self.originalsKey) as? [String: String] ?? [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID, saved[String(id)] == nil,
                  let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  !url.standardizedFileURL.path(percentEncoded: false).hasPrefix(ownDirectory.standardizedFileURL.path(percentEncoded: false))
            else { continue }
            saved[String(id)] = url.path(percentEncoded: false)
        }
        defaults.set(saved, forKey: Self.originalsKey)
    }

    private func reapplyCurrent() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID, let file = current[id],
                  NSWorkspace.shared.desktopImageURL(for: screen) != file
            else { continue }
            setDesktop(file, on: screen)
        }
    }

    private func setDesktop(_ file: URL, on screen: NSScreen) {
        do {
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        } catch {
            log.error("Setting wallpaper failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Borderless, click-through window sitting just above the desktop picture on every Space.
@MainActor
final class FadeWindow: NSWindow {
    init(screen: NSScreen, image: NSImage) {
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
        contentView = view
        setFrame(screen.frame, display: false)
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
