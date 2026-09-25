# Active Context

**State**: DOCS complete for v0.1; published to GitHub (public, MIT) on `main`.

## User decisions (2026-09-25)
- Fan-art sources: TheAudioDB (free key), DeviantArt and Brave. Keep all artist metadata so users can open profiles and source pages.
- Photos are welcome (band and press photos, not only drawn art).
- Fan art: album cover first, then cross-fade rotation like a Photos-folder wallpaper. Automatic framing (fit when fill would crop >15%).
- No DuckDuckGo (no official image API).
- fanart.tv integrated (`FanartTVSource`); the user's project key is `FAN_ART_API_KEY` in `.env` / Keychain. It is NOT embedded in the app or repo. Coverage: strong for established artists (NIN, Radiohead, Troye Sivan), none for newer ones (Frost Children, 2hollis, Sleepover); Brave fills those.
- Public repo on the user's GitHub with README, CONTRIBUTING, SECURITY, FUNDING (sponsors), CI, issue templates.

- Menu bar is a native menu; the rich view is the Mini Player window; widgets (Now Playing, Artwork); Dock only when needed; red gradient camera icon; "Show in menu bar" + Settings restores last pane. All approved by the user.

## Open items
- DeviantArt credentials needed to verify that provider live.
- Decide whether release builds should ship the fanart.tv project key (their terms expect a project key in the app plus an optional user key; the repo must not contain it).
- Stylized band logos can slip past OCR.
- Spotify source plugin.
