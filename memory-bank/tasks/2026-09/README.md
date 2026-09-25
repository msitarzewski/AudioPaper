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

### 2026-09-25: Collaboration credits
- "LE SSERAFIM & j-hope" found no fan art (no artist by that combined name). The pipeline now falls back to each credited artist when the full credit finds nothing; MusicBrainz recording matches accept any credited artist; pipeline version 3 re-searches cached songs. SPAGHETTI: 0 → 8 images (both artists).

### 2026-09-25: About pane
- Settings → About, mirroring Anomalous's About (same layout; links GitHub · Help (README) · Privacy (PRIVACY.md) · ♥ Sponsor, since AudioPaper has no website).

### 2026-09-25: Featured artists
- "Move Bitch (feat. Ludacris, Mystikal & I-20)" by Disturbing tha Peace (a label crew) found no art; the credit fallback now also tries featured artists parsed from the title. 0 → 8 curated images.

### 2026-09-25: Artist pool, Wikimedia Commons, smarter web search
- Per-artist pool (≤24, each song searched once, least-recently-seen rotation); Commons via MusicBrainz → Wikidata → category with "Photo by … · license" credits (Kim Petras: 7 Commons photos, no Brave needed); Brave relevance now matches the artist as a phrase ("Blu-ray Noir" ≠ "Ray Noir") with a "press photo" follow-up query; Brave relabelled as web-search fallback. Bugs caught on the way: Wikidata values aren't all strings (trimmed fixture hid it), Commons renditions only at standard widths, Swift Regex lacks look-behind. Docs: README, PRIVACY, NETWORK.

### 2026-09-25: Size rules and web credits
- Kim Petras had 2 images: curated sources had one (logo) image each, and Brave's 1280×720 and portrait results were rejected by a stricter web-only floor and a landscape-only shape limit. Now one 1280×720 floor for all sources and portrait allowed (fit framing handles it): 8 images, all verified to be her. Brave credits name the matched artist + site instead of SEO page titles. Pipeline version 4. Possible follow-up: crop letterbox bars from video stills.

### 2026-09-25: Privacy and network documentation
- Ephemeral URL session (no cookies/HTTP cache) for every request, including avatars; artist MBIDs remembered on disk (cleared with the cache; unresolved expire in 7 days). New `PRIVACY.md` (who learns what, what's stored, permissions, opting out) and `NETWORK.md` (every host, trigger, payload, count, rate limit), linked from README and SECURITY.

### 2026-09-25: Display icon
- Replaced the camera with GlassPowerTools' display (same bezel/screen geometry) and the Heroicons solid musical note on a red screen, 112% scale; menu bar template icons redrawn to match; `build_icons.py` builds multiple designs (`--ship <design> <palette>`); Heroicons MIT notice in `THIRD-PARTY-NOTICES.md`.

### 2026-09-25: Website (GitHub Pages)
- Landing, Help, Keyboard shortcuts, Reference; Privacy and Network rendered from the repo files with pandoc (`scripts/build_site.py`, `.github/workflows/pages.yml`). Copy judged against BEDROCK: facts only, what leaves the Mac, whose art it is, costs, how to leave, who benefits, decision handed back. Help menu (⌘?) and About open the site.

### 2026-09-25: Security hardening
- Review of every untrusted input (API JSON, arbitrary image hosts, redirects, Music notifications, widget commands, the URL scheme). Fixed: https + named hosts only, credential stripping on redirects, response caps and time limits, Retry-After, web-only credit links, explicit local artwork, pre-decode image caps, no recording of failed searches, Lucene escaping, spoof limits, Keychain save errors, apctl redaction. 25 new tests (`UntrustedInputTests`).

### 2026-09-25: v0.1.0 release
- `scripts/release.sh`: archive → Developer ID export (widget included) → verify signatures, hardened runtime, sandbox, key and version → notarize and staple app and DMG. fanart.tv project key injected at build time only. Published with checksum; Gatekeeper accepts the download.

### 2026-09-25: Screenshots, Commons subcategories, MusicBrainz 503s
- Site screenshots of AudioPaper's own windows and renders of credited Commons photos (no fan art on the site). Commons walks artist-named subcategories. MusicBrainz's momentary 503s are waited out once.

### 2026-09-25: Accessibility audit
- Standard: WCAG2ICT (WCAG 2.2 AA for software) + Apple HIG; site WCAG 2.2 AA. Audited through the AX API (System Events gave a false "unlabelled" result) and Lighthouse. Fixed: artwork description, photo vs fan-art names, link names, decorative avatars, service-specific field names, slider value, Reduce Motion, keyboard-anchored menu, widget image descriptions, camera glyph for photos; site in-text link underlines and light-mode contrast. Documented in README, CONTRIBUTING, Help and Reference.

### 2026-09-25: Settings opens in front
- Menu bar **Settings…** used `SettingsLink`, which opened the window behind the frontmost app (AudioPaper usually has no Dock icon). Both Settings items now call `SettingsWindow.show` (`App/AudioPaperApp.swift`): `NSApp.activate(ignoringOtherApps: true)` (the cooperative `activate()` was declined from the menu bar extra), `openSettings()`, then `makeKeyAndOrderFront` on the `com_apple_SwiftUI_Settings_window`. Verified with Finder frontmost.

### 2026-09-25: 0.1.1
- Version 0.1.1 (build 2); `FanArtPipeline.version` 6 so artist pools are re-searched and pick up Commons subcategory photos. Contents: MusicBrainz 503 handling, Commons subcategories, accessibility fixes, camera glyph for photos, Settings in front, site Credits page and screenshots. Notarized DMG built with `scripts/release.sh`.

### 2026-09-25: One signature for local and release builds
- The user was asked for the login password twice after installing 0.1.1: the legacy login keychain ties each item (one per saved key) to the app's designated requirement, and Debug builds were signed with Apple Development while releases use Developer ID. `scripts/install.sh` now signs local builds with the Developer ID (manual style) when available; verified identical designated requirements. Users updating between releases never saw this (same Developer ID).

### 2026-09-25: App first, cover first
- User: on a song change the app lagged a few seconds, then the art updated, then the wallpaper. Causes: the UI followed `showing`, set only after render + 1.6 s fade; the 1.5 s debounce applied even to downloaded covers; and pooled fan art was presented right after the cover, superseding it, so the cover was often never on the desktop. Now the app switches at `present`, downloaded covers skip the debounce, the cover holds one interval before fan art, and a no-cover song cancels an in-flight render (a race the existing test caught). 3 new tests (111). Render measured at 0.1–0.4 s at 5K, so not the bottleneck.
- Follow-up (user): the cover is a placeholder until the good stuff loads, so it holds 10 s (`coverHold`), not a full interval.
