// ============================================================
// BLANK TV — CatalogDBTests.swift
// The SQLite store, exercised against real SQLite — no mocks, no fakes.
//
// TWO SUITES, FOR TWO DIFFERENT REASONS.
//
//   · `CatalogDBStore` drives the SHARED store through its real public API, because
//     that is the code the app actually runs — including the pool configuration and
//     the WAL. Every test uses a unique scope, and everything in this store is
//     scope-keyed, so the tests cannot see each other's rows. It is `.serialized`
//     anyway: one test asks about the whole file rather than one scope.
//
//   · `CatalogDBMigrations` opens throwaway stores on temp paths, because a
//     migration that rewrites what an EARLIER build wrote can only be tested by
//     creating that earlier state first.
// ============================================================

import Foundation
import GRDB
import Testing
@testable import BlankTV

// MARK: - Helpers

private func tempStorePath(_ label: String) -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("catalogdb-tests-\(label)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("catalog.sqlite").path
}

private func content(channels: [Channel] = [], movies: [Movie] = [], series: [Series] = [],
                     liveCats: [BlankTV.Category] = [], movieCats: [BlankTV.Category] = [],
                     seriesCats: [BlankTV.Category] = []) -> M3UContent {
    var c = M3UContent()
    c.channels = channels; c.movies = movies; c.series = series
    c.liveCategories = liveCats; c.movieCategories = movieCats; c.seriesCategories = seriesCats
    return c
}

// MARK: - The store, through its real API

@Suite("CatalogDB — store", .serialized)
struct CatalogDBStoreTests {

    private func scope(_ name: String) -> String { "test://\(name)/\(UUID().uuidString)" }

    @Test("the shared store opens, and it opens as a WAL pool")
    func storeOpens() throws {
        let pool = try #require(CatalogDB.dbPool, "the shared store failed to open")
        let mode = try pool.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        // DatabasePool turns WAL on itself. If this ever reads "delete", the pool
        // silently degraded to serialized behaviour and the reason for the switch
        // is gone without anything failing.
        #expect(mode?.lowercased() == "wal")
    }

    @Test("synchronous is NORMAL, which is what makes a large import affordable")
    func synchronousIsNormal() throws {
        let pool = try #require(CatalogDB.dbPool)
        let sync = try pool.read { db in try Int.fetchOne(db, sql: "PRAGMA synchronous") }
        #expect(sync == 1)   // 0 = OFF, 1 = NORMAL, 2 = FULL
    }

    @Test("a saved catalogue reads back with its rows intact")
    func saveAndRead() {
        let s = scope("roundtrip")
        CatalogDB.save(content(
            channels: [Fx.channel("c1", group: "News", name: "BBC News")],
            movies:   [Fx.movie("m1", cat: "vod", name: "Sprite Fright")],
            series:   [Fx.series("s1", cat: "ser", name: "Breaking Bad")],
            liveCats: [Fx.category("News")], movieCats: [Fx.category("vod")],
            seriesCats: [Fx.category("ser")]), scope: s)

        #expect(CatalogDB.isPopulated(scope: s))
        #expect(CatalogDB.moviesByIds(scope: s, ids: ["m1"]).first?.name == "Sprite Fright")
        #expect(CatalogDB.channelsByIds(scope: s, ids: ["c1"]).first?.name == "BBC News")
        #expect(CatalogDB.seriesByIds(scope: s, ids: ["s1"]).first?.name == "Breaking Bad")
        #expect(CatalogDB.countMovies(scope: s, category: nil) == 1)
        #expect(CatalogDB.categories(scope: s, kind: "live").map(\.id) == ["News"])
    }

    @Test("one scope cannot see another scope's catalogue")
    func scopesAreIsolated() {
        let a = scope("iso-a"), b = scope("iso-b")
        CatalogDB.save(content(movies: [Fx.movie("shared-id", cat: "c", name: "In A")]), scope: a)
        CatalogDB.save(content(movies: [Fx.movie("shared-id", cat: "c", name: "In B")]), scope: b)
        #expect(CatalogDB.moviesByIds(scope: a, ids: ["shared-id"]).first?.name == "In A")
        #expect(CatalogDB.moviesByIds(scope: b, ids: ["shared-id"]).first?.name == "In B")
    }

