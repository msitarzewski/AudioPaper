# Network

Every network request AudioPaper makes: host, trigger, what's sent, and how often. For what this means for your privacy, see [PRIVACY.md](./PRIVACY.md).

All requests go through one client (`URLSessionHTTPClient`, `Packages/AudioPaperKit/Sources/AudioPaperKit/Support/HTTPClient.swift`) using a private, ephemeral session: **no cookies stored or sent, no HTTP disk cache**. Each request carries the User-Agent `AudioPaper/0.1 (https://github.com/msitarzewski/AudioPaper; macOS album-art wallpaper app)` (a contact address, as Wikimedia and MusicBrainz ask of API clients) and no Referer. Outgoing connections only; AudioPaper opens no listening sockets.

Every reply is treated as untrusted, since web search results can point anywhere. So the same client enforces:

- **`https` to named internet hosts only**, for every request and every redirect. Plain `http`, `file:` and other schemes, IP addresses, `localhost`, `.local` and other local-network names are refused. A search result can't make AudioPaper contact anything on your own network. Web results that link an image over `http` are fetched over `https` instead.
- **Keys stay with their service.** If a redirect leads to a different host, the Brave key and the DeviantArt token are removed from the request first.
- **Limits:** a response larger than 40 MB is abandoned, and each request gets 60 seconds in all.
- **Downloaded images** must be JPEG, PNG, HEIC, WebP or TIFF, at most 16,384 px on a side and 50 megapixels. This is checked from the file header, before any decoding.

## When requests happen

