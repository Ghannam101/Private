// ============================================================
// BLANK TV — HomeView.swift
// Home Screen — Dynamic Remote-Controlled
// ============================================================

import SwiftUI

@MainActor
final class HomeVM: ObservableObject {
    static let shared = HomeVM()
    @Published var liveChannels:  [Channel]      = []
    @Published var movies:        [Movie]         = []
    @Published var series:        [Series]        = []
    @Published var history:       [WatchHistory]  = []
    @Published var heroIndex:     Int             = 0
    @Published var isLoading:     Bool            = true
    @Published var error:         AppError?       = nil
    @Published var doneChannels = false
    @Published var doneMovies   = false
    @Published var doneSeries   = false
    @Published var heroItems:     [HeroItem]      = []   // mixed swipeable hero (movies + series)
    @Published var topMovies:     [Movie]         = []   // top-rated (Netflix Top 10 rail) — sorted ONCE
    @Published var topSeries:     [Series]        = []   // top-rated series rail — sorted ONCE
    @Published var newMovies:     [Movie]         = []   // recently added (id desc) — sorted ONCE
    @Published var newSeries:     [Series]        = []   // recently added (id desc) — sorted ONCE
    @Published var rails:         [HomeRail]      = []   // curated themed rails (network + genre) — built ONCE
    private var heroDir = 1                              // hero ping-pong direction (ذهاب/عودة)

    // Provider categories (names) — needed to classify content into themed rails.
    private var movieCats:  [Category] = []
    private var seriesCats: [Category] = []

    // A hero carousel item can be a movie OR a series.
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

