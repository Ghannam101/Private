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
    private init() {
        // Before anything reads a credential: rewrite stored Keychain items so they
        // carry the current accessibility class. One-shot, guarded by a flag.
        Keychain.shared.upgradeAccessibilityIfNeeded()
        restore()
    }

    @Published var loggedIn:   Bool      = false
    @Published var isLoading:  Bool      = false
    @Published var error:      AppError? = nil
    @Published var user:       UserInfo? = nil
    @Published var serverInfo: ServerInfo? = nil
    @Published var mode:       LoginMode = .xtream

    // `login(username:password:)` is deleted with the backend it spoke to. It was the
    // one call that passed `requiresAuth: false`, and no screen ever invoked it —
    // `loginXtream` and `loginM3U` are the real doors, and both talk to the user's own
    // provider with no proxy in between.
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

        let url = Self.xtreamAPIURL(base: base, username: u, password: pass)

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
            activate(playlistID: Store.shared.upsertPlaylist(pl))   // stable scope id, leaves demo
            // MUST reset the shared VMs: this method also runs from "add account" while
            // ALREADY signed in, where the view models still hold the previous line's
            // catalog and `loaded == true` would make every load() early-return.
            ContentCache.reset()
            AppRouter.shared.contentReady = false   // remount the tabs → fetch this line
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
    /// The Xtream API URL for a line: `<base>/player_api.php?username=&password=`.
    ///
    /// EXTRACTED, and not for tidiness. It was inline in `loginXtream`, so
    /// `switchPlaylist` — the other place that has to produce this exact string —
    /// did not produce it at all, and that is the defect this function exists to
    /// close. One builder, one behaviour, and it is testable on its own.
    ///
    /// The encoding set subtracts `&=+` from `urlQueryAllowed`: a password containing
    /// any of those would otherwise pass through unescaped and split the query, which
    /// silently authenticates as a DIFFERENT user or fails with no useful message.
    static func xtreamAPIURL(base: String, username: String, password: String) -> String {
        let cs = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let u = username.addingPercentEncoding(withAllowedCharacters: cs) ?? username
        let p = password.addingPercentEncoding(withAllowedCharacters: cs) ?? password
        return "\(base)/player_api.php?username=\(u)&password=\(p)"
    }

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
            activate(playlistID: Store.shared.upsertPlaylist(p))   // stable scope id, leaves demo
            ContentCache.reset()                    // see loginXtream — same reason
            AppRouter.shared.contentReady = false   // remount the tabs → fetch this line
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

    /// Switch the active playlist and reload content from it. `false` = refused, and
    /// `error` says why; the previous session is left exactly as it was.
    ///
    /// The login FORM has always pre-flighted the line — `validateCredentials` — so an
    /// expired or banned subscription is rejected while the user is still looking at the
    /// screen they typed it on. A saved-account card did not. Same destination, same
    /// engine, and one of the two roads told you the truth.
    ///
    /// What that cost: tapping a line that had since expired signed you in. `loggedIn`
    /// went true, the tabs remounted, the boot loader fetched nothing, and the app sat
    /// there empty with no message. Nothing said "this subscription has ended" — the
    /// one sentence the user needed, and the one the form would have shown.
    ///
    /// The refusal is deliberately narrow. Only `AppError` blocks the switch, because
    /// that is what `validateAuth` throws when the PANEL has answered and its answer was
    /// no: auth != 1, or a status of expired / banned / disabled, or a reply with no
    /// parseable `user_info` at all. A timeout, a dropped connection, a captive portal —
    /// anything that is not `AppError` — is the network failing to deliver a verdict, not
    /// a verdict. Those let the switch through: the boot loader has its own retry and its
    /// own error, and locking a paying customer out of a working line because a hotel
    /// wifi blinked would be a worse bug than the one this fixes.
    ///
    /// Order matters and is the reason validation sits where it does. `m3uURL` must be
    /// set first because that is what `validateCredentials` reads. But the teardown —
    /// `PlaylistService.reset()`, `ContentCache.reset()`, `contentReady = false` — comes
    /// only AFTER the line has answered, so a refused switch never destroys the session
    /// the user is still in. On refusal the three restored values are all that changed.
    @discardableResult
    func switchPlaylist(_ p: SavedPlaylist) async -> Bool {
        if p.kind == .m3u {
            let prevURL  = Store.shared.m3uURL
            let prevLogin = Store.shared.loginMode
            let prevMode = mode

            Store.shared.m3uURL = p.url
            do {
                try await PlaylistService.shared.validateCredentials()
            } catch let e as AppError {
                Store.shared.m3uURL = prevURL       // nothing else has been touched yet
                Store.shared.loginMode = prevLogin
                mode = prevMode
                error = e
                return false
            } catch {
                // Not a verdict — the panel never answered. Fall through and let the
                // boot loader report it, the same as a line that goes down mid-session.
            }

            Store.shared.loginMode = .m3u
            mode = .m3u
            await PlaylistService.shared.reset()
        } else {
            // A LEGACY `.xtream` PLAYLIST, HEALED RATHER THAN HONOURED.
            //
            // No code in this build creates one — all three call sites of
            // `upsertPlaylist` write `kind: .m3u`, because `loginXtream` stores its
            // player_api URL in `m3uURL` and the two paths share one pipeline from
            // there. But saved playlists live in the Keychain and outlive builds, so an
            // install upgraded from an older version can still carry one.
            //
            // What stood here was broken in two ways at once, and silently:
            //   · it never set `m3uURL`, which is the key EVERY downstream reader uses
            //     — the catalogue, the SQLite scope, search — so switching to such a
            //     playlist loaded the PREVIOUS one's catalogue;
            //   · it set `loginMode = .xtream`, and no restore path accepts that, so
            //     the user was logged out on the next launch.
            //
            // Rebuilding the URL from the stored host/user/pass turns it into exactly
            // what a playlist created today looks like, so it heals on first use. There
            // is no world in which the old branch was preferable to this.
            let base = Self.normalizeXtreamHost(p.url)
            guard !base.isEmpty, let user = p.username, let pass = p.password,
                  !user.isEmpty, !pass.isEmpty else {
                error = .server(L("error.invalid_credentials"))
                return false
            }
            Keychain.shared.saveServerCredentials(host: base, user: user, pass: pass)
            Store.shared.m3uURL   = Self.xtreamAPIURL(base: base, username: user, password: pass)
            Store.shared.loginMode = .m3u      // the shared pipeline — see loginXtream
            mode = .m3u
            await PlaylistService.shared.reset()
        }
        error = nil
        activate(playlistID: p.id)              // leaves demo + per-playlist history/favorites/watchlist
        ContentCache.reset()
        AppRouter.shared.contentReady = false   // re-run the boot loader → fresh content
        return true
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
            activate(playlistID: scopeID)          // leaves demo
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
        //
        // The result is CHECKED, and that is new. `switchPlaylist` used to always
        // succeed; now it refuses a line the panel has rejected — and the most likely
        // moment to hit that is exactly here, deleting one dead subscription when the
        // only one left is dead too. Ignoring the refusal would leave activePlaylistID
        // pointing at the id just removed from the list: a scope with no playlist, whose
        // favourites and history were wiped two lines above. Nothing at all is better
        // than a pointer to something deleted.
        if wasActive {
            if let next = list.first, await switchPlaylist(next) { return }
            Store.shared.activePlaylistID = nil
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

    /// A real account becomes the active one. THE ONLY way to do that.
    ///
    /// Reported from a device: sign out, then try to get back into a subscription while
    /// moving between it and the demo, and the subscription will not take.
    ///
    /// `demoMode` had exactly one writer setting it true — `enterDemo` — and two setting
    /// it false: `logout` and `deleteAccount`. FIVE functions made a real account active
    /// (login, loginXtream, loginM3U, addM3UPlaylist, switchPlaylist) and not one of them
    /// said the demo was over. So entering a real account from inside the demo left the
    /// flag standing, and `Store.isDemo` short-circuits ELEVEN content accessors —
    /// channels, movies, series, categories, seasons, EPG. Every screen kept answering
    /// with `DemoContent` while the app believed it had signed the user in. It is not
    /// that the account was rejected; it is that nothing it fetched was ever displayed.
    ///
    /// Two more things went with it. `scopeID` is `demoMode ? "demo" : activePlaylistID`,
    /// so favourites, history and watchlist stayed in the demo bucket — the real account's
    /// were invisible and anything saved landed in the wrong one. And `restore()` opens
    /// with `if demoMode { loggedIn = true; return }`, so the next launch went straight
    /// back to the demo, which is why it did not look like a glitch but like a refusal.
    ///
    /// The fix is this function rather than five assignments, because the sixth caller
    /// written next year would have repeated it. Order is load-bearing and is why the
    /// two lines live together: `reloadScopedCaches` reads `scopeID`, which reads
    /// `demoMode` — clear the flag after it and the caches reload into "demo" anyway.
    func activate(playlistID: String) {
        Store.shared.demoMode = false          // must precede the scope read below
        Store.shared.activePlaylistID = playlistID
        reloadScopedCaches()
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
        // No backend call. There is no backend, and there was no session to end:
        // `Keychain.token` was never written by anything, so the guard this replaces
        // could not be true. Logout is entirely local, which is the honest shape for
        // an app that only ever held the user's own provider credentials.
        await PlaylistService.shared.reset()
        Store.shared.demoMode = false
        Keychain.shared.clearAll()
        Store.shared.clearSession()
        AppTheme.shared.reset()
        ContentCache.reset()
        AppRouter.shared.contentReady = false
        mode = .xtream
        user = nil; serverInfo = nil; loggedIn = false; error = nil
    }

    // MARK: - Delete Account (Apple Required)
    /// No longer `throws`, and that is a promise being made honest.
    ///
    /// It threw only for the backend DELETE, which is deleted — there is no server
    /// holding an account. Every step is local now and none of them can throw, so the
    /// `try?` at the call site was swallowing an error that could not occur while
    /// looking like it was swallowing one that could. Guideline 5.1.1(v) asks that the
    /// deletion actually happen; with no network in the path, it cannot half-happen.
    func deleteAccount() async {
        // The guard `logout()` always had, which this was missing. `enterDemo()` never
        // sets `mode`, so it kept the .xtream DEFAULT — and with no token the DELETE
        // threw `invalidCredentials` before reaching the network, the caller's `try?`
        // swallowed it, and EVERY line below was skipped. Nothing was deleted, no error
        // was shown, the sheet just closed. Three taps from a fresh install, and demo
        // mode is exactly where an App Store reviewer is: App Store Guideline 5.1.1(v).
        // No backend call — see logout(). Everything 5.1.1(v) requires happens below
        // and locally: Keychain, saved playlists, downloads, both catalogue stores,
        // the whole UserDefaults domain, and the parental PIN.
        await PlaylistService.shared.reset()
        Store.shared.demoMode = false
        Keychain.shared.clearAll()
        // Everything below this line is what "delete all my data" actually has to
        // reach. Logout deliberately keeps all of it; deletion must not.
        //
        // `purgeSavedPlaylists` is here and NOT in `clearAll()` for a reason that used to
        // be automatic and no longer is. The accounts used to live in UserDefaults, so
        // `Store.clearAll()` below — which removes the whole persistent domain — swept
        // them up for free. They are in the Keychain now, and a Keychain item survives
        // deleting the APP, let alone a defaults wipe. Without this line "delete my
        // account" would leave every saved provider password on the device: the exact
        // 5.1.1(v) failure the comment above this function records happening once
        // already, reintroduced by a change made to improve security.
        Store.shared.purgeSavedPlaylists()
        Keychain.shared.deleteDeviceID()        // a Keychain item outlives the APP itself
        DownloadService.shared.clearAll()       // the downloaded files on disk
        CatalogDiskCache.purgeAll()             // every cached catalogue, all scopes
        await Task.detached(priority: .utility) { CatalogDB.deleteEverything() }.value
        Store.shared.clearAll()                 // wipes the whole UserDefaults domain
        AppTheme.shared.reset()
        // The palette no longer needs reverting: there is nothing that can change it at
        // runtime any more. `clearReseller` stays, and is now purely a migration — it
        // erases brand keys left in UserDefaults by a build from before 2026-07-22.
        ActivationService.shared.clearReseller()
        ContentCache.reset()                    // previous-user config/content lingers
        ParentalService.shared.resetAll()       // account deletion clears the parental PIN too
        AppRouter.shared.contentReady = false
        mode = .xtream
        user = nil; serverInfo = nil; loggedIn = false; error = nil
    }

    // `validateSession()` is deleted. It existed to ask a backend whether a token was
    // still good; there is no backend and there was never a token. Its callers went
    // with it — a foreground handler that did nothing and a `.task` that awaited it.

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
        // NOTHING ELSE RESTORES, and that is not a change.
        //
        // What stood here was a second branch that required `Keychain.tokenValid`.
        // No code ever wrote a token, so the guard could not pass and this branch had
        // never restored a session — it returned early on every launch. Deleting it
        // preserves behaviour exactly; keeping it would have preserved the appearance
        // of a second login path instead.
        //
        // Every real session comes back through the branch above. `loginXtream` stores
        // its `player_api.php` URL in `m3uURL` and sets `loginMode = .m3u` on purpose,
        // because the Xtream-credentials and raw-M3U paths share one pipeline from
        // that point on. So an Xtream user is restored by the M3U branch — verified by
        // reading `loginXtream`, not assumed from the names.
        //
        // That consequence has now been acted on: `ConfigService` is deleted, and with
        // it the three UI branches and the parental-control flag it fed. See the note
        // where the class used to live.
    }
}


