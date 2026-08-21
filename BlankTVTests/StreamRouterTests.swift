// ============================================================
// BLANK TV — StreamRouterTests.swift
// The routing brain decides which of the two engines opens a stream. Getting it
// wrong is not a cosmetic bug: AVPlayer on an MKV shows a black screen with audio,
// and VLC on a live HLS ladder loses adaptive switching.
//
// Every case here sets `directURL`, so the router is exercised on a URL the test
// controls rather than one built from stored credentials. Nothing here touches the
// network, the Keychain, or any stored preference.
// ============================================================

import Foundation
import Testing
@testable import BlankTV

@Suite("StreamRouter.classify")
struct StreamRouterClassifyTests {

    private func movieItem(_ url: String) -> ContentItem {
        .movie(Fx.movie("m1", directURL: url))
    }
    private func liveItem(_ url: String) -> ContentItem {
        .live(Fx.channel("c1", directURL: url))
    }

    @Test("containers are recognised from the URL")
    func containerFromURL() {
        // Written out rather than parameterised: the pairs ARE the specification of
        // the router, and a reader should be able to see the whole table at once.
        #expect(StreamRouter.classify(movieItem("http://h/x/1.m3u8")).container == .hls)
        #expect(StreamRouter.classify(movieItem("http://h/x/1.ts")).container   == .ts)
        #expect(StreamRouter.classify(movieItem("http://h/x/1.mkv")).container  == .mkv)
        #expect(StreamRouter.classify(movieItem("http://h/x/1.avi")).container  == .avi)
        #expect(StreamRouter.classify(movieItem("http://h/x/1.mp4")).container  == .mp4)
        #expect(StreamRouter.classify(movieItem("http://h/x/1.mov")).container  == .mp4)
        #expect(StreamRouter.classify(movieItem("http://h/x/1.m4v")).container  == .mp4)
        #expect(StreamRouter.classify(movieItem("http://h/x/1.xyz")).container  == .unknown)
        #expect(StreamRouter.classify(movieItem("http://h/x/1")).container      == .unknown)
    }

    @Test("an uppercase extension classifies the same as lowercase")
    func caseInsensitive() {
        #expect(StreamRouter.classify(movieItem("http://h/X/1.MKV")).container == .mkv)
    }

    @Test("an HLS URL is recognised through a query string")
    func hlsWithQuery() {
        // `.m3u8` is matched anywhere in the URL, not only at the end, because
        // panels routinely append a token.
        #expect(StreamRouter.classify(movieItem("http://h/x/1.m3u8?token=abc")).container == .hls)
    }

    @Test("live and on-demand are distinguished by the item, not the URL")
    func liveFlagComesFromTheItem() {
        #expect(StreamRouter.classify(liveItem("http://h/x/1.m3u8")).isLive)
        #expect(StreamRouter.classify(movieItem("http://h/x/1.m3u8")).isLive == false)
    }

    @Test("a file URL is flagged as local")
    func localFileDetected() {
        let s = StreamRouter.classify(movieItem("file:///tmp/downloaded.mkv"))
        #expect(s.isLocalFile)
    }

    @Test("a network URL is not flagged as local")
    func networkIsNotLocal() {
        #expect(StreamRouter.classify(movieItem("http://h/x/1.mkv")).isLocalFile == false)
    }
}

@Suite("StreamRouter.defaultEngine")
struct StreamRouterEngineTests {

    private func movieItem(_ url: String) -> ContentItem {
        .movie(Fx.movie("m1", directURL: url))
    }
    private func liveItem(_ url: String) -> ContentItem {
        .live(Fx.channel("c1", directURL: url))
    }
    private func episodeItem(_ url: String) -> ContentItem {
        .episode(Fx.episode("e1", directURL: url), Fx.series("s1"))
    }

    @Test("HLS opens on the hardware engine")
    func hlsGoesToAVPlayer() {
        #expect(StreamRouter.defaultEngine(for: liveItem("http://h/live/1.m3u8")) == .av)
        #expect(StreamRouter.defaultEngine(for: movieItem("http://h/vod/1.m3u8")) == .av)
    }

    @Test("everything that is not HLS opens on VLC",
          arguments: ["http://h/x/1.mkv", "http://h/x/1.avi", "http://h/x/1.ts",
                      "http://h/x/1.mp4", "http://h/x/1.xyz"])
    func nonHLSGoesToVLC(_ url: String) {
        #expect(StreamRouter.defaultEngine(for: movieItem(url)) == .vlc)
    }

    @Test("a live channel that is not HLS still opens on VLC")
    func liveTSGoesToVLC() {
        // A great many panels serve live as raw MPEG-TS. Routing that to AVPlayer
        // because it is "live" would black-screen it.
        #expect(StreamRouter.defaultEngine(for: liveItem("http://h/live/1.ts")) == .vlc)
    }

    @Test("an episode routes by container exactly like a movie")
    func episodeRoutesByContainer() {
        #expect(StreamRouter.defaultEngine(for: episodeItem("http://h/s/1.mkv")) == .vlc)
        #expect(StreamRouter.defaultEngine(for: episodeItem("http://h/s/1.m3u8")) == .av)
    }

    @Test("a local file always opens on VLC, even when it is HLS")
    func localAlwaysVLC() {
        // The local check comes FIRST in the policy. A downloaded playlist has no
        // adaptive ladder to lose, and VLC is the engine that reads every container
        // we may have written to disk.
        #expect(StreamRouter.defaultEngine(for: movieItem("file:///tmp/x.mkv")) == .vlc)
        #expect(StreamRouter.defaultEngine(for: movieItem("file:///tmp/x.m3u8")) == .vlc)
    }
}

@Suite("PlayerEngineKind")
struct PlayerEngineKindTests {

    @Test("each engine names its opposite")
    func otherIsSymmetric() {
        #expect(PlayerEngineKind.av.other == .vlc)
        #expect(PlayerEngineKind.vlc.other == .av)
        #expect(PlayerEngineKind.av.other.other == .av)
    }

    @Test("the display name is the product name and is written in exactly one place")
    func displayNames() {
        // Settings and the diagnostics screen both read this property. They once
        // hard-coded four different names for these two engines.
        #expect(PlayerEngineKind.av.displayName == "AVPlayer")
        #expect(PlayerEngineKind.vlc.displayName == "VLC")
    }

    @Test("the raw values are the strings persisted in the decision cache")
    func rawValuesArePersistenceKeys() {
        #expect(PlayerEngineKind.av.rawValue == "av")
        #expect(PlayerEngineKind.vlc.rawValue == "vlc")
        #expect(PlayerEngineKind(rawValue: "av") == .av)
        #expect(PlayerEngineKind(rawValue: "vlc") == .vlc)
        #expect(PlayerEngineKind(rawValue: "ksplayer") == nil)
    }
}
