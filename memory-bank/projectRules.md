# Project Rules

### Apple Human Interface Guidelines
**Context**: Standing user requirement, 2026-09-25.
**Pattern**: UI, interaction and icons follow Apple's HIG and Apple's own UI examples for each platform (macOS only for now). Deviations are called out to the user with the reason, never made silently.
**Implementation**: Read the relevant HIG page first. The site is JS-rendered; fetch `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json` (e.g. `app-icons`, `the-menu-bar`, `settings`, `popovers`) and extract the text.
**Example**: The app icon (`docs/icon/`, display design) uses layered vector SVGs in Icon Composer with system-provided glass effects, per HIG "App icons". The menu bar extra is a menu, not a popover (HIG "The menu bar"); the Mini Player follows Music's MiniPlayer.

### Verify UI by looking, without looking at the user's screen
**Context**: 2026-09-25 — several UI bugs (layout overflow, opaque "glass", bottom gap) were only caught from screenshots.
**Pattern**: After UI changes, capture and inspect AudioPaper's own windows; never capture the user's screen (a region capture once picked up an unrelated terminal).
**Implementation**: `screencapture -x -o -l <windowID>` with the ID from `CGWindowListCopyWindowInfo` (filter owner "AudioPaper", layer 0, on screen). Open windows via System Events menu clicks. Translucency can't be judged from a window-only capture, so ask the user.

### Secrets never reach the repo
**Context**: The repo is public; `.env` holds real Brave and fanart.tv keys.
**Pattern**: Before every commit, scan exactly the staged tree.
**Implementation**: `git archive $(git write-tree) | tar -x -C <tmp>`, then `gitleaks dir --config .gitleaks.toml <tmp>` and a literal grep for each `.env` value. Fixtures are checked for keys when recorded.
