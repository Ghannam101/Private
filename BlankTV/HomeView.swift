// ============================================================
// BLANK TV — HomeView.swift
// The home feed: its store, the page, and the screens it opens.
// ============================================================

import SwiftUI

// MARK: - De-duplicating and rating-parsing the catalog arrays

// SwiftUI `ForEach` + `.scrollPosition(id:)` REQUIRE unique ids. M3U series hash
// their id from the NAME, so same-titled series (mirrored across categories /
// quality variants — pervasive in IPTV lists) collide on the same id. The old
// `TabView(.page)` hero tolerated that; the new paging ScrollView does NOT and
// crashes. Keep only the first item per id everywhere a ForEach/scrollPosition
// consumes these arrays (hero + Top-10).
func s8kUniqueByID<T>(_ items: [T], _ id: (T) -> String) -> [T] {
    var seen = Set<String>()
    return items.filter { seen.insert(id($0)).inserted }
}
// NaN-safe rating parse: `Double("nan")` returns `.nan`, and a NaN in a `>`
// sort comparator violates strict-weak-ordering → `sorted` traps at runtime.
func s8kRating(_ s: String?) -> Double {
    let d = Double(s ?? "") ?? 0
    return d.isFinite ? d : 0
}

// MARK: - Home feed store — one shared catalog, five derived rows

@MainActor
final class HomeVM: ObservableObject {
    static let shared = HomeVM()

    // MARK: Catalog, exactly as the provider returned it
    @Published var liveChannels:  [Channel]      = []
    @Published var movies:        [Movie]         = []
    @Published var series:        [Series]        = []
    @Published var history:       [WatchHistory]  = []

    // MARK: Rows derived from it, computed once per load
    @Published var heroItems:     [HeroItem]      = []   // mixed swipeable hero (movies + series)
    @Published var topMovies:     [Movie]         = []   // top-rated (ranked rail) — sorted ONCE
    @Published var topSeries:     [Series]        = []   // top-rated series rail — sorted ONCE
    @Published var newMovies:     [Movie]         = []   // recently added (id desc) — sorted ONCE
    @Published var newSeries:     [Series]        = []   // recently added (id desc) — sorted ONCE

    // MARK: Where the load has got to
    @Published var isLoading:     Bool            = true
    @Published var error:         AppError?       = nil
    /// True once a load has COMPLETED at least once for this playlist. It gates the
    /// full-screen skeleton so a pull-to-refresh reloads IN PLACE instead of swapping
    /// the feed — and therefore the refresh control itself — out from under the
    /// user's finger. Cleared by `reset()`, so switching accounts still shows it.
    @Published private(set) var everLoaded = false

    // MARK: Collaborators
    private let hist    = HistoryService.shared
    private let config  = ConfigService.shared
    private var loaded = false
    // Provider category NAMES — the raw material the curated-rail classifier works from.
    private var movieCats:  [Category] = []
    private var seriesCats: [Category] = []

    // MARK: State for the parts that are built but not mounted (see the tail of this class)
    @Published var heroIndex:     Int             = 0
    @Published var doneChannels = false
    @Published var doneMovies   = false
    @Published var doneSeries   = false
    @Published var rails:         [HomeRail]      = []   // curated themed rails (network + genre) — built ONCE
    private var heroDir = 1                              // hero ping-pong direction (ذهاب/عودة)
    private var heroTimer: Timer?

    // MARK: A featured item is one movie or one series
    struct HeroItem: Identifiable {
        enum Kind { case movie(Movie), series(Series) }
        let kind: Kind
        var id: String {
            switch kind { case .movie(let m): return "m_\(m.id)"; case .series(let s): return "s_\(s.id)" }
        }
        var name: String {
            switch kind { case .movie(let m): return m.name; case .series(let s): return s.name }
        }
        var backdropURL: String? {
            switch kind {
            case .movie(let m):  return m.backdropURL ?? m.posterURL
            case .series(let s): return s.backdropURL ?? s.coverURL
            }
        }
        var rating: String? {
            switch kind { case .movie(let m): return m.rating; case .series(let s): return s.rating }
        }
        var genre: String? {
            switch kind { case .movie(let m): return m.genre; case .series(let s): return s.genre }
        }
    }

    // MARK: Loading

