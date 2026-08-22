// ============================================================
// BLANK TV — PanelClient.swift
// The app's only line to the owner panel: presence, and quality-of-experience
// measurements. It sends; it takes no orders.
// ============================================================

import Foundation
import UIKit

/// Build-time configuration. Both values are on the buyer's checklist in HANDOVER.md:
/// a buyer running their own panel changes the URL here and sets their own key in CI.
enum PanelConfig {
    /// A build constant rather than something fetched at runtime, deliberately.
    /// Anything that arrives over the network can be changed after review, and an app
    /// that learns where to report from a server it has not yet authenticated can be
    /// pointed at a different server by whoever answers first.
    static let baseURL = URL(string: "https://panel.8k.site/api/v1")

    /// Gates REGISTRATION only, and it is NOT IN THIS REPOSITORY.
    ///
    /// It is injected into Info.plist at build time from the `BLANKTV_APP_KEY`
    /// environment variable (see codemagic.yaml). The reason is the resale model: a
    /// buyer receives this source, and a key committed here would hand every buyer the
    /// owner's panel credential along with it.
    ///
    /// Be honest about what it is. It ships inside the binary, so `strings` finds it —
    /// that is true of every client-side app key and claiming otherwise would be worse
    /// than admitting it. What it buys is that forging a device means registering
    /// first, and a registration is one rate-limited row carrying an IP and a
    /// timestamp. The real protection is the per-device token the panel issues in
    /// exchange, which is bound to one device_id and cannot write for any other.
    ///
    /// Empty in a local build with no CI variable set. Registration then fails closed
    /// and the whole client goes quiet — which is the correct behaviour for a
    /// measurement system that cannot identify itself, and is why `isConfigured`
    /// guards every entry point.
    static var appKey: String {
        (Bundle.main.infoDictionary?["BLANKTVPanelKey"] as? String) ?? ""
    }

    /// Under the panel's 120s presence window, so one dropped beat does not move a
    /// watching viewer into the offline column.
    static let heartbeatInterval: TimeInterval = 45

    static var isConfigured: Bool { baseURL != nil && !appKey.isEmpty }
}

/// Sends presence and measurements. Never blocks anything, never fails loudly, and
/// never changes what the app does.
///
/// THE ONE-WAY RULE, and it is a constraint rather than an omission. This type has no
/// method that reads behaviour from the panel. Guideline 2.5.2 bans downloading code
/// that changes features, and 2.3.1 bans shipping behaviour a reviewer never saw.
/// Remote config within those limits is permitted and ordinary — but the moment a
/// client can be told what to do, every later question about this app becomes "what
/// was it told at the time". Measurements travel out. Nothing travels in.
final class PanelClient {
    static let shared = PanelClient()
    private init() {}

    private let lock = NSLock()
    private var queue: [[String: Any]] = []
    private var beat: Timer?
    private var registering = false
    private var flushing = false

    /// A queue that grows without bound through a long outage is a memory leak with an
    /// explanation. Oldest go first: the newest failure is the one worth keeping.
    private let cap = 500

    // MARK: - Registration

    /// Exchange the app key for a per-device token, once. Idempotent on both sides —
    /// the panel returns the existing token for a device it already knows, so a
    /// reinstall that restored the Keychain identity keeps its history instead of
    /// forking into a second row.
    private func withToken(_ use: @escaping (String) -> Void) {
        if let t = Keychain.shared.panelToken, !t.isEmpty { use(t); return }

        lock.lock()
        // One registration in flight, not one per queued event: without this a burst
        // of events on a fresh install fires a burst of identical registrations and
        // spends the endpoint's rate limit on itself.
        if registering { lock.unlock(); return }
        registering = true
        lock.unlock()

        guard let url = PanelConfig.baseURL?.appendingPathComponent("register") else {
            lock.lock(); registering = false; lock.unlock(); return
        }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(PanelConfig.appKey, forHTTPHeaderField: "X-App-Key")
        r.httpBody = try? JSONSerialization.data(withJSONObject: Self.identity())

        URLSession.shared.dataTask(with: r) { [weak self] data, _, _ in
            guard let self else { return }
            self.lock.lock(); self.registering = false; self.lock.unlock()
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = obj["token"] as? String, !token.isEmpty else { return }
            Keychain.shared.panelToken = token
            use(token)
        }.resume()
    }