    @Test("re-saving a scope replaces it rather than appending to it")
    func saveReplaces() {
        let s = scope("replace")
        CatalogDB.save(content(movies: (0..<5).map { Fx.movie("old\($0)", cat: "c") }), scope: s)
        CatalogDB.save(content(movies: [Fx.movie("new", cat: "c")]), scope: s)
        #expect(CatalogDB.countMovies(scope: s, category: nil) == 1)
        #expect(CatalogDB.moviesByIds(scope: s, ids: ["old0"]).isEmpty)
    }

    // MARK: Search — the reason the FTS index exists

    @Test("search finds a Latin title")
    func searchLatin() {
        let s = scope("search-latin")
        CatalogDB.save(content(movies: [Fx.movie("m1", cat: "c", name: "Sprite Fright")]), scope: s)
        #expect(CatalogDB.search("sprite", kind: "movie", scope: s, limit: 10) == ["m1"])
        #expect(CatalogDB.search("SPRITE", kind: "movie", scope: s, limit: 10) == ["m1"])
    }

    @Test("search is a prefix search, as the UI assumes while the user is typing")
    func searchIsPrefix() {
        let s = scope("search-prefix")
        CatalogDB.save(content(movies: [Fx.movie("m1", cat: "c", name: "Interstellar")]), scope: s)
        #expect(CatalogDB.search("inter", kind: "movie", scope: s, limit: 10) == ["m1"])
    }

    // THE DEFECT THIS STORE SHIPPED WITH.
    //
    // `tokenize = 'unicode61 remove_diacritics 2'` sounds like it covers this. It does
    // not: run against SQLite 3.50.4, an indexed "أفلام عربية" was not found by the
    // query "افلام". The fix is application-side folding on BOTH sides, and these are
    // the tests that hold it in place.
    @Test("search matches across hamza forms")
    func searchFoldsHamza() {
        let s = scope("search-hamza")
        CatalogDB.save(content(movies: [Fx.movie("m1", cat: "c", name: "أفلام عربية")]), scope: s)
        #expect(CatalogDB.search("افلام", kind: "movie", scope: s, limit: 10) == ["m1"])
        #expect(CatalogDB.search("أفلام", kind: "movie", scope: s, limit: 10) == ["m1"])
    }

    @Test("search matches across harakat")
    func searchFoldsHarakat() {
        let s = scope("search-harakat")
        CatalogDB.save(content(series: [Fx.series("s1", cat: "c", name: "مُسَلْسَل تركي")]), scope: s)
        #expect(CatalogDB.search("مسلسل", kind: "series", scope: s, limit: 10) == ["s1"])
    }

    @Test("a harakat-laden QUERY finds a plainly-written title")
    func searchFoldsTheQueryToo() {
        // The mirror of the case above. Folding only one side would pass one of these
        // two tests and fail the other, which is exactly how this defect hid.
        let s = scope("search-query-harakat")
        CatalogDB.save(content(movies: [Fx.movie("m1", cat: "c", name: "مسلسل")]), scope: s)
        #expect(CatalogDB.search("مُسَلْسَل", kind: "movie", scope: s, limit: 10) == ["m1"])
    }

    @Test("search is scoped by kind")
    func searchRespectsKind() {
        let s = scope("search-kind")
        CatalogDB.save(content(movies: [Fx.movie("m1", cat: "c", name: "Echo")],
                               series: [Fx.series("s1", cat: "c", name: "Echo")]), scope: s)
        #expect(CatalogDB.search("echo", kind: "movie", scope: s, limit: 10) == ["m1"])
        #expect(CatalogDB.search("echo", kind: "series", scope: s, limit: 10) == ["s1"])
    }

    @Test("an empty or punctuation-only query returns nothing rather than everything")
    func emptyQuery() {
        let s = scope("search-empty")
        CatalogDB.save(content(movies: [Fx.movie("m1", cat: "c", name: "Anything")]), scope: s)
        #expect(CatalogDB.search("", kind: "movie", scope: s, limit: 10).isEmpty)
        #expect(CatalogDB.search("   ", kind: "movie", scope: s, limit: 10).isEmpty)
        #expect(CatalogDB.search("!!!", kind: "movie", scope: s, limit: 10).isEmpty)
    }

