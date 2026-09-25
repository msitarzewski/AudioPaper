import Foundation
import Testing
import Vision
@testable import AudioPaperKit

/// A fan-art source returning a fixed list.
struct FixedFanArt: FanArtSource {
    var id = "fixed"
    var displayName = "Fixed"
    var isConfigured = true
    var isFallback = false
    var list: [ArtworkCandidate]
    func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate] { list }
}

/// Filter that rejects by URL, so pipeline behaviour can be tested without Vision.
struct RejectURLFilter: ArtworkFilter {
    let id = "reject-url"
    var rejected: Set<String>
    func evaluate(_ image: AnalyzedImage) async throws -> FilterVerdict {
        rejected.contains(image.candidate.imageURL.lastPathComponent) ? .reject("listed") : .accept(score: 0.5)
    }
}

func fanArtCandidate(_ name: String, width: Int? = 1920, height: Int? = 1080) -> ArtworkCandidate {
    ArtworkCandidate(
        imageURL: URL(string: "https://img.example/\(name)")!,
        width: width, height: height, kind: .fanArt, providerID: "fixed",
        attribution: Attribution(sourceName: "example")
    )
}

@Suite struct SizeFilterTests {
    let filter = SizeFilter()

    @Test func acceptsDesktopSizes() {
        #expect(filter.accepts(width: 1920, height: 1080))
        #expect(filter.accepts(width: 2560, height: 1600))
    }

    @Test func rejectsThumbnailsAndPhoneWallpapers() {
        #expect(!filter.accepts(width: 340, height: 270))
        #expect(!filter.accepts(width: 1080, height: 2400))
    }

    @Test func curatedBackgroundsMayBe720p() {
        #expect(!filter.accepts(width: 1280, height: 720))
        #expect(filter.accepts(width: 1280, height: 720, curated: true))
        #expect(!filter.accepts(width: 1000, height: 562, curated: true))
    }

    @Test func unknownSizeIsDeferredToDownload() {
        #expect(filter.accepts(width: nil, height: nil))
    }
}

@Suite struct FanArtPipelineTests {
    @Test func streamsOnlyCandidatesPassingEveryStep() async throws {
        let colours: [String: CGFloat] = ["good.png": 0.9, "small.png": 0.1, "listed.png": 0.5, "lies.png": 0.3]
        let http = StubHTTP { url in
            let name = url.lastPathComponent
            // "lies.png" reports a desktop size but is actually a thumbnail.
            let size = name == "lies.png" ? (300, 200) : (1920, 1080)
            return Fixture.png(width: size.0, height: size.1, red: colours[name] ?? 0.5)
        }
        let cache = ArtworkCache(root: Fixture.temporaryDirectory(), http: http)
        let source = FixedFanArt(list: [
            fanArtCandidate("good.png"),
            fanArtCandidate("small.png", width: 300, height: 300),
            fanArtCandidate("listed.png"),
            fanArtCandidate("lies.png"),
        ])
        let pipeline = FanArtPipeline(sources: [source], filters: [RejectURLFilter(rejected: ["listed.png"])], cache: cache)

        var accepted: [String] = []
        var rejected: [String: String] = [:]
        for await event in pipeline.run(for: .sample()) {
            switch event {
            case let .accepted(artwork): accepted.append(artwork.candidate.imageURL.lastPathComponent)
            case let .rejected(candidate, reason): rejected[candidate.imageURL.lastPathComponent] = reason
            }
        }
        #expect(accepted == ["good.png"])
        #expect(rejected["small.png"]?.hasPrefix("reported size") == true)
        #expect(rejected["listed.png"]?.contains("reject-url") == true)
        #expect(rejected["lies.png"]?.hasPrefix("size") == true)
        #expect(!http.requests.contains { $0.lastPathComponent == "small.png" }, "reported-too-small images are never downloaded")
    }

    @Test func fallbackSourcesOnlyFillGaps() async {
        let cache = ArtworkCache(root: Fixture.temporaryDirectory(), http: StubHTTP { _ in nil })
        let plenty = FixedFanArt(id: "primary", list: ["a", "b", "c"].map { fanArtCandidate($0, width: 10, height: 10) })
        let fallback = FixedFanArt(id: "fallback", isFallback: true, list: [fanArtCandidate("z", width: 10, height: 10)])
        var seen: [String] = []
        for await event in FanArtPipeline(sources: [plenty, fallback], filters: [], cache: cache).run(for: .sample()) {
            if case let .rejected(candidate, _) = event { seen.append(candidate.imageURL.lastPathComponent) }
        }
        #expect(seen == ["a", "b", "c"], "three primary candidates means the fallback is never asked")

        let sparse = FixedFanArt(id: "primary", list: [fanArtCandidate("a", width: 10, height: 10)])
        seen = []
        for await event in FanArtPipeline(sources: [sparse, fallback], filters: [], cache: cache).run(for: .sample()) {
            if case let .rejected(candidate, _) = event { seen.append(candidate.imageURL.lastPathComponent) }
        }
        #expect(seen == ["a", "z"])
    }

