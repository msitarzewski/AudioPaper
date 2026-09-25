import CoreGraphics
import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import AudioPaperKit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }

    /// A solid-colour PNG of the given size, standing in for a downloaded image.
    static func png(width: Int, height: Int, red: CGFloat = 0.8) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: red, green: 0.2, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "AudioPaperTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Serves canned responses; records requested URLs.
final class StubHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URL] = []
    private let responder: @Sendable (URL) -> Data?

    init(_ responder: @escaping @Sendable (URL) -> Data?) {
        self.responder = responder
    }

    var requests: [URL] { lock.withLock { _requests } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(request.url)
        lock.withLock { _requests.append(url) }
        guard let data = responder(url) else { throw HTTPError.status(404, url) }
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

struct StubSecrets: SecretStore {
    var values: [SecretKey: String]
    func value(for key: SecretKey) -> String? { values[key] }
}

extension Track {
    static func sample(_ title: String = "Closer", artist: String = "Nine Inch Nails", album: String = "The Downward Spiral") -> Track {
        Track(title: title, artist: artist, album: album, sourceID: "test")
    }
}
