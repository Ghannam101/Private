// ============================================================
// BLANK TV — RailEngineTests.swift
// The curation engine is the one place in the app that decides what a user sees
// FIRST, and it is pure — same input, same ordered output, no I/O. That makes it
// both the highest-value and the cheapest thing in this codebase to pin down.
//
// `classify` and `cleanTitle` are private, so every assertion here goes through the
// public `build`. That is deliberate and not a limitation: it means these tests
// describe the CONTRACT (which rails appear, named what, in what order) rather than
// the current implementation, so the classifier can be rewritten underneath them.
// ============================================================

import Foundation
import Testing
@testable import BlankTV

@Suite("RailEngine.build")
struct RailEngineBuildTests {

    // MARK: The size gate

    @Test("a category under minItems earns no rail")
    func belowMinimumIsDropped() {
        let cat = Fx.category("small", "Drama")
        let rails = RailEngine.build(movies: Fx.movies(RailEngine.minItems - 1, cat: "small"),
                                     movieCats: [cat], series: [], seriesCats: [])
        #expect(rails.isEmpty)
    }

    @Test("a category at exactly minItems earns a rail")
    func atMinimumIsKept() {
        let cat = Fx.category("ok", "Drama")
        let rails = RailEngine.build(movies: Fx.movies(RailEngine.minItems, cat: "ok"),
                                     movieCats: [cat], series: [], seriesCats: [])
        #expect(rails.count == 1)
        #expect(rails[0].id == "m_ok")
    }

    @Test("a category the provider declares but never fills earns no rail")
    func emptyCategoryIsDropped() {
        let rails = RailEngine.build(movies: [], movieCats: [Fx.category("ghost", "Ghost")],
                                     series: [], seriesCats: [])
        #expect(rails.isEmpty)
    }

    // MARK: Naming — the noise a provider ships must not reach the user

    @Test("quality and language noise is stripped from the rail title")
    func titleIsCleaned() {
        let cat = Fx.category("nf", "AR | NETFLIX MOVIES 4K")
        let rails = RailEngine.build(movies: Fx.movies(6, cat: "nf"),
                                     movieCats: [cat], series: [], seriesCats: [])
        #expect(rails.count == 1)
        #expect(rails[0].title == "NETFLIX MOVIES")
        #expect(rails[0].networkTag == "NETFLIX")
    }

    @Test("a plain genre carries no network chip")
    func genreHasNoTag() {
        let cat = Fx.category("act", "اكشن")
        let rails = RailEngine.build(movies: Fx.movies(6, cat: "act"),
                                     movieCats: [cat], series: [], seriesCats: [])
        #expect(rails.count == 1)
        #expect(rails[0].networkTag == nil)
    }

    @Test("a name that is entirely noise falls back to the raw name")
    func allNoiseFallsBack() {
        let cat = Fx.category("junk", "4K | HD")
        let rails = RailEngine.build(movies: Fx.movies(6, cat: "junk"),
                                     movieCats: [cat], series: [], seriesCats: [])
        #expect(rails.count == 1)
        #expect(rails[0].title.isEmpty == false)
    }

    @Test("Arabic network aliases resolve to the same canonical chip")
    func arabicNetworkAlias() {
        let cat = Fx.category("nfar", "نتفلكس")
        let rails = RailEngine.build(movies: Fx.movies(6, cat: "nfar"),
                                     movieCats: [cat], series: [], seriesCats: [])
        #expect(rails[0].networkTag == "NETFLIX")
    }

    // MARK: Ordering — the whole product decision

    @Test("networks outrank genres, and genres outrank unrecognised folders")
    func priorityOrder() {
        let cats = [Fx.category("z", "Something Random"),
                    Fx.category("g", "Comedy"),
                    Fx.category("n", "NETFLIX")]
        let movies = Fx.movies(6, cat: "z") + Fx.movies(6, cat: "g") + Fx.movies(6, cat: "n")
        let rails = RailEngine.build(movies: movies, movieCats: cats, series: [], seriesCats: [])
        #expect(rails.map(\.id) == ["m_n", "m_g", "m_z"])
    }

    @Test("network order follows the declared priority list, not input order")
    func networkPriorityIsFixed() {
        // SHAHID is declared after NETFLIX, so it must rank after it even when the
        // provider lists it first.
        let cats = [Fx.category("s", "SHAHID"), Fx.category("n", "NETFLIX")]
        let rails = RailEngine.build(movies: Fx.movies(6, cat: "s") + Fx.movies(6, cat: "n"),
                                     movieCats: cats, series: [], seriesCats: [])
        #expect(rails.map(\.networkTag) == ["NETFLIX", "SHAHID"])
    }

