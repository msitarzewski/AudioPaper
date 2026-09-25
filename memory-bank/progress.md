# Progress

## Done (v0.1, 2026-09-25)
- AudioPaperKit: models, normalizer/scorer, Apple Music source (distributed notification + launch-state AppleScript), album chain (iTunes, CAA, Music artwork), Brave + DeviantArt sources, Vision filter pipeline, cache, composer, wallpaper service with cross-fade, coordinator with rotation.
- App (first version): MenuBarExtra popover (hero, attribution with profile/page links, filmstrip, Liquid Glass controls), Settings (General, Sources, Accounts), launch at login. The popover was later replaced by the native menu + Mini Player (HIG pass).
- TheAudioDB source, fallback gating for Brave, curated size floor, fit/fill framing, Music-app artwork fallback, Brave relevance + rate limiting, auto-saving credentials, Icon Composer app icon, team signing (`com.audiopaper`).
- fanart.tv source with shared MusicBrainz artist resolution (ambiguity-safe).
- HIG pass: native menu bar menu, Mini Player window, WidgetKit widgets, conditional Dock icon + Dock menu, Show in menu bar, Settings pane restore, custom template menu bar icon, red gradient camera app icon.
- Mini Player polish: real Liquid Glass background, exact sizing under the hidden title bar, open state and position remembered, glass "…" button with a native menu, image strip follows the current image.
- Widgets verified in the gallery once installed to `/Applications`; `scripts/install.sh`; desaturated artwork in the accented widget style.
- Fan art: fallback gated on images that *pass*, duplicate threshold 0.2, incidental text allowed, versioned per-song cache keys (BABYMONSTER went from 1 image to 4).
- Cache controls in Settings (size, limit, Clear Cache…), LRU pruning after each song; Settings panes size to their content.
- App icon redesigned as a GlassPowerTools-style display with the Heroicons note (red); matching menu bar template icons; icon build supports multiple designs.
- Collaboration credits ("A & B", "feat.") fall back to each credited artist.
- Privacy tightening: ephemeral network session (no cookies, no HTTP cache), avatars through it, artist IDs persisted on disk; `PRIVACY.md` and `NETWORK.md` published.
- Fan-art size rules: single 1280×720 floor, portrait allowed; Brave credits show the matched artist.
- 64 tests passing. Verified live: sandboxed wallpaper setting, Music notifications, album + fan-art flow, both displays, Mini Player glass and position, widgets in the gallery.

## Next
- Verify DeviantArt with real credentials; Spotify source plugin; tune filters with more genres; decide on shipping the fanart.tv project key for release builds.
