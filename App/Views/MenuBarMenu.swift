import AudioPaperKit
import SwiftUI

/// The menu bar extra's menu. HIG: "Display a menu — not a popover — when people click your menu bar
/// extra." The rich view lives in the Mini Player window, one item away.
struct MenuBarMenu: View {
    let coordinator: NowPlayingCoordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        nowPlaying
        Divider()
        PlaybackMenuItems(coordinator: coordinator)
        Divider()
        Button("Show Mini Player") {
            NSApp.activate()
            openWindow(id: MiniPlayerScene.id)
        }
        .keyboardShortcut("m", modifiers: [.command, .option])
        Divider()
        Button("Settings…") { SettingsWindow.show(openSettings) }
            .keyboardShortcut(",", modifiers: .command)
        Button("Quit AudioPaper") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private var nowPlaying: some View {
        if let track = coordinator.track {
            Text(track.title)
            Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
        } else {
            Text(coordinator.status)
        }
        if let showing = coordinator.showing {
            let attribution = showing.candidate.attribution
            if let credit = showing.candidate.creatorCredit {
                if let profile = attribution.creatorProfileURL {
                    Button(credit) { openURL(profile) }
                } else {
                    Text(credit)
                }
            }
            if let page = attribution.pageURL {
                Button(showing.candidate.kind == .albumCover ? "View Album on \(attribution.sourceName)" : "View Image on \(attribution.sourceName)") {
                    openURL(page)
                }
            }
        }
    }
}

/// Wallpaper actions shared by the menu bar menu, the Dock menu and the Mini Player.
struct PlaybackMenuItems: View {
    let coordinator: NowPlayingCoordinator

    var body: some View {
        Button("Next Image") { coordinator.showNext() }
            .disabled(coordinator.fanArt.isEmpty)
        Button(coordinator.isSuspended ? "Resume Wallpaper Changes" : "Pause Wallpaper Changes") {
            coordinator.isSuspended.toggle()
        }
        Button("Restore Original Wallpaper") { coordinator.restoreOriginalWallpaper() }
    }
}
