# Next session — start here

Updated 2026-09-25 (end of the website / release / hardening / accessibility session).

## Where things stand
- **v0.1.3 is live** (notarized DMG + Sparkle zip, GitHub Releases) and updates itself from `https://msitarzewski.github.io/AudioPaper/appcast.xml`. HEAD `3b650cc`: only docs/site changed since, so the build is current.
- Website live (landing, Help, Shortcuts, Reference, Privacy, Network, Credits); README has credited screenshots and an "Other projects" list. CI green. 111 tests.
- Read first: `activeContext.md`, `projectRules.md` (HIG, UI verification, secrets, accessibility), `systemPatterns.md`, `techContext.md` (Website, Release, Updates).
- Standing user rules: commit, push and release only when asked; follow Apple's HIG and WCAG2ICT; never put Claude session URLs anywhere; never capture the user's screen (only AudioPaper's windows).

## Next
1. **Next release is 0.1.4, the first delivered by Sparkle** — only with the user's go-ahead. Bump `project.yml` (version + build), `set -a; source ~/.config/brew-browser/signing.env; set +a; scripts/release.sh`, commit, tag, `gh release create` with the DMG + Sparkle zip + notes + checksum, **then** push the updated `site/static/appcast.xml` (the feed must never point at a zip that isn't published yet).
2. **Commons relevance**: categories include photos merely related to an artist (Gabriel Boric in a NIN cap; speaker stacks). Proposal: trust top-category files only when the file name or caption names the artist. Verify against real categories (NIN, aespa, Poppy, Kim Petras, Laufey) before changing.
3. **Site screenshots** (done): BABYMETAL and BLACKPINK Mini Players captured by the user with only covers + Commons sources on; every image credited on `site/pages/credits.html` (identified by matching against Commons categories); screenshots offered under CC BY-SA 4.0. A Springsteen capture was skipped (2026-09-26, user's decision): its single cover shows protest signs, and the current set already shows the range.
4. A hands-on VoiceOver + Full Keyboard Access session.
5. **DeviantArt auth model** (raised by a Codex review, confirmed in DeviantArt's docs 2026-09-25): native apps are *public* OAuth clients (client ID only, Authorization Code + PKCE, OAuth 2.1 for new apps); Client Credentials needs a secret and is for confidential clients. AudioPaper uses Client Credentials with a per-user app ID + secret in the user's Keychain, public browse endpoints only. Asked on DeviantArt's official tracker, 2026-09-25: https://github.com/wix-incubator/DeviantArt-API/issues/1181 (no developer email exists; the issue tracker is their documented channel); if not, move to PKCE (user signs in) or drop the source. The tracker rarely gets staff replies (none on the last 8 issues, incl. #388's licence question since May), so if there's no answer by ~2026-10-09, decide without one. Still untested live.

## Loose ends
- DeviantArt unverified live (needs credentials). Stylized logos can pass OCR. Letterboxed stills. Spotify plugin.
