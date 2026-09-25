# 260925_audiopaper-v0.1

## Objective
Build AudioPaper v0.1: a macOS 26 menu bar app that sets the wallpaper to the playing album's cover, then cross-fades filtered fan art and artist photos, with a plugin architecture for players and art sources. Publish it as a public repo.

## Outcome
- ✅ Tests: 56 passing (`swift test` in `Packages/AudioPaperKit`)
- ✅ Build: app builds signed (team 7JQGQ7CRH8) and unsigned (CI)
- ✅ Verified live: sandboxed wallpaper setting on two displays, Music notifications, album → fan art flow, cross-fade, restore original, Mini Player (glass, position, open state), widgets in the gallery
- ✅ Review: approved by the user

## Files
- `Packages/AudioPaperKit/` — core library, `apctl` dev CLI, tests and recorded fixtures
- `App/` — SwiftUI menu bar menu, Mini Player window, Settings, Dock behaviour, `AppIcon.icon`, menu bar template icons
- `Widgets/` — WidgetKit extension (Now Playing, Artwork)
- `docs/icon/` — icon SVG masters and palette build; `scripts/install.sh`
- `project.yml` — XcodeGen spec
- Repo docs: README, CONTRIBUTING, SECURITY, LICENSE (MIT), `.github/` (FUNDING, CI, issue templates), `.gitleaks.toml`

## Patterns applied
- Plugin protocols: `NowPlayingSource`, `AlbumArtworkProvider`, `FanArtSource`, `ArtworkFilter` (`systemPatterns.md#Plugin protocols`)
- Cheapest-first pipeline with Vision filters (`systemPatterns.md#Fan-art pipeline`)
- Testing seams: `HTTPClient`, `SecretStore`, `WallpaperDisplay`

## Issues found and fixed during the build
- Plain "fan art" searches returned mostly merch thumbnails → "fan art wallpaper" queries plus a storefront blocklist.
- Brave free tier is 1 req/s → shared `RateLimiter`; partial results kept when a query fails.
- Common-word artist names ("Sleepover") matched unrelated art → relevance rule.
- `URL.path()` is percent-encoded → broke restoring the original wallpaper; switched to `path(percentEncoded: false)`.
- Releases missing from the online catalogs left the previous cover up → Music-app artwork fallback, and restore the original when nothing is found.
- Changing the signing identity triggered a Keychain prompt that blocked the main thread → Keychain checks moved off the main thread.
- Team signing enforced the hardened runtime, silently blocking the Music query → `automation.apple-events` entitlement.
- Accent-folded name matching confused ROSÉ with Rose → MusicBrainz recording-based identity, MBID-keyed art, accent-exact keys.
- A `Window`-only SwiftUI app quit with no windows open → `applicationShouldTerminateAfterLastWindowClosed` returns false.
- Mini Player "glass" was opaque and the window left a gap → window settings applied in `viewDidMoveToWindow`, title-bar height given back.
- Brave fallback counted found candidates, not passing images (BABYMONSTER: 1 of 7) → gate on accepted count; duplicate threshold and text limits retuned.
- Widgets never appeared from a DerivedData build → install to `/Applications`.
- Widget photos went blank when the desktop lost focus → desaturated accented rendering (the first attempt looked ineffective only because macOS kept the old widget extension running; `install.sh` now stops it).
- Clicking a widget did nothing visible → `audiopaper://` widget URL opens the Mini Player.

## Decisions
- Sandboxed Developer ID distribution, not the App Store (also required by TheAudioDB's free key terms).
- No generative outpainting (no public Apple API) → feathered fit plus a blurred edge extension.
- No DuckDuckGo (unofficial scraping only).
- Native menu in the menu bar and a Mini Player window instead of a popover (HIG); Dock icon only while needed.
- Vector gradient icon layers rather than 3D PNG renders, so the system's glass, lighting and appearances stay live.
