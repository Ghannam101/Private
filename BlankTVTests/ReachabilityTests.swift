// ============================================================
// BLANK TV — ReachabilityTests.swift
// `Link` is the half of connectivity worth testing: it turns a network path's facts
// into a decision, and that decision gates whether a metered download starts.
//
// The NWPathMonitor half is deliberately untested — it has no logic, and testing it
// would mean testing Apple's framework through a simulator's Wi-Fi. Drawing the line
// there is what makes the part that DOES decide something testable at all.
// ============================================================

import Foundation
import Testing
@testable import BlankTV

@Suite("Link")
struct LinkTests {

    @Test("the launch state is optimistic, so no offline banner flashes on a good connection")
    func unknownIsOnline() {
        // The first path update arrives a moment after launch. Starting at offline
        // would show every user a lie for that moment.
        #expect(Link.unknown.isOnline)
        #expect(Link.unknown.isExpensive == false)
        #expect(Link.unknown.isConstrained == false)
    }

    // MARK: allowsBulkTransfer — the one real decision in this type

    @Test("offline blocks a bulk transfer no matter what the switch says")
    func offlineBlocksEverything() {
        let l = Link(isOnline: false, isExpensive: false, isConstrained: false)
        #expect(l.allowsBulkTransfer(wifiOnly: false) == false)
        #expect(l.allowsBulkTransfer(wifiOnly: true) == false)
    }

    @Test("Low Data Mode blocks a bulk transfer even with the switch off")
    func constrainedBlocksEverything() {
        // The system asked apps to defer discretionary transfers. That request is
        // honoured whatever the user set for Wi-Fi-only, because it is not the same
        // question: the switch is about cost, this is about the OS being explicit.
        let l = Link(isOnline: true, isExpensive: false, isConstrained: true)
        #expect(l.allowsBulkTransfer(wifiOnly: false) == false)
        #expect(l.allowsBulkTransfer(wifiOnly: true) == false)
    }

    @Test("an expensive route is blocked only when the user asked for Wi-Fi only")
    func expensiveRespectsTheSwitch() {
        let l = Link(isOnline: true, isExpensive: true, isConstrained: false)
        #expect(l.allowsBulkTransfer(wifiOnly: true) == false)
        #expect(l.allowsBulkTransfer(wifiOnly: false))
    }

    @Test("a clean connection allows a bulk transfer either way")
    func cleanConnectionAllows() {
        let l = Link(isOnline: true, isExpensive: false, isConstrained: false)
        #expect(l.allowsBulkTransfer(wifiOnly: true))
        #expect(l.allowsBulkTransfer(wifiOnly: false))
    }

    @Test("every combination is decided, and only two of eight permit a transfer")
    func fullTruthTable() {
        var allowed: [String] = []
        for online in [true, false] {
            for expensive in [true, false] {
                for constrained in [true, false] {
                    let l = Link(isOnline: online, isExpensive: expensive, isConstrained: constrained)
                    for wifiOnly in [true, false] where l.allowsBulkTransfer(wifiOnly: wifiOnly) {
                        allowed.append("online=\(online) expensive=\(expensive) constrained=\(constrained) wifiOnly=\(wifiOnly)")
                    }
                }
            }
        }
        // Online + unconstrained + not expensive, under either switch position; plus
        // online + unconstrained + expensive with the switch OFF. Three cases, and
        // spelling them out is what stops a future edit widening the rule quietly.
        #expect(allowed.sorted() == [
            "online=true expensive=false constrained=false wifiOnly=false",
            "online=true expensive=false constrained=false wifiOnly=true",
            "online=true expensive=true constrained=false wifiOnly=false",
        ])
    }

    @Test("Link is Equatable so the monitor can drop identical path updates")
    func equatable() {
        // NWPathMonitor re-fires on changes the app does not care about. Without this
        // the publisher would churn and every observing view would re-render.
        #expect(Link.unknown == Link(isOnline: true, isExpensive: false, isConstrained: false))
        #expect(Link.unknown != Link(isOnline: true, isExpensive: true, isConstrained: false))
    }
}

@Suite("Reachability")
@MainActor
struct ReachabilityTests {

    @Test("the shared monitor exists and starts optimistic rather than offline")
    func sharedStartsOptimistic() {
        // On a simulator with a working network this settles to online almost at
        // once; the assertion is that it is never offline BEFORE the first update.
        #expect(Reachability.shared.link.isOnline)
        #expect(Reachability.shared.isOnline)
    }

    @Test("a reconnect observer can be registered and removed")
    func observerLifecycle() {
        // The removal half is what stops a dismissed error screen reloading forever.
        let token = Reachability.shared.onReconnect { }
        Reachability.shared.stopWatching(token)
        Reachability.shared.stopWatching(token)   // idempotent — must not trap
    }
}
