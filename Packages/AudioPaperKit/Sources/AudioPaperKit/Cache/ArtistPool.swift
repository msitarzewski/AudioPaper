import Foundation

/// The accepted fan art for one artist, grown over plays and rotated so repeat plays feel fresh.
///
/// Each song is searched once; its finds join the artist's pool (up to `capacity`). Every play shows a
/// selection that favours images seen least recently, so replays cost no network and still vary.
///
/// Images from sources the person has switched off (`hidden`, by source ID) are kept but never shown, and
/// don't count toward the capacity, so switching a source back on brings them back without a search.
public struct ArtistPool: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var artwork: Artwork
        public var lastShown: Date?
    }

    public static let capacity = 24
    /// A song that found nothing is searched again after this long (its sources may have new art).
    public static let emptySearchRetry: TimeInterval = 7 * 24 * 3600

    public private(set) var entries: [Entry] = []
    /// When each song (by `Track.songKey`) was last searched, and whether it found anything.
    public private(set) var searches: [String: Search] = [:]

    public struct Search: Codable, Sendable, Equatable {
        public var date: Date
        public var found: Int
    }

    public init() {}

    public var artworks: [Artwork] { entries.map(\.artwork) }

    /// Entries from sources that are switched on.
    func visibleEntries(hiding hidden: Set<String>) -> [Entry] {
        hidden.isEmpty ? entries : entries.filter { !hidden.contains($0.artwork.candidate.providerID) }
    }

    /// Every image from sources that are switched on, in pool order.
    public func artworks(hiding hidden: Set<String>) -> [Artwork] { visibleEntries(hiding: hidden).map(\.artwork) }

    public func isFull(hiding hidden: Set<String> = []) -> Bool { room(hiding: hidden) == 0 }
    public func room(hiding hidden: Set<String> = []) -> Int {
        max(0, Self.capacity - visibleEntries(hiding: hidden).count)
    }

    /// Whether playing this song should search for more art: the pool has room, and the song hasn't been
    /// searched yet (or found nothing a while ago).
    public func shouldSearch(song: String, hiding hidden: Set<String> = [], now: Date = .now) -> Bool {
        guard !isFull(hiding: hidden) else { return false }
        guard let search = searches[song] else { return true }
        return search.found == 0 && now.timeIntervalSince(search.date) > Self.emptySearchRetry
    }

    /// Up to `count` images for this play: never-shown first, then least recently shown; ties go to quality.
    public func selection(count: Int, hiding hidden: Set<String> = []) -> [Artwork] {
        visibleEntries(hiding: hidden)
            .sorted { a, b in
                let aShown = a.lastShown ?? .distantPast, bShown = b.lastShown ?? .distantPast
                if aShown != bShown { return aShown < bShown }
                return (a.artwork.qualityScore ?? -.infinity) > (b.artwork.qualityScore ?? -.infinity)
            }
            .prefix(count)
            .map(\.artwork)
    }

    /// Adds newly accepted images (ignoring ones already pooled) while there's room.
    public mutating func add(_ artworks: [Artwork], hiding hidden: Set<String> = []) {
        for artwork in artworks where room(hiding: hidden) > 0 && !entries.contains(where: { $0.artwork.id == artwork.id }) {
            entries.append(Entry(artwork: artwork, lastShown: nil))
        }
    }

    public mutating func recordSearch(song: String, found: Int, at date: Date = .now) {
        searches[song] = Search(date: date, found: found)
    }

    public mutating func markShown(_ id: Artwork.ID, at date: Date = .now) {
        if let index = entries.firstIndex(where: { $0.artwork.id == id }) {
            entries[index].lastShown = date
        }
    }

    /// Drops entries whose image file the cache has since evicted.
    public mutating func removeMissingFiles() {
        entries.removeAll { !FileManager.default.fileExists(atPath: $0.artwork.fileURL.path(percentEncoded: false)) }
    }
}
