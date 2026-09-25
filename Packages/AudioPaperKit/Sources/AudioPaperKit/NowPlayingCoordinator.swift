import AppKit
import Foundation
import Observation

/// Turns playback events into wallpapers: album cover first, then fan art as it passes the filters,
/// rotating through the fan art like a slideshow while the song plays.
@MainActor
@Observable
public final class NowPlayingCoordinator {
    public private(set) var track: Track?
    public private(set) var isPlaying = false
    public private(set) var albumArtwork: Artwork?
    public private(set) var fanArt: [Artwork] = []
    public private(set) var showing: Artwork?
    public private(set) var isSearchingFanArt = false
    public private(set) var status = "Waiting for music"
    /// When true, playback is still tracked but the wallpaper is left alone.
    public var isSuspended = false {
        didSet { isSuspended ? stopRotation() : resume() }
    }

    public let preferences: Preferences

    @ObservationIgnored private let registry: SourceRegistry
    @ObservationIgnored private let albumChain: AlbumArtworkChain
    @ObservationIgnored private let fanArtSources: [any FanArtSource]
    @ObservationIgnored private let cache: ArtworkCache
    @ObservationIgnored private let composer: WallpaperComposer
    @ObservationIgnored private let display: any WallpaperDisplay
    @ObservationIgnored private let debounce: Duration

    @ObservationIgnored private var albumKey: String?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var trackTask: Task<Void, Never>?
    @ObservationIgnored private var rotationTask: Task<Void, Never>?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var presentation: Task<Void, Never>?
    @ObservationIgnored private var presentationGeneration = 0
    @ObservationIgnored private var screenObserver: (any NSObjectProtocol)?

    public init(
        registry: SourceRegistry = .standard,
        albumChain: AlbumArtworkChain,
        fanArtSources: [any FanArtSource],
        cache: ArtworkCache = ArtworkCache(),
        composer: WallpaperComposer = WallpaperComposer(),
        display: any WallpaperDisplay,
        preferences: Preferences,
        debounce: Duration = .milliseconds(1500)
    ) {
        self.registry = registry
        self.albumChain = albumChain
        self.fanArtSources = fanArtSources
        self.cache = cache
        self.composer = composer
        self.display = display
        self.preferences = preferences
        self.debounce = debounce
    }

    public var availableSources: [any NowPlayingSource] { registry.available }
    public var allFanArtSources: [any FanArtSource] { fanArtSources }

    // MARK: Lifecycle

