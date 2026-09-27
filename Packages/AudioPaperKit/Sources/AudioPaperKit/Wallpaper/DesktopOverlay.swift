import AppKit

/// Shows the art in a click-through window just above the desktop picture, on every Space, instead of
/// replacing the wallpaper. The person's own wallpaper is never touched — macOS's dynamic and Aerial
/// wallpapers keep moving underneath — so "restore" is exact and instant, and quitting AudioPaper simply
/// uncovers it. (Plash works the same way.) The window sits below desktop icons and ignores the mouse, so
/// the desktop's own clicks and menus still reach Finder.
@MainActor
public final class DesktopOverlay: WallpaperDisplay {
    public var fadeDuration: TimeInterval = 1.6
    private var windows: [UInt32: FadeWindow] = [:]

    public init() {}

    public var screens: [ScreenDescriptor] { NSScreen.descriptors }

    public func show(_ files: [UInt32: URL], animated: Bool) async {
        var shown: Set<UInt32> = []
        await withTaskGroup(of: Void.self) { group in
            for screen in NSScreen.screens {
                guard let id = screen.displayID, let file = files[id], let image = NSImage(contentsOf: file) else { continue }
                shown.insert(id)
                let window = windows[id] ?? FadeWindow(screen: screen, image: nil)
                windows[id] = window
                window.setFrame(screen.frame, display: false)
                group.addTask { await window.show(image, duration: animated ? self.fadeDuration : 0) }
            }
        }
        // Displays that were unplugged, or get no art this time.
        for (id, window) in windows where !shown.contains(id) {
            window.close()
            windows[id] = nil
        }
    }

    @discardableResult
    public func restoreOriginals() -> Bool {
        let closing = windows.values
        windows = [:]
        for window in closing {
            Task { await window.fadeOut(duration: fadeDuration) }
        }
        return true
    }
}

/// How AudioPaper puts art on the desktop.
public enum WallpaperMode: String, CaseIterable, Sendable, Identifiable {
    /// A window over the wallpaper; the wallpaper itself is left alone. The default.
    case overlay
    /// The real desktop picture is replaced, as before 0.1.8: the art also shows in Mission Control, but
    /// macOS's own dynamic wallpapers can't always be put back exactly.
    case replace

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overlay: "Over my wallpaper"
        case .replace: "As my wallpaper"
        }
    }
}

/// A display that can change how it shows art while running.
@MainActor
public protocol WallpaperModeSwitching: AnyObject {
    func modeChanged()
}

/// Routes to the overlay or to the real wallpaper, following the setting, and tidies up after the mode
/// that's no longer in use.
@MainActor
public final class WallpaperModeDisplay: WallpaperDisplay, WallpaperModeSwitching {
    private let overlay: DesktopOverlay
    private let replace: WallpaperService
    private let mode: @MainActor () -> WallpaperMode
    private var active: WallpaperMode

    public init(overlay: DesktopOverlay = DesktopOverlay(), replace: WallpaperService = WallpaperService(), mode: @escaping @MainActor () -> WallpaperMode) {
        self.overlay = overlay
        self.replace = replace
        self.mode = mode
        active = mode()
        // Upgrading from a version that replaced the wallpaper (or switching back): any desktop still showing
        // an AudioPaper image gets the person's own wallpaper back — now, or when that Space is next visited.
        if active == .overlay { replace.releaseDesktop() }
    }

    private var current: any WallpaperDisplay { active == .overlay ? overlay : replace }

    public var screens: [ScreenDescriptor] { current.screens }

    public func show(_ files: [UInt32: URL], animated: Bool) async {
        await current.show(files, animated: animated)
    }

    @discardableResult
    public func restoreOriginals() -> Bool {
        current.restoreOriginals()
    }

    public func modeChanged() {
        let new = mode()
        guard new != active else { return }
        if active == .overlay { overlay.restoreOriginals() } else { replace.releaseDesktop() }
        active = new
    }
}

extension NSScreen {
    /// Every display's pixel size, for rendering the art to fit.
    static var descriptors: [ScreenDescriptor] {
        screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            let scale = screen.backingScaleFactor
            return ScreenDescriptor(
                id: id,
                pixelWidth: Int((screen.frame.width * scale).rounded()),
                pixelHeight: Int((screen.frame.height * scale).rounded())
            )
        }
    }
}
