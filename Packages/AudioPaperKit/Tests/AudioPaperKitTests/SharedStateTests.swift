import Foundation
import Testing
@testable import AudioPaperKit

@Suite struct SharedStoreTests {
    func artwork(_ name: String, kind: ArtworkKind, in dir: URL) throws -> Artwork {
        let file = dir.appending(path: "\(name).png")
        try Fixture.png(width: 1600, height: 1000).write(to: file)
        let candidate = ArtworkCandidate(
            imageURL: URL(string: "https://img.example/\(name).png")!, kind: kind, providerID: "t",
            attribution: Attribution(title: name, creatorName: "artist", creatorProfileURL: URL(string: "https://example.com/artist"), sourceName: "Example")
        )
        return Artwork(candidate: candidate, fileURL: file, pixelWidth: 1600, pixelHeight: 1000)
    }

    @Test func snapshotRoundTripsWithThumbnails() throws {
        let container = Fixture.temporaryDirectory()
        let source = Fixture.temporaryDirectory()
        let cover = try artwork("cover", kind: .albumCover, in: source)
        let fan = try artwork("fan", kind: .fanArt, in: source)
        try SharedStore.write(track: .sample(), isPlaying: true, isSuspended: false, showing: fan, slides: [cover, fan], to: container)

        let snapshot = SharedStore.read(from: container)
        #expect(snapshot.track?.title == "Closer")
        #expect(snapshot.isPlaying)
        #expect(snapshot.slides.map(\.kind) == [.albumCover, .fanArt])
        #expect(snapshot.showing?.id == fan.id)
        #expect(snapshot.showing?.creatorProfileURL?.absoluteString == "https://example.com/artist")
        let showing = try #require(snapshot.showing)
        let thumb = try #require(SharedStore.thumbnail(showing, in: container))
        #expect(max(thumb.width, thumb.height) <= SharedStore.thumbnailPixelSize)
    }

    @Test func staleThumbnailsArePruned() throws {
        let container = Fixture.temporaryDirectory()
        let source = Fixture.temporaryDirectory()
        let first = try artwork("first", kind: .fanArt, in: source)
        let second = try artwork("second", kind: .fanArt, in: source)
        try SharedStore.write(track: nil, isPlaying: false, isSuspended: false, showing: first, slides: [first], to: container)
        try SharedStore.write(track: nil, isPlaying: false, isSuspended: false, showing: second, slides: [second], to: container)
        let files = try FileManager.default.contentsOfDirectory(atPath: container.appending(path: "Thumbnails").path(percentEncoded: false))
        #expect(files == [SharedStore.read(from: container).showing!.file])
    }

    @Test func missingSnapshotReadsAsEmpty() {
        #expect(SharedStore.read(from: Fixture.temporaryDirectory()) == .empty)
        #expect(SharedStore.read(from: nil) == .empty)
    }
}

@Suite struct PrivacyTests {
    @Test func networkSessionStoresNoCookiesOrCache() {
        let configuration = URLSessionHTTPClient.privateSession.configuration
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCache == nil)
    }

    @Test func artistIDsSurviveARelaunchAndUnresolvedOnesExpire() async throws {
        let file = Fixture.temporaryDirectory().appending(path: "artist-ids.json")
        let first = MusicBrainz.ArtistIDMemo()
        await first.persist(at: file)
        await first.set("nine inch nails", "b7ffd2af")
        await first.set("nobody", nil)

        // A fresh memo (as after relaunch) reads them back from disk.
        let relaunched = MusicBrainz.ArtistIDMemo()
        await relaunched.persist(at: file)
        #expect(await relaunched.get("nine inch nails") == .some("b7ffd2af"))
        #expect(await relaunched.get("nobody") == .some(nil), "a recent 'not found' is remembered")

        // An old 'not found' has expired, so the artist is looked up again.
        var entries = try JSONDecoder().decode([String: MusicBrainz.ArtistIDMemo.Entry].self, from: Data(contentsOf: file))
        entries["nobody"]?.date = Date(timeIntervalSinceNow: -8 * 24 * 3600)
        try JSONEncoder().encode(entries).write(to: file)
        let later = MusicBrainz.ArtistIDMemo()
        await later.persist(at: file)
        #expect(await later.get("nobody") == nil)
        #expect(await later.get("nine inch nails") == .some("b7ffd2af"), "resolved IDs don't expire")
    }
}

@Suite struct ArtistPoolTests {
    func art(_ name: String, score: Double = 0.5) -> Artwork {
        Artwork(candidate: fanArtCandidate(name), fileURL: URL(filePath: "/tmp/\(name)"), pixelWidth: 1920, pixelHeight: 1080, qualityScore: score)
    }

    @Test func selectionShowsUnseenFirstThenLeastRecentlyShown() {
        var pool = ArtistPool()
        pool.add([art("a", score: 0.9), art("b", score: 0.1), art("c", score: 0.5)])
        pool.markShown(art("a").id, at: Date(timeIntervalSince1970: 200))
        pool.markShown(art("c").id, at: Date(timeIntervalSince1970: 100))
        let names = pool.selection(count: 3).map { $0.candidate.imageURL.lastPathComponent }
        #expect(names == ["b", "c", "a"], "never shown, then shown longest ago")
    }

    @Test func unseenTiesGoToQuality() {
        var pool = ArtistPool()
        pool.add([art("low", score: 0.1), art("high", score: 0.9)])
        #expect(pool.selection(count: 1).first?.candidate.imageURL.lastPathComponent == "high")
    }

    @Test func eachSongIsSearchedOnceUntilThePoolIsFull() {
        var pool = ArtistPool()
        #expect(pool.shouldSearch(song: "kim|autobahn"))
        pool.add([art("a")])
        pool.recordSearch(song: "kim|autobahn", found: 1)
        #expect(!pool.shouldSearch(song: "kim|autobahn"), "already searched")
        #expect(pool.shouldSearch(song: "kim|coconuts"), "a new song by the artist")
        pool.add((0..<30).map { art("x\($0)") })
        #expect(pool.artworks.count == ArtistPool.capacity)
        #expect(!pool.shouldSearch(song: "kim|heart to break"), "full")
    }

    @Test func songsThatFoundNothingAreRetriedAfterAWeek() {
        var pool = ArtistPool()
        let then = Date(timeIntervalSince1970: 0)
        pool.recordSearch(song: "s", found: 0, at: then)
        #expect(!pool.shouldSearch(song: "s", now: then.addingTimeInterval(3600)))
        #expect(pool.shouldSearch(song: "s", now: then.addingTimeInterval(ArtistPool.emptySearchRetry + 1)))
    }

    @Test func addingIgnoresImagesAlreadyPooled() {
        var pool = ArtistPool()
        pool.add([art("a"), art("a"), art("b")])
        #expect(pool.artworks.count == 2)
    }

    @Test func cacheUpdatesPoolsAtomicallyAndDropsEvictedImages() async throws {
        let dir = Fixture.temporaryDirectory()
        let cache = ArtworkCache(root: dir, http: StubHTTP { _ in Fixture.png(width: 1920, height: 1080) })
        let (file, _, _) = try await cache.download(fanArtCandidate("kept.png"))
        let kept = Artwork(candidate: fanArtCandidate("kept.png"), fileURL: file, pixelWidth: 1920, pixelHeight: 1080)
        let gone = art("gone.png")  // its file never existed
        try await cache.updatePool(forKey: "k") { $0.add([kept, gone]) }
        #expect(await cache.pool(forKey: "k").artworks == [kept])
    }
}
