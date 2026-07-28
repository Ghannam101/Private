// ============================================================
// BLANK TV — BlankTVApp.swift
// Main App Entry Point
// iOS 17+ • SwiftUI • Apple HIG
// ============================================================

import SwiftUI
import AVFoundation
import UserNotifications

// MARK: - App Router (cross-screen tab navigation)
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    private init() {}
    @Published var tab: AppTab = .home
    /// How many blocking confirmations are on screen. A DEPTH rather than a flag so a
    /// second confirm appearing before the first finishes dismissing cannot leave the
    /// tab bar hidden for good. S8KConfirm maintains this itself — see its onAppear —
    /// so no call site has to remember to set it.
    @Published var modalDepth: Int = 0
    var modalBlocking: Bool { modalDepth > 0 }
    /// Legacy signal, kept so the eight flows in Services.swift that mean "the catalog
    /// must be rebuilt" did not have to change. It is COMPUTED, not stored: writing
    /// `false` bumps `contentGen`, which is what actually remounts the tab stack.
    ///
    /// It must not be a stored `@Published Bool`. Those call sites write `false` over an
    /// already-`false` value, so an `.onChange` observer would never fire — the remount
    /// would silently never happen and a playlist switch or a refresh would leave every
    /// tab on a skeleton forever.
    var contentReady: Bool {
        get { true }
        set { if !newValue { contentGen &+= 1 } }
    }
    /// Content generation. Bumping it remounts the whole tab stack, which re-runs every
    /// tab's `.task { await vm.load() }` against freshly reset view models.
    @Published var contentGen = 0

    /// Home top-bar presentations (search / notifications). Hosted here — at the
    /// app-level singleton — and presented from the STABLE tabView, NOT from
    /// HomeView's local @State. This is the root-cause fix for "bell/search work
    /// in demo but not in playlists": HomeView's @State could be reset by any
    /// ancestor re-render (and lived in a different structural position per
    /// mode), so the cover silently failed to present. Router state survives all
    /// re-renders and is identical in demo and real mode.
    @Published var homeSheet: HomeSheet? = nil
    /// Scope the contextual search opens with (seeded from the current section by
    /// the tab bar's search button before it presents the search cover).
    @Published var searchScope: SearchVM.SearchScope = .movies

    /// Global in-place search (owner spec): the corner-menu search button morphs
    /// into a text field (App-Store style) instead of opening a separate page.
    /// `searchActive` toggles the tab bar into search mode; `searchText` is the
    /// single query the active section (or Home = all content) filters by live.
    @Published var searchActive = false
    @Published var searchText   = ""
    /// Collapse search mode + clear the query (Cancel / section switch).
    func endSearch() { searchActive = false; searchText = "" }
    enum HomeSheet: Identifiable {
        case search, alerts, downloads
        var id: String {
            switch self {
            case .search:    return "search"
            case .alerts:    return "alerts"
            case .downloads: return "downloads"
            }
        }
    }
}

// MARK: - App Delegate (orientation control for the player)
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// iPhone browses portrait-locked (the player unlocks rotation while open);
    /// iPad rotates freely everywhere from launch.
    static var orientationLock: UIInterfaceOrientationMask =
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    /// Re-attach to the background download session when iOS relaunches us to
    /// finish offline transfers, and store the completion handler so the system
    /// knows when we're done updating the UI.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        // If a prior relaunch handler was stored but never fired, flush it now so
        // a second event can't strand the first and trip the background watchdog.
        DownloadService.shared.backgroundCompletion?()
        DownloadService.shared.backgroundCompletion = completionHandler
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Install the app-wide "tap anywhere to dismiss the keyboard" gesture.
        KeyboardDismisser.shared.install()
        UNUserNotificationCenter.current().delegate = self
        // Merely TOUCHING the singleton is the point, and it is load-bearing: its
        // init rebuilds the background URLSession — which is what re-attaches us to
        // transfers still running — and then runs reconcileOnLaunch, which restarts
        // the ones iOS killed at force-quit. Nothing referenced it at a normal
        // launch, so both only happened if the user opened the Downloads screen. A
        // download interrupted by a force-quit therefore stayed frozen (the owner
        // saw it stuck at 1%) no matter what reconcileOnLaunch did.
        _ = DownloadService.shared
    }
}