// `ConfigService` IS DELETED.
//
// It held `features`, `appConfig` and `maintenance`, all fetched from a backend that
// no longer exists. After the severance nothing could write them, so every consumer
// read `.defaults` forever: `storeURL`, `supportWhatsApp`, `supportTelegram` and
// `announcement` were permanently nil, and `hasParental` permanently true.
//
// Removing it is not only cleanup. It deletes the mechanism behind finding L-3 — a
// server able to change the app after review, including switching parental controls
// off. Guideline 2.5.2 is written about exactly that, and the safest version of a
// remote kill for a user-facing safety control is one that cannot be built because
// the type is gone.
//
// `FeaturesConfig`, `AppConfig` and `ThemeConfig` stay in Models: `Store` still reads
// what an older build wrote, and deleting the types would break that decode for no
// gain.

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
        // Cap PER TYPE, not globally. This is an IPTV app: flicking through channels
        // writes a `.live` row per channel, so a single zapping session used to push
        // 50 rows in and evict the episode progress that the series "resume" button
        // reads — watch episode 9, browse live for a minute, and the series was back
        // to episode 1. `items` is already most-recent-first, so one pass keeps the
        // newest 50 of each kind and preserves the order.
        if items.count > 150 {
            var kept: [WatchHistory] = []
            var seen: [WatchHistory.ContentType: Int] = [:]
            for it in items {
                let n = (seen[it.contentType] ?? 0) + 1
                seen[it.contentType] = n
                if n <= 50 { kept.append(it) }
            }
            items = kept
        }
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