    /// Build the mixed hero: top-rated movies + top-rated series, interleaved, up to 8.
    func rebuildHero() {
        // Sort ONCE here (not on every SwiftUI render) — re-sorting a large catalog
        // on each body eval was a major source of home jank.
        topMovies = Array(movies.sorted { $0.ratingDouble > $1.ratingDouble }.prefix(10))
        topSeries = Array(series.sorted { (Double($0.rating ?? "") ?? 0) > (Double($1.rating ?? "") ?? 0) }.prefix(10))
        // "Recently added" ≈ highest Xtream id (ids auto-increment, so newest last).
        newMovies = Array(movies.sorted { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) }.prefix(20))
        newSeries = Array(series.sorted { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) }.prefix(20))

        // Hero features the NEWEST content (movies + series interleaved) — it refreshes
        // as fresh titles arrive on reload. (Owner: hero tracks new movies/series.)
        let hM = newMovies.prefix(4).map { HeroItem(kind: .movie($0)) }
        let hS = newSeries.prefix(4).map { HeroItem(kind: .series($0)) }
        var out: [HeroItem] = []
        for i in 0..<max(hM.count, hS.count) {
            if i < hM.count { out.append(hM[i]) }
            if i < hS.count { out.append(hS[i]) }
        }
        heroItems = Array(out.prefix(8))
        if heroIndex >= heroItems.count { heroIndex = 0 }
        heroDir = 1

        // Prefetch hero backdrops so swiping is smooth (image decode was the jank).
        S8KImageCache.shared.prefetch(heroItems.compactMap { $0.backdropURL }, maxPixel: 1400)
    }

    private let hist    = HistoryService.shared
    private let config  = ConfigService.shared
    private var heroTimer: Timer?
    private var loaded = false

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
        loaded = true
        rebuildHero()
        rebuildRails()
        isLoading = false
    }

    func reset() {
        loaded = false; liveChannels = []; movies = []; series = []
        history = []; heroIndex = 0; isLoading = true; error = nil
        doneChannels = false; doneMovies = false; doneSeries = false
        rails = []; movieCats = []; seriesCats = []
    }

    /// Parallel boot load for the dedicated loading screen: live + movies +
    /// series fetched concurrently, each flipping its own progress flag as it
    /// finishes — so total time ≈ the slowest request, not the sum of all three.
    func bootLoad() async {
        if loaded { doneChannels = true; doneMovies = true; doneSeries = true; return }
        await config.fetchIfStale()
        async let c: Void = loadChannels()
        async let m: Void = loadMovies()
        async let s: Void = loadSeries()
        _ = await (c, m, s)
        history = Array(hist.items.prefix(8))
        loaded = true
        rebuildHero()
        rebuildRails()
        isLoading = false
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

    /// Build the curated themed rails ONCE (network + genre), off the loaded
    /// catalog + category names. Prefetch the first rows' posters so the feed
    /// paints smoothly on first scroll.
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
    /// Remember a content-load failure so the home can show a clear banner
    /// (e.g. the provider line expired mid-session) instead of an empty screen.
    private func noteError(_ e: Error) { error = (e as? AppError) ?? .network(e) }

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

struct HomeView: View {
    @StateObject private var vm     = HomeVM.shared
    @StateObject private var config = ConfigService.shared
    @StateObject private var theme  = AppTheme.shared
    @StateObject private var auth   = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @StateObject private var favs   = FavoritesService.shared
    @ObservedObject private var bars = BarVisibility.shared   // drives the top bar's glass on scroll
    @Environment(\.horizontalSizeClass) private var hSize

    // Single enum-driven presentation each — SwiftUI only honors one
    // .sheet / one .fullScreenCover per view reliably.
    // Definitive fix for the bell: route EVERYTHING through a single
    // .fullScreenCover. Mixing .sheet + .fullScreenCover on one view made
    // SwiftUI silently swallow the sheet (the bell never opened). One
    // presentation = no conflict possible.
    @State private var cover: HomeCover? = nil
    @State private var editingHistory = false   // long-press → reveal ✕ on history cards
    @State private var refreshing = false           // content refresh in progress
    @State private var showRefreshConfirm = false   // confirm before a heavy reload

    enum HomeCover: Identifiable {
        case player(ContentItem), movie(Movie), series(Series)
        case channel(Channel), allHistory
        var id: String {
            switch self {
            case .player(let i): return "p_\(i.id)"
            case .movie(let m):  return "m_\(m.id)"
            case .series(let s): return "s_\(s.id)"
            case .channel(let c): return "ch_\(c.id)"
            case .allHistory:    return "history"
            }
        }
    }

    var body: some View {
        // No NavigationStack here: the home never pushes a navigation destination
        // (it presents via .fullScreenCover). The previous NavigationStack +
        // deprecated .navigationBarHidden(true) left an invisible nav bar that
        // RESERVED/CAPTURED touches in the top band on iOS 17 — which silently
        // ate the bell/search/refresh taps once real (tall) content scrolled
        // under it (Demo's short content didn't trigger it). Removing it deletes
        // the blocking layer at the root.
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            // Show the full-screen loader ONLY on the first load (no content yet).
            // A refresh/retry that already has content reloads in place instead of
            // blanking the whole screen.
            if vm.isLoading && vm.liveChannels.isEmpty && vm.movies.isEmpty && vm.series.isEmpty {
                homeSkeleton
            } else {
                mainScroll
            }
        }
        // Floating top bar (profile · logo) over the hero — transparent at the top,
        // frosted glass once scrolled. Overlaid (NOT a scroll child) so its taps are
        // always live and the hero image runs full-bleed underneath it.
        .overlay(alignment: .top) { homeTopBar }
        .task { await vm.load() }
        .onAppear { vm.startHeroTimer() }
        .onDisappear { vm.stopHeroTimer() }
        // A presented fullScreenCover does NOT trigger Home's onDisappear, so the
        // hero timer would keep rotating an off-screen carousel. Pause it while any
        // cover is open and resume on dismissal.
        .onChange(of: cover != nil) { _, presented in
            if presented { vm.stopHeroTimer() } else { vm.startHeroTimer() }
        }
        .fullScreenCover(item: $cover) { c in
            switch c {
            case .player(let item): PlayerView(item: item, channels: vm.liveChannels)
            case .movie(let m):     MovieDetailView(movie: m)
            case .series(let s):    SeriesDetailView(series: s)
            case .channel(let ch):  ChannelInfoSheet(channel: ch) { cover = .player(.live(ch)) }
            case .allHistory:
                AllHistoryView(items: vm.history,
                               onClose: { cover = nil },
                               onSelect: { resume($0); cover = nil },
                               onDelete: { removeHistory($0) },
                               onClearAll: { clearHistory(); cover = nil })
            }
        }
        // Branded confirm before a heavy content reload — matches the app's
        // identity (black/gold), same component as logout/delete in Settings.
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
    }

    // MARK: - Main Scroll
    private var mainScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if contentFailed { contentErrorBanner }
                // Home section order (owner spec): immersive hero → Continue Watching →
                // a) Top-rated Movies + b) Top-rated Series (quickNav) → c) Recently
                // added Movies → d) Recently added Series → e) Live / يبث الآن.
                heroSection
                continueWatching
                quickNav
                moviesSection       // c) recently added movies
                seriesSection       // d) recently added series
                liveSection         // e) live channels
                supportButtons
                Color.clear.frame(height: 100)
            }
            // Cap + center the content on iPad so the page isn't a blown-up phone
            // screen stretched edge-to-edge.
            .frame(maxWidth: hSize == .regular ? 900 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await vm.load() }
        // Drive the floating menu (collapse on scroll) + the top bar glass (frost on scroll).
        .reportsScrollToTabBar()
        // Hero runs full-bleed UNDER the status bar; the top bar is a top OVERLAY
        // (see `body`), hit-tested independently so its taps are always live.
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Loading skeleton (first, empty load)
    // A home-shaped shimmer (hero block + rail rows) instead of a bare spinner —
    // the premium "streaming service is loading" cue (matches the reference).
    private var homeSkeleton: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                SkeletonBlock(cornerRadius: 0).frame(height: heroHeight)
                ForEach(0..<3, id: \.self) { _ in skeletonRail }
                Color.clear.frame(height: 60)
            }
            .frame(maxWidth: hSize == .regular ? 900 : .infinity)
            .frame(maxWidth: .infinity)
        }
        // The top bar is the shared overlay in `body`; the skeleton just runs
        // full-bleed under it (matches the loaded layout).
        .ignoresSafeArea(edges: .top)
    }

    private var skeletonRail: some View {
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

    // MARK: - Content-load error banner
    // Shown only when every section is empty AND a load error occurred (e.g. the
    // provider line expired mid-session, or a network failure) — so the user sees
    // a clear reason + retry instead of a confusing blank home.
    private var contentFailed: Bool {
        vm.error != nil && vm.liveChannels.isEmpty && vm.movies.isEmpty && vm.series.isEmpty
    }
    private var contentErrorBanner: some View {
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

    // MARK: - Nav Bar
    private var navBar: some View {
        HStack {
            // Logo + Name — give it layout priority so the wordmark keeps its full
            // width and never wraps/squeezes on narrower phones (iPhone 11 etc.).
            HStack(spacing: 10) {
                BrandLogo(size: 34)
                    .shadow(color: .s8kGoldHigh.opacity(0.25), radius: 6)
                S8KWordmark(size: 18)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            // Actions
            HStack(spacing: 10) {
                if refreshing {
                    ProgressView().tint(.s8kGoldMid).frame(width: 38, height: 38)
                } else {
                    navBtn(icon: "arrow.clockwise") { showRefreshConfirm = true }
                }
                navBtn(icon: "magnifyingglass") {
                    AppRouter.shared.homeSheet = .search
                }
                // My downloads (offline)
                navBtn(icon: "arrow.down.circle") {
                    AppRouter.shared.homeSheet = .downloads
                }
                ZStack(alignment: .topTrailing) {
                    navBtn(icon: "bell") {
                        AppRouter.shared.homeSheet = .alerts
                    }
                    let unread = activation.unreadCount
                    if unread > 0 {
                        Text("\(min(unread, 9))")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.s8kRed)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.s8kBlack, lineWidth: 1.5))
                            .offset(x: 4, y: -4)
                            .allowsHitTesting(false)   // never block the bell tap
                    }
                }
            }
        }
        .padding(.horizontal, S8KSpace.xl)
        .padding(.top, 60)
        .padding(.bottom, S8KSpace.lg)
    }

    private func navBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.s8kTextSecondary)
                .frame(width: 40, height: 40)
                // Solid background (NOT interactive glass — the iOS 26 interactive
                // glass effect was swallowing the tap) + full-area hit testing.
                .background(Color.s8kSurface, in: RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .strokeBorder(Color.s8kBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
    }

    // MARK: - Home Top Bar (profile · logo) — Filmm-style
    // Floats over the hero: profile (المجسم) on the LEFT opens Settings, the logo on
    // the RIGHT. Transparent (with a soft scrim) at the top so it blends into the
    // poster; frosts to glass — keeping logo + profile clear — once scrolled.
    private var homeTopBar: some View {
        HStack {
            HStack(spacing: 9) {
                BrandLogo(size: 30).shadow(color: .s8kGoldHigh.opacity(0.25), radius: 6)
                S8KWordmark(size: 17)
            }
            Spacer(minLength: 8)
            profileButton
        }
        .padding(.horizontal, S8KSpace.xl)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background {
            if bars.scrolled {
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(Color.s8kBlack.opacity(0.22))
                    .overlay(GoldDivider(), alignment: .bottom)
                    .ignoresSafeArea(edges: .top)
            } else {
                LinearGradient(colors: [.black.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
    }

    // The "المجسم" profile avatar — top-left. Opens Settings (the full profile page
    // is milestone M6). A material circle so its tap is never swallowed.
    private var profileButton: some View {
        Button {
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

    // MARK: - Announcement
    @ViewBuilder
    private var announcementBar: some View {
        if let text = config.appConfig.announcement {
            HStack(spacing: 8) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.s8kGoldHigh)
                Text(text)
                    .font(S8KFont.caption1)
                    .foregroundColor(.s8kTextSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, S8KSpace.xl)
            .padding(.vertical, 10)
            .background(Color.s8kGoldMid.opacity(0.1))
            .overlay(GoldDivider(), alignment: .bottom)
            .padding(.bottom, S8KSpace.lg)
        }
    }

    // MARK: - Admin Banner
    @ViewBuilder
    private var bannerSection: some View {
        if let url = config.appConfig.bannerURL {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .overlay { S8KImage(url: url, placeholder: "photo") }
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg)
                    .strokeBorder(Color.s8kBorderGold, lineWidth: 1))
                .padding(.horizontal, S8KSpace.xl)
                .padding(.bottom, S8KSpace.xl)
                .onTapGesture {
                    // Banner taps open an external (operator-controlled) URL — gated
                    // so the iOS build can't be used to surface an external purchase
                    // page post-approval (Guideline 3.1.1).
                    if AppCompliance.allowsExternalPurchaseLinks,
                       let link = config.appConfig.bannerLink, let url = URL(string: link) {
                        UIApplication.shared.open(url)
                    }
                }
        }
    }

    // Responsive hero height — enlarged DOWNWARD so the full poster shows on all
    // phones (full-bleed under the notch/Dynamic Island; the top bar overlays a scrim).
    private var heroHeight: CGFloat {
        hSize == .regular ? 560 : min(max(UIScreen.main.bounds.height * 0.62, 520), 660)
    }

    // MARK: - Hero Section — SWIPEABLE cinematic carousel mixing top-rated movies +
    // series (auto-rotates every 5s via the VM timer; the customer can also swipe).
    @ViewBuilder
    private var heroSection: some View {
        if !vm.heroItems.isEmpty {
            TabView(selection: $vm.heroIndex) {
                ForEach(Array(vm.heroItems.enumerated()), id: \.element.id) { idx, item in
                    heroCard(item).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: heroHeight)
            // Pause the auto-rotation the moment the user touches the hero, and
            // resume (with a fresh interval) when they lift — so manual swiping is
            // never fought by the timer (removes the residual stutter).
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in vm.stopHeroTimer() }
                    .onEnded   { _ in vm.startHeroTimer() }
            )
        }
    }

    private func heroCard(_ item: HomeVM.HeroItem) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .overlay { S8KImage(url: item.backdropURL, placeholder: "film") }
                .clipped()
            LinearGradient(
                stops: [
                    .init(color: .s8kBlack,              location: 0.0),
                    .init(color: .s8kBlack.opacity(0.6), location: 0.28),
                    .init(color: .clear,                 location: 0.60),
                    .init(color: .s8kBlack.opacity(0.5), location: 1.0)
                ],
                startPoint: .bottom, endPoint: .top)
                .frame(height: heroHeight)
                .allowsHitTesting(false)

            VStack(alignment: .trailing, spacing: 11) {
                HStack(spacing: 6) {
                    tag(L("home.featured"), isGold: true)
                    tag(L("home.new_tag"), color: .s8kBlue)
                }
                Text(item.name).font(.system(size: 32, weight: .black)).foregroundColor(.s8kTextPrimary)
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
                    Button(action: { openHero(item) }) {
                        Image(systemName: "play.fill").font(.system(size: 20, weight: .black))
                            .foregroundColor(.s8kBlack)
                            .frame(width: 52, height: 52)
                            .background(S8KGradient.goldFlat)
                            .clipShape(Circle())
                            .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 12, y: 3)
                    }
                    .buttonStyle(S8KButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 5) {
                    ForEach(0..<vm.heroItems.count, id: \.self) { i in
                        Capsule()
                            .fill(i == vm.heroIndex ? AnyShapeStyle(S8KGradient.goldFlat)
                                                    : AnyShapeStyle(Color.white.opacity(0.3)))
                            .frame(width: i == vm.heroIndex ? 22 : 6, height: 6)
                            .animation(.spring(response: 0.3), value: vm.heroIndex)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 4)
            }
            .padding(.horizontal, S8KSpace.xl)
            .padding(.bottom, S8KSpace.xl)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: heroHeight)
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
    private func openHero(_ item: HomeVM.HeroItem) {
        switch item.kind {
        case .movie(let m):  cover = .movie(m)
        case .series(let s): cover = .series(s)
        }
    }

    private func tag(_ text: String, color: Color? = nil, isGold: Bool = false) -> some View {
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

    // MARK: - Top-rated numbered rankings (Netflix "Top 10" — HOLLOW numbers ON the
    // poster + global ★ rating). Uses the ONCE-sorted vm.topMovies/topSeries.
    private var quickNav: some View {
        VStack(spacing: 0) {
            if !vm.topMovies.isEmpty {
                rankRail(title: L("home.top_movies"),
                         cells: vm.topMovies.enumerated().map { ($0.offset + 1, $0.element.id, $0.element.posterURL, $0.element.rating, $0.element.year) }) { id in
                    if let m = vm.topMovies.first(where: { $0.id == id }) { cover = .movie(m) }
                }
            }
            if !vm.topSeries.isEmpty {
                rankRail(title: L("home.top_series"),
                         cells: vm.topSeries.enumerated().map { ($0.offset + 1, $0.element.id, $0.element.coverURL, $0.element.rating, $0.element.year) }) { id in
                    if let s = vm.topSeries.first(where: { $0.id == id }) { cover = .series(s) }
                }
                .padding(.bottom, S8KSpace.md)
            }
        }
    }

    private func rankRail(title: String, cells: [(rank: Int, id: String, poster: String?, rating: String?, year: String?)],
                          onTap: @escaping (String) -> Void) -> some View {
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
                HStack(alignment: .bottom, spacing: 10) {
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
        // Poster overlaps the number's right edge by a small amount (Netflix Top-10
        // look) — the number stays legible, the poster "owns" part of it.
        HStack(alignment: .bottom, spacing: -18) {
            outlinedNumber(rank)
            Color.clear.frame(width: 106, height: 154)
                .overlay { S8KImage(url: poster, placeholder: "film") }
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                // Production YEAR — small badge, top of the poster (short + useful).
                .overlay(alignment: .topTrailing) {
                    if let y = year, !y.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(y)
                            .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
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
                            Text(String(format: "%.1f", rv)).font(.system(size: 10, weight: .black)).foregroundColor(.white)
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
        let base = Text("\(n)").font(.system(size: 94, weight: .black, design: .rounded))
        let offs: [(CGFloat, CGFloat)] = [(-2, 0), (2, 0), (0, -2), (0, 2),
                                          (-1.4, -1.4), (1.4, 1.4), (-1.4, 1.4), (1.4, -1.4)]
        return ZStack {
            ForEach(Array(offs.enumerated()), id: \.offset) { _, o in
                base.foregroundColor(.s8kGoldHigh).offset(x: o.0, y: o.1)
            }
            base.foregroundColor(.s8kBlack)
        }
        .shadow(color: .black.opacity(0.5), radius: 3)
    }

    // MARK: - Curated themed rails (Smart Rail Engine)
    // A streaming-service-style editorial feed built from the user's OWN provider
    // categories (network rails like NETFLIX/OSN + genre rails like Anime/Action).
    // Each rail is lazy: its posters decode only when the row scrolls into view.
    @ViewBuilder
    private var railsSection: some View {
        if !vm.rails.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(vm.rails) { rail in
                    railRow(rail)
                }
            }
        }
    }

    private func railRow(_ rail: HomeRail) -> some View {
        VStack(spacing: 0) {
            railHeader(rail)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    switch rail.kind {
                    case .movie(let items):
                        ForEach(items) { m in
                            ContentCard(title: m.name, subtitle: m.year,
                                        imageURL: m.posterURL) { cover = .movie(m) }
                        }
                    case .series(let items):
                        ForEach(items) { s in
                            ContentCard(title: s.name, subtitle: s.year,
                                        imageURL: s.coverURL) { cover = .series(s) }
                        }
                    }
                }
                .padding(.horizontal, S8KSpace.xl)
            }
        }
        .padding(.bottom, S8KSpace.xxl)
    }

    // Right-aligned (Arabic) rail header: optional brand chip + heavy title + lime
    // underline. Network rails carry a small lime brand chip so they read as
    // premium "provider" rows; genre rails show the title alone.
    private func railHeader(_ rail: HomeRail) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let tag = rail.networkTag {
                    Text(tag)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.s8kGoldHigh)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.s8kGoldMid.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.xs, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.xs, style: .continuous)
                            .strokeBorder(Color.s8kBorderGold, lineWidth: 0.5))
                }
                Text(rail.title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(.s8kTextPrimary)
                    .lineLimit(1)
            }
            RoundedRectangle(cornerRadius: 1.5).fill(S8KGradient.goldFlat)
                .frame(width: 30, height: 3)
                .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 4)
        }
        .padding(.horizontal, S8KSpace.xl)
        .padding(.bottom, S8KSpace.sm)
    }

    // MARK: - Continue Watching
    @ViewBuilder
    private var continueWatching: some View {
        if !vm.history.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    if editingHistory {
                        Button(action: { clearHistory() }) {
                            Label(L("home.clear_all"), systemImage: "trash")
                                .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kRed)
                        }
                        Spacer()
                        Button(action: { withAnimation { editingHistory = false } }) {
                            Text(L("common.done")).font(S8KFont.caption1.weight(.bold)).foregroundColor(.s8kGoldMid)
                        }
                    } else {
                        Button(action: { cover = .allHistory }) {
                            HStack(spacing: 3) {
                                Text(L("home.see_all")).font(S8KFont.caption1.weight(.semibold))
                                Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.s8kGoldMid)
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
                            watchCard(item)
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                }
            }
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    private func watchCard(_ item: WatchHistory) -> some View {
        ZStack(alignment: .topLeading) {
            Button(action: {
                if editingHistory { withAnimation { editingHistory = false } }
                else { resume(item) }
            }) {
                watchCardBody(item)
            }
            .buttonStyle(S8KButtonStyle())
            .onLongPressGesture { withAnimation(.spring(response: 0.3)) { editingHistory = true } }
            .contextMenu {
                Button(role: .destructive) { removeHistory(item) } label: {
                    Label(L("home.remove_history"), systemImage: "trash")
                }
            }

            // Small corner ✕ — appears in edit mode for single-item delete
            if editingHistory {
                Button(action: { removeHistory(item) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.s8kRed).clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }
                .buttonStyle(S8KButtonStyle())
                .padding(7)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func removeHistory(_ item: WatchHistory) {
        HistoryService.shared.remove(item.id)
        withAnimation { vm.history.removeAll { $0.id == item.id } }
    }
    private func clearHistory() {
        HistoryService.shared.clear()
        withAnimation { vm.history = []; editingHistory = false }
    }

    /// Resume playback from history by locating the content in the loaded catalog
    private func resume(_ item: WatchHistory) {
        switch item.contentType {
        case .live:
            if let ch = vm.liveChannels.first(where: { $0.id == item.contentID }) {
                cover = .player(.live(ch))
            }
        case .movie:
            if let m = vm.movies.first(where: { $0.id == item.contentID }) {
                cover = .movie(m)
            }
        case .episode:
            // Episodes need their parent series — open the series page if we can find it
            if let s = vm.series.first(where: { item.contentName.hasPrefix($0.name) }) {
                cover = .series(s)
            }
        }
    }

    private func watchCardBody(_ item: WatchHistory) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            ZStack(alignment: .bottom) {
                S8KImage(url: item.posterURL, placeholder: "play.fill")
                    .frame(width: 220, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                        .strokeBorder(Color.s8kBorder, lineWidth: 1))

                // Play button
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: "play.fill")
                        .font(.system(size: 14)).foregroundColor(.white).offset(x: 1))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))

                // Progress
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Color.white.opacity(0.15)
                        S8KGradient.goldFlat
                            .frame(width: g.size.width * min(1, max(0, item.progress)))
                            .shadow(color: .s8kGoldHigh.opacity(0.4), radius: 2)
                    }
                }
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
            }
            .frame(width: 220, height: 124)

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

    // MARK: - Live Channels
    @ViewBuilder
    private var liveSection: some View {
        if !vm.liveChannels.isEmpty {
            VStack(spacing: 0) {
                SectionHeader(title: L("home.live_now"), count: vm.liveChannels.count) { AppRouter.shared.tab = .live }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.liveChannels.prefix(20)) { ch in
                            ChannelChip(name: ch.name, logoURL: ch.logoURL, isLive: true) {
                                cover = .player(.live(ch))
                            }
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                }
            }
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    // MARK: - Movies
    @ViewBuilder
    // c) Recently Added Movies (newest first, by Xtream id).
    private var moviesSection: some View {
        if !vm.newMovies.isEmpty {
            VStack(spacing: 0) {
                SectionHeader(title: L("home.new_movies")) { AppRouter.shared.tab = .movies }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.newMovies) { m in
                            ContentCard(title: m.name, subtitle: m.year,
                                        imageURL: m.posterURL) { cover = .movie(m) }
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                }
            }
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    // MARK: - Series
    @ViewBuilder
    // d) Recently Added Series (newest first, by Xtream id).
    private var seriesSection: some View {
        if !vm.newSeries.isEmpty {
            VStack(spacing: 0) {
                SectionHeader(title: L("home.new_series")) { AppRouter.shared.tab = .series }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.newSeries) { s in
                            ContentCard(title: s.name, subtitle: s.year,
                                        imageURL: s.coverURL) { cover = .series(s) }
                        }
                    }
                    .padding(.horizontal, S8KSpace.xl)
                }
            }
            .padding(.bottom, S8KSpace.xxl)
        }
    }

    // MARK: - Support / Store
    @ViewBuilder
    private var supportButtons: some View {
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
                    supportBtn(L("home.whatsapp"), icon: "message.fill", color: .s8kGreen) {
                        if let u = URL(string: "https://wa.me/\(wa)") { UIApplication.shared.open(u) }
                    }
                }
                if let tg = config.appConfig.supportTelegram {
                    supportBtn(L("home.telegram"), icon: "paperplane.fill", color: .s8kBlue) {
                        if let u = URL(string: tg) { UIApplication.shared.open(u) }
                    }
                }
            }
        }
        .padding(.horizontal, S8KSpace.xl)
    }

    private func supportBtn(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
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

// MARK: - Dedicated post-login content loader (elegant, full-screen, no tab bar)
struct ContentBootView: View {
    let onComplete: () -> Void
    @StateObject private var vm = HomeVM.shared
    @State private var p: [Double] = [0, 0, 0]   // live, movies, series
    @State private var logoPulse = false
    private let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    private let sections: [(String, String)] = [
        (L("home.boot.live"),   "dot.radiowaves.left.and.right"),
        (L("home.boot.movies"), "film.fill"),
        (L("home.boot.series"), "play.tv.fill")
    ]

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            RadialGradient(colors: [Color.s8kGoldMid.opacity(0.12), .clear],
                           center: .center, startRadius: 0, endRadius: 340).ignoresSafeArea()

            // Clean, minimal loader — NO percentage bar (per owner feedback). The
            // section chips fill lime + check off as each section finishes loading.
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image("Logo").resizable().scaledToFit().frame(width: 92, height: 92)
                        .shadow(color: .s8kGoldHigh.opacity(0.45), radius: 24)
                        .scaleEffect(logoPulse ? 1.05 : 0.96)
                        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: logoPulse)
                    S8KWordmark(size: 27)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(S8KGradient.goldFlat)
                        .frame(width: 46, height: 4)
                        .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 5)
                }

                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        chip(sections[i].0, sections[i].1, p[i])
                    }
                }

                HStack(spacing: 9) {
                    ProgressView().tint(.s8kGoldHigh).scaleEffect(0.85)
                    Text(L("home.preparing"))
                        .font(S8KFont.footnote).foregroundColor(.s8kTextTertiary)
                }
            }
        }
        .onAppear { logoPulse = true }
        .task {
            await vm.bootLoad()
            try? await Task.sleep(nanoseconds: 150_000_000)  // brief settle; disk cache makes content instant
            onComplete()
        }
        .onReceive(timer) { _ in
            advance(0, vm.doneChannels)
            if vm.doneChannels { advance(1, vm.doneMovies) }
            if vm.doneMovies   { advance(2, vm.doneSeries) }
        }
    }

    private func advance(_ i: Int, _ done: Bool) {
        if done { if p[i] < 1 { p[i] = min(1, p[i] + 0.14) } }
        else if p[i] < 0.92 { p[i] += 0.018 }
    }

    private func chip(_ name: String, _ icon: String, _ value: Double) -> some View {
        let done = value >= 1
        return HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(done ? .s8kGoldHigh : .s8kTextDisabled)
            Text(name).font(S8KFont.caption1.weight(.semibold))
                .foregroundColor(done ? .s8kTextPrimary : .s8kTextTertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(done ? Color.s8kGoldHigh.opacity(0.12) : Color.s8kElevated)
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
            .strokeBorder(done ? Color.s8kGoldHigh.opacity(0.3) : Color.s8kBorder, lineWidth: 1))
        .animation(.easeOut(duration: 0.25), value: done)
    }
}

