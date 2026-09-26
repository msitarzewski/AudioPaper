# Active Context

**State** (2026-09-26): **v0.1.5 live** (update switches in Settings → About); 0.1.4 added Spotify (songs, podcasts, ads ignored), "During podcasts: My wallpaper / Podcast cover art", player icon + note/mic glyph; first update delivered through Sparkle. Open: DeviantArt OAuth question (issue #1181, decide by ~2026-10-09), Commons relevance, VoiceOver session. See NEXT-SESSION.md.

## User decisions (2026-09-25)
- Follow Apple's HIG, Apple's own UI examples and per-platform icon practice, macOS only for now (`projectRules.md`).
- Surfaces: native menu bar menu; the rich view lives in a Music-style Mini Player window (Liquid Glass, artwork under the traffic lights, remembers open state and position); WidgetKit widgets (Now Playing, Artwork); Dock icon only while needed.
- Fan-art sources: fanart.tv (user's project key in `.env`/Keychain as `FAN_ART_API_KEY`, never in the repo), TheAudioDB (free key), DeviantArt, and Brave as a metered fallback. Keep all artist metadata so people can open profiles and source pages.
- Photos are welcome (band and press photos, not only drawn art); small incidental text is fine, prominent text is not.
- Album cover first, then a cross-fade rotation like a Photos-folder wallpaper. Automatic framing (fit when fill would crop >15%).
- App icon: the display design (GlassPowerTools' display with the Heroicons note on a red screen), enlarged 112%; replaced the camera, which "seemed out of place". Menu bar icon matches. Other palettes (cobalt, emerald, violet, amber) are built as alternates.
- Cache: re-searches reuse downloaded images; people control the size limit and can clear it in Settings.
- Per-artist pool of up to 24 images (each song searched once; each play shows the least recently seen 8) — "we can't have a zillion".
- Wikimedia Commons added as a primary source; Brave labelled "Web search (Brave)" with a note that it only fills gaps (turning it off = curated only; no separate "curated" toggle, per HIG's fewer-settings guidance).
- DuckDuckGo: declined twice (no official API).
- No DuckDuckGo (no official image API). No generative outpainting (no public Apple API).
- Widgets follow the system widget style: grayscale while the desktop isn't focused (confirmed by the user), full colour otherwise. A click opens the Mini Player.
- Commits and pushes only when the user asks (their global rule).

- Settings has an About pane mirroring Anomalous's.
- Featured artists in song titles ("feat. …") fill in when the credited artist has no art.

## Open items
- DeviantArt credentials needed to verify that provider live.
- **Decided 2026-09-25:** release builds ship the fanart.tv project key, injected at build time from an environment variable (never in the repo; the build fails if it's missing). Rationale: fanart.tv keys are free and unlimited (not usage-billed), and a project key per app is fanart.tv's model. User's rule: any usage-billed service (Brave) needs the user's own key. Recommended a dedicated AudioPaper project key, separate from the user's personal one, so it can be revoked and rotated alone.
- Security sweep done and fixes approved and implemented (2026-09-25): https + named hosts only (redirects too), header stripping across hosts, response caps and a 60 s total timeout, Retry-After, web-only credit links, explicit local-artwork flag, pixel and format caps before decode, no recording of failed or cancelled searches, backslash escaping, spoof limits, modern Keychain, apctl redaction.
- Stylized band logos can slip past OCR.
- Letterboxed video stills (black bars) pass the filters; could detect and crop the bars.
- Spotify source plugin: **shipped in 0.1.4 (2026-09-26).** Labels: "During podcasts: My wallpaper / Podcast cover art". An ad was observed: Spotify posts NO notification for ads; AppleScript reports `spotify:ad:…` with empty artist and no artwork; the next song is announced normally. Probed live with a free account: `com.spotify.client.PlaybackStateChanged` carries Name/Artist/Album/Album Artist/Player State/Track ID (`spotify:track:…`); podcasts arrive with empty Artist and `spotify:episode:…`; Spotify can post a brief `Stopped` between items; ads (documented as `spotify:ad:…`) not yet observed. Rule: accept `spotify:track:` as songs, `spotify:episode:` as podcasts, ignore everything else. User asked for a setting "During podcasts: ( ) System wallpaper ( ) Podcast cover art", system wallpaper the default. Spotify installed via `brew install --cask spotify`; probe in the session scratchpad.
