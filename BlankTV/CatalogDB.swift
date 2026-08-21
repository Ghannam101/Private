// ============================================================
// BLANK TV — CatalogDB.swift
// Local SQLite catalog store (GRDB) — the scalable replacement for the eager
// in-memory M3UContent + JSON blob (CatalogDiskCache). Bounded memory at ANY
// catalog size via keyset-paged reads on covering (scope[,category],pos) indexes,
// plus an FTS5 index for instant diacritic-insensitive search across 20k–50k
// channels / movies / series.
//
// A clean-sheet v1 store for BLANK: a single v1
// migration that bakes in `pos` (provider order = keyset sort key) + covering
// indexes + the multi-field FTS index from the start — no legacy migration dance.
//
// STEP 2 (isolated): schema + records + save / load / paging / search. NO consumer
// yet — CatalogDiskCache stays the live path until the VMs are switched over
// (step 4). Mirrors CatalogDiskCache.save(_:scope:) / load(scope:) so the swap is a
// drop-in. If the store can't open, every call degrades to a safe no-op / nil and
// the legacy JSON cache carries on unharmed.
// ============================================================

import Foundation
import GRDB

enum CatalogDB {
    /// Same freshness window as the legacy JSON cache (stale-while-revalidate).
    static let ttl: TimeInterval = 12 * 3600   // matches CatalogDiskCache.ttl

