import Foundation
import Testing
@testable import AudioPaperKit

@Suite struct AlbumProviderTests {
    @Test func iTunesPicksOriginalAlbumAndRequestsFullSizeArt() throws {
        let response = try Fixture.decode(ITunesSearchProvider.Response.self, "itunes-in-rainbows")
        let track = Track.sample("Nude", artist: "Radiohead", album: "In Rainbows (Deluxe Edition)")
        let candidate = try #require(ITunesSearchProvider.bestMatch(in: response, for: track))
        #expect(candidate.attribution.title == "In Rainbows")
        #expect(candidate.attribution.creatorName == "Radiohead")
        #expect(candidate.imageURL.absoluteString.hasSuffix("/3000x3000bb.jpg"))
        #expect(candidate.kind == .albumCover)
        #expect(candidate.matchScore == 1)
    }

    @Test func musicBrainzPicksExactReleaseGroup() throws {
        let response = try Fixture.decode(CoverArtArchiveProvider.Response.self, "musicbrainz-downward-spiral")
        let candidate = try #require(CoverArtArchiveProvider.bestMatch(in: response, for: .sample()))
        #expect(candidate.attribution.title == "The Downward Spiral")
        #expect(candidate.imageURL.host() == "coverartarchive.org")
        #expect(candidate.imageURL.path().hasSuffix("/front-1200"))
    }

    @Test func chainFallsThroughToNextProviderWhenFirstHasNoMatch() async throws {
        let http = StubHTTP { url in
            switch url.host() {
            case "itunes.apple.com": Data(#"{"resultCount":0,"results":[]}"#.utf8)
            case "musicbrainz.org": try? Fixture.data("musicbrainz-downward-spiral")
            default: nil
            }
        }
        let chain = AlbumArtworkChain(providers: [ITunesSearchProvider(http: http, country: "US"), CoverArtArchiveProvider(http: http)])
        let candidate = try #require(await chain.artwork(for: .sample()))
        #expect(candidate.providerID == "coverartarchive")
        #expect(http.requests.map { $0.host() } == ["itunes.apple.com", "musicbrainz.org"])
    }
}

@Suite struct FanArtSourceTests {
    @Test func braveDropsMerchHostsAndDecodesTitles() throws {
        let response = try Fixture.decode(BraveImageSource.Response.self, "brave-closer")
        let candidates = BraveImageSource.candidates(from: response, for: .sample())
        #expect(!candidates.isEmpty)
        for candidate in candidates {
            let host = try #require(candidate.imageURL.host())
            #expect(!BraveImageSource.isBlocked(host))
            #expect(!BraveImageSource.isBlocked(candidate.attribution.pageURL?.host()))
            #expect(candidate.attribution.title == "Nine Inch Nails", "credited to the matched artist, not the page title")
        }
        #expect(response.results.count > candidates.count, "fixture contains Etsy/Redbubble results that must be dropped")
    }

    @Test func braveRequiresArtistPlusSongAlbumOrMusicContext() {
        let band = Track.sample("Run It", artist: "Sleepover", album: "Cactus Club")
        #expect(BraveImageSource.relevance(title: "Sleepover Aesthetic Anime Art Desktop Wallpaper", pageURL: nil, track: band) == nil)
        #expect(BraveImageSource.relevance(title: "Sleepover band live wallpaper", pageURL: nil, track: band) == 0.6)
        #expect(BraveImageSource.relevance(title: "Cactus Club artwork", pageURL: URL(string: "https://x.example/sleepover-fan-art"), track: band) == 0.8)
        #expect(BraveImageSource.relevance(title: "Run It — Sleepover fan art", pageURL: nil, track: band) == 1)
        #expect(BraveImageSource.relevance(title: "Music Nine Inch Nails Wallpaper", pageURL: nil, track: .sample()) == 0.6)
        #expect(BraveImageSource.relevance(title: "Closer poster", pageURL: nil, track: .sample()) == nil, "must name the artist")
        let rose = Track.sample("new trick", artist: "ROSÉ", album: "new trick")
        #expect(BraveImageSource.relevance(title: "Rose singer album wallpaper", pageURL: nil, track: rose) == nil, "accents distinguish artists")
        #expect(BraveImageSource.relevance(title: "Rosé new trick fan art", pageURL: nil, track: rose) == 1)
        #expect(BraveImageSource.relevance(title: "HD Wallpaper: Nine Inch Nails Inspired Art", pageURL: nil, track: .sample()) == 0.5)
    }

    @Test func braveIsUnconfiguredWithoutKey() async throws {
        let source = BraveImageSource(http: StubHTTP { _ in nil }, secrets: StubSecrets(values: [:]))
        #expect(!source.isConfigured)
        #expect(try await source.candidates(for: .sample(), limit: 10).isEmpty)
    }

    @Test func braveSendsKeyHeaderAndStrictSafeSearch() async throws {
        let http = StubHTTP { _ in try? Fixture.data("brave-closer") }
        let source = BraveImageSource(http: http, secrets: StubSecrets(values: [.braveAPIKey: "test-key"]))
        _ = try await source.candidates(for: .sample(), limit: 5)
        let url = try #require(http.requests.first)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "safesearch", value: "strict")))
        #expect(query.first { $0.name == "q" }?.value == "Nine Inch Nails Closer fan art wallpaper")
    }