    public func start() {
        restartEvents()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let showing = self.showing else { return }
                self.present(showing, animated: false)
            }
        }
        Task { await cache.prune() }
    }

    /// Re-subscribes after the enabled players change.
    public func restartEvents() {
        eventsTask?.cancel()
        let stream = registry.events(enabled: preferences.enabledSources)
        eventsTask = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
    }

    // MARK: User actions

    /// Shows a specific image now (from the menu's filmstrip) and restarts the rotation clock.
    public func show(_ artwork: Artwork) {
        present(artwork, animated: true)
        startRotation()
    }

    /// Re-renders what's on screen, e.g. after the framing setting changes.
    public func refresh() {
        guard let showing else { return }
        present(showing, animated: true)
    }

    public func showNext() {
        guard let next = nextInRotation() else { return }
        show(next)
    }

    public func restoreOriginalWallpaper() {
        stopRotation()
        presentation?.cancel()
        presentationGeneration += 1
        display.restoreOriginals()
        showing = nil
        status = "Original wallpaper restored"
    }

    // MARK: Playback

    func handle(_ event: PlaybackEvent) {
        switch event {
        case let .playing(newTrack):
            isPlaying = true
            restoreTask?.cancel()
            if newTrack.songKey == track?.songKey, showing != nil {
                startRotation()
                return
            }
            track = newTrack
            status = "Now playing"
            trackTask?.cancel()
            trackTask = Task { [weak self, debounce] in
                // Skipping through tracks quickly shouldn't trigger a lookup for each one.
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
                await self?.load(newTrack)
            }
        case .paused, .stopped:
            isPlaying = false
            stopRotation()
            if case .stopped = event { trackTask?.cancel() }
            status = "Paused"
            scheduleRestoreIfNeeded()
        }
    }

    private func load(_ track: Track) async {
        fanArt = []
        if albumKey != track.albumKey {
            albumArtwork = await resolveAlbum(for: track)
            albumKey = track.albumKey
        }
        guard !Task.isCancelled else { return }
        if let albumArtwork {
            if showing != albumArtwork { present(albumArtwork, animated: true) }
        } else {
            status = "No cover found for “\(track.album)”"
            // Don't leave the previous album's art up for a different record.
            if showing != nil { restoreOriginalWallpaper() }
        }
        guard preferences.mode == .albumThenFanArt else { return }
        await loadFanArt(for: track)
        guard !Task.isCancelled else { return }
        startRotation()
    }

    private func resolveAlbum(for track: Track) async -> Artwork? {
        guard !track.album.isEmpty else { return nil }
        let key = "album:" + track.albumKey
        if let cached = await cache.artworks(forKey: key)?.first { return cached }
        guard let candidate = await albumChain.artwork(for: track) else { return nil }
        do {
            let (file, width, height) = try await cache.download(candidate)
            let artwork = Artwork(candidate: candidate, fileURL: file, pixelWidth: width, pixelHeight: height)
            try await cache.store([artwork], forKey: key)
            return artwork
        } catch {
            log.error("Cover download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func loadFanArt(for track: Track) async {
        let key = "fanart:" + track.songKey
        if let cached = await cache.artworks(forKey: key) {
            if let first = cached.first {
                fanArt = cached
                present(first, animated: true)
                return
            }
            // "Nothing found" is remembered for a week so obscure songs don't spend search quota on every play.
            if let searched = await cache.storedDate(forKey: key), searched.timeIntervalSinceNow > -7 * 24 * 3600 { return }
        }
        let enabled = fanArtSources.filter { !preferences.disabledFanArtSources.contains($0.id) }
        // `isConfigured` reads the Keychain, which can block on an access prompt; keep it off the main thread.
        let sources = await Task.detached { enabled.filter(\.isConfigured) }.value
        guard !sources.isEmpty else { return }

        isSearchingFanArt = true
        defer { isSearchingFanArt = false }
        // Skip the album cover and whatever is on screen, so the first fan art is a visible change.
        let exclude = [albumArtwork, showing].compactMap { $0 }.compactMap { ImageLoading.image(at: $0.fileURL, maxPixelSize: 1024) }
        let pipeline = FanArtPipeline(sources: sources, cache: cache)
        for await event in pipeline.run(for: track, excluding: exclude) {
            guard !Task.isCancelled else { return }
            if case let .accepted(artwork) = event {
                fanArt.append(artwork)
                if fanArt.count == 1 { present(artwork, animated: true) }
            }
        }
        // The first image went up as soon as it passed; the rest of the rotation runs best-first.
        fanArt.sort { ($0.qualityScore ?? -.infinity) > ($1.qualityScore ?? -.infinity) }
        try? await cache.store(fanArt, forKey: key)
    }

    // MARK: Presentation

    /// Renders and shows `artwork`. Requests are serialized; a newer request supersedes queued ones.
    private func present(_ artwork: Artwork, animated: Bool) {
        guard !isSuspended else { return }
        presentationGeneration += 1
        let generation = presentationGeneration
        let previous = presentation
        let composer = self.composer
        let framing = preferences.fanArtFraming
        presentation = Task { [weak self] in
            await previous?.value
            guard let self, generation == self.presentationGeneration else { return }
            let screens = self.display.screens
            let files: [UInt32: URL]
            do {
                files = try await Task.detached(priority: .userInitiated) {
                    try composer.render(artwork, for: screens, framing: framing)
                }.value
            } catch {
                log.error("Render failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard generation == self.presentationGeneration else { return }
            await self.display.show(files, animated: animated && self.showing != nil)
            self.showing = artwork
            composer.prune(keeping: Set(files.values))
        }
    }

    private func nextInRotation() -> Artwork? {
        guard !fanArt.isEmpty else { return nil }
        guard let showing, let index = fanArt.firstIndex(of: showing) else { return fanArt.first }
        return fanArt[(index + 1) % fanArt.count]
    }

    private func startRotation() {
        stopRotation()
        guard isPlaying, !isSuspended else { return }
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.preferences.rotationInterval ?? 45
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                if self.fanArt.count > 1 || (self.fanArt.count == 1 && self.showing != self.fanArt.first),
                   let next = self.nextInRotation() {
                    self.present(next, animated: true)
                }
            }
        }
    }

    private func stopRotation() {
        rotationTask?.cancel()
        rotationTask = nil
    }

    private func resume() {
        if let showing {
            present(showing, animated: true)
        } else if let albumArtwork {
            present(albumArtwork, animated: true)
        }
        startRotation()
    }

    private func scheduleRestoreIfNeeded() {
        restoreTask?.cancel()
        guard preferences.restoreWhenStopped else { return }
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, !self.isPlaying else { return }
            self.restoreOriginalWallpaper()
        }
    }
}
