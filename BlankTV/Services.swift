// ============================================================
// BLANK TV — Services.swift
// Auth + Config + Favorites + WatchHistory Services
// ============================================================

import SwiftUI
import UIKit

// MARK: ════════════════════════════════════════
// AUTH SERVICE
// ════════════════════════════════════════════
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()
    private init() { restore() }

    @Published var loggedIn:   Bool      = false
    @Published var isLoading:  Bool      = false
    @Published var error:      AppError? = nil
    @Published var user:       UserInfo? = nil
    @Published var serverInfo: ServerInfo? = nil
    @Published var mode:       LoginMode = .xtream

    // MARK: - Login (Xtream Codes)
    func login(username: String, password: String, customURL: String? = nil) async {
        guard !isLoading else { return }
        isLoading = true; error = nil

        if SecurityCheck.isJailbroken() {
            error = .server("هذا الجهاز لا يدعم تشغيل التطبيق لأسباب أمنية")
            isLoading = false; return
        }

        let req = LoginRequest(
            username:    username.trimmingCharacters(in: .whitespaces).lowercased(),
            password:    password,
            deviceID:    UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            deviceModel: UIDevice.current.model,
            appVersion:  Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        )

        do {
            let resp: LoginResponse = try await APIClient.shared.request(
                path: "/auth/login", method: .POST, body: req, requiresAuth: false
            )
            // Save credentials
            Keychain.shared.token       = resp.token
            Keychain.shared.tokenExpiry = resp.expiresAt
            Keychain.shared.userID      = resp.user.id
            Keychain.shared.saveServerCredentials(
                host: customURL ?? resp.server.host,
                user: resp.server.username,
                pass: resp.server.password
            )
            // Save to store
            Store.shared.saveUserInfo(resp.user)
            Store.shared.saveServerInfo(resp.server)
            Store.shared.saveTheme(resp.theme)
            Store.shared.saveFeatures(resp.features)
            Store.shared.saveAppConfig(resp.config)
            Store.shared.lastConfigFetch = Date()
            // Apply theme + config
            AppTheme.shared.apply(resp.theme)
            ConfigService.shared.apply(features: resp.features, config: resp.config)
            // Update state
            Store.shared.loginMode = .xtream
            mode = .xtream
            let p = SavedPlaylist(name: resp.user.username, kind: .xtream,
                                  url: customURL ?? resp.server.host,
                                  username: resp.server.username, password: resp.server.password)
            Store.shared.activePlaylistID = Store.shared.upsertPlaylist(p)   // stable scope id
            reloadScopedCaches()
            user = resp.user; serverInfo = resp.server; loggedIn = true
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .network(error)
        }
        isLoading = false
    }

    // MARK: - Login (Xtream Codes — DIRECT to the user's provider)
    // Connects straight to the provider's player_api.php (same proven engine as
    // M3U via XtreamDirect/PlaylistService) instead of proxying content through
    // our backend. This keeps the app a pure player (App Store 4.3/5.x + legal),
    // works with any user's own/reseller line, and reuses loadXtreamDirect's
    // auth/status validation — so an expired/disabled line is rejected with a
    // clear message instead of showing an empty home. Saved as a .m3u playlist
    // so it restores through the same direct path on relaunch/switch.
    func loginXtream(host: String, username: String, password: String) async {
        guard !isLoading else { return }
        isLoading = true; error = nil

        if SecurityCheck.isJailbroken() {
            error = .server("هذا الجهاز لا يدعم تشغيل التطبيق لأسباب أمنية")
            isLoading = false; return
        }

        let u    = username.trimmingCharacters(in: .whitespaces)
        let pass = password
        let base = Self.normalizeXtreamHost(host)
        guard !base.isEmpty else {
            error = .server("أدخل رابط السيرفر (مثال: http://server.com:8080)")
            isLoading = false; return
        }
        guard !u.isEmpty, !pass.isEmpty else {
            error = .server("أدخل اسم المستخدم وكلمة المرور")
            isLoading = false; return
        }

        // Build the Xtream API URL; encode credentials so symbols don't break it.
        let cs = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let eu = u.addingPercentEncoding(withAllowedCharacters: cs) ?? u
        let ep = pass.addingPercentEncoding(withAllowedCharacters: cs) ?? pass
        let url = "\(base)/player_api.php?username=\(eu)&password=\(ep)"

        do {
            Store.shared.m3uURL = url
            // Cheap pre-flight: validate the line (auth/status) here so an expired/
            // banned account is rejected on the LOGIN screen. The heavy catalog fetch
            // is deferred to the boot screen (real progress bar) instead of blocking
            // the login button on the whole library.
            try await PlaylistService.shared.validateCredentials()
            await PlaylistService.shared.reset()   // clean slate → boot fetches fresh for this line
            Store.shared.loginMode = .m3u
            mode = .m3u
            let pl = SavedPlaylist(name: u, kind: .m3u, url: url)
            Store.shared.activePlaylistID = Store.shared.upsertPlaylist(pl)   // stable scope id
            reloadScopedCaches()
            AppRouter.shared.contentReady = false   // ensure the boot screen runs (fetches this line)
            loggedIn = true
        } catch let e as AppError {
            error = e; Store.shared.m3uURL = nil
        } catch {
            self.error = .network(error); Store.shared.m3uURL = nil
        }
        isLoading = false
    }

    /// Normalize whatever the user types as a host into `scheme://host[:port]`
    /// (accepts "host", "host:port", "http://host:port", or a full get.php URL).
    static func normalizeXtreamHost(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        let withScheme = trimmed.lowercased().hasPrefix("http") ? trimmed : "http://\(trimmed)"
        if let comps = URLComponents(string: withScheme), let host = comps.host {
            let scheme = comps.scheme ?? "http"
            var base = "\(scheme)://\(host)"
            if let port = comps.port { base += ":\(port)" }
            return base
        }
        var h = withScheme
        while h.hasSuffix("/") { h.removeLast() }
        return h
    }

    // MARK: - Login (M3U / M3U8 Playlist)
    func loginM3U(urlString: String) async {
        guard !isLoading else { return }
        isLoading = true; error = nil

        if SecurityCheck.isJailbroken() {
            error = .server("هذا الجهاز لا يدعم تشغيل التطبيق لأسباب أمنية")
            isLoading = false; return
        }

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("http"), URL(string: trimmed) != nil else {
            error = .server("رابط قائمة التشغيل غير صالح — يجب أن يبدأ بـ http")
            isLoading = false; return
        }

        do {
            Store.shared.m3uURL = trimmed
            // Cheap pre-flight (auth/status for a get.php/player_api.php URL; a no-op
            // for a raw .m3u file). The full catalog is fetched on the boot screen
            // with real progress, so the login button doesn't block on the library.
            try await PlaylistService.shared.validateCredentials()
            await PlaylistService.shared.reset()   // clean slate → boot fetches fresh for this line
            Store.shared.loginMode = .m3u
            mode = .m3u
            // Remember this playlist
            let p = SavedPlaylist(name: Self.playlistName(from: trimmed), kind: .m3u, url: trimmed)
            Store.shared.activePlaylistID = Store.shared.upsertPlaylist(p)   // stable scope id
            reloadScopedCaches()
            AppRouter.shared.contentReady = false   // ensure the boot screen runs (fetches this line)
            loggedIn = true
        } catch let e as AppError {
            error = e
            Store.shared.m3uURL = nil
        } catch {
            self.error = .network(error)
            Store.shared.m3uURL = nil
        }
        isLoading = false
    }

    // MARK: - Multiple playlists
    static func playlistName(from url: String) -> String {
        if let host = URLComponents(string: url)?.host { return host }
        return "قائمة"
    }

    /// Switch the active playlist and reload content from it.
    func switchPlaylist(_ p: SavedPlaylist) async {
        if p.kind == .m3u {
            Store.shared.m3uURL = p.url
            Store.shared.loginMode = .m3u
            mode = .m3u
            await PlaylistService.shared.reset()
        } else {
            Keychain.shared.saveServerCredentials(host: p.url, user: p.username ?? "", pass: p.password ?? "")
            Store.shared.loginMode = .xtream
            mode = .xtream
        }
        Store.shared.activePlaylistID = p.id
        reloadScopedCaches()                    // per-playlist history/favorites/watchlist
        ContentCache.reset()
        AppRouter.shared.contentReady = false   // re-run the boot loader → fresh content
    }

    /// Force a fresh reload of the current playlist's content (#6 refresh).
    func refreshContent() async {
        if mode == .m3u {
            // FORCE a fresh network fetch (bypasses the 12h catalog disk cache and
            // re-saves it) + clear the EPG cache — so the refresh button truly
            // pulls new content, not the cached copy. The current content stays
            // on screen until this completes.
            await PlaylistService.shared.reset()
            _ = try? await PlaylistService.shared.load(force: true)
        }
        ContentCache.reset()
        AppRouter.shared.contentReady = false   // rebuild the tab VMs from the fresh content
    }

    /// Add a new M3U/get.php playlist (validates, saves, switches to it).
    func addM3UPlaylist(name: String, urlString: String) async -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("http"), URL(string: trimmed) != nil else {
            error = .server("رابط غير صالح — يجب أن يبدأ بـ http"); return false
        }
        let prevURL = Store.shared.m3uURL
        Store.shared.m3uURL = trimmed
        await PlaylistService.shared.reset()
        do {
            _ = try await PlaylistService.shared.load(force: true)
            let p = SavedPlaylist(name: name.isEmpty ? Self.playlistName(from: trimmed) : name,
                                  kind: .m3u, url: trimmed)
            let scopeID = Store.shared.upsertPlaylist(p)   // stable scope id
            Store.shared.loginMode = .m3u; mode = .m3u
            Store.shared.activePlaylistID = scopeID
            reloadScopedCaches()
            ContentCache.reset()
            AppRouter.shared.contentReady = false
            return true
        } catch let e as AppError {
            error = e; Store.shared.m3uURL = prevURL; await PlaylistService.shared.reset(); return false
        } catch {
            self.error = .network(error); Store.shared.m3uURL = prevURL; return false
        }
    }

    func deletePlaylist(_ id: String) async {
        let wasActive = Store.shared.activePlaylistID == id
        var list = Store.shared.savedPlaylists
        list.removeAll { $0.id == id }
        Store.shared.savedPlaylists = list
        Store.shared.clearScopedData(playlistID: id)   // remove only THIS playlist's data
        // If the active (e.g. broken/expired) playlist was deleted, properly
        // re-activate a remaining one — reloading its credentials + content —
        // instead of leaving the app pointed at the dead playlist (#5).
        if wasActive {
            if let next = list.first { await switchPlaylist(next) }
            else { Store.shared.activePlaylistID = nil }
        }
    }

    // MARK: - Demo Mode (App Store Review, Guideline 2.1)
    func enterDemo() {
        Store.shared.demoMode = true
        ContentCache.reset()
        reloadScopedCaches()    // demo has its own scope → show demo data only
        loggedIn = true
        error = nil
    }

    /// Reload all per-playlist in-memory caches (history/favorites/watchlist) after
    /// the active scope changes, so switching playlist/account never shows another
    /// one's data. Must be called after activePlaylistID / demoMode change.
    func reloadScopedCaches() {
        HistoryService.shared.reload()
        FavoritesService.shared.reload()
        WatchlistService.shared.reload()
    }

    // MARK: - Logout
    func logout() async {
        if mode == .xtream && !Store.shared.demoMode {
            _ = try? await APIClient.shared.request(path: "/auth/logout", method: .POST) as EmptyResp
        }
        await PlaylistService.shared.reset()
        Store.shared.demoMode = false
        Keychain.shared.clearAll()
        Store.shared.clearSession()
        AppTheme.shared.reset()
        ConfigService.shared.reset()
        ContentCache.reset()
        AppRouter.shared.contentReady = false
        mode = .xtream
        user = nil; serverInfo = nil; loggedIn = false; error = nil
    }

    // MARK: - Delete Account (Apple Required)
    func deleteAccount() async throws {
        if mode == .xtream {
            _ = try await APIClient.shared.request(path: "/auth/account", method: .DELETE) as EmptyResp
        }
        await PlaylistService.shared.reset()
        Store.shared.demoMode = false
        Keychain.shared.clearAll()
        Store.shared.clearAll()                 // wipes the whole UserDefaults domain
        AppTheme.shared.reset()
        AppTheme.shared.applyBrandTheme(hex: nil)   // revert to the official BLANK TV palette
        ActivationService.shared.clearReseller()    // drop the reseller brand/host too
        ConfigService.shared.reset()            // mirror logout's full teardown so no
        ContentCache.reset()                    // previous-user config/content lingers
        ParentalService.shared.resetAll()       // account deletion clears the parental PIN too
        AppRouter.shared.contentReady = false
        mode = .xtream
        user = nil; serverInfo = nil; loggedIn = false; error = nil
    }

    // MARK: - Validate + Refresh
    func validateSession() async {
        if Store.shared.demoMode { return }   // demo never talks to the backend
        guard mode == .xtream else { return } // M3U sessions are local-only
        guard Keychain.shared.tokenValid else { await logout(); return }
        do {
            let u: UserInfo = try await APIClient.shared.request(path: "/auth/validate")
            user = u; Store.shared.saveUserInfo(u)
        } catch { await logout() }
    }

    // MARK: - Restore Session
    private func restore() {
        // Demo session persists until logout
        if Store.shared.demoMode { loggedIn = true; return }
        // M3U session — local only, no token needed
        if Store.shared.loginMode == .m3u, Store.shared.m3uURL != nil {
            mode = .m3u
            loggedIn = true
            return
        }
        guard Keychain.shared.tokenValid,
              let u = Store.shared.loadUserInfo(),
              let s = Store.shared.loadServerInfo(),
              !u.isExpired else { return }
        mode = .xtream
        user = u; serverInfo = s
        if let theme = Store.shared.loadTheme() { AppTheme.shared.apply(theme) }
        if let feat  = Store.shared.loadFeatures(),
           let conf  = Store.shared.loadAppConfig() {
            ConfigService.shared.apply(features: feat, config: conf)
        }
        loggedIn = true
    }
}