| Moment | Network? |
|---|---|
| App launch | Music is asked locally (Apple Events) what's playing. If that song isn't cached, its lookups follow, exactly as for a new song. Nothing else. |
| A **new album** starts (cover not cached) | Album cover lookup, below |
| A **new song** starts, and its artist's pool has room | Artist identity and fan-art lookups, below. Each song is searched once, ever. |
| Replaying a song or album already cached | **None** (the artist's pooled images are shown, least recently seen first) |
| A song by an artist whose pool is full (24 images) | **None** |
| A song with nothing found in the last 7 days | **None** |
| A song whose search was cut short (offline, rate limited, a server error, or skipped mid-search) | Searched again on its next play; it isn't remembered as having found nothing |
| More than 60 new songs in an hour | Later ones show the album cover only and are searched on a later play |
| Wallpaper rotation, Mini Player, widgets, Settings | **None**, except DeviantArt artist avatars (below) |
| Clicking a credit, a source link, Help or an About link | Opens the page in your browser; AudioPaper makes no request |
| Checking for updates | The update feed (below): about once a day if you allowed automatic checks, or when you choose **Check for Updates…** |

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

Needed by fanart.tv, TheAudioDB and Wikimedia Commons, which are keyed by exact identity. Rate-limited to one request per 1.1 s.

| Host | Request | Sends |
|---|---|---|
| `musicbrainz.org` | `GET /ws/2/recording?query=recording:"…" AND artist:"…"&limit=10` | song title + artist |
| `musicbrainz.org` | `GET /ws/2/artist?query=artist:"…"&limit=5` (only if the recording search is inconclusive) | artist |
| `musicbrainz.org` | `GET /ws/2/artist/{MBID}?inc=url-rels` — the artist's Wikidata link, for Commons | artist ID |
| `www.wikidata.org` | `GET /wiki/Special:EntityData/{QID}.json` — the artist's Commons category | Wikidata ID |

**1–2 requests per artist, once.** Results are remembered on disk (unresolved names for 7 days), so an artist you've played before costs nothing, even after a relaunch. A collaboration credit ("A & B") is looked up as a whole first; only if that finds nothing are its individual artists, then any featured artists in the title ("feat. …"), looked up too.

## Fan art (per new song)

The primary sources are asked in parallel. Brave is asked afterwards, only if fewer than 3 images pass the on-device filters.

| Host | Request | Sends | Per song |
|---|---|---|---|
| `webservice.fanart.tv` | `GET /v3/music/{artist MBID}?api_key=…[&client_key=…]` | artist ID; AudioPaper's project key (or yours, if you set one) and your optional personal key | 1 per artist (remembered until quit) |
| `www.theaudiodb.com` | `GET /api/v1/json/{key}/artist-mb.php?i={MBID}` (or `search.php?s={artist}` without an ID); spaced 2.1 s | artist ID or name, the key (free public key `123`, or yours) | 1 per artist (remembered until quit) |
| `commons.wikimedia.org` | `GET /w/api.php?action=query&generator=categorymembers&gcmtitle=Category:{artist}` (files with size, photographer, license); if too few are wallpaper-sized, `list=categorymembers&cmtype=subcat` and the files of subcategories named after the artist ("… by year" → "… in 2025", newest first); spaced 0.5 s | the artist's Commons category and those subcategory names | 1–7 per artist (remembered until quit) |
| `www.deviantart.com` | `POST /oauth2/token` (client credentials), then `GET /api/v1/oauth2/browse/popular?q={artist song}` and `browse/tags?tag={artist}` | artist + song; your client ID/secret to the token endpoint only | 2 (+1 token about hourly). Only with your credentials |
| `api.search.brave.com` | `GET /res/v1/images/search?q=…&count=50&safesearch=strict` with header `X-Subscription-Token` | `"{artist} {song} fan art wallpaper"`, then `"{artist} fan art wallpaper"`, then `"{artist} press photo"` — each only while relevant results are still short; spaced 1.1 s | 0–3. Only with your key, only as a fallback |

### Image downloads (per new song)

Candidates the sources report as too small (under 1280×720) are skipped without downloading, as are images already in the artist's pool. The rest are downloaded 4 at a time and checked on your Mac, stopping once 8 pass (or the pool is full). Downloaded images are cached, so a later re-search reuses them.

| Host | When |
|---|---|
| `assets.fanart.tv` | fanart.tv images |
| `r2.theaudiodb.com` | TheAudioDB images |
| `upload.wikimedia.org`, `thumb.wikimedia.org` | Commons photos: originals up to 4000 px wide, a 1920 px rendition for larger ones; Commons' `utm_*` tracking parameters are removed |
| DeviantArt's image servers (`images-wixmp-*.wixmp.com`), avatars from `a.deviantart.net` | DeviantArt images and artist avatars |
| **Any website** | Images found by Brave Search, fetched from the site that hosts them |

**Typically 4–12 downloads per new song.** At most about 30 per source, since each source returns up to 30 candidates.

### DeviantArt avatars

When the Mini Player credits a DeviantArt artist, their avatar is fetched from DeviantArt's avatar server, through the same cookie-free session.

## Checking for updates (Sparkle)

AudioPaper uses [Sparkle](https://sparkle-project.org). On the second launch it asks whether to check automatically; nothing is checked until you choose.

| Host | Request | When | Sends |
|---|---|---|---|
| `msitarzewski.github.io` | `GET /AudioPaper/appcast.xml` (the update feed) | about once a day if you allowed automatic checks; whenever you choose **Check for Updates…** | your IP address, and Sparkle's User-Agent (app name and version). **No system profile** |
| `github.com` → GitHub's download servers | the update's `.zip` | only when you choose to install an update | — |

Every update is verified against the EdDSA public key built into the app before it's installed; a feed or file that doesn't match is refused.

## Typical totals

| Situation | Requests |
|---|---|
| Replaying something you've heard | **0** |
| New song by an artist you've played this session | fanart.tv, TheAudioDB and Commons answered from memory; downloads only for images not yet pooled (often 0) |
| New song by a new artist, curated sources only (default) | ~2 identity + 2–8 for Commons (Wikidata link, category, and up to 6 subcategory requests) + 3 art APIs + ~4–10 images |
| Same, plus Brave as fallback | + up to 3 searches + images from third-party sites |
| Artist's pool full (24 images) | **0** |
| New album | + 2 (Apple search + cover) |

## Rate limits and quotas

| Service | AudioPaper's spacing | Service's published limit |
|---|---|---|
| MusicBrainz | 1 request / 1.1 s (shared by all lookups) | 1 / s |
| TheAudioDB | 1 request / 2.1 s | 30 / min on the free key |
| Wikimedia (Wikidata, Commons) | 1 request / 0.5 s | "be reasonable"; a contact User-Agent is required |
| Brave Search | 1 request / 1.1 s | 1 / s and 2,000 / month on the free plan |
| Others | caching only | — |

When a service answers **429 Too Many Requests** or **503**, AudioPaper sends nothing more to that host for as long as its `Retry-After` header asks (a minute if it doesn't say, at most an hour), and the song is searched again later.

## Verifying it yourself

- **Watch it live:** macOS's Network privacy report, Little Snitch or LuLu will show exactly these hosts.
- **Run the pipeline from the terminal:** `swift run apctl fanart "<artist>" "<song>"` (in `Packages/AudioPaperKit`) prints every candidate and verdict for one song, using your `.env` keys.
- **Read the code:** each host appears in exactly one source file under `Packages/AudioPaperKit/Sources/AudioPaperKit/` (`Artwork/`, `FanArt/`, `Support/MusicBrainz.swift`). The per-artist pool is `Cache/ArtistPool.swift`.
