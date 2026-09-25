import Testing
@testable import AudioPaperKit

@Suite struct NormalizerTests {
    @Test(arguments: [
        ("In Rainbows (Deluxe Edition)", "In Rainbows"),
        ("Closer - Single", "Closer"),
        ("The Downward Spiral (2004 Remaster)", "The Downward Spiral"),
        ("Hurt [Explicit]", "Hurt"),
        ("Wish - 2011 Remastered", "Wish"),
        ("Head Like a Hole (feat. Someone)", "Head Like a Hole"),
        ("Ghosts I-IV", "Ghosts I-IV"),
        ("Love (Is All)", "Love (Is All)"),
    ])
    func searchTermStripsEditionNoise(raw: String, expected: String) {
        #expect(Normalizer.searchTerm(raw) == expected)
    }

    @Test func keyFoldsCaseDiacriticsPunctuationAndLeadingThe() {
        #expect(Normalizer.key("The Beatles") == "beatles")
        #expect(Normalizer.key("Beyoncé") == "beyonce")
        #expect(Normalizer.key("Simon & Garfunkel") == "simon and garfunkel")
        #expect(Normalizer.key("AC/DC") == "ac dc")
        #expect(Normalizer.key("The The") == "the")
    }

    @Test func htmlEntitiesAreDecoded() {
        #expect("Nine Inch Nails &quot;Closer&quot; &amp; more &#39;art&#39;".decodingHTMLEntities() == "Nine Inch Nails \"Closer\" & more 'art'")
    }
}

@Suite struct MatchScorerTests {
    @Test func identicalAfterNormalizationScoresOne() {
        #expect(MatchScorer.similarity("In Rainbows (Deluxe Edition)", "In Rainbows") == 1)
    }

    @Test func unrelatedScoresLow() {
        #expect(MatchScorer.similarity("In Rainbows", "Kid A") < 0.2)
    }

    @Test func wrongArtistIsRejectedEvenWithSameAlbumTitle() {
        let score = MatchScorer.albumScore(
            artist: "Radiohead", album: "In Rainbows",
            candidateArtist: "Vitamin String Quartet", candidateAlbum: "In Rainbows"
        )
        #expect(score == 0)
    }

    @Test func tributeAlbumScoresBelowOriginal() {
        let original = MatchScorer.albumScore(artist: "Radiohead", album: "In Rainbows", candidateArtist: "Radiohead", candidateAlbum: "In Rainbows")
        let tribute = MatchScorer.albumScore(artist: "Radiohead", album: "In Rainbows", candidateArtist: "Radiohead", candidateAlbum: "In Rainbows Disk 2 Tribute")
        #expect(original > tribute)
    }
}

@Suite struct CreditedArtistTests {
    @Test(arguments: [
        ("LE SSERAFIM & j-hope", ["LE SSERAFIM", "j-hope"]),
        ("Calvin Harris feat. Dua Lipa", ["Calvin Harris", "Dua Lipa"]),
        ("Drake ft. Rihanna", ["Drake", "Rihanna"]),
        ("A, B & C", ["A", "B", "C"]),
        ("Lil Nas X x Jack Harlow", ["Lil Nas X", "Jack Harlow"]),
        ("Beyoncé with JAY-Z", ["Beyoncé", "JAY-Z"]),
    ])
    func collaborationsSplitIntoArtists(credit: String, expected: [String]) {
        #expect(Track.sample(artist: credit).creditedArtists == expected)
    }

    @Test(arguments: ["BABYMONSTER", "Nine Inch Nails", "Lil Nas X", "Xiu Xiu"])
    func singleArtistsDoNotSplit(name: String) {
        #expect(Track.sample(artist: name).creditedArtists.isEmpty)
    }

    @Test(arguments: [
        ("Move Bitch (feat. Ludacris, Mystikal & I-20)", ["Ludacris", "Mystikal", "I-20"]),
        ("Stay [ft. Justin Bieber]", ["Justin Bieber"]),
        ("(Rock) Superstar [feat. Chino Moreno & Everlast]", ["Chino Moreno", "Everlast"]),
        ("Numb/Encore (with JAY-Z)", ["JAY-Z"]),
        ("Closer", []),
        ("With or Without You", []),
    ])
    func featuredArtistsComeFromTheTitle(title: String, expected: [String]) {
        #expect(Track.sample(title, artist: "Someone").featuredArtists == expected)
    }

    @Test func fallbackTriesCreditedThenFeaturedArtistsOnce() {
        let track = Track.sample("SPAGHETTI (feat. j-hope)", artist: "LE SSERAFIM & j-hope")
        #expect(track.fallbackArtists == ["LE SSERAFIM", "j-hope"], "j-hope appears in both, tried once")
    }

    @Test func creditingKeepsTheSongButNotTheAlbumArtist() {
        let track = Track(title: "SPAGHETTI", artist: "LE SSERAFIM & j-hope", album: "SPAGHETTI", albumArtist: "LE SSERAFIM & j-hope", sourceID: "t")
        let solo = track.crediting("j-hope")
        #expect(solo.artist == "j-hope" && solo.title == "SPAGHETTI" && solo.albumArtist == nil)
    }
}