    func load(force: Bool = false) async {
        history = Array(hist.items.prefix(8))
        if loaded && !force { return }
        isLoading = true; error = nil
        doneChannels = false; doneMovies = false; doneSeries = false
        await config.fetchIfStale()
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadChannels() }
            g.addTask { await self.loadMovies() }
            g.addTask { await self.loadSeries() }
        }
        loaded = true; everLoaded = true
        rebuildHero()
        // The curated themed feed is deliberately left unbuilt here. Nothing on this
        // page draws it, and assembling it costs a classification pass plus a set of
        // per-category sorts on the main actor and a poster prefetch — all of it thrown
        // away on every single load. Wire the builder back in if that feed is mounted.
        isLoading = false
    }

    func reset() {
        loaded = false; liveChannels = []; movies = []; series = []
        history = []; heroIndex = 0; isLoading = true; error = nil
        doneChannels = false; doneMovies = false; doneSeries = false
        rails = []; movieCats = []; seriesCats = []
        // The DERIVED arrays must be cleared too — MoviesVM/SeriesVM already do this and
        // Home was the outlier. Without it, "add account" / "switch playlist" left
        // `heroItems` populated, so the first-paint check was false from the first frame
        // and Home showed the PREVIOUS line's hero and Top-10 under the new subscription.
        heroItems = []; topMovies = []; topSeries = []; newMovies = []; newSeries = []
        everLoaded = false
    }

    private func loadChannels() async {
        do { liveChannels = try await ContentService.liveStreams() }
        catch { print("channels: \(error)"); noteError(error) }
        doneChannels = true
    }
    private func loadMovies() async {
        // Fetch the category list CONCURRENTLY with the movies (both feed the rail
        // engine); a category-list failure must never fail the movie load.
        async let cats = ContentService.vodCategories()
        do { movies = try await ContentService.movies() }
        catch { print("movies: \(error)"); noteError(error) }
        movieCats = (try? await cats) ?? []
        doneMovies = true
    }
    private func loadSeries() async {
        async let cats = ContentService.seriesCategories()
        do { series = try await ContentService.series() }
        catch { print("series: \(error)"); noteError(error) }
        seriesCats = (try? await cats) ?? []
        doneSeries = true
    }

    /// Record WHY a catalog load failed, so the page can name the reason — an expired
    /// line, a dropped connection — rather than leave the user in front of a blank feed.
    /// A load torn down by a tab remount is not a failure and must not be recorded as
    /// one: doing so painted a warning over content that arrived perfectly on the very
    /// next attempt.
    private func noteError(_ e: Error) {
        guard !Task.isCancelled else { return }
        error = (e as? AppError) ?? .network(e)
    }

    // MARK: Deriving the editorial rows

    /// Build the mixed hero: top-rated movies + top-rated series, interleaved, up to 8.
    func rebuildHero() {
        // Sort ONCE here (not on every SwiftUI render) — re-sorting a large catalog
        // on each body eval was a major source of home jank.
        // SORT INDICES, NOT ELEMENTS. The old comparators parsed a String into a
        // Double/Int on EVERY comparison — twice per compare, ~n·log n compares. On a
        // 30–60k-title line that was 0.4–1.5s of BLOCKED MAIN THREAD right after login,
        // which is what held the half-empty page motionless and made the app read as
        // "just a plain screen".
        // Each key is now parsed ONCE, and only Ints are moved during the sort — so no
        // 224-byte struct with 13 refcounted String fields is ever copied (that would
        // have traded the CPU cost for a ~55MB transient spike, four times over).
        // `.prefix(n*4)` before materialising: we only need 10/20 items, and the extra
        // headroom absorbs any duplicate ids that `s8kUniqueByID` then removes.
        let mRate = movies.map(\.ratingDouble)
        let mByRate: [Int] = movies.indices.sorted { mRate[$0] > mRate[$1] }
        topMovies = Array(s8kUniqueByID(mByRate.prefix(40).map { movies[$0] }, { $0.id }).prefix(10))

        let sRate = series.map { s8kRating($0.rating) }
        let sByRate: [Int] = series.indices.sorted { sRate[$0] > sRate[$1] }
        topSeries = Array(s8kUniqueByID(sByRate.prefix(40).map { series[$0] }, { $0.id }).prefix(10))

        // "Recently added" ≈ highest Xtream id (ids auto-increment, so newest last).
        let mID = movies.map { Int($0.id) ?? 0 }
        let mByID: [Int] = movies.indices.sorted { mID[$0] > mID[$1] }
        newMovies = mByID.prefix(20).map { movies[$0] }

        let sID = series.map { Int($0.id) ?? 0 }
        let sByID: [Int] = series.indices.sorted { sID[$0] > sID[$1] }
        newSeries = sByID.prefix(20).map { series[$0] }

        // Hero features the NEWEST content (movies + series interleaved) — it refreshes
        // as fresh titles arrive on reload. (Owner: hero tracks new movies/series.)
        let hM = newMovies.prefix(4).map { HeroItem(kind: .movie($0)) }
        let hS = newSeries.prefix(4).map { HeroItem(kind: .series($0)) }
        var out: [HeroItem] = []
        for i in 0..<max(hM.count, hS.count) {
            if i < hM.count { out.append(hM[i]) }
            if i < hS.count { out.append(hS[i]) }
        }
        heroItems = Array(s8kUniqueByID(out, { $0.id }).prefix(8))
        if heroIndex >= heroItems.count { heroIndex = 0 }
        heroDir = 1

        // Prefetch hero backdrops so swiping is smooth (image decode was the jank).
        S8KImageCache.shared.prefetch(heroItems.compactMap { $0.backdropURL }, maxPixel: 1400)
    }

    // MARK: Built, kept, not currently mounted
    //
    // Nothing below is reached today. It is kept, not deleted, because each piece is a
    // finished feature waiting on a decision rather than an experiment: removing them is
    // an owner call, not a refactor. None of them runs, so none of them can misbehave —
    // but `heroIndex` above is a landmine to respect: it is a @Published index on the
    // SHARED store, and the moment a timer drives it again every section of this page
    // re-renders on that timer. That is precisely the defect the hero carousel was
    // extracted to fix, so read the note above `HeroCarouselView` before rewiring it.

    /// The concurrent boot load: channels, movies and series in flight together, each
    /// raising its own progress flag as it lands, so the wait is the slowest request
    /// rather than the sum of the three.
    ///
    /// It belonged to the full-screen post-login loading page, which no longer exists —
    /// signing in now lands straight on the app and each tab fills in behind its own
    /// placeholder. This page's `.task` calls `load()`, so nothing calls this.
    func bootLoad() async {
        if loaded { doneChannels = true; doneMovies = true; doneSeries = true; return }
        await config.fetchIfStale()
        async let c: Void = loadChannels()
        async let m: Void = loadMovies()
        async let s: Void = loadSeries()
        _ = await (c, m, s)
        history = Array(hist.items.prefix(8))
        loaded = true; everLoaded = true
        rebuildHero()
        isLoading = false
    }

    /// Assemble the curated themed rails once — by network and by genre — from the
    /// loaded catalog and the provider's own category names, then warm the first rows'
    /// posters so the feed paints without a stutter on the first scroll.
    func rebuildRails() {
        rails = RailEngine.build(movies: movies, movieCats: movieCats,
                                 series: series, seriesCats: seriesCats)
        let firstPosters: [String] = rails.prefix(3).flatMap { rail -> [String] in
            switch rail.kind {
            case .movie(let a):  return a.prefix(6).compactMap { $0.posterURL }
            case .series(let a): return a.prefix(6).compactMap { $0.coverURL }
            }
        }
        S8KImageCache.shared.prefetch(firstPosters, maxPixel: 400)
    }

    func startHeroTimer() {
        heroTimer?.invalidate() // avoid stacking timers on every onAppear
        heroTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            // Capture weak INSIDE the Task (not a strong rebind outside) so the
            // concurrent closure never captures a strong self — Swift-6-safe.
            Task { @MainActor [weak self] in
                guard let self, self.heroItems.count > 1 else { return }
                // Ping-pong (ذهاب/عودة): reverse at the ends instead of a jarring
                // wrap from the last card back to the first.
                if self.heroIndex >= self.heroItems.count - 1 { self.heroDir = -1 }
                else if self.heroIndex <= 0 { self.heroDir = 1 }
                withAnimation(.easeInOut(duration: 0.6)) {
                    self.heroIndex += self.heroDir
                }
            }
        }
    }

    func stopHeroTimer() {
        heroTimer?.invalidate()
        heroTimer = nil
    }
}

// MARK: - The home page

struct HomeView: View {
    @StateObject private var vm     = HomeVM.shared
    @StateObject private var config = ConfigService.shared
    @StateObject private var theme  = AppTheme.shared
    @StateObject private var auth   = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @ObservedObject private var bars = BarVisibility.shared   // drives the top bar's glass on scroll
    @ObservedObject private var router = AppRouter.shared     // global in-place search (Home = all)
    @StateObject private var searchVM = SearchVM()            // Home all-content search results
    @Environment(\.horizontalSizeClass) private var hSize
    /// The canonical layout metrics (window + size classes), injected once by
    /// S8KMetricsRoot around the TabView. Never re-derive a size locally.
    @Environment(\.s8kMetrics) private var metrics

    // ONE value drives ONE presentation. SwiftUI reliably honours a single
    // .fullScreenCover per view, and while this page also carried a .sheet the two
    // fought each other: the sheet was swallowed outright, so the bell opened nothing
    // at all. Every screen that covers the feed now travels through the route below,
    // which leaves no second presenter to conflict with.
    @State private var route: HomeRoute? = nil
    @State private var editingHistory = false   // long-press → reveal ✕ on history cards
    @State private var refreshing = false           // content refresh in progress
    @State private var showRefreshConfirm = false   // confirm before a heavy reload

    /// Everything this page can put over itself, as one value.
    enum HomeRoute: Identifiable {
        case play(ContentItem)
        case movieDetail(Movie)
        case seriesDetail(Series)
        case channelCard(Channel)
        case watchHistory

        var id: String {
            switch self {
            case .play(let item):      return "play:\(item.id)"
            case .movieDetail(let m):  return "movie:\(m.id)"
            case .seriesDetail(let s): return "series:\(s.id)"
            case .channelCard(let ch): return "channel:\(ch.id)"
            case .watchHistory:        return "history"
            }
        }
    }

