// ============================================================
// BLANK TV — RailEngine.swift
// Smart Home Rail Engine — turns the user's own Xtream/M3U
// categories into a curated, streaming-service-style home feed
// (network rails + genre rails), with NO external metadata API.
// ============================================================

import SwiftUI

// A single themed home rail: a titled horizontal row of movies OR series,
// derived from ONE provider category.
struct HomeRail: Identifiable {
    enum Kind {
        case movie([Movie])
        case series([Series])
    }
    let id: String            // stable: "m_<catID>" / "s_<catID>"
    let title: String         // cleaned, human display title
    let networkTag: String?   // canonical brand chip (e.g. "NETFLIX"), nil = plain genre/other
    let kind: Kind

    var count: Int {
        switch kind {
        case .movie(let a):  return a.count
        case .series(let a): return a.count
        }
    }
}

// The curation engine. Pure, deterministic, testable — no side effects.
enum RailEngine {

    /// A category must have at least this many items to earn its own rail
    /// (avoids a home full of 1–2 item "categories").
    static let minItems = 4
    /// Cap the rail count for performance + focus (matches the ~14–18 rails a
    /// premium streaming home shows).
    static let maxRails = 16
    /// How many items to keep per rail (horizontal scroll — no need for more).
    static let perRail = 20

    // Known streaming networks → canonical chip label.
    // Matched case-insensitively as a substring of the (lowercased) category name.
    // Array ORDER = display priority (Netflix first, …).
    private static let networks: [(keys: [String], label: String)] = [
        (["netflix", "نتفلكس", "نتفليكس"],                 "NETFLIX"),
        (["shahid", "شاهد"],                               "SHAHID"),
        (["osn"],                                          "OSN+"),
        (["disney", "ديزني"],                              "DISNEY+"),
        (["hbo", "max "],                                  "HBO MAX"),
        (["amazon", "prime", "برايم", "امازون", "أمازون"], "PRIME"),
        (["apple tv", "apple+", "appletv", "ابل", "آبل"],  "APPLE TV+"),
        (["hulu"],                                         "HULU"),
        (["bein", "بي ان", "بين سبورت"],                   "beIN"),
        (["starz", "ستارز"],                               "STARZ"),
        (["paramount"],                                    "PARAMOUNT+"),
        (["peacock"],                                      "PEACOCK"),
        (["watch it", "watchit", "واتش"],                  "WATCH IT")
    ]

    // Genre keywords → priority weight (lower = earlier). Existence is still
    // per-category; this only ORDERS recognized genres above generic folders.
    private static let genres: [(keys: [String], weight: Int)] = [
        (["ramadan", "رمضان"],                             20),  // seasonal — surface high
        (["anime", "أنمي", "انمي"],                        30),
        (["action", "أكشن", "اكشن"],                       31),
        (["adventure", "مغامرة"],                          32),
        (["sci-fi", "sci fi", "science", "خيال علمي"],     33),
        (["fantasy", "فانتازيا", "فانتازي"],               34),
        (["crime", "جريمة", "جرائم"],                      35),
        (["thriller", "إثارة", "اثارة"],                   36),
        (["horror", "رعب"],                                37),
        (["comedy", "كوميد"],                              38),
        (["drama", "دراما"],                               39),
        (["romance", "رومانس", "رومانسي"],                 40),
        (["documentary", "وثائق"],                         41),
        (["kids", "أطفال", "اطفال", "كرتون", "cartoon"],   42),
        (["arabic", "عربي", "عربية"],                      43),
        (["turkish", "تركي", "تركية"],                     44),
        (["indian", "hindi", "هندي", "بوليوود", "bollywood"], 45),
        (["korean", "كوري", "كورية"],                      46)
    ]

    private static let genericScore = 100

    // Noise tokens stripped from a category name to get a clean rail title.
    private static let noiseTokens: Set<String> = [
        "4k", "8k", "uhd", "fhd", "hd", "sd", "vip", "hevc", "h265", "h264", "raw", "new",
        "ar", "en", "fr", "us", "uk", "tr", "in", "sa", "eg", "ksa", "uae",
        "|", "-", "•", "·", ":", "—", "+", "()", "*"
    ]

