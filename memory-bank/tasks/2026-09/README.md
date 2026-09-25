# 2026-09

## Tasks Completed

### 2026-09-25: AudioPaper v0.1
- Built the app end to end: Apple Music source, album cover chain, TheAudioDB/DeviantArt/Brave fan art with Vision filtering, cross-fade slideshow, Settings, icon; published as a public MIT repo.
- Files: `Packages/AudioPaperKit/`, `App/`, `project.yml`, repo docs
- Pattern: plugin protocols + cheapest-first pipeline
- See: [260925_audiopaper-v0.1.md](./260925_audiopaper-v0.1.md)

### 2026-09-25: fanart.tv source
- Added `FanartTVSource` (4K + 1080p artist backgrounds) and shared `MusicBrainz` artist-ID resolution with an ambiguity guard; cover lookups now share the MusicBrainz rate limiter.
- Files: `FanArt/FanartTVSource.swift`, `Support/MusicBrainz.swift`, Settings → Accounts, tests + fixtures

### 2026-09-25: HIG pass — menu, Mini Player, widgets, Dock, icons
- Menu bar extra became a native menu; the popover design moved to a Music-style Mini Player window; WidgetKit extension with Now Playing and Artwork widgets over an App Group snapshot; Dock icon only while needed; camera app icon (vector gradients, five palettes, red shipped) and template menu bar icon.
- Fixes on the way: popover layout overflow, hardened-runtime Apple Events entitlement, ROSÉ/Rose identity (MusicBrainz recording lookup + MBID-keyed art), app quitting with no windows open.

### 2026-09-25: Mini Player polish, widgets install, cache controls, more fan art
- Mini Player: real Liquid Glass, exact sizing, remembered open state and position, glass "…" button, strip follows the current image.
- Widgets appear once installed to `/Applications` (`scripts/install.sh`, which also stops the stale widget extension); stronger scrim on the small widget; desaturated artwork in the accented style; clicks open the Mini Player; real version numbers (0.1.0).
- Fan-art pipeline: Brave fallback gated on images that pass, duplicate threshold 0.2, incidental text allowed, versioned cache keys.
- Settings → Storage: live cache size, limit, Clear Cache…; LRU pruning; panes size to content without extra padding.
- Docs: README and memory bank brought up to date.

### 2026-09-25: Display icon
- Replaced the camera with GlassPowerTools' display (same bezel/screen geometry) and the Heroicons solid musical note on a red screen, 112% scale; menu bar template icons redrawn to match; `build_icons.py` builds multiple designs (`--ship <design> <palette>`); Heroicons MIT notice in `THIRD-PARTY-NOTICES.md`.
