# Active Context

**State**: v0.1 feature-complete and public on `main` (github.com/msitarzewski/AudioPaper, MIT, CI green). Installed locally in `/Applications` via `scripts/install.sh`.

## User decisions (2026-09-25)
- Follow Apple's HIG, Apple's own UI examples and per-platform icon practice, macOS only for now (`projectRules.md`).
- Surfaces: native menu bar menu; the rich view lives in a Music-style Mini Player window (Liquid Glass, artwork under the traffic lights, remembers open state and position); WidgetKit widgets (Now Playing, Artwork); Dock icon only while needed.
- Fan-art sources: fanart.tv (user's project key in `.env`/Keychain as `FAN_ART_API_KEY`, never in the repo), TheAudioDB (free key), DeviantArt, and Brave as a metered fallback. Keep all artist metadata so people can open profiles and source pages.
- Photos are welcome (band and press photos, not only drawn art); small incidental text is fine, prominent text is not.
- Album cover first, then a cross-fade rotation like a Photos-folder wallpaper. Automatic framing (fit when fill would crop >15%).
- App icon: the display design (GlassPowerTools' display with the Heroicons note on a red screen), enlarged 112%; replaced the camera, which "seemed out of place". Menu bar icon matches. Other palettes (cobalt, emerald, violet, amber) are built as alternates.
- Cache: re-searches reuse downloaded images; people control the size limit and can clear it in Settings.
- No DuckDuckGo (no official image API). No generative outpainting (no public Apple API).
- Widgets follow the system widget style: grayscale while the desktop isn't focused (confirmed by the user), full colour otherwise. A click opens the Mini Player.
- Commits and pushes only when the user asks (their global rule).

## Open items
- DeviantArt credentials needed to verify that provider live.
- Decide whether release builds should ship the fanart.tv project key (their terms expect a project key in the app plus an optional user key; the repo must not contain it).
- Stylized band logos can slip past OCR.
- Spotify source plugin.
