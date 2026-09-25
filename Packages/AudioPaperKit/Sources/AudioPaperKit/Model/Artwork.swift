import Foundation

/// Who made a piece of artwork and where it lives, kept so the UI can link back to the creator.
public struct Attribution: Hashable, Sendable, Codable {
    public var title: String?
    public var creatorName: String?
    public var creatorProfileURL: URL?
    public var creatorAvatarURL: URL?
    /// Page the artwork was found on (the deviation, the web page, the album listing).
    public var pageURL: URL?
    /// Human-readable origin, e.g. "DeviantArt", "etsy.com", "Apple Music".
    public var sourceName: String
    /// License, when the source states one (e.g. "CC BY-SA 4.0"); shown in the credit.
    public var license: String?

    public init(
        title: String? = nil,
        creatorName: String? = nil,
        creatorProfileURL: URL? = nil,
        creatorAvatarURL: URL? = nil,
        pageURL: URL? = nil,
        sourceName: String,
        license: String? = nil
    ) {
        self.title = title
        self.creatorName = creatorName
        self.creatorProfileURL = creatorProfileURL
        self.creatorAvatarURL = creatorAvatarURL
        self.pageURL = pageURL
        self.sourceName = sourceName
        self.license = license
    }
}

public enum ArtworkKind: String, Hashable, Sendable, Codable {
    case albumCover
    case fanArt
}

extension ArtworkCandidate {
    /// What the image is, for credits: "Album cover", "Photo" (Wikimedia Commons) or "Fan art".
    public var kindLabel: String {
        switch kind {
        case .albumCover: "Album cover"
        case .fanArt: providerID == "wikimedia" ? "Photo" : "Fan art"
        }
    }

    /// The credit's second line: kind, license and source, e.g. "Photo · CC BY-SA 4.0 · Wikimedia Commons".
    public var creditLine: String {
        [kindLabel, attribution.license, attribution.sourceName].compactMap { $0 }.joined(separator: " · ")
    }

    /// Who made it — "Photo by Yan Mayen", "Art by example-artist" — or nil when unknown (and for covers).
    public var creatorCredit: String? {
        guard kind == .fanArt, let creator = attribution.creatorName else { return nil }
        return "\(kindLabel == "Photo" ? "Photo" : "Art") by \(creator)"
    }

    /// One line for tight spaces (widgets): the maker plus license or source, else `creditLine`.
    public var shortCredit: String {
        creatorCredit.map { "\($0) · \(attribution.license ?? attribution.sourceName)" } ?? creditLine
    }
}

/// A remote image that may become a wallpaper.
public struct ArtworkCandidate: Hashable, Sendable, Codable, Identifiable {
    public var id: String { imageURL.absoluteString }
    public var imageURL: URL
    public var width: Int?
    public var height: Int?
    public var kind: ArtworkKind
    public var providerID: String
    public var attribution: Attribution
    /// Provider-reported confidence that this matches the request, 0...1.
    public var matchScore: Double

    public init(
        imageURL: URL,
        width: Int? = nil,
        height: Int? = nil,
        kind: ArtworkKind,
        providerID: String,
        attribution: Attribution,
        matchScore: Double = 1
    ) {
        self.imageURL = imageURL
        self.width = width
        self.height = height
        self.kind = kind
        self.providerID = providerID
        self.attribution = attribution
        self.matchScore = matchScore
    }

}

/// An artwork candidate that has been downloaded to disk and accepted.
public struct Artwork: Hashable, Sendable, Codable, Identifiable {
    public var id: String { candidate.id }
    public var candidate: ArtworkCandidate
    public var fileURL: URL
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Fan-art pipeline score: Vision aesthetics plus a boost for images classified as artwork. Higher is better.
    public var qualityScore: Double?

    public init(candidate: ArtworkCandidate, fileURL: URL, pixelWidth: Int, pixelHeight: Int, qualityScore: Double? = nil) {
        self.candidate = candidate
        self.fileURL = fileURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.qualityScore = qualityScore
    }
}
