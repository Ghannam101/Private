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

// NAMES ARE QUALIFIED WITH `BlankTV.` DELIBERATELY.
//
// The Objective-C runtime declares `typedef struct objc_category *Category;` in
// objc/runtime.h, which Swift surfaces as `ObjectiveC.Category`. Inside the app
// that never matters: `Category` is declared in the same module, and a local
// declaration shadows an imported one. Inside a TEST bundle both names arrive by
// import, they rank equally, and the compiler stops at
// "'Category' is ambiguous for type lookup in this context" — which is exactly
// how the first green-attempt build failed.
//
// Every model name is qualified rather than only the one that collided today,
// because the next collision would be found the same expensive way.
enum Fx {

    static func category(_ id: String, _ name: String? = nil) -> BlankTV.Category {
        BlankTV.Category(id: id, name: name ?? id, parentID: nil)
    }

    static func movie(_ id: String,
                      cat: String = "c",
                      rating: String? = nil,
                      name: String? = nil,
                      ext: String = "mp4",
                      directURL: String? = nil) -> BlankTV.Movie {
        BlankTV.Movie(id: id, name: name ?? "movie-\(id)",
              posterURL: nil, backdropURL: nil,
              year: nil, rating: rating, genre: nil, plot: nil,
              duration: nil, director: nil, cast: nil,
              categoryID: cat, containerExtension: ext,
              directURL: directURL)
    }

    static func series(_ id: String,
                       cat: String = "c",
                       rating: String? = nil,
                       name: String? = nil) -> BlankTV.Series {
        BlankTV.Series(id: id, name: name ?? "series-\(id)",
               coverURL: nil, backdropURL: nil,
               year: nil, rating: rating, genre: nil, plot: nil,
               cast: nil, director: nil,
               categoryID: cat, seasons: [])
    }

    static func channel(_ id: String,
                        group: String = "g",
                        name: String? = nil,
                        directURL: String? = nil) -> BlankTV.Channel {
        BlankTV.Channel(id: id, name: name ?? "channel-\(id)",
                logoURL: nil, groupTitle: group,
                epgChannelID: nil, directURL: directURL)
    }

    static func episode(_ id: String,
                        season: Int = 1,
                        number: Int = 1,
                        ext: String = "mkv",
                        directURL: String? = nil) -> BlankTV.Episode {
        BlankTV.Episode(id: id, title: "episode-\(id)",
                episodeNumber: number, seasonNumber: season,
                containerExtension: ext,
                posterURL: nil, plot: nil, duration: nil,
                directURL: directURL)
    }

    /// `n` movies in one category, each with a distinct id.
    static func movies(_ n: Int, cat: String, rating: String? = nil) -> [BlankTV.Movie] {
        (0..<n).map { movie("\(cat)-\($0)", cat: cat, rating: rating) }
    }

    /// `n` series in one category, each with a distinct id.
    static func seriesList(_ n: Int, cat: String, rating: String? = nil) -> [BlankTV.Series] {
        (0..<n).map { series("\(cat)-\($0)", cat: cat, rating: rating) }
    }
}
