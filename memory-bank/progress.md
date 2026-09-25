# Progress

## Done (v0.1, 2026-09-25)
- AudioPaperKit: models, normalizer/scorer, Apple Music source (distributed notification + launch-state AppleScript), album chain (iTunes, CAA, Music artwork), Brave + DeviantArt sources, Vision filter pipeline, cache, composer, wallpaper service with cross-fade, coordinator with rotation.
- App: MenuBarExtra popover (hero, attribution with profile/page links, filmstrip, Liquid Glass controls), Settings (General, Sources, Accounts), launch at login.
- TheAudioDB source, fallback gating for Brave, curated size floor, fit/fill framing, Music-app artwork fallback, Brave relevance + rate limiting, auto-saving credentials, Icon Composer app icon, team signing (`com.audiopaper`).
- fanart.tv source with shared MusicBrainz artist resolution (ambiguity-safe).
- HIG pass: native menu bar menu, Mini Player window, WidgetKit widgets, conditional Dock icon + Dock menu, Show in menu bar, Settings pane restore, custom template menu bar icon, red gradient camera app icon.
- 53 tests passing. Verified live: sandboxed wallpaper setting, Music notifications, album + fan-art flow, both displays.

## Next
- Verify DeviantArt with real credentials; Spotify source plugin; tune filters with more genres.
