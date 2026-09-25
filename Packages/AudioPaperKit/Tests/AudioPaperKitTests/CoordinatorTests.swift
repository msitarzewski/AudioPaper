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

/// A desktop that takes as long as the test says, to check what the app shows in the meantime.
@MainActor
final class GatedDisplay: WallpaperDisplay {
    var screens = [ScreenDescriptor(id: 1, pixelWidth: 320, pixelHeight: 200)]
    var shown = 0
    var isOpen = true
    func show(_ files: [UInt32: URL], animated: Bool) async {
        while !isOpen { try? await Task.sleep(for: .milliseconds(10)) }
        shown += 1
    }
    func restoreOriginals() {}
}

/// Song changes: the app leads, the wallpaper follows, and the cover comes before the fan art.
@MainActor
@Suite struct SongChangeTimingTests {
    let source = ManualSource()
    let display = GatedDisplay()
    let cache = ArtworkCache(root: Fixture.temporaryDirectory(), http: StubHTTP { _ in Fixture.png(width: 1920, height: 1080) })
    let preferences: Preferences

    init() {
        preferences = Preferences(defaults: UserDefaults(suiteName: "AudioPaperTests-\(UUID().uuidString)")!)
        preferences.enabledSources = ["manual"]
        preferences.mode = .albumThenFanArt
    }

    func coordinator(debounce: Duration, coverHold: Duration = .seconds(10)) -> NowPlayingCoordinator {
        NowPlayingCoordinator(
            registry: SourceRegistry(sources: [source]),
            albumChain: AlbumArtworkChain(providers: [FixedAlbumProvider()]),
            fanArtSources: [],
            cache: cache,
            composer: WallpaperComposer(outputDirectory: Fixture.temporaryDirectory()),
            display: display,
            preferences: preferences,
            debounce: debounce,
            coverHold: coverHold
        )
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func theAppShowsTheCoverBeforeTheWallpaperIsDone() async {
        let coordinator = coordinator(debounce: .milliseconds(20))
        display.isOpen = false
        coordinator.start()
        source.send(.playing(.sample()))
        await waitUntil { coordinator.showing != nil }
        #expect(coordinator.showing?.candidate.kind == .albumCover)
        #expect(display.shown == 0, "the desktop is still rendering")
        display.isOpen = true
        await waitUntil { display.shown == 1 }
        #expect(display.shown == 1)
    }

    @Test func aDownloadedCoverDoesNotWaitForTheDebounce() async {
        let coordinator = coordinator(debounce: .milliseconds(800))
        coordinator.start()
        source.send(.playing(.sample("Closer", album: "The Downward Spiral")))
        await waitUntil { coordinator.showing?.candidate.attribution.title == "The Downward Spiral" }
        source.send(.playing(.sample("Wish", album: "Broken")))
        await waitUntil { coordinator.showing?.candidate.attribution.title == "Broken" }
        // Back to a cover already downloaded: it's up well inside the 800 ms debounce.
        let start = ContinuousClock.now
        source.send(.playing(.sample("Hurt", album: "The Downward Spiral")))
        await waitUntil { coordinator.showing?.candidate.attribution.title == "The Downward Spiral" }
        #expect(coordinator.showing?.candidate.attribution.title == "The Downward Spiral")
        #expect(ContinuousClock.now - start < .milliseconds(500))
    }

    @Test func theCoverHoldsThePlaceThenTheFanArtTakesOver() async throws {
        preferences.rotationInterval = 60
        let track = Track.sample()
        let file = Fixture.temporaryDirectory().appending(path: "art.png")
        try Fixture.png(width: 1920, height: 1080, red: 0.1).write(to: file)
        let art = Artwork(candidate: fanArtCandidate("art.png"), fileURL: file, pixelWidth: 1920, pixelHeight: 1080)
        _ = try await cache.updatePool(forKey: NowPlayingCoordinator.poolKey(for: track)) { $0.add([art]) }

        // A 60 s rotation, but the cover only holds its place for the (shortened) cover hold.
        let coordinator = coordinator(debounce: .milliseconds(20), coverHold: .milliseconds(300))
        var kinds: [ArtworkKind] = []
        coordinator.start()
        source.send(.playing(track))
        for _ in 0..<150 {
            if let kind = coordinator.showing?.candidate.kind, kinds.last != kind { kinds.append(kind) }
            if kinds.count == 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(kinds == [.albumCover, .fanArt], "the cover first, then the fan art after the cover hold, not the interval")
    }
}