    var body: some View {
        // This page presents; it never pushes. An enclosing NavigationStack — with the
        // deprecated hidden-bar modifier on it — left a bar that still RESERVED the top
        // band, and on iOS 17 that invisible layer quietly absorbed taps aimed at the
        // controls floating there, but only once real content grew tall enough to scroll
        // underneath it. There is no stack here, so there is nothing left to absorb them.
        //
        // The reader below measures exactly one thing: the safe-area inset the pinned
        // bar needs. It is the page root — the single placement where reading geometry
        // is safe — and its value never feeds a width, so it can collapse nothing.
        GeometryReader { geo in
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                // The full-page placeholder is for the FIRST paint only. A refresh or a
                // retry that already has something to draw reloads underneath the user
                // rather than blanking the screen out from under them.
                if isFirstPaint {
                    firstPaintPlaceholder.transition(.opacity)
                } else {
                    feed.transition(.opacity)
                }
            }
            // The bar is an OVERLAY, never a scroll child, and it is positioned from the
            // measured inset — not from a bare top padding. That shortcut has cost this
            // project twice: an `.ignoresSafeArea()` child inflates the ZStack to the
            // whole screen, so "top" becomes the PHYSICAL top and the wordmark and avatar
            // land in the status bar around the Dynamic Island.
            .overlay(alignment: .top) {
                S8KPinnedPageBar(topInset: geo.safeAreaInsets.top) { pinnedBarContent }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isFirstPaint)
        .task { await vm.load() }
        // The hero paces and pauses itself from inside HeroCarouselView, so this page
        // drives no timer that could re-render the whole feed every few seconds.
        .fullScreenCover(item: $route) { screen(for: $0) }
        // A confirm in the app's own black-and-gold, the same component the destructive
        // actions in Settings use, rather than a system alert.
        .overlay {
            if showRefreshConfirm {
                S8KConfirm(icon: "arrow.clockwise", iconColor: .s8kGoldMid,
                           title: L("refresh.title"), message: L("refresh.msg"),
                           confirmTitle: L("refresh.confirm"),
                           onConfirm: {
                               withAnimation { showRefreshConfirm = false }
                               refreshing = true
                               Task { await auth.refreshContent(); refreshing = false }
                           },
                           onCancel: { withAnimation { showRefreshConfirm = false } })
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showRefreshConfirm)
        // Home searches EVERYTHING (owner #6). The field itself belongs to the tab bar
        // above this page; here we only mirror its text into the search store and lay
        // the results over the feed while it is active.
        .onChange(of: router.searchActive) { _, active in
            if active { searchVM.scope = .all }
            else { searchVM.query = ""; searchVM.results = [] }
        }
        .onChange(of: router.searchText) { _, q in searchVM.query = q; searchVM.search() }
        .overlay { searchLayer }
        .animation(.easeInOut(duration: 0.2), value: router.searchActive)
    }
}

// MARK: - Home · what a tap opens

private extension HomeView {

    /// The one place a route becomes a screen.
    @ViewBuilder
    func screen(for target: HomeRoute) -> some View {
        switch target {
        case .play(let item):      PlayerView(item: item, channels: vm.liveChannels)
        case .movieDetail(let m):  MovieDetailView(movie: m)
        case .seriesDetail(let s): SeriesDetailView(series: s)
        case .channelCard(let ch): ChannelCardSheet(channel: ch) { route = .play(.live(ch)) }
        case .watchHistory:
            WatchHistoryPage(items: vm.history,
                             onDismiss:   { route = nil },
                             onOpen:      { openFromHistory($0); route = nil },
                             onRemove:    { dropFromHistory($0) },
                             onRemoveAll: { dropAllHistory(); route = nil })
        }
    }

    /// The search results, laid over the feed while the tab bar's field is active.
    @ViewBuilder
    var searchLayer: some View {
        if router.searchActive {
            HomeSearchOverlay(vm: searchVM,
                              onMovie:   { route = .movieDetail($0) },
                              onSeries:  { route = .seriesDetail($0) },
                              onChannel: { route = .channelCard($0) })
                .transition(.opacity)
        }
    }

    func openFeatured(_ item: HomeVM.HeroItem) {
        switch item.kind {
        case .movie(let m):  route = .movieDetail(m)
        case .series(let s): route = .seriesDetail(s)
        }
    }

    /// Pick up something the user was part-way through, by finding it again in the
    /// catalog that is currently loaded.
    func openFromHistory(_ item: WatchHistory) {
        switch item.contentType {
        case .live:
            if let ch = vm.liveChannels.first(where: { $0.id == item.contentID }) {
                route = .play(.live(ch))
            }
        case .movie:
            if let m = vm.movies.first(where: { $0.id == item.contentID }) {
                route = .movieDetail(m)
            }
        case .episode:
            // An episode has no page of its own here — land on its parent series when
            // we can identify one.
            if let s = vm.series.first(where: { item.contentName.hasPrefix($0.name) }) {
                route = .seriesDetail(s)
            }
        }
    }

    func dropFromHistory(_ item: WatchHistory) {
        HistoryService.shared.remove(item.id)
        withAnimation { vm.history.removeAll { $0.id == item.id } }
    }

    func dropAllHistory() {
        HistoryService.shared.clear()
        withAnimation { vm.history = []; editingHistory = false }
    }
}

// MARK: - Home · the feed, in the order it is drawn

private extension HomeView {

