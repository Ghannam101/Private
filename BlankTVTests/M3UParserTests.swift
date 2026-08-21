// ============================================================
// BLANK TV — M3UParserTests.swift
// The parser is where the app meets the messiest input it will ever see: a text
// file written by someone else's panel, with no schema and no guarantees. Every
// case below is a shape a real provider ships.
//
// The `stableID` determinism test is not academic. Ids here are djb2 hashes of the
// URL, and a SwiftUI paging `ScrollView` with `.scrollPosition(id:)` TRAPS on
// duplicate ids — that combination already crashed one shipped build. A test that
// pins id stability is the cheapest possible guard on it.
// ============================================================

import Foundation
import Testing
@testable import BlankTV

@Suite("M3UParser.entries")
struct M3UEntriesTests {

    @Test("a well-formed entry parses every attribute")
    func fullEntry() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="AbuDhabiTV.ae@SD" tvg-logo="http://l/a.png" group-title="عرب",Abu Dhabi TV
        http://host/live/u/p/1.ts
        """
        let e = try #require(M3UParser.entries(from: text).first)
        #expect(e.name == "Abu Dhabi TV")
        #expect(e.logo == "http://l/a.png")
        #expect(e.group == "عرب")
        #expect(e.url == "http://host/live/u/p/1.ts")
    }

    @Test("a tvg-id feed suffix is stripped and the id is lower-cased")
    func tvgIDIsNormalised() throws {
        let text = """
        #EXTINF:-1 tvg-id="AbuDhabiTV.ae@SD" group-title="g",Name
        http://host/1.ts
        """
        let e = try #require(M3UParser.entries(from: text).first)
        #expect(e.tvgID == "abudhabitv.ae")
    }

    @Test("a missing tvg-id is nil, not an empty string")
    func missingTvgID() throws {
        let text = """
        #EXTINF:-1 group-title="g",Name
        http://host/1.ts
        """
        let e = try #require(M3UParser.entries(from: text).first)
        #expect(e.tvgID == nil)
    }

    @Test("an empty tvg-id is nil, not an empty string")
    func emptyTvgID() throws {
        let text = """
        #EXTINF:-1 tvg-id="" group-title="g",Name
        http://host/1.ts
        """
        let e = try #require(M3UParser.entries(from: text).first)
        #expect(e.tvgID == nil)
    }

    @Test("a missing group falls back to the generic folder")
    func missingGroup() throws {
        let text = """
        #EXTINF:-1,Name
        http://host/1.ts
        """
        let e = try #require(M3UParser.entries(from: text).first)
        #expect(e.group == "عام")
    }

    @Test("an entry with no name still parses rather than being dropped")
    func missingName() throws {
        let text = """
        #EXTINF:-1
        http://host/1.ts
        """
        let e = try #require(M3UParser.entries(from: text).first)
        #expect(e.name == "بدون اسم")
    }

    @Test("an #EXTINF with no URL after it yields nothing")
    func danglingInfo() {
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="g",Orphan
        """
        #expect(M3UParser.entries(from: text).isEmpty)
    }

    @Test("a bare URL with no #EXTINF before it is ignored")
    func urlWithoutInfo() {
        let text = """
        #EXTM3U
        http://host/1.ts
        """
        #expect(M3UParser.entries(from: text).isEmpty)
    }

    @Test("comment lines other than #EXTINF are skipped")
    func commentsSkipped() {
        let text = """
        #EXTM3U
        #EXTVLCOPT:http-user-agent=x
        #EXTINF:-1 group-title="g",Name
        #EXTVLCOPT:network-caching=1000
        http://host/1.ts
        """
        #expect(M3UParser.entries(from: text).count == 1)
    }

    @Test("whitespace around a line does not break parsing")
    func whitespaceTolerated() throws {
        let text = "  #EXTINF:-1 group-title=\"g\",Name  \n   http://host/1.ts   "
        let e = try #require(M3UParser.entries(from: text).first)
        #expect(e.url == "http://host/1.ts")
    }

    @Test("empty input yields no entries")
    func emptyInput() {
        #expect(M3UParser.entries(from: "").isEmpty)
        #expect(M3UParser.entries(from: "#EXTM3U").isEmpty)
    }
}

// ============================================================
// MARK: - Classification
// ============================================================

@Suite("M3UParser.build")
struct M3UBuildTests {

    @Test("an SxxEyy title becomes a series with its season and episode")
    func seriesDetected() throws {
        let text = """
        #EXTINF:-1 group-title="Series",Breaking Bad S01E02
        http://host/series/u/p/9.mkv
        """
        let c = M3UParser.build(from: text)
        #expect(c.channels.isEmpty)
        #expect(c.movies.isEmpty)
        let s = try #require(c.series.first)
        #expect(s.name == "Breaking Bad")
        #expect(s.categoryID == "Series")
        let season = try #require(s.seasons.first)
        #expect(season.seasonNumber == 1)
        #expect(season.episodes.first?.episodeNumber == 2)
        #expect(c.seriesCategories.map(\.id) == ["Series"])
    }

    @Test("episodes of one show collapse into a single series")
    func episodesGrouped() throws {
        let text = """
        #EXTINF:-1 group-title="Series",Show S01E01
        http://host/series/1.mkv
        #EXTINF:-1 group-title="Series",Show S01E02
        http://host/series/2.mkv
        #EXTINF:-1 group-title="Series",Show S02E01
        http://host/series/3.mkv
        """
        let c = M3UParser.build(from: text)
        #expect(c.series.count == 1)
        let s = try #require(c.series.first)
        #expect(s.seasons.count == 2)
        #expect(s.seasons.map(\.seasonNumber) == [1, 2])
        #expect(s.seasons[0].episodes.count == 2)
        #expect(s.seasons[0].episodes.map(\.episodeNumber) == [1, 2])
    }

