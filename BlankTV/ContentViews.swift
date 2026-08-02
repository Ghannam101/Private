// BLANK TV · ContentViews.swift
//
// The catalogue surface: the three browse pages, the two detail covers, the
// search screen, and the parts they share.
//
// Laid out by ROLE, not by content type — one band for the shared controls
// rather than a copy inside each vertical:
//
//   1  folding + windowing     the two rules every list in here obeys
//   2  section models          live · movies · series
//   3  shared browse controls  header bar, field, tiles, sidebar, sheets
//   4  poster walls            movie / series / watch-history tiles
//   5  live surfaces           lineup rows, the inline preview, the guide
//   6  the three pages         live · movies · series
//   7  folder ordering         the editor and the settings page around it
//   8  detail covers           movie · series
//   9  search                  model + screen
//  10  chip wrapping           the Layout that wraps recent terms

import SwiftUI
import UIKit

// MARK: - 1 · Folding and windowing

/// The one comparison rule every catalogue search in this file obeys.
enum CatalogText {
    /// Flatten a title to the form searches are actually done against. Applied once
    /// per name at load and once per query, never once per name per comparison —
    /// `localizedCaseInsensitiveContains` reaches into ICU and allocates on every
    /// call, and across thirty to fifty thousand titles that single call was the most
    /// expensive thing a browse page did while the user was typing.
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                  locale: nil)
    }

    /// Narrow a list that is already short — one folder, one sheet — by the same rule
    /// the catalogue-wide index uses, so a title that the main search finds can never
    /// be one a folder search misses.
    static func narrow<T>(_ items: [T], matching query: String,
                          by name: (T) -> String) -> [T] {
        let q = fold(query)
        // Test the FOLDED needle, not the raw one: a query made only of combining
        // marks folds away to nothing, and nothing has to mean "do not filter".
        guard !q.isEmpty else { return items }
        return items.filter { fold(name($0)).contains(q) }
    }
}

/// One place for the windowing constants, so every list grows the same way.
enum CatalogWindow {
    /// Enough to fill any screen in the matrix plus a comfortable scroll buffer.
    static let firstBatch = 120
    /// Roughly a screenful and a half per extension — big enough that the sentinel
    /// never fires twice in one flick, small enough that it stays cheap.
    static let growth = 180
}

/// Clears all cached content (called on logout / session change).
@MainActor
enum ContentCache {
    static func reset() {
        LiveTVVM.shared.reset()
        MoviesVM.shared.reset()
        SeriesVM.shared.reset()
        HomeVM.shared.reset()
    }
}

// MARK: - 2 · Section models
//
// The three section models — live, movies, series — are built to one anatomy, set
// down here once rather than three times over:
//
//   · a grouped index rebuilt after each load, so `folders` / `list(in:)` never
//     rescan the whole catalogue from inside a view body;
//   · a folded name index plus a one-entry memo behind `searchResults`, which IS
//     read from a body — folding once at load turns an ICU comparison per title per
//     keystroke into a plain substring test, and makes Arabic matching ignore
//     diacritics into the bargain;
//   · editorial rows (the hero and the top ten) computed once inside `load`;
//   · a silent exit when the load was cancelled.
//
// THE COUNT CHECK COMES BEFORE THE MEMO. Movies and Series build their name index
// off the first-paint path, so it can still be empty at the instant the user types.
// Reading the memo first meant a result computed against an empty catalogue was
// handed back for that same query once the real catalogue landed — and because the
// rebuild publishes nothing, no re-render ever arrived to correct it. The page sat
// on "no results" for a query that matches until another character was typed. So
// the count is compared first, and rebuilding clears the memo, which is exactly
// what that case needs. Live deliberately has no such check: its index is built
// synchronously inside `load`, so it can never be behind.
//
// A CANCELLED LOAD MUST SAY NOTHING. Switching playlist or pulling to refresh
// remounts the tab and cancels the load in flight — but a cancelled task still
// resumes, and it would write its URLError(.cancelled) into `error` AFTER the
// replacement load had cleared it. Every page here reads `error` ahead of content,
// so it would show a failure over data that arrived perfectly well. That is what
// the `Task.isCancelled` guard in front of each `error` assignment is for.

// MARK: Live channels
@MainActor
final class LiveTVVM: ObservableObject {
    static let shared = LiveTVVM()
    @Published var categories: [Category]  = [.all]
    @Published var channels:   [Channel]   = []
    @Published var search:     String      = ""
    @Published var isLoading:  Bool        = true
    @Published var error:      AppError?   = nil
    private var loaded = false

    // Precomputed once after load: channels grouped by their category NAME, and
    // the list of non-empty folders. Avoids the O(categories × channels) rescan
    // that the `folders`/`list(in:)` helpers used to run on every render.
    private(set) var grouped: [String: [Channel]] = [:]
    private(set) var folderList: [Category] = []
    private func rebuildGroups() {
        grouped = Dictionary(grouping: channels, by: { $0.groupTitle })
        folderList = categories.filter { $0.id != "all" && !(grouped[$0.name]?.isEmpty ?? true) }
    }

    // Folded name index + one-entry memo — the shared anatomy, described above.
    private var foldedNames: [String] = []
    private var lastQuery: String? = nil
    private var lastResults: [Channel] = []
    private func rebuildSearchIndex() {
        foldedNames = channels.map { CatalogText.fold($0.name) }
        lastQuery = nil; lastResults = []
    }
    /// Channels whose name matches `search`. Memoised; safe to call from a body.
    /// (Mutating plain stored properties of a class from a getter fires no
    /// objectWillChange, so this cannot re-enter the view update.)
    fileprivate func searchMatches() -> [Channel] {
        let q = CatalogText.fold(search)
        if lastQuery == q { return lastResults }
        // zip truncates rather than trapping if the index is ever out of step.
        let r: [Channel] = q.isEmpty ? [] : zip(foldedNames, channels).compactMap { $0.0.contains(q) ? $0.1 : nil }
        lastQuery = q; lastResults = r
        return r
    }

    func load(force: Bool = false) async {
        if loaded && !force { return }   // load once — keeps tab switches instant
        isLoading = true; error = nil
        do {
            async let cats  = ContentService.liveCategories()
            async let chans = ContentService.liveStreams()
            let (c, ch) = try await (cats, chans)
            categories = [.all] + c
            channels   = ch
            rebuildGroups(); rebuildSearchIndex()
            loaded = true
        // Silent on cancellation — see the note above these models.
        } catch let e as AppError { guard !Task.isCancelled else { return }; error = e }
          catch { guard !Task.isCancelled else { return }; self.error = .network(error) }
        isLoading = false
    }

    func reset() {
        loaded = false; channels = []; categories = [.all]; isLoading = true; error = nil
        grouped = [:]; folderList = []; rebuildSearchIndex()
    }

    // What the pages actually read. `folders` runs the user's saved arrangement over
    // the non-empty folders; the key is a persisted UserDefaults string.
    var folders: [Category] { Store.shared.orderedCategories(folderList, "live") }
    func list(in cat: Category) -> [Channel] {
        cat.id == "all" ? channels : (grouped[cat.name] ?? [])
    }
    var searchResults: [Channel] { searchMatches() }
}

// MARK: Movies

@MainActor
final class MoviesVM: ObservableObject {
    static let shared = MoviesVM()
    @Published var categories: [Category] = [.all]
    @Published var movies:     [Movie]    = []
    @Published var search:     String     = ""
    @Published var isLoading:  Bool       = true
    @Published var error:      AppError?  = nil
    // Editorial feed (Home-style, movies-only) — built once after load.
    @Published var heroItems:  [HomeVM.HeroItem] = []   // swipeable hero: newest movies
    @Published var topRanked:  [Movie]    = []          // Top-10 by rating
    private var loaded = false

    // Precomputed once after load: movies grouped by categoryID + non-empty folders.
    private(set) var grouped: [String: [Movie]] = [:]
    private(set) var folderList: [Category] = []
    private func rebuildGroups() {
        grouped = Dictionary(grouping: movies, by: { $0.categoryID })
        folderList = categories.filter { $0.id != "all" && !(grouped[$0.id]?.isEmpty ?? true) }
    }

    // Folded search index + one-entry memo — see LiveTVVM.
    private var foldedNames: [String] = []
    private var lastQuery: String? = nil
    private var lastResults: [Movie] = []
    private func rebuildSearchIndex() {
        foldedNames = movies.map { CatalogText.fold($0.name) }
        lastQuery = nil; lastResults = []
    }
    fileprivate func searchMatches() -> [Movie] {
        let q = CatalogText.fold(search)
        // Count check FIRST, memo second — the order is load-bearing; see the note
        // above these models.
        if foldedNames.count != movies.count { rebuildSearchIndex() }
        if lastQuery == q { return lastResults }
        let r: [Movie] = q.isEmpty ? [] : zip(foldedNames, movies).compactMap { $0.0.contains(q) ? $0.1 : nil }
        lastQuery = q; lastResults = r
        return r
    }

    // Editorial rows: Top-10 by rating (Movie has a ratingDouble helper) + a
    // newest-movies hero.
    private func rebuildEditorial() {
        // SORT INDICES, NOT ELEMENTS — the same fix HomeVM.rebuildHero already carries
        // (HomeView.swift:75-98). These two were left behind.
        //
        // The old comparators parsed a String into a Double/Int on EVERY comparison —
        // twice per compare, over ~n·log n compares — and moved a 424-byte struct with
        // a dozen refcounted String fields on every swap, twice over. On a large line
        // that is hundreds of milliseconds of BLOCKED MAIN THREAD plus a multi-copy
        // transient spike, to produce ten rows and a six-item hero.
        //
        // Now each key is parsed once, only Ints move during the sort, and only the few
        // dozen we might keep are ever materialised — the headroom absorbs duplicate
        // ids that s8kUniqueByID then removes.
        let rate = movies.map(\.ratingDouble)
        let byRate: [Int] = movies.indices.sorted { rate[$0] > rate[$1] }
        topRanked = Array(s8kUniqueByID(byRate.prefix(40).map { movies[$0] }, { $0.id }).prefix(10))

        let ids = movies.map { Int($0.id) ?? 0 }
        let byID: [Int] = movies.indices.sorted { ids[$0] > ids[$1] }
        let newest = s8kUniqueByID(byID.prefix(24).map { movies[$0] }, { $0.id })
        heroItems = newest.prefix(6).map { HomeVM.HeroItem(kind: .movie($0)) }
        S8KImageCache.shared.prefetch(heroItems.compactMap { $0.backdropURL }, maxPixel: 1200)
    }

    func load(force: Bool = false) async {
        if loaded && !force { return }
        isLoading = true; error = nil
        do {
            async let cats = ContentService.vodCategories()
            async let movs = ContentService.movies()
            let (c, m) = try await (cats, movs)
            categories = [.all] + c; movies = m
            rebuildGroups(); rebuildEditorial(); loaded = true
            // Off the first-paint path, in its own main-actor hop. Folding every title
            // is the most expensive per-row work here and the grid never reads it —
            // only the search box does, and `searchMatches` builds it on demand if the
            // user beats us to it. Doing it in THIS hop would hold the very frame that
            // `isLoading = false` below is meant to release.
            Task { @MainActor [weak self] in self?.rebuildSearchIndex() }
        // Silent on cancellation — see the note above these models.
        } catch let e as AppError { guard !Task.isCancelled else { return }; error = e }
          catch { guard !Task.isCancelled else { return }; self.error = .network(error) }
        isLoading = false
    }

    func reset() {
        loaded = false; movies = []; categories = [.all]; isLoading = true; error = nil
        grouped = [:]; folderList = []; heroItems = []; topRanked = []; rebuildSearchIndex()
    }

    /// Categories that actually contain movies (folders), in the user's own order.
    var folders: [Category] { Store.shared.orderedCategories(folderList, "movies") }
    func list(in cat: Category) -> [Movie] {
        cat.id == "all" ? movies : (grouped[cat.id] ?? [])
    }
    var searchResults: [Movie] { searchMatches() }
}

// MARK: Series

@MainActor
final class SeriesVM: ObservableObject {
    static let shared = SeriesVM()
    @Published var categories: [Category] = [.all]
    @Published var series:     [Series]   = []
    @Published var search:     String     = ""
    @Published var isLoading:  Bool       = true
    @Published var error:      AppError?  = nil
    // Editorial feed (Home-style, series-only) — built once after load.
    @Published var heroItems:  [HomeVM.HeroItem] = []   // swipeable hero: newest series
    @Published var topRanked:  [Series]   = []          // Top-10 by rating
    private var loaded = false

    // Precomputed once after load: series grouped by categoryID + non-empty folders.
    private(set) var grouped: [String: [Series]] = [:]
    private(set) var folderList: [Category] = []
    private func rebuildGroups() {
        grouped = Dictionary(grouping: series, by: { $0.categoryID })
        folderList = categories.filter { $0.id != "all" && !(grouped[$0.id]?.isEmpty ?? true) }
    }

    // Folded search index + one-entry memo — see LiveTVVM.
    private var foldedNames: [String] = []
    private var lastQuery: String? = nil
    private var lastResults: [Series] = []
    private func rebuildSearchIndex() {
        foldedNames = series.map { CatalogText.fold($0.name) }
        lastQuery = nil; lastResults = []
    }
    fileprivate func searchMatches() -> [Series] {
        let q = CatalogText.fold(search)
        // Count check FIRST, memo second — the order is load-bearing; see the note
        // above these models.
        if foldedNames.count != series.count { rebuildSearchIndex() }
        if lastQuery == q { return lastResults }
        let r: [Series] = q.isEmpty ? [] : zip(foldedNames, series).compactMap { $0.0.contains(q) ? $0.1 : nil }
        lastQuery = q; lastResults = r
        return r
    }

    // Build the editorial rows (Top-10 by rating + a newest-series hero). `Series`
    // carries its rating as a String and has no `ratingDouble` of its own, so the
    // key comes from the shared `s8kRating` parser.
    private func rebuildEditorial() {
        // Indices, not elements — see the note in MoviesVM.rebuildEditorial.
        let rate = series.map { s8kRating($0.rating) }
        let byRate: [Int] = series.indices.sorted { rate[$0] > rate[$1] }
        topRanked = Array(s8kUniqueByID(byRate.prefix(40).map { series[$0] }, { $0.id }).prefix(10))

        let ids = series.map { Int($0.id) ?? 0 }
        let byID: [Int] = series.indices.sorted { ids[$0] > ids[$1] }
        let newest = s8kUniqueByID(byID.prefix(24).map { series[$0] }, { $0.id })
        heroItems = newest.prefix(6).map { HomeVM.HeroItem(kind: .series($0)) }
        S8KImageCache.shared.prefetch(heroItems.compactMap { $0.backdropURL }, maxPixel: 1200)
    }

    func load(force: Bool = false) async {
        if loaded && !force { return }
        isLoading = true; error = nil
        do {
            async let cats = ContentService.seriesCategories()
            async let sers = ContentService.series()
            let (c, s) = try await (cats, sers)
            categories = [.all] + c; series = s
            rebuildGroups(); rebuildEditorial(); loaded = true
            // See MoviesVM.load — the index is off the first-paint path.
            Task { @MainActor [weak self] in self?.rebuildSearchIndex() }
        // Silent on cancellation — see the note above these models.
        } catch let e as AppError { guard !Task.isCancelled else { return }; error = e }
          catch { guard !Task.isCancelled else { return }; self.error = .network(error) }
        isLoading = false
    }

    func reset() {
        loaded = false; series = []; categories = [.all]; isLoading = true; error = nil
        grouped = [:]; folderList = []; heroItems = []; topRanked = []; rebuildSearchIndex()
    }

    /// Categories that actually contain series (folders), in the user's own order.
    var folders: [Category] { Store.shared.orderedCategories(folderList, "series") }
    func list(in cat: Category) -> [Series] {
        cat.id == "all" ? series : (grouped[cat.id] ?? [])
    }
    var searchResults: [Series] { searchMatches() }
}

// MARK: - 3 · Controls the browse pages share

