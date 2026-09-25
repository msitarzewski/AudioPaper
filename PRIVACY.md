# Privacy

AudioPaper changes your wallpaper to match the music you're playing. To do that, it has to look up artwork online, so some information about what you play does leave your Mac. This page says exactly what, to whom, and what stays on your Mac. For every request, host and timing, see [NETWORK.md](./NETWORK.md).

## The short version

- **No telemetry, no analytics, no accounts, no AudioPaper server.** AudioPaper talks only to the artwork and music-data services listed below, and only to look up art.
- **What leaves your Mac:** the **names** of the artist, album and song you're playing, sent to look up artwork, plus your IP address, as with any internet request.
- **What never leaves your Mac:** your library, play counts, playlists, account details, the images you've seen, and your settings. All image filtering happens on your Mac with Apple's Vision framework.
- **Replays are free:** once a song's artwork is found, playing it again makes no requests.

## Who learns what

| Service | Learns | Why |
|---|---|---|
| **Apple** (iTunes Search) | Each **new album** you play (artist + album), and your region | To find the album cover |
| **MusicBrainz** | Each **new song** you play (title + artist), and occasionally an album | To identify the artist, and for covers Apple doesn't know |
| **Internet Archive** (Cover Art Archive) | Which cover is fetched | Hosts MusicBrainz's covers |
| **fanart.tv** | Which artist (by ID) | Artist backgrounds |
| **TheAudioDB** | Which artist (by ID, or by name if there's no ID) | Artist backgrounds |
| **Wikimedia** (Wikidata, Commons) | Which artist (by ID) | Freely licensed artist photos |
| **DeviantArt** (only with your credentials) | Each new song (artist + title) | Fan art |
| **Brave Search** (only with your key, and only as a fallback) | Each new song it's used for ("artist song fan art wallpaper") | Fan art when the sources above find too little |
| **Websites Brave points to** | Your IP address, when one of their images is downloaded | They host the image; they don't learn what you're listening to |

**In practice, MusicBrainz sees the most:** roughly a list of the new songs you play, because that's how AudioPaper tells artists with the same name apart (ROSÉ of BLACKPINK is not Rose, the French singer). Apple sees new albums. The others see artists, or, if you've enabled them, song searches. Each song is searched only once, ever.

Every request identifies itself with the User-Agent `AudioPaper/0.1 (https://github.com/msitarzewski/AudioPaper; macOS album-art wallpaper app)` — the project's address, which Wikimedia and MusicBrainz ask API clients to include. It includes no account, device ID or tracking identifier, and the tracking parameters Wikimedia adds to its image links are removed.

## What AudioPaper does to keep this small

- **Caching.** Album covers and each artist's images are kept on disk: every song is searched once, and replays make no requests. Each artist builds a pool of up to 24 images, and every play shows the ones you've seen least recently, so repeat plays stay fresh without going back online. If nothing is found for a song, that's remembered for a week. Artist identities are remembered too, so artists you've played before don't need looking up again.
- **Fallback only.** Brave, the one service that searches the open web, is asked only when the curated sources return fewer than three usable images.
- **No cookies, no web cache.** Every request goes through a private network session that never stores or sends cookies and writes nothing to an HTTP cache. Image sites can't leave anything behind or recognise a returning visitor by cookie.
- **Rate limits.** Requests to each service are spaced out (1–2 seconds apart), and each service gets at most a handful of calls per song.
- **Your keys stay yours.** API keys are stored in your Keychain and sent only to the service they belong to.

## What's stored on your Mac

All of it stays inside AudioPaper's sandbox container (`~/Library/Containers/com.audiopaper/`) or its App Group, and none of it is uploaded anywhere.

| What | Where | How long |
|---|---|---|
| Downloaded artwork, each artist's image pool (with when each image was last shown) and which songs were searched | Caches | Up to the limit you set (500 MB by default), least recently used first; **Settings → General → Clear Cache…** removes it |
| Remembered artist identities | Caches (with the search results) | Until you clear the cache; unresolved names expire after a week |
| Rendered wallpapers | Application Support | Only the current ones are kept |
| Your original wallpaper's location | Preferences | Until you restore it |
| Settings, and the Mini Player's position | Preferences | Until you change them |
| API keys | Keychain | Until you remove them in Settings → Accounts |
| Widget snapshot (track, credits, small thumbnails) | App Group, shared only with AudioPaper's own widgets | Replaced on every change |

## Permissions

- **Automation (Music):** asked once, so AudioPaper can read what's already playing when it launches and, as a last resort, the album artwork Music has. It never controls playback. Track changes come from a notification Music broadcasts, which needs no permission.
- **Network (outgoing only):** for the lookups above. AudioPaper accepts no incoming connections.
- **Keychain:** for your API keys.

AudioPaper is sandboxed, and asks for nothing else: no location, contacts, camera, microphone, photos or files.

## Turning things off

- **Settings → Sources:** switch off any art source individually. With every fan-art source off (or **Wallpaper: Album cover** in General), AudioPaper contacts only Apple (and MusicBrainz as a fallback) for covers.
- **Settings → Accounts:** remove a key or DeviantArt credentials, and that service is never contacted.
- **Settings → General → Clear Cache…:** deletes downloaded artwork, remembered searches and artist identities.

## Questions

Report privacy concerns the same way as security issues; see [SECURITY.md](./SECURITY.md).
