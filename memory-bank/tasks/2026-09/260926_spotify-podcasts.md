# 260926_spotify-podcasts

## Objective
Follow Spotify as well as Apple Music (a free account works), handle podcasts and ads, and show which player and what kind of item is playing. Released as 0.1.4, the first update delivered through Sparkle.

## Outcome
- ✅ Tests: 130 passing (+19), fixtures are real Spotify notifications and a real ad
- ✅ Build: app + widgets; live-tested by the user (songs, fan art, podcasts, icon)
- ✅ Review: plan approved, result approved ("Magic")

## Files Modified
- `Packages/AudioPaperKit/Sources/AudioPaperKit/Sources/SpotifySource.swift` (new) — `SpotifySource`, `SpotifyArtworkProvider`. New file: Music's plugin is tied to Music's names, IDs and scripts; shared parts moved to `PlayerInfo`.
- `Sources/NowPlayingSource.swift` — `PlayerInfo`, `playsPodcasts`, `appBundleID`, registry by disabled set.
- `Sources/AppleMusicSource.swift` — uses `PlayerInfo`.
- `Model/Track.swift` — `MediaKind`, `isPodcast`, `subtitle`, backward-compatible decoding.
- `Model/Artwork.swift` — `ArtworkKind.podcastCover`, `isCover`, `pageNoun`.
- `Artwork/ArtworkProvider.swift` — `handlesPodcasts`; the chain skips album catalogs for podcasts.
- `Support/Preferences.swift` — `PodcastWallpaper`, `disabledSources` with migration from `enabledSources`.
- `NowPlayingCoordinator.swift` — podcast handling, `podcastSettingChanged()`, `player(for:)`, re-load after a Stopped-cancelled lookup.
- `Wallpaper/WallpaperComposer.swift` — podcast covers framed like album covers.
- `App/Views/SettingsView.swift`, `MiniPlayerView.swift`, `MenuBarMenu.swift`, `App/AppModel.swift`, `Widgets/AudioPaperWidgets.swift` — setting, player icon, glyphs, labels.
- `project.yml` — Spotify Apple Events exception, usage text, 0.1.4 (5).
- `scripts/install.sh` — `touch` after `ditto`.
- Docs: README, PRIVACY, NETWORK, CONTRIBUTING, site Help/Reference/landing, social card.

## Patterns Applied
- `systemPatterns.md#Plugin protocols` (one file + one registration), `#Preferences` (store what's off).
- `projectRules.md` accessibility: player icon decorative, named in the hero description.

## Architectural Decisions
- Classify Spotify items by ID prefix, never by missing fields: ads and unknown kinds are ignored whatever they contain.
- Podcast covers come from Spotify itself (exact image), not a name search in Apple's podcast directory (a guess, and misses Spotify-only shows).
- Show other apps' icons from the installed app (`NSWorkspace.icon(forFile:)`), shipping no one else's logo.