    @Test("within one priority, the bigger folder comes first")
    func sizeBreaksTies() {
        let cats = [Fx.category("a", "Folder A"), Fx.category("b", "Folder B")]
        let rails = RailEngine.build(movies: Fx.movies(5, cat: "a") + Fx.movies(9, cat: "b"),
                                     movieCats: cats, series: [], seriesCats: [])
        #expect(rails.map(\.id) == ["m_b", "m_a"])
    }

    @Test("the feed is capped at maxRails")
    func railCountIsCapped() {
        let n = RailEngine.maxRails + 5
        let cats = (0..<n).map { Fx.category("c\($0)", "Folder \($0)") }
        let movies = cats.flatMap { Fx.movies(6, cat: $0.id) }
        let rails = RailEngine.build(movies: movies, movieCats: cats, series: [], seriesCats: [])
        #expect(rails.count == RailEngine.maxRails)
    }

    // MARK: Contents of a rail

    @Test("a rail carries at most perRail items")
    func itemsAreCapped() {
        let cat = Fx.category("big", "Big Folder")
        let rails = RailEngine.build(movies: Fx.movies(RailEngine.perRail + 30, cat: "big"),
                                     movieCats: [cat], series: [], seriesCats: [])
        #expect(rails[0].count == RailEngine.perRail)
    }

    @Test("items inside a rail are ranked by rating, best first")
    func itemsAreRanked() throws {
        let cat = Fx.category("r", "Rated")
        let movies = [Fx.movie("low", cat: "r", rating: "3.0"),
                      Fx.movie("high", cat: "r", rating: "9.5"),
                      Fx.movie("mid", cat: "r", rating: "6.1"),
                      Fx.movie("none", cat: "r", rating: nil)]
        let rails = RailEngine.build(movies: movies, movieCats: [cat], series: [], seriesCats: [])
        guard case .movie(let ranked) = rails[0].kind else {
            Issue.record("expected a movie rail"); return
        }
        #expect(ranked.map(\.id) == ["high", "mid", "low", "none"])
    }

    // MARK: The crash this file exists to prevent

    @Test("a non-numeric rating cannot trap the sort")
    func nanRatingIsSurvivable() throws {
        // `Double("nan")` IS `.nan`, and NaN in a `>` comparator violates
        // strict-weak-ordering, which makes `sorted` TRAP at runtime — not return a
        // wrong answer, trap. A provider that publishes rating="nan" or rating="inf"
        // would take the home screen down. This test is the guard on that.
        let cat = Fx.category("bad", "Bad Ratings")
        let movies = [Fx.movie("a", cat: "bad", rating: "nan"),
                      Fx.movie("b", cat: "bad", rating: "inf"),
                      Fx.movie("c", cat: "bad", rating: "-inf"),
                      Fx.movie("d", cat: "bad", rating: "not a number"),
                      Fx.movie("e", cat: "bad", rating: "7.0")]
        let rails = RailEngine.build(movies: movies, movieCats: [cat], series: [], seriesCats: [])
        #expect(rails.count == 1)
        #expect(rails[0].count == 5)
        guard case .movie(let ranked) = rails[0].kind else {
            Issue.record("expected a movie rail"); return
        }
        // The only finite rating must win; the rest are floored to 0 by `ratingDouble`.
        #expect(ranked.first?.id == "e")
    }

    @Test("a non-numeric series rating cannot trap the sort either")
    func nanSeriesRatingIsSurvivable() {
        let cat = Fx.category("bads", "Bad Series")
        let list = [Fx.series("a", cat: "bads", rating: "nan"),
                    Fx.series("b", cat: "bads", rating: "8.2"),
                    Fx.series("c", cat: "bads", rating: nil),
                    Fx.series("d", cat: "bads", rating: "inf")]
        let rails = RailEngine.build(movies: [], movieCats: [], series: list, seriesCats: [cat])
        #expect(rails.count == 1)
        #expect(rails[0].count == 4)
    }

    // MARK: Determinism

    @Test("the same catalogue always produces the same feed")
    func isDeterministic() {
        let cats = [Fx.category("n", "NETFLIX"), Fx.category("g", "Comedy"),
                    Fx.category("z", "Misc")]
        let movies = cats.flatMap { Fx.movies(7, cat: $0.id, rating: "5.0") }
        let first = RailEngine.build(movies: movies, movieCats: cats, series: [], seriesCats: [])
        let again = RailEngine.build(movies: movies, movieCats: cats, series: [], seriesCats: [])
        #expect(first.map(\.id) == again.map(\.id))
        #expect(first.map(\.title) == again.map(\.title))
    }

