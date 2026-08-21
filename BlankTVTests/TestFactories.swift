// ============================================================
// BLANK TV — TestFactories.swift
// Model builders for the test suites.
//
// They exist so a test reads as the ONE thing it is asserting. A `Movie` has
// thirteen initialiser parameters and a rail test cares about exactly two of them
// (category and rating); spelling the other eleven out at every call site buries
// the assertion in noise and — worse — makes a test that fails for an unrelated
// reason look like a rail bug.
//
// Every default here is deliberately INERT: nil metadata, no artwork, no direct
// URL. A test that needs a field sets it, and nothing else can influence a result.
// ============================================================

import Foundation
@testable import BlankTV

enum Fx {

    static func category(_ id: String, _ name: String? = nil) -> Category {
        Category(id: id, name: name ?? id, parentID: nil)
    }

    static func movie(_ id: String,
                      cat: String = "c",
                      rating: String? = nil,
                      name: String? = nil,
                      ext: String = "mp4",
                      directURL: String? = nil) -> Movie {
        Movie(id: id, name: name ?? "movie-\(id)",
              posterURL: nil, backdropURL: nil,
              year: nil, rating: rating, genre: nil, plot: nil,
              duration: nil, director: nil, cast: nil,
              categoryID: cat, containerExtension: ext,
              directURL: directURL)
    }

    static func series(_ id: String,
                       cat: String = "c",
                       rating: String? = nil,
                       name: String? = nil) -> Series {
        Series(id: id, name: name ?? "series-\(id)",
               coverURL: nil, backdropURL: nil,
               year: nil, rating: rating, genre: nil, plot: nil,
               cast: nil, director: nil,
               categoryID: cat, seasons: [])
    }

    static func channel(_ id: String,
                        group: String = "g",
                        name: String? = nil,
                        directURL: String? = nil) -> Channel {
        Channel(id: id, name: name ?? "channel-\(id)",
                logoURL: nil, groupTitle: group,
                epgChannelID: nil, directURL: directURL)
    }

    static func episode(_ id: String,
                        season: Int = 1,
                        number: Int = 1,
                        ext: String = "mkv",
                        directURL: String? = nil) -> Episode {
        Episode(id: id, title: "episode-\(id)",
                episodeNumber: number, seasonNumber: season,
                containerExtension: ext,
                posterURL: nil, plot: nil, duration: nil,
                directURL: directURL)
    }

    /// `n` movies in one category, each with a distinct id.
    static func movies(_ n: Int, cat: String, rating: String? = nil) -> [Movie] {
        (0..<n).map { movie("\(cat)-\($0)", cat: cat, rating: rating) }
    }

    /// `n` series in one category, each with a distinct id.
    static func seriesList(_ n: Int, cat: String, rating: String? = nil) -> [Series] {
        (0..<n).map { series("\(cat)-\($0)", cat: cat, rating: rating) }
    }
}
