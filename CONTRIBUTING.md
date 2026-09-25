# Contributing to AudioPaper

Thanks for considering a contribution. AudioPaper is small and deliberately native. The bar for landing a change is: it matches the patterns already here, keeps the tests green, and doesn't add a dependency.

## TL;DR

1. Fork the repo and create a topic branch off `main`.
2. Make your change. Keep it small and focused.
3. Run `swift test` in `Packages/AudioPaperKit` and build the app (see below).
4. Open a PR with a short description of what changed and why. For visual changes, include a screenshot.

**No CLA. No rights assignment.** Your contributions remain yours, licensed under [MIT](./LICENSE) to match the project. By opening a PR you confirm you wrote the change or have the right to contribute it under that license.

## Dev setup

Prereqs:

- macOS 26 and Xcode 26 or later (`xcode-select -p` should point at `Xcode.app`, not the Command Line Tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

Loop:

```sh
git clone https://github.com/<your-fork>/AudioPaper
cd AudioPaper
xcodegen generate                        # after adding or removing files under App/
open AudioPaper.xcodeproj                # run the AudioPaper scheme

cd Packages/AudioPaperKit
swift test                               # the whole core, no network needed
```

The `.xcodeproj` is generated and git-ignored. Change `project.yml`, not the project file.

### Signing

`project.yml` sets the maintainer's team (`DEVELOPMENT_TEAM`). To build locally, either choose your own team in Xcode's Signing & Capabilities tab (don't commit that change), or build unsigned:

```sh
xcodebuild -project AudioPaper.xcodeproj -scheme AudioPaper -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

### API keys for development

The app reads keys from the Keychain (Settings → Accounts). The `apctl` developer tool reads them from the environment or a `.env` file. Copy `.env.example` to `.env` and fill in what you have. `.env` is git-ignored; never commit keys, fixtures that contain keys, or screenshots that show them.

### `apctl`: the pipeline from the terminal

```sh
cd Packages/AudioPaperKit
swift run apctl cover  "Radiohead" "In Rainbows"            # album cover lookup, per provider
swift run apctl fanart "Nine Inch Nails" "Closer" ./out     # every fan-art verdict; survivors copied to ./out
swift run apctl labels ./out/*.jpg                          # Vision labels, aesthetics, recognized text
swift run apctl render ./out/1-brave.jpg 3024 1964 fit      # preview a wallpaper at a screen size
```

`fanart` spends real search quota (Brave's free tier is 1 request/second and 2,000/month), so prefer the unit tests and recorded fixtures when you're tuning filters.

## Adding a plugin

Each extension point is a protocol in `AudioPaperKit`. Add one file, register it in one place, and add tests with a recorded fixture.

| You want to add… | Conform to | Register in |
|---|---|---|
| A music player (Spotify, …) | `NowPlayingSource` | `SourceRegistry.standard` |
| An album-cover source | `AlbumArtworkProvider` | the `AlbumArtworkChain` in `App/AudioPaperApp.swift` |
| A fan-art / artist-image source | `FanArtSource` | `fanArtSources` in `App/AudioPaperApp.swift` |
| A new image check | `ArtworkFilter` | `FanArtPipeline.filters` |

Guidelines:

- **Keep attribution.** Fill in `Attribution` (creator, profile URL, page URL, source name) for everything you return. The app shows it to users, and several sources require it.
- **Respect rate limits.** Use a shared `RateLimiter` if the service has a per-second limit, and rely on `ArtworkCache` rather than re-fetching.
- **Credentials go through `SecretStore`.** Add a case to `SecretKey`, report `isConfigured == false` when it's missing, and add the field to Settings → Accounts.
- **Test against recorded responses.** Save a real response under `Tests/AudioPaperKitTests/Fixtures/` (checking it contains no keys or personal data) and exercise the parsing through `StubHTTP`.
- **Relevance before quality.** A beautiful image of the wrong artist is worse than no image. Look at `BraveImageSource.relevance` for the pattern.

## Code style

- Swift 6 language mode with strict concurrency. Keep UI and AppKit work on `@MainActor`.
- Apple frameworks only; no third-party packages.
- Match the surrounding code: small types, doc comments on public API and non-obvious decisions, no commented-out code.
- File-system paths use `path(percentEncoded: false)`; `URL.path()` is percent-encoded.

## Reporting bugs

Open an issue with:

- your macOS version and the AudioPaper version or commit
- the player, artist, album and song, if the bug is about a lookup
- what you expected and what happened; Console output filtered by subsystem `com.audiopaper` helps

For security issues, follow [SECURITY.md](./SECURITY.md) instead of opening a public issue.