struct EmptyResp: Decodable {}

// MARK: ════════════════════════════════════════
// REMOTE CONFIG SERVICE
// ════════════════════════════════════════════
@MainActor
final class ConfigService: ObservableObject {
    static let shared = ConfigService()
    private init() {}

    @Published var features:     FeaturesConfig = .defaults
    @Published var appConfig:    AppConfig      = .defaults
    @Published var maintenance:  Bool           = false

    func apply(features: FeaturesConfig, config: AppConfig) {
        self.features    = features
        self.appConfig   = config
        self.maintenance = config.maintenanceMode
        Store.shared.saveFeatures(features)
        Store.shared.saveAppConfig(config)
    }

    func fetchIfStale() async {
        if Store.shared.demoMode { return }                     // no backend in demo
        guard Store.shared.loginMode == .xtream else { return } // remote config is Xtream-only
        guard Store.shared.configStale else { return }
        do {
            let resp: RemoteConfigResponse = try await APIClient.shared.request(path: "/config/remote")
            apply(features: resp.features, config: resp.config)
            AppTheme.shared.apply(resp.theme)
            Store.shared.saveTheme(resp.theme)
            Store.shared.lastConfigFetch = Date()
        } catch { /* use cached */ }
    }

    func reset() {
        features = .defaults; appConfig = .defaults; maintenance = false
    }

