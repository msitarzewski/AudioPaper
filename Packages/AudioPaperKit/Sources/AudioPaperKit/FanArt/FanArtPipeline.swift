import CoreGraphics
import Foundation
import Vision

/// Searches every configured fan-art source, downloads candidates, and streams those that pass all filters.
///
/// Order of work is cheapest first: reported size → download → decode → Vision filters → duplicate check.
public struct FanArtPipeline: Sendable {
    public enum Event: Sendable {
        case accepted(Artwork)
        case rejected(ArtworkCandidate, reason: String)
    }

    public var sources: [any FanArtSource]
    public var sizeFilter: SizeFilter
    public var filters: [any ArtworkFilter]
    public var cache: ArtworkCache
    public var candidatesPerSource = 30
    /// Fallback sources are searched only when the primary sources return fewer candidates than this.
    public var fallbackThreshold = 3
    public var maxAccepted = 8
    public var concurrentDownloads = 4
    /// Feature-print distance under which two images count as the same picture.
    public var duplicateDistance: Double = 0.35

    public init(
        sources: [any FanArtSource],
        sizeFilter: SizeFilter = SizeFilter(),
        filters: [any ArtworkFilter] = [AestheticsFilter(), TextFilter(), ClassificationFilter()],
        cache: ArtworkCache
    ) {
        self.sources = sources
        self.sizeFilter = sizeFilter
        self.filters = filters
        self.cache = cache
    }

    /// - Parameter excluding: images that must not reappear (the album cover, art shown for the previous song).
    public func run(for track: Track, excluding: [CGImage] = []) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task {
                await execute(track: track, excluding: excluding, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(track: Track, excluding: [CGImage], continuation: AsyncStream<Event>.Continuation) async {
        let candidates = await gatherCandidates(for: track)
        var queue = candidates.filter { candidate in
            guard sizeFilter.accepts(width: candidate.width, height: candidate.height, curated: candidate.isCurated) else {
                continuation.yield(.rejected(candidate, reason: "reported size \(candidate.width ?? 0)×\(candidate.height ?? 0)"))
                return false
            }
            return true
        }[...]

        var acceptedPrints: [FeaturePrintObservation] = []
        for image in excluding {
            if let print = try? await Self.featurePrint(image) { acceptedPrints.append(print) }
        }
        var acceptedCount = 0

        await withTaskGroup(of: (ArtworkCandidate, Result<(AnalyzedImage, Double?), RejectReason>).self) { group in
            func startNext() {
                guard let candidate = queue.popFirst() else { return }
                group.addTask { (candidate, await analyze(candidate)) }
            }
            for _ in 0..<concurrentDownloads { startNext() }

            for await (candidate, result) in group {
                if Task.isCancelled || acceptedCount >= maxAccepted {
                    group.cancelAll()
                    break
                }
                switch result {
                case let .failure(reason):
                    continuation.yield(.rejected(candidate, reason: reason.message))
                case let .success((image, score)):
                    // Duplicate check is serialized here so every new image is compared to all accepted ones.
                    if let print = try? await Self.featurePrint(image.preview) {
                        if let distance = acceptedPrints.lazy.compactMap({ try? print.distance(to: $0) }).min(),
                           distance < duplicateDistance {
                            continuation.yield(.rejected(candidate, reason: String(format: "duplicate (%.2f)", distance)))
                            startNext()
                            continue
                        }
                        acceptedPrints.append(print)
                    }
                    acceptedCount += 1
                    continuation.yield(.accepted(Artwork(
                        candidate: candidate, fileURL: image.fileURL,
                        pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight,
                        qualityScore: score
                    )))
                }
                startNext()
            }
        }
    }

    /// Asks the primary sources, then the fallbacks only if the primaries came up short.
    private func gatherCandidates(for track: Track) async -> [ArtworkCandidate] {
        let configured = sources.filter(\.isConfigured)
        let primary = await gather(from: configured.filter { !$0.isFallback }, for: track)
        guard primary.count < fallbackThreshold else { return primary }
        let fallback = await gather(from: configured.filter(\.isFallback), for: track)
        var seen = Set(primary.map(\.imageURL))
        return primary + fallback.filter { seen.insert($0.imageURL).inserted }
    }

    /// Round-robins sources (each already ordered by relevance) so no single source dominates.
    private func gather(from configured: [any FanArtSource], for track: Track) async -> [ArtworkCandidate] {
        let limit = candidatesPerSource
        let lists = await withTaskGroup(of: (Int, [ArtworkCandidate]).self) { group in
            for (index, source) in configured.enumerated() {
                group.addTask {
                    do {
                        let found = try await source.candidates(for: track, limit: limit)
                        return (index, found.sorted { $0.matchScore > $1.matchScore })
                    } catch {
                        log.error("\(source.id, privacy: .public) search failed: \(error.localizedDescription, privacy: .public)")
                        return (index, [])
                    }
                }
            }
            var lists = [[ArtworkCandidate]](repeating: [], count: configured.count)
            for await (index, list) in group { lists[index] = list }
            return lists
        }
        var merged: [ArtworkCandidate] = []
        var seen = Set<URL>()
        for position in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where position < list.count {
                if seen.insert(list[position].imageURL).inserted { merged.append(list[position]) }
            }
        }
        return merged
    }

    struct RejectReason: Error {
        var message: String
    }

    private func analyze(_ candidate: ArtworkCandidate) async -> Result<(AnalyzedImage, Double?), RejectReason> {
        do {
            let (file, width, height) = try await cache.download(candidate)
            guard let preview = ImageLoading.image(at: file, maxPixelSize: 1024) else {
                return .failure(RejectReason(message: "undecodable"))
            }
            let image = AnalyzedImage(candidate: candidate, fileURL: file, pixelWidth: width, pixelHeight: height, preview: preview)
            if case let .reject(reason) = try await sizeFilter.evaluate(image) {
                return .failure(RejectReason(message: reason))
            }
            var score: Double?
            for filter in filters {
                try Task.checkCancellation()
                switch try await filter.evaluate(image) {
                case let .reject(reason): return .failure(RejectReason(message: "\(filter.id): \(reason)"))
                case let .accept(filterScore):
                    // Scores add up across filters (aesthetics, plus an art boost from classification).
                    if let filterScore { score = (score ?? 0) + filterScore }
                }
            }
            return .success((image, score))
        } catch {
            return .failure(RejectReason(message: "download: \(error.localizedDescription)"))
        }
    }

    static func featurePrint(_ image: CGImage) async throws -> FeaturePrintObservation {
        try await GenerateImageFeaturePrintRequest().perform(on: image)
    }
}
