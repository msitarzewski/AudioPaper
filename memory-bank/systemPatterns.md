# System Patterns

## Plugin protocols (AudioPaperKit)
- `NowPlayingSource` (`Sources/NowPlayingSource.swift`) — `events() -> AsyncStream<PlaybackEvent>`; registered in `SourceRegistry.standard`. Compiled-in; no dynamic bundles (library validation).
- `AlbumArtworkProvider` → ordered `AlbumArtworkChain` (iTunes → Cover Art Archive → Music app's own artwork, 800 px last resort).
- `FanArtSource` (fanart.tv, TheAudioDB, DeviantArt, Brave) → `FanArtPipeline`. Sources marked `isFallback` (Brave) are asked only when the primaries return fewer than 3 candidates. `ArtworkCandidate.isCurated` relaxes the size floor to 1280×720.
- `ArtworkFilter` — pipeline steps returning `.accept(score:)` / `.reject(reason)`.

## Fan-art pipeline (cheapest first)
reported size (`SizeFilter.accepts`) → download (`ArtworkCache`) → real size → `AestheticsFilter` (Vision `isUtility`, score ≥ −0.5) → `TextFilter` (accurate OCR, ≤1.5% area, ≤3 words) → `ClassificationFilter` (blocklist of real Vision identifiers ≥0.6 — screens/UI, advertising/retail, print/documents, products/mockups; a test checks each label exists; people and concert photos are allowed, per the user; `art`/`illustrations`/`painting`/`graffiti` add a ranking boost) → feature-print duplicate check (< 0.35) against accepted, album cover, and the current wallpaper. Results stream as they pass; the first is shown at once, and the rest of the rotation is sorted by `qualityScore` (aesthetics + art boost) when the search finishes.

## Relevance (Brave)
A result's title or page slug must name the artist, plus the song (1.0), the album (0.8), or a music word (0.6). Multi-word artist names alone count (0.5). This stops "Sleepover" (the band) from matching sleepover anime art.

## Coordinator flow (`NowPlayingCoordinator`)
playing → 1.5 s debounce → album cover (cached per album key; redrawn only when the album changes) → fan art (cached per song key, empty results remembered for 7 days) → rotation every `rotationInterval`. No cover for a new album → restore original wallpaper (never leave the wrong album up). Presentations are serialized; newer requests supersede queued ones.

## MusicBrainz
`MusicBrainz` (Support/MusicBrainz.swift) owns the shared 1 req/s limiter (used by the cover lookup too) and artist-name → MBID resolution. Several exact-name artists ≥90 score means ambiguous → nil (a wrong artist is worse than none).

## Preferences
New plugins must start enabled: fan-art sources are stored as `disabledFanArtSources`.

## Wallpaper
`WallpaperComposer` (Core Image): album = cover at 56% screen height over a blurred, saturated wash of itself. Fan art = `FanArtFraming` (automatic by default): fill when cropping ≤15%, otherwise fit at full height/width with feathered edges over a blurred edge-clamp extension (Apple has no public generative outpainting API). HEIC per screen at native pixel size.
`WallpaperService`: `FadeWindow` at desktop level +1 (below icons, click-through, all Spaces) fades in, then the real wallpaper is set and the window is removed. Originals are saved per display ID on first change. Reapplied on Space change.

## App surfaces (HIG-driven, 2026-09-25)
- Menu bar extra: native `.menu` style (HIG: menu, not popover), `MenuBarExtra(isInserted:)` bound to `showInMenuBar`.
- Mini Player: SwiftUI `Window` (id `mini-player`), hidden title bar with artwork under the traffic lights (Music's MiniPlayer precedent), real Liquid Glass background (`NSGlassEffectView`, window made non-opaque/clear), Float on Top / Show on All Desktops. `WindowConfigurator`'s `Probe` view applies window settings in `viewDidMoveToWindow` (updateNSView runs before the window exists), measures the hidden title bar (32pt on macOS 26) and gives it back at the bottom so the window hugs its content, and saves/restores the window's top-left (frame autosave names don't survive SwiftUI's placement). Open state persists in `Preferences.miniPlayerOpen` (quitting doesn't clear it). The "…" control is a real glass `Button` popping an `NSMenu`, because `Menu` doesn't take the glass button style.
- Dock: `AppDelegate` switches the activation policy: `.regular` while the Mini Player is open or the menu bar extra is hidden, `.accessory` otherwise. Reopen opens the Mini Player; `applicationDockMenu` mirrors the wallpaper actions; `applicationShouldTerminateAfterLastWindowClosed` returns false (SwiftUI otherwise quits a `Window`-only app with no windows).
- Widgets: `AudioPaperWidgets` extension. The app writes `WidgetSnapshot` + ≤800px JPEG thumbnails to the App Group (`$(DEVELOPMENT_TEAM).com.audiopaper`, name read from the `AudioPaperAppGroup` Info.plist key) on the coordinator's coalesced `onStateChange`, then reloads timelines. Widget buttons run `AppIntent`s in the extension that post Darwin notifications (`WidgetCommand`), which the app observes.

## Testing seams
`HTTPClient` (`StubHTTP`), `SecretStore` (`StubSecrets`), `WallpaperDisplay` (`RecordingDisplay`), manual `NowPlayingSource`. Fixtures are recorded real responses (iTunes, MusicBrainz, Brave) plus a documented-shape DeviantArt sample.
