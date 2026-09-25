import Foundation
import os

let log = Logger(subsystem: "com.audiopaper", category: "kit")

/// Minimal HTTP seam so providers can be tested against recorded responses.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public enum HTTPError: Error, LocalizedError {
    case status(Int, URL?)
    case notHTTP
    /// The address isn't one AudioPaper will contact (see `URL.isAllowedRemote`).
    case blockedURL(URL?)
    /// The response was larger than `URLSessionHTTPClient.maxResponseBytes`.
    case tooLarge(URL?)
    /// The service asked us to slow down (HTTP 429/503); nothing is sent to that host until `until`.
    case rateLimited(host: String, until: Date)

    public var errorDescription: String? {
        switch self {
        case let .status(code, url): "HTTP \(code) from \(url?.host() ?? "unknown host")"
        case .notHTTP: "Response was not HTTP"
        case let .blockedURL(url): "Refused to contact \(url?.scheme ?? "?")://\(url?.host() ?? "")"
        case let .tooLarge(url): "Response from \(url?.host() ?? "unknown host") was too large"
        case let .rateLimited(host, until): "\(host) asked to wait until \(until.formatted(date: .omitted, time: .standard))"
        }
    }

    /// A failure that says nothing about whether the thing searched for exists: the search should be
    /// tried again later rather than remembered as having found nothing.
    public static func isTransient(_ error: any Error) -> Bool {
        switch error {
        case HTTPError.status(let code, _): code == 408 || code == 429 || code >= 500
        case HTTPError.rateLimited, HTTPError.tooLarge, HTTPError.notHTTP, is URLError, is CancellationError: true
        default: false
        }
    }
}

extension URL {
    /// Whether AudioPaper may send a request here: `https` to a named internet host. Everything a service
    /// returns is untrusted, and web search results point anywhere, so this refuses plain `http`, other
    /// schemes (`file:`, `smb:`, …), IP-address literals, `localhost`, `.local` and single-label names —
    /// nothing on your own network can be reached through a search result or a redirect.
    public var isAllowedRemote: Bool {
        guard scheme?.lowercased() == "https", let host = host(percentEncoded: false)?.lowercased(),
              user == nil, password == nil
        else { return false }
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        guard name.contains("."), !name.contains(":"), !name.hasPrefix("[") else { return false }
        // A numeric last label means an IPv4 literal, including shorthand like 127.1 or 0x7f.0x1;
        // every real top-level domain starts with a letter.
        guard let tld = name.split(separator: ".").last, tld.first?.isLetter == true else { return false }
        let local = ["localhost", "local", "internal", "home.arpa", "lan", "intranet", "private", "corp", "home"]
        return !local.contains { name == $0 || name.hasSuffix("." + $0) }
    }

    /// A link that's safe to open in the browser when someone clicks a credit: `https`, or `http`, with a
    /// host. Anything else a service returns (`file:`, `smb:`, `shortcuts:`, custom app schemes) is dropped.
    public var isWebLink: Bool {
        guard let scheme = scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return !(host(percentEncoded: false) ?? "").isEmpty
    }

    /// `self` when it's a safe web link, else nil. For links taken from service responses.
    public var webLink: URL? { isWebLink ? self : nil }
}

public struct URLSessionHTTPClient: HTTPClient {
    /// Identifies AudioPaper, with a contact address as Wikimedia and MusicBrainz ask of API clients.
    public static let userAgent = "AudioPaper/0.1 (https://github.com/msitarzewski/AudioPaper; macOS album-art wallpaper app)"
    /// Largest response accepted, for images and API replies alike. The biggest images AudioPaper uses
    /// (4K fan art, 3000 px covers, 4000 px photos) are well under this.
    public static let maxResponseBytes: Int64 = 40_000_000
    /// Headers that carry credentials; dropped when a redirect leaves the host they were meant for.
    static let credentialHeaders = ["Authorization", "X-Subscription-Token"]

    private let session: URLSession

    /// Every request AudioPaper makes goes through this session. It is ephemeral: no cookies are stored or
    /// sent, and nothing is written to an HTTP disk cache, so the image sites a search points to can't leave
    /// anything behind. Downloaded artwork is cached deliberately by `ArtworkCache` instead.
    public static let privateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // A whole request, however slowly the bytes arrive, gets one minute (the per-request idle
        // timeout alone would let a host drip a byte every few seconds forever).
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    private let limit: Int64