// MARK: - Alerts / Notifications Sheet
struct AlertsView: View {
    var onClose: (() -> Void)? = nil
    @StateObject private var config = ConfigService.shared
    @StateObject private var auth   = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @Environment(\.dismiss) var dismiss

    private func kindStyle(_ kind: String) -> (String, Color) {
        switch kind {
        case "warning": return ("exclamationmark.triangle.fill", .s8kOrange)
        case "promo":   return ("gift.fill", .s8kGoldHigh)
        default:        return ("bell.fill", .s8kBlue)
        }
    }
    private var isEmpty: Bool {
        activation.notifications.isEmpty && config.appConfig.announcement == nil && auth.user == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Owner broadcast notifications (newest first)
                        ForEach(activation.notifications) { n in
                            let s = kindStyle(n.kind)
                            alertCard(icon: s.0, color: s.1, title: n.title,
                                      message: n.body.isEmpty ? " " : n.body)
                        }
                        if let text = config.appConfig.announcement {
                            alertCard(icon: "megaphone.fill", color: .s8kGoldHigh,
                                      title: L("alerts.announcement"), message: text)
                        }
                        if let user = auth.user {
                            if user.daysRemaining <= 7 {
                                alertCard(icon: "exclamationmark.triangle.fill", color: .s8kOrange,
                                          title: L("alerts.sub_warning"),
                                          message: "\(L("sub.days_left_prefix")) \(user.daysRemaining) \(L("unit.day")) \(L("sub.expire_suffix"))")
                            } else {
                                alertCard(icon: "checkmark.seal.fill", color: .s8kGreen,
                                          title: L("alerts.sub_active"),
                                          message: "\(L("sub.days_left_prefix")) \(user.daysRemaining) \(L("unit.day")) \(L("sub.active_suffix"))")
                            }
                        }
                        if isEmpty {
                            EmptyState(icon: "bell.slash",
                                       title: L("alerts.empty.title"),
                                       subtitle: L("alerts.empty.sub"))
                                .padding(.top, 60)
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

    private func alertCard(icon: String, color: Color, title: String, message: String) -> some View {
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

// MARK: - All watch history (full page, reachable from "see all")
struct AllHistoryView: View {
    let items: [WatchHistory]
    var onClose: () -> Void
    var onSelect: (WatchHistory) -> Void
    var onDelete: (WatchHistory) -> Void
    var onClearAll: () -> Void
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    if !items.isEmpty {
                        Button(action: onClearAll) {
                            Label(L("home.clear_all"), systemImage: "trash")
                                .font(S8KFont.caption1.weight(.semibold)).foregroundColor(.s8kRed)
                        }
                    }
                    Spacer()
                    Text(L("home.continue")).font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
                    Spacer()
                    Button(L("common.close")) { onClose() }
                        .font(S8KFont.subhead).foregroundColor(.s8kGoldMid)
                }
                .padding(.horizontal, S8KSpace.xl).padding(.top, 56).padding(.bottom, S8KSpace.md)

                if items.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: L("history.empty"),
                               subtitle: L("history.empty.generic")).padding(.top, 80)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: cols, spacing: 16) {
                            ForEach(items) { h in cell(h) }
                        }
                        .padding(20)
                    }
                }
            }
        }
    }

    private func cell(_ h: WatchHistory) -> some View {
        Button(action: { onSelect(h) }) {
            VStack(alignment: .trailing, spacing: 6) {
                ZStack(alignment: .bottom) {
                    Color.clear
                        .frame(maxWidth: .infinity).frame(height: 96)
                        .overlay { S8KImage(url: h.posterURL, placeholder: "play.fill") }
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Color.white.opacity(0.15)
                            S8KGradient.goldFlat.frame(width: g.size.width * min(1, max(0, h.progress)))
                        }
                    }
                    .frame(height: 3).clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                }
                .frame(height: 96)
                Text(h.contentName).font(S8KFont.caption2.weight(.semibold))
                    .foregroundColor(.s8kTextPrimary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .buttonStyle(S8KButtonStyle())
        .contextMenu {
            Button(role: .destructive) { onDelete(h) } label: {
                Label(L("history.remove"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Channel Info Sheet (Hero "معلومات")
struct ChannelInfoSheet: View {
    let channel: Channel
    let onPlay: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.s8kBlack.ignoresSafeArea()
            VStack(spacing: S8KSpace.xl) {
                S8KImage(url: channel.logoURL, placeholder: "antenna.radiowaves.left.and.right")
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

                // Live program guide (now/next) — hidden when the provider has no EPG.
                EPGNowNext(channel: channel)
                    .padding(.horizontal, 40)

                GoldButton(title: L("channel.play"), icon: "play.fill", action: onPlay)
                    .padding(.horizontal, 40)

                Button(L("common.close")) { dismiss() }
                    .font(S8KFont.subhead).foregroundColor(.s8kTextTertiary)

                Spacer()
            }
        }
        .presentationDetents([.medium])
    }
}
