// ============================================================
// BLANK TV — EngineStats.swift
// Lightweight, persistent counters that make the routing brain PROVABLE with
// numbers instead of subjective impressions. Every engine decision, every stable
// success, and every auto-failover is tallied and stored in UserDefaults. The
// Settings → Connection → "Playback Engine Diagnostics" panel reads these live.
//
// Not correctness-critical (a rare off-main miscount is harmless), so no locking.
// ============================================================

import Foundation

final class EngineStats {
    static let shared = EngineStats()
    private let key = "engineStats.v1"

    struct Snapshot: Codable {
        var opens       = 0   // total engine decisions (one per open/retry)
        var cacheHits   = 0   // opened on the remembered engine (instant)
        var cacheMisses = 0   // no memory yet → StreamRouter default
        var forced      = 0   // user pinned an engine in Settings
        var records     = 0   // stable successful plays (>2s) recorded
        var failovers   = 0   // first engine failed → auto-switched
        var avGood      = 0   // stable successes on AVPlayer
        var vlcGood     = 0   // stable successes on VLC
    }
    private(set) var snapshot: Snapshot

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = s
        } else {
            snapshot = Snapshot()
        }
    }

    enum DecisionSource { case forced, cache, defaultRoute }

    func noteDecision(_ src: DecisionSource) {
        snapshot.opens += 1
        switch src {
        case .forced:       snapshot.forced += 1
        case .cache:        snapshot.cacheHits += 1
        case .defaultRoute: snapshot.cacheMisses += 1
        }
        save()
    }

    func noteRecord(_ kind: PlayerEngineKind) {
        snapshot.records += 1
        switch kind {
        case .av:  snapshot.avGood += 1
        case .vlc: snapshot.vlcGood += 1
        }
        save()
    }

    func noteFailover() { snapshot.failovers += 1; save() }

    func reset() { snapshot = Snapshot(); save() }

    /// Cache-hit rate over AUTO (non-forced) opens, 0…1 — the headline "is the
    /// memory actually being used?" number.
    var hitRate: Double {
        let auto = snapshot.cacheHits + snapshot.cacheMisses
        return auto > 0 ? Double(snapshot.cacheHits) / Double(auto) : 0
    }
    /// Auto-failover rate over all opens, 0…1 — should trend DOWN as the cache learns.
    var failoverRate: Double {
        snapshot.opens > 0 ? Double(snapshot.failovers) / Double(snapshot.opens) : 0
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