// MARK: What a folder screen opens with
// A heavy title over a short accent rule, the item count beneath it, and one way
// back. It once carried an optional trailing icon and an optional reorder pill as
// well; no caller ever supplied either, so both branches were dead and both are
// gone. `onBack` stays optional because the top padding reads it.
struct FolderScreenHeader: View {
    let title: String
    var subtitle: String
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                backButton(action: onBack)
            }
            VStack(alignment: .trailing, spacing: 6) {
                Text(title).font(S8KFont.title1.weight(.black)).foregroundColor(.s8kTextPrimary).lineLimit(1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(S8KGradient.goldFlat)
                    .frame(width: 30, height: 3)
                    .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 4)
                Text(subtitle).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, S8KSpace.xl)
        .padding(.top, onBack == nil ? 60 : 24).padding(.bottom, S8KSpace.lg)
    }

    // A rounded square, not a circle.
    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold)).foregroundColor(.s8kGoldMid)
                .frame(width: 38, height: 38)
                .background(Color.s8kSurface)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
                // 38 → 44pt, drawn identically. Inside the label and after the clip —
                // clipShape clips hit testing too. This is the back button on every
                // folder screen, where the swipe-to-pop gesture is also disabled.
                .s8kMinTouch(3)
        }
        .buttonStyle(S8KButtonStyle())
        // Unchanged from what shipped: it announces the symbol name. Wrong, and
        // deliberately left wrong here — correcting it is a change to what the user
        // hears, which is not what this pass is for. Logged as a follow-up.
        .accessibilityLabel("chevron.right")
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(.s8kTextDisabled)
            TextField("", text: $text,
                      prompt: Text(placeholder).foregroundColor(Color.s8kTextDisabled))
                .font(S8KFont.callout).foregroundColor(.s8kTextPrimary)
                // Scoped to the field, and decided by the ACTIVE LANGUAGE rather than
                // set once: typed Latin under a right-to-left direction right-aligns
                // and moves the caret the wrong way as you type.
                .environment(\.layoutDirection, LocalizationManager.current.isRTL ? .rightToLeft : .leftToRight)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.s8kTextDisabled)
                        // ~17pt glyph. 14 vertically fills the 46pt row (the row's own
                        // clipShape would cut anything past it); 5 sideways is half the
                        // 10pt gap to the text field, so it cannot swallow the tap that
                        // focuses the field.
                        .s8kMinTouch(h: 5, v: 14)
                }
                    .accessibilityLabel(L("a11y.clear_text"))
            }
        }
        .padding(.horizontal, S8KSpace.lg).frame(height: 46)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
            .strokeBorder(Color.s8kBorder, lineWidth: 1))
    }
}

struct FolderTile: View {
    let name: String
    let count: Int
    var icon: String = "folder.fill"
    var color: Color = .s8kGoldMid

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14)).frame(width: 46, height: 46)
                Image(systemName: icon).font(.system(size: 19)).foregroundColor(color)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                Text("\(count) \(L("unit.item"))").font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Image(systemName: "chevron.left").font(.system(size: 13)).foregroundColor(.s8kTextDisabled)
        }
        .padding(.horizontal, S8KSpace.lg).padding(.vertical, 13)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
            .strokeBorder(Color.s8kBorder, lineWidth: 1))
    }
}

// MARK: Jump straight to a folder
struct FolderPickerSheet: View {
    let title: String
    let categories: [Category]
    let count: (Category) -> Int
    let onPick: (Category) -> Void
    @State private var search = ""
    @Environment(\.dismiss) var dismiss

    private var shown: [Category] {
        search.isEmpty ? categories
                       : CatalogText.narrow(categories, matching: search, by: { $0.name })
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 0) {
                    SearchField(text: $search, placeholder: L("search.cat"))
                        .padding(.horizontal, S8KSpace.xl).padding(.top, 16).padding(.bottom, S8KSpace.md)
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(shown) { cat in
                                Button(action: { onPick(cat); dismiss() }) {
                                    FolderTile(name: cat.name, count: count(cat))
                                }
                                .buttonStyle(S8KButtonStyle())
                            }
                            if shown.isEmpty {
                                EmptyState(icon: "folder.badge.questionmark",
                                           title: L("cats.empty.title"), subtitle: L("cats.empty.sub")).padding(.top, 40)
                            }
                        }
                        .padding(.horizontal, S8KSpace.xl).padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.close")) { dismiss() }.foregroundColor(.s8kGoldMid) } }
        }
        .presentationDetents([.large])
    }
}

// MARK: The folder list that anchors the iPad split
struct FolderSidebar: View {
    @Environment(\.s8kMetrics) private var metrics
    let title: String
    let folders: [Category]
    @Binding var selected: Category?     // nil = All, Category.favorites = Favorites
    var count: (Category) -> Int
    let allCount: Int
    /// When non-nil, a "Favorites" row is shown above "All" (iPad parity with the
    /// iPhone Favorites tab). Selecting it sets `selected = Category.favorites`.
    var favoritesCount: Int? = nil
    var onReorder: (() -> Void)? = nil

    private var isFavoritesSelected: Bool { selected?.id == Category.favorites.id }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 8) {
                if let onReorder {
                    Button(action: onReorder) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.s8kGoldMid)
                            .frame(width: 34, height: 34)
                            .background(Color.s8kElevated).clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.s8kBorder, lineWidth: 1))
                            // 34 → 44pt. Nothing tappable is within 5pt: a Spacer to one
                            // side, the sidebar's 16pt padding to the other.
                            .s8kMinTouch(5)
                    }
                    .buttonStyle(S8KButtonStyle())
                    .accessibilityLabel(L("a11y.reorder"))
                }
                Spacer()
                Text(title)
                    .font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
            }
            .padding(.horizontal, S8KSpace.lg).padding(.top, max(50, metrics.safeTop + S8KSpace.sm)).padding(.bottom, S8KSpace.md)
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    if let favCount = favoritesCount {
                        row(L("ctab.favorites"), favCount, isFavoritesSelected,
                            icon: "heart.fill") { selected = Category.favorites }
                    }
                    row(L("ctab.all"), allCount, selected == nil) { selected = nil }
                    ForEach(folders) { cat in
                        row(cat.name, count(cat), selected?.id == cat.id) { selected = cat }
                    }
                }
                .padding(.horizontal, S8KSpace.md).padding(.bottom, metrics.bottomClearance)  // clear the floating AppTabBar
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color.s8kSurface.opacity(0.4))
    }

    private func row(_ label: String, _ n: Int, _ isOn: Bool, icon: String? = nil,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("\(n)").font(S8KFont.caption2)
                    .foregroundColor(isOn ? .black.opacity(0.7) : .s8kTextTertiary)
                Spacer()
                Text(label).font(S8KFont.subhead.weight(isOn ? .bold : .regular))
                    .foregroundColor(isOn ? .black : .s8kTextPrimary)
                    .lineLimit(1).multilineTextAlignment(.trailing)
                if let icon {
                    Image(systemName: icon).font(.system(size: 12))
                        .foregroundColor(isOn ? .black : .s8kRed)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(isOn ? AnyShapeStyle(S8KGradient.goldFlat) : AnyShapeStyle(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: The four ways to narrow a browse page
enum BrowseFilter: String, CaseIterable, Identifiable {
    case all = "الكل", favorites = "المفضلة", newest = "الأجدد", history = "السجل"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("ctab.all")
        case .favorites: return L("ctab.favorites")
        case .newest: return L("ctab.newest")
        case .history: return L("ctab.history")
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart.fill"
        case .newest: return "sparkles"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

// MARK: The row of working controls every browse page carries
// Folders on one side, reorder on the other, the filter menu between them. All
// three browse pages held their own byte-identical copy of this; only the folder
// button's wording and the top padding ever differed, so both are parameters.
//
// It is a NORMAL ROW OF THE FEED wherever it is used, never an overlay laid over
// the scroll view — see the note in `MoviesView.browser`. Each page keeps a
// one-expression `toolRow` wrapper so its own call sites, and therefore its own
// layout, are untouched.
private struct BrowseToolRow: View {
    let foldersLabel: String
    @Binding var filter: BrowseFilter
    var topPad: CGFloat = 14
    var onFolders: () -> Void
    var onReorder: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            circleButton("line.3.horizontal.decrease.circle", foldersLabel, onFolders)
            filterMenu
            Spacer(minLength: 0)
            circleButton("arrow.up.arrow.down", L("reorder.button"), onReorder)
        }
        .padding(.horizontal, S8KSpace.lg)
        .padding(.top, topPad)
        .padding(.bottom, 4)
    }

    private var filterMenu: some View {
        Menu {
            Picker("", selection: $filter) {
                ForEach(BrowseFilter.allCases) { t in Label(t.title, systemImage: t.icon).tag(t) }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: filter.icon).font(.system(size: 13, weight: .bold))
                Text(filter.title).font(S8KFont.subhead.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(filter == .all ? .s8kTextSecondary : .s8kBlack)
            .padding(.horizontal, 14).frame(height: 42)
            .background(Capsule(style: .continuous)
                .fill(filter == .all ? AnyShapeStyle(Color.white.opacity(0.07))
                                     : AnyShapeStyle(Color.s8kGoldHigh)))
            .overlay(Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(filter == .all ? 0.12 : 0), lineWidth: 1)
                .allowsHitTesting(false))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func circleButton(_ icon: String, _ label: String,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold)).foregroundColor(.s8kGoldHigh)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false))
                .contentShape(Circle())
        }
        .buttonStyle(S8KButtonStyle())
        .accessibilityLabel(label)
    }
}

// MARK: One folder's shelf — a header that opens it, and a strip of tiles
struct CategoryShelf<Cell: View>: View {
    let category: Category
    var count: Int = 0
    var locked: Bool = false   // in the parental lock list → show a lock badge
    var gated:  Bool = false   // locked AND not unlocked this session → hide the
                               // content previews and require a PIN to enter
    @ViewBuilder let cells: () -> Cell

    var body: some View {
        VStack(spacing: 11) {
            NavigationLink(value: category) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(S8KGradient.goldFlat)
                        .frame(width: 3, height: 18)
                    Text(category.name).font(S8KFont.title3).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    if locked {
                        Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold))
                            .foregroundColor(.s8kGoldMid)
                    }
                    if count > 0 {
                        Text("\(count)")
                            .font(S8KFont.caption1.weight(.bold))
                            .foregroundColor(.s8kGoldMid)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.s8kGoldMid.opacity(0.12)).clipShape(Capsule())
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Text(gated ? L("gate.enter_pin") : L("common.all")).font(S8KFont.caption1.weight(.semibold))
                        Image(systemName: gated ? "lock.fill" : "chevron.left").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.s8kGoldMid)
                }
                .padding(.horizontal, S8KSpace.xl)
                // The row has a Spacer in the middle, and a Spacer draws nothing — so
                // without this the whole centre of every category header was dead and
                // only the title text and the trailing chevron were tappable. This is
                // the main entry point to every category on four different pages.
                .contentShape(Rectangle())
            }
            .buttonStyle(S8KButtonStyle())

            // Hide the preview thumbnails for a gated folder so locked content
            // is never exposed; tapping the row opens the PIN gate instead.
            if !gated {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) { cells() }
                        .padding(.horizontal, S8KSpace.xl)
                }
            }
        }
        .padding(.bottom, S8KSpace.xxl)
    }
}

// MARK: One screen for one folder
// Movies, series and channels each had their own copy of this screen, differing in
// three places: the noun under the title, what fills the body, and what a tap does.
// Those three are arguments now. `narrow` runs over the folder's own items, so the
// field filters what is on screen rather than re-querying the catalogue.
private struct FolderScreen<Item, Rows: View>: View {
    @Environment(\.s8kMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss
    let title: String
    let unit: String
    let items: [Item]
    let name: (Item) -> String
    @ViewBuilder let rows: ([Item]) -> Rows
    @State private var query = ""

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    FolderScreenHeader(title: title, subtitle: "\(items.count) \(unit)",
                                       onBack: { dismiss() })
                    SearchField(text: $query,
                                placeholder: "\(L("common.search_in")) \(title)…")
                        .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.lg)
                    rows(CatalogText.narrow(items, matching: query, by: name))
                    Color.clear.frame(height: metrics.bottomClearance)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - 4 · Poster walls

struct MovieTile: View {
    let movie: Movie
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    // Fixed-size box drives layout; the poster fills it as a
                    // clipped overlay. Prevents a non-2:3 poster from leaking its
                    // width and overlapping neighbours in the grid.
                    // 2:3, NOT a fixed 150pt: on an iPad the adaptive column is ~172pt
                    // wide, so a 150pt-tall cell rendered a LANDSCAPE band of a portrait
                    // poster (233×150 on an iPad mini). It also made the loaded grid a
                    // different shape from the skeleton, which already uses 2:3.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .overlay { S8KImage(url: movie.posterURL, placeholder: "film") }
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    if let y = movie.year {
                        Text(y).font(S8KFont.caption3.weight(.bold)).foregroundColor(S8KBrand.accentInk)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(S8KGradient.goldFlat)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)).padding(5)
                    }
                }
                Text(movie.name).font(S8KFont.caption2.weight(.bold))
                    .foregroundColor(.s8kTextPrimary).lineLimit(1)
                if let r = movie.rating, let rv = Double(r), rv > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundColor(.s8kGoldHigh)
                        Text(String(format: "%.1f", rv)).font(S8KFont.caption3).foregroundColor(.s8kGoldHigh)
                    }
                }
            }
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: The movie wall
struct MovieWall: View {
    let movies: [Movie]
    var empty: String = L("grid.empty")
    let onSelect: (Movie) -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    // Larger, more immersive posters (fewer per row) — a bolder catalog than the
    // reference's dense postage-stamp grid.
    private var cols: [GridItem] { [GridItem(.adaptive(minimum: hSize == .regular ? 168 : 116), spacing: 14)] }
    /// See CatalogWindow — ForEach walks the whole collection on every invalidation
    /// even inside a LazyVGrid, so a 30k-title catalogue paid for 30k identities on
    /// every favourite toggle and every keystroke.
    @State private var shown = CatalogWindow.firstBatch

    var body: some View {
        Group {
            if movies.isEmpty {
                EmptyState(icon: "film.slash", title: empty, subtitle: L("grid.empty.sub"))
            } else {
                LazyVGrid(columns: cols, spacing: 18) {
                    ForEach(movies.prefix(shown)) { m in MovieTile(movie: m) { onSelect(m) } }
                    // Sentinel: reaching it means the user scrolled past the window.
                    if shown < movies.count {
                        Color.clear.frame(height: 1)
                            .onAppear { shown = min(shown + CatalogWindow.growth, movies.count) }
                    }
                }
                .padding(.horizontal, S8KSpace.lg)
                // Warm the first screenful of posters so the grid paints instantly.
                .onAppear { S8KImageCache.shared.prefetch(movies.prefix(30).compactMap { $0.posterURL }, maxPixel: 800) }
            }
        }
        // Keyed on the head item, not count — see ChannelLineup for why.
        .onChange(of: movies.first?.id) { _, _ in shown = CatalogWindow.firstBatch }
    }
}

