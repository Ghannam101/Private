// ============================================================
// BLANK TV — Reachability.swift
// The app had NO connectivity awareness of any kind. Offline, every screen showed
// either a spinner that never resolved or a generic "something went wrong", and the
// user was left to guess which of the two it was. For a player whose content lives
// entirely on someone else's server — often over mobile data — that is the single
// most common failure it will ever hit, and it was the one state it could not name.
//
// TWO SEPARATE JOBS, and they are kept separate on purpose:
//
//   `S8KNetLink` is pure. It turns a path's facts into the state the UI needs, and it is a
//   plain value with no Network import in its way, so it can be tested exhaustively
//   without a device, a simulator, or a Wi-Fi router.
//
//   `Reachability` is the plumbing. It owns the NWPathMonitor, hops to the main
//   actor, and publishes. There is nothing in it worth testing because there is
//   nothing in it to get wrong — which is the point of having drawn the line here.
// ============================================================

import Foundation
import Network

/// What the app needs to know about the connection, derived from one path.
///
/// PREFIXED, and not for tidiness. This was called `Link`, which is a SwiftUI VIEW —
/// `AuthViews.swift:527` builds one — so the plain name turned four unrelated lines
/// of a login screen into compile errors. Same class of collision as `Category`,
/// which the Objective-C runtime also owns. A short, obvious name is exactly the kind
/// most likely to be taken already; the S8K prefix is the house answer to that.
///
/// `satisfied` alone is not the answer. iOS reports a path as satisfied while Low
/// Data Mode is throttling it and while the only route is a cellular hotspot, and
/// those are different products for a video app: one should still stream, the other
/// should not start a background download the user pays for by the megabyte.
struct S8KNetLink: Equatable {
    /// A route exists. False means every request will fail — say so, do not spin.
    var isOnline: Bool
    /// Cellular, a personal hotspot, or another metered route.
    var isExpensive: Bool
    /// Low Data Mode. The system asks apps to defer discretionary transfers.
    var isConstrained: Bool

    /// Optimistic. The first path update lands a moment after launch, and starting
    /// at `false` would flash an offline banner on every cold start of a perfectly
    /// connected app — a lie that is worse than the silence being fixed.
    static let unknown = S8KNetLink(isOnline: true, isExpensive: false, isConstrained: false)

    /// Whether a large, deferrable transfer should begin right now.
    ///
    /// Separate from the Settings switch rather than merged with it: the switch is
    /// what the user asked for, this is what the network is currently doing, and a
    /// download needs both to agree. Low Data Mode is honoured even when the user
    /// left the Wi-Fi-only switch off, because the system asked us to.
    func allowsBulkTransfer(wifiOnly: Bool) -> Bool {
        guard isOnline, !isConstrained else { return false }
        return wifiOnly ? !isExpensive : true
    }
}

@MainActor
final class Reachability: ObservableObject {
    static let shared = Reachability()

    @Published private(set) var link: S8KNetLink = .unknown

    var isOnline: Bool { link.isOnline }

    /// Fires once on every transition from offline to online, and never on launch.
    ///
    /// This is what turns the monitor from a label into behaviour: a list that failed
    /// while the connection was down reloads itself the moment it comes back, instead
    /// of waiting for the user to discover a retry button.
    private var observers: [UUID: () -> Void] = [:]

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.blanktv.reachability", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor calls back on its own queue. Everything below touches
            // @Published state, so it has to arrive on the main actor.
            let next = S8KNetLink(isOnline: path.status == .satisfied,
                            isExpensive: path.isExpensive,
                            isConstrained: path.isConstrained)
            Task { @MainActor [weak self] in self?.apply(next) }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    private func apply(_ next: S8KNetLink) {
        let cameBack = !link.isOnline && next.isOnline
        guard next != link else { return }   // no churn on identical updates
        link = next
        if cameBack { observers.values.forEach { $0() } }
    }

    /// Register a reload to run when the connection returns. Returns a token; drop it
    /// with `stopWatching` when the screen goes away, or the closure outlives it.
    @discardableResult
    func onReconnect(_ work: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = work
        return id
    }

    func stopWatching(_ id: UUID) { observers[id] = nil }
}
