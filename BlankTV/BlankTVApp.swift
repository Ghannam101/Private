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
    /// False until the post-login content boot loader has finished.
    @Published var contentReady = false

    /// Home top-bar presentations (search / notifications). Hosted here — at the
    /// app-level singleton — and presented from the STABLE tabView, NOT from
    /// HomeView's local @State. This is the root-cause fix for "bell/search work
    /// in demo but not in playlists": HomeView's @State could be reset by any
    /// ancestor re-render (and lived in a different structural position per
    /// mode), so the cover silently failed to present. Router state survives all
    /// re-renders and is identical in demo and real mode.
    @Published var homeSheet: HomeSheet? = nil
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
                    if router.contentReady {
                        tabView.transition(.opacity)
                    } else {
                        // Dedicated full-screen content loader (no tab bar)
                        ContentBootView { router.contentReady = true }
                            .transition(.opacity)
                    }
                } else {
                    // NEW: multi-subscription entry gate (lists saved accounts +
                    // switch/add/demo). LoginView is now the "add subscription" form.
                    SubscriptionsGateView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: router.contentReady)
        }
    }

    // MARK: - Main Tab View
    // Native TabView keeps each page alive and lazily-rendered (only the
    // visible page renders) — switching is instant. The native bar is hidden
    // (UITabBar.appearance().isHidden) and replaced by our custom AppTabBar.
    private var tabView: some View {
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
                SettingsView().tag(AppTab.settings)
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
        }
        // Top-bar presentations live HERE (stable host) so they present
        // identically in demo and real playlist mode and can never be lost
        // by a HomeView re-render. See AppRouter.homeSheet.
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
