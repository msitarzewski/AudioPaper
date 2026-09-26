# Next session — start here

Updated 2026-09-26 (Spotify / podcasts session).

## Where things stand
- **v0.1.6 is live** (2026-09-26): compact Mini Player (Show Artwork optional, off by default; song → strip → credit → controls). The Help page's Mini Player screenshots still show the old layout; retake with covers/Commons-only sources before the user-growth push.
- v0.1.5 (2026-09-26): Settings → About gained the update switches (check automatically, install automatically, last checked, Check Now).
- v0.1.4 (2026-09-26): Spotify support, "During podcasts" setting, player icon and music/podcast glyph. The first release delivered through Sparkle (0.1.3 users get it from the feed). Tag `v0.1.4` = `6fd20fd`; the feed commit follows it.
- Website live (landing, Help, Shortcuts, Reference, Privacy, Network, Credits) and the social card name Apple Music and Spotify. 130 tests.
- Spotify is installed on this Mac (Homebrew cask) with the user's free account; handy for testing.
- Read first: `activeContext.md`, `projectRules.md` (HIG, UI verification, secrets, accessibility), `systemPatterns.md` (Spotify facts under Plugin protocols), `techContext.md` (Website, Release, Updates).
- Standing user rules: commit, push and release only when asked; follow Apple's HIG and WCAG2ICT; never put Claude session URLs anywhere; never capture the user's screen (only AudioPaper's windows).

## Next
1. **Releases:** bump `project.yml` (version + build), `set -a; source ~/.config/brew-browser/signing.env; source .env; set +a; RELEASE_NOTES_HTML=<notes.html> scripts/release.sh`, commit, tag, `gh release create` with the DMG + zip + .sha256 + notes, **then** commit and push `site/static/appcast.xml`.
2. **Commons relevance**: categories include photos merely related to an artist (Gabriel Boric in a NIN cap; speaker stacks). Proposal: trust top-category files only when the file name or caption names the artist. Verify against real categories (NIN, aespa, Poppy, Kim Petras, Laufey) before changing.
3. **Site screenshots** (done): BABYMETAL and BLACKPINK Mini Players captured by the user with only covers + Commons sources on; every image credited on `site/pages/credits.html` (identified by matching against Commons categories); screenshots offered under CC BY-SA 4.0. A Springsteen capture was skipped (2026-09-26, user's decision): its single cover shows protest signs, and the current set already shows the range.
4. A hands-on VoiceOver + Full Keyboard Access session.
5. **DeviantArt auth model** (raised by a Codex review, confirmed in DeviantArt's docs 2026-09-25): native apps are *public* OAuth clients (client ID only, Authorization Code + PKCE, OAuth 2.1 for new apps); Client Credentials needs a secret and is for confidential clients. AudioPaper uses Client Credentials with a per-user app ID + secret in the user's Keychain, public browse endpoints only. Asked on DeviantArt's official tracker, 2026-09-25: https://github.com/wix-incubator/DeviantArt-API/issues/1181 (no developer email exists; the issue tracker is their documented channel); if not, move to PKCE (user signs in) or drop the source. The tracker rarely gets staff replies (none on the last 8 issues, incl. #388's licence question since May), so if there's no answer by ~2026-10-09, decide without one. Still untested live.

## Loose ends
- DeviantArt unverified live (needs credentials). Stylized logos can pass OCR. Letterboxed stills. Idea: fanart.tv album-cover scans for artists with no fan art (Chemlab). Verify 0.1.3 → 0.1.4 Sparkle update on a real install.