    // MARK: read(scope:) — the cold-start path

    @Test("read returns the catalogue and its age, not a freshness verdict")
    func readReturnsAge() throws {
        let s = scope("read-age")
        CatalogDB.save(content(movies: [Fx.movie("m1", cat: "c", name: "Stored")]), scope: s)
        let hit = try #require(CatalogDB.read(scope: s))
        #expect(hit.content.movies.first?.name == "Stored")
        #expect(hit.age >= 0 && hit.age < 60)
    }

    @Test("read serves a STALE catalogue, because load's TTL cliff is what it exists to avoid")
    func readIgnoresTTL() throws {
        // `load` returns nil past the TTL, so a caller cannot tell "nothing stored"
        // from "stored, slightly stale" and blocks on a full network parse either way.
        // Stale-while-revalidate needs the bytes plus the age. Backdating savedAt is
        // the only way to assert that without waiting twelve hours.
        let s = scope("read-stale")
        CatalogDB.save(content(movies: [Fx.movie("m1", cat: "c", name: "Old")]), scope: s)
        let pool = try #require(CatalogDB.dbPool)
        let longAgo = Date().timeIntervalSince1970 - (CatalogDB.ttl + 3600)
        try pool.write { db in
            try db.execute(sql: "UPDATE catalog_meta SET savedAt = ? WHERE scope = ?",
                           arguments: [longAgo, s])
        }
        #expect(CatalogDB.load(scope: s) == nil, "load must still enforce its TTL")
        let hit = try #require(CatalogDB.read(scope: s), "read must serve it anyway")
        #expect(hit.content.movies.first?.name == "Old")
        #expect(hit.age > CatalogDB.ttl)
    }

    @Test("read on an unknown scope returns nothing")
    func readMissing() {
        #expect(CatalogDB.read(scope: scope("read-missing")) == nil)
    }

    @Test("read preserves provider order")
    func readPreservesOrder() throws {
        let s = scope("read-order")
        let ids = ["z", "a", "m", "b"]     // deliberately not sorted
        CatalogDB.save(content(movies: ids.map { Fx.movie($0, cat: "c") }), scope: s)
        let hit = try #require(CatalogDB.read(scope: s))
        #expect(hit.content.movies.map(\.id) == ids)
    }

    // MARK: Keyset paging — the path m1.4 will switch the lists onto

    @Test("paging walks the whole catalogue in provider order, once each")
    func pagingIsCompleteAndOrdered() {
        let s = scope("paging")
        let all = (0..<25).map { Fx.movie("p\(String(format: "%02d", $0))", cat: "c") }
        CatalogDB.save(content(movies: all), scope: s)

        var seen: [String] = []
        var cursor: Int? = nil
        var guardRail = 0
        repeat {
            let page = CatalogDB.pageMovies(scope: s, category: nil, after: cursor, limit: 10)
            seen += page.items.map(\.id)
            cursor = page.nextCursor
            guardRail += 1
        } while cursor != nil && guardRail < 10

        #expect(seen == all.map(\.id))          // order preserved, nothing skipped
        #expect(Set(seen).count == seen.count)  // nothing repeated
    }

    @Test("paging can be narrowed to one category")
    func pagingByCategory() {
        let s = scope("paging-cat")
        CatalogDB.save(content(movies: (0..<3).map { Fx.movie("a\($0)", cat: "A") }
                                      + (0..<4).map { Fx.movie("b\($0)", cat: "B") }), scope: s)
        let page = CatalogDB.pageMovies(scope: s, category: "B", after: nil, limit: 50)
        #expect(page.items.count == 4)
        #expect(page.items.allSatisfy { $0.categoryID == "B" })
        #expect(CatalogDB.countMovies(scope: s, category: "B") == 4)
    }

    @Test("paging an empty scope returns nothing and no cursor")
    func pagingEmpty() {
        let page = CatalogDB.pageMovies(scope: scope("paging-empty"), category: nil, after: nil, limit: 10)
        #expect(page.items.isEmpty)
        #expect(page.nextCursor == nil)
    }
}

// MARK: - Migrations

@Suite("CatalogDB — migrations")
struct CatalogDBMigrationTests {