    @Test func unconfiguredSourcesAreSkipped() async {
        let cache = ArtworkCache(root: Fixture.temporaryDirectory(), http: StubHTTP { _ in nil })
        let pipeline = FanArtPipeline(sources: [FixedFanArt(isConfigured: false, list: [fanArtCandidate("a.png")])], filters: [], cache: cache)
        var events = 0
        for await _ in pipeline.run(for: .sample()) { events += 1 }
        #expect(events == 0)
    }
}

@Suite struct WallpaperComposerTests {
    func artwork(kind: ArtworkKind, width: Int, height: Int) throws -> Artwork {
        let dir = Fixture.temporaryDirectory()
        let file = dir.appending(path: "art.png")
        try Fixture.png(width: width, height: height).write(to: file)
        let candidate = ArtworkCandidate(imageURL: URL(string: "https://img.example/art.png")!, kind: kind, providerID: "t", attribution: Attribution(sourceName: "t"))
        return Artwork(candidate: candidate, fileURL: file, pixelWidth: width, pixelHeight: height)
    }

    @Test(arguments: [ArtworkKind.albumCover, .fanArt])
    func rendersOneScreenSizedFilePerScreen(kind: ArtworkKind) throws {
        let composer = WallpaperComposer(outputDirectory: Fixture.temporaryDirectory())
        let screens = [ScreenDescriptor(id: 1, pixelWidth: 1600, pixelHeight: 1000), ScreenDescriptor(id: 2, pixelWidth: 800, pixelHeight: 1200)]
        let files = try composer.render(artwork(kind: kind, width: 1000, height: 1000), for: screens)
        #expect(files.count == 2)
        for screen in screens {
            let file = try #require(files[screen.id])
            let size = try #require(ImageLoading.pixelSize(of: file))
            #expect(size.width == screen.pixelWidth && size.height == screen.pixelHeight)
        }
    }

    @Test func automaticFramingFitsWhenFillingWouldCropTooMuch() {
        let screen = CGSize(width: 3024, height: 1964)
        #expect(FanArtFraming.automatic.fits(imageSize: CGSize(width: 1440, height: 1440), canvas: screen))
        #expect(!FanArtFraming.automatic.fits(imageSize: CGSize(width: 1920, height: 1200), canvas: screen))
        #expect(!FanArtFraming.fill.fits(imageSize: CGSize(width: 1440, height: 1440), canvas: screen))
        #expect(FanArtFraming.fit.fits(imageSize: CGSize(width: 1920, height: 1200), canvas: screen))
    }

    @Test(arguments: [FanArtFraming.fill, .fit])
    func fanArtRendersScreenSizedInEitherFraming(framing: FanArtFraming) throws {
        let composer = WallpaperComposer(outputDirectory: Fixture.temporaryDirectory())
        let screen = ScreenDescriptor(id: 1, pixelWidth: 1600, pixelHeight: 900)
        let files = try composer.render(artwork(kind: .fanArt, width: 900, height: 1200), for: [screen], framing: framing)
        let file = try #require(files[1])
        let size = try #require(ImageLoading.pixelSize(of: file))
        #expect(size.width == 1600 && size.height == 900)
    }

    @Test func everyRenderUsesNewFileNamesAndPruneKeepsOnlyCurrent() throws {
        let composer = WallpaperComposer(outputDirectory: Fixture.temporaryDirectory())
        let screens = [ScreenDescriptor(id: 1, pixelWidth: 400, pixelHeight: 300)]
        let art = try artwork(kind: .fanArt, width: 800, height: 600)
        let first = try composer.render(art, for: screens)
        let second = try composer.render(art, for: screens)
        #expect(first[1] != second[1])
        composer.prune(keeping: Set(second.values))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: composer.outputDirectory.path())
        #expect(remaining == [second[1]!.lastPathComponent])
    }
}

@Suite struct ClassificationFilterTests {
    @Test func everyLabelIsARealVisionIdentifier() throws {
        let supported = Set(try VNClassifyImageRequest().supportedIdentifiers())
        let unknownRejected = ClassificationFilter.defaultRejectedLabels.subtracting(supported)
        let unknownArt = ClassificationFilter.artLabels.subtracting(supported)
        #expect(unknownRejected.isEmpty, "not in Vision's taxonomy: \(unknownRejected.sorted())")
        #expect(unknownArt.isEmpty, "not in Vision's taxonomy: \(unknownArt.sorted())")
    }
}
