import AppKit
import AudioPaperKit
import SwiftUI
import WidgetKit

enum MiniPlayerScene {
    static let id = "mini-player"
}

/// App-wide state shared by the scenes and the app delegate: the coordinator, the widget snapshot,
/// and the bridge that lets AppKit callbacks open SwiftUI windows.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let coordinator: NowPlayingCoordinator
    /// Captured from the first SwiftUI view that appears, so the Dock and reopen handlers can open windows.
    var openWindow: OpenWindowAction?
    private var widgetCommands: WidgetCommand.Observation?

    private init() {
        let secrets = KeychainSecretStore()
        coordinator = NowPlayingCoordinator(
            albumChain: AlbumArtworkChain(providers: [ITunesSearchProvider(), CoverArtArchiveProvider(), AppleMusicArtworkProvider()]),
            fanArtSources: [
                FanartTVSource(secrets: secrets),
                TheAudioDBSource(secrets: secrets),
                DeviantArtSource(secrets: secrets),
                BraveImageSource(secrets: secrets),
            ],
            display: WallpaperService(),
            preferences: Preferences()
        )
        coordinator.onStateChange = { [weak self] in self?.publishWidgetSnapshot() }
        widgetCommands = WidgetCommand.observe { [weak self] command in
            guard let coordinator = self?.coordinator else { return }
            switch command {
            case .next: coordinator.showNext()
            case .togglePause: coordinator.isSuspended.toggle()
            }
        }
        coordinator.start()
    }

    func showMiniPlayer() {
        NSApp.activate()
        openWindow?(id: MiniPlayerScene.id)
    }

    /// Writes what the widgets show, off the main thread, then asks WidgetKit to refresh.
    private func publishWidgetSnapshot() {
        let c = coordinator
        let (track, playing, suspended, showing, slides) = (c.track, c.isPlaying, c.isSuspended, c.showing, c.slides)
        Task.detached(priority: .utility) {
            do {
                try SharedStore.write(track: track, isPlaying: playing, isSuspended: suspended, showing: showing, slides: slides)
            } catch {
                return
            }
            await MainActor.run { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
}

/// Dock presence and the Dock menu. AudioPaper is a background utility: it shows in the Dock only
/// while the Mini Player is open, or when its menu bar extra is hidden (so there's always a way in).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var miniPlayerOpen = false
    /// Set when quitting, so windows closing on the way out don't count as the person closing them.
    private var isTerminating = false

    func miniPlayerDidOpen() {
        AppModel.shared.coordinator.preferences.miniPlayerOpen = true
        updateDockPresence(miniPlayerOpen: true)
    }

    func miniPlayerDidClose() {
        if !isTerminating {
            AppModel.shared.coordinator.preferences.miniPlayerOpen = false
        }
        updateDockPresence(miniPlayerOpen: false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
    }

    func updateDockPresence(miniPlayerOpen: Bool? = nil) {
        if let miniPlayerOpen { self.miniPlayerOpen = miniPlayerOpen }
        let needsDock = self.miniPlayerOpen || !AppModel.shared.coordinator.preferences.showInMenuBar
        let policy: NSApplication.ActivationPolicy = needsDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateDockPresence()
    }

    /// A menu bar utility keeps running with no windows open; closing the Mini Player must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon (or launching again from Finder) opens the Mini Player, like Music.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            AppModel.shared.showMiniPlayer()
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let coordinator = AppModel.shared.coordinator
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Next Image", enabled: !coordinator.fanArt.isEmpty) { coordinator.showNext() })
        menu.addItem(ClosureMenuItem(coordinator.isSuspended ? "Resume Wallpaper Changes" : "Pause Wallpaper Changes") {
            coordinator.isSuspended.toggle()
        })
        menu.addItem(ClosureMenuItem("Restore Original Wallpaper") { coordinator.restoreOriginalWallpaper() })
        return menu
    }
}

/// An NSMenuItem that runs a closure, for the Dock menu and the Mini Player's "…" menu.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, enabled: Bool = true, checked: Bool = false, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() {
        handler()
    }
}