    var feed: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroRow
                railColumn
            }
            // Planted on the CONTENT, not the ScrollView: the probe walks UP to find
            // the UIScrollView, and on the ScrollView itself it lands as a sibling
            // behind it and clears nothing.
            .s8kInstantTaps()
        }
        // Without a bounce there is no over-scroll, and with no over-scroll there is no
        // stretch. Movies/Series already declare it; Home was relying on `.refreshable`.
        .scrollBounceBehavior(.always)
        // force: without it `loaded == true` makes pull-to-refresh a silent no-op.
        .refreshable { await vm.load(force: true) }
        // Drive the floating menu (collapse on scroll) + the top bar glass (frost on scroll).
        .reportsScrollToTabBar()
        // Hero runs full-bleed UNDER the status bar; the top bar is a top OVERLAY
        // (see `body`), hit-tested independently so its taps are always live.
        .ignoresSafeArea(edges: .top)
        .s8kNoScrollEdgeEffect()
    }

    /// Everything below the hero. Order here IS the order on screen: what the user was
    /// watching, the two ranked rows, the two freshly-added rows, live, then contact.
    var railColumn: some View {
        VStack(spacing: 0) {
            if catalogUnavailable { catalogErrorCard }
            resumeRow
            rankedRows
            newMoviesRow
            newSeriesRow
            liveRow
            contactRow
            // Clears the floating tab puck (its height, its gap and the home indicator);
            // a smaller number left the contact buttons underneath it.
            Color.clear.frame(height: metrics.bottomClearance)
        }
        // Only the RAILS are capped and centred on a wide window. Left to run edge to
        // edge they read as a phone layout pulled apart rather than an iPad layout.
        .frame(maxWidth: metrics.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    /// The carousel is its own view (below) so its rotation re-renders the hero alone.
    /// It is paused whenever the hero is not the thing the user is looking at.
    ///
    /// The height comes from the one canonical formula. Home, Movies and Series each
    /// carried a near-identical copy that disagreed with the others, and two of those
    /// produced a hero TALLER THAN THE VIEWPORT — a small phone in portrait at 78% of
    /// the screen, and every phone in landscape. `S8KMetrics.heroHeight` adds the term
    /// they all lacked: a ceiling that guarantees the next row still peeks.
    ///
    /// The hero stays FULL-BLEED: inside the capped rail column a wide window rested it
    /// between black bars, and because a frame does not clip, the stretch then grew out
    /// of the column into those bars and snapped back.
    @ViewBuilder
    var heroRow: some View {
        if !vm.heroItems.isEmpty {
            HeroCarouselView(items: vm.heroItems, height: metrics.heroHeight,
                             paused: route != nil || router.searchActive
                                     || router.homeSheet != nil || router.tab != .home,
                             onOpen: openFeatured)
                // The stretch itself lives INSIDE the card, on the artwork only
                // (see heroCard) — scaling the whole card also inflated the title and
                // pushed the controls off-screen.
                .frame(height: metrics.heroHeight)
        } else {
            // With no hero, reserve what the pinned bar occupies. Otherwise the first
            // row begins at physical y=0 beneath the bar and can never be scrolled into
            // view — it is already at the very top of the content. Movies and Series
            // have reserved it since they were built; Home never did.
            // safeTop + 66, not the shared compact reserve: this page's bar is taller —
            // a 48pt avatar with 8 above and 10 below — and 62 left the first row a few
            // points under the frosted strip.
            Color.clear.frame(height: metrics.safeTop + 66)
        }
    }

    @ViewBuilder
    var resumeRow: some View {
        if !vm.history.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    if editingHistory {
                        Button(action: { dropAllHistory() }) {
                            Label(L("home.clear_all"), systemImage: "trash")
                                .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kRed)
                                // ~16pt of text → 40pt. 12 is the ceiling downward: the
                                // card rail starts 12pt below and would take the touch.
                                .s8kMinTouch(h: 12, v: 12)
                        }
                        Spacer()
                        Button(action: { withAnimation { editingHistory = false } }) {
                            Text(L("common.done")).font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kGoldMid)
                                .s8kMinTouch(h: 12, v: 12)   // see the note above
                        }
                    } else {
                        Button(action: { route = .watchHistory }) {
                            HStack(spacing: 3) {
                                Text(L("home.see_all")).font(S8KFont.caption1.weight(.semibold))
                                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.s8kGoldMid)
                            .s8kMinTouch(h: 12, v: 12)       // see the note above
                        }
                        Spacer()
                        Text(L("home.continue")).font(S8KFont.headline).foregroundColor(.s8kTextPrimary)
                    }
                }
                .padding(.horizontal, S8KSpace.xl)
                .padding(.bottom, S8KSpace.md)
                .padding(.top, S8KSpace.lg)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.history) { item in
                            resumeCard(item)
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                }
            }
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    func resumeCard(_ item: WatchHistory) -> some View {
        ZStack(alignment: .topLeading) {
            Button(action: {
                if editingHistory { withAnimation { editingHistory = false } }
                else { openFromHistory(item) }
            }) {
                resumeCardFace(item)
            }
            .buttonStyle(S8KButtonStyle())
            // Edit mode used to be a SECOND long-press recogniser on this same button.
            // .contextMenu is itself built on a long press, so ONE hold fired both: the
            // row entered edit mode AND the menu opened over it, leaving whichever path
            // the user did not take half-applied. A hold now does one thing, and edit
            // mode moves into the menu where it is still one gesture away.
            .contextMenu {
                Button(role: .destructive) { dropFromHistory(item) } label: {
                    Label(L("home.remove_history"), systemImage: "trash")
                }
                Button { withAnimation(.spring(response: 0.3)) { editingHistory = true } } label: {
                    Label(L("home.edit"), systemImage: "pencil")
                }
            }

            // In edit mode each card grows its own delete affordance in the corner.
            if editingHistory {
                Button(action: { dropFromHistory(item) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.s8kRed).clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        // 24 → 44pt, after the clip. The badge sits 7pt inside the card's
                        // corner, so the extra area is mostly the card underneath — and
                        // in edit mode the card only leaves edit mode, while a missed tap
                        // here is a delete that never happened.
                        .s8kMinTouch(10)
                }
                .buttonStyle(S8KButtonStyle())
                .padding(7)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(L("home.remove_history"))
            }
        }
    }

    func resumeCardFace(_ item: WatchHistory) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            resumeThumb(item)

            Text(item.contentName)
                .font(S8KFont.caption1.weight(.semibold))
                .foregroundColor(.s8kTextPrimary)
                .lineLimit(1)
                .frame(width: 220, alignment: .trailing)

            Text("\(Int(item.progress * 100))% \(L("home.percent_done"))")
                .font(S8KFont.caption2)
                .foregroundColor(.s8kTextTertiary)
                .frame(width: 220, alignment: .trailing)
        }
    }

    /// Artwork, the centre glyph and how far in they got — one fixed-size tile.
    func resumeThumb(_ item: WatchHistory) -> some View {
        ZStack(alignment: .bottom) {
            S8KImage(url: item.posterURL, placeholder: "play.fill")
                .frame(width: 220, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))

            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: "play.fill")
                    .font(.system(size: 14)).foregroundColor(.white).offset(x: 1))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))

            S8KProgressBar(fraction: item.progress, track: Color.white.opacity(0.15))
        }
        .frame(width: 220, height: 124)
    }

    /// The two ranked rows — hollow numerals with the poster overlapping them, off the
    /// arrays the store sorted ONCE.
    var rankedRows: some View {
        VStack(spacing: 0) {
            if !vm.topMovies.isEmpty {
                RankRail(title: L("home.top_movies"),
                         cells: vm.topMovies.enumerated().map { ($0.offset + 1, $0.element.id, $0.element.posterURL, $0.element.rating, $0.element.year) }) { id in
                    if let m = vm.topMovies.first(where: { $0.id == id }) { route = .movieDetail(m) }
                }
            }
            if !vm.topSeries.isEmpty {
                RankRail(title: L("home.top_series"),
                         cells: vm.topSeries.enumerated().map { ($0.offset + 1, $0.element.id, $0.element.coverURL, $0.element.rating, $0.element.year) }) { id in
                    if let s = vm.topSeries.first(where: { $0.id == id }) { route = .seriesDetail(s) }
                }
                .padding(.bottom, S8KSpace.md)
            }
        }
    }

    /// Freshly added films, newest Xtream id first.
    @ViewBuilder
    var newMoviesRow: some View {
        if !vm.newMovies.isEmpty {
            VStack(spacing: 0) {
                SectionHeader(title: L("home.new_movies")) { BarVisibility.shared.pageChanged(); AppRouter.shared.tab = .movies }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.newMovies) { m in
                            ContentCard(title: m.name, subtitle: m.year,
                                        imageURL: m.posterURL) { route = .movieDetail(m) }
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                }
            }
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    /// Freshly added series, same ordering.
    @ViewBuilder
    var newSeriesRow: some View {
        if !vm.newSeries.isEmpty {
            VStack(spacing: 0) {
                SectionHeader(title: L("home.new_series")) { BarVisibility.shared.pageChanged(); AppRouter.shared.tab = .series }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.newSeries) { s in
                            ContentCard(title: s.name, subtitle: s.year,
                                        imageURL: s.coverURL) { route = .seriesDetail(s) }
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                }
            }
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    @ViewBuilder
    var liveRow: some View {
        if !vm.liveChannels.isEmpty {
            VStack(spacing: 0) {
                SectionHeader(title: L("home.live_now"), count: vm.liveChannels.count) { BarVisibility.shared.pageChanged(); AppRouter.shared.tab = .live }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.liveChannels.prefix(20)) { ch in
                            ChannelChip(name: ch.name, logoURL: ch.logoURL, isLive: true) {
                                route = .play(.live(ch))
                            }
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                }
            }
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    /// How the user reaches a human — and, only where Apple's rules allow it, the
    /// operator's own store.
    @ViewBuilder
    var contactRow: some View {
        VStack(spacing: 10) {
            // Renew links to an external store → only on platforms where Apple's
            // 3.1.1 rule does not apply (never shown in the iOS build).
            if AppCompliance.allowsExternalPurchaseLinks, let store = config.appConfig.storeURL {
                Button(action: { if let u = URL(string: store) { UIApplication.shared.open(u) } }) {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill").font(.system(size: 15))
                        Text(L("sub.renew"))
                            .font(S8KFont.headline)
                        Spacer()
                        Image(systemName: "chevron.left").font(.system(size: 12))
                    }
                    .foregroundColor(.s8kGoldHigh)
                    .padding(.horizontal, S8KSpace.xl).padding(.vertical, 15)
                    .background(Color.s8kGoldMid.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                        .strokeBorder(Color.s8kBorderGold, lineWidth: 1))
                }
                .buttonStyle(S8KButtonStyle())
            }
            HStack(spacing: 10) {
                if let wa = config.appConfig.supportWhatsApp {
                    contactButton(L("home.whatsapp"), icon: "message.fill", color: .s8kGreen) {
                        if let u = URL(string: "https://wa.me/\(wa)") { UIApplication.shared.open(u) }
                    }
                }
                if let tg = config.appConfig.supportTelegram {
                    contactButton(L("home.telegram"), icon: "paperplane.fill", color: .s8kBlue) {
                        if let u = URL(string: tg) { UIApplication.shared.open(u) }
                    }
                }
            }
        }
        .padding(.horizontal, S8KSpace.xl)
    }

    func contactButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(S8KFont.subhead)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                .strokeBorder(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: - Home · the pinned identity bar

private extension HomeView {

    /// Floats over the hero: the avatar on the left opens Settings, the wordmark sits on
    /// the right. Transparent over the poster at rest, frosting to glass once scrolled.
    var pinnedBarContent: some View {
        HStack {
            HStack(spacing: 9) {
                BrandLogo(size: 30).shadow(color: .s8kGoldHigh.opacity(0.25), radius: 6)
                S8KWordmark(size: 17)
            }
            Spacer(minLength: 8)
            accountButton
        }
        .padding(.horizontal, S8KSpace.xl)
        // Home was the ONLY page with no top inset: the 48pt avatar sat flush against
        // the safe-area top — right under the status bar on a home-button iPhone.
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            if bars.scrolled {
                // Elegant frosted glass (owner: the "ثلجي" look). The earlier solid
                // `s8kBlack.opacity` read GREEN because s8kBlack is the deep-green
                // brand base — a material stays neutral. It's only the small top-bar
                // strip (not a full-bleed layer), so the blur cost is negligible.
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.18))
                    .overlay(GoldDivider(), alignment: .bottom)
                    // NOT .ignoresSafeArea: the host (S8KPinnedPageBar) already ignored
                    // the top, so there is no region left to expand into and the frost
                    // would start below the status bar with a visible hard seam.
                    // A negative padding inside a `.background` cannot affect layout.
                    .padding(.top, -400)
                    // Decorative: without this the frosted strip swallowed every flick
                    // started in the top band — and users flick from the top constantly.
                    .allowsHitTesting(false)
            }
            // (no `else` gradient: the at-rest scrim now comes from S8KPinnedPageBar, so
            //  the two no longer stack into a doubly-dark band over the hero)
        }
    }

    /// The "المجسم" avatar. Opens Settings for now — the full profile page is M6.
    /// A material circle, so its tap is never swallowed by what it sits on.
    var accountButton: some View {
        Button {
            BarVisibility.shared.pageChanged()
            AppRouter.shared.tab = .settings
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.s8kGoldHigh)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(S8KButtonStyle())
        .accessibilityLabel(L("tab.settings"))
    }
}

