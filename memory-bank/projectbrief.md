# Project Brief — AudioPaper

A small, native macOS 26+ app that changes the desktop wallpaper to match the music playing.

## Goals
- Detect track changes in Apple Music (first player); add others (Spotify next) as plugins.
- Show the album cover immediately, sourced from the internet (Music's own artwork as a last resort).
- Then cross-fade in fan art and artist photos (photos are welcome, per the user), found online and filtered on-device: no prominent text, no screenshots, ads or merch. Rotate them like a Photos-folder wallpaper slideshow.
- Keep attribution (artist profile, source page) visible and clickable everywhere artwork appears.
- Surfaces, per Apple's HIG: a native menu bar menu, a Music-style Mini Player window, desktop widgets, and a Dock presence only while needed.
- Apple-native APIs only (SwiftUI, AppKit, WidgetKit, Core Image, Vision, ImageIO). No third-party dependencies.
- Public, MIT-licensed, sponsor-supported (github.com/msitarzewski/AudioPaper).