struct SeriesTile: View {
    let series: Series
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 6) {
                // 2:3 for the same reason as MovieTile — a fixed height turned a
                // portrait cover into a landscape band on every iPad column width.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay { S8KImage(url: series.coverURL, placeholder: "tv") }
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                Text(series.name).font(S8KFont.caption2.weight(.bold))
                    .foregroundColor(.s8kTextPrimary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let y = series.year {
                    Text(y).font(S8KFont.caption3).foregroundColor(.s8kTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .buttonStyle(S8KButtonStyle())
    }
}

struct SeriesWall: View {
    let series: [Series]
    var empty: String = L("grid.empty")
    let onSelect: (Series) -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var cols: [GridItem] { [GridItem(.adaptive(minimum: hSize == .regular ? 168 : 116), spacing: 14)] }
    /// See CatalogWindow.
    @State private var shown = CatalogWindow.firstBatch

    var body: some View {
        Group {
            if series.isEmpty {
                EmptyState(icon: "tv.slash", title: empty, subtitle: L("grid.empty.sub"))
            } else {
                grid
            }
        }
        // Keyed on the head item, not count — see ChannelLineup for why.
        .onChange(of: series.first?.id) { _, _ in shown = CatalogWindow.firstBatch }
    }

    private var grid: some View {
        LazyVGrid(columns: cols, spacing: 16) {
            ForEach(series.prefix(shown)) { s in
                Button(action: { onSelect(s) }) {
                    VStack(alignment: .trailing, spacing: 6) {
                        // 2:3 like MovieTile — and via a Color.clear box, which
                        // also stops a non-2:3 cover leaking its width and overlapping
                        // its neighbours. Left at a fixed 150 this grid rendered a
                        // landscape band beside a correctly-proportioned Movies grid.
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                            .overlay { S8KImage(url: s.coverURL, placeholder: "tv") }
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                            .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm)
                                .strokeBorder(Color.s8kBorder, lineWidth: 1))
                        Text(s.name).font(S8KFont.caption2.weight(.semibold))
                            .foregroundColor(.s8kTextPrimary).lineLimit(1)
                        if let y = s.year {
                            Text(y).font(S8KFont.caption3).foregroundColor(.s8kTextTertiary)
                        }
                    }
                }
                .buttonStyle(S8KButtonStyle())
            }
            if shown < series.count {
                Color.clear.frame(height: 1)
                    .onAppear { shown = min(shown + CatalogWindow.growth, series.count) }
            }
        }
        .padding(.horizontal, S8KSpace.lg)
        .onAppear { S8KImageCache.shared.prefetch(series.prefix(30).compactMap { $0.coverURL }, maxPixel: 800) }
    }
}

// MARK: Where you left off
struct WatchHistoryTiles: View {
    let items: [WatchHistory]
    var empty: String = L("history.empty.generic")
    let onTap: (WatchHistory) -> Void
    @Environment(\.horizontalSizeClass) private var hSize
    private var cols: [GridItem] { [GridItem(.adaptive(minimum: hSize == .regular ? 168 : 116), spacing: 14)] }

    var body: some View {
        if items.isEmpty {
            EmptyState(icon: "clock.badge.xmark", title: empty, subtitle: L("history.empty.sub"))
        } else {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(items) { h in
                    Button(action: { onTap(h) }) {
                        VStack(alignment: .trailing, spacing: 6) {
                            ZStack(alignment: .bottom) {
                                S8KImage(url: h.posterURL, placeholder: "play.rectangle")
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm)
                                        .strokeBorder(Color.s8kBorder, lineWidth: 1))
                                S8KProgressBar(fraction: h.progress, track: Color.white.opacity(0.15))
                            }
                            .frame(height: 150)
                            Text(h.contentName).font(S8KFont.caption2.weight(.semibold))
                                .foregroundColor(.s8kTextPrimary).lineLimit(1)
                        }
                    }
                    .buttonStyle(S8KButtonStyle())
                }
            }
            .padding(.horizontal, S8KSpace.lg)
        }
    }
}

// MARK: - 5 · Live surfaces

struct LineupRow: View {
    let channel: Channel
    let index: Int
    /// Passed IN, not observed here. Every row used to hold its own `@StateObject`
    /// on the FavoritesService singleton, so a long channel list allocated one
    /// state box and one Combine subscription per visible row and churned them on
    /// every scroll — for a value the parent already knows. The parent observes
    /// once and hands each row a plain Bool.
    let isFav: Bool
    let onFav: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text("\(index)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.s8kTextDisabled).frame(width: 22)

                    S8KImage(url: channel.logoURL, placeholder: "antenna.radiowaves.left.and.right", maxPixel: 240)
                        .frame(width: 46, height: 46).background(Color.s8kElevated)
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(channel.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                        if !channel.groupTitle.isEmpty {
                            Text(channel.groupTitle).font(S8KFont.caption2)
                                .foregroundColor(.s8kTextTertiary).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
            .buttonStyle(S8KButtonStyle())

            // Favorite toggle
            Button(action: onFav) {
                Image(systemName: isFav ? "heart.fill" : "heart")
                    .font(.system(size: 15))
                    .foregroundColor(isFav ? .s8kRed : .s8kTextDisabled)
                    .frame(width: 30, height: 30)
                    // 6, not 8: the row's HStack spacing is 12, so 6 + 6 makes the two
                    // rings touch without overlapping. At 8 the play button — the later
                    // sibling, drawn in front — would have taken 3pt of the heart.
                    .s8kMinTouch(6)
            }
            .buttonStyle(S8KButtonStyle())
            .accessibilityLabel(isFav ? L("detail.fav_added") : L("detail.fav_add"))

            Button(action: onTap) {
                RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .fill(S8KGradient.goldFlat).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                        .foregroundColor(S8KBrand.accentInk))
                    .shadow(color: .s8kGoldMid.opacity(0.3), radius: 4)
                    .s8kMinTouch(6)   // matches the heart; 12pt spacing, no overlap
            }
            .buttonStyle(S8KButtonStyle())
            .accessibilityLabel(L("common.play"))
        }
        .padding(.horizontal, S8KSpace.xl).padding(.vertical, 10)
    }
}

// MARK: The channel lineup
struct ChannelLineup: View {
    let channels: [Channel]
    let onTap: (Channel) -> Void
    /// How many rows are handed to `ForEach` right now. A `LazyVStack` defers building
    /// the VIEWS, but `ForEach` still walks the WHOLE collection to build its identity
    /// map on every invalidation — and `Array(channels.enumerated())` additionally
    /// materialises one tuple per channel each time. On a 56k-channel line, toggling a
    /// single favourite paid for 56k tuples. The window makes first paint O(120) at any
    /// catalogue size and grows as the user actually scrolls.
    @State private var shown = CatalogWindow.firstBatch
    /// Observed ONCE for the whole list — see LineupRow.
    @StateObject private var favs = FavoritesService.shared

    private var visible: ArraySlice<Channel> { channels.prefix(shown) }

    var body: some View {
        Group {
            if channels.isEmpty {
                EmptyState(icon: "antenna.radiowaves.left.and.right.slash",
                           title: L("live.empty.title"), subtitle: L("live.empty.sub"))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, ch in
                        LineupRow(channel: ch, index: idx + 1,
                                   isFav: favs.channels.contains(ch.id),
                                   onFav: { favs.toggleChannel(ch.id) }) { onTap(ch) }
                        if idx < visible.count - 1 {
                            Divider().background(Color.s8kBorder).padding(.leading, 74)
                        }
                    }
                    // Sentinel: appearing means the user reached the end of the window.
                    if shown < channels.count {
                        Color.clear.frame(height: 1)
                            .onAppear { shown = min(shown + CatalogWindow.growth, channels.count) }
                    }
                }
                .onAppear { S8KImageCache.shared.prefetch(channels.prefix(40).compactMap { $0.logoURL }, maxPixel: 240) }
            }
        }
        // Reset when the LIST ITSELF changes (category switch, search, reorder).
        // Keyed on the HEAD ITEM, not count: toggling one favourite changes the count
        // but not the list the user is scrolling, and a reset there would collapse the
        // content height and throw the scroll position. Lives on the Group so it
        // survives the empty branch (a modifier inside `else` is destroyed on 5000 -> 0
        // and never fires).
        .onChange(of: channels.first?.id) { _, _ in shown = CatalogWindow.firstBatch }
    }
}

// MARK: The small always-on preview
// Two structs, not one. THIS one only decides which engine to try — the hardware
// path for HLS, the software one otherwise, subject to whatever the user picked in
// settings — and, if that attempt reports a failure, hands the job to the other
// engine exactly once. The swap works because the inner view is keyed by engine, so
// changing the key tears the failed attempt down and stands a fresh one up. Merge
// the two and there is nothing left to key. The preview carries a single control:
// go fullscreen. Everything else — zapping, gestures, picture-in-picture — belongs
// to the full player and is deliberately absent here.
struct LivePreviewTile: View {
    let channel: Channel
    var isExpanded: Bool = false     // fullscreen is presented over this preview → pause it
    var onExpand: () -> Void
    @State private var engine: PlayerEngineKind
    @State private var triedFallback = false

    init(channel: Channel, isExpanded: Bool = false, onExpand: @escaping () -> Void) {
        self.channel = channel
        self.isExpanded = isExpanded
        self.onExpand = onExpand
        _engine = State(initialValue: PlayerEngineSelector.initialKind(for: .live(channel)))
    }

    var body: some View {
        LivePreviewEngine(channel: channel, engine: engine, canFallback: !triedFallback,
                             isExpanded: isExpanded,
                             onExpand: onExpand,
                             onEngineFailed: {
                                 guard !triedFallback else { return }
                                 triedFallback = true
                                 engine = engine.other      // swap → .id rebuilds with a fresh attempt
                             })
            .id(engine)
    }
}

private struct LivePreviewEngine: View {
    let channel: Channel
    let engine: PlayerEngineKind
    let canFallback: Bool
    let isExpanded: Bool
    var onExpand: () -> Void
    var onEngineFailed: () -> Void
    @StateObject private var vm: BasePlayerVM
    @State private var didReport = false

    init(channel: Channel, engine: PlayerEngineKind, canFallback: Bool, isExpanded: Bool,
         onExpand: @escaping () -> Void, onEngineFailed: @escaping () -> Void) {
        self.channel = channel
        self.engine = engine
        self.canFallback = canFallback
        self.isExpanded = isExpanded
        self.onExpand = onExpand
        self.onEngineFailed = onEngineFailed
        _vm = StateObject(wrappedValue: PlayerEngineSelector.make(item: .live(channel), kind: engine))
    }

    var body: some View {
        ZStack {
            Color.black
            PlayerSurfaceView(vm: vm)
            if vm.isLoading || vm.buffering {
                ProgressView().progressViewStyle(.circular).tint(.s8kGoldHigh).scaleEffect(1.2)
            }
            // Error + retry — only once both engines have failed (a first failure
            // silently fails over via onEngineFailed below).
            if let err = vm.errorMsg, !canFallback {
                Color.black.opacity(0.85)
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26)).foregroundColor(.s8kTextDisabled)
                    Text(err).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 20)
                    Button(action: { vm.errorMsg = nil; vm.setup() }) {
                        Label(L("common.retry"), systemImage: "arrow.clockwise")
                            .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kGoldMid)
                            // ~14pt of text → 44pt tall. It is the only control on the
                            // error overlay, and the only thing within 15pt of it is the
                            // error message itself, which takes no touches.
                            .s8kMinTouch(h: 14, v: 15)
                    }
                }
            }
            VStack {
                HStack {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.45)).clipShape(Circle())
                            // 34 → 44pt, after the clip. It sits in a 10pt inset corner
                            // over the video surface, which carries no gesture of its own.
                            .s8kMinTouch(5)
                    }
                    .buttonStyle(S8KButtonStyle())
                    .accessibilityLabel(L("live.fullscreen"))
                    Spacer()
                }
                Spacer()
            }
            .padding(10)
        }
        .onChange(of: vm.errorMsg) { _, msg in
            if msg != nil, canFallback, !didReport { didReport = true; onEngineFailed() }
        }
        .onAppear { vm.setup() }
        .onDisappear { vm.cleanup() }
        // A cover presented on top of this preview does NOT disappear it — the preview
        // is still "appeared" underneath, so `.onDisappear` above never runs and it
        // keeps decoding and keeps its audio going. That is the doubled-sound report
        // from iPad. Stopping it has to be explicit: pause when the cover goes up,
        // resume when it comes down, so exactly one engine is ever producing sound.
        .onChange(of: isExpanded) { _, expanded in
            if expanded { vm.pause() } else { vm.play() }
        }
    }
}

// MARK: What is on right now
// A one-line guide strip: what is airing, how far through it is, and — outside the
// compact form — what follows. Many providers ship no guide data at all, and for
// those this draws literally nothing, which is what makes it safe to place anywhere
// a channel is on screen without first asking whether a guide exists.
struct EPGNowNext: View {
    let channel: Channel
    var compact: Bool = false
    @State private var programs: [EPGProgram] = []
    @State private var now = Date()
    // A stored property, so the publisher survives a body pass instead of being
    // built again on each one.
    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var current: EPGProgram? { programs.first { $0.startTime <= now && now < $0.endTime } }
    private var upNext:  EPGProgram? { programs.first { $0.startTime > now } }

    var body: some View {
        Group {
            if let c = current {
                VStack(alignment: .trailing, spacing: compact ? 4 : 6) {
                    HStack(spacing: 8) {
                        Text(c.title).font(S8KFont.caption1.weight(.semibold))
                            .foregroundColor(.s8kTextPrimary).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(timeRange(c)).font(S8KFont.caption2)
                            .foregroundColor(.s8kTextTertiary).monospacedDigit()
                    }
                    S8KProgressBar(fraction: progress(c), track: Color.white.opacity(0.10))
                    if !compact, let n = upNext {
                        Text("\(L("epg.next")): \(n.title)").font(S8KFont.caption2)
                            .foregroundColor(.s8kTextTertiary).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .task(id: channel.id) {
            programs = await ContentService.epg(for: channel)
            now = Date()
        }
        .onReceive(ticker) { _ in now = Date() }
    }

    private func progress(_ p: EPGProgram) -> Double {
        let total = p.endTime.timeIntervalSince(p.startTime)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(p.startTime) / total))
    }
    private static let hhmm: DateFormatter = {
        // POSIX: a fixed dateFormat still renders its DIGITS through the locale, so
        // without this an Arabic device shows ١٤:٣٠ in the EPG.
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"; return f
    }()
    private func timeRange(_ p: EPGProgram) -> String {
        "\(Self.hhmm.string(from: p.startTime)) – \(Self.hhmm.string(from: p.endTime))"
    }
}

// MARK: - 6 · The three browse pages

// MARK: Live TV

struct LiveTVView: View {
    @StateObject private var loc  = LocalizationManager.shared
    @StateObject private var vm   = LiveTVVM.shared
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @StateObject private var parental = ParentalService.shared
    @ObservedObject private var router = AppRouter.shared   // global in-place search
    @Environment(\.horizontalSizeClass) private var hSize
    /// Canonical layout metrics — injected once by S8KMetricsRoot (BlankTVApp).
    @Environment(\.s8kMetrics) private var metrics
    @State private var playerItem: ContentItem? = nil
    @State private var showCategories = false
    @State private var showReorder = false
    @State private var tab: BrowseFilter = .all
    @State private var path = NavigationPath()
    @State private var padCat: Category? = nil
    @State private var padChannel: Channel? = nil
    @State private var padShown = CatalogWindow.firstBatch
    @State private var currentChannel: Channel? = nil   // iPhone sticky mini-player selection

    private var favorites: [Channel] { vm.channels.filter { favs.channels.contains($0.id) } }
    private var liveHistory: [WatchHistory] { hist.items.filter { $0.contentType == .live } }
    // The channel shown in the iPhone sticky mini-player — the tapped one, else
    // the first channel (so the page auto-previews on open).
    private var previewing: Channel? { currentChannel ?? vm.channels.first }
    private func preview(_ ch: Channel) { currentChannel = ch }
    private var isPad: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    // Use the 3-pane split only when there's genuinely room (full-screen iPad).
    // In Split View / Slide Over the size class is still .regular but the width
    // is narrow, so fall back to the phone layout to avoid overflowing panes.
    private func useSplit(_ width: CGFloat) -> Bool { isPad && width >= 720 }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ZStack {
                    Color.s8kBlack.ignoresSafeArea()
                    if vm.isLoading {
                        S8KListSkeleton()
                    } else if let e = vm.error {
                        // force: a plain load() early-returns when `loaded` is already
                        // true, so Retry would do nothing and the tab would be stuck on
                        // the error page (reachable when a load is cancelled mid-flight
                        // by a tab remount).
                        ErrorView(message: e.errorDescription ?? L("loading.error")) { Task { await vm.load(force: true) } }
                    } else if useSplit(geo.size.width) { padBrowser(geo.size.width) }
                    else { browser(geo.safeAreaInsets.top) }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Category.self) { cat in
                ParentalGate(kind: .live, categoryID: cat.id) {
                    FolderScreen(title: cat.name, unit: L("unit.channel"),
                                 items: vm.list(in: cat), name: { $0.name }) { shown in
                        ChannelLineup(channels: shown) { playerItem = .live($0) }
                    }
                }
            }
        }
        .task { await vm.load() }
        // Global in-place search (owner #6) — corner-menu search field drives it.
        .onChange(of: router.searchText) { _, q in vm.search = q }
        .onChange(of: router.searchActive) { _, a in if !a { vm.search = "" } }
        .fullScreenCover(item: $playerItem) { PlayerView(item: $0, channels: vm.channels) }
        .sheet(isPresented: $showCategories) {
            FolderPickerSheet(title: L("cats.channels"), categories: vm.folders,
                                count: { vm.list(in: $0).count }) { path.append($0) }
        }
        .sheet(isPresented: $showReorder) {
            CategoryOrderEditor(title: L("reorder.title"), categories: vm.folders, section: "live") { vm.objectWillChange.send() }
        }
    }