// MARK: - Home · first paint, and the card shown when nothing loads

private extension HomeView {

    /// A load is genuinely in flight AND there is nothing at all to draw yet.
    ///
    /// All three terms carry weight. Drop `heroItems.isEmpty` and the placeholder is
    /// torn down the instant the movies array lands — but every row on this page is
    /// built by `rebuildHero()`, which runs only after ALL three loads finish, so the
    /// user gets a black screen until the slowest one returns. Drop `isLoading` and the
    /// condition never ends: if all three fail — an expired line, no network, a provider
    /// with no VOD — the shimmer runs forever and the error card and pull-to-refresh,
    /// which both live inside `feed`, are unreachable. `load()` always clears
    /// `isLoading` at the end, so this cannot get stuck.
    ///
    /// And deliberately NOT `&& liveChannels.isEmpty`: all three loaders await the same
    /// single-flight playlist fetch and resume together, and the channel load has no
    /// second await — so channels always land first, and adding that term used to tear
    /// the placeholder down while the hero and every row were still empty, leaving a
    /// black page with one strip of chips for the whole time the catalog was sorting.
    var isFirstPaint: Bool {
        vm.isLoading && vm.heroItems.isEmpty && !vm.everLoaded
    }

    /// A home-SHAPED shimmer — a hero block over three rows — rather than a lone
    /// spinner, so the first frame already has the geometry of the real page.
    var firstPaintPlaceholder: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Full-bleed, exactly like the real hero. Inside the rail cap it was a
                // 900-wide grey block replaced by a full-width poster — a visible width
                // pop on every wide-window load.
                SkeletonBlock(cornerRadius: 0).frame(height: metrics.heroHeight)
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in placeholderRow }
                    Color.clear.frame(height: 60)
                }
                .frame(maxWidth: metrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
        }
        // The bar is the shared overlay in `body`; this just runs full-bleed under it,
        // matching the loaded layout.
        .ignoresSafeArea(edges: .top)
        .s8kNoScrollEdgeEffect()   // match `feed`, or iOS 26 dims only the placeholder
    }

    var placeholderRow: some View {
        VStack(alignment: .trailing, spacing: S8KSpace.sm) {
            SkeletonBlock(cornerRadius: 4)
                .frame(width: 150, height: 18)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, S8KSpace.xl)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonBlock(cornerRadius: S8KRadius.md)
                            .frame(width: 118, height: 166)
                    }
                }
                .padding(.horizontal, S8KSpace.xl)
            }
        }
        .padding(.top, S8KSpace.lg)
        .padding(.bottom, S8KSpace.xxl)
    }

    /// A load failed AND not one section has anything in it. A partial catalog still
    /// draws; this is only for the case where the user would otherwise be left with an
    /// empty page, no reason given and no way to try again.
    var catalogUnavailable: Bool {
        vm.error != nil && vm.liveChannels.isEmpty && vm.movies.isEmpty && vm.series.isEmpty
    }

    var catalogErrorCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30)).foregroundColor(.s8kGoldHigh)
            Text(L("home.content_error.title"))
                .font(S8KFont.headline).foregroundColor(.s8kTextPrimary)
            Text(vm.error?.errorDescription ?? L("home.content_error.sub"))
                .font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                .multilineTextAlignment(.center)
            Button(action: { Task { await vm.load(force: true) } }) {
                Label(L("common.retry"), systemImage: "arrow.clockwise")
                    .font(S8KFont.subhead).foregroundColor(.black)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(S8KGradient.goldFlat).clipShape(Capsule())
            }
            .buttonStyle(S8KButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
            .strokeBorder(Color.s8kBorderGold, lineWidth: 1))
        .padding(.horizontal, S8KSpace.xl)
        .padding(.vertical, S8KSpace.lg)
    }
}

// MARK: - Editorial rows reused by the movie and series pages

// The carousel is a view of its own so its 5-second rotation re-renders the hero and
// NOTHING else. It used to advance a @Published index on the shared store that this
// page observed, so every tick re-evaluated the ranked rows, the film rows, the series
// rows and live — a primary source of the reported scroll and animation jank. Page
// index and timer are local here, and so is the favourites service it observes, so a
// heart toggle no longer invalidates the feed either.
// Used by Home, Movies and Series alike.
struct HeroCarouselView: View {
    let items: [HomeVM.HeroItem]
    let height: CGFloat
    /// True while a detail/player cover is open above Home — pause the rotation
    /// so we don't animate an off-screen carousel.
    let paused: Bool
    let onOpen: (HomeVM.HeroItem) -> Void