    @Test("a fresh store migrates to the current schema and is empty")
    func freshStore() throws {
        let pool = try CatalogDB.makeStore(path: tempStorePath("fresh"))
        let tables = try pool.read { db -> Set<String> in
            let names = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table','view')")
            return Set(names)
        }
        for t in ["channel", "movie", "series", "category", "catalog_meta", "catalog_fts", "image_hash"] {
            #expect(tables.contains(t), "missing table \(t)")
        }
        let n = try pool.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM catalog_fts") }
        #expect(n == 0)
    }

    @Test("migrating twice is a no-op rather than an error")
    func idempotent() throws {
        let path = tempStorePath("twice")
        _ = try CatalogDB.makeStore(path: path)
        _ = try CatalogDB.makeStore(path: path)   // must not throw
    }

    /// The one that matters. An install from before the folding fix carries an FTS
    /// index built from RAW names while the query side now folds — and that
    /// combination returns NOTHING for Arabic, which is worse than the bug it
    /// replaced. `v3_fold_fts` exists to rebuild it, and this is the only honest way
    /// to test it: create the old state, then migrate across.
    @Test("v3 rebuilds an index that an older build wrote unfolded")
    func v3RebuildsStaleIndex() throws {
        let path = tempStorePath("v3")
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA synchronous = NORMAL") }
        let pool = try DatabasePool(path: path, configuration: config)

        // Stop at v2 — the schema as an older build left it.
        try CatalogDB.migrator.migrate(pool, upTo: "v2_imagehash")

        // Write what that build would have written: real rows, and an FTS entry with
        // the name exactly as the provider sent it.
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO movie (scope, id, name, categoryID, containerExtension, pos)
                VALUES ('s', 'm1', 'أفلام عربية', 'c', 'mp4', 0)
                """)
            try db.execute(sql: """
                INSERT INTO catalog_fts (scope, kind, itemId, name, genre, actors, plot, director)
                VALUES ('s', 'movie', 'm1', 'أفلام عربية', '', '', '', '')
                """)
        }

        // Proof the old state really is broken, so this test cannot pass vacuously.
        let beforeHits = try pool.read { db in
            try String.fetchAll(db, sql: "SELECT itemId FROM catalog_fts WHERE catalog_fts MATCH ?",
                                arguments: ["افلام*"])
        }
        #expect(beforeHits.isEmpty, "the pre-migration index was expected to be unsearchable")

        try CatalogDB.migrator.migrate(pool)

        let afterHits = try pool.read { db in
            try String.fetchAll(db, sql: "SELECT itemId FROM catalog_fts WHERE catalog_fts MATCH ?",
                                arguments: ["افلام*"])
        }
        #expect(afterHits == ["m1"])
    }

    @Test("v3 carries a movie's other indexed fields across, not just its name")
    func v3KeepsEveryField() throws {
        let path = tempStorePath("v3-fields")
        let pool = try DatabasePool(path: path)
        try CatalogDB.migrator.migrate(pool, upTo: "v2_imagehash")
        // "cast" is the SQL keyword; unquoted here it is a syntax error, which is the
        // same trap the migration itself has to avoid.
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO movie (scope, id, name, genre, "cast", plot, director, categoryID, containerExtension, pos)
                VALUES ('s', 'm1', 'Title', 'Drama', 'Emma Watson', 'A plot line', 'Some Director', 'c', 'mp4', 0)
                """)
        }
        try CatalogDB.migrator.migrate(pool)
        let row = try pool.read { db in
            try Row.fetchOne(db, sql: "SELECT name, genre, actors, plot, director FROM catalog_fts WHERE itemId = 'm1'")
        }
        let r = try #require(row)
        #expect(r["name"] as String == "title")
        #expect(r["genre"] as String == "drama")
        #expect(r["actors"] as String == "emma watson")
        #expect(r["plot"] as String == "a plot line")
        #expect(r["director"] as String == "some director")
    }

    @Test("v3 on an empty store does nothing and does not fail")
    func v3OnEmptyStore() throws {
        let pool = try DatabasePool(path: tempStorePath("v3-empty"))
        try CatalogDB.migrator.migrate(pool, upTo: "v2_imagehash")
        try CatalogDB.migrator.migrate(pool)      // must not throw
        let n = try pool.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM catalog_fts") }
        #expect(n == 0)
    }
}
