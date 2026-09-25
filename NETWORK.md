# Network

Every network request AudioPaper makes: host, trigger, what's sent, and how often. For what this means for your privacy, see [PRIVACY.md](./PRIVACY.md).

All requests go through one client (`URLSessionHTTPClient`, `Packages/AudioPaperKit/Sources/AudioPaperKit/Support/HTTPClient.swift`) using a private, ephemeral session: **no cookies stored or sent, no HTTP disk cache**. Each request carries the User-Agent `AudioPaper/0.1 ( macOS album-art wallpaper app )` and no Referer. Outgoing connections only; AudioPaper opens no listening sockets.

## When requests happen

| Moment | Network? |
|---|---|
| App launch | Music is asked locally (Apple Events) what's playing. If that song isn't cached, its lookups follow, exactly as for a new song. Nothing else. |
| A **new album** starts (cover not cached) | Album cover lookup, below |
| A **new song** starts (fan art not cached) | Artist identity and fan-art lookups, below |
| Replaying a song or album already cached | **None** |
| A song with nothing found in the last 7 days | **None** |
| Wallpaper rotation, Mini Player, widgets, Settings | **None**, except DeviantArt artist avatars (below) |
| Clicking a credit or source link | Opens the page in your browser; AudioPaper makes no request |

## Album cover (per new album)

Providers are tried in order; the first confident match wins and later ones aren't contacted.

| # | Host | Request | Sends |
|---|---|---|---|
| 1 | `itunes.apple.com` | `GET /search?entity=album&limit=10` | artist + album, region (`country`) |
| 1a | `is1-ssl.mzstatic.com` | the cover image (up to 3000×3000) | — |
| 2 | `musicbrainz.org` | `GET /ws/2/release-group?query=…&limit=5` (only if Apple has no match) | artist + album |
| 2a | `coverartarchive.org` → `archive.org` (redirect) | the cover image (1200 px) | — |
| 3 | — | Music's own artwork, read locally | — |

**Typical: 2 requests** (Apple search + image). **At most 4.**

## Artist identity (per new artist)

Needed by fanart.tv and TheAudioDB, which are keyed by MusicBrainz ID. Rate-limited to one request per 1.1 s.

| Host | Request | Sends |
|---|---|---|
| `musicbrainz.org` | `GET /ws/2/recording?query=recording:"…" AND artist:"…"&limit=10` | song title + artist |
| `musicbrainz.org` | `GET /ws/2/artist?query=artist:"…"&limit=5` (only if the recording search is inconclusive) | artist |

**1–2 requests per artist, once.** Results are remembered on disk (unresolved names for 7 days), so an artist you've played before costs nothing, even after a relaunch. A collaboration credit ("A & B") is looked up as a whole first, and per artist only if that finds nothing.

## Fan art (per new song)

The primary sources are asked in parallel. Brave is asked afterwards, only if fewer than 3 images pass the on-device filters.

| Host | Request | Sends | Per song |
|---|---|---|---|
| `webservice.fanart.tv` | `GET /v3/music/{artist MBID}?api_key=…[&client_key=…]` | artist ID, your fanart.tv key(s) | 1 per artist (remembered until quit) |
| `www.theaudiodb.com` | `GET /api/v1/json/{key}/artist-mb.php?i={MBID}` (or `search.php?s={artist}` without an ID); spaced 2.1 s | artist ID or name, the key (free public key `123`, or yours) | 1 per artist (remembered until quit) |
| `www.deviantart.com` | `POST /oauth2/token` (client credentials), then `GET /api/v1/oauth2/browse/popular?q={artist song}` and `browse/tags?tag={artist}` | artist + song; your client ID/secret to the token endpoint only | 2 (+1 token about hourly). Only with your credentials |
| `api.search.brave.com` | `GET /res/v1/images/search?q=…&count=50&safesearch=strict` with header `X-Subscription-Token` | `"{artist} {song} fan art wallpaper"`, then `"{artist} fan art wallpaper"`; spaced 1.1 s | 0–2. Only with your key, only as a fallback |

### Image downloads (per new song)

Candidates the sources report as too small are skipped without downloading. The rest are downloaded 4 at a time and checked on your Mac, stopping once 8 pass. Downloaded images are cached, so a later re-search reuses them.

| Host | When |
|---|---|
| `assets.fanart.tv` | fanart.tv images |
| `r2.theaudiodb.com` | TheAudioDB images |
| DeviantArt's image servers (`images-wixmp-*.wixmp.com`), avatars from `a.deviantart.net` | DeviantArt images and artist avatars |
| **Any website** | Images found by Brave Search, fetched from the site that hosts them |

**Typically 4–12 downloads per new song.** At most about 30 per source, since each source returns up to 30 candidates.

### DeviantArt avatars

When the Mini Player credits a DeviantArt artist, their avatar is fetched from DeviantArt's avatar server, through the same cookie-free session.

## Typical totals

| Situation | Requests |
|---|---|
| Replaying something you've heard | **0** |
| New song, same album and artist as before | fanart.tv/TheAudioDB answered from memory; image downloads for any new candidates (often 0) |
| New song by a new artist, curated sources only (default) | ~2 identity + 2 art APIs + ~4–10 images |
| Same, plus Brave as fallback | + up to 2 searches + images from third-party sites |
| New album | + 2 (Apple search + cover) |

## Rate limits and quotas

| Service | AudioPaper's spacing | Service's published limit |
|---|---|---|
| MusicBrainz | 1 request / 1.1 s (shared by all lookups) | 1 / s |
| TheAudioDB | 1 request / 2.1 s | 30 / min on the free key |
| Brave Search | 1 request / 1.1 s | 1 / s and 2,000 / month on the free plan |
| Others | caching only | — |

## Verifying it yourself

- **Watch it live:** macOS's Network privacy report, Little Snitch or LuLu will show exactly these hosts.
- **Run the pipeline from the terminal:** `swift run apctl fanart "<artist>" "<song>"` (in `Packages/AudioPaperKit`) prints every candidate and verdict for one song, using your `.env` keys.
- **Read the code:** each host appears in exactly one source file under `Packages/AudioPaperKit/Sources/AudioPaperKit/` (`Artwork/`, `FanArt/`, `Support/MusicBrainz.swift`).