    @ObservedObject private var favs = FavoritesService.shared
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.s8kMetrics) private var metrics
    @State private var currentID: String?   // the visible page's item id (drives dots + auto-rotate)
    @State private var dir = 1               // ping-pong direction (ذهاب/عودة)
    // @State, not `let`: this is a struct, so a `let` publisher was RE-CREATED on every
    // body pass. `.onReceive` then saw a new publisher identity, cancelled the old
    // subscription and restarted the 5s countdown from zero — so the hero only ever
    // rotated when Home sat completely idle, and looked broken whenever anything else
    // on the screen published.
    @State private var ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    // A paging horizontal ScrollView (NOT TabView.page): a `.page` TabView nested
    // in a vertical ScrollView swallows vertical drags, so the user could only
    // swipe posters and never scroll the Movies/Series feed (owner #1). The iOS 17
    // paging scroll composes orthogonally with the parent vertical scroll — a
    // horizontal swipe pages the hero, a vertical swipe scrolls the page.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    heroCard(item)
                        .containerRelativeFrame(.horizontal)   // one page = container width
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .frame(height: height)
        // The stretch now lives INSIDE this scroll view (on the artwork of each card),
        // and a ScrollView clips its content by default — so everything the pull-down
        // grew above the card's top edge was being thrown away and the black tear came
        // back. Un-clip, then re-clip on the HORIZONTAL axis only (a bottom-anchored
        // scaled rectangle), so the artwork can grow upward while the neighbouring page
        // still cannot bleed in from the side while it is scaled.
        .scrollClipDisabled()
        .clipShape(Rectangle().scale(x: 1, y: 4, anchor: .bottom))
        .onReceive(ticker) { _ in advance() }
        .onAppear { if currentID == nil { currentID = items.first?.id } }
        .onChange(of: items.map(\.id)) { _, ids in
            if currentID == nil || !ids.contains(currentID!) { currentID = ids.first }
        }
    }

    // Auto-rotate: ping-pong to the neighbouring page. Skipped while a cover is
    // open. Manual scrolling updates `currentID` natively via `scrollPosition`.
    private func advance() {
        guard !paused, items.count > 1,
              let cur = currentID, let idx = items.firstIndex(where: { $0.id == cur }) else { return }
        if idx >= items.count - 1 { dir = -1 } else if idx <= 0 { dir = 1 }
        let next = max(0, min(items.count - 1, idx + dir))
        withAnimation(.easeInOut(duration: 0.6)) { currentID = items[next].id }
    }

    /// The hero headline. Was a flat 32pt everywhere, which reads oversized over two
    /// lines of Arabic on a phone (owner-reported). Scaled by window class so a large
    /// iPad window still carries the weight the layout was designed around.
    private var heroTitleSize: CGFloat {
        switch metrics.cls {
        case .compactNarrow:                 return 23
        case .compactRegular, .compactWide:  return 26
        case .regularMedium:                 return 28
        case .regularLarge, .regularXL:      return 32
        }
    }

    private func heroCard(_ item: HomeVM.HeroItem) -> some View {
        ZStack(alignment: .bottom) {
            // ONLY the artwork + its scrim stretch. The modifier used to wrap the whole
            // card, so a pull-down also scaled the title, the ★, the play/favourite
            // buttons and the page dots — the 32pt Arabic title inflated to ~39pt and the
            // right-aligned controls were pushed past the screen edge and clipped. And
            // because a visual effect is render-only, those buttons stayed tappable where
            // they used to be, not where they were drawn.
            ZStack {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    // alignment: .top biases the CROP upward. The artwork is scaled to
                    // fill, so something must be cut; centred, it ate the top of portrait
                    // art — where the subject sits. Anchoring at the top keeps it and
                    // crops the bottom, where the scrim already is.
                    .overlay(alignment: .top) {
                        // Start the artwork BELOW the system's reserved strip. It used
                        // to run to the physical top, so the status bar, the Dynamic
                        // Island and the pinned bar were all drawn over the part of a
                        // poster that carries the subject and the title. The band left
                        // above is the page background, which is what the bar should sit
                        // on. `alignment: .top` still biases the crop upward from there.
                        VStack(spacing: 0) {
                            Color.clear.frame(height: metrics.safeTop)
                            S8KImage(url: item.backdropURL, placeholder: "film",
                                     maxPixel: s8kHeroPixels(metrics.cls.isCompact))
                        }
                    }
                    .clipped()
                LinearGradient(
                    stops: [
                        .init(color: .s8kBlack,              location: 0.0),
                        .init(color: .s8kBlack.opacity(0.6), location: 0.28),
                        .init(color: .clear,                 location: 0.60),
                        .init(color: .s8kBlack.opacity(0.5), location: 1.0)
                    ],
                    startPoint: .bottom, endPoint: .top)
                    .frame(height: height)
                    .allowsHitTesting(false)
            }
            .s8kStretchyHeader()
            // Clip each CARD to its own width: the stretch scales x and y uniformly, so
            // without this the neighbouring page slid ~39pt in from the side during a
            // pull. Bottom-anchored and tall, so the upward growth still survives.
            .clipShape(Rectangle().scale(x: 1, y: 4, anchor: .bottom))

            VStack(alignment: .trailing, spacing: 11) {
                HStack(spacing: 6) {
                    heroChip(L("home.featured"), isGold: true)
                    heroChip(L("home.new_tag"), color: .s8kBlue)
                }
                Text(item.name).font(.system(size: heroTitleSize, weight: .black)).foregroundColor(.s8kTextPrimary)
                    .lineLimit(2).multilineTextAlignment(.trailing)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                RoundedRectangle(cornerRadius: 2)
                    .fill(S8KGradient.goldFlat)
                    .frame(width: 52, height: 4)
                    .shadow(color: .s8kGoldHigh.opacity(0.6), radius: 5)
                HStack(spacing: 8) {
                    if let r = item.rating, let rv = Double(r), rv > 0, rv <= 10 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.s8kGoldHigh)
                            Text(String(format: "%.1f", rv)).font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kGoldHigh)
                        }
                    }
                    if let g = item.genre {
                        Text(g).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 14) {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        toggleHeroFav(item)
                    }) {
                        let isFav = heroIsFav(item)
                        Image(systemName: isFav ? "heart.fill" : "heart").font(.system(size: 18, weight: .bold))
                            .foregroundColor(isFav ? .s8kRed : .s8kTextPrimary)
                            .symbolEffect(.bounce, value: isFav)   // interactive pop on toggle
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(S8KButtonStyle())
                    // heroIsFav(item), not `isFav`: that binding is declared INSIDE the
                    // label closure and does not exist out here.
                    .accessibilityLabel(heroIsFav(item) ? L("detail.fav_added") : L("detail.fav_add"))
                    Button(action: { onOpen(item) }) {
                        Image(systemName: "play.fill").font(.system(size: 20, weight: .black))
                            .foregroundColor(S8KBrand.accentInk)
                            .frame(width: 52, height: 52)
                            .background(S8KGradient.goldFlat)
                            .clipShape(Circle())
                            .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 12, y: 3)
                    }
                    .buttonStyle(S8KButtonStyle())
                    .accessibilityLabel(L("common.play"))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 5) {
                    ForEach(items) { it in
                        let on = it.id == currentID
                        Capsule()
                            .fill(on ? AnyShapeStyle(S8KGradient.goldFlat)
                                     : AnyShapeStyle(Color.white.opacity(0.3)))
                            .frame(width: on ? 22 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
                .animation(.spring(response: 0.3), value: currentID)
            }
            .padding(.horizontal, S8KSpace.xl)
            .padding(.bottom, S8KSpace.xl)
            // The ARTWORK stays full-bleed, but the copy column matches the rails' 900pt
            // cap. Edge-anchored, the hero's title and play button sat 238pt further out
            // than every rail heading on a landscape iPad — geometrically fine, visually
            // disjoint. Inert on a phone (the ternary yields .infinity).
            .frame(maxWidth: metrics.contentMaxWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: height)
    }

    private func heroIsFav(_ item: HomeVM.HeroItem) -> Bool {
        switch item.kind {
        case .movie(let m):  return favs.isMovieFav(m.id)
        case .series(let s): return favs.isSeriesFav(s.id)
        }
    }
    private func toggleHeroFav(_ item: HomeVM.HeroItem) {
        switch item.kind {
        case .movie(let m):  favs.toggleMovie(m.id)
        case .series(let s): favs.toggleSeries(s.id)
        }
    }

    private func heroChip(_ text: String, color: Color? = nil, isGold: Bool = false) -> some View {
        Text(text)
            .font(S8KFont.caption3)
            .foregroundColor(isGold ? .black : (color ?? .s8kTextPrimary))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                Group {
                    if isGold { AnyView(S8KGradient.goldFlat) }
                    else if let c = color { AnyView(c.opacity(0.15)) }
                    else { AnyView(Color.white.opacity(0.12)) }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.xs))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.xs)
                .strokeBorder(color?.opacity(0.35) ?? Color.clear, lineWidth: 0.5))
    }
}