    // Feature helpers
    var hasCatchUp:        Bool { features.catchUp }
    var hasEPG:            Bool { features.epg }
    var hasParental:       Bool { features.parentalControl }
    var hasSleepTimer:     Bool { features.sleepTimer }
    var hasWatchlist:      Bool { features.watchlist }
    var has4K:             Bool { features.quality4K }
}

// MARK: ════════════════════════════════════════
// FAVORITES SERVICE
// ════════════════════════════════════════════
@MainActor
final class FavoritesService: ObservableObject {
    static let shared = FavoritesService()
    private init() { load() }

    @Published var channels: Set<String> = []
    @Published var movies:   Set<String> = []
    @Published var series:   Set<String> = []

    func isChannelFav(_ id: String) -> Bool { channels.contains(id) }
    func isMovieFav(_ id: String)   -> Bool { movies.contains(id) }
    func isSeriesFav(_ id: String)  -> Bool { series.contains(id) }

    func toggleChannel(_ id: String) { toggle(&channels, id: id); save() }
    func toggleMovie(_ id: String)   { toggle(&movies,   id: id); save() }
    func toggleSeries(_ id: String)  { toggle(&series,   id: id); save() }

    private func toggle(_ set: inout Set<String>, id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func save() {
        Store.shared.favChannels = channels
        Store.shared.favMovies   = movies
        Store.shared.favSeries   = series
    }
    private func load() {
        channels = Store.shared.favChannels
        movies   = Store.shared.favMovies
        series   = Store.shared.favSeries
    }
    /// Re-read favorites for the now-active playlist scope (call on switch/login).
    func reload() { load() }
}

// MARK: ════════════════════════════════════════
// WATCH HISTORY SERVICE
// ════════════════════════════════════════════
@MainActor
final class HistoryService: ObservableObject {
    static let shared = HistoryService()
    private init() { items = Store.shared.loadHistory() }

