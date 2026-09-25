import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AudioPaperKit

/// Everything a service returns is untrusted, and web search results point anywhere. These tests pin the
/// rules that keep hostile responses from reaching local files, the local network, or unbounded memory.

@Suite struct URLPolicyTests {
    @Test(arguments: [
        "https://assets.fanart.tv/fanart/music/a.jpg",
        "https://upload.wikimedia.org/wikipedia/commons/a/ab/Photo.jpg",
        "https://images.example.cafe/x.png",
        "https://xn--bcher-kva.example/x.jpg",
    ])
    func allowsHTTPSToNamedHosts(_ string: String) throws {
        #expect(try #require(URL(string: string)).isAllowedRemote)
    }

    @Test(arguments: [
        "http://assets.fanart.tv/a.jpg",            // plain http
        "file:///etc/hosts", "file://localhost/etc/hosts",
        "smb://attacker.example/share",
        "https://192.168.1.1/admin", "https://127.0.0.1:8080/", "https://10.0.0.2/x",
        "https://127.1/", "https://0x7f.0x1/",       // IPv4 shorthand
        "https://[::1]/", "https://[fe80::1]/x",
        "https://localhost/x", "https://printer.local/x", "https://nas.home.arpa/x", "https://router.lan/x",
        "https://intranet/x",                        // single label
        "https://user:pass@example.com/x",
    ])
    func refusesEverythingElse(_ string: String) throws {
        #expect(!(try #require(URL(string: string)).isAllowedRemote))
    }

    @Test func creditLinksMustBeWebLinks() {
        #expect(URL(string: "https://www.deviantart.com/someone")!.isWebLink)
        #expect(URL(string: "http://example.com/page")!.isWebLink)
        for string in ["smb://attacker/x", "file:///Applications/Calculator.app", "shortcuts://run-shortcut?name=x",
                       "x-apple.systempreferences:com.apple.preference", "javascript:alert(1)", "https:///nohost"] {
            #expect(URL(string: string)?.isWebLink != true, "\(string)")
        }
    }

    @Test func attributionDropsNonWebLinksWhenBuiltAndWhenDecoded() throws {
        let built = Attribution(creatorProfileURL: URL(string: "smb://a/b"), pageURL: URL(string: "file:///etc/hosts"), sourceName: "x")
        #expect(built.creatorProfileURL == nil && built.pageURL == nil)

        let json = #"{"sourceName":"x","pageURL":"shortcuts://run-shortcut?name=x","creatorAvatarURL":"https://a.example/p.png"}"#
        let decoded = try JSONDecoder().decode(Attribution.self, from: Data(json.utf8))
        #expect(decoded.pageURL == nil)
        #expect(decoded.creatorAvatarURL == URL(string: "https://a.example/p.png"))
    }

    @Test func candidatesDecodedFromOlderCachesAreNotLocal() throws {
        let json = #"{"imageURL":"file:///etc/hosts","kind":"fanArt","providerID":"x","attribution":{"sourceName":"x"},"matchScore":1}"#
        #expect(try JSONDecoder().decode(ArtworkCandidate.self, from: Data(json.utf8)).isLocal == false)
    }
}