    // MARK: Three panes, for a full-size iPad only
    private func padBrowser(_ width: CGFloat) -> some View {
        // Proportional pane widths so the player pane never gets squeezed on
        // portrait / smaller iPads (fixed 230+320 left only ~194–284pt for it).
        let sidebarW  = min(230, max(175, width * 0.20))
        let channelsW = min(320, max(240, width * 0.27))
        return HStack(spacing: 0) {
            FolderSidebar(title: L("title.live"), folders: vm.folders,
                            selected: $padCat, count: { vm.list(in: $0).count },
                            allCount: vm.channels.count, favoritesCount: favorites.count,
                            onReorder: { showReorder = true })
                .frame(width: sidebarW)
            Divider().background(Color.s8kBorder)
            padChannelsPane.frame(width: channelsW)
            Divider().background(Color.s8kBorder)
            padPlayerPane.frame(maxWidth: .infinity)
        }
        // Clear channel preview AND any leftover search query when switching
        // sidebar sections — a stale query would filter the new category to
        // "no results" (matches the Movies/Series iPad behavior).
        .onChange(of: padCat?.id) { _, _ in padChannel = nil; vm.search = ""; padShown = CatalogWindow.firstBatch }
        // While viewing Favorites, if the previewing channel is un-favorited it
        // leaves the middle list — clear the player so it doesn't keep showing a
        // channel that's no longer in view.
        .onChange(of: favs.channels) { _, _ in
            if padCat?.id == Category.favorites.id, let ch = padChannel,
               !favs.channels.contains(ch.id) { padChannel = nil }
        }
    }

    @ViewBuilder
    private var padChannelsPane: some View {
        if padCat?.id == Category.favorites.id {
            channelScroll(favorites)            // cross-category favorites (no parental gate)
        } else if let cat = padCat {
            ParentalGate(kind: .live, categoryID: cat.id) { channelScroll(vm.list(in: cat)) }
        } else {
            channelScroll(vm.channels)
        }
    }
    private func channelScroll(_ chans: [Channel]) -> some View {
        // When a search query is active, show global results across all channels
        // (mirrors the Movies/Series iPad panes and the iPhone live browser);
        // otherwise show the selected category's channels.
        let list = vm.search.isEmpty ? chans : vm.searchResults
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                SearchField(text: $vm.search, placeholder: L("search.live"))
                    .padding(.horizontal, S8KSpace.lg)
                    .padding(.top, max(50, metrics.safeTop + S8KSpace.sm)).padding(.bottom, S8KSpace.md)
                if list.isEmpty {
                    EmptyState(icon: "antenna.radiowaves.left.and.right.slash",
                               title: L("live.empty.title"), subtitle: L("live.empty.sub"))
                        .padding(.top, S8KSpace.xl)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(list.prefix(padShown).enumerated()), id: \.element.id) { idx, ch in
                            LineupRow(channel: ch, index: idx + 1,
                                       isFav: favs.channels.contains(ch.id),
                                       onFav: { favs.toggleChannel(ch.id) }) { padChannel = ch }
                                .background(padChannel?.id == ch.id ? Color.s8kGoldMid.opacity(0.12) : .clear)
                            Divider().background(Color.s8kBorder).padding(.leading, 74)
                        }
                        if padShown < list.count {                  // window sentinel — grows only when scrolled to
                            Color.clear.frame(height: 1)
                                .onAppear { padShown = min(padShown + CatalogWindow.growth, list.count) }
                        }
                    }
                }
                Color.clear.frame(height: metrics.bottomClearance)   // clear the floating AppTabBar
            }
        }
    }

    @ViewBuilder
    private var padPlayerPane: some View {
        if let ch = padChannel {
            VStack(spacing: 0) {
                LivePreviewTile(channel: ch, isExpanded: playerItem != nil) { playerItem = .live(ch) }
                    .id(ch.id)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                channelInfoPane(ch)
                Spacer(minLength: 0)
            }
            .padding(.top, max(50, metrics.safeTop + S8KSpace.sm))   // align with the sidebar + channel list panes
        } else {
            VStack(spacing: 14) {
                Image(systemName: "play.tv").font(.system(size: 54)).foregroundColor(.s8kTextDisabled)
                Text(L("live.pick_channel")).font(S8KFont.callout).foregroundColor(.s8kTextTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func channelInfoPane(_ ch: Channel) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: { favs.toggleChannel(ch.id) }) {
                    Image(systemName: favs.isChannelFav(ch.id) ? "heart.fill" : "heart")
                        .foregroundColor(favs.isChannelFav(ch.id) ? .s8kRed : .s8kTextSecondary)
                        // A bare ~17pt glyph. Vertically it can reach the HIG minimum
                        // (the pane's own padding is above and a Divider below, neither
                        // of them tappable); horizontally 6 is half the row's 12pt
                        // spacing, so it stops where the pill beside it starts.
                        .s8kMinTouch(h: 6, v: 14)
                }
                .buttonStyle(S8KButtonStyle())
                .accessibilityLabel(favs.isChannelFav(ch.id) ? L("detail.fav_added") : L("detail.fav_add"))
                Button(action: { playerItem = .live(ch) }) {
                    Label(L("live.fullscreen"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(S8KGradient.goldFlat).clipShape(Capsule())
                        .s8kMinTouchV(8)     // ~29 → 45pt tall, after the clip
                }
                .buttonStyle(S8KButtonStyle())
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(ch.name).font(S8KFont.title3).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(Color.s8kRed).frame(width: 6, height: 6)
                        Text(L("home.live_now")).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Divider().background(Color.s8kBorder)
            // Live program guide (now/next) — renders nothing if the provider has no EPG.
            EPGNowNext(channel: ch)
        }
        .padding(S8KSpace.xl)
    }

    // iPhone: a sticky mini-player (preview) pinned at the top + a scrolling
    // channel list under it. Tapping a row swaps the preview channel; tapping the
    // player expands to fullscreen. Auto-previews the first channel on open.
    // Same pattern as Movies and Series (owner: make Live match): the page identity
    // capsule top-leading, then ONE glass row carrying categories · the four filters
    // (All / Favorites / Newest / History) · reorder. `topInset` is the measured
    // safe-area top — the old hard-coded `.padding(.top, 56)` was stacked on top of the
    // real inset, which is why this page started lower than everything else.
    @ViewBuilder
    private func browser(_ topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            liveTopBar(topInset)
            if let ch = previewing {
                LivePreviewTile(channel: ch, isExpanded: playerItem != nil) { playerItem = .live(ch) }
                    .id(ch.id)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                miniInfoBar(ch)
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Search field removed — it now lives in the corner menu (owner #6).
                    toolRow
                    if !vm.search.isEmpty {
                        ChannelLineup(channels: vm.searchResults) { preview($0) }
                    } else {
                        tabContent
                    }
                    Color.clear.frame(height: metrics.bottomClearance)
                }
                .s8kInstantTaps()   // on the CONTENT — the probe walks UP to the UIScrollView
            }
            .scrollBounceBehavior(.always)
        .reportsScrollToTabBar()   // collapse the corner puck on scroll (owner #4)
        }
        // Same footing as Movies/Series: the page ZStack is inflated to the full screen
        // by its `ignoresSafeArea` background, so `topInset` must be measured from the
        // PHYSICAL top. Without this the capsule sat 30–60pt lower than the other pages.
        .ignoresSafeArea(edges: .top)
    }

    private func liveTopBar(_ topInset: CGFloat) -> some View {
        S8KSectionBar(title: L("title.live"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, S8KSpace.xl)
            .padding(.top, max(0, topInset) + 6)
            .padding(.bottom, 8)
    }

    // 12, not the shared default of 14 — this page's row sits under a section bar
    // rather than under a hero, and the two pt is the difference that lined it up.
    private var toolRow: some View {
        BrowseToolRow(foldersLabel: L("cats.channels"), filter: $tab, topPad: 12,
                      onFolders: { showCategories = true },
                      onReorder: { showReorder = true })
    }

    // Compact info bar under the mini-player: favorite · fullscreen · name/live ·
    // now/next EPG (renders nothing if the provider has no guide).
    private func miniInfoBar(_ ch: Channel) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 12) {
                Button { favs.toggleChannel(ch.id) } label: {
                    Image(systemName: favs.isChannelFav(ch.id) ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(favs.isChannelFav(ch.id) ? .s8kRed : .s8kTextSecondary)
                        // 16pt glyph. 6 a side is half the row's 12pt spacing, so this
                        // and the fullscreen circle beside it meet without overlapping;
                        // 14 vertically lands inside the bar's 10pt padding.
                        .s8kMinTouch(h: 6, v: 14)
                }
                .buttonStyle(S8KButtonStyle())
                .accessibilityLabel(favs.isChannelFav(ch.id) ? L("detail.fav_added") : L("detail.fav_add"))
                Button { playerItem = .live(ch) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(S8KBrand.accentInk)
                        .frame(width: 34, height: 34).background(S8KGradient.goldFlat).clipShape(Circle())
                        .s8kMinTouch(h: 6, v: 5)   // 34 → 46×44, after the clip
                }
                .buttonStyle(S8KButtonStyle())
                .accessibilityLabel(L("live.fullscreen"))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ch.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(Color.s8kRed).frame(width: 6, height: 6)
                        Text(L("home.live_now")).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                    }
                }
            }
            EPGNowNext(channel: ch, compact: true)
        }
        .padding(.horizontal, S8KSpace.xl).padding(.vertical, 10)
        .background(Color.s8kBlack)
        .overlay(GoldDivider(), alignment: .bottom)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .all:
            if vm.folders.isEmpty {
                ChannelLineup(channels: vm.channels) { preview($0) }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(vm.folders) { cat in
                        CategoryShelf(category: cat, count: vm.list(in: cat).count,
                                    locked: parental.isLockedCategory(.live, cat.id),
                                    gated: parental.isGated(.live, cat.id)) {
                            ForEach(vm.list(in: cat).prefix(16)) { ch in
                                ChannelChip(name: ch.name, logoURL: ch.logoURL, isLive: true) {
                                    preview(ch)
                                }
                            }
                        }
                    }
                }
            }
        case .favorites:
            ChannelLineup(channels: favorites) { preview($0) }
        case .newest:
            ChannelLineup(channels: vm.channels) { preview($0) }
        case .history:
            WatchHistoryTiles(items: liveHistory, empty: L("history.empty")) { h in
                if let ch = vm.channels.first(where: { $0.id == h.contentID }) { preview(ch) }
            }
        }
    }
}

// MARK: Movies

struct MoviesView: View {
    @StateObject private var loc  = LocalizationManager.shared
    @StateObject private var vm   = MoviesVM.shared
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @StateObject private var parental = ParentalService.shared
    @ObservedObject private var router = AppRouter.shared   // global in-place search
    @Environment(\.horizontalSizeClass) private var hSize
    /// Canonical layout metrics — injected once by S8KMetricsRoot (BlankTVApp).
    @Environment(\.s8kMetrics) private var metrics
    @State private var selected: Movie? = nil
    @State private var tab: BrowseFilter = .all
    @State private var showCategories = false
    @State private var showReorder = false
    @State private var path = NavigationPath()
    @State private var padCat: Category? = nil

    private var favorites: [Movie] { vm.movies.filter { favs.movies.contains($0.id) } }
    private var movieHistory: [WatchHistory] { hist.items.filter { $0.contentType == .movie } }
    private var isPad: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    // Split only with real room (full-screen iPad); narrow Split View → phone layout.
    private func useSplit(_ width: CGFloat) -> Bool { isPad && width >= 720 }

    // Editorial hero height (mirrors Home, a touch shorter so the Top-10 peeks).
    /// The ONE hero formula — see `S8KMetrics.heroHeight`. It is FULL-BLEED (it already
    /// spans the area under the status bar), so call sites must NOT add `+ topInset`
    /// the way they used to; that was why "hero height" meant two different things on
    /// Home versus here.
    private var heroHeight: CGFloat { metrics.heroHeight }
    private func openHero(_ item: HomeVM.HeroItem) {
        if case .movie(let m) = item.kind { selected = m }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ZStack {
                    Color.s8kBlack.ignoresSafeArea()
                    if vm.isLoading {
                        // Reserve the same space the loaded page reserves, so the
                        // skeleton does not sit behind the pinned identity capsule.
                        S8KPosterGridSkeleton()
                            .padding(.top, geo.safeAreaInsets.top + 62)
                            .ignoresSafeArea(edges: .top)
                    } else if let e = vm.error {
                        // force: a plain load() early-returns when `loaded` is already
                        // true, so Retry would do nothing and the tab would be stuck on
                        // the error page (reachable when a load is cancelled mid-flight
                        // by a tab remount).
                        ErrorView(message: e.errorDescription ?? L("loading.error")) { Task { await vm.load(force: true) } }
                    } else if useSplit(geo.size.width) { padBrowser(geo.size.width) }
                    else { browser(geo.safeAreaInsets.top) }
                }
                // Pinned identity capsule over the artwork (phone layout only — the iPad
                // split pane has its own sidebar chrome).
                .overlay(alignment: .top) {
                    // NOT gated on !isLoading: hiding the identity bar while the page
                    // loaded meant the skeleton had no title and looked nothing like the
                    // page that replaced it.
                    if vm.error == nil, !useSplit(geo.size.width) {
                        S8KPinnedPageBar(topInset: geo.safeAreaInsets.top) { moviesTopBar }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Category.self) { cat in
                ParentalGate(kind: .movie, categoryID: cat.id) {
                    FolderScreen(title: cat.name, unit: L("unit.movie"),
                                 items: vm.list(in: cat), name: { $0.name }) { shown in
                        MovieWall(movies: shown) { selected = $0 }
                    }
                }
            }
        }
        .task { await vm.load() }
        // Global in-place search (owner #6): the corner-menu search field drives
        // this section's live filter; typing swaps the feed for results.
        .onChange(of: router.searchText) { _, q in vm.search = q }
        .onChange(of: router.searchActive) { _, a in if !a { vm.search = "" } }
        .fullScreenCover(item: $selected) { MovieDetailView(movie: $0) }
        .sheet(isPresented: $showCategories) {
            FolderPickerSheet(title: L("cats.movies"), categories: vm.folders,
                                count: { vm.list(in: $0).count }) { path.append($0) }
        }
        .sheet(isPresented: $showReorder) {
            CategoryOrderEditor(title: L("reorder.title"), categories: vm.folders, section: "movies") { vm.objectWillChange.send() }
        }
    }