    @Published var items: [WatchHistory] = []

    func update(contentID: String, type: WatchHistory.ContentType,
                name: String, posterURL: String?,
                progress: Double, duration: TimeInterval) {
        let entry = WatchHistory(
            id: contentID, contentID: contentID, contentType: type,
            contentName: name, posterURL: posterURL,
            progress: progress, duration: duration, lastWatched: Date()
        )
        items.removeAll { $0.contentID == contentID }
        items.insert(entry, at: 0)
        if items.count > 50 { items = Array(items.prefix(50)) }
        Store.shared.saveHistory(items)
    }

    func progress(for id: String) -> Double {
        items.first { $0.contentID == id }?.progress ?? 0
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
        Store.shared.saveHistory(items)
    }

    func clear() { items = []; Store.shared.saveHistory([]) }

    /// Reload from storage — called when the active playlist changes so history
    /// reflects the current playlist only.
    func reload() { items = Store.shared.loadHistory() }
}

// MARK: ════════════════════════════════════════
// WATCHLIST SERVICE
// ════════════════════════════════════════════
@MainActor
final class WatchlistService: ObservableObject {
    static let shared = WatchlistService()
    private init() { ids = Set(Store.shared.loadWatchlist()) }

    @Published var ids: Set<String> = []

    func isInList(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        Store.shared.saveWatchlist(Array(ids))
    }
    /// Re-read the watchlist for the now-active playlist scope.
    func reload() { ids = Set(Store.shared.loadWatchlist()) }
}

// ============================================================
// Parental Control — lock specific categories behind a PIN
// ============================================================
import CryptoKit

enum ParentalKind: String { case live, movie, series }

@MainActor
final class ParentalService: ObservableObject {
    static let shared = ParentalService()
    private init() {
        enabled = Store.shared.parentalEnabled
        locked  = Store.shared.lockedCategories
    }

