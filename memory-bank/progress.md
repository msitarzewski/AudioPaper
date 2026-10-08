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
- Per-artist image pool with least-recently-seen rotation; Wikimedia Commons source with photographer/license credits; Brave phrase-based relevance and a "press photo" follow-up query (Ray Noir 0 → 2); contact User-Agent; Commons tracking parameters stripped.
- Featured artists in titles fill in when the credited artist has no art.
- 80 tests passing. Verified live: sandboxed wallpaper setting, Music notifications, album + fan-art flow, both displays, Mini Player glass and position, widgets in the gallery.

- Settings → About (mirrors Anomalous).

## Done (after v0.1, 2026-09-25)
- **Website** live on GitHub Pages (landing, Help, Keyboard shortcuts, Reference, Privacy, Network), framed with BEDROCK; Help ⌘? opens it. Real screenshots: aespa (David Lee, CC BY 2.0), Poppy (Justin Higuchi, CC BY 2.0), Ghosts V cover (public domain), Mini Players in album-cover mode.
- **Security hardening** against untrusted responses (see `systemPatterns.md#Network and privacy`), found by a review that treated every response as hostile.
- **v0.1.0 released**: notarized DMG, fanart.tv project key built in at release time.
- **MusicBrainz 503s** (a shared pool refilling each second) are waited out once instead of pausing the host a minute.
- **Commons subcategories**: aespa and Poppy photos, filed by year, are now found.
- **Accessibility audit** (WCAG2ICT + Apple HIG; site WCAG 2.2 AA): spoken names for the artwork, photos, links and Settings fields; Reduce Motion; keyboard-safe "…" menu; widget descriptions; site links underlined and light-mode contrast fixed (Lighthouse 100 on every page, both schemes).
- Settings opens in front from the menu (`SettingsWindow.show`).
- Site: Credits page; BABYMETAL and BLACKPINK Mini Player screenshots (only covers + Commons photos), screenshots under CC BY-SA 4.0.
- **v0.1.1 released** (version 0.1.1, build 2; pipeline version 6).
- **v0.1.3**: Sparkle auto-update (verified sandboxed install end to end), internet-content disclaimer, CI timing fix.
- **v0.1.2**: song changes show the new cover in the app at once and on the desktop right after; downloaded covers skip the debounce; the cover holds 10 s before fan art (was often skipped).
- **v0.1.4** (2026-09-26): Spotify player (songs, podcasts, ads ignored), "During podcasts" setting, player icon and music/podcast glyph in the Mini Player and menu, Spotify cover fallback, players stored as disabled, install.sh icon-cache fix. 130 tests.
- **v0.1.5** (2026-09-26): Settings → About has the update switches (check automatically; download and install automatically) plus last-checked and Check Now. The user's Mac had automatic checks off, with no way to turn them on before this.
- **v0.1.6** (2026-09-26): compact Mini Player — artwork optional (Show Artwork, off by default); order song → strip → credit → controls. 131 tests.
- **v0.1.7** (2026-09-26): Siri/Shortcuts/Spotlight App Intents ("What's on my desktop in AudioPaper?" answers with the credit), AppleScript dictionary (read what's showing, `show image n`, `next image`, `paused`), switched-off fan-art sources hidden from pools at once (kept, don't count toward 24). 134 tests.
- **v0.1.8** (2026-09-27): art drawn over the wallpaper by default ("Show art: Over my wallpaper"; the desktop picture is never touched), replace mode with per-display-and-Space restore, restore on by default, player quit counts as stopped, click the song to open it in Music/Spotify, command-style Siri phrases ("AudioPaper credit") + phrase registration at launch, widget intents hidden from Shortcuts, exact Settings-window match, Keychain off the main thread, Commons placeholder authors tidied, narrow slider label, more AppleScript (source pages, choose by page, restore). 142 tests.
- **v0.1.9** (2026-10-04): songs with no album in the library (blank Album in Music) now get a cover: looked up as a song in the Apple Music catalog (title + artist), Music's embedded artwork as fallback, and each such song has its own cover key. Before, they skipped straight to fan art. 143 tests.

## Next
- Commons relevance: prefer files that name the artist (a NIN-cap photo of Gabriel Boric and a speaker stack came through).
- A hands-on VoiceOver + Full Keyboard Access session.
- Idea: for artists with no fan art (e.g. Chemlab), fanart.tv's scans of their other album covers.
- **Backlog: narrower Apple Events permission.** Replace `temporary-exception.apple-events` (Music, Spotify) with `com.apple.security.scripting-targets` for the groups the apps publish: Music `com.apple.Music.playback` (+ `com.apple.Music.library.read` if artwork needs it), Spotify `com.spotify.playback`. Same Automation prompt for users; macOS then enforces read-only. Verify every AppleScript term live (terms outside the groups fail silently), then say so in PRIVACY.md.
- **DeviantArt: verified, no further work.** DeviantArt is verified live (2026-10-07): the maintainer answered issue #1181 on 2026-09-27 ("Per-user credentials are fine to use!", closed as completed), and a run with the user's own app ID + secret (Keychain `com.audiopaper.credentials`) got a token (3600 s), browsed `/browse/tags`, and returned 11–17 candidates per artist (BLACKPINK, NIN, Poppy, Taylor Swift). Almost all fail the quality floor (mostly ≤1024 px or square, some text/utility): 1 of 53 accepted. Fanart.tv and TheAudioDB fill the 8-image cap first, so DeviantArt stays a minor source. Filters were left alone; loosening the size floor would admit low-resolution art. The fanart.tv project key ships in release builds (decided 2026-09-25).

## Hopes
Features we'd like but can't build well today, each waiting on something outside AudioPaper. Revisit when macOS or the services change.
- **Apple Podcasts as a player** (2026-09-27): the Podcasts app posts no change notification (verified with a listener while playing, skipping and pausing) and has no AppleScript dictionary. The system now-playing service (MediaRemote) is private and, since macOS 15.4, limited to Apple-entitled processes; the Perl-loading workaround isn't fit for a sandboxed app. Needs a public now-playing API (worth filing feedback).
- **Podcast chapter art** (2026-09-27): Podcasting 2.0 `<podcast:chapters>` JSON can give each chapter its own image, perfect for the rotation (Callisto.fm did this). Only useful once AudioPaper can follow a player that exposes the episode's feed. Apple's in-app chapters ("Automatically created") have titles only and aren't reachable. Checked: Tech Policy Press (300 episodes, one image, no chapters).
- **Restoring macOS's own dynamic wallpapers exactly** in "As my wallpaper" mode: no public API reads or sets provider wallpapers (FB13683971). The overlay default sidesteps it.
- **Siri's built-in phrases**: actions work in Shortcuts, but Siri hasn't routed "AudioPaper credit" to the app on the user's Mac. Re-test with a released build after indexing; the named-shortcut workaround is documented.