    // MARK: Sidebar and wall, for a full-size iPad only
    private func padBrowser(_ width: CGFloat) -> some View {
        let sidebarW = min(300, max(230, width * 0.26))   // proportional so the grid isn't cramped in portrait
        return HStack(spacing: 0) {
            FolderSidebar(title: L("title.movies"), folders: vm.folders,
                            selected: $padCat, count: { vm.list(in: $0).count },
                            allCount: vm.movies.count, favoritesCount: favorites.count,
                            onReorder: { showReorder = true })
                .frame(width: sidebarW)
            Divider().background(Color.s8kBorder)
            padGridPane
        }
        // A leftover search query would otherwise filter a freshly-selected
        // category to "no results" — clear it when switching sidebar sections.
        .onChange(of: padCat?.id) { _, _ in vm.search = "" }
    }
    @ViewBuilder
    private var padGridPane: some View {
        if padCat?.id == Category.favorites.id {
            padGrid(favorites, empty: L("movies.empty.fav"))   // favorites (no parental gate)
        } else if let cat = padCat {
            ParentalGate(kind: .movie, categoryID: cat.id) { padGrid(vm.list(in: cat)) }
        } else {
            padGrid(vm.movies)
        }
    }
    private func padGrid(_ items: [Movie], empty: String = L("movies.empty")) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: S8KSpace.lg) {
                SearchField(text: $vm.search, placeholder: L("search.movies"))
                    .padding(.horizontal, S8KSpace.lg).padding(.top, max(50, metrics.safeTop + S8KSpace.sm))
                MovieWall(movies: vm.search.isEmpty ? items : vm.searchResults,
                           empty: empty) { selected = $0 }
                Color.clear.frame(height: metrics.bottomClearance)   // clear the floating AppTabBar (iPad grid)
            }
        }
    }

    // BLANK TV "Stage + Collections" library (see DESIGN.md). No oversized title
    // bar, no 4-chip strip: a FIXED working top bar (safe-area inset) + an immersive
    // Stage + category "Collections" rails.
    // The poster now runs EDGE TO EDGE under the status bar and stretches on pull-down;
    // the page identity ("الأفلام") is a pinned frosted capsule welded onto it; and every
    // working control that used to crowd the old 114pt title bar has moved into one glass
    // row directly beneath the hero. `topInset` = the real safe-area top, passed in from
    // the page's GeometryReader — never a hard-coded number.
    @ViewBuilder
    private func browser(_ topInset: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if !vm.search.isEmpty {
                    // No hero in search results → reserve the space the pinned bar needs,
                    // and keep the controls reachable (they used to live in a fixed bar
                    // that stayed visible during a search).
                    filteredPage(topInset) {
                        MovieWall(movies: vm.searchResults, empty: L("empty.no_results")) { selected = $0 }
                    }
                } else {
                    tabContent(topInset)
                }
                Color.clear.frame(height: metrics.bottomClearance)
            }
            .s8kInstantTaps()   // on the CONTENT — the probe walks UP to the UIScrollView
        }
        // `.always`: without a bounce there is no over-scroll, and with no over-scroll
        // there is no stretch — on a short page the effect would silently not exist.
        .scrollBounceBehavior(.always)
        .reportsScrollToTabBar()   // collapse the corner puck on scroll (owner #4)
        // Full-bleed: the artwork runs under the notch / Dynamic Island. The working
        // controls are NOT in here — a scroll-child button goes dead in this codebase —
        // they sit in `toolRow`, which is a normal (non-overlapping) row of the feed.
        .ignoresSafeArea(edges: .top)
        .s8kNoScrollEdgeEffect()
    }

    // Pinned page identity. An overlay on the page ZStack (not a safe-area inset, which
    // would push the poster down and destroy the full bleed), so it floats over the
    // artwork and stays put while the page scrolls under it.
    private var moviesTopBar: some View {
        S8KSectionBar(title: L("title.movies"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, S8KSpace.xl)
            .padding(.top, 6)
    }

    // Every control the old top bar carried, in one glass row under the hero:
    // categories (which Movies had LOST — the sheet existed but nothing could open it),
    // the four filters, and reorder.
    private var toolRow: some View {
        BrowseToolRow(foldersLabel: L("cats.movies"), filter: $tab,
                      onFolders: { showCategories = true },
                      onReorder: { showReorder = true })
    }

    // Favourites, newest and history are one page three times over: the strip that
    // reserves room under the pinned capsule, the working row, then a single wall.
    private func filteredPage<Wall: View>(_ topInset: CGFloat,
                                          @ViewBuilder wall: () -> Wall) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset + 62)
            toolRow
            wall()
        }
    }

    @ViewBuilder
    private func tabContent(_ topInset: CGFloat) -> some View {
        switch tab {
        case .all:
            // Editorial feed (Home-style, movies-only): full-bleed stretchy hero →
            // the working row → Top-10 → the user's own category shelves.
            LazyVStack(spacing: 0) {
                if !vm.heroItems.isEmpty {
                    HeroCarouselView(items: vm.heroItems, height: heroHeight,
                                     paused: selected != nil || router.tab != .movies,
                                     onOpen: openHero)
                        // Fixed height so LazyVStack measures the header correctly. The
                        // stretch lives inside the hero card, on the ARTWORK only.
                        .frame(height: heroHeight)
                    toolRow
                } else {
                    Color.clear.frame(height: topInset + 62)
                    toolRow
                }
                if !vm.topRanked.isEmpty {
                    RankRail(title: L("home.top_movies"),
                             cells: vm.topRanked.enumerated().map { ($0.offset + 1, $0.element.id, $0.element.posterURL, $0.element.rating, $0.element.year) }) { id in
                        if let m = vm.topRanked.first(where: { $0.id == id }) { selected = m }
                    }
                }
                if vm.folders.isEmpty {
                    MovieWall(movies: vm.movies, empty: L("movies.empty")) { selected = $0 }
                } else {
                    ForEach(vm.folders) { cat in
                        CategoryShelf(category: cat, count: vm.list(in: cat).count,
                                    locked: parental.isLockedCategory(.movie, cat.id),
                                    gated: parental.isGated(.movie, cat.id)) {
                            ForEach(vm.list(in: cat).prefix(14)) { m in
                                MovieTile(movie: m) { selected = m }.frame(width: 104)
                            }
                        }
                    }
                }
            }
        case .favorites:
            filteredPage(topInset) {
                MovieWall(movies: favorites, empty: L("movies.empty.fav")) { selected = $0 }
            }
        case .newest:
            filteredPage(topInset) {
                MovieWall(movies: vm.movies, empty: L("movies.empty")) { selected = $0 }
            }
        case .history:
            filteredPage(topInset) {
                WatchHistoryTiles(items: movieHistory, empty: L("history.empty")) { h in
                    if let m = vm.movies.first(where: { $0.id == h.contentID }) { selected = m }
                }
            }
        }
    }
}

// MARK: Series

struct SeriesListView: View {
    @StateObject private var loc  = LocalizationManager.shared
    @StateObject private var vm   = SeriesVM.shared
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @StateObject private var parental = ParentalService.shared
    @ObservedObject private var router = AppRouter.shared   // global in-place search
    @Environment(\.horizontalSizeClass) private var hSize
    /// Canonical layout metrics — injected once by S8KMetricsRoot (BlankTVApp).
    @Environment(\.s8kMetrics) private var metrics
    @State private var selected: Series? = nil
    @State private var tab: BrowseFilter = .all
    @State private var showCategories = false
    @State private var showReorder = false
    @State private var path = NavigationPath()
    @State private var padCat: Category? = nil

    private var favorites: [Series] { vm.series.filter { favs.series.contains($0.id) } }
    private var seriesHistory: [WatchHistory] { hist.items.filter { $0.contentType == .episode } }
    private var isPad: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    // Split only with real room (full-screen iPad); narrow Split View → phone layout.
    private func useSplit(_ width: CGFloat) -> Bool { isPad && width >= 720 }

    // Editorial hero height (mirrors Home, a touch shorter so the Top-10 peeks).
    /// The ONE hero formula — see `S8KMetrics.heroHeight`. It is FULL-BLEED (it already
    /// spans the area under the status bar), so call sites must NOT add `+ topInset`
    /// the way they used to; that was why "hero height" meant two different things on
    /// Home versus here.
    private var heroHeight: CGFloat { metrics.heroHeight }
    private func openHero(_ item: HomeVM.HeroItem) {
        if case .series(let s) = item.kind { selected = s }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                ZStack {
                    Color.s8kBlack.ignoresSafeArea()
                    if vm.isLoading {
                        // Reserve the same space the loaded page reserves, so the
                        // skeleton does not sit behind the pinned identity capsule.
                        S8KPosterGridSkeleton()
                            .padding(.top, geo.safeAreaInsets.top + 62)
                            .ignoresSafeArea(edges: .top)
                    } else if let e = vm.error {
                        // force: a plain load() early-returns when `loaded` is already
                        // true, so Retry would do nothing and the tab would be stuck on
                        // the error page (reachable when a load is cancelled mid-flight
                        // by a tab remount).
                        ErrorView(message: e.errorDescription ?? L("loading.error")) { Task { await vm.load(force: true) } }
                    } else if useSplit(geo.size.width) { padBrowser(geo.size.width) }
                    else { browser(geo.safeAreaInsets.top) }
                }
                .overlay(alignment: .top) {
                    if vm.error == nil, !useSplit(geo.size.width) {
                        S8KPinnedPageBar(topInset: geo.safeAreaInsets.top) { seriesTopBar }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Category.self) { cat in
                ParentalGate(kind: .series, categoryID: cat.id) {
                    FolderScreen(title: cat.name, unit: L("unit.series"),
                                 items: vm.list(in: cat), name: { $0.name }) { shown in
                        SeriesWall(series: shown) { selected = $0 }
                    }
                }
            }
        }
        .task { await vm.load() }
        // Global in-place search (owner #6) — corner-menu search field drives it.
        .onChange(of: router.searchText) { _, q in vm.search = q }
        .onChange(of: router.searchActive) { _, a in if !a { vm.search = "" } }
        .fullScreenCover(item: $selected) { SeriesDetailView(series: $0) }
        .sheet(isPresented: $showCategories) {
            FolderPickerSheet(title: L("cats.series"), categories: vm.folders,
                                count: { vm.list(in: $0).count }) { path.append($0) }
        }
        .sheet(isPresented: $showReorder) {
            CategoryOrderEditor(title: L("reorder.title"), categories: vm.folders, section: "series") { vm.objectWillChange.send() }
        }
    }

    // MARK: Sidebar and wall, for a full-size iPad only
    private func padBrowser(_ width: CGFloat) -> some View {
        let sidebarW = min(300, max(230, width * 0.26))   // proportional so the grid isn't cramped in portrait
        return HStack(spacing: 0) {
            FolderSidebar(title: L("title.series"), folders: vm.folders,
                            selected: $padCat, count: { vm.list(in: $0).count },
                            allCount: vm.series.count, favoritesCount: favorites.count,
                            onReorder: { showReorder = true })
                .frame(width: sidebarW)
            Divider().background(Color.s8kBorder)
            padGridPane
        }
        // Clear a leftover query when switching sidebar sections (see Movies).
        .onChange(of: padCat?.id) { _, _ in vm.search = "" }
    }
    @ViewBuilder
    private var padGridPane: some View {
        if padCat?.id == Category.favorites.id {
            padGrid(favorites, empty: L("series.empty.fav"))   // favorites (no parental gate)
        } else if let cat = padCat {
            ParentalGate(kind: .series, categoryID: cat.id) { padGrid(vm.list(in: cat)) }
        } else {
            padGrid(vm.series)
        }
    }
    private func padGrid(_ items: [Series], empty: String = L("series.empty")) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: S8KSpace.lg) {
                SearchField(text: $vm.search, placeholder: L("search.series"))
                    .padding(.horizontal, S8KSpace.lg).padding(.top, max(50, metrics.safeTop + S8KSpace.sm))
                SeriesWall(series: vm.search.isEmpty ? items : vm.searchResults,
                           empty: empty) { selected = $0 }
                Color.clear.frame(height: metrics.bottomClearance)   // clear the floating AppTabBar (iPad grid)
            }
        }
    }

    // Mirrors Movies exactly (see the notes there): full-bleed stretchy hero under the
    // status bar, a pinned frosted identity capsule, and one glass row of controls.
    // The oversized title bar this page used to open with is gone — its buttons were
    // SCROLL CHILDREN, the arrangement this codebase records as making a button dead.
    @ViewBuilder
    private func browser(_ topInset: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if !vm.search.isEmpty {
                    filteredPage(topInset) {
                        SeriesWall(series: vm.searchResults, empty: L("empty.no_results")) { selected = $0 }
                    }
                } else {
                    tabContent(topInset)
                }
                Color.clear.frame(height: metrics.bottomClearance)
            }
            .s8kInstantTaps()   // on the CONTENT — the probe walks UP to the UIScrollView
        }
        .scrollBounceBehavior(.always)   // no bounce → no over-scroll → no stretch
        .reportsScrollToTabBar()         // collapse the corner puck on scroll (owner #4)
        .ignoresSafeArea(edges: .top)    // artwork runs under the notch
        .s8kNoScrollEdgeEffect()
    }

    private var seriesTopBar: some View {
        S8KSectionBar(title: L("title.series"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, S8KSpace.xl)
            .padding(.top, 6)
    }

    private var toolRow: some View {
        BrowseToolRow(foldersLabel: L("cats.series"), filter: $tab,
                      onFolders: { showCategories = true },
                      onReorder: { showReorder = true })
    }

    // Same three-part page as Movies — see the note there.
    private func filteredPage<Wall: View>(_ topInset: CGFloat,
                                          @ViewBuilder wall: () -> Wall) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset + 62)
            toolRow
            wall()
        }
    }

    @ViewBuilder
    private func tabContent(_ topInset: CGFloat) -> some View {
        switch tab {
        case .all:
            // Editorial feed (Home-style, series-only): full-bleed stretchy hero →
            // the working row → Top-10 → the user's own category shelves.
            LazyVStack(spacing: 0) {
                if !vm.heroItems.isEmpty {
                    HeroCarouselView(items: vm.heroItems, height: heroHeight,
                                     paused: selected != nil || router.tab != .series,
                                     onOpen: openHero)
                        .frame(height: heroHeight)
                    toolRow
                } else {
                    Color.clear.frame(height: topInset + 62)
                    toolRow
                }
                if !vm.topRanked.isEmpty {
                    RankRail(title: L("home.top_series"),
                             cells: vm.topRanked.enumerated().map { ($0.offset + 1, $0.element.id, $0.element.coverURL, $0.element.rating, $0.element.year) }) { id in
                        if let s = vm.topRanked.first(where: { $0.id == id }) { selected = s }
                    }
                }
                if vm.folders.isEmpty {
                    SeriesWall(series: vm.series, empty: L("series.empty")) { selected = $0 }
                } else {
                    ForEach(vm.folders) { cat in
                        CategoryShelf(category: cat, count: vm.list(in: cat).count,
                                    locked: parental.isLockedCategory(.series, cat.id),
                                    gated: parental.isGated(.series, cat.id)) {
                            ForEach(vm.list(in: cat).prefix(14)) { s in
                                SeriesTile(series: s) { selected = s }.frame(width: 104)
                            }
                        }
                    }
                }
            }
        case .favorites:
            filteredPage(topInset) {
                SeriesWall(series: favorites, empty: L("series.empty.fav")) { selected = $0 }
            }
        case .newest:
            filteredPage(topInset) {
                SeriesWall(series: vm.series, empty: L("series.empty")) { selected = $0 }
            }
        case .history:
            filteredPage(topInset) {
                WatchHistoryTiles(items: seriesHistory, empty: L("history.empty")) { h in
                    if let s = vm.series.first(where: { h.contentName.hasPrefix($0.name) }) { selected = s }
                }
            }
        }
    }
}

// MARK: - 7 · Putting the folders in your own order

// MARK: The folder-order editor
// Two stacks. The top one is the order the user built: numbered badges, drag to
// move, swipe to drop. Everything still unchosen waits underneath behind a +.
// Nothing is written until the user actually arranges something — leave it
// untouched and the provider's own order stands (Store.orderedCategories), so a
// first run behaves as though this editor did not exist. What does get written is
// scoped to the playlist and outlives a relaunch or a logout.
struct CategoryOrderEditor: View {
    let title: String
    let categories: [Category]     // current display order
    let section: String            // "live" | "movies" | "series"
    var onSaved: () -> Void = {}   // parent notifies its VM so folders refresh instantly
    var embedded: Bool = false     // inside the unified reorder page: no nav chrome, auto-save
    @Environment(\.dismiss) private var dismiss
    @State private var arranged: [String] = []
    @State private var searchText = ""
    @State private var didLoad = false
    private let haptic = UISelectionFeedbackGenerator()