    @Test("a /movie/ URL stays a movie even when the title looks like an episode")
    func movieURLBeatsEpisodePattern() {
        // Raw-M3U movie filenames routinely carry an SxxEyy-looking token. The
        // provider's own /movie/ path is the stronger signal and must win.
        let text = """
        #EXTINF:-1 group-title="VOD",Some Film S01E02
        http://host/movie/u/p/5.mkv
        """
        let c = M3UParser.build(from: text)
        #expect(c.series.isEmpty)
        #expect(c.movies.count == 1)
    }

    @Test("an explicit movies group stays movies even with an episode-looking title")
    func explicitMovieGroupBeatsEpisodePattern() {
        let text = """
        #EXTINF:-1 group-title="أفلام عربية",Film S01E02
        http://host/vod/5.mkv
        """
        let c = M3UParser.build(from: text)
        #expect(c.series.isEmpty)
        #expect(c.movies.count == 1)
        #expect(c.movieCategories.map(\.id) == ["أفلام عربية"])
    }

    @Test("an episode in a group named for series is never rescued into movies")
    func seriesGroupIsNotAMovieGroup() {
        let text = """
        #EXTINF:-1 group-title="Movies Series",Show S01E01
        http://host/x/1.mkv
        """
        let c = M3UParser.build(from: text)
        #expect(c.movies.isEmpty)
        #expect(c.series.count == 1)
    }

    @Test("an m3u8 stream with no episode pattern is a live channel")
    func liveDetected() throws {
        let text = """
        #EXTINF:-1 tvg-id="bbc.uk" group-title="News",BBC News
        http://host/live/u/p/3.m3u8
        """
        let c = M3UParser.build(from: text)
        #expect(c.movies.isEmpty)
        #expect(c.series.isEmpty)
        let ch = try #require(c.channels.first)
        #expect(ch.name == "BBC News")
        #expect(ch.groupTitle == "News")
        #expect(ch.epgChannelID == "bbc.uk")
        #expect(ch.directURL == "http://host/live/u/p/3.m3u8")
        #expect(c.liveCategories.map(\.id) == ["News"])
    }

    @Test("a URL with no file extension is a live channel")
    func extensionlessIsLive() {
        let text = """
        #EXTINF:-1 group-title="News",Channel
        http://host/live/u/p/7
        """
        #expect(M3UParser.build(from: text).channels.count == 1)
    }

    @Test("a .ts stream is a live channel, not a movie")
    func tsIsLive() {
        let text = """
        #EXTINF:-1 group-title="News",Channel
        http://host/live/u/p/7.ts
        """
        #expect(M3UParser.build(from: text).channels.count == 1)
    }

    @Test("a VOD group makes an entry a movie regardless of container")
    func vodGroupIsMovie() throws {
        let text = """
        #EXTINF:-1 group-title="VOD Arabic",Film Name
        http://host/x/9.mp4
        """
        let c = M3UParser.build(from: text)
        let m = try #require(c.movies.first)
        #expect(m.name == "Film Name")
        #expect(m.containerExtension == "mp4")
        #expect(m.categoryID == "VOD Arabic")
        #expect(m.directURL == "http://host/x/9.mp4")
    }

    @Test("categories are first-seen order and carry no duplicates")
    func categoriesDeduped() {
        let text = """
        #EXTINF:-1 group-title="A",One
        http://host/1.m3u8
        #EXTINF:-1 group-title="B",Two
        http://host/2.m3u8
        #EXTINF:-1 group-title="A",Three
        http://host/3.m3u8
        """
        #expect(M3UParser.build(from: text).liveCategories.map(\.id) == ["A", "B"])
    }

    // MARK: The crash guard

    @Test("ids are stable across runs, so nothing can produce a duplicate by accident")
    func idsAreStable() {
        let text = """
        #EXTINF:-1 group-title="News",Channel One
        http://host/live/1.m3u8
        #EXTINF:-1 group-title="VOD",Film
        http://host/movie/2.mkv
        #EXTINF:-1 group-title="Series",Show S01E01
        http://host/series/3.mkv
        """
        let first = M3UParser.build(from: text)
        let again = M3UParser.build(from: text)
        #expect(first.channels.map(\.id) == again.channels.map(\.id))
        #expect(first.movies.map(\.id) == again.movies.map(\.id))
        #expect(first.series.map(\.id) == again.series.map(\.id))
        #expect(first.channels[0].id.hasPrefix("m3u_live_"))
        #expect(first.movies[0].id.hasPrefix("m3u_movie_"))
        #expect(first.series[0].id.hasPrefix("m3u_series_"))
    }

    @Test("two entries with different URLs never share a channel id")
    func distinctURLsGiveDistinctIDs() {
        let text = """
        #EXTINF:-1 group-title="News",Same Name
        http://host/live/1.m3u8
        #EXTINF:-1 group-title="News",Same Name
        http://host/live/2.m3u8
        """
        let c = M3UParser.build(from: text)
        #expect(c.channels.count == 2)
        #expect(Set(c.channels.map(\.id)).count == 2)
    }

    @Test("an empty playlist produces an empty catalogue rather than failing")
    func emptyPlaylist() {
        let c = M3UParser.build(from: "#EXTM3U")
        #expect(c.channels.isEmpty && c.movies.isEmpty && c.series.isEmpty)
        #expect(c.isPartial == false)
    }
}
