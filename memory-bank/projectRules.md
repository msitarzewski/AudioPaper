# Project Rules

### Apple Human Interface Guidelines
**Context**: Standing user requirement, 2026-09-25.
**Pattern**: UI, interaction and icons follow Apple's HIG and Apple's own UI examples for each platform (macOS only for now). Deviations are called out to the user with the reason, never made silently.
**Implementation**: Read the relevant HIG page first. The site is JS-rendered; fetch `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json` (e.g. `app-icons`, `the-menu-bar`, `settings`, `popovers`) and extract the text.
**Example**: The app icon (`docs/icon/`) uses layered vector SVGs in Icon Composer with system-provided glass effects, per HIG "App icons".