    // The chosen lists, in the saved order.
    private var arrangedCats: [Category] { arranged.compactMap { id in categories.first { $0.id == id } } }
    // Everything not yet chosen (search-filtered).
    private var unarranged: [Category] {
        let rest = categories.filter { !arranged.contains($0.id) }
        return CatalogText.narrow(rest, matching: searchText, by: { $0.name })
    }
    // How tall the arranged stack is allowed to get. It sizes to its own rows, but a
    // ceiling stops it eating the window: past the cap it scrolls inside itself
    // instead of growing. The point of the ceiling is the OTHER stack — the pool of
    // lists still to be added has to stay usable at every screen size and in both
    // orientations, so it is guaranteed the larger share and can never be squeezed
    // to a sliver. With only a handful arranged the stack is shorter than its cap
    // anyway and the pool simply gets more.
    private func arrangedHeight(_ available: CGFloat) -> CGFloat {
        let content = CGFloat(max(arrangedCats.count, 1)) * 52 + 6
        // The first layout pass of a sheet can report height 0, which would collapse the
        // drag list to nothing (and it never comes back until the view is rebuilt).
        // Substitute a sensible height ONLY for that degenerate pass — clamping every
        // real height to ≥500 would hand the list 64% of a short landscape window.
        let usable: CGFloat = available > 1 ? available : 500
        // Short (landscape) heights spend more on fixed chrome, so hand the pool an
        // even bigger share there; tall layouts allow the arranged list up to ~42%.
        let fraction: CGFloat = usable < 500 ? 0.32 : 0.42
        return min(content, usable * fraction)
    }

    var body: some View {
        if embedded {
            // Inside the unified reorder page: no nav chrome; changes auto-save so
            // switching section tabs never loses the arrangement.
            reorderBody
                .onChange(of: arranged) { _, p in Store.shared.setCategoryOrder(p, section); onSaved() }
        } else {
            NavigationStack {
                reorderBody
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("common.cancel")) { dismiss() }.foregroundColor(.s8kTextSecondary)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L("common.save")) {
                                Store.shared.setCategoryOrder(arranged, section)
                                onSaved(); dismiss()
                            }
                            .foregroundColor(.s8kGoldMid).fontWeight(.bold)
                        }
                    }
            }
        }
    }

    private var reorderBody: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            GeometryReader { geo in
                VStack(spacing: 0) {
                    regionPresets
                    arrangedSection(geo.size.height)
                    Divider().background(Color.s8kBorder).padding(.vertical, S8KSpace.sm)
                    unarrangedSection
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // Attached to the ZStack, NOT to the GeometryReader. The saved order has to be
        // read once, when the editor appears — hanging this off the reader would tie it
        // to a measurement pass instead.
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            // Pre-fill ONLY the user's previously-saved arrangement (still-existing
            // categories): empty for a new user, their own order for a returning one.
            arranged = Store.shared.categoryOrder(section).filter { id in categories.contains { $0.id == id } }
        }
    }

    // One tap floats a whole region to the top; dragging afterwards still works.
    // Classification is offline keyword matching (RegionClassifier) — no lookup.
    private var regionPresets: some View {
        HStack(spacing: 8) {
            Text(L("reorder.quick")).font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kTextSecondary)
            Spacer()
            ForEach(ContentRegion.allCases) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        arranged = RegionClassifier.presetOrder(categories, primary: r)
                    }
                    haptic.selectionChanged()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: r.icon).font(.system(size: 11, weight: .bold))
                        Text(r.title).font(S8KFont.caption2.weight(.bold))
                    }
                    .foregroundColor(.s8kGoldMid)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.s8kGoldMid.opacity(0.10)).clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.s8kBorderGold, lineWidth: 1))
                }
                .buttonStyle(S8KButtonStyle())
            }
        }
        .padding(.horizontal, S8KSpace.xl).padding(.top, S8KSpace.sm).padding(.bottom, 2)
    }

    // The upper stack: the user's own order. Drag to move, swipe to remove. Takes the
    // window height rather than reading it, so the height rule stays in one place.
    @ViewBuilder
    private func arrangedSection(_ availableHeight: CGFloat) -> some View {
        bandLabel(L("reorder.your_order"), count: arrangedCats.isEmpty ? nil : arrangedCats.count)
        Text(L("reorder.drag_hint"))
            .font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, S8KSpace.xl).padding(.bottom, 4)

        if arrangedCats.isEmpty {
            Text(L("reorder.empty_arranged"))
                .font(S8KFont.subhead).foregroundColor(.s8kTextTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 22)
        } else {
            List {
                ForEach(arrangedCats) { cat in
                    arrangedCatRow(cat, number: (arranged.firstIndex(of: cat.id) ?? 0) + 1)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.s8kBorder)
                        .listRowInsets(EdgeInsets(top: 0, leading: S8KSpace.lg,
                                                  bottom: 0, trailing: S8KSpace.lg))
                }
                .onMove { from, to in
                    // Manual reorder (standard SwiftUI onMove semantics) — the
                    // move(fromOffsets:toOffsets:) helper failed to resolve under
                    // the Xcode 26.4 toolchain, so do it with plain array ops.
                    let moving = from.sorted().map { arranged[$0] }
                    for i in from.sorted(by: >) { arranged.remove(at: i) }
                    let dest = to - from.filter { $0 < to }.count
                    arranged.insert(contentsOf: moving, at: min(max(dest, 0), arranged.count))
                    haptic.selectionChanged()
                }
                .onDelete { offsets in
                    let ids = offsets.map { arrangedCats[$0].id }
                    arranged.removeAll { ids.contains($0) }; haptic.selectionChanged()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .frame(height: arrangedHeight(availableHeight))
        }
    }

    // The lower stack: everything not chosen yet, searchable, each with a + .
    @ViewBuilder
    private var unarrangedSection: some View {
        bandLabel(L("reorder.available"), count: nil)
        SearchField(text: $searchText, placeholder: L("reorder.search"))
            .padding(.horizontal, S8KSpace.xl).padding(.bottom, 4)
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(unarranged) { cat in
                    addableRow(cat)
                    Divider().background(Color.s8kBorder).padding(.leading, 64)
                }
                if unarranged.isEmpty {
                    Text(L("empty.no_results"))
                        .font(S8KFont.subhead).foregroundColor(.s8kTextTertiary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }
                Color.clear.frame(height: 40)
            }
            .animation(.easeInOut(duration: 0.22), value: arranged)
        }
    }

    private func bandLabel(_ text: String, count: Int?) -> some View {
        HStack(spacing: 8) {
            Text(text).font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kTextSecondary)
            if let c = count {
                Text("\(c)").font(S8KFont.caption1.weight(.heavy)).foregroundColor(.black)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(S8KGradient.goldFlat).clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, S8KSpace.xl).padding(.top, S8KSpace.sm).padding(.bottom, 4)
    }

    // A row of the upper stack: position badge + name. The drag handle and the delete
    // control are the List's own, supplied by edit mode.
    private func arrangedCatRow(_ cat: Category, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(S8KFont.subhead.weight(.heavy)).foregroundColor(.black)
                .frame(width: 26, height: 26)
                .background(S8KGradient.goldFlat).clipShape(Circle())
            Text(cat.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // A row of the lower stack: the whole row is the + — tapping it appends.
    private func addableRow(_ cat: Category) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.22)) { arranged.append(cat.id) }
            haptic.selectionChanged()
        }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22)).foregroundColor(.s8kGoldMid)
                Text(cat.name).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, S8KSpace.xl).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: The Settings entry point (owner #7)
// One place — reached from Settings — to organize ALL sections: a segmented
// Movies / Series / Live picker over the shared embedded reorder view. Each
// section auto-saves and carries the region quick-sort presets.
struct UnifiedReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var movies = MoviesVM.shared
    @StateObject private var series = SeriesVM.shared
    @StateObject private var live   = LiveTVVM.shared
    @State private var section: Sect = .movies

    enum Sect: String, CaseIterable, Identifiable {
        case movies, series, live
        var id: String { rawValue }
        var title: String {
            switch self {
            case .movies: return L("title.movies")
            case .series: return L("title.series")
            case .live:   return L("title.live")
            }
        }
    }

    private var cats: [Category] {
        switch section {
        case .movies: return movies.folders
        case .series: return series.folders
        case .live:   return live.folders
        }
    }
    private func notifyVM() {
        switch section {
        case .movies: movies.objectWillChange.send()
        case .series: series.objectWillChange.send()
        case .live:   live.objectWillChange.send()
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $section) {
                        ForEach(Sect.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, S8KSpace.xl)
                    .padding(.top, S8KSpace.md).padding(.bottom, S8KSpace.sm)

                    CategoryOrderEditor(title: "", categories: cats, section: section.rawValue,
                                        onSaved: { notifyVM() }, embedded: true)
                        .id(section)   // fresh state per section → loads that section's saved order
                }
            }
            .navigationTitle(L("reorder.manage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.close")) { dismiss() }
                        .foregroundColor(.s8kGoldMid).fontWeight(.bold)
                }
            }
            .task { await movies.load(); await series.load(); await live.load() }
        }
    }
}

// MARK: - 8 · Detail covers