    /// What the panel needs to tell one install from another, and nothing more. No
    /// account, no playlist URL, no credential: those describe the USER, and the user
    /// is not what this reports on.
    private static func identity() -> [String: Any] {
        [
            "device_id":   DeviceIdentity.current,
            "platform":    "ios",
            "model":       UIDevice.current.model,
            "os_version":  UIDevice.current.systemVersion,
            "app_version": Self.appVersion,
        ]
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    // MARK: - Presence

    /// Beat while something is playing. `content` is the human title, so a live session
    /// on the panel says what is being watched rather than only that someone is there.
    func startHeartbeat(content: String?) {
        stopHeartbeat()
        guard PanelConfig.isConfigured else { return }
        sendHeartbeat(content: content)
        // `.common` so the beat survives a scroll. The default run-loop mode is paused
        // while a UIScrollView tracks a finger, and a viewer browsing the guide would
        // otherwise blink out of the online column for as long as their thumb moves.
        let t = Timer(timeInterval: PanelConfig.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat(content: content)
        }
        RunLoop.main.add(t, forMode: .common)
        beat = t
    }

    func stopHeartbeat() {
        beat?.invalidate()
        beat = nil
    }

    private func sendHeartbeat(content: String?) {
        var body = Self.identity()
        if let content, !content.isEmpty { body["content"] = String(content.prefix(200)) }
        post("heartbeat", body: body) { _ in }
    }

    // MARK: - Measurements

    /// Record one CTA-2066 event. Returns immediately; nothing here sits on a path a
    /// user is waiting on.
    func track(_ event: String, _ properties: [String: Any] = [:]) {
        guard PanelConfig.isConfigured else { return }
        let row: [String: Any] = [
            "event": event,
            "occurred_at": Self.iso.string(from: Date()),
            "properties": properties,
        ]
        lock.lock()
        queue.append(row)
        if queue.count > cap { queue.removeFirst(queue.count - cap) }
        let count = queue.count
        lock.unlock()

        // Batched on purpose. The events worth having are emitted exactly when the app
        // is busiest — opening a stream — and a player that spends the first frame's
        // budget on HTTP requests about how slow the first frame was has instrumented
        // itself into the problem it is measuring.
        if count >= 20 { flush() }
    }

    /// Send what is queued. Safe to call often; one flush runs at a time.
    func flush() {
        guard PanelConfig.isConfigured else { return }
        lock.lock()
        guard !flushing, !queue.isEmpty else { lock.unlock(); return }
        flushing = true
        let batch = Array(queue.prefix(100))
        lock.unlock()

        var body = Self.identity()
        body["events"] = batch

        post("events", body: body) { [weak self] ok in
            guard let self else { return }
            self.lock.lock()
            // Drop only what the server said it took. Clearing on "the request did not
            // throw" loses a batch the server rejected; never clearing sends the same
            // batch forever.
            if ok { self.queue.removeFirst(min(batch.count, self.queue.count)) }
            self.flushing = false
            let more = !self.queue.isEmpty
            self.lock.unlock()
            if ok && more { self.flush() }
        }
    }

    // MARK: - Transport

    private func post(_ path: String, body: [String: Any], done: @escaping (Bool) -> Void) {
        guard let url = PanelConfig.baseURL?.appendingPathComponent(path) else { done(false); return }
        withToken { token in
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.timeoutInterval = 20
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: r) { _, resp, err in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                // A 401 means the panel no longer knows this token — a rotated key, a
                // deleted row. Forget it, so the next call registers again instead of
                // retrying a credential that can never work.
                if code == 401 { Keychain.shared.panelToken = nil }
                done(err == nil && (200..<300).contains(code))
            }.resume()
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
