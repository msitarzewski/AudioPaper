import Foundation

/// Cleans up track/album names so searches and comparisons ignore edition noise.
public enum Normalizer {
    /// Parenthetical or bracketed qualifiers that describe an edition rather than the work.
    private static let editionWords = [
        "deluxe", "remaster", "remastered", "expanded", "edition", "anniversary",
        "bonus", "version", "mono", "stereo", "explicit", "clean", "single", "ep",
        "live", "reissue", "special", "super", "collector", "radio edit", "feat", "ft",
    ]

    /// Human-readable cleaned name used as a search term, e.g. "In Rainbows (Deluxe Edition)" → "In Rainbows".
    public static func searchTerm(_ raw: String) -> String {
        var s = raw.decodingHTMLEntities()
        // Drop (…) and […] groups that only describe the edition or a featured artist.
        s = s.replacing(/\s*[\(\[]([^\)\]]*)[\)\]]/) { match in
            let inner = match.output.1.lowercased()
            return editionWords.contains(where: { inner.contains($0) }) ? "" : String(match.output.0)
        }
        // Drop trailing " - Single", " - EP", " - 2011 Remaster".
        s = s.replacing(/\s+-\s+[^-]*$/) { match in
            let tail = match.output.lowercased()
            return editionWords.contains(where: { tail.contains($0) }) ? "" : String(match.output)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Comparison key: cleaned, case/diacritic-folded, punctuation-free, "&" → "and", leading "the" dropped.
    public static func key(_ raw: String) -> String {
        var s = searchTerm(raw)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
        s = String(s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
        var words = s.split(separator: " ").map(String.init)
        if words.first == "the", words.count > 1 { words.removeFirst() }
        return words.joined(separator: " ")
    }
}

extension String {
    /// Decodes the handful of HTML entities search APIs leave in titles.
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }
        var s = self
        let named = ["&quot;": "\"", "&apos;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&amp;": "&"]
        for (entity, value) in named { s = s.replacingOccurrences(of: entity, with: value) }
        s = s.replacing(/&#(\d+);/) { match in
            guard let code = UInt32(match.output.1), let scalar = Unicode.Scalar(code) else { return String(match.output.0) }
            return String(Character(scalar))
        }
        return s
    }
}
