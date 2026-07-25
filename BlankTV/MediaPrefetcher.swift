// ============================================================
// BLANK TV — MediaPrefetcher.swift
// Netflix-style warm-player pool: when a VOD detail page appears, we quietly build
// a muted AVPlayer that buffers the first HLS chunk BEFORE the user taps Play, so
// real playback starts near-instantly by adopting the already-buffering item.
// Bounded to `cap` warm items so memory never balloons; a backed-out prefetch is
// evicted. VOD only (live is fast-start already). Ported from the proven Strong8K
// implementation. Consumer wiring (AVPlayerVM.setup take + detail-page prefetch)
// lands in the next step.
// ============================================================

import Foundation
import AVFoundation

final class MediaPrefetcher {
    static let shared = MediaPrefetcher()
    private var warm: [String: (player: AVPlayer, item: AVPlayerItem, at: Date)] = [:]
    private let lock = NSLock()          // prefetch runs on main (onAppear); take from the engine
    private let cap = 2
    private init() {}

    private static func headerOptions() -> [String: Any] {
        ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "VLC/3.0.20 LibVLC/3.0.20"]]
    }

    /// Start warming a VOD item's first data. No-op for live, duplicates, or a missing URL.
    func prefetch(_ item: ContentItem) {
        if case .live = item { return }
        guard let url = BasePlayerVM.resolvedURL(for: item) else { return }
        let key = url.absoluteString
        lock.lock(); let exists = warm[key] != nil; lock.unlock()
        if exists { return }
        let pItem = AVPlayerItem(asset: AVURLAsset(url: url, options: Self.headerOptions()))
        pItem.preferredForwardBufferDuration = 1
        let p = AVPlayer(playerItem: pItem)
        p.automaticallyWaitsToMinimizeStalling = true
        p.isMuted = true                 // buffers toward ready with no audio/visual side-effect
        lock.lock()
        warm[key] = (p, pItem, Date())
        while warm.count > cap {          // evict the oldest OTHER warm item (bounded memory)
            guard let old = warm.filter({ $0.key != key }).min(by: { $0.value.at < $1.value.at })?.key else { break }
            warm.removeValue(forKey: old)?.player.replaceCurrentItem(with: nil)
        }
        lock.unlock()
    }

    /// Hand off the warmed item for playback, detaching it from the prewarm player. nil if not warm.
    func take(for item: ContentItem) -> AVPlayerItem? {
        guard let url = BasePlayerVM.resolvedURL(for: item) else { return nil }
        lock.lock(); let w = warm.removeValue(forKey: url.absoluteString); lock.unlock()
        guard let w else { return nil }
        w.player.replaceCurrentItem(with: nil)   // detach so the item can join the real player
        return w.item
    }

    /// Drop everything (e.g. on a memory warning).
    func clear() {
        lock.lock(); let all = Array(warm.values); warm.removeAll(); lock.unlock()
        all.forEach { $0.player.replaceCurrentItem(with: nil) }
    }
}