    @Published var enabled: Bool
    @Published private(set) var locked: Set<String>
    /// Once the parent enters the PIN, locked categories open until app relaunch.
    @Published private(set) var sessionUnlocked = false

    var hasPIN: Bool { (Store.shared.parentalPIN ?? "").isEmpty == false }

    func setEnabled(_ on: Bool) {
        enabled = on
        Store.shared.parentalEnabled = on
        // Locks take effect IMMEDIATELY — do not auto-unlock the session on
        // enable. The session is unlocked only by entering the PIN (via
        // unlockSession), and re-locks on relaunch. This keeps the standard
        // parental-control behavior: lock it → it's locked → PIN to view.
        sessionUnlocked = false
    }

    func verify(_ pin: String) -> Bool {
        guard let saved = Store.shared.parentalPIN, !saved.isEmpty else { return false }
        return saved == Self.hash(pin)
    }

    /// First-time setup: store the PIN + generate a one-time recovery code
    /// (returned in plain text to show the user ONCE).
    func setupPIN(_ pin: String) -> String {
        Store.shared.parentalPIN = Self.hash(pin)
        let code = Self.randomCode()
        Store.shared.parentalRecovery = Self.hash(code)
        return code
    }
    /// Change the PIN (recovery code stays the same).
    func changePIN(_ pin: String) { Store.shared.parentalPIN = Self.hash(pin) }

    func verifyRecovery(_ code: String) -> Bool {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard let saved = Store.shared.parentalRecovery, !saved.isEmpty else { return false }
        return saved == Self.hash(c)
    }

    /// Full reset (used after recovery, or on logout).
    func resetAll() {
        Store.shared.parentalPIN = nil
        Store.shared.parentalRecovery = nil
        enabled = false; Store.shared.parentalEnabled = false
        sessionUnlocked = false
    }

    private static func randomCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // no ambiguous 0/O/1/I
        return String((0..<8).map { _ in chars.randomElement()! })
    }

    private func key(_ kind: ParentalKind, _ catID: String) -> String { "\(kind.rawValue):\(catID)" }
    func isLockedCategory(_ kind: ParentalKind, _ catID: String) -> Bool {
        locked.contains(key(kind, catID))
    }
    /// True when this category must be gated right now (enabled + locked + not yet unlocked).
    func isGated(_ kind: ParentalKind, _ catID: String) -> Bool {
        enabled && !sessionUnlocked && isLockedCategory(kind, catID)
    }
    func toggleLock(_ kind: ParentalKind, _ catID: String) {
        let k = key(kind, catID)
        if locked.contains(k) { locked.remove(k) } else { locked.insert(k) }
        Store.shared.lockedCategories = locked
    }
    /// Bulk lock/unlock a list of categories (for "lock all" / "unlock all").
    func setLockedBulk(_ kind: ParentalKind, ids: [String], _ lock: Bool) {
        var s = locked
        for id in ids { let k = key(kind, id); if lock { s.insert(k) } else { s.remove(k) } }
        locked = s
        Store.shared.lockedCategories = s
    }
    func unlockSession() { sessionUnlocked = true }
    func relock() { sessionUnlocked = false }

    static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
