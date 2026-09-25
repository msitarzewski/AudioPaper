import AudioPaperKit
import SwiftUI

@main
struct AudioPaperApp: App {
    @State private var coordinator: NowPlayingCoordinator

    init() {
        let secrets = KeychainSecretStore()
        let coordinator = NowPlayingCoordinator(
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
        coordinator.start()
        _coordinator = State(initialValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(coordinator: coordinator)
        } label: {
            Image(systemName: coordinator.isSuspended ? "photo.on.rectangle" : "photo.on.rectangle.angled.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coordinator: coordinator, preferences: coordinator.preferences)
        }
    }
}
