# Next session — start here

Written 2026-09-25 at the end of the v0.1 build session, before a context compaction.

## Where things stand
- AudioPaper v0.1 is feature-complete, public (github.com/msitarzewski/AudioPaper, MIT), CI green, and installed
  locally from `scripts/install.sh`. 80 tests in `Packages/AudioPaperKit` (`swift test`).
- Read first: `activeContext.md` (decisions), `systemPatterns.md` (how it works), `techContext.md` (build,
  services, gotchas), `projectRules.md` (HIG, UI verification without capturing the user's screen, secret
  scanning, keep PRIVACY/NETWORK true).
- Standing user rules: commit and push only when asked; follow Apple's HIG; never put Claude session URLs
  anywhere; attribution lines per the harness reminder.

## Task 1 — GitHub Pages website (user's request, verbatim intent)
"A complete GitHub Pages website for the project — landing page, help, command keys, the full reference —
use **bedrock** for the framing so it's wonderful."
- "Bedrock" = the BEDROCK philosophy corpus, available through the `ask-bedrock` skill (agency, floor-not-summit,
  no manufactured wanting, hand-the-shovel). Use it to frame the site's voice and structure, and to judge copy.
- Pages to build: landing; Help (setup, sources/keys, Mini Player, widgets, Dock, troubleshooting); keyboard
  shortcuts ("command keys": ⌥⌘M Show Mini Player, ⌘, Settings, ⌘Q Quit, Mini Player/Window-menu items);
  full reference (settings table, sources, filters, pool, privacy/network — reuse README, PRIVACY.md,
  NETWORK.md, docs/icon/README.md as sources of truth; don't fork facts).
- Check how the user's other projects publish sites (e.g. `~/Software/brew-browser/landing`, glas.sh docs) and
  match their house style. Use the shipped icon (`docs/icon.png`, `docs/icon/palettes/previews/display-red-*.png`).
- Screenshots: capture only AudioPaper's own windows (`screencapture -o -l <windowID>`); never the user's
  screen. Album/fan art in screenshots is third-party — prefer neutral/own imagery or ask.
- Publish via GitHub Pages (a `docs/` or `site/` folder or `gh-pages` branch); verify the live URL.

## Task 2 — Notarized release for Mac
- Developer ID signing with team `7JQGQ7CRH8`; hardened runtime is already on; entitlements in `project.yml`.
  The widget extension must be signed and notarized too.
- Flow to establish: Release build (`scripts/install.sh Release` builds; a `scripts/release.sh` probably
  needed): archive/export with Developer ID → `notarytool submit --wait` → `stapler staple` → zip/DMG → GitHub
  Release with notes. Check the user's other apps (GlassPowerTools, brew-browser `build-icons.sh`/release
  scripts, Anomalous) for their existing notarization credentials/profile name before inventing one.
- Decide with the user: version number (currently 0.1.0 build 1), DMG vs zip, and whether release builds ship the
  fanart.tv project key (open item; the repo must never contain it).
- Update README install instructions and the website once a download exists.

## Loose ends (not blocking)
- DeviantArt provider still unverified live (needs the user's credentials).
- Stylized band logos can pass OCR; letterboxed video stills could be cropped.
- Spotify source plugin.
