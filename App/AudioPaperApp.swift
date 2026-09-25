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
