// ============================================================
// BLANK TV — EngineDecisionCache.swift
// Persistent per-content "last-known-good engine" memory.
//
// After a stream plays stably on an engine (>2s, no error), we remember it, keyed
// by the item's namespaced id (ContentItem.id → "live_…"/"movie_…"/"ep_…"). On the
// NEXT open, PlayerEngineSelector.initialKind consults this FIRST, so a channel
// that only decodes on VLC (or a movie that plays best on AVPlayer) opens instantly
// on the right engine instead of re-running the failover dance every time.
//
// Bounded (LRU-trimmed to `cap`) and stored in UserDefaults. Self-healing: if the
// remembered engine later fails, the failover's success on the OTHER engine records
// a fresh entry that overwrites the stale one. User's explicit engine choice in
// Settings bypasses this cache entirely (handled in initialKind).
// ============================================================

import Foundation

final class EngineDecisionCache {
    static let shared = EngineDecisionCache()

    private let key = "engineDecisionCache.v1"
    private let cap = 500                       // hard cap → no unbounded growth
    private struct Entry: Codable { let id: String; let engine: String }
    private var entries: [Entry]                // oldest → newest

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// The last engine that played this item stably, if remembered.
    func lastGood(for item: ContentItem) -> PlayerEngineKind? {
        let id = item.id
        guard let e = entries.last(where: { $0.id == id }) else { return nil }
        return PlayerEngineKind(rawValue: e.engine)
    }

    /// Remember `kind` as the good engine for `item`. Idempotent (skips a write when
    /// the newest entry already matches) and LRU-bounded to `cap`.
    func record(_ kind: PlayerEngineKind, for item: ContentItem) {
        let id = item.id
        if let last = entries.last, last.id == id, last.engine == kind.rawValue { return }
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, engine: kind.rawValue))
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Current remembered set, for the diagnostics panel: total + per-engine counts.
    func summary() -> (total: Int, av: Int, vlc: Int) {
        var av = 0, vlc = 0
        for e in entries {
            if e.engine == "av" { av += 1 } else if e.engine == "vlc" { vlc += 1 }
        }
        return (entries.count, av, vlc)
    }
}