// Numbered ranking row — a hollow accent numeral with the poster
// overlapping it, plus year + ★rating badges. Extracted from Home so the Movies
// and Series pages reuse the exact same component. `cells` is content-agnostic
// (rank / id / poster / rating / year); `onTap` receives the tapped id.
struct RankRail: View {
    let title: String
    let cells: [(rank: Int, id: String, poster: String?, rating: String?, year: String?)]
    let onTap: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Elegant ranking header: bold title + a trophy glyph + a short lime bar.
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(title).font(.system(size: 20, weight: .heavy)).foregroundColor(.s8kTextPrimary)
                    Image(systemName: "trophy.fill").font(.system(size: 13)).foregroundColor(.s8kGoldHigh)
                }
                RoundedRectangle(cornerRadius: 1.5).fill(S8KGradient.goldFlat).frame(width: 34, height: 3)
                    .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 4)
            }
            .padding(.horizontal, S8KSpace.xl)
            .padding(.bottom, S8KSpace.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 10) {
                    ForEach(cells, id: \.id) { c in
                        Button(action: { onTap(c.id) }) {
                            rankCell(rank: c.rank, poster: c.poster, rating: c.rating, year: c.year)
                        }
                        .buttonStyle(S8KButtonStyle())
                    }
                }
                .padding(.horizontal, S8KSpace.xl)
                .padding(.top, S8KSpace.sm)
            }
        }
        .padding(.bottom, S8KSpace.lg)
    }

    // A big HOLLOW (outlined) rank number with the poster overlapping its right
    // side, and the global rating (★ 8.3) badged on the poster.
    private func rankCell(rank: Int, poster: String?, rating: String?, year: String?) -> some View {
        HStack(alignment: .bottom, spacing: -18) {
            outlinedNumber(rank)
            Color.clear.frame(width: 106, height: 154)
                .overlay { S8KImage(url: poster, placeholder: "film", maxPixel: 420) }
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                // Production YEAR — small badge, top of the poster (short + useful).
                .overlay(alignment: .topTrailing) {
                    if let y = year, !y.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(y)
                            .font(S8KFont.caption3).foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.black.opacity(0.72)).clipShape(Capsule())
                            .padding(5)
                    }
                }
                // Global RATING — only when it's a valid 0–10 score (filters the
                // m3u garbage where the "rating" field was actually a year).
                .overlay(alignment: .bottomTrailing) {
                    if let r = rating, let rv = Double(r), rv > 0, rv <= 10 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(size: 8)).foregroundColor(.s8kGoldHigh)
                            // `String(format:)` with a nil locale is already Western and
                            // dot-separated; tabular keeps 8.3 and 10.0 the same width so
                            // the badge does not resize down the rail.
                            Text(String(format: "%.1f", rv))
                                .font(.system(size: 10, weight: .black).monospacedDigit())
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.78)).clipShape(Capsule())
                        .padding(5)
                    }
                }
        }
    }

    // Outlined/hollow number: fill = deep-green (invisible on the dark bg) + a lime
    // outline built from offset copies (SwiftUI has no native text stroke).
    private func outlinedNumber(_ n: Int) -> some View {
        // Tabular: every digit gets the same advance, so rank 1 and rank 8 occupy an
        // identical gutter and the rail keeps one rhythm all the way across. Without it
        // each cell is a different width and the overlap with the poster changes per
        // rank — which is exactly the drift the owner asked to be engineered out.
        let base = Text("\(n)")
            .font(.system(size: 94, weight: .black, design: .rounded).monospacedDigit())
        let offs: [(CGFloat, CGFloat)] = [(-2, 0), (2, 0), (0, -2), (0, 2),
                                          (-1.4, -1.4), (1.4, 1.4), (-1.4, 1.4), (1.4, -1.4)]
        return ZStack {
            ForEach(Array(offs.enumerated()), id: \.offset) { _, o in
                base.foregroundColor(.s8kGoldHigh).offset(x: o.0, y: o.1)
            }
            base.foregroundColor(S8KBrand.accentInk)
        }
        .shadow(color: .black.opacity(0.5), radius: 3)
        // Flatten the 9 stacked 94pt glyph layers into a single GPU texture so a
        // horizontal fling of the Top-10 rail composites one layer per cell, not 9.
        .drawingGroup()
    }
}

// MARK: - A channel's card, before you commit to watching it