    @Test("movie and series rails from the same category stay distinct")
    func movieAndSeriesRailsDoNotCollide() {
        let cat = Fx.category("shared", "NETFLIX")
        let rails = RailEngine.build(movies: Fx.movies(6, cat: "shared"),
                                     movieCats: [cat],
                                     series: Fx.seriesList(6, cat: "shared"),
                                     seriesCats: [cat])
        #expect(rails.count == 2)
        #expect(Set(rails.map(\.id)) == ["m_shared", "s_shared"])
    }

    @Test("an empty catalogue produces an empty feed")
    func emptyInput() {
        #expect(RailEngine.build(movies: [], movieCats: [], series: [], seriesCats: []).isEmpty)
    }
}

// ============================================================
// MARK: - Regional classifier
// ============================================================

@Suite("RegionClassifier")
struct RegionClassifierTests {

    @Test("Arabic broadcasters classify as Arabic",
          arguments: ["MBC مصر", "beIN Sports 1", "قنوات رياضية", "Rotana Cinema",
                      "OSN Movies", "AbuDhabi TV", "Saudi TV"])
    func arabic(_ name: String) {
        #expect(RegionClassifier.region(for: name) == .arabic)
    }

    @Test("American broadcasters classify as American",
          arguments: ["HBO Max", "ESPN 1", "FOX Sports", "Disney Channel", "USA Network"])
    func american(_ name: String) {
        #expect(RegionClassifier.region(for: name) == .american)
    }

    @Test("European broadcasters classify as European",
          arguments: ["BBC One UK", "Canal+ France", "Sky Sports", "RAI Italia"])
    func european(_ name: String) {
        #expect(RegionClassifier.region(for: name) == .european)
    }

    @Test("an unrecognised name classifies as nothing rather than guessing")
    func unknownIsNil() {
        #expect(RegionClassifier.region(for: "Channel 12345") == nil)
        #expect(RegionClassifier.region(for: "") == nil)
    }

    // MARK: The three misfilings that substring matching caused

    @Test("a key buried inside a word no longer decides the region")
    func noSubstringMisfiling() {
        // "Sukkar" contains "uk" and "Duke" contains "uk"; neither is European.
        #expect(RegionClassifier.region(for: "Sukkar TV") == nil)
        #expect(RegionClassifier.region(for: "Duke TV") == nil)
    }

    @Test("Romania lands on the European stem, not on Oman")
    func romaniaIsEuropean() {
        // "R-oman-ia" used to match the Arabic key "oman" before the European key
        // "roman" was ever reached. Word-initial matching puts it where it belongs.
        #expect(RegionClassifier.region(for: "Romania TV") == .european)
        #expect(RegionClassifier.region(for: "Oman TV") == .arabic)
    }

    @Test("the spaced spelling of Abu Dhabi is recognised")
    func abuDhabiSpaced() {
        // The list only carried "abudhabi". Every broadcaster writes it with a space.
        #expect(RegionClassifier.region(for: "Abu Dhabi TV") == .arabic)
        #expect(RegionClassifier.region(for: "AbuDhabi Sports") == .arabic)
        #expect(RegionClassifier.region(for: "ابو ظبي") == .arabic)
    }

    @Test("Arabic keys survive hamza and harakat variation")
    func arabicKeysAreFolded() {
        // The name is folded before matching, so a provider's spelling choice cannot
        // hide a channel from its own region.
        #expect(RegionClassifier.region(for: "الكوَيت اليوم") == .arabic)
        #expect(RegionClassifier.region(for: "قنَوات عربية") == .arabic)
    }

    @Test("Arabic wins over the other lists when a name matches both")
    func arabicTakesPrecedence() {
        // "OSN" is Arabic; the name also carries "movies" which appears nowhere in
        // the other lists — but the precedence rule is what is being pinned here.
        #expect(RegionClassifier.region(for: "OSN USA Movies") == .arabic)
    }

    @Test("presetOrder returns only the region's categories, in their original order")
    func presetOrderIsFiltered() {
        let cats = [Fx.category("1", "HBO Max"),
                    Fx.category("2", "MBC 1"),
                    Fx.category("3", "BBC Two"),
                    Fx.category("4", "beIN 2")]
        #expect(RegionClassifier.presetOrder(cats, primary: .arabic) == ["2", "4"])
        #expect(RegionClassifier.presetOrder(cats, primary: .american) == ["1"])
        #expect(RegionClassifier.presetOrder(cats, primary: .european) == ["3"])
    }

    @Test("presetOrder on a catalogue with no match returns nothing")
    func presetOrderEmpty() {
        let cats = [Fx.category("1", "Channel 9999")]
        #expect(RegionClassifier.presetOrder(cats, primary: .arabic).isEmpty)
    }
}