@Suite struct BraveResultSafetyTests {
    func candidates(_ results: String) throws -> [ArtworkCandidate] {
        let response = try JSONDecoder().decode(BraveImageSource.Response.self, from: Data(#"{"results":[\#(results)]}"#.utf8))
        return BraveImageSource.candidates(from: response, for: .sample())
    }

    @Test func dropsLocalAndLANImageAddresses() throws {
        let found = try candidates("""
        {"title":"Nine Inch Nails Closer fan art","url":"https://a.example/1","properties":{"url":"file://localhost/etc/hosts"}},
        {"title":"Nine Inch Nails Closer fan art","url":"https://a.example/2","properties":{"url":"https://192.168.1.10/a.jpg"}},
        {"title":"Nine Inch Nails Closer fan art","url":"https://a.example/3","properties":{"url":"https://printer.local/a.jpg"}}
        """)
        #expect(found.isEmpty)
    }

    @Test func upgradesPlainHTTPImagesAndNamesTheRealSite() throws {
        let found = try candidates("""
        {"title":"Nine Inch Nails Closer fan art","url":"https://www.wallpapers.example/nin","source":"wikipedia.org",
         "properties":{"url":"http://img.wallpapers.example/nin.jpg","width":1920,"height":1080}}
        """)
        let candidate = try #require(found.first)
        #expect(candidate.imageURL.absoluteString == "https://img.wallpapers.example/nin.jpg")
        #expect(candidate.attribution.sourceName == "wallpapers.example", "not the self-reported source")
    }

    @Test func dropsNonWebPageLinks() throws {
        let found = try candidates("""
        {"title":"Nine Inch Nails Closer fan art","url":"smb://attacker.example/share","source":"wikipedia.org",
         "properties":{"url":"https://img.example.com/nin.jpg"}}
        """)
        let candidate = try #require(found.first)
        #expect(candidate.attribution.pageURL == nil)
        #expect(candidate.attribution.sourceName == "img.example.com")
    }
}

@Suite struct CacheSafetyTests {
    @Test func networkCandidatesWithFileURLsAreNeverRead() async throws {
        let cache = ArtworkCache(root: Fixture.temporaryDirectory(), http: URLSessionHTTPClient())
        let candidate = ArtworkCandidate(imageURL: URL(filePath: "/etc/hosts"), kind: .fanArt, providerID: "x",
                                         attribution: Attribution(sourceName: "x"))
        await #expect(throws: HTTPError.self) { try await cache.download(candidate) }
    }

    @Test func localPlayerArtworkIsCopied() async throws {
        let directory = Fixture.temporaryDirectory()
        let file = directory.appending(path: "cover.png")
        try Fixture.png(width: 600, height: 600).write(to: file)
        let cache = ArtworkCache(root: directory.appending(path: "cache"), http: StubHTTP { _ in nil })
        let candidate = ArtworkCandidate(imageURL: file, kind: .albumCover, providerID: "apple-music-local",
                                         attribution: Attribution(sourceName: "Music"), isLocal: true)
        let (_, width, height) = try await cache.download(candidate)
        #expect(width == 600 && height == 600)
    }

    @Test func refusesImagesTooLargeToDecodeSafely() async throws {
        // A decompression bomb stand-in: a tiny file whose header claims an edge past the limit.
        let cache = ArtworkCache(root: Fixture.temporaryDirectory(), http: StubHTTP { _ in Fixture.png(width: 20_000, height: 1) })
        await #expect(throws: (any Error).self) { try await cache.download(fanArtCandidate("wide.png")) }
    }

    @Test func refusesFormatsServicesDontServe() async throws {
        let gif = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(gif, UTType.gif.identifier as CFString, 1, nil))
        let image = try #require(ImageLoading.thumbnail(from: Fixture.png(width: 1920, height: 1080), maxPixelSize: 1920))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        let data = gif as Data
        let cache = ArtworkCache(root: Fixture.temporaryDirectory(), http: StubHTTP { _ in data })
        await #expect(throws: (any Error).self) { try await cache.download(fanArtCandidate("animated.gif")) }
    }

    @Test func thumbnailsOfUntrustedDataAreBounded() {
        #expect(ImageLoading.thumbnail(from: Fixture.png(width: 400, height: 400), maxPixelSize: 96)?.width == 96)
        #expect(ImageLoading.thumbnail(from: Fixture.png(width: 20_000, height: 1), maxPixelSize: 96) == nil)
        #expect(ImageLoading.thumbnail(from: Data("not an image".utf8), maxPixelSize: 96) == nil)
    }
}

// MARK: - The HTTP client, against a stubbed network

/// Serves canned responses per host, so requests never leave the test process.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Route {
        case redirect(to: String)
        case respond(status: Int, headers: [String: String] = [:], body: Data = Data())
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: Route] = [:]
    nonisolated(unsafe) private static var received: [String: [URLRequest]] = [:]

    static func route(_ host: String, _ route: Route) { lock.withLock { routes[host] = route } }
    static func requests(to host: String) -> [URLRequest] { lock.withLock { received[host] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        let route = Self.lock.withLock {
            Self.received[host, default: []].append(request)
            return Self.routes[host]
        }
        switch route {
        case let .redirect(target):
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": target])!
            var next = request
            next.url = URL(string: target)
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
        case let .respond(status, headers, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }

    override func stopLoading() {}

    static func client(maxResponseBytes: Int64 = URLSessionHTTPClient.maxResponseBytes) -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.timeoutIntervalForResource = 10
        return URLSessionHTTPClient(session: URLSession(configuration: configuration), maxResponseBytes: maxResponseBytes)
    }
}

@Suite struct HTTPClientSafetyTests {
    /// Each test uses its own hosts, since the stub routes and the backoff registry are shared.
    func host(_ name: String) -> String { "\(name)-\(UUID().uuidString.prefix(8).lowercased()).example" }

    @Test func refusesBlockedAddressesWithoutSendingAnything() async throws {
        let client = StubProtocol.client()
        for string in ["http://example.com/x", "file:///etc/hosts", "https://192.168.1.1/"] {
            await #expect(throws: HTTPError.self) { try await client.data(for: URLRequest(url: URL(string: string)!)) }
        }
    }

    @Test func refusesRedirectsToTheLocalNetwork() async throws {
        let start = host("redirector")
        StubProtocol.route(start, .redirect(to: "https://192.168.1.1/admin"))
        await #expect(throws: HTTPError.self) {
            try await StubProtocol.client().data(for: URLRequest(url: URL(string: "https://\(start)/img.jpg")!))
        }
        #expect(StubProtocol.requests(to: "192.168.1.1").isEmpty)
    }

    @Test func dropsCredentialsWhenARedirectChangesHost() async throws {
        let (start, target) = (host("api"), host("cdn"))
        StubProtocol.route(start, .redirect(to: "https://\(target)/img.jpg"))
        StubProtocol.route(target, .respond(status: 200, body: Data("ok".utf8)))
        var request = URLRequest(url: URL(string: "https://\(start)/search")!)
        request.setValue("secret-token", forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (data, _) = try await StubProtocol.client().data(for: request)
        #expect(data == Data("ok".utf8))
        let forwarded = try #require(StubProtocol.requests(to: target).last)
        #expect(forwarded.value(forHTTPHeaderField: "X-Subscription-Token") == nil)
        #expect(forwarded.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func stopsReadingOversizedResponses() async throws {
        let big = host("big")
        StubProtocol.route(big, .respond(status: 200, body: Data(count: 5_000)))
        await #expect(throws: HTTPError.self) {
            try await StubProtocol.client(maxResponseBytes: 1_000).data(for: URLRequest(url: URL(string: "https://\(big)/x")!))
        }
    }

    @Test func honoursRetryAfterWithoutHammering() async throws {
        let limited = host("limited")
        StubProtocol.route(limited, .respond(status: 429, headers: ["Retry-After": "120"]))
        let client = StubProtocol.client()
        let url = URL(string: "https://\(limited)/api")!
        for _ in 0..<3 {
            await #expect(throws: HTTPError.self) { try await client.data(for: URLRequest(url: url)) }
        }
        #expect(StubProtocol.requests(to: limited).count == 1, "later calls wait out the Retry-After locally")
    }

    @Test func aMomentaryLimitIsWaitedOutOnce() async throws {
        let busy = host("busy")
        StubProtocol.route(busy, .respond(status: 503, headers: ["Retry-After": "1"]))
        let client = StubProtocol.client()
        let url = URL(string: "https://\(busy)/api")!
        let clock = ContinuousClock.now
        await #expect(throws: HTTPError.self) { try await client.data(for: URLRequest(url: url)) }
        #expect(StubProtocol.requests(to: busy).count == 2, "one retry after the short wait, then the host is paused")
        #expect(ContinuousClock.now - clock >= .seconds(1))
    }

    @Test func retryAfterIsParsedAndBounded() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HostBackoff.delay(retryAfter: "30", now: now) == 30)
        #expect(HostBackoff.delay(retryAfter: nil, now: now) == 10)
        #expect(HostBackoff.delay(retryAfter: nil, rateLimitReset: "1000002", now: now) == 2, "MusicBrainz's reset time")
        #expect(HostBackoff.delay(retryAfter: "30", rateLimitReset: "1000002", now: now) == 30, "Retry-After wins")
        #expect(HostBackoff.delay(retryAfter: "999999", now: now) == 3600, "capped at an hour")
        #expect(HostBackoff.delay(retryAfter: "-5", now: now) == 1)
        // `now` is Mon, 12 Jan 1970 13:46:40 GMT.
        #expect(HostBackoff.delay(retryAfter: "Mon, 12 Jan 1970 13:48:10 GMT", now: now) == 90)
    }

    @Test func transientFailuresAreToldApartFromAnswers() {
        #expect(HTTPError.isTransient(HTTPError.status(503, nil)))
        #expect(HTTPError.isTransient(HTTPError.rateLimited(host: "x", until: .now)))
        #expect(HTTPError.isTransient(URLError(.notConnectedToInternet)))
        #expect(!HTTPError.isTransient(HTTPError.status(404, nil)))
        #expect(!HTTPError.isTransient(HTTPError.blockedURL(nil)))
    }
}