    /// Build the curated home rails from movies/series + their categories.
    /// Deterministic: same input → same ordered output.
    static func build(movies: [Movie], movieCats: [Category],
                      series: [Series], seriesCats: [Category]) -> [HomeRail] {
        let mByCat = Dictionary(grouping: movies, by: { $0.categoryID })
        let sByCat = Dictionary(grouping: series, by: { $0.categoryID })

        // (rail, priorityScore, itemCount) so we can sort by curation priority
        // then by size (bigger folders first within the same priority).
        var scored: [(rail: HomeRail, score: Int, count: Int)] = []

        for cat in movieCats {
            guard let items = mByCat[cat.id], items.count >= minItems else { continue }
            let c = classify(cat.name)
            let ranked = items.sorted { $0.ratingDouble > $1.ratingDouble }
            let rail = HomeRail(id: "m_\(cat.id)", title: c.title,
                                networkTag: c.tag, kind: .movie(Array(ranked.prefix(perRail))))
            scored.append((rail, c.score, items.count))
        }
        for cat in seriesCats {
            guard let items = sByCat[cat.id], items.count >= minItems else { continue }
            let c = classify(cat.name)
            let ranked = items.sorted { s8kRating($0.rating) > s8kRating($1.rating) }
            let rail = HomeRail(id: "s_\(cat.id)", title: c.title,
                                networkTag: c.tag, kind: .series(Array(ranked.prefix(perRail))))
            scored.append((rail, c.score, items.count))
        }

        let sorted = scored.sorted { a, b in
            a.score != b.score ? a.score < b.score : a.count > b.count
        }
        return Array(sorted.prefix(maxRails).map { $0.rail })
    }

    // Classify a raw category name into (clean title, network chip, priority score).
    private static func classify(_ raw: String) -> (title: String, tag: String?, score: Int) {
        let lower = raw.lowercased()
        for (i, net) in networks.enumerated() where net.keys.contains(where: { lower.contains($0) }) {
            return (cleanTitle(raw), net.label, i)                 // 0 ..< networks.count
        }
        for g in genres where g.keys.contains(where: { lower.contains($0) }) {
            return (cleanTitle(raw), nil, g.weight)
        }
        return (cleanTitle(raw), nil, genericScore)
    }

    // Turn "AR | NETFLIX MOVIES 4K" → "NETFLIX MOVIES", "OSN+ مسلسلات" stays.
    // Strips separators, language/country codes and quality noise; keeps the
    // meaningful words so a network's movie- and series-rail stay distinct.
    private static func cleanTitle(_ raw: String) -> String {
        let seps = CharacterSet(charactersIn: "|•·—:/\\")
        let tokens = raw.components(separatedBy: seps)
            .joined(separator: " ")
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !noiseTokens.contains($0.lowercased()) }
        let joined = tokens.joined(separator: " ")
        return joined.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : joined
    }
}

// MARK: - Regional classifier (quick "Arabic / European / American" ordering)
// Classifies a provider category by REGION from keyword rules — same offline,
// metadata-free approach as RailEngine — so the unified reorder page can offer a
// one-tap "put my region first" default. The user can still drag to fine-tune.
enum ContentRegion: String, CaseIterable, Identifiable {
    case arabic, european, american
    var id: String { rawValue }
    var title: String {
        switch self {
        case .arabic:   return L("region.arabic")
        case .european: return L("region.european")
        case .american: return L("region.american")
        }
    }
    var icon: String {
        switch self {
        case .arabic:   return "moon.stars.fill"
        case .european: return "globe.europe.africa.fill"
        case .american: return "globe.americas.fill"
        }
    }
}

enum RegionClassifier {
    private static let arabic: [String] = [
        "عرب","arab","mbc","بين","bein","osn","شاهد","قنوات","سعود","ksa","saudi","مصر","egypt",
        "uae","امارات","emirat","kuwait","الكويت","قطر","qatar","دبي","dubai","اردن","jordan",
        "lebanon","لبنان","syria","سوري","iraq","عراق","maghreb","مغرب","tunis","تونس","algeri",
        "جزائر","yemen","يمن","oman","عمان","bahrain","بحرين","sudan","سودان","libya","ليبيا",
        "palestin","فلسطين","islam","اسلام","قران","quran","نايل","nile","روتانا","rotana","abudhabi","ابوظبي"]
    private static let european: [String] = [
        "uk","british","britain","bbc","itv","sky","germ","deutsch","france","french","canal",
        "ital","spain","span","españ","dutch","holland","portug","poland","polski","turk","türk",
        "greek","yunan","roman","serbia","croat","sweden","norway","denmark","finland","russia",
        "ukrain","euro","albania","الماني","فرنس","ايطال","اسبان","برتغال","يونان","روسي","تركي","اوروب"]
    private static let american: [String] = [
        "usa","united states","america","hbo","espn","nbc"," abc","cbs","fox","disney","hulu",
        "peacock","paramount","latino","latin","brazil","brasil","mexic","argentin","colombia",
        "chile","peru","canada","canadian","امريك","لاتين","برازيل","مكسيك"]

    static func region(for name: String) -> ContentRegion? {
        let l = " " + name.lowercased() + " "
        if arabic.contains(where: { l.contains($0) })   { return .arabic }
        if american.contains(where: { l.contains($0) }) { return .american }
        if european.contains(where: { l.contains($0) }) { return .european }
        return nil
    }

    /// Category IDs for the chosen region, in their original order — the reorder
    /// page floats these to the top (the rest stay in provider-default order).
    static func presetOrder(_ cats: [Category], primary: ContentRegion) -> [String] {
        cats.filter { region(for: $0.name) == primary }.map { $0.id }
    }
}
