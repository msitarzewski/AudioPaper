import AppKit
import Foundation
import Observation

/// Turns playback events into wallpapers: album cover first, then fan art as it passes the filters,
/// rotating through the fan art like a slideshow while the song plays.
@MainActor
@Observable
public final class NowPlayingCoordinator {
    public private(set) var track: Track? { didSet { stateChanged() } }
    public private(set) var isPlaying = false { didSet { stateChanged() } }
    public private(set) var albumArtwork: Artwork? { didSet { stateChanged() } }
    public private(set) var fanArt: [Artwork] = [] { didSet { stateChanged() } }
    /// The image AudioPaper is showing: the app (Mini Player, menu, widgets) switches to it at once, and the
    /// wallpaper follows as soon as it's rendered and cross-faded (`onDesktop`).
    public private(set) var showing: Artwork? { didSet { stateChanged() } }
    /// What the desktop actually shows, a moment behind `showing` while a new image renders and fades in.
    @ObservationIgnored private var onDesktop: Artwork?
    /// Whether an image is being rendered or faded in right now.
    @ObservationIgnored private var isPresenting = false
    public private(set) var isSearchingFanArt = false
    public private(set) var status = "Waiting for music"
    /// When true, playback is still tracked but the wallpaper is left alone.
    public var isSuspended = false {
        didSet {
            isSuspended ? stopRotation() : resume()
            stateChanged()
        }
    }

    /// Everything shown to people, in order: the album cover, then the fan art rotation.
    public var slides: [Artwork] {
        (albumArtwork.map { [$0] } ?? []) + fanArt
    }

    /// Called (coalesced, on the main actor) after anything people can see changes; the app uses it
    /// to refresh the shared widget snapshot.
    @ObservationIgnored public var onStateChange: (@MainActor () -> Void)?
    @ObservationIgnored private var stateChangePending = false

