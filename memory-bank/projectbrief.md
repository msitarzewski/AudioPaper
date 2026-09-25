# Project Brief — AudioPaper

A small, native macOS 26+ menu bar app that changes the desktop wallpaper to match the music playing.

## Goals
- Detect track changes in Apple Music (first player); add others (Spotify next) as plugins.
- Show the album cover immediately, sourced from the internet.
- Then cross-fade in song fan art, found online and filtered on-device to "pure art" (no text, no screenshots, no merch), rotating like a Photos-folder wallpaper slideshow.
- Keep artist attribution (DeviantArt profile, source page) visible and clickable in the app.
- Apple-native APIs only (SwiftUI, AppKit, Core Image, Vision, ImageIO). No third-party dependencies.
