# System Patterns

## Plugin protocols (AudioPaperKit)
- `NowPlayingSource` (`Sources/NowPlayingSource.swift`) — `events() -> AsyncStream<PlaybackEvent>`; registered in `SourceRegistry.standard`. Compiled-in; no dynamic bundles (library validation).
- `AlbumArtworkProvider` → ordered `AlbumArtworkChain` (iTunes → Cover Art Archive → Music app's own artwork, 800 px last resort).
- `FanArtSource` (TheAudioDB, DeviantArt, Brave) → `FanArtPipeline`. Sources marked `isFallback` (Brave) are asked only when the primaries return fewer than 3 candidates. `ArtworkCandidate.isCurated` relaxes the size floor to 1280×720.
- `ArtworkFilter` — pipeline steps returning `.accept(score:)` / `.reject(reason)`.

## Fan-art pipeline (cheapest first)
reported size (`SizeFilter.accepts`) → download (`ArtworkCache`) → real size → `AestheticsFilter` (Vision `isUtility`, score ≥ −0.5) → `TextFilter` (accurate OCR, ≤1.5% area, ≤3 words) → `ClassificationFilter` (blocklist of real Vision identifiers ≥0.6 — screens/UI, advertising/retail, print/documents, products/mockups; a test checks each label exists; people and concert photos are allowed, per the user; `art`/`illustrations`/`painting`/`graffiti` add a ranking boost) → feature-print duplicate check (< 0.35) against accepted, album cover, and the current wallpaper. Results stream as they pass; the first is shown at once, and the rest of the rotation is sorted by `qualityScore` (aesthetics + art boost) when the search finishes.

## Relevance (Brave)
A result's title or page slug must name the artist, plus the song (1.0), the album (0.8), or a music word (0.6). Multi-word artist names alone count (0.5). This stops "Sleepover" (the band) from matching sleepover anime art.

## Coordinator flow (`NowPlayingCoordinator`)
playing → 1.5 s debounce → album cover (cached per album key; redrawn only when the album changes) → fan art (cached per song key, empty results remembered for 7 days) → rotation every `rotationInterval`. No cover for a new album → restore original wallpaper (never leave the wrong album up). Presentations are serialized; newer requests supersede queued ones.

## Preferences
New plugins must start enabled: fan-art sources are stored as `disabledFanArtSources`.

## Wallpaper
`WallpaperComposer` (Core Image): album = cover at 56% screen height over a blurred, saturated wash of itself. Fan art = `FanArtFraming` (automatic by default): fill when cropping ≤15%, otherwise fit at full height/width with feathered edges over a blurred edge-clamp extension (Apple has no public generative outpainting API). HEIC per screen at native pixel size.
`WallpaperService`: `FadeWindow` at desktop level +1 (below icons, click-through, all Spaces) fades in, then the real wallpaper is set and the window is removed. Originals are saved per display ID on first change. Reapplied on Space change.

## Testing seams
`HTTPClient` (`StubHTTP`), `SecretStore` (`StubSecrets`), `WallpaperDisplay` (`RecordingDisplay`), manual `NowPlayingSource`. Fixtures are recorded real responses (iTunes, MusicBrainz, Brave) plus a documented-shape DeviantArt sample.
