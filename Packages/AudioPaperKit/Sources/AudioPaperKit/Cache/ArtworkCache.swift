import CryptoKit
import Foundation
import ImageIO

/// On-disk store for downloaded images and the accepted-artwork list per album/song key.
public actor ArtworkCache {
    public let root: URL
    private let http: any HTTPClient
    private var imagesDir: URL { root.appending(path: "images", directoryHint: .isDirectory) }
    private var indexDir: URL { root.appending(path: "index", directoryHint: .isDirectory) }

    /// Remembered artist identities (see `MusicBrainz.rememberArtistIDs`); inside the index, so clearing
    /// the cache forgets them along with the search results.
    public var artistIDsFile: URL { indexDir.appending(path: "artist-ids.json") }

    public init(root: URL = ArtworkCache.defaultRoot, http: any HTTPClient = URLSessionHTTPClient()) {
        self.root = root
        self.http = http
    }

    public static var defaultRoot: URL {
        URL.cachesDirectory.appending(path: "AudioPaper", directoryHint: .isDirectory)
    }

    /// Downloads `candidate` unless already cached; returns the local file and its true pixel size.
    public func download(_ candidate: ArtworkCandidate) async throws -> (URL, width: Int, height: Int) {
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let file = imagesDir.appending(path: Self.hash(candidate.imageURL.absoluteString))
        let isLocal = candidate.isLocal && candidate.imageURL.isFileURL
        if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)), !isLocal {
            // Reused: mark it recently used, so pruning removes images that haven't been needed longest.
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path(percentEncoded: false))
        } else if isLocal {
            // Artwork a player handed us locally; copy it so it lives as long as the cache entry.
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.copyItem(at: candidate.imageURL, to: file)
        } else {
            // The HTTP client refuses anything but https to a named host, so a `file:` or LAN address in a
            // response never reaches the disk or the network.
            var request = URLRequest(url: candidate.imageURL, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, _) = try await http.data(for: request)
            try data.write(to: file, options: .atomic)
        }
        // Checked from the header alone, before anything decodes the pixels.
        guard let info = ImageLoading.inspect(file), info.isSafeToDecode else {
            try? FileManager.default.removeItem(at: file)
            throw CocoaError(.fileReadCorruptFile)
        }
        return (file, info.width, info.height)
    }

    public func artworks(forKey key: String) -> [Artwork]? {
        let file = indexDir.appending(path: Self.hash(key) + ".json")
        guard let data = try? Data(contentsOf: file),
              let artworks = try? JSONDecoder().decode([Artwork].self, from: data)
        else { return nil }
        // Entries whose image was evicted are dropped rather than returned broken.
        let present = artworks.filter { FileManager.default.fileExists(atPath: $0.fileURL.path(percentEncoded: false)) }
        return present.count == artworks.count ? present : nil
    }

    /// The artist's fan-art pool, minus any images the cache has since evicted.
    public func pool(forKey key: String) -> ArtistPool {
        let file = indexDir.appending(path: Self.hash(key) + ".pool.json")
        guard let data = try? Data(contentsOf: file), var pool = try? JSONDecoder().decode(ArtistPool.self, from: data) else {
            return ArtistPool()
        }
        pool.removeMissingFiles()
        return pool
    }

    /// Reads, changes and writes a pool in one step, so concurrent updates (a search adding images while
    /// the rotation records what was shown) can't overwrite each other.
    @discardableResult
    public func updatePool(forKey key: String, _ change: @Sendable (inout ArtistPool) -> Void) throws -> ArtistPool {
        var pool = pool(forKey: key)
        change(&pool)
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(pool).write(to: indexDir.appending(path: Self.hash(key) + ".pool.json"), options: .atomic)
        return pool
    }

    public func store(_ artworks: [Artwork], forKey key: String) throws {
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(artworks)
        try data.write(to: indexDir.appending(path: Self.hash(key) + ".json"), options: .atomic)
    }

    /// Total bytes on disk: downloaded images plus the per-album and per-song result lists.
    public func size() -> Int {
        [imagesDir, indexDir].reduce(0) { total, dir in
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return total + files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
    }

    /// Removes least-recently-used images until the image folder is under `maxBytes`, never touching `keeping`
    /// (the images on screen). "Used" is the file's modification date, refreshed whenever a cached image is reused.
    public func prune(maxBytes: Int, keeping: Set<URL> = []) {
        let keep = Set(keeping.map { $0.standardizedFileURL.path(percentEncoded: false) })
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: keys) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries where total > maxBytes && !keep.contains(url.standardizedFileURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }

    /// Deletes every cached image except `keeping`, and every remembered search result, so songs are
    /// searched afresh next time they play.
    public func clear(keeping: Set<URL> = []) {
        try? FileManager.default.removeItem(at: indexDir)
        let keep = Set(keeping.map { $0.standardizedFileURL.path(percentEncoded: false) })
        let files = (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keep.contains(file.standardizedFileURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    public static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// ImageIO helpers shared by the cache, the fan-art filters, and the wallpaper composer.
public enum ImageLoading {
    /// What an image file claims to be, read from its header without decoding any pixels.
    public struct Info: Sendable {
        public var width: Int
        public var height: Int
        public var type: String

        /// Formats AudioPaper decodes: the ones image services actually serve. Everything else is refused,
        /// which keeps rarely used decoders away from untrusted bytes.
        public static let allowedTypes: Set<String> = [
            "public.jpeg", "public.png", "public.heic", "public.heif", "org.webmproject.webp", "public.tiff",
        ]
        /// A decoded image costs 4 bytes a pixel; 50 megapixels (200 MB) is ample for a 6K display and far
        /// below what a "decompression bomb" — a small file claiming enormous dimensions — would ask for.
        public static let maxPixels = 50_000_000
        public static let maxEdge = 16_384

        public var isSafeToDecode: Bool {
            Self.allowedTypes.contains(type) && width > 0 && height > 0
                && width <= Self.maxEdge && height <= Self.maxEdge && width * height <= Self.maxPixels
        }
    }

    public static func inspect(_ file: URL) -> Info? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let type = CGImageSourceGetType(source) as String?,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // EXIF orientations 5–8 are rotated 90°, so the displayed size is transposed.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? Info(width: height, height: width, type: type) : Info(width: width, height: height, type: type)
    }

    public static func pixelSize(of file: URL) -> (width: Int, height: Int)? {
        inspect(file).map { ($0.width, $0.height) }
    }

    /// Decodes image data from anywhere (an avatar, say) as a small thumbnail, or nil if it isn't a
    /// format AudioPaper accepts or claims unreasonable dimensions.
    public static func thumbnail(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?, Info.allowedTypes.contains(type),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              Info(width: width, height: height, type: type).isSafeToDecode
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Decodes a file, downsampled so its longest edge is at most `maxPixelSize`, with orientation applied.
    public static func image(at file: URL, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        } else if let size = pixelSize(of: file) {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(size.width, size.height)
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