    // One shared connection, opened lazily. nil if the store can't be created.
    static let dbQueue: DatabaseQueue? = {
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask, appropriateFor: nil, create: true)
            let q = try DatabaseQueue(path: dir.appendingPathComponent("catalog.sqlite").path)
            try migrator.migrate(q)
            return q
        } catch { print("CatalogDB init failed:", error); return nil }
    }()

    // MARK: - Records (row ⇄ model). `pos` = provider insertion order = keyset sort key.
    struct Chan: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "channel"
        var scope: String; var id: String; var name: String
        var logoURL: String?; var groupTitle: String; var epgChannelID: String?; var directURL: String?
        var pos: Int = 0
        var model: Channel { Channel(id: id, name: name, logoURL: logoURL,
                                     groupTitle: groupTitle, epgChannelID: epgChannelID, directURL: directURL) }
    }
    struct Mov: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "movie"
        var scope: String; var id: String; var name: String
        var posterURL: String?; var backdropURL: String?; var year: String?; var rating: String?
        var genre: String?; var plot: String?; var duration: String?; var director: String?; var cast: String?
        var categoryID: String; var containerExtension: String; var directURL: String?
        var pos: Int = 0
        var model: Movie { Movie(id: id, name: name, posterURL: posterURL, backdropURL: backdropURL,
                                 year: year, rating: rating, genre: genre, plot: plot, duration: duration,
                                 director: director, cast: cast, categoryID: categoryID,
                                 containerExtension: containerExtension, directURL: directURL) }
    }
    struct Ser: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "series"
        var scope: String; var id: String; var name: String
        var coverURL: String?; var backdropURL: String?; var year: String?; var rating: String?
        var genre: String?; var plot: String?; var cast: String?; var director: String?; var categoryID: String
        var pos: Int = 0
        var model: Series { Series(id: id, name: name, coverURL: coverURL, backdropURL: backdropURL,
                                   year: year, rating: rating, genre: genre, plot: plot, cast: cast,
                                   director: director, categoryID: categoryID) }
    }
    struct Cat: Codable, FetchableRecord, PersistableRecord {
        static let databaseTableName = "category"
        var scope: String; var kind: String; var id: String; var name: String
    }

    // MARK: - Schema — one clean migration (fresh store, no legacy history to replay).
    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1_catalog") { db in
            try db.create(table: "channel") { t in
                t.column("scope", .text).notNull(); t.column("id", .text).notNull()
                t.column("name", .text).notNull(); t.column("logoURL", .text)
                t.column("groupTitle", .text).notNull(); t.column("epgChannelID", .text)
                t.column("directURL", .text)
                t.column("pos", .integer).notNull().defaults(to: 0)
                t.primaryKey(["scope", "id"])
            }
            try db.create(index: "channel_scope_pos",     on: "channel", columns: ["scope", "pos"])
            try db.create(index: "channel_scope_cat_pos",  on: "channel", columns: ["scope", "groupTitle", "pos"])

            try db.create(table: "movie") { t in
                t.column("scope", .text).notNull(); t.column("id", .text).notNull()
                t.column("name", .text).notNull(); t.column("posterURL", .text); t.column("backdropURL", .text)
                t.column("year", .text); t.column("rating", .text); t.column("genre", .text); t.column("plot", .text)
                t.column("duration", .text); t.column("director", .text); t.column("cast", .text)
                t.column("categoryID", .text).notNull(); t.column("containerExtension", .text).notNull()
                t.column("directURL", .text)
                t.column("pos", .integer).notNull().defaults(to: 0)
                t.primaryKey(["scope", "id"])
            }
            try db.create(index: "movie_scope_pos",     on: "movie", columns: ["scope", "pos"])
            try db.create(index: "movie_scope_cat_pos",  on: "movie", columns: ["scope", "categoryID", "pos"])

            try db.create(table: "series") { t in
                t.column("scope", .text).notNull(); t.column("id", .text).notNull()
                t.column("name", .text).notNull(); t.column("coverURL", .text); t.column("backdropURL", .text)
                t.column("year", .text); t.column("rating", .text); t.column("genre", .text); t.column("plot", .text)
                t.column("cast", .text); t.column("director", .text); t.column("categoryID", .text).notNull()
                t.column("pos", .integer).notNull().defaults(to: 0)
                t.primaryKey(["scope", "id"])
            }
            try db.create(index: "series_scope_pos",     on: "series", columns: ["scope", "pos"])
            try db.create(index: "series_scope_cat_pos",  on: "series", columns: ["scope", "categoryID", "pos"])

            try db.create(table: "category") { t in
                t.column("scope", .text).notNull(); t.column("kind", .text).notNull()
                t.column("id", .text).notNull(); t.column("name", .text).notNull()
                t.primaryKey(["scope", "kind", "id"])
            }
            try db.create(table: "catalog_meta") { t in
                t.column("scope", .text).primaryKey(); t.column("savedAt", .double).notNull()
            }
            // FTS5: instant diacritic-insensitive search over name+genre+cast+plot+director.
            // scope/kind/itemId are stored UNINDEXED (filter + retrieval only). `actors`
            // avoids the SQL CAST keyword clash with a column literally named "cast".
            try db.execute(sql: """
                CREATE VIRTUAL TABLE catalog_fts USING fts5(
                    scope UNINDEXED, kind UNINDEXED, itemId UNINDEXED,
                    name, genre, actors, plot, director,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """)
        }
        // Perceived-instant images: a ~25-byte ThumbHash per image URL, so a blurred
        // structure-preserving placeholder paints instantly on the next cold start,
        // before the real poster/logo downloads. Keyed by URL (global, NOT per-scope —
        // the same poster reused across lines shares one hash). Additive migration.
        m.registerMigration("v2_imagehash") { db in
            try db.create(table: "image_hash") { t in
                t.column("url", .text).primaryKey()
                t.column("hash", .blob).notNull()
                t.column("savedAt", .double).notNull()
            }
        }
        // Rebuild the FTS index with folded text.
        //
        // Not cosmetic and not deferrable: every install that already has a catalogue
        // carries an index built from RAW names, and the query side now folds. Without
        // this the two sides speak different alphabets and Arabic search returns
        // nothing at all — strictly worse than the bug being fixed.
        //
        // Rebuilt from `channel` / `movie` / `series`, which are the source of truth
        // and are written in the same transaction as the index, so they cannot be out
        // of step with it. Streamed with a cursor rather than fetched into an array: a
        // fifty-thousand-title catalogue carries plot text, and materialising all of it
        // to migrate a database is how a migration becomes the crash it was meant to
        // prevent. Reading one table while inserting into another is safe in SQLite.
        //
        // A fresh install runs this against empty tables and does nothing.
        m.registerMigration("v3_fold_fts") { db in
            let f = S8KFold.key
            try db.execute(sql: "DELETE FROM catalog_fts")
            let ins = """
                INSERT INTO catalog_fts (scope, kind, itemId, name, genre, actors, plot, director)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """
            let chans = try Row.fetchCursor(db, sql: "SELECT scope, id, name FROM channel")
            while let r = try chans.next() {
                try db.execute(sql: ins, arguments: [r["scope"] as String, "live", r["id"] as String,
                                                     f(r["name"] as String), "", "", "", ""])
            }
            for (table, kind) in [("movie", "movie"), ("series", "series")] {
                // "cast" is QUOTED because it is the SQL keyword CAST. The FTS column
                // beside it is named `actors` for exactly this reason — the note on the
                // v1 migration says so — and an unquoted `cast` here is a syntax error
                // that would only ever surface on a device mid-migration.
                let rows = try Row.fetchCursor(db, sql: """
                    SELECT scope, id, name, genre, "cast", plot, director FROM \(table)
                    """)
                while let r = try rows.next() {
                    try db.execute(sql: ins, arguments: [
                        r["scope"] as String, kind, r["id"] as String,
                        f(r["name"] as String),
                        f(r["genre"] as String? ?? ""), f(r["cast"] as String? ?? ""),
                        f(r["plot"] as String? ?? ""), f(r["director"] as String? ?? "")
                    ])
                }
            }
        }
        return m
    }

    // MARK: - Load / populate guard (parallels CatalogDiskCache.load)
    static func load(scope: String, ttl: TimeInterval = CatalogDB.ttl) -> M3UContent? {
        guard let q = dbQueue else { return nil }
        return try? q.read { db -> M3UContent? in
            guard let savedAt = try Double.fetchOne(db,
                    sql: "SELECT savedAt FROM catalog_meta WHERE scope = ?", arguments: [scope]),
                  Date().timeIntervalSince1970 - savedAt < ttl else { return nil }
            let chans = try Chan.filter(Column("scope") == scope).order(Column("pos")).fetchAll(db)
            let movs  = try Mov.filter(Column("scope") == scope).order(Column("pos")).fetchAll(db)
            let sers  = try Ser.filter(Column("scope") == scope).order(Column("pos")).fetchAll(db)
            let cats  = try Cat.filter(Column("scope") == scope).fetchAll(db)
            guard !chans.isEmpty || !movs.isEmpty || !sers.isEmpty else { return nil }
            var c = M3UContent()
            c.channels = chans.map(\.model)
            c.movies   = movs.map(\.model)
            c.series   = sers.map(\.model)
            func catsOf(_ kind: String) -> [Category] {
                cats.filter { $0.kind == kind }.map { Category(id: $0.id, name: $0.name, parentID: nil) }
            }
            c.liveCategories = catsOf("live"); c.movieCategories = catsOf("movie"); c.seriesCategories = catsOf("series")
            return c
        } ?? nil
    }

    static func isPopulated(scope: String) -> Bool {
        guard let q = dbQueue else { return false }
        return (try? q.read { db in
            try Chan.filter(Column("scope") == scope).fetchCount(db) > 0
            || (try Mov.filter(Column("scope") == scope).fetchCount(db)) > 0
            || (try Ser.filter(Column("scope") == scope).fetchCount(db)) > 0
        }) ?? false
    }

    // MARK: - FTS search
    /// Turn a user's typing into an FTS5 MATCH expression.
    ///
    /// `S8KFold.key` FIRST, and the index is built with the same call. The tokenizer
    /// is `unicode61 remove_diacritics 2`, whose name promises more than it delivers:
    /// verified against SQLite 3.50.4, it leaves Arabic hamza forms and harakat
    /// exactly as they were, so `افلام` did not match an indexed `أفلام`. Normalising
    /// on both sides is what makes the index searchable in the app's first language.
    private static func ftsQuery(_ raw: String) -> String? {
        let tokens = S8KFold.key(raw).lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\($0)*" }.joined(separator: " ")
    }
    /// FTS search → ordered matching item ids for a scope + kind (live|movie|series).
    static func search(_ raw: String, kind: String, scope: String, limit: Int) -> [String] {
        guard let q = dbQueue, let match = ftsQuery(raw) else { return [] }
        return (try? q.read { db in
            try String.fetchAll(db, sql: """
                SELECT itemId FROM catalog_fts
                WHERE catalog_fts MATCH ? AND scope = ? AND kind = ?
                ORDER BY rank LIMIT ?
                """, arguments: [match, scope, kind, limit])
        }) ?? []
    }
    static func isSearchable(scope: String) -> Bool {
        guard let q = dbQueue else { return false }
        return (try? q.read { db in
            try Int.fetchOne(db, sql: "SELECT 1 FROM catalog_fts WHERE scope = ? LIMIT 1", arguments: [scope]) != nil
        }) ?? false
    }

    // MARK: - Keyset paging (constant-time at any depth on the covering indexes)
    static func pageChannels(scope: String, category: String?, after: Int?, limit: Int) -> (items: [Channel], nextCursor: Int?) {
        guard let q = dbQueue else { return ([], nil) }
        let rows: [Chan] = (try? q.read { db -> [Chan] in
            var req = Chan.filter(Column("scope") == scope)
            if let category { req = req.filter(Column("groupTitle") == category) }
            if let after { req = req.filter(Column("pos") > after) }
            return try req.order(Column("pos")).limit(limit).fetchAll(db)
        }) ?? []
        return (rows.map(\.model), rows.count == limit ? rows.last?.pos : nil)
    }
    static func pageMovies(scope: String, category: String?, after: Int?, limit: Int) -> (items: [Movie], nextCursor: Int?) {
        guard let q = dbQueue else { return ([], nil) }
        let rows: [Mov] = (try? q.read { db -> [Mov] in
            var req = Mov.filter(Column("scope") == scope)
            if let category { req = req.filter(Column("categoryID") == category) }
            if let after { req = req.filter(Column("pos") > after) }
            return try req.order(Column("pos")).limit(limit).fetchAll(db)
        }) ?? []
        return (rows.map(\.model), rows.count == limit ? rows.last?.pos : nil)
    }
    static func pageSeries(scope: String, category: String?, after: Int?, limit: Int) -> (items: [Series], nextCursor: Int?) {
        guard let q = dbQueue else { return ([], nil) }
        let rows: [Ser] = (try? q.read { db -> [Ser] in
            var req = Ser.filter(Column("scope") == scope)
            if let category { req = req.filter(Column("categoryID") == category) }
            if let after { req = req.filter(Column("pos") > after) }
            return try req.order(Column("pos")).limit(limit).fetchAll(db)
        }) ?? []
        return (rows.map(\.model), rows.count == limit ? rows.last?.pos : nil)
    }

    // MARK: - Resolve FTS hits → models (preserve rank order)
    static func channelsByIds(scope: String, ids: [String]) -> [Channel] {
        guard let q = dbQueue, !ids.isEmpty else { return [] }
        let rows: [Chan] = (try? q.read { db in
            try Chan.filter(Column("scope") == scope && ids.contains(Column("id"))).fetchAll(db)
        }) ?? []
        let byId = Dictionary(rows.map { ($0.id, $0.model) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byId[$0] }
    }
    static func moviesByIds(scope: String, ids: [String]) -> [Movie] {
        guard let q = dbQueue, !ids.isEmpty else { return [] }
        let rows: [Mov] = (try? q.read { db in
            try Mov.filter(Column("scope") == scope && ids.contains(Column("id"))).fetchAll(db)
        }) ?? []
        let byId = Dictionary(rows.map { ($0.id, $0.model) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byId[$0] }
    }
    static func seriesByIds(scope: String, ids: [String]) -> [Series] {
        guard let q = dbQueue, !ids.isEmpty else { return [] }
        let rows: [Ser] = (try? q.read { db in
            try Ser.filter(Column("scope") == scope && ids.contains(Column("id"))).fetchAll(db)
        }) ?? []
        let byId = Dictionary(rows.map { ($0.id, $0.model) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byId[$0] }
    }

    // MARK: - Counts (list headers / folder cards)
    static func countMovies(scope: String, category: String?) -> Int {
        guard let q = dbQueue else { return 0 }
        return (try? q.read { db -> Int in
            var req = Mov.filter(Column("scope") == scope)
            if let category { req = req.filter(Column("categoryID") == category) }
            return try req.fetchCount(db)
        }) ?? 0
    }
    private struct CatCount: Codable, FetchableRecord { var categoryID: String; var n: Int }
    static func movieCategoryCounts(scope: String) -> [String: Int] {
        guard let q = dbQueue else { return [:] }
        return (try? q.read { db -> [String: Int] in
            let rows = try CatCount.fetchAll(db, sql:
                "SELECT categoryID, COUNT(*) AS n FROM movie WHERE scope = ? GROUP BY categoryID", arguments: [scope])
            return Dictionary(rows.map { ($0.categoryID, $0.n) }, uniquingKeysWith: { a, _ in a })
        }) ?? [:]
    }
    static func categories(scope: String, kind: String) -> [Category] {
        guard let q = dbQueue else { return [] }
        let rows: [Cat] = (try? q.read { db in
            try Cat.filter(Column("scope") == scope && Column("kind") == kind).fetchAll(db)
        }) ?? []
        return rows.map { Category(id: $0.id, name: $0.name, parentID: nil) }
    }

    /// Empty EVERY scope. Account deletion only — "delete all my data" has to mean
    /// the catalogue as well as the login. Rows are dropped inside the existing queue
    /// rather than unlinking the file: `dbQueue` is opened once for the process
    /// lifetime, so pulling the file out from under it would leave every later read
    /// failing silently instead of rebuilding.
    static func deleteEverything() {
        guard let q = dbQueue else { return }
        try? q.write { db in
            for t in ["channel", "movie", "series", "category", "catalog_fts",
                      "catalog_meta", "image_hash"] {
                try? db.execute(sql: "DELETE FROM \(t)")
            }
        }
    }

    // MARK: - Bulk write (replace-all for scope inside ONE transaction, off-main by caller)
    static func save(_ c: M3UContent, scope: String) {
        guard let q = dbQueue else { return }
        do {
            try q.write { db in
                try Chan.filter(Column("scope") == scope).deleteAll(db)
                try Mov.filter(Column("scope") == scope).deleteAll(db)
                try Ser.filter(Column("scope") == scope).deleteAll(db)
                try Cat.filter(Column("scope") == scope).deleteAll(db)
                for (i, x) in c.channels.enumerated() {
                    try Chan(scope: scope, id: x.id, name: x.name, logoURL: x.logoURL,
                             groupTitle: x.groupTitle, epgChannelID: x.epgChannelID, directURL: x.directURL, pos: i).insert(db)
                }
                for (i, x) in c.movies.enumerated() {
                    try Mov(scope: scope, id: x.id, name: x.name, posterURL: x.posterURL, backdropURL: x.backdropURL,
                            year: x.year, rating: x.rating, genre: x.genre, plot: x.plot, duration: x.duration,
                            director: x.director, cast: x.cast, categoryID: x.categoryID,
                            containerExtension: x.containerExtension, directURL: x.directURL, pos: i).insert(db)
                }
                for (i, x) in c.series.enumerated() {
                    try Ser(scope: scope, id: x.id, name: x.name, coverURL: x.coverURL, backdropURL: x.backdropURL,
                            year: x.year, rating: x.rating, genre: x.genre, plot: x.plot, cast: x.cast,
                            director: x.director, categoryID: x.categoryID, pos: i).insert(db)
                }
                for (kind, cats) in [("live", c.liveCategories), ("movie", c.movieCategories), ("series", c.seriesCategories)] {
                    for cat in cats { try Cat(scope: scope, kind: kind, id: cat.id, name: cat.name).insert(db) }
                }
                // FTS index (raw SQL — catalog_fts is a virtual table, not a Record).
                try db.execute(sql: "DELETE FROM catalog_fts WHERE scope = ?", arguments: [scope])
                let ins = "INSERT INTO catalog_fts (scope, kind, itemId, name, genre, actors, plot, director) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
                // FOLDED on the way in — see the note on `ftsQuery`. unicode61 does not
                // touch Arabic, so the normalisation has to happen here, and the query
                // side has to use the SAME rule or the index becomes unsearchable.
                let f = S8KFold.key
                for x in c.channels { try db.execute(sql: ins, arguments: [scope, "live",   x.id, f(x.name), "", "", "", ""]) }
                for x in c.movies   { try db.execute(sql: ins, arguments: [scope, "movie",  x.id, f(x.name), f(x.genre ?? ""), f(x.cast ?? ""), f(x.plot ?? ""), f(x.director ?? "")]) }
                for x in c.series   { try db.execute(sql: ins, arguments: [scope, "series", x.id, f(x.name), f(x.genre ?? ""), f(x.cast ?? ""), f(x.plot ?? ""), f(x.director ?? "")]) }
                try db.execute(sql: "INSERT OR REPLACE INTO catalog_meta (scope, savedAt) VALUES (?, ?)",
                               arguments: [scope, Date().timeIntervalSince1970])
            }
        } catch { print("CatalogDB save failed:", error) }
    }

    // MARK: - Image ThumbHash cache (perceived-instant poster/logo placeholders)
    /// The stored ThumbHash bytes for an image URL, or nil if not encoded yet.
    static func imageHash(_ url: String) -> Data? {
        guard let q = dbQueue else { return nil }
        return (try? q.read { db in
            try Data.fetchOne(db, sql: "SELECT hash FROM image_hash WHERE url = ?", arguments: [url])
        }) ?? nil
    }
    /// Fast existence check (skip the ~1-2ms re-encode when a URL is already hashed).
    static func hasImageHash(_ url: String) -> Bool {
        guard let q = dbQueue else { return false }
        return (try? q.read { db in
            try Int.fetchOne(db, sql: "SELECT 1 FROM image_hash WHERE url = ? LIMIT 1", arguments: [url]) != nil
        }) ?? false
    }
    /// Persist (or replace) the ThumbHash for an image URL. Tiny (~25-byte) write.
    static func saveImageHash(_ url: String, _ hash: Data) {
        guard let q = dbQueue else { return }
        try? q.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO image_hash (url, hash, savedAt) VALUES (?, ?, ?)",
                           arguments: [url, hash, Date().timeIntervalSince1970])
        }
    }
}
