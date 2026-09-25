import AudioPaperKit
import SwiftUI

@main
struct AudioPaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    private var coordinator: NowPlayingCoordinator { model.coordinator }

    var body: some Scene {
        MenuBarExtra(isInserted: showInMenuBar) {
            MenuBarMenu(coordinator: coordinator)
        } label: {
            // Template images (Assets.xcassets), so the system tints them for light, dark and selected menu bars.
            Image(coordinator.isSuspended ? "MenuBarIconPaused" : "MenuBarIcon")
                .accessibilityLabel(coordinator.isSuspended ? "AudioPaper, paused" : "AudioPaper")
                .background(WindowOpenerCapture(model: model))
        }
        .menuBarExtraStyle(.menu)

        Window("Mini Player", id: MiniPlayerScene.id) {
            MiniPlayerView(coordinator: coordinator, preferences: coordinator.preferences)
                .background(WindowOpenerCapture(model: model))
                .onAppear { appDelegate.miniPlayerDidOpen() }
                .onDisappear { appDelegate.miniPlayerDidClose() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        // Reopens if it was open at quit; with the menu bar extra hidden it's the way in, so it always opens.
        .defaultLaunchBehavior(coordinator.preferences.miniPlayerOpen || !coordinator.preferences.showInMenuBar ? .presented : .suppressed)
        // Open state is remembered explicitly (above), so the system's window restoration would only double it.
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .windowArrangement) {
                MiniPlayerCommands(model: model)
            }
            // HIG: the Help menu opens the app's help; ours is the website.
            CommandGroup(replacing: .help) {
                HelpCommands()
            }
            // Where macOS apps put it: the app menu, after About.
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updates.shared.checkForUpdates() }
            }
        }

        Settings {
            SettingsView(coordinator: coordinator, preferences: coordinator.preferences)
                .onChange(of: coordinator.preferences.showInMenuBar) { appDelegate.updateDockPresence() }
        }
    }

    private var showInMenuBar: Binding<Bool> {
        Binding(
            get: { coordinator.preferences.showInMenuBar },
            set: { coordinator.preferences.showInMenuBar = $0 }
        )
    }
}

/// Window menu items for the Mini Player, mirroring Music's MiniPlayer options.
private struct MiniPlayerCommands: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var preferences = model.coordinator.preferences
        Button("Show Mini Player") { openWindow(id: MiniPlayerScene.id) }
            .keyboardShortcut("m", modifiers: [.command, .option])
        Toggle("Float Mini Player on Top", isOn: $preferences.miniPlayerFloatsOnTop)
        Toggle("Show Mini Player on All Desktops", isOn: $preferences.miniPlayerOnAllDesktops)
    }
}

/// The project website (GitHub Pages, built from `site/`).
enum Website {
    static let home = URL(string: "https://msitarzewski.github.io/AudioPaper/")!
    static let help = home.appending(path: "help.html")
    static let privacy = home.appending(path: "privacy.html")
}

/// Opens Settings in front. AudioPaper usually has no Dock icon, so opening the window alone leaves it
/// behind whatever app is frontmost; activate first, then bring the window forward once SwiftUI has made it.
@MainActor
enum SettingsWindow {
    static func show(_ openSettings: OpenSettingsAction) {
        // The request comes from AudioPaper's own menu, so taking focus is what the person asked for; the
        // cooperative `activate()` can be declined when a menu bar extra, which never activates, is the source.
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

private struct HelpCommands: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("AudioPaper Help") { openURL(Website.help) }
            .keyboardShortcut("?", modifiers: .command)
    }
}

/// Hands SwiftUI's `openWindow` to the AppKit side (Dock clicks, reopen) the first time any view appears.
private struct WindowOpenerCapture: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { model.openWindow = openWindow }
    }
}
