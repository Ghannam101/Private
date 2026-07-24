// ============================================================
// BLANK TV — StreamRouter.swift
// The routing "brain": classifies each stream, then picks the DEFAULT engine.
//
// It reproduces the app's proven reliability-first policy EXACTLY — AVPlayer only
// for HLS (.m3u8, typically live), VLC for every VOD / TS / MKV / AVI and every
// local downloaded file — now in ONE classified place, so future codec-aware
// rules have a single home. This file changes NO routing decision vs. the
// previous `PlayerEngineSelector.preferAVPlayer`; the behavioural upgrade ships in
// the persistent EngineDecisionCache, which PlayerEngineSelector consults first.
// ============================================================

import Foundation

/// Coarse container family derived from the resolved URL.
enum StreamContainer { case hls, mp4, ts, mkv, avi, unknown }

/// A lightweight, side-effect-free description of a stream.
struct StreamClass {
    let container: StreamContainer
    let isLive: Bool
    let isLocalFile: Bool
}

enum StreamRouter {
    /// Classify a stream from its resolved (offline-or-network) URL. Pure.
    static func classify(_ item: ContentItem) -> StreamClass {
        let url = (BasePlayerVM.resolvedURL(for: item)?.absoluteString.lowercased()) ?? ""
        let isLocal = url.hasPrefix("file:")
        let container: StreamContainer
        if url.contains(".m3u8") { container = .hls }
        else if url.hasSuffix(".ts") { container = .ts }
        else if url.hasSuffix(".mkv") { container = .mkv }
        else if url.hasSuffix(".avi") { container = .avi }
        else if url.hasSuffix(".mp4") || url.hasSuffix(".mov") || url.hasSuffix(".m4v") { container = .mp4 }
        else { container = .unknown }
        let live: Bool
        if case .live = item { live = true } else { live = false }
        return StreamClass(container: container, isLive: live, isLocalFile: isLocal)
    }

    /// The DEFAULT engine for a fresh stream (no user override, no cache hit).
    /// IDENTICAL policy to the previous `preferAVPlayer`: AVPlayer only for HLS,
    /// VLC for local files and everything else — the reliability-first hybrid.
    static func defaultEngine(for item: ContentItem) -> PlayerEngineKind {
        let s = classify(item)
        if s.isLocalFile { return .vlc }
        return s.container == .hls ? .av : .vlc
    }
}
