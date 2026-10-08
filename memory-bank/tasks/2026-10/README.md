# October 2026

## Tasks Completed

### 2026-10-04: Album-less songs find their cover (0.1.9)
- A song with a blank Album in Music was never looked up for a cover, so the desktop went straight to fan art. Found by reading the app's `image credits` over AppleScript (the first image was a photo).
- Now looked up as a song in the Apple Music catalog (title + artist); Music's embedded artwork is the fallback; each album-less song has its own cover key (`single:<title>`). Files: `Artwork/ITunesSearchProvider.swift`, `Artwork/CoverArtArchiveProvider.swift`, `Model/Track.swift`, `NowPlayingCoordinator.swift`; test `iTunesFindsTheCoverOfASongWithNoAlbum`. 143 tests. Released as v0.1.9 (`ed3faa3`, feed `94181f0`).

### 2026-10-07: DeviantArt verified end to end
- Maintainer reply on issue #1181 (2026-09-27): "Per-user credentials are fine to use!" Closed as completed.
- Live run with the user's own credentials through `apctl fanart`: token and browse worked; 11-17 candidates per artist; 1 of 53 passed the filters (mostly small or square). Credentials were read from the Keychain into the process environment only, never printed or written.