    public init(session: URLSession = URLSessionHTTPClient.privateSession, maxResponseBytes: Int64 = URLSessionHTTPClient.maxResponseBytes) {
        self.session = session
        self.limit = maxResponseBytes
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.isAllowedRemote else { throw HTTPError.blockedURL(request.url) }
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        try await HostBackoff.shared.check(host)
        var request = request
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        }
        let (data, http) = try await BoundedLoad(session: session, request: request, limit: limit).run()
        if http.statusCode == 429 || http.statusCode == 503 {
            let until = Date.now.addingTimeInterval(HostBackoff.delay(retryAfter: http.value(forHTTPHeaderField: "Retry-After")))
            await HostBackoff.shared.pause(host, until: until)
            log.info("\(host, privacy: .public) is rate limiting (HTTP \(http.statusCode)); pausing it")
            throw HTTPError.rateLimited(host: host, until: until)
        }
        guard (200..<300).contains(http.statusCode) else { throw HTTPError.status(http.statusCode, request.url) }
        return (data, http)
    }
}

/// Hosts that asked AudioPaper to back off (HTTP 429/503). Requests to them fail straight away, without
/// touching the network, until the time they asked for — so a rate limit is honoured, not hammered.
actor HostBackoff {
    static let shared = HostBackoff()
    private var pausedUntil: [String: Date] = [:]

    func check(_ host: String, now: Date = .now) throws {
        guard let until = pausedUntil[host] else { return }
        if until > now { throw HTTPError.rateLimited(host: host, until: until) }
        pausedUntil[host] = nil
    }

    func pause(_ host: String, until: Date) {
        pausedUntil[host] = max(until, pausedUntil[host] ?? .distantPast)
    }

    /// Seconds to wait from a `Retry-After` header (seconds, or an HTTP date), defaulting to a minute and
    /// capped at an hour so a hostile value can't switch a source off indefinitely.
    static func delay(retryAfter: String?, now: Date = .now) -> TimeInterval {
        let requested: TimeInterval? = retryAfter.flatMap { value in
            let value = value.trimmingCharacters(in: .whitespaces)
            if let seconds = TimeInterval(value) { return seconds }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return formatter.date(from: value).map { $0.timeIntervalSince(now) }
        }
        return min(max(requested ?? 60, 1), 3600)
    }
}

/// One request, read with limits: it refuses redirects to addresses `isAllowedRemote` rejects, drops
/// credential headers when a redirect changes host, and cancels once the body passes `limit` bytes.
private final class BoundedLoad: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let session: URLSession
    private let request: URLRequest
    private let limit: Int64
    private let lock = NSLock()
    private var received = Data()
    private var response: HTTPURLResponse?
    private var failure: (any Error)?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?

    init(session: URLSession, request: URLRequest, limit: Int64) {
        self.session = session
        self.request = request
        self.limit = limit
    }

    func run() async throws -> (Data, HTTPURLResponse) {
        let task = session.dataTask(with: request)
        task.delegate = self
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { self.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let target = newRequest.url, target.isAllowedRemote else {
            lock.withLock { failure = HTTPError.blockedURL(newRequest.url) }
            task.cancel()
            completionHandler(nil)
            return
        }
        var next = newRequest
        if target.host(percentEncoded: false)?.lowercased() != request.url?.host(percentEncoded: false)?.lowercased() {
            for header in URLSessionHTTPClient.credentialHeaders { next.setValue(nil, forHTTPHeaderField: header) }
        }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            lock.withLock { failure = HTTPError.notHTTP }
            completionHandler(.cancel)
            return
        }
        if http.expectedContentLength > limit {
            lock.withLock { failure = HTTPError.tooLarge(request.url) }
            completionHandler(.cancel)
            return
        }
        lock.withLock { self.response = http }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overLimit = lock.withLock {
            received.append(data)
            return Int64(received.count) > limit
        }
        if overLimit {
            lock.withLock { failure = HTTPError.tooLarge(request.url) }
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, result): (CheckedContinuation<(Data, HTTPURLResponse), any Error>?, Result<(Data, HTTPURLResponse), any Error>) = lock.withLock {
            defer { self.continuation = nil }
            if let failure { return (self.continuation, .failure(failure)) }
            if let error { return (self.continuation, .failure(error)) }
            guard let response else { return (self.continuation, .failure(HTTPError.notHTTP)) }
            return (self.continuation, .success((received, response)))
        }
        continuation?.resume(with: result)
    }
}

extension HTTPClient {
    func json<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, _) = try await data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension URL {
    /// Builds a URL from a base and query items, dropping empty values.
    static func api(_ base: String, _ query: [String: String]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
}

/// Spaces calls at least `interval` apart across the whole process (e.g. Brave's free tier: 1 request/second).
public actor RateLimiter {
    private let interval: Duration
    private var next = ContinuousClock.now

    public init(interval: Duration) {
        self.interval = interval
    }

    public func wait() async throws {
        let now = ContinuousClock.now
        let slot = max(now, next)
        next = slot + interval
        if slot > now { try await Task.sleep(until: slot) }
    }
}
