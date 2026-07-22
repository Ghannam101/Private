// ============================================================
// BLANK TV — ActivationService.swift
// INDEPENDENCE (M0a, 2026-07-22): BLANK TV is a fully independent, pure IPTV
// player. ALL dependency on the external management / control-panel server
// (strong8k.app: /v2/device/check + /v2/device/resolve) has been SEVERED.
//
// This service is now a LOCAL, always-allowed stub: it keeps the exact public
// @Published surface every screen consumes (gate, maintenance, notifications,
// brand, subscription fields…) so the app compiles and behaves normally, but it
// NEVER contacts any server. The device is always `.allowed` — the app opens
// straight to the subscription gate. Remote app-control (kill-switch, forced
// update, maintenance, push announcements) and server-driven reseller white-label
// are intentionally gone. The LOCAL BrandTheme mechanism (AppTheme.applyBrandTheme)
// is kept dormant so a future build-time white-label stays trivial.
// Subscription status/expiry now come from the user's Xtream `user_info` (Profile,
// milestone M6), not from an activation server.
// ============================================================

import Foundation
import SwiftUI
import UIKit

// MARK: - Notification model (kept: consumed by the bell / AlertsView).
// No longer server-delivered — the list stays empty until/unless a future LOCAL
// source populates it. Kept so all consumers compile unchanged.
struct AppNotification: Codable, Identifiable {
    let id:        Int
    let title:     String
    let body:      String
    let kind:      String   // info | warning | promo
    let createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id, title, body, kind
        case createdAt = "created_at"
    }
}

// MARK: - Service (local, always-allowed — no server)
@MainActor
final class ActivationService: ObservableObject {
    static let shared = ActivationService()
    private init() {
        // Independent app: allowed from the first frame, no round-trip, no gate wait.
        gate = .allowed
    }

    enum Gate: Equatable { case checking, allowed, denied, offline }

    // Always `.allowed` — an independent player is never gated by a server.
    @Published var gate:           Gate    = .allowed
    // Subscription fields — now sourced from Xtream `user_info` (Profile, M6),
    // empty here so nothing displays a stale server value.
    @Published var status:         String  = ""
    @Published var activationType: String  = ""
    @Published var daysLeft:       Int?    = nil
    @Published var expiresAt:      Double? = nil
    @Published var message:        String  = ""
    @Published var announcement:   String? = nil
    @Published var supportURL:     String? = nil
    @Published var notifications:  [AppNotification] = []
    @Published var lastError:      String? = nil

    // Remote app-control — permanently OFF (no control panel). Kept so the
    // Maintenance / Update / gate views still compile; they simply never trigger.
    @Published var maintenance:        Bool    = false
    @Published var maintenanceMessage: String? = nil
    @Published var minVersion:         String  = "1.0.0"
    @Published var latestVersion:      String? = nil
    @Published var updateURL:          String? = nil
    @Published var forceUpdate:        Bool    = false

    /// No server force-update path anymore → never required.
    var updateRequired: Bool { false }

    /// Compare dotted numeric versions: true if `a` < `b` (e.g. 1.9 < 1.10).
    /// Retained as a local utility (used by About / version checks elsewhere).
    static func versionLessThan(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    // Reseller branding — LOCAL only now (kept dormant for a future build-time
    // white-label). Server-driven reseller resolution has been removed.
    @Published var brandName:  String? = Store.shared.brandName
    @Published var brandColor: String? = Store.shared.brandColor
    @Published var brandLogo:  String? = Store.shared.brandLogo
    var isResellerMode: Bool { (Store.shared.resellerCode ?? "").isEmpty == false }

    /// Count of notifications newer than the last time the user opened the bell.
    var unreadCount: Int {
        let seen = UserDefaults.standard.integer(forKey: "s8k.notif.lastSeen")
        return notifications.filter { $0.id > seen }.count
    }
    func markNotificationsRead() {
        if let maxID = notifications.map(\.id).max() {
            UserDefaults.standard.set(maxID, forKey: "s8k.notif.lastSeen")
        }
        objectWillChange.send()
    }

    let deviceID = DeviceIdentity.current

    var isAllowed: Bool { true }   // independent — always entitled to run
    var isTrial:   Bool { false }

    // MARK: - Check (no-op — no server)
    /// Kept so existing call sites (app foreground, gate .task) compile. It simply
    /// guarantees the device stays allowed; it performs NO network request.
    func check() async {
        lastError = nil
        gate = .allowed
    }

    /// Reseller-code resolution used to call the server (/v2/device/resolve).
    /// Removed for independence — always fails cleanly (no server to resolve against).
    /// White-label, if reintroduced, will be a build-time/local config (owner decision).
    func resolveCode(_ code: String) async -> Bool { false }

    /// Clear reseller mode (revert to the official BLANK TV identity). LOCAL only.
    func clearReseller() {
        Store.shared.clearReseller()
        brandName = nil; brandColor = nil; brandLogo = nil
        AppTheme.shared.applyBrandTheme(hex: nil)
    }
}

// MARK: - Small helpers (local utilities, kept)
extension UIDevice {
    /// Marketing-ish model identifier (e.g. "iPhone15,3").
    var modelName: String {
        var info = utsname(); uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let id = mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(v)))) }
        }
        return id.isEmpty ? model : id
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