struct MovieDetailView: View {
    let movie: Movie
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.s8kMetrics) private var metrics
    @State private var playItem: ContentItem? = nil
    @State private var enriched: Movie? = nil
    @State private var loadingInfo = true
    @State private var showDetails = false

    // The movie shown — enriched with full metadata once fetched
    private var m: Movie { enriched ?? movie }

    // The artwork canvas is FIXED and the content rises over it. 44% of the window,
    // clamped so it is never taller than half a short window.
    private var canvasHeight: CGFloat {
        // max(180, …): with iPad multitasking enabled a window can be 320pt tall, where
        // h - 300 goes to 20 and the plinth spacer (canvasHeight - 34) went NEGATIVE.
        max(180, min(metrics.size.height * 0.44, metrics.size.height - 300))
    }

    var body: some View {
        // NO NavigationStack: its bar is what forced the borrowed chrome (an inline
        // title plus a bare xmark). Identity here is the artwork and the plinth.
        ZStack(alignment: .top) {
            Color.s8kBlack.ignoresSafeArea()
            canvas
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Transparent window onto the fixed canvas. The plinth starts
                    // below it and scrolls up over the artwork.
                    Color.clear.frame(height: canvasHeight - 34)
                    S8KPlinth { plinthContent }
                }
                .frame(maxWidth: metrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.always)
            .ignoresSafeArea(edges: .top)
            .s8kNoScrollEdgeEffect()
            closeBar
        }
        .task {
            MediaPrefetcher.shared.prefetch(.movie(movie))   // warm the stream while the page loads
            enriched = try? await ContentService.movieDetail(movie)
            loadingInfo = false
        }
        .fullScreenCover(item: $playItem) { PlayerView(item: $0) }
        .sheet(isPresented: $showDetails) {
            if let d = m.details {
                S8KDetailsSheet(title: m.name, details: d,
                                onTrailer: s8kTrailerURL(d.trailer).map { url in { s8kOpenURL(url) } })
            }
        }
    }

    // MARK: The fixed artwork canvas
    private var canvas: some View {
        Color.clear
            .frame(maxWidth: .infinity).frame(height: canvasHeight)
            .overlay(alignment: .top) {
                S8KImage(url: m.backdropURL ?? m.posterURL, placeholder: "film", maxPixel: 1400)
            }
            .clipped()
            // A dark wash over the artwork so the status bar and the close control stay
            // legible over ANY poster, and the plinth's edge reads as a lift, not a seam.
            .overlay(LinearGradient(stops: [
                .init(color: .black.opacity(0.55), location: 0.00),
                .init(color: .black.opacity(0.10), location: 0.28),
                .init(color: .clear,               location: 0.55),
                .init(color: .s8kBlack.opacity(0.65), location: 1.00),
            ], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    // MARK: Close — the same circular glass object as the tool rows on the main pages
    private var closeBar: some View {
        S8KPinnedPageBar(topInset: metrics.safeTop) {
            HStack {
                if s8kIsRTL { Spacer(minLength: 0) }
                S8KSatellite(icon: "xmark", tint: .white, label: L("common.close")) { dismiss() }
                if !s8kIsRTL { Spacer(minLength: 0) }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, 4)
        }
    }

    // MARK: The plinth — live type, never an image of a title
    private var plinthContent: some View {
        VStack(alignment: s8kTextAlign, spacing: 18) {
            Text(m.name)
                .font(.system(size: 30, weight: .black))
                .foregroundColor(.s8kTextPrimary)
                .multilineTextAlignment(s8kMultiline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
            RoundedRectangle(cornerRadius: 2).fill(Color.s8kGoldHigh).frame(width: 52, height: 4)

            metaLine
            actionRow

            if let plot = m.plot, !plot.isEmpty {
                VStack(alignment: s8kTextAlign, spacing: 12) {
                    S8KDetailHeading(title: L("detail.story"))
                    S8KExpandableText(text: plot)
                }
            } else if loadingInfo {
                HStack { Spacer(); ProgressView().tint(.s8kGoldHigh); Spacer() }.padding(.vertical, 8)
            }

            if let cast = m.cast, !cast.isEmpty {
                VStack(alignment: s8kTextAlign, spacing: 12) {
                    S8KDetailHeading(title: L("detail.cast"))
                    // Flat text, no bordered chips — bordered micro-chips are the other
                    // app's vocabulary and this page no longer speaks it.
                    Text(castList(cast).joined(separator: "  ·  "))
                        .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                        .lineSpacing(6)
                        .multilineTextAlignment(s8kMultiline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
                }
            }
            // A cover has no floating tab bar to clear -- only the home indicator.
            Color.clear.frame(height: metrics.safeBottom + S8KSpace.xxl)
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.top, 26)
    }

    /// One flat interpunct line instead of a row of bordered micro-chips.
    private var metaLine: some View {
        let parts = [m.year, m.genre, m.duration, m.director].compactMap { $0 }.filter { !$0.isEmpty }
        return HStack(spacing: 10) {
            if let r = m.rating, let rv = Double(r), rv > 0, rv.isFinite {
                Text(String(format: "%.1f", rv))
                    .font(S8KFont.caption1.weight(.heavy)).foregroundColor(S8KBrand.accentInk)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.s8kGoldHigh))
            }
            if !parts.isEmpty {
                Text(parts.joined(separator: "  ·  "))
                    .font(S8KFont.subhead).foregroundColor(.s8kTextSecondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
    }

    /// A content-sized play capsule with circular glass satellites — NOT a full-width
    /// bar plus two rounded squares, which is the single most-copied strip in the
    /// category and was identical to the reference app line for line.
    private var actionRow: some View {
        let progress = hist.progress(for: m.id)
        // The details satellite adds a THIRD non-shrinkable 48pt control. Measured
        // against the device matrix: at .compactNarrow (the 320pt iPad Slide Over
        // pane) three satellites plus the play capsule's own fixed padding exceed the
        // 288pt of content width before a single glyph of the title, and the download
        // control would be pushed out and clipped. So below that breakpoint the row
        // stacks: capsule on top, satellites centred beneath. Explicit breakpoint
        // rather than ViewThatFits — deterministic, and it reads the same on every
        // device instead of silently choosing a different branch per width.
        let stacked = metrics.cls == .compactNarrow
        // Edge-aligned, not centred: every other block in the plinth uses
        // s8kFrameAlign, and the outer .frame(maxWidth:) centres its child unless it
        // is given an alignment of its own — so without both, the stacked row would
        // be the only centred thing on the page.
        return VStack(alignment: s8kTextAlign, spacing: 12) {
            if stacked {
                capsule(progress)
                HStack(spacing: 12) { satellites }
            } else {
                HStack(spacing: 12) {
                    // Mirror by LANGUAGE: an unconditional trailing Spacer makes the
                    // HStack fill, so a trailing .frame(alignment:) can never move
                    // anything.
                    if s8kIsRTL { Spacer(minLength: 0) }
                    capsule(progress)
                    satellites
                    if !s8kIsRTL { Spacer(minLength: 0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
    }

    private func capsule(_ progress: Double) -> some View {
        S8KPlayCapsule(title: progress > 0.02 && progress < 0.98
                              ? L("detail.resume") : L("detail.play_movie"),
                       progress: progress) {
            playItem = .movie(m)
        }
    }

    @ViewBuilder
    private var satellites: some View {
        S8KSatellite(icon: favs.isMovieFav(m.id) ? "heart.fill" : "heart",
                     tint: favs.isMovieFav(m.id) ? .s8kRed : .s8kTextSecondary,
                     label: favs.isMovieFav(m.id) ? L("detail.fav_added") : L("detail.fav_add")) { favs.toggleMovie(m.id) }
        // Appears ONLY when the panel actually published something worth showing —
        // a details button that opens an empty sheet is worse than no button.
        if let d = m.details, !d.isEmpty {
            S8KSatellite(icon: "list.bullet.rectangle", tint: .s8kTextSecondary,
                         label: L("details.title")) { showDetails = true }
        }
        DownloadControl(target: .movie(m), size: 18, showPercent: false)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.white.opacity(0.07)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false))
    }

    private func castList(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: ",،"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// NOTE: `MetaSection` — a right-aligned section title with a 3×16 vertical accent bar
// beside it — was DELETED. It was byte-identical to the sibling app's section header,
// and it contradicted this app's own approved motif (a heavy title with a short accent
// rule BENEATH it, `SectionHeader` / `S8KDetailHeading`) inside one binary. Deleting it
// rather than leaving it unused is deliberate: an unused view is an invitation to
// reintroduce the borrowed motif.

@MainActor
final class SeriesDetailModel: ObservableObject {
    @Published var seasons:  [Season]  = []
    @Published var selected: Season?   = nil
    @Published var isLoading: Bool     = true
    @Published var error:    AppError? = nil
    /// Harvested from the very same get_series_info payload the episode list needs —
    /// never a second request. nil for demo and raw-M3U sources, where the details
    /// button simply does not appear.
    @Published var details:  S8KTitleDetails? = nil

    func load(series: Series) async {
        isLoading = true; error = nil
        do {
            // M3U: seasons are parsed locally; Xtream: fetched from API
            seasons  = try await ContentService.seasons(of: series)
            selected = seasons.first
            details  = await ContentService.seriesDetails(of: series)
        // Silent on cancellation — same rule as the section models.
        } catch let e as AppError { guard !Task.isCancelled else { return }; error = e }
          catch { guard !Task.isCancelled else { return }; self.error = .network(error) }
        isLoading = false
    }
}

struct SeriesDetailView: View {
    let series: Series
    @StateObject private var vm   = SeriesDetailModel()
    @StateObject private var favs = FavoritesService.shared
    @StateObject private var hist = HistoryService.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.s8kMetrics) private var metrics
    @State private var playItem: ContentItem? = nil
    @State private var showDetails = false

    private var canvasHeight: CGFloat {
        // max(180, …): with iPad multitasking enabled a window can be 320pt tall, where
        // h - 300 goes to 20 and the plinth spacer (canvasHeight - 34) went NEGATIVE.
        max(180, min(metrics.size.height * 0.44, metrics.size.height - 300))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.s8kBlack.ignoresSafeArea()
            canvas
            if let e = vm.error {
                ErrorView(message: e.errorDescription ?? L("loading.error")) {
                    Task { await vm.load(series: series) }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: canvasHeight - 34)
                        S8KPlinth { plinthContent }
                    }
                    .frame(maxWidth: metrics.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.always)
                .ignoresSafeArea(edges: .top)
                .s8kNoScrollEdgeEffect()
            }
            closeBar
        }
        .task { await vm.load(series: series) }
        .fullScreenCover(item: $playItem) { PlayerView(item: $0, queue: vm.selected?.episodes ?? []) }
        .sheet(isPresented: $showDetails) {
            if let d = vm.details {
                S8KDetailsSheet(title: series.name, details: d,
                                onTrailer: s8kTrailerURL(d.trailer).map { url in { s8kOpenURL(url) } })
            }
        }
    }

    private var canvas: some View {
        Color.clear
            .frame(maxWidth: .infinity).frame(height: canvasHeight)
            .overlay(alignment: .top) {
                S8KImage(url: series.backdropURL ?? series.coverURL, placeholder: "tv", maxPixel: 1400)
            }
            .clipped()
            .overlay(LinearGradient(stops: [
                .init(color: .black.opacity(0.55), location: 0.00),
                .init(color: .black.opacity(0.10), location: 0.28),
                .init(color: .clear,               location: 0.55),
                .init(color: .s8kBlack.opacity(0.65), location: 1.00),
            ], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    private var closeBar: some View {
        S8KPinnedPageBar(topInset: metrics.safeTop) {
            HStack {
                if s8kIsRTL { Spacer(minLength: 0) }
                S8KSatellite(icon: "xmark", tint: .white, label: L("common.close")) { dismiss() }
                if !s8kIsRTL { Spacer(minLength: 0) }
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.top, 4)
        }
    }

    private var plinthContent: some View {
        VStack(alignment: s8kTextAlign, spacing: 18) {
            Text(series.name)
                .font(.system(size: 30, weight: .black))
                .foregroundColor(.s8kTextPrimary)
                .multilineTextAlignment(s8kMultiline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
            RoundedRectangle(cornerRadius: 2).fill(Color.s8kGoldHigh).frame(width: 52, height: 4)

            metaLine
            actionRow

            if let plot = series.plot, !plot.isEmpty {
                VStack(alignment: s8kTextAlign, spacing: 12) {
                    S8KDetailHeading(title: L("detail.story"))
                    S8KExpandableText(text: plot)
                }
            }

            seasonBar
            episodeList
            // A cover has no floating tab bar to clear -- only the home indicator.
            Color.clear.frame(height: metrics.safeBottom + S8KSpace.xxl)
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.top, 26)
    }

    private var metaLine: some View {
        let parts = [series.year, series.genre].compactMap { $0 }.filter { !$0.isEmpty }
        return HStack(spacing: 10) {
            if let r = series.rating, let rv = Double(r), rv > 0, rv.isFinite {
                Text(String(format: "%.1f", rv))
                    .font(S8KFont.caption1.weight(.heavy)).foregroundColor(S8KBrand.accentInk)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.s8kGoldHigh))
            }
            if !parts.isEmpty {
                Text(parts.joined(separator: "  ·  "))
                    .font(S8KFont.subhead).foregroundColor(.s8kTextSecondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
    }

    /// Play resolves to the NEXT unwatched episode of the selected season, so the
    /// primary action is never "which episode?" — the page answers it.
    /// Which episode the play capsule offers.
    ///
    /// OWNER-REPORTED: watch episode 9, leave the series, come back — the button said
    /// episode 1. The old rule was "the first episode with progress < 0.9", which only
    /// ever works if you watch strictly in order from the start: episode 1, never
    /// opened and therefore at progress 0, also satisfies "< 0.9" and it comes first,
    /// so it won every time no matter what you actually watched.
    ///
    /// The rule now, in priority order:
    ///   1. The episode you last watched and did NOT finish — resume exactly there.
    ///   2. Otherwise the one AFTER the furthest episode you did finish — go forward.
    ///   3. Otherwise the first.
    private var nextEpisode: Episode? {
        guard let s = vm.selected, !s.episodes.isEmpty else { return nil }
        let ids = Set(s.episodes.map(\.id))
        // `hist.items` is kept most-recent-first (update() inserts at 0), so the first
        // match IS the latest one touched — no date comparison needed.
        let furthestDone = s.episodes.lastIndex(where: { hist.progress(for: $0.id) >= 0.9 })
        if let recent = hist.items.first(where: { ids.contains($0.contentID) && $0.progress < 0.9 }),
           let idx = s.episodes.firstIndex(where: { $0.id == recent.contentID }),
           // ...but only if it is not BEHIND something already finished. Abandoning
           // ep 9 and then finishing ep 10 should offer 11, not drag you back to 9.
           idx >= (furthestDone ?? -1) {
            return s.episodes[idx]
        }
        // Everything watched is finished: offer the one after the furthest finished.
        // Finishing the last episode offers it again rather than returning nil.
        if let done = furthestDone {
            let after = s.episodes.index(after: done)
            return after < s.episodes.endIndex ? s.episodes[after] : s.episodes[done]
        }
        return s.episodes.first
    }

    private var actionRow: some View {
        let ep = nextEpisode
        let progress = ep.map { hist.progress(for: $0.id) } ?? 0
        return HStack(spacing: 12) {
            // Mirror by LANGUAGE — see MovieDetailView.actionRow.
            if s8kIsRTL { Spacer(minLength: 0) }
            if let ep {
                S8KPlayCapsule(title: "\(L("episode.number")) \(s8kEpisodeNumeral(ep.episodeNumber))",
                               progress: progress) {
                    playItem = .episode(ep, series)
                }
            }
            S8KSatellite(icon: favs.isSeriesFav(series.id) ? "heart.fill" : "heart",
                         tint: favs.isSeriesFav(series.id) ? .s8kRed : .s8kTextSecondary,
                         label: favs.isSeriesFav(series.id) ? L("detail.fav_added") : L("detail.fav_add")) { favs.toggleSeries(series.id) }
            // Only when the panel published something — see MovieDetailView.
            if let d = vm.details, !d.isEmpty {
                S8KSatellite(icon: "list.bullet.rectangle", tint: .s8kTextSecondary,
                             label: L("details.title")) { showDetails = true }
            }
            if !s8kIsRTL { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    /// ONE control, not a scrolling strip of season chips: the season is a Menu, the
    /// same object as the filter control on the Movies/Series pages.
    @ViewBuilder
    private var seasonBar: some View {
        if let sel = vm.selected {
            HStack(spacing: 12) {
                if s8kIsRTL { Spacer(minLength: 0) }
                Menu {
                    Picker("", selection: Binding(get: { sel.id },
                                                  set: { id in vm.selected = vm.seasons.first { $0.id == id } })) {
                        ForEach(vm.seasons) { s in
                            Text("\(L("season.number")) \(s.seasonNumber)").tag(s.id)
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text("\(L("season.number")) \(sel.seasonNumber)")
                            .font(S8KFont.subhead.weight(.bold))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.s8kTextPrimary)
                    .padding(.horizontal, 14).frame(height: 42)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.07)))
                    .overlay(Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        .allowsHitTesting(false))
                    .contentShape(Rectangle())
                }
                .buttonStyle(S8KButtonStyle())
                .disabled(vm.seasons.count < 2)
                Text("\(s8kEpisodeNumeral(sel.episodes.count)) \(L("detail.episodes_n"))")
                    .font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                if !s8kIsRTL { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        } else if vm.isLoading {
            HStack { Spacer(); ProgressView().tint(.s8kGoldHigh); Spacer() }.padding(.vertical, 20)
        }
    }

    /// NUMBER-LED rows: an oversized episode numeral in its own gutter, the thumbnail
    /// on the OPPOSITE side, and the resume state as a rule along the thumbnail's
    /// bottom edge. This is the deliberate inversion of the universal anatomy
    /// (120x68 thumbnail leading + circular play badge + trailing chevron), which the
    /// reference app and every mainstream service ship identically.
    /// The numeral is deliberately oversized and set in TABULAR figures, so the
    /// gutter holds its width from episode 1 to episode 199 and the rows never shuffle.
    private var episodeList: some View {
        LazyVStack(spacing: 10) {
            if let season = vm.selected {
                ForEach(season.episodes) { ep in
                    episodeRow(ep)
                }
            }
        }
        // Fresh identity per season so switching seasons rebuilds the subtree instead
        // of recycling row Buttons mid-touch (that recycling made a season tap open an
        // episode on iPad).
        .id(vm.selected?.id)
    }

    private func episodeRow(_ ep: Episode) -> some View {
        let progress = hist.progress(for: ep.id)
        let watched  = progress >= 0.9
        return HStack(spacing: 8) {
        Button(action: { playItem = .episode(ep, series) }) {
            HStack(spacing: 14) {
                // The row MIRRORS: in Arabic the numeral gutter is on the right and the
                // thumbnail on the left, so the gutter always sits on the same side as
                // the text it numbers. (The app forces layoutDirection .leftToRight, so
                // child ORDER has to be flipped by hand.)
                if s8kIsRTL { episodeThumb(ep, progress: progress, watched: watched) }
                if !s8kIsRTL { episodeNumeral(ep, watched: watched) }

                VStack(alignment: s8kTextAlign, spacing: 4) {
                    Text(ep.title.isEmpty
                         ? "\(L("episode.number")) \(s8kEpisodeNumeral(ep.episodeNumber))"
                         : ep.title)
                        .font(S8KFont.headline).foregroundColor(.s8kTextPrimary)
                        .lineLimit(2).multilineTextAlignment(s8kMultiline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let d = ep.duration, !d.isEmpty {
                        Text(d).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: s8kFrameAlign)

                if !s8kIsRTL { episodeThumb(ep, progress: progress, watched: watched) }
                if s8kIsRTL { episodeNumeral(ep, watched: watched) }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L("episode.number")) \(s8kEpisodeNumeral(ep.episodeNumber)), \(ep.title)")
        // A SIBLING of the row button, never a child: a Button inside a Button never
        // receives its own taps. The rebuild had dropped this control entirely, which
        // silently made every series episode in the app undownloadable.
        DownloadControl(target: .episode(ep, series), size: 18, showPercent: false)
            .frame(width: 44)     // matches the control's own 44pt minimum
        }
    }

    /// The oversized numeral in its own gutter — replaced by a check once watched, so
    /// the state is a GLYPH, not just a tint (colour alone is not an accessible signal).
    private func episodeNumeral(_ ep: Episode, watched: Bool) -> some View {
        ZStack {
            if watched {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.s8kGoldHigh)
            } else {
                Text(s8kEpisodeNumeral(ep.episodeNumber))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.s8kTextPrimary.opacity(0.45))
            }
        }
        .frame(width: 44)
    }

    /// The thumbnail, with the resume state as a rule along ITS bottom edge — not a
    /// separate bar across the whole row.
    private func episodeThumb(_ ep: Episode, progress: Double, watched: Bool) -> some View {
        Color.clear
            .frame(width: 112, height: 63)
            .overlay {
                S8KImage(url: ep.posterURL ?? series.backdropURL ?? series.coverURL,
                         placeholder: "play.tv.fill")
            }
            .overlay(alignment: .bottom) {
                if progress > 0.02 && !watched {
                    // S8KProgressBar, not a GeometryReader: this codebase records that a
                    // GeometryReader per cell forced an extra layout pass on every
                    // visible episode row — real cost with dozens on screen.
                    S8KProgressBar(fraction: progress, track: Color.black.opacity(0.35), height: 3)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
    }
}

// MARK: - 9 · Search

@MainActor
final class SearchVM: ObservableObject {
    @Published var query:   String         = ""
    @Published var results: [SearchResult] = []
    @Published var loading: Bool           = false
    @Published var failed:  Bool           = false
    @Published var recent:  [String]       = []
    @Published var scope:   SearchScope    = .movies

    /// The section the user is searching within (all / movies / series / live).
    /// `.all` (used on Home) searches every content type at once.
    enum SearchScope: String, CaseIterable, Identifiable {
        case all, movies, series, live
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:    return L("search.type.all")
            case .movies: return L("search.type.movie")
            case .series: return L("search.type.series")
            case .live:   return L("search.type.live")
            }
        }
        var icon: String {
            switch self {
            case .all:    return "magnifyingglass"
            case .movies: return "film"
            case .series: return "tv"
            case .live:   return "antenna.radiowaves.left.and.right"
            }
        }
        var prompt: String {
            switch self {
            case .all:    return L("search.all")
            case .movies: return L("search.movies")
            case .series: return L("search.series")
            case .live:   return L("search.live")
            }
        }
    }

    struct SearchResult: Identifiable {
        let id    = UUID()
        let type: ResultType
        let title, subtitle: String
        let imageURL: String?
        enum ResultType {
            case channel(Channel), movie(Movie), series(Series)
            var icon: String {
                switch self { case .channel: return "antenna.radiowaves.left.and.right"
                              case .movie:   return "film"
                              case .series:  return "tv" }
            }
            var label: String {
                switch self { case .channel: return L("search.type.live")
                              case .movie:   return L("search.type.movie")
                              case .series:  return L("search.type.series") }
            }
        }
    }

    private var task: Task<Void, Never>?

    init() { recent = UserDefaults.standard.stringArray(forKey: "s8k.search.recent") ?? [] }

    /// Switch the section and re-run the current query immediately.
    func setScope(_ s: SearchScope) {
        guard s != scope else { return }
        scope = s
        search()
    }

    /// Search ONLY within the selected section, against the real content source
    /// (ContentService → Xtream / M3U in real mode, DemoContent in demo).
    func search() {
        task?.cancel()
        failed = false
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; loading = false; return }
        loading = true
        let scope = self.scope
        task = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)   // debounce
            guard !Task.isCancelled else { return }
            do {
                var r: [SearchResult] = []
                // Fast path: FTS5 (multi-field, diacritic-insensitive, ranked) once the
                // SQLite store is populated for this line. Falls back to the in-memory
                // scan when the store isn't ready (demo, first run, pure-Xtream, or an
                // empty index) — so behaviour is identical until the store fills.
                if let sk = Store.shared.m3uURL, CatalogDB.isSearchable(scope: sk) {
                    // GRDB reads run OFF the main actor (SearchVM is @MainActor).
                    r = await Task.detached(priority: .userInitiated) {
                        SearchVM.ftsResults(q, scope: scope, scopeKey: sk)
                    }.value
                } else {
                    let low = q.lowercased()
                    switch scope {
                    case .all:
                        // Home: search movies + series + channels at once, merged.
                        async let am = (try? await ContentService.movies()) ?? []
                        async let asr = (try? await ContentService.series()) ?? []
                        async let ac = (try? await ContentService.liveStreams()) ?? []
                        let (mm, ss, cc) = await (am, asr, ac)
                        let rm = mm.filter { $0.name.lowercased().contains(low) }.prefix(30).map {
                            SearchResult(type: .movie($0), title: $0.name, subtitle: $0.year ?? "", imageURL: $0.posterURL)
                        }
                        let rs = ss.filter { $0.name.lowercased().contains(low) }.prefix(30).map {
                            SearchResult(type: .series($0), title: $0.name, subtitle: $0.year ?? "", imageURL: $0.coverURL)
                        }
                        let rc = cc.filter { $0.name.lowercased().contains(low) }.prefix(30).map {
                            SearchResult(type: .channel($0), title: $0.name, subtitle: "", imageURL: $0.logoURL)
                        }
                        r = Array(rm) + Array(rs) + Array(rc)
                    case .movies:
                        let m = try await ContentService.movies()
                        r = m.filter { $0.name.lowercased().contains(low) }.prefix(60).map {
                            SearchResult(type: .movie($0), title: $0.name,
                                         subtitle: $0.year ?? "", imageURL: $0.posterURL)
                        }
                    case .series:
                        let s = try await ContentService.series()
                        r = s.filter { $0.name.lowercased().contains(low) }.prefix(60).map {
                            SearchResult(type: .series($0), title: $0.name,
                                         subtitle: $0.year ?? "", imageURL: $0.coverURL)
                        }
                    case .live:
                        let c = try await ContentService.liveStreams()
                        r = c.filter { $0.name.lowercased().contains(low) }.prefix(80).map {
                            SearchResult(type: .channel($0), title: $0.name,
                                         subtitle: "", imageURL: $0.logoURL)
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { self.results = r; self.loading = false; self.saveRecent(q) }
            } catch {
                print("🔎 search failed (scope=\(scope.rawValue)): \(error)")
                await MainActor.run { self.loading = false; self.failed = true; self.results = [] }
            }
        }
    }

    /// FTS-backed results (rank-ordered) for a scope, resolved from the SQLite store.
    /// Word-prefix, multi-field (name/genre/cast/plot/director), diacritic-insensitive.
    /// `nonisolated` so it can run off the main actor (GRDB reads are synchronous).
    nonisolated private static func ftsResults(_ q: String, scope: SearchScope, scopeKey sk: String) -> [SearchResult] {
        func movs(_ limit: Int) -> [SearchResult] {
            CatalogDB.moviesByIds(scope: sk, ids: CatalogDB.search(q, kind: "movie", scope: sk, limit: limit)).map {
                SearchResult(type: .movie($0), title: $0.name, subtitle: $0.year ?? "", imageURL: $0.posterURL)
            }
        }
        func sers(_ limit: Int) -> [SearchResult] {
            CatalogDB.seriesByIds(scope: sk, ids: CatalogDB.search(q, kind: "series", scope: sk, limit: limit)).map {
                SearchResult(type: .series($0), title: $0.name, subtitle: $0.year ?? "", imageURL: $0.coverURL)
            }
        }
        func chans(_ limit: Int) -> [SearchResult] {
            CatalogDB.channelsByIds(scope: sk, ids: CatalogDB.search(q, kind: "live", scope: sk, limit: limit)).map {
                SearchResult(type: .channel($0), title: $0.name, subtitle: "", imageURL: $0.logoURL)
            }
        }
        switch scope {
        case .all:    return movs(30) + sers(30) + chans(30)
        case .movies: return movs(60)
        case .series: return sers(60)
        case .live:   return chans(80)
        }
    }

    private func saveRecent(_ q: String) {
        recent.removeAll { $0 == q }; recent.insert(q, at: 0)
        recent = Array(recent.prefix(8))
        UserDefaults.standard.set(recent, forKey: "s8k.search.recent")
    }
    func clearRecent() { recent = []; UserDefaults.standard.removeObject(forKey: "s8k.search.recent") }
}

extension View {
    /// Cap a block's width, then keep the capped block centred in whatever it was
    /// given. The second frame is what does the centring — the first one alone would
    /// leave the block hugging one edge.
    ///
    /// Deliberately `fileprivate`: it is a local shorthand for a pair of modifiers on
    /// this one screen, not a second width API standing beside `S8KMetrics`.
    fileprivate func s8kCapWidth(_ w: CGFloat) -> some View {
        frame(maxWidth: w).frame(maxWidth: .infinity)
    }
}

struct SearchView: View {
    @Environment(\.s8kMetrics) private var metrics
    var onClose: (() -> Void)? = nil
    @StateObject private var vm = SearchVM()
    @State private var playerItem: ContentItem? = nil
    @State private var showMovie:  Movie?  = nil
    @State private var showSeries: Series? = nil
    @FocusState private var focused: Bool
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    private var isPad: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    // Poster grid: more columns on iPad (wider min) → uses the extra width.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: isPad ? 150 : 108), spacing: 14, alignment: .top)]
    }
    // Cap + center the content block on iPad so the field/results aren't an ugly
    // full-width stretch; full width on iPhone.
    private var contentMaxWidth: CGFloat { isPad ? metrics.readableMaxWidth : .infinity }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 0) {
                    queryBar
                    GoldDivider()
                    resultsPane
                }
                // Hold the query bar against the TOP. Without the alignment the block
                // centres itself vertically the moment the results below it are short.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationBarHidden(true)
        }
        .fullScreenCover(item: $playerItem) { PlayerView(item: $0) }
        .fullScreenCover(item: $showMovie)  { MovieDetailView(movie: $0) }
        .fullScreenCover(item: $showSeries) { SeriesDetailView(series: $0) }
        // Contextual search: open on the section the user came from (set by the
        // tab bar's search button). Applied once on present.
        .onAppear { vm.setScope(AppRouter.shared.searchScope) }
    }

    // MARK: What sits above the divider
    private var queryBar: some View {
        VStack(spacing: 14) {
            titleRow
            queryField
            sectionSelector
        }
        .s8kCapWidth(contentMaxWidth)
        .padding(.horizontal, S8KSpace.xl)
        .padding(.top, 20)
        .padding(.bottom, S8KSpace.lg)
    }

    private var titleRow: some View {
        HStack {
            Text(L("search.title")).font(S8KFont.title1).foregroundColor(.s8kTextPrimary)
            Spacer()
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                // Written with an explicit label so the expansion can live INSIDE it:
                // on the outside it would only widen the layout cell and leave the
                // gesture on the ~44×17 text. 14 down stops exactly at the search
                // field below; a Spacer and the 20pt page margin flank it sideways.
                Text(L("common.close")).s8kMinTouch(h: 12, v: 14)
            }.foregroundColor(.s8kGoldMid).font(S8KFont.subhead)
        }
    }

    private var queryField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(focused ? .s8kGoldMid : .s8kTextDisabled)
                .animation(.easeInOut(duration: 0.2), value: focused)
            TextField("", text: $vm.query,
                     prompt: Text(vm.scope.prompt).foregroundColor(Color.s8kTextDisabled))
                .font(S8KFont.body).foregroundColor(.s8kTextPrimary)
                // Field-scoped and language-driven — same reasoning as SearchField.
                .environment(\.layoutDirection, LocalizationManager.current.isRTL ? .rightToLeft : .leftToRight)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: vm.query) { vm.search() }
            if vm.loading {
                ProgressView().progressViewStyle(.circular).tint(.s8kGoldMid).scaleEffect(0.7)
            } else if !vm.query.isEmpty {
                Button(action: { vm.query = ""; vm.results = []; vm.failed = false }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.s8kTextDisabled)
                        // ~17pt glyph inside a 50pt row; 5 sideways is half the gap to
                        // the text field, so focusing the field still works right up to
                        // the glyph.
                        .s8kMinTouch(h: 5, v: 14)
                }
                    .accessibilityLabel(L("a11y.clear_text"))
            }
        }
        .padding(.horizontal, S8KSpace.lg).frame(height: 50)
        .s8kGlass(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
            .strokeBorder(focused ? Color.s8kGoldMid : Color.s8kBorder, lineWidth: 1.5))
        .animation(.easeInOut(duration: 0.2), value: focused)
    }

    // Segmented section selector (Movies / Series / Live) — active = gold.
    private var sectionSelector: some View {
        HStack(spacing: 8) {
            ForEach(SearchVM.SearchScope.allCases) { sc in
                let active = vm.scope == sc
                Button(action: { vm.setScope(sc) }) {
                    HStack(spacing: 6) {
                        Image(systemName: sc.icon).font(.system(size: 12, weight: .semibold))
                        Text(sc.label).font(S8KFont.caption1.weight(.semibold))
                    }
                    .foregroundColor(active ? .black : .s8kTextSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(active ? AnyShapeStyle(S8KGradient.goldFlat)
                                       : AnyShapeStyle(Color.s8kSurface))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(active ? Color.clear : Color.s8kBorder, lineWidth: 1))
                    .shadow(color: active ? .s8kGoldMid.opacity(0.35) : .clear, radius: 6, y: 2)
                    // ~33 → 45pt tall, after the clip. Vertical only: the three chips
                    // divide the row's width between them with 8pt gaps, so any sideways
                    // growth here is growth into the next chip.
                    .s8kMinTouchV(6)
                }
                .buttonStyle(S8KButtonStyle())
            }
        }
        .animation(.easeInOut(duration: 0.18), value: vm.scope)
    }

    // MARK: What the query is currently showing
    // Five states, and only ever one of them. Naming them makes the precedence
    // explicit and checkable — the old chain of else-ifs had exactly this order, and
    // getting the order wrong is invisible: put `failed` ahead of `prompt` and
    // clearing the field shows an error page; put `noMatches` ahead of `working` and
    // the spinner is replaced by "nothing found" while the search is still running.
    private enum ResultsPhase { case prompt, failed, working, noMatches, matches }

    private var phase: ResultsPhase {
        if vm.query.isEmpty                 { return .prompt    }
        if vm.failed                        { return .failed    }
        if vm.loading && vm.results.isEmpty { return .working   }
        if vm.results.isEmpty               { return .noMatches }
        return .matches
    }

    @ViewBuilder private var resultsPane: some View {
        switch phase {
        case .prompt:
            recentTerms
        case .failed:
            VStack {
                EmptyState(icon: "wifi.exclamationmark",
                           title: L("search.failed.title"), subtitle: L("search.failed.sub"))
                Button(action: { vm.search() }) {
                    Label(L("common.retry"), systemImage: "arrow.clockwise")
                        .font(S8KFont.subhead).foregroundColor(.s8kGoldMid)
                }.buttonStyle(S8KButtonStyle())
            }
        case .working:
            VStack(spacing: 12) {
                Spacer()
                ProgressView().progressViewStyle(.circular).tint(.s8kGoldMid).scaleEffect(1.2)
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noMatches:
            EmptyState(icon: vm.scope.icon, title: L("search.empty.title"), subtitle: L("search.empty.sub"))
        case .matches:
            matchesScroll
        }
    }

    // No query yet → recent searches (if any) or a friendly hint.
    @ViewBuilder private var recentTerms: some View {
        if vm.recent.isEmpty {
            EmptyState(icon: "magnifyingglass", title: L("search.start.title"), subtitle: L("search.start.sub"))
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .trailing, spacing: 12) {
                    HStack {
                        Button(L("search.clear_all")) { vm.clearRecent() }
                            .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kGoldMid)
                        Spacer()
                        Text(L("search.recent")).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                    }
                    ChipWrap(items: vm.recent) { term in
                        Button(action: { vm.query = term; vm.search() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "clock").font(.system(size: 11))
                                Text(term).font(S8KFont.caption1)
                            }
                            .foregroundColor(.s8kTextSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.s8kSurface).clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color.s8kBorder, lineWidth: 1))
                        }
                        .buttonStyle(S8KButtonStyle())
                    }
                }
                .s8kCapWidth(contentMaxWidth)
                .padding(.horizontal, S8KSpace.xl).padding(.vertical, 12)
            }
        }
    }

    // Channels read better as rows (a logo and a name); everything else as posters.
    // NOTE: the two branches are capped with DIFFERENT widths — the row list with
    // this view's own `contentMaxWidth`, the grid with the metric. That is what
    // shipped; it is preserved here rather than quietly unified, and logged.
    private var matchesScroll: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if vm.scope == .live {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.results) { r in
                            matchRow(r)
                            GoldDivider().padding(.leading, 72)
                        }
                    }
                    .s8kCapWidth(contentMaxWidth)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(vm.results) { matchTile($0) }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                    .s8kCapWidth(metrics.contentMaxWidth)
                }
                Color.clear.frame(height: 100)
            }
            .padding(.top, 14)
        }
    }

    private func matchTile(_ r: SearchVM.SearchResult) -> some View {
        Button(action: { present(r) }) {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                    .fill(Color.s8kElevated)
                    .aspectRatio(2.0/3.0, contentMode: .fit)
                    .overlay(S8KImage(url: r.imageURL, placeholder: r.type.icon))
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .strokeBorder(Color.s8kBorder, lineWidth: 1))
                Text(r.title).font(S8KFont.caption1).foregroundColor(.s8kTextPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func matchRow(_ r: SearchVM.SearchResult) -> some View {
        Button(action: { present(r) }) {
            HStack(spacing: 12) {
                S8KImage(url: r.imageURL, placeholder: r.type.icon)
                    .frame(width: 50, height: 50)
                    .background(Color.s8kElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.s8kBorder, lineWidth: 1))
                VStack(alignment: .trailing, spacing: 3) {
                    Text(r.title).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    Text(r.type.label).font(S8KFont.caption3).foregroundColor(.s8kGoldMid)
                }
                Spacer()
                Image(systemName: "chevron.left").font(.system(size: 12)).foregroundColor(.s8kTextDisabled)
            }
            .padding(.horizontal, S8KSpace.xl).padding(.vertical, 12)
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func present(_ r: SearchVM.SearchResult) {
        switch r.type {
        case .channel(let ch): playerItem = .live(ch)
        case .movie(let m):    showMovie  = m
        case .series(let s):   showSeries = s
        }
    }
}

// MARK: - 10 · Chip wrapping

// MARK: Chips that wrap
// A real Layout, because the width has to be a CONSTRAINT and not a guess. The
// version this replaced measured itself from a GeometryReader and aligned by hand;
// it read a width it had not been given, laid rows out against it, and the result
// ran off both edges of the page it was on.
struct ChipWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(items, id: \.self) { content($0) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // `max(…, 1)`: SwiftUI probes layouts with ProposedViewSize.zero. A 0 width
        // would wrap every chip onto its own row and report width 0 — a one-frame
        // collapse of the chip rows.
        let maxW = max(proposal.width ?? .infinity, 1)
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxRowW: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { maxRowW = max(maxRowW, x - spacing); x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        maxRowW = max(maxRowW, x - spacing)
        return CGSize(width: maxW.isFinite ? maxW : maxRowW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
