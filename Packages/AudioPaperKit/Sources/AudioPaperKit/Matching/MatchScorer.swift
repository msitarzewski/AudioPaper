import Foundation

/// Scores how well a search result's artist/album matches the track being played.
public enum MatchScorer {
    /// Similarity of two strings after normalization, 0...1 (token-set Dice coefficient, exact match = 1).
    public static func similarity(_ a: String, _ b: String) -> Double {
        let ka = Normalizer.key(a), kb = Normalizer.key(b)
        if ka.isEmpty || kb.isEmpty { return 0 }
        if ka == kb { return 1 }
        let ta = Set(ka.split(separator: " ")), tb = Set(kb.split(separator: " "))
        let shared = Double(ta.intersection(tb).count)
        let dice = 2 * shared / Double(ta.count + tb.count)
        // A short name wholly contained in a longer one ("Closer" vs "Closer to God") is a strong partial.
        let contained = ka.contains(kb) || kb.contains(ka) ? 0.8 : 0
        return max(dice, contained)
    }

    /// Combined album match; the artist must match reasonably or the result is rejected outright.
    public static func albumScore(artist: String, album: String, candidateArtist: String, candidateAlbum: String) -> Double {
        let artistScore = similarity(artist, candidateArtist)
        guard artistScore >= 0.5 else { return 0 }
        return 0.4 * artistScore + 0.6 * similarity(album, candidateAlbum)
    }
}