// MARK: - Searches that couldn't finish aren't remembered as finding nothing

@Suite struct IncompleteSearchTests {
    struct FailingFanArt: FanArtSource {
        var id = "failing"
        var displayName = "Failing"
        var isConfigured = true
        var isFallback = false
        var error: any Error & Sendable
        func candidates(for track: Track, limit: Int) async throws -> [ArtworkCandidate] { throw error }
    }

    func events(for error: any Error & Sendable) async -> [FanArtPipeline.Event] {
        let pipeline = FanArtPipeline(sources: [FailingFanArt(error: error)], cache: ArtworkCache(root: Fixture.temporaryDirectory(), http: StubHTTP { _ in nil }))
        var events: [FanArtPipeline.Event] = []
        for await event in pipeline.run(for: .sample()) { events.append(event) }
        return events
    }

    @Test func outagesAndRateLimitsMarkTheSearchIncomplete() async {
        let events = await events(for: HTTPError.rateLimited(host: "webservice.fanart.tv", until: .now))
        #expect(events.contains { if case .incomplete(sourceID: "failing", _) = $0 { true } else { false } })
    }

    @Test func otherFailuresCountAsNothingFound() async {
        let events = await events(for: HTTPError.status(404, nil))
        #expect(!events.contains { if case .incomplete = $0 { true } else { false } })
    }
}

@Suite struct TrackInputTests {
    @Test func queryPhrasesCantBreakOutOfTheirQuotes() {
        #expect(MusicBrainz.phrase(#"Say "Hi" \"#) == "Say Hi ")
        #expect(!MusicBrainz.phrase(#"a\"#).contains("\\"))
    }

    @Test func notificationFieldsAreLengthLimited() throws {
        let long = String(repeating: "x", count: 10_000)
        let track = try #require(AppleMusicSource.track(from: ["Name": long, "Artist": long, "Album": long]))
        #expect(track.title.count == AppleMusicSource.maxFieldLength)
        #expect(track.artist.count == AppleMusicSource.maxFieldLength)
        #expect(track.album.count == AppleMusicSource.maxFieldLength)
    }

    @Test func searchBudgetBoundsAFloodOfTrackChanges() {
        var budget = SearchBudget(limit: 3, window: .seconds(60))
        let start = ContinuousClock.now
        var results: [Bool] = []
        for _ in 0..<5 { results.append(budget.allow(at: start)) }
        #expect(results == [true, true, true, false, false])
        let later = budget.allow(at: start + .seconds(61))
        #expect(later, "the window slides")
    }
}
