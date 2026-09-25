# Active Context

**State** (2026-09-25): **v0.1.3** — Sparkle auto-update (feed `site/static/appcast.xml` on GitHub Pages; EdDSA key in the login Keychain, `generate_keys --account AudioPaper`), internet-content disclaimer (Settings → Sources, About, README, site). Everyone installs 0.1.3 by hand once; later versions update through Sparkle. Next: Commons relevance, VoiceOver session.

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
- Spotify source plugin.
