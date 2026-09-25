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
            #expect(!(candidate.attribution.title ?? "").contains("&quot;"))
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
    @Test func artistFanArtIsCuratedAndCredited() throws {
        let response = try Fixture.decode(TheAudioDBSource.Response.self, "theaudiodb-nin")
        let candidates = TheAudioDBSource.candidates(from: response, for: .sample())
        #expect(candidates.count == 4)
        for candidate in candidates {
            #expect(candidate.isCurated)
            #expect(candidate.attribution.sourceName == "TheAudioDB")
            #expect(candidate.attribution.pageURL?.absoluteString == "https://www.theaudiodb.com/artist/111402")
        }
    }

    @Test func differentArtistIsIgnored() throws {
        let response = try Fixture.decode(TheAudioDBSource.Response.self, "theaudiodb-nin")
        #expect(TheAudioDBSource.candidates(from: response, for: .sample(artist: "Nine Days")).isEmpty)
    }

    @Test func usesFreeKeyUnlessPersonalKeyIsSet() async throws {
        let http = StubHTTP { _ in try? Fixture.data("theaudiodb-nin") }
        let source = TheAudioDBSource(http: http, secrets: StubSecrets(values: [:]))
        #expect(source.isConfigured)
        _ = try await source.candidates(for: .sample(artist: "Free Key Artist \(UUID())"), limit: 10)
        #expect(http.requests.first?.path().contains("/json/123/") == true)

        let personal = StubHTTP { _ in try? Fixture.data("theaudiodb-nin") }
        _ = try await TheAudioDBSource(http: personal, secrets: StubSecrets(values: [.theAudioDBAPIKey: "mine"]))
            .candidates(for: .sample(artist: "Personal Key Artist \(UUID())"), limit: 10)
        #expect(personal.requests.first?.path().contains("/json/mine/") == true)
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
