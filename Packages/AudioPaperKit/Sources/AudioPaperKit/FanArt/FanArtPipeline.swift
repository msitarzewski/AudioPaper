import CoreGraphics
import Foundation
import Vision

/// Searches every configured fan-art source, downloads candidates, and streams those that pass all filters.
///
/// Order of work is cheapest first: reported size → download → decode → Vision filters → duplicate check.
public struct FanArtPipeline: Sendable {
    /// Bump when sources, filters or thresholds change, so cached per-song results are searched again.
    public static let version = 5

    public enum Event: Sendable {
        case accepted(Artwork)
        case rejected(ArtworkCandidate, reason: String)
    }

    public var sources: [any FanArtSource]
    public var sizeFilter: SizeFilter
    public var filters: [any ArtworkFilter]
    public var cache: ArtworkCache
    public var candidatesPerSource = 30
    /// Fallback sources are searched only when fewer than this many primary images pass the filters.
    public var fallbackThreshold = 3
    public var maxAccepted = 8
    public var concurrentDownloads = 4
    /// Feature-print distance under which two images count as the same picture. True duplicates measure
    /// 0.00–0.18; different photos from one shoot (group shots especially) measure 0.23–0.32, and are kept.
    public var duplicateDistance: Double = 0.2

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

    /// - Parameters:
    ///   - excluding: images that must not reappear, compared by look (the album cover, what's on screen,
    ///     the artist's pooled images).
    ///   - known: image URLs already pooled; skipped without downloading.
    public func run(for track: Track, excluding: [CGImage] = [], known: Set<URL> = []) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task {
                await execute(track: track, excluding: excluding, known: known, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func execute(track: Track, excluding: [CGImage], known: Set<URL>, continuation: AsyncStream<Event>.Continuation) async {
        var accepted = AcceptedSet()
        for image in excluding {
            if let print = try? await Self.featurePrint(image) { accepted.prints.append(print) }
        }
        let configured = sources.filter(\.isConfigured)

        let primary = await gatherCrediting(from: configured.filter { !$0.isFallback }, for: track).filter { !known.contains($0.imageURL) }
        await process(primary, into: &accepted, continuation: continuation)

        // Metered fallbacks fill in only when too few images *passed* the filters (not merely were found).
        guard !Task.isCancelled, accepted.count < fallbackThreshold else { return }
        let seen = known.union(primary.map(\.imageURL))
        let fallback = await gatherCrediting(from: configured.filter(\.isFallback), for: track).filter { !seen.contains($0.imageURL) }
        await process(fallback, into: &accepted, continuation: continuation)
    }

    /// Feature prints and count of everything accepted so far (plus the excluded images' prints).
    struct AcceptedSet {
        var prints: [FeaturePrintObservation] = []
        var count = 0
    }

    private func process(
        _ candidates: [ArtworkCandidate],
        into accepted: inout AcceptedSet,
        continuation: AsyncStream<Event>.Continuation
    ) async {
        var queue = candidates.filter { candidate in
            guard sizeFilter.accepts(width: candidate.width, height: candidate.height) else {
                continuation.yield(.rejected(candidate, reason: "reported size \(candidate.width ?? 0)×\(candidate.height ?? 0)"))
                return false
            }
            return true
        }[...]
        guard !queue.isEmpty, accepted.count < maxAccepted else { return }

        var state = accepted
        await withTaskGroup(of: (ArtworkCandidate, Result<(AnalyzedImage, Double?), RejectReason>).self) { group in
            func startNext() {
                guard let candidate = queue.popFirst() else { return }
                group.addTask { (candidate, await analyze(candidate)) }
            }
            for _ in 0..<concurrentDownloads { startNext() }

            for await (candidate, result) in group {
                if Task.isCancelled || state.count >= maxAccepted {
                    group.cancelAll()
                    break
                }
                switch result {
                case let .failure(reason):
                    continuation.yield(.rejected(candidate, reason: reason.message))
                case let .success((image, score)):
                    // Duplicate check is serialized here so every new image is compared to all accepted ones.
                    if let print = try? await Self.featurePrint(image.preview) {
                        if let distance = state.prints.lazy.compactMap({ try? print.distance(to: $0) }).min(),
                           distance < duplicateDistance {
                            continuation.yield(.rejected(candidate, reason: String(format: "duplicate (%.2f)", distance)))
                            startNext()
                            continue
                        }
                        state.prints.append(print)
                    }
                    state.count += 1
                    continuation.yield(.accepted(Artwork(
                        candidate: candidate, fileURL: image.fileURL,
                        pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight,
                        qualityScore: score
                    )))
                }
                startNext()
            }
        }
        accepted = state
    }

    /// Round-robins sources (each already ordered by relevance) so no single source dominates.
    /// Searches under the full artist credit; if that finds nothing and the credit is a collaboration
    /// ("LE SSERAFIM & j-hope"), searches each credited artist and interleaves their results.
    private func gatherCrediting(from configured: [any FanArtSource], for track: Track) async -> [ArtworkCandidate] {
        let full = await gather(from: configured, for: track)
        let artists = track.creditedArtists
        guard full.isEmpty, !artists.isEmpty else { return full }
        var lists: [[ArtworkCandidate]] = []
        for artist in artists {
            lists.append(await gather(from: configured, for: track.crediting(artist)))
        }
        return Self.interleave(lists)
    }

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
        return Self.interleave(lists)
    }

    /// Round-robin merge of ranked lists, dropping repeated images.
    static func interleave(_ lists: [[ArtworkCandidate]]) -> [ArtworkCandidate] {
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
