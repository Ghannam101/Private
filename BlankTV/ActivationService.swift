// ============================================================
// BLANK TV — ActivationService.swift
// Talks to the activation backend (device gating + credits)
// ============================================================

import Foundation
import SwiftUI
import UIKit

// MARK: - Config
enum ActivationConfig {
    /// Activation server over HTTPS via the domain (TLS by Let's Encrypt).
    /// Requires DNS A-record strong8k.app -> server IP + certbot done first.
    static let baseURL = "https://strong8k.app"
    /// Must match APP_KEY in the server's .env-vars.
    static let appKey  = "s8k_1ba20e7bead5716bb9e9b871fb71f3f304919f125dd62e91"
    /// Short — the check runs in the background (optimistic gate), and offline
    /// grace covers a slow/failed network, so we never make the user wait long.
    static let timeout: TimeInterval = 8
    /// How long an offline device may keep working on its last "allowed" check.
    static let offlineGrace: TimeInterval = 7 * 86400
}

// MARK: - Server response
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

struct ActivationResponse: Codable {
    let deviceID:       String
    let status:         String   // trial | active | expired | blocked
    let activationType: String
    let expiresAt:      Double?
    let daysLeft:       Int?
    let mode:           String
    let announcement:   String?
    let supportURL:     String?
    let brand:          Brand?
    // Optional + defaulted on apply: a 200 response that omits these (or a future
    // server change) must NOT throw a decode error and drop a first-time user to
    // the offline screen. Defaults are applied in apply().
    let minVersion:     String?
    let message:        String?
    let notifications:  [AppNotification]?

    // Remote app-control (App Control panel) — all optional / backward-compatible.
    let maintenance:        Bool?
    let maintenanceMessage: String?
    let latestVersion:      String?
    let updateURL:          String?
    let forceUpdate:        Bool?

    struct Brand: Codable { let name: String?; let logo: String?; let color: String? }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case status
        case activationType = "activation_type"
        case expiresAt = "expires_at"
        case daysLeft  = "days_left"
        case mode
        case announcement
        case supportURL = "support_url"
        case brand
        case minVersion = "min_version"
        case message
        case notifications
        case maintenance
        case maintenanceMessage = "maintenance_message"
        case latestVersion      = "latest_version"
        case updateURL          = "update_url"
        case forceUpdate        = "force_update"
    }
}

/// Server response for resolving a reseller code.
struct CodeResolveResponse: Codable {
    let ok: Bool
    let code: String?
    let brand: ActivationResponse.Brand?
    let hosts: [Host]?
    struct Host: Codable { let label: String?; let url: String?; let type: String? }
}

// MARK: - Service
@MainActor
final class ActivationService: ObservableObject {
    static let shared = ActivationService()
    private init() { loadCache() }

    enum Gate: Equatable { case checking, allowed, denied, offline }

    @Published var gate:         Gate    = .checking
    @Published var status:       String  = ""
    @Published var activationType: String = ""
    @Published var daysLeft:     Int?    = nil
    @Published var expiresAt:    Double? = nil
    @Published var message:      String  = ""
    @Published var announcement: String? = nil
    @Published var supportURL:   String? = nil
    @Published var notifications: [AppNotification] = []
    @Published var lastError:    String? = nil

    // Remote app-control (read from /v2/device/check). Fail-safe: all default to
    // "off", and are only ever turned ON by a LIVE successful check — so a parse
    // failure, offline launch, or missing field can never lock the user out.
    @Published var maintenance:        Bool   = false
    @Published var maintenanceMessage: String? = nil
    @Published var minVersion:         String = "1.0.0"
    @Published var latestVersion:      String? = nil
    @Published var updateURL:          String? = nil
    @Published var forceUpdate:        Bool   = false

    /// True only when the server forces an update AND the running build is older
    /// than min_version (real semantic-version comparison, not string compare).
    var updateRequired: Bool {
        forceUpdate && Self.versionLessThan(Bundle.main.appVersion, minVersion)
    }

    /// Compare dotted numeric versions: returns true if `a` < `b` (e.g. 1.9 < 1.10).
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

    // Reseller branding (from the entered code) — drives remote re-skin
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

    var isAllowed: Bool { status == "active" || status == "trial" }
    var isTrial:   Bool { status == "trial" }

