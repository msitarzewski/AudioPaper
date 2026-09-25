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