// Show download-complete notifications as a banner even while the app is open.
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - App-wide keyboard dismissal
// A single tap recognizer on the key window that resigns first responder on any
// tap, with cancelsTouchesInView = false so it NEVER blocks buttons/controls,
// and simultaneous recognition so it never fights other gestures. This fixes
// "the keyboard stays up and blocks the UI" for every text/search field at once.
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()

    func install() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return }
        // Avoid installing twice.
        if window.gestureRecognizers?.contains(where: { $0.name == "s8kKeyboardDismiss" }) == true { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.name = "s8kKeyboardDismiss"
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // Recognize alongside scroll/tap/button gestures — don't swallow them.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

@main
struct BlankTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var auth   = AuthService.shared
    @StateObject private var theme  = AppTheme.shared
    @StateObject private var router = AppRouter.shared
    @StateObject private var loc    = LocalizationManager.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var splashDone = false

    init() {
        configureAudio()
        configureAppearance()
        // One-time, crash-safe migration of legacy global favorites/watchlist
        // into the active playlist's scope (issue #4). activePlaylistID is read
        // from persisted UserDefaults, so it's correct this early.
        Store.shared.migrateLegacyScopedDataIfNeeded()
        // Crash / performance observability (MetricKit — zero dependency).
        Diagnostics.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            content
                // Rebuild the whole tree when the brand palette changes (reseller
                // re-skin) so every computed color token resolves to the new theme.
                .id(theme.brandTick)
                .preferredColorScheme(.dark)
                // Keep a consistent layout for all languages (same page/tab
                // order); only the text changes. Arabic text stays right-aligned
                // via the existing per-view modifiers.
                .environment(\.layoutDirection, .leftToRight)
                .environment(\.locale, Locale(identifier: loc.lang.rawValue))
                // Re-check entitlement + remote app-control on foreground so
                // maintenance / forced-update take effect without a cold launch.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, splashDone, !Store.shared.demoMode {
                        Task { await AuthService.shared.validateSession(); await ActivationService.shared.check() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !splashDone {
            SplashView { splashDone = true }
        } else {
            // Activation gate sits in front of all content: the device must be
            // allowed (active/trial) before it can reach login or the tabs.
            ActivationGate {
                if auth.loggedIn {
                    // INSTANT ENTRY (owner spec): pressing Sign In lands on the app
                    // immediately — no full-screen loading page. Every tab already owns
                    // a skeleton for its first load, so the shell paints at once and the
                    // catalog fills in underneath, the way the big streaming apps do.
                    //
                    // `.id(contentGen)` is what replaces the old unmount/remount: the
                    // eight flows that used to set `contentReady = false` (login, switch
                    // playlist, refresh, add playlist, logout, delete account…) relied on
                    // the boot screen swapping the tabs out to re-run every tab's
                    // `.task { await vm.load() }`. Bumping the generation remounts them
                    // just the same — but instantly, and with skeletons instead of a
                    // blocking page.
                    tabView
                        .id(router.contentGen)
                        .transition(.opacity)
                } else {
                    // The poster-wall gateway is now the real login screen (it carries
                    // the Xtream/M3U form, saved accounts with one-tap entry, language
                    // and demo). The old SubscriptionsGateView is retired.
                    GatewayView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: auth.loggedIn)
            // SELF-HEALING. modalDepth is app-lifetime state, and both live confirms
            // tear down their OWN hosting hierarchy from inside onConfirm — logout and
            // deleteAccount both flip `loggedIn`, which swaps this whole branch while
            // the confirm is still mid-removal-transition. `onDisappear` for a view
            // whose removal is interrupted by an ancestor identity change is not
            // guaranteed, and a single miss would hide the tab bar — the only
            // navigation in the app — for the rest of the session, invisibly.
            // These three are the moments no confirm can legitimately still be up.
            // They must sit OUTSIDE `.id(router.contentGen)`, or the fresh subtree
            // would never observe the change that reset it.
            .onChange(of: router.contentGen) { _, _ in router.modalDepth = 0 }
            .onChange(of: auth.loggedIn)     { _, _ in router.modalDepth = 0 }
            .onChange(of: router.tab)        { _, _ in router.modalDepth = 0 }
        }
    }

    // MARK: - Main Tab View
    // Native TabView keeps each page alive and lazily-rendered (only the
    // visible page renders) — switching is instant. The native bar is hidden
    // (UITabBar.appearance().isHidden) and replaced by our custom AppTabBar.
    private var tabView: some View {
        // S8KMetricsRoot is the app's SINGLE layout-metrics injection point. Every
        // page reads `@Environment(\.s8kMetrics)` instead of re-deriving sizes, which
        // is how three disagreeing hero formulas and eleven width caps happened.
        // Do not add a second one.
        S8KMetricsRoot {
        ZStack(alignment: .bottom) {
            TabView(selection: $router.tab) {
                HomeView().tag(AppTab.home)
                    .toolbar(.hidden, for: .tabBar)
                LiveTVView().tag(AppTab.live)
                    .toolbar(.hidden, for: .tabBar)
                MoviesView().tag(AppTab.movies)
                    .toolbar(.hidden, for: .tabBar)
                SeriesListView().tag(AppTab.series)
                    .toolbar(.hidden, for: .tabBar)
                SettingsProV2().tag(AppTab.settings)
                    .toolbar(.hidden, for: .tabBar)
            }
            // Hide the system tab bar (incl. the new iPadOS 18 top tab bar) so
            // only our custom AppTabBar shows.
            .toolbar(.hidden, for: .tabBar)
            // Content fills to the physical bottom (scrolls behind the glass bar)…
            .ignoresSafeArea(edges: .bottom)

            // …but the floating glass bar itself RESPECTS the safe area, so it sits
            // a comfortable margin above the home indicator (not glued to the edge).
            AppTabBar(selected: $router.tab)
                .zIndex(1)   // always above content so its taps never fall through
                // …but NOT above a modal confirmation. The bar lives outside the
                // TabView, so a confirm presented inside a tab page can never out-rank
                // it locally — the puck stayed live over the scrim and could open the
                // nav bar on top of a destructive confirm. Pages raise this flag while
                // a confirm is up.
                .opacity(router.modalBlocking ? 0 : 1)
                .allowsHitTesting(!router.modalBlocking)
                .animation(.easeOut(duration: 0.16), value: router.modalBlocking)
        }
        // Top-bar presentations live HERE (stable host) so they present identically in
        // demo and real playlist mode and can never be lost by a HomeView re-render.
        // Attached INSIDE S8KMetricsRoot so these covers inherit the real layout metrics
        // — outside it they would silently get the hardcoded 393×852 default.
        .fullScreenCover(item: $router.homeSheet) { sheet in
            switch sheet {
            case .search:    SearchView()
            case .alerts:    AlertsView()
            case .downloads: DownloadsView()
            }
        }
        .task {
            if auth.loggedIn {
                await auth.validateSession()
            }
        }
        }
    }

    // MARK: - Audio Session
    private func configureAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session: \(error)")
        }
    }

    // MARK: - Appearance
    private func configureAppearance() {
        // Navigation bar
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Color.s8kBlack)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .bold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 34, weight: .black)
        ]
        UINavigationBar.appearance().standardAppearance  = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(Color.s8kGoldMid)

        // Hide default tab bar (we use custom)
        UITabBar.appearance().isHidden = true
    }
}
