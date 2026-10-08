# Next session — start here

Updated 2026-10-07 (v0.1.9 shipped; DeviantArt verified).

## Where things stand
- **v0.1.9** (2026-10-04): a song with a blank Album in Music now shows its cover first (catalog song search by title + artist, then Music's embedded art), instead of jumping to fan art. Cause found via the AppleScript `image credits` property (first image was a photo).
- **v0.1.8** (2026-09-27): art over the wallpaper by default (see `systemPatterns.md#Wallpaper`), click-to-open in the player, command-style Siri phrases. Siri still unverified: if "AudioPaper credit" doesn't route, the workaround is a named user shortcut.
- v0.1.7 (2026-09-26): Siri, Shortcuts and AppleScript (see `systemPatterns.md#Automation`); switched-off fan-art sources leave the rotation at once.
- v0.1.6 (2026-09-26): compact Mini Player (Show Artwork optional, off by default; song → strip → credit → controls). The Help page's Mini Player screenshots still show the old layout; retake with covers/Commons-only sources before the user-growth push.
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
5. **DeviantArt: settled (2026-10-07).** AudioPaper uses Client Credentials with a per-user app ID + secret in the Keychain (public browse endpoints only). The maintainer approved that on #1181 (2026-09-27: "Per-user credentials are fine to use!"), so no PKCE and no dropping the source. Verified live end to end: token, browse, 11–17 candidates per artist, 1 of 53 accepted by the filters (art is mostly small or square). Nothing left to do unless the size floor is revisited.

## Pause point (2026-10-07)
- v0.1.9 live (commits `ed3faa3`, feed `94181f0`); the Hopes list is committed. Repo quiet: no issues or PRs; 3 downloads of 0.1.9.
- Open: Siri built-in phrases (re-test after a released update), Commons relevance (Shibuya-billboard and j-hope/BTS collaboration strays are good test cases), the narrower Apple Events permission (backlog), a VoiceOver session, retaking the Help page's Mini Player screenshots in the compact layout.

## Loose ends
- Stylized logos can pass OCR. Letterboxed stills. Idea: fanart.tv album-cover scans for artists with no fan art (Chemlab). Verify 0.1.3 → 0.1.4 Sparkle update on a real install.