    // MARK: - Check with backend
    func check() async {
        lastError = nil
        if gate == .denied || gate == .offline { gate = .checking }

        guard let url = URL(string: "\(ActivationConfig.baseURL)/v2/device/check") else {
            gate = .denied; message = "إعداد غير صالح"; return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = ActivationConfig.timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ActivationConfig.appKey, forHTTPHeaderField: "X-App-Key")
        var body: [String: String] = [
            "device_id":   deviceID,
            "model":       UIDevice.current.modelName,
            "app_version": Bundle.main.appVersion
        ]
        if let code = Store.shared.resellerCode, !code.isEmpty { body["code"] = code }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                // 403 wrong key, 400 bad id, etc.
                throw NSError(domain: "activation", code: http.statusCode)
            }
            let result = try JSONDecoder().decode(ActivationResponse.self, from: data)
            apply(result)
        } catch {
            handleOffline(error)
        }
    }

    /// Resolve a reseller code → store code + host + brand. Then call check()
    /// again so the device becomes auto-activated under that reseller.
    func resolveCode(_ code: String) async -> Bool {
        let c = code.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty,
              let enc = c.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(ActivationConfig.baseURL)/v2/device/resolve?code=\(enc)")
        else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = ActivationConfig.timeout
        req.setValue(ActivationConfig.appKey, forHTTPHeaderField: "X-App-Key")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let r = try JSONDecoder().decode(CodeResolveResponse.self, from: data)
            guard r.ok else { return false }
            Store.shared.resellerCode = r.code ?? c
            Store.shared.resellerHost = r.hosts?.first?.url
            Store.shared.brandName = r.brand?.name
            Store.shared.brandColor = r.brand?.color
            Store.shared.brandLogo = r.brand?.logo
            brandName = r.brand?.name; brandColor = r.brand?.color; brandLogo = r.brand?.logo
            AppTheme.shared.applyBrandTheme(hex: r.brand?.color)   // re-skin to the reseller
            await check()                      // becomes activated under the reseller
            // Report success on the ACTUAL entitlement, not merely that the code
            // resolved — otherwise the UI says "activated" while the gate stays
            // denied (e.g. the code is valid but the device isn't entitled yet).
            return gate == .allowed
        } catch { return false }
    }

    /// Clear reseller mode (revert to independent / BLANK TV branding).
    func clearReseller() {
        Store.shared.clearReseller()
        brandName = nil; brandColor = nil; brandLogo = nil
        AppTheme.shared.applyBrandTheme(hex: nil)   // back to the official BLANK TV identity
    }

    private func apply(_ r: ActivationResponse) {
        status         = r.status
        activationType = r.activationType
        daysLeft       = r.daysLeft
        expiresAt      = r.expiresAt
        message        = r.message ?? ""
        announcement   = r.announcement
        supportURL     = r.supportURL
        notifications  = r.notifications ?? []
        // Remote app-control (only ever set from this LIVE response)
        maintenance        = r.maintenance ?? false
        maintenanceMessage = r.maintenanceMessage
        minVersion         = (r.minVersion?.isEmpty == false) ? r.minVersion! : "1.0.0"
        latestVersion      = (r.latestVersion?.isEmpty == false) ? r.latestVersion : nil
        updateURL          = r.updateURL
        forceUpdate        = r.forceUpdate ?? false
        if let b = r.brand {
            Store.shared.brandName = b.name; Store.shared.brandColor = b.color; Store.shared.brandLogo = b.logo
            brandName = b.name; brandColor = b.color; brandLogo = b.logo
            AppTheme.shared.applyBrandTheme(hex: b.color)          // keep the app re-skinned
        }
        gate           = isAllowed ? .allowed : .denied
        cache(r)
    }

    /// If the network is unavailable but the device was recently allowed,
    /// keep it working (grace window) instead of locking the user out.
    private func handleOffline(_ error: Error) {
        lastError = error.localizedDescription
        if let cached = cachedAllowed(), cached {
            gate = .allowed
        } else if status.isEmpty {
            gate = .offline
            message = "تعذّر الاتصال بخادم التفعيل — تحقق من اتصالك"
        } else {
            gate = isAllowed ? .allowed : .denied
        }
    }

    // MARK: - Cache (offline grace)
    private func cache(_ r: ActivationResponse) {
        let ud = UserDefaults.standard
        ud.set(r.status, forKey: "s8k.act.status")
        ud.set(Date().timeIntervalSince1970, forKey: "s8k.act.ts")
    }
    private func loadCache() {
        status = UserDefaults.standard.string(forKey: "s8k.act.status") ?? ""
        // OPTIMISTIC GATE: if the device was recently allowed (within the offline
        // grace window), ENTER INSTANTLY and verify in the background instead of
        // making the user wait on the /check round-trip at every launch. Fail-safe:
        // this can only let a VALID user in faster — check() still downgrades to
        // .denied on a definitive server "not allowed", and handleOffline keeps the
        // 7-day grace. It never locks a paying user out.
        if cachedAllowed() == true { gate = .allowed }
    }
    private func cachedAllowed() -> Bool? {
        let ud = UserDefaults.standard
        let s  = ud.string(forKey: "s8k.act.status") ?? ""
        let ts = ud.double(forKey: "s8k.act.ts")
        guard ts > 0 else { return nil }
        let fresh = Date().timeIntervalSince1970 - ts < ActivationConfig.offlineGrace
        return fresh && (s == "active" || s == "trial")
    }
}

// MARK: - Small helpers
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
