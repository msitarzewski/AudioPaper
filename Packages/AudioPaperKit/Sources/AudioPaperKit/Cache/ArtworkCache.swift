import CryptoKit
import Foundation
import ImageIO

/// On-disk store for downloaded images and the accepted-artwork list per album/song key.
public actor ArtworkCache {
    public let root: URL
    private let http: any HTTPClient
    private var imagesDir: URL { root.appending(path: "images", directoryHint: .isDirectory) }
    private var indexDir: URL { root.appending(path: "index", directoryHint: .isDirectory) }

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
        if candidate.imageURL.isFileURL {
            // Artwork a player handed us locally; copy it so it lives as long as the cache entry.
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.copyItem(at: candidate.imageURL, to: file)
        } else if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            var request = URLRequest(url: candidate.imageURL, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, _) = try await http.data(for: request)
            try data.write(to: file, options: .atomic)
        }
        guard let size = ImageLoading.pixelSize(of: file) else {
            try? FileManager.default.removeItem(at: file)
            throw CocoaError(.fileReadCorruptFile)
        }
        return (file, size.width, size.height)
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

    /// When the list for `key` was last stored, so an empty result can be trusted for a while.
    public func storedDate(forKey key: String) -> Date? {
        let file = indexDir.appending(path: Self.hash(key) + ".json")
        return try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    public func store(_ artworks: [Artwork], forKey key: String) throws {
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(artworks)
        try data.write(to: indexDir.appending(path: Self.hash(key) + ".json"), options: .atomic)
    }

    /// Removes least-recently-modified images until the image folder is under `maxBytes`.
    public func prune(maxBytes: Int = 500_000_000) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: keys) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries where total > maxBytes {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }

    public static func hash(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// ImageIO helpers shared by the cache, the fan-art filters, and the wallpaper composer.
public enum ImageLoading {
    public static func pixelSize(of file: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        // EXIF orientations 5–8 are rotated 90°, so the displayed size is transposed.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (height, width) : (width, height)
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
