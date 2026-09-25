# 260925_audiopaper-v0.1

## Objective
Build AudioPaper v0.1: a macOS 26 menu bar app that sets the wallpaper to the playing album's cover, then cross-fades filtered fan art and artist photos, with a plugin architecture for players and art sources. Publish it as a public repo.

## Outcome
- ✅ Tests: 53 passing (`swift test` in `Packages/AudioPaperKit`)
- ✅ Build: app builds signed (team 7JQGQ7CRH8) and unsigned (CI)
- ✅ Verified live: sandboxed wallpaper setting on two displays, Music notifications, album → fan art flow, cross-fade, restore original
- ✅ Review: approved by the user

## Files
- `Packages/AudioPaperKit/` — core library, `apctl` dev CLI, tests and recorded fixtures
- `App/` — SwiftUI MenuBarExtra, Settings, `AppIcon.icon`
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

## Decisions
- Sandboxed Developer ID distribution, not the App Store (also required by TheAudioDB's free key terms).
- No generative outpainting (no public Apple API) → feathered fit plus a blurred edge extension.
- No DuckDuckGo (unofficial scraping only).
