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
