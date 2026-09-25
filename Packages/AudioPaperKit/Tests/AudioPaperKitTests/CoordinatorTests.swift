import Foundation
import Testing
@testable import AudioPaperKit

/// A player the test drives by hand.
final class ManualSource: NowPlayingSource, @unchecked Sendable {
    let id = "manual"
    let displayName = "Manual"
    let isAvailable = true
    private let stream: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func events() -> AsyncStream<PlaybackEvent> { stream }
    func send(_ event: PlaybackEvent) { continuation.yield(event) }
}

struct FixedAlbumProvider: AlbumArtworkProvider {
    let id = "fixed-album"
    let displayName = "Fixed"
    func albumArtwork(for track: Track) async throws -> ArtworkCandidate? {
        guard track.album != "Unknown Release" else { return nil }
        return ArtworkCandidate(
            imageURL: URL(string: "https://img.example/cover-\(Normalizer.key(track.album).replacingOccurrences(of: " ", with: "-")).png")!,
            kind: .albumCover, providerID: id,
            attribution: Attribution(title: track.album, sourceName: "test")
        )
    }
}

@MainActor
final class RecordingDisplay: WallpaperDisplay {
    var screens = [ScreenDescriptor(id: 1, pixelWidth: 320, pixelHeight: 200)]
    var shown: [(files: [UInt32: URL], animated: Bool)] = []
    var restored = 0
    func show(_ files: [UInt32: URL], animated: Bool) async { shown.append((files, animated)) }
    func restoreOriginals() { restored += 1 }
}

@MainActor
@Suite struct CoordinatorTests {
    let source = ManualSource()
    let display = RecordingDisplay()
    let coordinator: NowPlayingCoordinator

    init() {
        let http = StubHTTP { _ in Fixture.png(width: 1920, height: 1080) }
        let cache = ArtworkCache(root: Fixture.temporaryDirectory(), http: http)
        let defaults = UserDefaults(suiteName: "AudioPaperTests-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.enabledSources = ["manual"]
        preferences.mode = .albumOnly
        coordinator = NowPlayingCoordinator(
            registry: SourceRegistry(sources: [source]),
            albumChain: AlbumArtworkChain(providers: [FixedAlbumProvider()]),
            fanArtSources: [],
            cache: cache,
            composer: WallpaperComposer(outputDirectory: Fixture.temporaryDirectory()),
            display: display,
            preferences: preferences,
            debounce: .milliseconds(50)
        )
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func rapidSkipsLoadOnlyTheTrackThatSettles() async {
        coordinator.start()
        source.send(.playing(.sample("A", album: "First")))
        source.send(.playing(.sample("B", album: "Second")))
        source.send(.playing(.sample("C", album: "Third")))
        await waitUntil { coordinator.showing != nil }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(display.shown.count == 1)
        #expect(coordinator.showing?.candidate.attribution.title == "Third")
    }

    @Test func nextSongOnSameAlbumDoesNotRedrawCover() async {
        coordinator.start()
        source.send(.playing(.sample("Mr. Self Destruct")))
        await waitUntil { display.shown.count == 1 }
        source.send(.playing(.sample("Piggy")))
        try? await Task.sleep(for: .milliseconds(200))
        #expect(display.shown.count == 1)
        #expect(coordinator.track?.title == "Piggy")
    }

    @Test func newAlbumCrossFades() async {
        coordinator.start()
        source.send(.playing(.sample("Closer")))
        await waitUntil { display.shown.count == 1 }
        #expect(display.shown[0].animated == false, "first wallpaper has nothing to fade from")
        source.send(.playing(.sample("Hurt", album: "Broken")))
        await waitUntil { display.shown.count == 2 }
        #expect(display.shown[1].animated)
    }

    @Test func suspendedCoordinatorLeavesWallpaperAlone() async {
        coordinator.isSuspended = true
        coordinator.start()
        source.send(.playing(.sample()))
        try? await Task.sleep(for: .milliseconds(200))
        #expect(display.shown.isEmpty)
        #expect(coordinator.track?.title == "Closer")
    }

    @Test func albumWithNoCoverRestoresOriginalInsteadOfLeavingPreviousAlbumUp() async {
        coordinator.start()
        source.send(.playing(.sample()))
        await waitUntil { coordinator.showing != nil }
        source.send(.playing(.sample("A-Z", artist: "Sleepover", album: "Unknown Release")))
        await waitUntil { display.restored == 1 }
        #expect(display.restored == 1)
        #expect(coordinator.showing == nil)
    }

    @Test func stateChangesAreReportedCoalesced() async {
        var calls = 0
        coordinator.onStateChange = { calls += 1 }
        coordinator.start()
        source.send(.playing(.sample()))
        await waitUntil { coordinator.showing != nil }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(calls >= 1)
        #expect(calls < 6, "several property changes in one turn collapse into one report")
    }

    @Test func restoreHandsBackOriginal() async {
        coordinator.start()
        source.send(.playing(.sample()))
        await waitUntil { coordinator.showing != nil }
        coordinator.restoreOriginalWallpaper()
        #expect(display.restored == 1)
        #expect(coordinator.showing == nil)
    }
}
