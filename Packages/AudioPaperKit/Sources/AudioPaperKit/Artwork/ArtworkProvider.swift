import Foundation

/// Plugin that finds the official cover for a track's album.
public protocol AlbumArtworkProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func albumArtwork(for track: Track) async throws -> ArtworkCandidate?
}

/// Plugin that finds community artwork for a track (song first, then artist).
public protocol FanArtSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// False when required credentials are missing; the pipeline skips unconfigured sources.
    var isConfigured: Bool { get }
    func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate]
    /// Fallback sources (e.g. metered web search) are only asked when the others come up short.
    var isFallback: Bool { get }
}

extension FanArtSource {
    public var isFallback: Bool { false }
}

/// Tries album-art providers in order and returns the first confident match.
public struct AlbumArtworkChain: Sendable {
    public var providers: [any AlbumArtworkProvider]
    public var minimumScore: Double

    public init(providers: [any AlbumArtworkProvider], minimumScore: Double = 0.6) {
        self.providers = providers
        self.minimumScore = minimumScore
    }

    public func artwork(for track: Track) async -> ArtworkCandidate? {
        for provider in providers {
            do {
                if let candidate = try await provider.albumArtwork(for: track), candidate.matchScore >= minimumScore {
                    return candidate
                }
            } catch {
                log.error("\(provider.id, privacy: .public) album lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }
}
