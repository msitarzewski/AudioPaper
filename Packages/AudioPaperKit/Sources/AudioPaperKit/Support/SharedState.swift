import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the widgets show: the playing track and the wallpaper images, shared through the App Group.
///
/// The app writes it whenever playback or the wallpaper changes; the widget extension only reads it.
/// Images are small JPEG thumbnails in the group container, since widgets can't load large files.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Image: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        /// File name inside the shared thumbnails folder.
        public var file: String
        public var kind: ArtworkKind
        public var title: String?
        public var creatorName: String?
        public var sourceName: String
        public var pageURL: URL?
        public var creatorProfileURL: URL?
        /// One-line credit, e.g. "Photo by Yan Mayen · CC BY-SA 4.0" (`ArtworkCandidate.shortCredit`).
        public var credit: String
    }

    public var track: Track?
    public var isPlaying: Bool
    public var isSuspended: Bool
    public var showing: Image?
    /// The album cover followed by the fan art in rotation order.
    public var slides: [Image]
    public var updated: Date

    public static let empty = WidgetSnapshot(track: nil, isPlaying: false, isSuspended: false, showing: nil, slides: [], updated: .distantPast)
}

/// Reads and writes `WidgetSnapshot` in the App Group container named by the `AudioPaperAppGroup`
/// Info.plist key (set from the build's team prefix, so forks signing with another team just work).
public enum SharedStore {
    static let snapshotName = "snapshot.json"
    static let thumbnailsName = "Thumbnails"
    public static let thumbnailPixelSize = 800

    public static var groupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "AudioPaperAppGroup") as? String
    }

    public static var container: URL? {
        groupIdentifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    public static func read(from container: URL? = SharedStore.container) -> WidgetSnapshot {
        guard let container,
              let data = try? Data(contentsOf: container.appending(path: snapshotName)),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    public static func thumbnail(_ image: WidgetSnapshot.Image, in container: URL? = SharedStore.container) -> CGImage? {
        guard let container else { return nil }
        return ImageLoading.image(at: container.appending(path: thumbnailsName).appending(path: image.file))
    }

    /// Writes the snapshot, creating thumbnails for any image not already shared and removing stale ones.
    public static func write(
        track: Track?, isPlaying: Bool, isSuspended: Bool,
        showing: Artwork?, slides: [Artwork],
        to container: URL? = SharedStore.container
    ) throws {
        guard let container else { return }
        let folder = container.appending(path: thumbnailsName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        func share(_ artwork: Artwork) -> WidgetSnapshot.Image? {
            let file = ArtworkCache.hash(artwork.id) + ".jpg"
            let target = folder.appending(path: file)
            if !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
                guard let image = ImageLoading.image(at: artwork.fileURL, maxPixelSize: thumbnailPixelSize),
                      let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
                else { return nil }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { return nil }
            }
            let attribution = artwork.candidate.attribution
            return WidgetSnapshot.Image(
                id: artwork.id, file: file, kind: artwork.candidate.kind,
                title: attribution.title, creatorName: attribution.creatorName, sourceName: attribution.sourceName,
                pageURL: attribution.pageURL, creatorProfileURL: attribution.creatorProfileURL,
                credit: artwork.candidate.shortCredit
            )
        }

        let shared = slides.compactMap(share)
        let snapshot = WidgetSnapshot(
            track: track, isPlaying: isPlaying, isSuspended: isSuspended,
            showing: showing.flatMap { current in shared.first { $0.id == current.id } ?? share(current) },
            slides: shared, updated: .now
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: container.appending(path: snapshotName), options: .atomic)

        let keep = Set(shared.map(\.file) + [snapshot.showing?.file].compactMap { $0 })
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [] where !keep.contains(file) {
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
    }
}

/// Where a click on a widget takes people (HIG: open the app to the related content). The app registers
/// the `audiopaper` URL scheme and opens the Mini Player for it.
public enum WidgetLink {
    public static let scheme = "audiopaper"
    public static let miniPlayer = URL(string: "audiopaper://mini-player")!
}

/// Commands from widget buttons to the app. Widget intents run in the extension's process, so they
/// signal the app with a Darwin notification (no payload), which sandboxed processes may post.
public enum WidgetCommand: String, CaseIterable, Sendable {
    case next = "com.audiopaper.command.next"
    case togglePause = "com.audiopaper.command.toggle-pause"

    public func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue as CFString), nil, nil, true
        )
    }

    /// Calls `handler` on the main queue for every command. Keep the returned token alive.
    public static func observe(_ handler: @escaping @MainActor (WidgetCommand) -> Void) -> Observation {
        Observation(handler: handler)
    }

    public final class Observation: @unchecked Sendable {
        private let handler: @MainActor (WidgetCommand) -> Void

        init(handler: @escaping @MainActor (WidgetCommand) -> Void) {
            self.handler = handler
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let observer = Unmanaged.passUnretained(self).toOpaque()
            for command in WidgetCommand.allCases {
                CFNotificationCenterAddObserver(center, observer, { _, observer, name, _, _ in
                    guard let observer, let raw = name?.rawValue as String?, let command = WidgetCommand(rawValue: raw) else { return }
                    let observation = Unmanaged<Observation>.fromOpaque(observer).takeUnretainedValue()
                    DispatchQueue.main.async { MainActor.assumeIsolated { observation.handler(command) } }
                }, command.rawValue as CFString, nil, .deliverImmediately)
            }
        }

        deinit {
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
        }
    }
}