struct ChannelCardSheet: View {
    let channel: Channel
    let onWatch: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            // SCROLLABLE + a .large detent available: IPTV channel names are long and
            // wrap to several lines, and EPGNowNext has a variable height — a fixed
            // medium detent would push the Play button out of reach.
            ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: S8KSpace.xl) {
                S8KImage(url: channel.logoURL, placeholder: "antenna.radiowaves.left.and.right", maxPixel: 240)
                    .frame(width: 90, height: 90)
                    .background(Color.s8kElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.s8kBorderGold, lineWidth: 1))
                    .padding(.top, 32)

                VStack(spacing: 8) {
                    Text(channel.name)
                        .font(S8KFont.title2).foregroundColor(.s8kTextPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(0.7)
                        .padding(.horizontal, 24)
                    if !channel.groupTitle.isEmpty {
                        Text(channel.groupTitle)
                            .font(S8KFont.caption1).foregroundColor(.s8kGoldMid)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.s8kGoldMid.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    HStack(spacing: 5) {
                        Circle().fill(Color.s8kRed).frame(width: 6, height: 6)
                        Text(L("channel.live_now"))
                            .font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                    }
                }

                // What is on now and what follows it. Draws nothing at all when the
                // line carries no guide data.
                EPGNowNext(channel: channel)
                    .padding(.horizontal, 40)

                GoldButton(title: L("channel.play"), icon: "play.fill", action: onWatch)
                    .padding(.horizontal, 40)

                Button { dismiss() } label: {
                    // Explicit label so the expansion sits inside it. 14 a side takes the
                    // ~17pt text to 45: above it the Play button is 20pt away, below it
                    // there is 28pt of sheet padding.
                    Text(L("common.close")).s8kMinTouch(h: 14, v: 14)
                }
                    .font(S8KFont.subhead).foregroundColor(.s8kTextTertiary)
            }
            .padding(.bottom, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - The full watch-history page

struct WatchHistoryPage: View {
    @Environment(\.s8kMetrics) private var metrics
    let items: [WatchHistory]
    var onDismiss: () -> Void
    var onOpen: (WatchHistory) -> Void
    var onRemove: (WatchHistory) -> Void
    var onRemoveAll: () -> Void
    private let grid = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if !items.isEmpty {
                        Button(action: onRemoveAll) {
                            Label(L("home.clear_all"), systemImage: "trash")
                                .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kRed)
                                // 12 is the ceiling downward — the grid begins there.
                                .s8kMinTouch(h: 12, v: 12)
                        }
                    }
                    Spacer()
                    Text(L("home.continue")).font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
                    Spacer()
                    Button { onDismiss() } label: {
                        // Explicit label: outside the Button the expansion would widen the
                        // layout cell only and leave the gesture on the ~44×17 text.
                        Text(L("common.close")).s8kMinTouch(h: 12, v: 12)
                    }
                        .font(S8KFont.subhead).foregroundColor(.s8kGoldMid)
                }
                .padding(.horizontal, S8KSpace.xl).padding(.top, max(56, metrics.safeTop + S8KSpace.md)).padding(.bottom, S8KSpace.md)

                if items.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: L("history.empty"),
                               subtitle: L("history.empty.generic")).padding(.top, 80)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: grid, spacing: 16) {
                            ForEach(items) { h in historyTile(h) }
                        }
                        .padding(20)
                    }
                }
            }
        }
    }

    private func historyTile(_ h: WatchHistory) -> some View {
        Button(action: { onOpen(h) }) {
            VStack(alignment: .trailing, spacing: 6) {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(maxWidth: .infinity).frame(height: 96)
                        .overlay { S8KImage(url: h.posterURL, placeholder: "play.fill") }
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                    S8KProgressBar(fraction: h.progress, track: Color.white.opacity(0.15))
                }
                .frame(height: 96)
                Text(h.contentName).font(S8KFont.caption2.weight(.semibold))
                    .foregroundColor(.s8kTextPrimary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .buttonStyle(S8KButtonStyle())
        .contextMenu {
            Button(role: .destructive) { onRemove(h) } label: {
                Label(L("history.remove"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Search results, laid over the feed

// Every kind of content at once, listed over the home feed while the tab bar's search
// field is active (scope = .all). The field itself lives above this; all this does is
// render the matches and open the one that is tapped.
private struct HomeSearchOverlay: View {
    @Environment(\.s8kMetrics) private var metrics
    @ObservedObject var vm: SearchVM
    let onMovie:   (Movie) -> Void
    let onSeries:  (Series) -> Void
    let onChannel: (Channel) -> Void

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            let q = vm.query.trimmingCharacters(in: .whitespaces)
            if q.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 42, weight: .light))
                        .foregroundColor(.s8kTextDisabled)
                    Text(L("search.all")).font(S8KFont.callout).foregroundColor(.s8kTextTertiary)
                }
            } else if vm.loading {
                ProgressView().tint(.s8kGoldMid).scaleEffect(1.2)
            } else if vm.results.isEmpty {
                EmptyState(icon: "magnifyingglass", title: L("empty.no_results"), subtitle: "")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.results) { r in
                            Button { open(r) } label: { row(r) }
                                .buttonStyle(S8KButtonStyle())
                            Divider().background(Color.s8kBorder).padding(.leading, 74)
                        }
                    }
                    // Capped and centred: this list is a full-screen overlay with no
                    // width limit, so on a 12.9" iPad each row put ~1256pt of nothing
                    // between a thumbnail and its own title.
                    .frame(maxWidth: metrics.readableMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.top, max(66, metrics.safeTop + S8KSpace.sm))
                    Color.clear.frame(height: metrics.bottomClearance)
                }
            }
        }
    }

    private func open(_ r: SearchVM.SearchResult) {
        switch r.type {
        case .movie(let m):   onMovie(m)
        case .series(let s):  onSeries(s)
        case .channel(let c): onChannel(c)
        }
    }

    private func row(_ r: SearchVM.SearchResult) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 46, height: 46)
                .overlay { S8KImage(url: r.imageURL, placeholder: r.type.icon, maxPixel: 160) }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
            VStack(alignment: .trailing, spacing: 3) {
                Text(r.title).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(r.type.label).font(S8KFont.caption2).foregroundColor(.s8kGoldMid)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                .foregroundColor(.s8kTextDisabled)
        }
        .padding(.horizontal, S8KSpace.xl).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - The notifications inbox

struct AlertsView: View {
    @Environment(\.s8kMetrics) private var metrics
    var onClose: (() -> Void)? = nil
    @StateObject private var config = ConfigService.shared
    @StateObject private var auth   = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @Environment(\.dismiss) var dismiss

    private func badgeStyle(_ kind: String) -> (String, Color) {
        switch kind {
        case "warning": return ("exclamationmark.triangle.fill", .s8kOrange)
        case "promo":   return ("gift.fill", .s8kGoldHigh)
        default:        return ("bell.fill", .s8kBlue)
        }
    }
    private var hasNothingToShow: Bool {
        activation.notifications.isEmpty && config.appConfig.announcement == nil && auth.user == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Broadcasts pushed by the operator, most recent first.
                        ForEach(activation.notifications) { n in
                            let s = badgeStyle(n.kind)
                            noticeCard(icon: s.0, color: s.1, title: n.title,
                                       message: n.body.isEmpty ? " " : n.body)
                        }
                        if let text = config.appConfig.announcement {
                            noticeCard(icon: "megaphone.fill", color: .s8kGoldHigh,
                                       title: L("alerts.announcement"), message: text)
                        }
                        if let user = auth.user {
                            if user.daysRemaining <= 7 {
                                noticeCard(icon: "exclamationmark.triangle.fill", color: .s8kOrange,
                                           title: L("alerts.sub_warning"),
                                           message: "\(L("sub.days_left_prefix")) \(user.daysRemaining) \(L("unit.day")) \(L("sub.expire_suffix"))")
                            } else {
                                noticeCard(icon: "checkmark.seal.fill", color: .s8kGreen,
                                           title: L("alerts.sub_active"),
                                           message: "\(L("sub.days_left_prefix")) \(user.daysRemaining) \(L("unit.day")) \(L("sub.active_suffix"))")
                            }
                        }
                        if hasNothingToShow {
                            EmptyState(icon: "bell.slash",
                                       title: L("alerts.empty.title"),
                                       subtitle: L("alerts.empty.sub"))
                                .padding(.top, max(56, metrics.safeTop + S8KSpace.md))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(L("set.notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.close")) {
                        if let onClose { onClose() } else { dismiss() }
                    }.foregroundColor(.s8kGoldMid)
                }
            }
        }
        .onDisappear { activation.markNotificationsRead() }
    }

    private func noticeCard(icon: String, color: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
            VStack(alignment: .trailing, spacing: 4) {
                Text(title).font(S8KFont.subhead).foregroundColor(.s8kTextPrimary)
                Text(message).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                    .multilineTextAlignment(.trailing).lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(S8KSpace.lg)
        .background(Color.s8kSurface)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
            .strokeBorder(Color.s8kBorder, lineWidth: 1))
    }
}
