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

    public var errorDescription: String? {
        switch self {
        case let .status(code, url): "HTTP \(code) from \(url?.host() ?? "unknown host")"
        case .notHTTP: "Response was not HTTP"
        }
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    public static let userAgent = "AudioPaper/0.1 ( macOS album-art wallpaper app )"

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
        return URLSession(configuration: configuration)
    }()

    public init(session: URLSession = URLSessionHTTPClient.privateSession) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw HTTPError.status(http.statusCode, request.url) }
        return (data, http)
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