    private func stateChanged() {
        guard onStateChange != nil, !stateChangePending else { return }
        stateChangePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stateChangePending = false
            self.onStateChange?()
        }
    }

    public let preferences: Preferences

    @ObservationIgnored private let registry: SourceRegistry
    @ObservationIgnored private let albumChain: AlbumArtworkChain
    @ObservationIgnored private let fanArtSources: [any FanArtSource]
    @ObservationIgnored private let cache: ArtworkCache
    @ObservationIgnored private let composer: WallpaperComposer
    @ObservationIgnored private let display: any WallpaperDisplay
    @ObservationIgnored private let debounce: Duration
    /// How long a new song's cover stays up before the fan art takes over: a placeholder while the
    /// artist's images load, not a full slide.
    @ObservationIgnored private let coverHold: Duration

    @ObservationIgnored private var albumKey: String?
    /// The pool the current song's fan art belongs to, so shown images can be recorded.
    @ObservationIgnored private var poolKey: String?
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
        debounce: Duration = .milliseconds(1500),
        coverHold: Duration = .seconds(10)
    ) {
        self.registry = registry
        self.albumChain = albumChain
        self.fanArtSources = fanArtSources
        self.cache = cache
        self.composer = composer
        self.display = display
        self.preferences = preferences
        self.debounce = debounce
        self.coverHold = coverHold
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
        Task {
            await MusicBrainz.rememberArtistIDs(in: cache.artistIDsFile)
            await pruneCache()
        }
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

    // MARK: Cache

    public func cacheSize() async -> Int {
        await cache.size()
    }

    /// Clears downloaded artwork and remembered search results, keeping what's on screen right now.
    public func clearCache() async {
        await cache.clear(keeping: Set(slides.map(\.fileURL)))
    }

    /// Trims the cache to the configured limit, never removing what's on screen.
    public func pruneCache() async {
        await cache.prune(maxBytes: preferences.cacheLimitBytes, keeping: Set(slides.map(\.fileURL)))
    }

    public func showNext() {
        guard let next = nextInRotation() else { return }
        show(next)
    }

    public func restoreOriginalWallpaper() {
        stopRotation()
        presentation?.cancel()
        presentationGeneration += 1
        isPresenting = false
        display.restoreOriginals()
        showing = nil
        onDesktop = nil
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
            // The previous song's slideshow ends now, not after the lookup.
            stopRotation()
            fanArt = []
            trackTask = Task { [weak self, debounce] in
                // A cover that's already downloaded goes up at once: the app first, the wallpaper right after.
                // Otherwise the old song's art is cleared, rather than lingering while the new cover is found.
                await self?.showCachedCover(for: newTrack)
                // Skipping through tracks quickly shouldn't trigger a network lookup for each one.
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
        if albumKey != track.albumKey {
            albumArtwork = await resolveAlbum(for: track)
            albumKey = track.albumKey
        }
        guard !Task.isCancelled else { return }
        if let albumArtwork {
            if showing != albumArtwork { present(albumArtwork, animated: true) }
        } else {
            status = "No cover found for “\(track.album)”"
            // Don't leave the previous album's art up for a different record — including one still on its
            // way to the desktop, which restoring cancels.
            if onDesktop != nil || isPresenting { restoreOriginalWallpaper() }
        }
        guard preferences.mode == .albumThenFanArt else { return }
        // The cover holds the place for a few seconds while the artist's images load; then the fan art takes over.
        startRotation(firstAfter: coverHold)
        await loadFanArt(for: track)
    }

    /// On a song change: puts the new album's cover up straight away when it's already downloaded (no
    /// network), otherwise clears the previous song's art from the app.
    private func showCachedCover(for track: Track) async {
        if track.albumKey == albumKey, let albumArtwork {
            if showing != albumArtwork { present(albumArtwork, animated: true) }
            return
        }
        guard !track.album.isEmpty, let cached = await cache.artworks(forKey: "album:" + track.albumKey)?.first else {
            showing = nil
            return
        }
        guard !Task.isCancelled else { return }
        albumArtwork = cached
        albumKey = track.albumKey
        present(cached, animated: true)
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

    private var searchBudget = SearchBudget()

    /// Images shown per play of a song; the artist's pool can hold more (`ArtistPool.capacity`).
    public static let imagesPerPlay = 8

    static func poolKey(for track: Track) -> String {
        "pool:v\(FanArtPipeline.version):" + MusicBrainz.identityKey(track.artist)
    }

    /// Shows this play's selection from the artist's pool at once, then — only if this song hasn't been
    /// searched yet and the pool has room — searches, adding new finds to the rotation and the pool.
    private func loadFanArt(for track: Track) async {
        let key = Self.poolKey(for: track)
        poolKey = key
        let pool = await cache.pool(forKey: key)
        fanArt = pool.selection(count: Self.imagesPerPlay)
        // Fan art waits its turn after the cover; it goes up at once only when there's no cover to show.
        if albumArtwork == nil, let first = fanArt.first { present(first, animated: true) }
        guard pool.shouldSearch(song: track.songKey) else { return }

        // New-song searches are budgeted, so a flood of track changes (a process spoofing Music's
        // notification, say) can't spend a metered quota. Over budget, the song is simply searched on a
        // later play; nothing is recorded.
        guard searchBudget.allow() else {
            log.info("Search budget reached; not searching this song now")
            return
        }
        let enabled = fanArtSources.filter { !preferences.disabledFanArtSources.contains($0.id) }
        // `isConfigured` reads the Keychain, which can block on an access prompt; keep it off the main thread.
        let sources = await Task.detached { enabled.filter(\.isConfigured) }.value
        guard !sources.isEmpty else { return }

        isSearchingFanArt = true
        defer { isSearchingFanArt = false }
        // Nothing that looks like the album cover, what's on screen, or an image already pooled.
        let lookalikes = ([albumArtwork, showing].compactMap { $0 } + pool.artworks)
            .compactMap { ImageLoading.image(at: $0.fileURL, maxPixelSize: 512) }
        var pipeline = FanArtPipeline(sources: sources, cache: cache)
        pipeline.maxAccepted = min(Self.imagesPerPlay, pool.room)
        var found: [Artwork] = []
        var complete = true
        for await event in pipeline.run(for: track, excluding: lookalikes, known: Set(pool.artworks.map(\.candidate.imageURL))) {
            guard !Task.isCancelled else { return }
            switch event {
            case let .accepted(artwork):
                found.append(artwork)
                fanArt.append(artwork)
                if albumArtwork == nil, showing == nil { present(artwork, animated: true) }
            case .incomplete:
                complete = false
            case .rejected:
                break
            }
        }
        // Skipped mid-search: the stream ends early, so this song hasn't really been searched.
        guard !Task.isCancelled else { return }
        // New finds join the rotation after this play's selection, best first.
        let selected = fanArt.count - found.count
        fanArt = Array(fanArt.prefix(selected)) + fanArt.dropFirst(selected).sorted { ($0.qualityScore ?? -.infinity) > ($1.qualityScore ?? -.infinity) }
        let finds = found
        let searchedFully = complete
        _ = try? await cache.updatePool(forKey: key) { pool in
            pool.add(finds)
            // A source that was offline or rate limited may have art for this song: search it again next
            // play (images already pooled are skipped) rather than remembering it as found-nothing.
            if searchedFully { pool.recordSearch(song: track.songKey, found: finds.count) }
        }
        await pruneCache()
    }

    // MARK: Presentation

    /// Renders and shows `artwork`. Requests are serialized; a newer request supersedes queued ones.
    private func present(_ artwork: Artwork, animated: Bool) {
        guard !isSuspended else { return }
        presentationGeneration += 1
        let generation = presentationGeneration
        // The app shows it now; the wallpaper follows once it's rendered.
        showing = artwork
        isPresenting = true
        let previous = presentation
        let composer = self.composer
        let framing = preferences.fanArtFraming
        presentation = Task { [weak self] in
            await previous?.value
            guard let self, generation == self.presentationGeneration else { return }
            defer { if generation == self.presentationGeneration { self.isPresenting = false } }
            let screens = self.display.screens
            let files: [UInt32: URL]
            do {
                files = try await Task.detached(priority: .userInitiated) {
                    try composer.render(artwork, for: screens, framing: framing)
                }.value
            } catch {
                log.error("Render failed: \(error.localizedDescription, privacy: .public)")
                // The app shouldn't claim an image the desktop never got.
                if generation == self.presentationGeneration { self.showing = self.onDesktop }
                return
            }
            guard generation == self.presentationGeneration else { return }
            await self.display.show(files, animated: animated && self.onDesktop != nil)
            self.onDesktop = artwork
            self.recordShown(artwork)
            composer.prune(keeping: Set(files.values))
        }
    }

    /// Notes when a pooled image was last on screen, so the next play favours others.
    private func recordShown(_ artwork: Artwork) {
        guard artwork.candidate.kind == .fanArt, let key = poolKey else { return }
        let cache = self.cache
        Task { try? await cache.updatePool(forKey: key) { $0.markShown(artwork.id) } }
    }

    private func nextInRotation() -> Artwork? {
        guard !fanArt.isEmpty else { return nil }
        guard let showing, let index = fanArt.firstIndex(of: showing) else { return fanArt.first }
        return fanArt[(index + 1) % fanArt.count]
    }

    /// Rotates through the fan art every `rotationInterval`; the first change can come sooner (`firstAfter`),
    /// as when a new song's cover is only holding the place.
    private func startRotation(firstAfter first: Duration? = nil) {
        stopRotation()
        guard isPlaying, !isSuspended else { return }
        rotationTask = Task { [weak self] in
            var delay = first
            while !Task.isCancelled {
                let interval = Duration.seconds(self?.preferences.rotationInterval ?? 45)
                try? await Task.sleep(for: delay.map { min($0, interval) } ?? interval)
                delay = nil
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

/// At most `limit` new-song searches in any `window`. Generous for real listening, even skipping through a
/// playlist; bounds what a flood of fake track changes could cost.
struct SearchBudget {
    var limit: Int
    var window: Duration
    private var recent: [ContinuousClock.Instant] = []

    init(limit: Int = 60, window: Duration = .seconds(3600)) {
        self.limit = limit
        self.window = window
    }

    mutating func allow(at now: ContinuousClock.Instant = .now) -> Bool {
        recent.removeAll { now - $0 >= window }
        guard recent.count < limit else { return false }
        recent.append(now)
        return true
    }
}
