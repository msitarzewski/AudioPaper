# 2026-09

## Tasks Completed

### 2026-09-25: AudioPaper v0.1
- Built the app end to end: Apple Music source, album cover chain, TheAudioDB/DeviantArt/Brave fan art with Vision filtering, cross-fade slideshow, Settings, icon; published as a public MIT repo.
- Files: `Packages/AudioPaperKit/`, `App/`, `project.yml`, repo docs
- Pattern: plugin protocols + cheapest-first pipeline
- See: [260925_audiopaper-v0.1.md](./260925_audiopaper-v0.1.md)

### 2026-09-25: fanart.tv source
- Added `FanartTVSource` (4K + 1080p artist backgrounds) and shared `MusicBrainz` artist-ID resolution with an ambiguity guard; cover lookups now share the MusicBrainz rate limiter.
- Files: `FanArt/FanartTVSource.swift`, `Support/MusicBrainz.swift`, Settings → Accounts, tests + fixtures