    @Test func deviantArtKeepsArtistMetadataAndSkipsMatureAndImagelessPosts() throws {
        let response = try Fixture.decode(DeviantArtSource.BrowseResponse.self, "deviantart-browse")
        let candidates = DeviantArtSource.candidates(from: response, song: "Closer")
        #expect(candidates.count == 1)
        let art = try #require(candidates.first)
        #expect(art.attribution.creatorName == "example-artist")
        #expect(art.attribution.creatorProfileURL?.absoluteString == "https://www.deviantart.com/example-artist")
        #expect(art.attribution.creatorAvatarURL != nil)
        #expect(art.attribution.pageURL?.absoluteString == "https://www.deviantart.com/example-artist/art/Closer-Tribute-1000000001")
        #expect(art.width == 2560 && art.height == 1440)
        #expect(art.matchScore == 1, "title matches the song exactly")
    }

    @Test func deviantArtTagIsSingleLowercaseWord() {
        #expect(DeviantArtSource.tag(for: "Nine Inch Nails") == "nineinchnails")
        #expect(DeviantArtSource.tag(for: "The Smashing Pumpkins") == "smashingpumpkins")
    }

    @Test func deviantArtFetchesTokenOnceAndSendsBearer() async throws {
        let http = StubHTTP { url in
            if url.path() == "/oauth2/token" { return Data(#"{"access_token":"tok","expires_in":3600,"status":"success"}"#.utf8) }
            return try? Fixture.data("deviantart-browse")
        }
        let source = DeviantArtSource(http: http, secrets: StubSecrets(values: [.deviantArtClientID: "id", .deviantArtClientSecret: "secret"]))
        #expect(source.isConfigured)
        _ = try await source.candidates(for: .sample(), limit: 10)
        _ = try await source.candidates(for: .sample(), limit: 10)
        #expect(http.requests.filter { $0.path() == "/oauth2/token" }.count == 1)
        #expect(http.requests.contains { $0.path().hasSuffix("/browse/tags") })
    }
}

@Suite struct TheAudioDBSourceTests {
    @Test func artistFanArtIsCredited() throws {
        let response = try Fixture.decode(TheAudioDBSource.Response.self, "theaudiodb-nin")
        let candidates = TheAudioDBSource.candidates(from: response, for: .sample(), match: .byID)
        #expect(candidates.count == 4)
        for candidate in candidates {
            #expect(candidate.attribution.sourceName == "TheAudioDB")
            #expect(candidate.attribution.pageURL?.absoluteString == "https://www.theaudiodb.com/artist/111402")
        }
    }

    @Test func differentArtistIsIgnored() throws {
        let response = try Fixture.decode(TheAudioDBSource.Response.self, "theaudiodb-nin")
        #expect(TheAudioDBSource.candidates(from: response, for: .sample(artist: "Nine Days"), match: .byName).isEmpty)
    }

    @Test func nameFallbackRequiresAccentExactMatch() throws {
        let rose = try JSONDecoder().decode(TheAudioDBSource.Response.self, from: Data(#"{"artists":[{"idArtist":"1","strArtist":"Rose","strArtistFanart":"https://r2.theaudiodb.com/rose.jpg"}]}"#.utf8))
        #expect(TheAudioDBSource.candidates(from: rose, for: .sample("new trick", artist: "ROSÉ"), match: .byName).isEmpty)
        #expect(TheAudioDBSource.candidates(from: rose, for: .sample(artist: "Rose"), match: .byName).count == 1)
    }

    @Test func usesFreeKeyUnlessPersonalKeyIsSet() async throws {
        let http = StubHTTP { _ in try? Fixture.data("theaudiodb-nin") }
        let source = TheAudioDBSource(http: http, secrets: StubSecrets(values: [:]))
        #expect(source.isConfigured)
        _ = try await source.candidates(for: .sample(artist: "Free Key Artist \(UUID())"), limit: 10)
        #expect(http.requests.first { $0.host() == "www.theaudiodb.com" }?.path().contains("/json/123/") == true)

        let personal = StubHTTP { _ in try? Fixture.data("theaudiodb-nin") }
        _ = try await TheAudioDBSource(http: personal, secrets: StubSecrets(values: [.theAudioDBAPIKey: "mine"]))
            .candidates(for: .sample(artist: "Personal Key Artist \(UUID())"), limit: 10)
        #expect(personal.requests.first { $0.host() == "www.theaudiodb.com" }?.path().contains("/json/mine/") == true)
    }
}

@Suite struct FanartTVSourceTests {
    @Test func fourKBackgroundsComeFirstAndEverythingIsCredited() throws {
        let response = try Fixture.decode(FanartTVSource.Response.self, "fanarttv-nin")
        let candidates = FanartTVSource.candidates(from: response, mbid: "b7ffd2af-418f-4be2-bdd1-22f8b48613da")
        #expect(candidates.count == (response.artist4kbackground?.count ?? 0) + (response.artistbackground?.count ?? 0))
        #expect(candidates.first?.width == 3840)
        for candidate in candidates {
            #expect(candidate.attribution.sourceName == "fanart.tv")
            #expect(candidate.attribution.pageURL?.absoluteString == "https://fanart.tv/artist/b7ffd2af-418f-4be2-bdd1-22f8b48613da/")
        }
    }

    @Test func sendsPersonalKeyAlongsideProjectKey() async throws {
        // Unique per run so the per-artist memo from other tests can't answer first.
        let artist = "Keyed Artist \(UUID().uuidString.prefix(8))"
        let http = StubHTTP { url in
            url.host() == "musicbrainz.org"
                ? Data(#"{"artists":[{"id":"mbid-1","name":"\#(artist)","score":100}]}"#.utf8)
                : try? Fixture.data("fanarttv-nin")
        }
        let source = FanartTVSource(http: http, secrets: StubSecrets(values: [.fanartTVProjectKey: "project", .fanartTVClientKey: "personal"]))
        let candidates = try await source.candidates(for: .sample(artist: artist), limit: 10)
        #expect(!candidates.isEmpty)
        let request = try #require(http.requests.first { $0.host() == "webservice.fanart.tv" })
        #expect(request.path() == "/v3/music/mbid-1")
        let items = URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "api_key", value: "project")))
        #expect(items.contains(URLQueryItem(name: "client_key", value: "personal")))
    }

    @Test func unconfiguredWithoutProjectKey() {
        #expect(!FanartTVSource(http: StubHTTP { _ in nil }, secrets: StubSecrets(values: [:])).isConfigured)
    }
}

@Suite struct MusicBrainzTests {
    @Test func ambiguousArtistNameResolvesToNothing() throws {
        let response = try Fixture.decode(MusicBrainz.ArtistSearch.self, "musicbrainz-artist-sleepover")
        #expect(MusicBrainz.resolve(response, name: "Sleepover") == nil, "several artists are named Sleepover")
    }

    @Test func recordingSearchPicksTheArtistWhoRecordedTheSong() throws {
        let response = try Fixture.decode(MusicBrainz.RecordingSearch.self, "musicbrainz-recording-new-trick")
        #expect(MusicBrainz.resolve(response, artist: "ROSÉ") == "7f233cda-eacb-4235-b681-5f7be343a1a2")
    }

    @Test func featuredArtistResolvesFromTheRecording() throws {
        let response = try JSONDecoder().decode(MusicBrainz.RecordingSearch.self, from: Data(#"{"recordings":[{"score":100,"artist-credit":[{"name":"LE SSERAFIM","artist":{"id":"ls"}},{"name":"j-hope","artist":{"id":"jh"}}]}]}"#.utf8))
        #expect(MusicBrainz.resolve(response, artist: "j-hope") == "jh")
        #expect(MusicBrainz.resolve(response, artist: "LE SSERAFIM") == "ls")
    }

    @Test func accentExactArtistBeatsFoldedNamesakes() throws {
        let response = try JSONDecoder().decode(MusicBrainz.ArtistSearch.self, from: Data(#"{"artists":[{"id":"rose-fr","name":"Rose","score":100},{"id":"rose-kr","name":"ROSÉ","score":95}]}"#.utf8))
        #expect(MusicBrainz.resolve(response, name: "ROSÉ") == "rose-kr")
        #expect(MusicBrainz.resolve(response, name: "Rose") == "rose-fr")
    }

    @Test func uniqueExactNameResolves() throws {
        let response = try JSONDecoder().decode(MusicBrainz.ArtistSearch.self, from: Data(#"{"artists":[{"id":"a","name":"Nine Inch Nails","score":100},{"id":"b","name":"Nine Inch Nails Tribute","score":80}]}"#.utf8))
        #expect(MusicBrainz.resolve(response, name: "Nine Inch Nails") == "a")
    }
}

@Suite struct AppleMusicSourceTests {
    let info: [AnyHashable: Any] = [
        "Player State": "Playing", "Name": "Closer", "Artist": "Nine Inch Nails",
        "Album": "The Downward Spiral", "Album Artist": "Nine Inch Nails", "PersistentID": NSNumber(value: -4_280_000_000_000_000_000 as Int64),
    ]

    @Test func playingNotificationBecomesTrack() throws {
        guard case let .playing(track)? = AppleMusicSource.event(from: info) else {
            Issue.record("expected .playing")
            return
        }
        #expect(track.title == "Closer")
        #expect(track.album == "The Downward Spiral")
        #expect(track.persistentID?.isEmpty == false)
        #expect(track.sourceID == "apple-music")
    }

    @Test func pausedAndStoppedStates() {
        var paused = info
        paused["Player State"] = "Paused"
        #expect(AppleMusicSource.event(from: paused) == .paused(AppleMusicSource.track(from: info)))
        #expect(AppleMusicSource.event(from: ["Player State": "Stopped"]) == .stopped)
    }

    @Test func streamWithoutArtistIsIgnored() {
        #expect(AppleMusicSource.event(from: ["Player State": "Playing", "Name": "Beats 1"]) == nil)
    }
}
