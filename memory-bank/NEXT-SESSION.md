# Next session — start here

Updated 2026-09-25 (end of the website / release / hardening / accessibility session).

## Where things stand
- **v0.1.0 is released** (notarized DMG, github.com/msitarzewski/AudioPaper/releases) and the **website is live** at https://msitarzewski.github.io/AudioPaper/.
- In 0.1.1: MusicBrainz 503 handling, Commons subcategories, the accessibility audit and fixes, site screenshots. 108 tests.
- Read first: `activeContext.md`, `projectRules.md` (HIG, UI verification, secrets, accessibility), `systemPatterns.md`, `techContext.md` (website + release sections).
- Standing user rules: commit and push only when asked; follow Apple's HIG and WCAG2ICT; never put Claude session URLs anywhere; never capture the user's screen (only AudioPaper's windows).

## Next
1. **0.1.2 is published.** For the next release: the DMG is built and notarized (`build/release/AudioPaper-0.1.1.dmg`); commit, push, tag `v0.1.1` and `gh release create` with the notes and checksum — only with the user's go-ahead. Future releases: bump `project.yml`, `set -a; source ~/.config/brew-browser/signing.env; set +a; scripts/release.sh`.
2. **Commons relevance**: categories include photos merely related to an artist (Gabriel Boric in a NIN cap; speaker stacks). Proposal: trust top-category files only when the file name or caption names the artist. Verify against real categories (NIN, aespa, Poppy, Kim Petras, Laufey) before changing.
3. **Site screenshots** (done): BABYMETAL and BLACKPINK Mini Players captured by the user with only covers + Commons sources on; every image credited on `site/pages/credits.html` (identified by matching against Commons categories); screenshots offered under CC BY-SA 4.0. A Springsteen capture is held back: its single cover shows "ICE OUT" protest signs, and the site stays out of sides — the user's call.
4. A hands-on VoiceOver + Full Keyboard Access session.

5. **DeviantArt auth model** (raised by a Codex review, confirmed in DeviantArt's docs 2026-09-25): native apps are *public* OAuth clients (client ID only, Authorization Code + PKCE, OAuth 2.1 for new apps); Client Credentials needs a secret and is for confidential clients. AudioPaper uses Client Credentials with a per-user app ID + secret in the user's Keychain, public browse endpoints only. Ask DeviantArt whether that pattern is supported (the user sends it); if not, move to PKCE (user signs in) or drop the source. Still untested live.

## Loose ends
- DeviantArt unverified live (needs credentials). Stylized logos can pass OCR. Letterboxed stills. Spotify plugin.
