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
        isLoading = false
    }

    func reset() {
        loaded = false; liveChannels = []; movies = []; series = []
        history = []; heroIndex = 0; isLoading = true; error = nil
        doneChannels = false; doneMovies = false; doneSeries = false
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
        isLoading = false
    }

    private func loadChannels() async {
        do { liveChannels = try await ContentService.liveStreams() }
        catch { print("channels: \(error)"); noteError(error) }
        doneChannels = true
    }
    private func loadMovies() async {
        do { movies = try await ContentService.movies() }
        catch { print("movies: \(error)"); noteError(error) }
        doneMovies = true
    }
    private func loadSeries() async {
        do { series = try await ContentService.series() }
        catch { print("series: \(error)"); noteError(error) }
        doneSeries = true
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
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    self.heroIndex = (self.heroIndex + 1) % max(1, self.movies.prefix(6).count)
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
                LoadingView(message: L("loading.updating"))
            } else {
                mainScroll
            }
        }
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
                announcementBar
                bannerSection
                heroSection
                quickNav
                continueWatching
                liveSection
                moviesSection
                seriesSection
                supportButtons
                Color.clear.frame(height: 100)
            }
            // Cap + center the content on iPad so the page isn't a blown-up phone
            // screen stretched edge-to-edge.
            .frame(maxWidth: hSize == .regular ? 900 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await vm.load() }
        // The top bar is a real top safe-area INSET, NOT a child of the
        // ScrollView. When it lived inside the scroll, the scroll's content
        // container (taller than the viewport once content exceeded one screen)
        // spanned up over the buttons and captured their taps in real (tall)
        // playlists while working in Demo (short content). As an inset, the bar
        // reserves its own space above the scrollable content (no overlap) and
        // is hit-tested independently, on top — so the buttons always receive
        // their taps. Do NOT move it back inside the ScrollView.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                TrialBanner()
                navBar
            }
            .background(Color.s8kBlack)
        }
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

    // MARK: - Hero Section (cinematic latest movies; admin banner overrides via bannerSection)
    @ViewBuilder
    private var heroSection: some View {
        let heroes = Array(vm.movies.prefix(6))
        if !heroes.isEmpty {
            ZStack(alignment: .bottomTrailing) {
                if let m = heroes[safe: vm.heroIndex] {
                    // A fixed-size Color.clear is the LAYOUT primary (screen width
                    // × 240); the image is an overlay that's clipped to it. This
                    // makes the box's size — never the image's intrinsic/fill size
                    // — drive layout, so a wide source image can never widen the
                    // page (the prior maxWidth+clipped still leaked the fill width).
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .overlay { S8KImage(url: m.backdropURL ?? m.posterURL, placeholder: "film") }
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.xl))
                        .id(m.id)                                   // cross-fade on change
                        .transition(.opacity)
                }
                RoundedRectangle(cornerRadius: S8KRadius.xl)
                    .fill(LinearGradient(
                        colors: [Color.s8kBlack, Color.black.opacity(0.35), .clear],
                        startPoint: .bottom, endPoint: .top))
                    .frame(height: 240)
                    .allowsHitTesting(false)   // decorative scrim — never intercept the hero buttons

                VStack(alignment: .trailing, spacing: 9) {
                    HStack(spacing: 6) {
                        tag(L("home.featured"), isGold: true)
                        tag(L("home.new_tag"), color: .s8kBlue)
                    }
                    if let m = heroes[safe: vm.heroIndex] {
                        Text(m.name).font(.system(size: 25, weight: .black)).foregroundColor(.s8kTextPrimary)
                            .lineLimit(2).multilineTextAlignment(.trailing)
                            .shadow(color: .black.opacity(0.6), radius: 5)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        // Editorial lime underline accent under the hero title
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(S8KGradient.goldFlat)
                            .frame(width: 40, height: 3)
                            .shadow(color: .s8kGoldHigh.opacity(0.6), radius: 4)
                        if let y = m.year {
                            Text(y).font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Button(action: {
                            if let m = heroes[safe: vm.heroIndex] { cover = .movie(m) }
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                                Text(L("common.play")).font(S8KFont.subhead.weight(.bold))
                            }
                            .foregroundColor(.s8kBlack)
                            .padding(.horizontal, 22).padding(.vertical, 11)
                            .background(S8KGradient.goldFlat)
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                            .shadow(color: .s8kGoldMid.opacity(0.45), radius: 8, y: 3)
                        }
                        .buttonStyle(S8KButtonStyle())
                        Button(action: {
                            if let m = heroes[safe: vm.heroIndex] { cover = .movie(m) }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle").font(.system(size: 12))
                                Text(L("common.details")).font(S8KFont.caption1.weight(.semibold))
                            }
                            .foregroundColor(.s8kTextPrimary)
                            .padding(.horizontal, 15).padding(.vertical, 11)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(S8KButtonStyle())
                    }
                }
                .padding(S8KSpace.xl)
                .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 4) {
                    ForEach(0..<heroes.count, id: \.self) { i in
                        Capsule()
                            .fill(i == vm.heroIndex ? AnyShapeStyle(S8KGradient.goldFlat)
                                                    : AnyShapeStyle(Color.white.opacity(0.25)))
                            .frame(width: i == vm.heroIndex ? 20 : 5, height: 5)
                            .animation(.spring(response: 0.3), value: vm.heroIndex)
                    }
                }
                .padding(.horizontal, S8KSpace.xl).padding(.bottom, S8KSpace.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.xl)
                .strokeBorder(Color.s8kBorderGold, lineWidth: 1))
            .padding(.horizontal, S8KSpace.xl)
            .padding(.bottom, S8KSpace.xxl)
            .animation(.easeInOut(duration: 0.6), value: vm.heroIndex)
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

    // MARK: - Quick Nav (tappable shortcuts to sections)
    private var quickNav: some View {
        HStack(spacing: 10) {
            quickNavCard(L("home.qn_live"), icon: "antenna.radiowaves.left.and.right",
                         sub: "\(vm.liveChannels.count) \(L("unit.channel"))", color: .s8kRed, tab: .live)
            quickNavCard(L("home.qn_movies"), icon: "film.stack.fill",
                         sub: "\(vm.movies.count)+ \(L("unit.movie"))", color: .s8kBlue, tab: .movies)
            quickNavCard(L("home.qn_series"), icon: "play.tv.fill",
                         sub: "\(vm.series.count)+ \(L("unit.series"))", color: .s8kGoldMid, tab: .series)
        }
        .padding(.horizontal, S8KSpace.xl)
        .padding(.bottom, S8KSpace.xxl)
    }

    private func quickNavCard(_ title: String, icon: String, sub: String, color: Color, tab: AppTab) -> some View {
        Button(action: { AppRouter.shared.tab = tab }) {
            // Editorial tile: rounded-square icon badge top-left, heavy title + count
            // below, left-aligned. Distinct from the reference's centered circle card.
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .fill(color.opacity(0.16))
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                            .strokeBorder(color.opacity(0.30), lineWidth: 1))
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(S8KFont.subhead.weight(.heavy)).foregroundColor(.s8kTextPrimary)
                    Text(sub).font(S8KFont.caption2).foregroundColor(.s8kTextTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(S8KSpace.md)
            .s8kGlass(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
                .strokeBorder(Color.s8kBorder, lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
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
    private var moviesSection: some View {
        if !vm.movies.isEmpty {
            VStack(spacing: 0) {
                SectionHeader(title: L("home.new_movies"), count: vm.movies.count) { AppRouter.shared.tab = .movies }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.movies.prefix(20)) { m in
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
    private var seriesSection: some View {
        if !vm.series.isEmpty {
            VStack(spacing: 0) {
                SectionHeader(title: L("home.new_series"), count: vm.series.count) { AppRouter.shared.tab = .series }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(vm.series.prefix(20)) { s in
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

            let overall = (p[0] + p[1] + p[2]) / 3
            VStack(spacing: 30) {
                VStack(spacing: 12) {
                    Image("Logo").resizable().scaledToFit().frame(width: 88, height: 88)
                        .shadow(color: .s8kGoldHigh.opacity(0.45), radius: 24)
                        .scaleEffect(logoPulse ? 1.04 : 0.97)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: logoPulse)
                    S8KWordmark(size: 26)
                }

                // Editorial: one BIG bold percentage + a single slim lime bar.
                VStack(spacing: 16) {
                    Text("\(Int(overall * 100))%")
                        .font(.system(size: 66, weight: .black, design: .rounded))
                        .foregroundStyle(S8KGradient.goldFlat)
                        .monospacedDigit()
                        .shadow(color: .s8kGoldHigh.opacity(0.3), radius: 12)
                    GeometryReader { g in
                        ZStack(alignment: .trailing) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(S8KGradient.goldFlat)
                                .frame(width: g.size.width * overall)
                                .shadow(color: .s8kGoldHigh.opacity(0.4), radius: 5)
                        }
                    }
                    .frame(height: 6)
                    .animation(.easeOut(duration: 0.3), value: overall)
                }
                .padding(.horizontal, 48)

                // Section status chips — fill lime + check as each completes.
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { i in
                        chip(sections[i].0, sections[i].1, p[i])
                    }
                }

                Text(L("home.preparing"))
                    .font(S8KFont.footnote).foregroundColor(.s8kTextTertiary)
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
