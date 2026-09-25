import CoreGraphics
import Foundation
import Vision

/// A downloaded candidate plus a small decoded copy for on-device analysis.
public struct AnalyzedImage: @unchecked Sendable {
    public var candidate: ArtworkCandidate
    public var fileURL: URL
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Downsampled (≤1024px) image used only for Vision; CGImage is immutable so sharing is safe.
    public var preview: CGImage
}

public enum FilterVerdict: Sendable, Equatable {
    /// Accepted; a filter may contribute a quality score used for ranking.
    case accept(score: Double? = nil)
    case reject(String)
}

/// One step of the fan-art pipeline. Filters are small plugins run in order; the first rejection wins.
public protocol ArtworkFilter: Sendable {
    var id: String { get }
    func evaluate(_ image: AnalyzedImage) async throws -> FilterVerdict
}

/// Rejects small or badly-proportioned images. Also usable before download via `accepts(width:height:)`.
public struct SizeFilter: ArtworkFilter {
    public let id = "size"
    public var minLongEdge: Int
    public var minShortEdge: Int
    /// Width ÷ height bounds; wallpapers are landscape, so very tall art crops badly.
    public var aspectRange: ClosedRange<Double>

    public init(minLongEdge: Int = 1400, minShortEdge: Int = 900, aspectRange: ClosedRange<Double> = 0.75...2.6) {
        self.minLongEdge = minLongEdge
        self.minShortEdge = minShortEdge
        self.aspectRange = aspectRange
    }

    /// Floor for curated background collections, which publish at 1280×720.
    public static let curatedMinimum = (longEdge: 1280, shortEdge: 720)

    public func accepts(width: Int?, height: Int?, curated: Bool = false) -> Bool {
        // Unknown sizes are allowed through to download; the real size is checked afterwards.
        guard let width, let height, width > 0, height > 0 else { return true }
        let long = curated ? min(minLongEdge, Self.curatedMinimum.longEdge) : minLongEdge
        let short = curated ? min(minShortEdge, Self.curatedMinimum.shortEdge) : minShortEdge
        return max(width, height) >= long
            && min(width, height) >= short
            && aspectRange.contains(Double(width) / Double(height))
    }

    public func evaluate(_ image: AnalyzedImage) async throws -> FilterVerdict {
        accepts(width: image.pixelWidth, height: image.pixelHeight, curated: image.candidate.isCurated)
            ? .accept()
            : .reject("size \(image.pixelWidth)×\(image.pixelHeight)")
    }
}

/// Vision aesthetics: rejects "utility" images (screenshots, documents, receipts) and low-scoring images.
public struct AestheticsFilter: ArtworkFilter {
    public let id = "aesthetics"
    /// Vision's overall score runs roughly -1...1.
    public var minimumScore: Double

    public init(minimumScore: Double = -0.5) {
        self.minimumScore = minimumScore
    }

    public func evaluate(_ image: AnalyzedImage) async throws -> FilterVerdict {
        let observation = try await CalculateImageAestheticsScoresRequest().perform(on: image.preview)
        if observation.isUtility { return .reject("utility image") }
        let score = Double(observation.overallScore)
        return score >= minimumScore ? .accept(score: score) : .reject(String(format: "aesthetics %.2f", score))
    }
}

/// Rejects images carrying readable text (titles, lyrics, watermarks, UI). A small signature is tolerated.
public struct TextFilter: ArtworkFilter {
    public let id = "text"
    /// Maximum fraction of the image area that recognized text may cover.
    public var maxCoverage: Double
    /// Maximum number of recognized words.
    public var maxWords: Int

    public init(maxCoverage: Double = 0.015, maxWords: Int = 3) {
        self.maxCoverage = maxCoverage
        self.maxWords = maxWords
    }

    public func evaluate(_ image: AnalyzedImage) async throws -> FilterVerdict {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image.preview)
        let coverage = observations.reduce(0.0) { total, observation in
            let rect = observation.boundingBox.cgRect
            return total + Double(rect.width * rect.height)
        }
        let words = observations.reduce(0) { total, observation in
            total + (observation.topCandidates(1).first?.string.split(separator: " ").count ?? 0)
        }
        if coverage > maxCoverage || words > maxWords {
            return .reject(String(format: "text %.1f%%, %d words", coverage * 100, words))
        }
        return .accept()
    }
}

/// Vision scene classification: rejects documents, product shots, and other scenes that aren't art or photography.
/// People, performers and concerts are welcome; merch mockups are mostly kept out by the source blocklists.
public struct ClassificationFilter: ArtworkFilter {
    public let id = "classification"
    public var rejectedLabels: Set<String>
    public var threshold: Float

    /// Every entry must be a real Vision identifier (`VNClassifyImageRequest().supportedIdentifiers()`);
    /// a test enforces this so guessed names can't silently never match.
    public static let defaultRejectedLabels: Set<String> = [
        // Screens and UI
        "screenshot", "computer", "computer_monitor", "computer_keyboard", "computer_mouse", "computer_tower",
        "television", "phone",
        // Advertising and retail
        "billboards", "banner", "sign", "street_sign", "storefront", "interior_shop", "shopping_cart",
        // Print and documents
        "document", "printed_page", "newspaper", "magazine", "book", "bookshelf", "receipt", "ticket",
        "chart", "diagram", "map", "calendar", "handwriting", "whiteboard", "flipchart",
        "checkbook", "credit_card", "gift_card",
        // Products and mockups (merch shots, framed prints on a wall, album packshots)
        "mug", "cup", "bottle", "wine_bottle", "tableware", "cardboard_box", "carton", "paper_bag",
        "cd", "record", "turntable", "frame", "interior_room",
    ]

    /// Labels that mark an image as artwork; they raise its rank but aren't required (photos are welcome).
    public static let artLabels: Set<String> = ["art", "illustrations", "painting", "graffiti"]

    public init(rejectedLabels: Set<String> = ClassificationFilter.defaultRejectedLabels, threshold: Float = 0.6) {
        self.rejectedLabels = rejectedLabels
        self.threshold = threshold
    }

    public func evaluate(_ image: AnalyzedImage) async throws -> FilterVerdict {
        let observations = try await ClassifyImageRequest().perform(on: image.preview)
        if let hit = observations.first(where: { $0.confidence >= threshold && rejectedLabels.contains($0.identifier) }) {
            return .reject(String(format: "label %@ %.2f", hit.identifier, hit.confidence))
        }
        // Artwork gets a ranking boost equal to Vision's confidence that it's art.
        let artConfidence = observations.filter { Self.artLabels.contains($0.identifier) }.map(\.confidence).max() ?? 0
        return .accept(score: artConfidence > 0 ? Double(artConfidence) : nil)
    }
}
