// ============================================================
// BLANK TV — PlayerEngine.swift
// Hybrid playback engine abstraction.
//
// WHY: VLC (MobileVLCKit) is universal but software-decoded — higher battery /
// heat, slower start, and NO native Picture-in-Picture. AVPlayer is hardware-
// decoded (VideoToolbox), starts faster, supports LL-HLS, AirPlay and native
// PiP — but only plays HLS / fragmented-mp4 / progressive mp4/mov. So we run a
// HYBRID: AVPlayer for HLS & mp4/mov (the common live + VOD case), VLC as the
// universal fallback for TS / MKV / AVI / exotic codecs.
//
// `BasePlayerVM` is the shared surface `PlayerView` drives — both the VLC engine
// (VLCPlayerVM, reparented to this base) and the new AVPlayer engine conform to
// it, so the player UI is identical regardless of which engine is active.
//
// This file compiles standalone and does NOT change current behaviour until the
// factory is wired into PlayerView (next step).
// ============================================================

import SwiftUI
import AVKit
import AVFoundation
import MediaPlayer

// MARK: - Screen keep-awake (driven by the video engine, not SwiftUI lifecycle)
// EARLIER BUG: keep-awake was acquired/released from SwiftUI .onAppear/.onDisappear.
// On iPad's 3-pane live browser the inline preview's .onDisappear fires spuriously
// on re-layout while playback continues, which flipped the idle timer back ON
// mid-stream — so the screen dimmed even though video kept playing (no visible
// pause, just dimming).
//
// FIX: tie keep-awake to the PLAYER ENGINE itself. Each engine registers while it
// is set up and on every time-observer tick (~2x/sec), and unregisters on
// cleanup/deinit. Re-asserting on every tick is immune to view-lifecycle flicker
// or any system reset: while frames advance, the display CANNOT sleep. A set of
// active engines supports several players at once (iPad inline + full screen);
// normal auto-lock resumes only when the last engine stops.
enum KeepAwake {
    private static var active = Set<ObjectIdentifier>()
    /// Register `owner` as actively playing and keep the display awake.
    static func keep(_ owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        onMain {
            active.insert(id)
            if !UIApplication.shared.isIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
    /// Unregister `owner`; restore normal auto-lock once no engine is playing.
    static func relinquish(_ owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        onMain {
            active.remove(id)
            if active.isEmpty { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }
    private static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated { work() } }
        else { Task { @MainActor in work() } }
    }
}

// MARK: - Shared engine base
// All @Published playback state + helpers live here so PlayerView binds to ONE
// type. Concrete engines override the control methods + the video surface.
class BasePlayerVM: NSObject, ObservableObject {
    /// True once the decoder has actually put a picture on the surface.
    ///
    /// NOT the same as `isPlaying` or `!isLoading`: those flip when playback is
    /// underway, which on a remote MKV is still a beat before anything is visible.
    /// The gap is what the user reads as a black screen, so it needs its own signal.
    @Published var hasFirstFrame:  Bool   = false
    @Published var isPlaying:      Bool   = false
    @Published var isLoading:      Bool   = true
    /// Observed rather than merely published, so the rebuffer measurement lives in ONE
    /// place instead of being sprinkled through two engines that would drift apart.
    @Published var buffering:      Bool   = false { didSet { noteBuffering(oldValue) } }
    // True only while a silent auto-retry is in flight (VLC engine) — lets the
    // spinner say "reconnecting" instead of "buffering" so the user knows we're
    // recovering, not stuck. Cleared the moment playback resumes or fails for good.
    @Published var reconnecting:   Bool   = false
    /// Same reasoning as `buffering`: every terminal failure in either engine ends up
    /// assigned here, which makes this the only choke point both share.
    @Published var errorMsg:       String? = nil { didSet { noteError(oldValue) } }
    @Published var currentTime:    Double = 0       // seconds
    @Published var duration:       Double = 0       // seconds (0 for live)
    @Published var isMuted:        Bool   = false
    @Published var subtitleTracks: [(id: Int32, name: String)] = []
    @Published var currentSubtitle: Int32 = -1
    @Published var audioTracks:    [(id: Int32, name: String)] = []
    @Published var currentAudio:   Int32 = -1
    @Published var aspectIndex:    Int   = 0
    @Published var rate:           Float = 1.0
    @Published var subtitleFontSize: Int = Store.shared.subtitleFontSize   // px, 0 = auto

    private(set) var item: ContentItem
    var resumeTarget: Double                          // 0…1 saved position

    // Mid-stream stall monitor (shared by both engines): a wall-clock timer that
    // trips if playback started then froze while BUFFERING for a long stretch — a
    // dead source. The engines' start-watchdogs only cover "never started"; this
    // covers "died mid-play" so the user gets a retryable error instead of an
    // endless spinner. Gated on `buffering` so a USER PAUSE never trips it.
    private var stallMonitor: Timer?
    private var stallLastTime: Double = -1
    private var stallSeconds: Double = 0

    init(item: ContentItem) {
        self.item = item
        self.resumeTarget = BasePlayerVM.savedResume(for: item)
        super.init()
        // HERE, not only in setItem. The VM for the tap that OPENS the player is built
        // by the factory through this initialiser; setItem runs only for next-episode
        // and channel zap. Marking only there measured everything except the thing the
        // owner reports as slow.
        S8KPerf.begin("التشغيل ← أول إطار")
        // Closes the chain the tap opened. A no-op when nothing opened it — a failover
        // builds a second VM through here and the mark is already spent, and the
        // next-episode path never taps at all.
        S8KPerf.end("اللمسة ← المشغّل")
        // Counted BEFORE reporting, so `players_alive` includes this one: a clean open
        // reads 1, and 2 means the previous player was still in memory when this
        // stream was asked for.
        _ = Self.bumpLive(+1)
        reportRequested()
    }

    /// The end of a session, wherever it ends. See `reportEnded`.
    deinit {
        let remaining = Self.bumpLive(-1)
        reportEnded()
        // `via: deinit` — the view model was actually deallocated. `cleanup()` emits
        // the same event with `via: cleanup`. Both are recorded because they answer
        // DIFFERENT questions: cleanup stops VLC and releases the connection, deinit
        // means the object is gone. Seeing one without the other is the finding —
        // `playback_ended` has never once been recorded for a movie or an episode,
        // and until these two are separated there is no way to know which half failed.
        PanelClient.shared.track("player_released", ["via": "deinit", "players_alive": remaining])
        PanelClient.shared.flush()
    }

    /// Called by each engine's `cleanup()` override. Not merged into `reportEnded`:
    /// cleanup can run without deinit and deinit can run without cleanup, and telling
    /// those two apart is the entire point.
    func reportCleanup() {
        PanelClient.shared.track("player_released", [
            "via":           "cleanup",
            "kind":          contentKind,
            "players_alive": Self.liveNow,
        ])
    }

    func setItem(_ i: ContentItem) {
        // BEFORE `item` is reassigned. `reportEnded` reads `contentKind` off `item`, so
        // closing the session after the swap would file the episode you just finished
        // under the one you just started — and on a zap from a movie to a channel it
        // would move the watch time between content types entirely.
        //
        // Ended here rather than only in deinit because a zap or a next episode reuses
        // this same VM: without this the two sessions merge into one that appears to
        // last as long as the player stayed open.
        reportEnded()

        item = i; hasFirstFrame = false
        // Chain two: tap -> first video frame. Closed by `markFirstFrame` below.
        S8KPerf.begin("التشغيل ← أول إطار")
        reportRequested()
    }

    /// The single place either engine declares "there is a picture". Centralised so
    /// the measurement cannot drift between them.
    ///
    /// This is now a MEASUREMENT latch only — no view reads `hasFirstFrame`. It briefly
    /// also gated an artwork underlay over the video surface; the owner tested that on
    /// device and had it removed. The latch stays because it is what closes the
    /// tap-to-first-frame chain on the performance page, and that is the one number
    /// that tells us whether playback actually got faster.
    func markFirstFrame(_ note: String = "") {
        guard !hasFirstFrame else { return }
        S8KPerf.end("التشغيل ← أول إطار", note)
        hasFirstFrame = true   // no animation: nothing observes this any more
        reportStarted(engine: note)
    }

    // MARK: - CTA-2066 telemetry
    //
    // The Consumer Technology Association's streaming QoE standard, and its vocabulary
    // rather than one invented here: "startup time" then means what it means everywhere,
    // and the panel reading these needs no translation layer.
    //
    // All of it lives in the BASE class on purpose. Both engines inherit it, so the two
    // cannot drift into measuring different things and calling them the same name — the
    // failure mode that makes a metric worse than no metric.

    private var requestedAt   = Date()
    private var startedAt:      Date?
    private var bufferingSince: Date?
    private var reportedFailure = false

    /// movie / episode / live — the dimension every QoE number wants splitting by.
    private var contentKind: String {
        switch item {
        case .live:    return "live"
        case .movie:   return "movie"
        case .episode: return "episode"
        }
    }

    /// The container the provider says this is. Reported because the first measurement
    /// showed the SAME engine opening the SAME kind of content in 2.3s, 10.2s and
    /// 31.2s inside one session — so whatever varies is per-stream, and the container
    /// is the first per-stream property worth ruling in or out.
    private var contentExt: String {
        switch item {
        case .live:                return "m3u8"
        case .movie(let m):        return m.containerExtension.isEmpty ? "?" : m.containerExtension
        case .episode(let ep, _):  return ep.containerExtension.isEmpty ? "?" : ep.containerExtension
        }
    }

    /// HOW MANY PLAYER VIEW MODELS EXIST RIGHT NOW.
    ///
    /// This is a measurement, not a guard, and it exists to settle one question with
    /// evidence instead of argument: when a new stream is opened, is the PREVIOUS
    /// player still alive?
    ///
    /// It matters because Xtream lines cap concurrent connections — often at one — so
    /// a player that has not been torn down still holds the slot the next stream needs,
    /// and the next stream waits for the server to reap it. That would explain a first
    /// attempt producing no frame for 28 seconds and a rebuild then succeeding in 2.6.
    ///
    /// It would ALSO be explained by a slow provider, or by the container, or by
    /// something not yet thought of. `cleanup()` does call `player.stop()`, and it is
    /// called from `onDisappear` — so the leak is plausible and unproven, which is
    /// exactly why it is being counted rather than assumed.
    private static let liveCountLock = NSLock()
    private static var liveCount = 0
    private static func bumpLive(_ d: Int) -> Int {
        liveCountLock.lock(); defer { liveCountLock.unlock() }
        liveCount += d
        return liveCount
    }

    /// The viewer asked for video. Everything else is measured from here, including
    /// the ones who never get a picture at all.
    func reportRequested() {
        requestedAt = Date()
        startedAt = nil
        bufferingSince = nil
        reportedFailure = false
        PanelClient.shared.track("playback_requested", [
            "kind": contentKind,
            "ext":  contentExt,
            // >1 means a previous player was still in memory when this one opened. On a
            // line that allows one connection, that is the whole question.
            "players_alive": Self.liveNow,
        ])
    }

    /// Read without mutating — `bumpLive(0)` returns the current count under the lock.
    private static var liveNow: Int { bumpLive(0) }

    private func reportStarted(engine: String) {
        let now = Date()
        startedAt = now
        PanelClient.shared.track("playback_started", [
            "startup_ms": Int(now.timeIntervalSince(requestedAt) * 1000),
            "engine":     engine.isEmpty ? "unknown" : engine,
            "kind":       contentKind,
            "ext":        contentExt,
            // The resume hypothesis. The first real measurement came back `false` on
            // both slow opens, which killed it — kept because a refuted field that
            // keeps proving itself refuted is cheaper than re-arguing it.
            "resume":     resumeTarget > 0.02 && resumeTarget < 0.95,
        ])
        PanelClient.shared.startHeartbeat(content: nowPlayingTitle.0)
    }

    private func noteError(_ old: String?) {
        guard let msg = errorMsg, !msg.isEmpty, old == nil, !reportedFailure else { return }
        reportedFailure = true
        PanelClient.shared.track("playback_failed", [
            "kind":      contentKind,
            "reason":    msg,
            // A failure BEFORE the first frame is a start failure; one after it is an
            // interruption. The standard counts them differently and so should we.
            "had_frame": hasFirstFrame,
            "after_ms":  Int(Date().timeIntervalSince(requestedAt) * 1000),
        ])
        PanelClient.shared.flush()
    }

    private func noteBuffering(_ old: Bool) {
        // Only stalls AFTER playback began are rebuffering. The wait before the first
        // frame is startup time, and counting it twice would inflate both.
        guard hasFirstFrame else { bufferingSince = nil; return }
        if buffering, !old {
            bufferingSince = Date()
        } else if !buffering, let since = bufferingSince {
            bufferingSince = nil
            let ms = Int(Date().timeIntervalSince(since) * 1000)
            // Below a quarter second nobody saw a stall. Recording those would bury the
            // ones that matter in noise and make the ratio meaningless.
            if ms >= 250 { PanelClient.shared.track("rebuffer", ["ms": ms, "kind": contentKind]) }
        }
    }

    /// Closes the session. In `deinit` because it is the only point BOTH engines are
    /// guaranteed to reach: `cleanup()` is overridden by each of them and an override
    /// that forgets `super` would silently lose every ended session.
    private func reportEnded() {
        PanelClient.shared.stopHeartbeat()
        if let started = startedAt {
            PanelClient.shared.track("playback_ended", [
                "kind":       contentKind,
                "watched_ms": Int(Date().timeIntervalSince(started) * 1000),
            ])
        }
        PanelClient.shared.flush()
    }

    /// Start the mid-stream stall monitor (call from each engine's setup()).
    func startStallMonitor() {
        stallMonitor?.invalidate()
        stallLastTime = -1; stallSeconds = 0
        stallMonitor = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Only act once playback has started (currentTime>0) AND the engine is
            // buffering with a frozen clock. A user pause clears `buffering`, so the
            // guard resets the counter and never false-fires on an intentional pause.
            guard self.currentTime > 0, self.buffering, self.errorMsg == nil else {
                self.stallSeconds = 0; self.stallLastTime = self.currentTime; return
            }
            if self.currentTime > self.stallLastTime { self.stallSeconds = 0 }
            else { self.stallSeconds += 2 }
            self.stallLastTime = self.currentTime
            // 30s of continuous frozen buffering = a dead stream (no legitimate
            // rebuffer lasts that long). Surface a retryable error → failover/overlay.
            if self.stallSeconds >= 30 {
                self.stopStallMonitor()
                self.handleStallTimeout()
            }
        }
    }
    func stopStallMonitor() { stallMonitor?.invalidate(); stallMonitor = nil }

    /// Called when the mid-stream stall monitor trips (30s of frozen buffering).
    /// Base behaviour = surface a terminal, retryable error (the AVPlayer path; the
    /// PlayerView wrapper then fails over / shows the overlay). The VLC engine
    /// OVERRIDES this to attempt a bounded silent rebuild-retry first — a fresh
    /// player commonly un-sticks a wedged source before we give up.
    func handleStallTimeout() { errorMsg = L("player.err.interrupted") }

    static func savedResume(for item: ContentItem) -> Double {
        // `assumeIsolated` is safe ONLY on the main thread; guard so an off-main
        // construction degrades gracefully (no resume) instead of trapping.
        guard Thread.isMainThread else { return 0 }
        return MainActor.assumeIsolated {
            switch item {
            case .movie(let m):       return HistoryService.shared.progress(for: m.id)
            case .episode(let ep, _): return HistoryService.shared.progress(for: ep.id)
            case .live:               return 0
            }
        }
    }

    var isLive: Bool { if case .live = item { return true }; return false }

    /// The network source URL (direct M3U URL, else Xtream API URL) — no offline check.
    static func remoteURL(for item: ContentItem) -> URL? {
        switch item {
        case .live(let ch):
            if let d = ch.directURL { return URL(string: d) }
            return XtreamService.shared.liveURL(id: ch.id)
        case .movie(let m):
            if let d = m.directURL { return URL(string: d) }
            return XtreamService.shared.vodURL(id: m.id, ext: m.containerExtension)
        case .episode(let ep, _):
            if let d = ep.directURL { return URL(string: d) }
            return XtreamService.shared.seriesURL(episodeID: ep.id, ext: ep.containerExtension)
        }
    }

    /// Playable URL — prefers a COMPLETED offline download for this content
    /// (movies/episodes), so the player + hybrid engine use the local file with
    /// no internet. Falls back to the network source.
    static func resolvedURL(for item: ContentItem) -> URL? {
        // MEASURED AS A TALLY, not a sample, because this is asked several times for
        // one open — the engine router, the failover wrapper's body, and the engine's
        // own setup each call it independently and none of them caches.
        //
        // And it is not free for the two kinds the owner reports as slow: `.live`
        // returns straight to the network URL, while a movie or an episode first goes
        // through `completedFileURL`, which creates the downloads folder if absent and
        // then ENUMERATES it — a filesystem walk, on whichever thread asked, one of
        // them being a SwiftUI body. Whether that matters is exactly what a count and
        // a total answer and a guess does not.
        return S8KPerf.measure("حلّ الرابط") { () -> URL? in
            switch item {
            case .movie(let m):
                if let local = DownloadService.completedFileURL(forContentID: m.id) { return local }
            case .episode(let ep, _):
                if let local = DownloadService.completedFileURL(forContentID: ep.id) { return local }
            case .live: break
            }
            return remoteURL(for: item)
        }
    }

    // Aspect label (overridden per engine — VLC has 5 crop modes, AVPlayer 3).
    var aspectLabel: String { ["احتواء", "ملء", "تمدّد"][min(max(aspectIndex, 0), 2)] }

    // Progress helpers (shared)
    var progress: Double { duration > 0 ? currentTime / duration : 0 }
    func fmt(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "--:--" }
        let h = Int(t) / 3600, m = Int(t) % 3600 / 60, s = Int(t) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
    var currentFmt: String { fmt(currentTime) }
    var durationFmt: String { fmt(duration) }

    /// Lock-screen / Dynamic Island title (localized).
    var nowPlayingTitle: (String, String?) {
        switch item {
        case .live(let ch):           return (ch.name, nil)
        case .movie(let m):           return (m.name, m.year)
        case .episode(let ep, let s): return (s.name, "\(L("episode.number")) \(ep.episodeNumber)")
        }
    }

    /// Persist resume position to the watch history (shared by both engines).
    func saveProgress() {
        guard duration > 1 else { return }
        let p = progress, dur = duration, it = item
        Task { @MainActor in
            switch it {
            case .live(let ch):
                HistoryService.shared.update(contentID: ch.id, type: .live, name: ch.name,
                    posterURL: ch.logoURL, progress: p, duration: dur)
            case .movie(let m):
                HistoryService.shared.update(contentID: m.id, type: .movie, name: m.name,
                    posterURL: m.posterURL, progress: p, duration: dur)
            case .episode(let ep, let s):
                HistoryService.shared.update(contentID: ep.id, type: .episode,
                    name: "\(s.name) - \(L("episode.number")) \(ep.episodeNumber)",
                    posterURL: s.coverURL, progress: p, duration: dur)
            }
        }
    }

    // ── Overridable surface + controls (base = no-ops / defaults) ──
    func makeSurfaceView() -> UIView { UIView() }
    func setup() {}
    func load(_ newItem: ContentItem) { setItem(newItem) }
    func cleanup() {}
    func togglePlay() {}
    func play() {}
    func pause() {}
    func skip(_ seconds: Int32) {}
    func seek(to progress: Double) {}
    func seekToTime(_ seconds: Double) {}
    /// Two-phase scrubbing: begin (freeze audio), scrub (fast preview seeks while
    /// dragging), end (precise landing + resume). Base = no-ops.
    func beginScrub() {}
    func scrub(to progress: Double) {}
    func endScrub(to progress: Double) { seek(to: progress) }
    func toggleMute() {}
    func setVolume(_ v: Double) {}
    var currentVolume: Double { 1.0 }
    func boostSpeed(_ on: Bool) {}
    func setRate(_ r: Float) {}
    func cycleAspect() {}
    func loadSubtitles() {}
    func selectSubtitle(_ id: Int32) {}
    func loadAudioTracks() {}
    func selectAudio(_ id: Int32) {}
    /// Set the subtitle font size (px, 0 = auto), remember it app-wide, and apply it
    /// to the running stream. Engine applies via applySubtitleFontSize().
    func setSubtitleFontSize(_ px: Int) {
        subtitleFontSize = px
        Store.shared.subtitleFontSize = px
        applySubtitleFontSize()
    }
    func applySubtitleFontSize() {}   // engine-specific (VLC implements; AVPlayer n/a)
    /// Native PiP (AVPlayer engine only).
    func startPiP() {}
    var pipSupported: Bool { false }
}

// MARK: - AVPlayer engine (hardware-decoded HLS / mp4 / mov + native PiP)
final class AVPlayerVM: BasePlayerVM {
    let avPlayer = AVPlayer()

    private var didResume = false
    private var timeObserver: Any?
    private var statusObs: NSKeyValueObservation?
    private var bufferEmptyObs: NSKeyValueObservation?
    private var likelyKeepUpObs: NSKeyValueObservation?
    private var lastNP: Double = -10
    private weak var surface: AVPlayerLayerView?
    private var pipController: AVPictureInPictureController?
    private var stallWatchdog: Timer?
    private var videoWatchdog: Timer?

    // Seek coalescing ("chase the target"): AVPlayer doesn't cancel an in-flight
    // seek, so we keep only the newest destination and re-issue when the last
    // one lands. `lastRequestedTime` lets rapid ±10 skips accumulate off the
    // pending target instead of the stale (0.5s-old) currentTime.
    private var chaseTarget: CMTime = .invalid
    private var chasePrecise = false
    /// Whether the instant-start forward-buffer cap has been handed back to AVPlayer.
    private var bufferRelaxed = false
    private var isChasing = false
    private var lastRequestedTime: Double?
    private var wasPlayingBeforeScrub = false

    // AVPlayer can only resize the layer (no real crop like VLC) — 3 modes.
    private let gravities: [(label: String, gravity: AVLayerVideoGravity)] = [
        ("احتواء", .resizeAspect), ("ملء", .resizeAspectFill), ("تمدّد", .resize)
    ]
    override var aspectLabel: String { gravities[min(max(aspectIndex, 0), gravities.count - 1)].label }
    override var pipSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    // MARK: Surface + PiP
    override func makeSurfaceView() -> UIView {
        let v = AVPlayerLayerView()
        v.playerLayer.player = avPlayer
        surface = v
        v.playerLayer.videoGravity = gravityForCurrentAspect()
        // Re-evaluate on rotation so "fill" fills in landscape but doesn't zoom
        // enormously in portrait (returns to fit when flipped upright).
        v.onLayout = { [weak self] in
            guard let self else { return }
            self.surface?.playerLayer.videoGravity = self.gravityForCurrentAspect()
        }
        if Store.shared.pipEnabled, AVPictureInPictureController.isPictureInPictureSupported() {
            // init(playerLayer:) is failable on this SDK → keep the optional.
            let c = AVPictureInPictureController(playerLayer: v.playerLayer)
            c?.canStartPictureInPictureAutomaticallyFromInline = true   // auto-PiP on background
            pipController = c
        }
        return v
    }
    override func startPiP() {
        guard let c = pipController, !c.isPictureInPictureActive else { return }
        c.startPictureInPicture()
    }

    // MARK: Setup / teardown
    override func setup() {
        teardownObservers()
        guard let url = BasePlayerVM.resolvedURL(for: item) else {
            errorMsg = L("player.err.no_url"); isLoading = false; return
        }
        // Adopt a warm, already-buffering item if the detail page prewarmed this VOD
        // (near-instant start); otherwise build a fresh one. Identify as VLC so strict
        // IPTV panels don't reject the stream.
        let pItem: AVPlayerItem
        if let warm = MediaPrefetcher.shared.take(for: item) {
            pItem = warm
        } else {
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "VLC/3.0.20 LibVLC/3.0.20"]
            ])
            pItem = AVPlayerItem(asset: asset)
            if !isLive { pItem.preferredForwardBufferDuration = 1 }    // instant-start: 1 HLS chunk
        }
        pItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        observe(pItem)
        avPlayer.replaceCurrentItem(with: pItem)
        // ALWAYS true — including live. An earlier build set this to `!isLive` to make
        // channel zapping start sooner. That was wrong: Apple documents that with
        // automatic waiting DISABLED the player does not resume by itself after a
        // stall, so on a live channel a single buffer underrun froze the picture until
        // our own 30-second stall monitor gave up and surfaced an error. A slower start
        // is a far better trade than a channel that dies on the first hiccup.
        //
        // Nothing is lost: `playImmediately(atRate:)` on .readyToPlay already begins
        // playback the moment the first chunk lands, and by contract it ignores this
        // property — so the fast start was coming from there all along, not from
        // disabling stall recovery.
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        avPlayer.preventsDisplaySleepDuringVideoPlayback = true   // secondary keep-awake (idle timer handled by the view)
        avPlayer.play()
        isPlaying = true; isLoading = true; buffering = false; errorMsg = nil
        startStallWatchdog()
        startStallMonitor()   // catch a mid-stream freeze (dead source) → retryable error
        if isLive { startVideoWatchdog() }   // catch audio-only channels → fail over to VLC
        KeepAwake.keep(self)   // keep the screen awake while this engine is live

        NowPlayingManager.shared.onTogglePlay = { [weak self] in self?.togglePlay() }
        NowPlayingManager.shared.onSkip = { [weak self] s in self?.skip(Int32(s)) }
        NowPlayingManager.shared.configure()
        updateNowPlaying()
    }

    override func load(_ newItem: ContentItem) {
        // A cached group describes ONE asset. Carrying it into the next episode would
        // select a track index out of a playlist that no longer exists.
        legibleGroup = nil; audibleGroup = nil

        // Save the OUTGOING item first. cleanup() saves on teardown, but load() is the
        // zap / next-episode path and never calls it: watching episode 1 then tapping
        // episode 2 discarded episode 1's position, so a back-to-back session recorded
        // no "continue watching" for anything but the last thing played.
        saveProgress()
        setItem(newItem)
        // The next item gets its own instant start — without this reset the relaxed
        // buffer would carry over and the FIRST frame of every later episode would be
        // slow, which is the trade this cap exists to avoid.
        bufferRelaxed = false
        didResume = false
        resumeTarget = BasePlayerVM.savedResume(for: newItem)
        currentTime = 0; duration = 0; isLoading = true; buffering = false; errorMsg = nil
        subtitleTracks = []; audioTracks = []; currentSubtitle = -1; currentAudio = -1
        setup()
    }

    override func cleanup() {
        reportCleanup()
        saveProgress()
        teardownObservers()
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        pipController = nil
        NowPlayingManager.shared.clear()
        KeepAwake.relinquish(self)   // allow normal auto-lock once this engine stops
    }

    private func teardownObservers() {
        statusObs?.invalidate();       statusObs = nil
        bufferEmptyObs?.invalidate();  bufferEmptyObs = nil
        likelyKeepUpObs?.invalidate(); likelyKeepUpObs = nil
        if let t = timeObserver { avPlayer.removeTimeObserver(t); timeObserver = nil }
        stallWatchdog?.invalidate(); stallWatchdog = nil
        videoWatchdog?.invalidate(); videoWatchdog = nil
        stopStallMonitor()
    }
    deinit { teardownObservers(); KeepAwake.relinquish(self) }

    /// Slow-failing HLS often never reaches `.status == .failed` — it sits in
    /// buffering forever, so the failover (which keys off `errorMsg`) never fires
    /// and the user is stuck on an infinite spinner. If playback hasn't started
    /// after a grace window, surface an error so the wrapper can fail over to VLC.
    private func startStallWatchdog() {
        stallWatchdog?.invalidate()
        stallWatchdog = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Fires if playback never advanced past 0 within the grace window —
                // covers both "never became ready" and "ready then stalled at 0".
                if self.currentTime == 0, self.errorMsg == nil {
                    self.errorMsg = L("player.err.start_failed")
                }
            }
        }
    }

    /// Some live channels use a video codec AVPlayer can't decode: it plays the
    /// AUDIO with a black picture (the user's report), yet never reports `.failed`
    /// — so no failover fires. After a grace window, if playback is advancing but
    /// nothing has been rendered (layer not ready AND no presentation size), treat
    /// it as "no video on this engine" and surface an error so the wrapper fails
    /// over to VLC (which decodes it). A real video stream is ready well before
    /// this fires, so it won't false-positive.
    private func startVideoWatchdog() {
        videoWatchdog?.invalidate()
        videoWatchdog = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let ready = self.surface?.playerLayer.isReadyForDisplay ?? false
                let sized = (self.avPlayer.currentItem?.presentationSize ?? .zero) != .zero
                if self.currentTime > 0.5, !ready, !sized, self.errorMsg == nil {
                    self.errorMsg = "لا توجد صورة على هذا المحرك — جارٍ التبديل"
                }
            }
        }
    }

    private func observe(_ pItem: AVPlayerItem) {
        // `.initial` is not cosmetic. Plain `observe(_:)` fires on CHANGE only, so an
        // item that is ALREADY .readyToPlay when we attach never calls back and
        // `isLoading` stays true forever — a spinner sitting on top of a video that is
        // playing perfectly. That is not a rare race: MediaPrefetcher exists precisely
        // to hand `setup()` an item that finished preparing in another player. The same
        // applies to isPlaybackLikelyToKeepUp, which is the backstop for that spinner.
        statusObs = pItem.observe(\.status, options: [.initial, .new]) { [weak self] it, _ in
            let status = it.status
            let dur = it.duration.seconds
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                    // Keep the stall watchdog armed until playback actually ADVANCES
                    // (cancelled in the time observer on currentTime>0). A stream can
                    // reach .readyToPlay then stall at 0 forever — cancelling here
                    // would leave it spinning with no failover.
                    if self.duration == 0, dur.isFinite, dur > 0 { self.duration = dur }
                    self.resumeIfNeeded()
                    // Instant-start: begin the moment the first chunk is ready instead of
                    // waiting out the default stall-minimizing buffer (research-backed).
                    self.avPlayer.playImmediately(atRate: 1.0)
                    self.loadSubtitles(); self.loadAudioTracks()
                    self.updateNowPlaying()
                case .failed:
                    self.errorMsg = L("player.err.failed")
                    self.isLoading = false
                default: break
                }
            }
        }
        bufferEmptyObs = pItem.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] it, _ in
            let empty = it.isPlaybackBufferEmpty
            Task { @MainActor [weak self] in self?.buffering = empty }
        }
        likelyKeepUpObs = pItem.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] it, _ in
            let ok = it.isPlaybackLikelyToKeepUp
            Task { @MainActor [weak self] in if ok { self?.buffering = false; self?.isLoading = false } }
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            let secs = t.seconds
            let ct = secs.isFinite ? secs : 0
            if self.currentTime != ct { self.currentTime = ct }
            // Playback genuinely advanced → cancel the start/stall watchdog (it only
            // guards the "stuck at 0" case; a mid-stream stall is handled elsewhere).
            if ct > 0, self.stallWatchdog != nil { self.stallWatchdog?.invalidate(); self.stallWatchdog = nil }
            // …and hand buffering back to AVPlayer. `preferredForwardBufferDuration = 1`
            // exists to make the FIRST frame arrive fast; leaving it there for the rest
            // of the film means every seek lands with one chunk in hand and the picture
            // waits on the network to refill. That is what "seeking is slow" was.
            // 0 = automatic, which is what the property means, and AVPlayer then keeps
            // a healthy read-ahead. Done once, on the first real tick.
            if ct > 0, !self.isLive, self.bufferRelaxed == false {
                self.bufferRelaxed = true
                self.avPlayer.currentItem?.preferredForwardBufferDuration = 0
            }
            // Once playback reaches the last requested seek, drop it so the next
            // ±10 skip accumulates from the live position, not a stale target.
            // `|| ct > req`: the ±10 skip seeks with INFINITE tolerance, so on a
            // long-GOP file it can land several seconds past the request. The playhead
            // then starts beyond req + 1.0 and only grows, so the window never opened
            // and lastRequestedTime was stranded — ten minutes later the next +10 tap
            // computed from that stale value and jumped BACKWARDS.
            if let req = self.lastRequestedTime, !self.isChasing,
               abs(ct - req) < 1.0 || ct > req {
                self.lastRequestedTime = nil
            }
            let playing = self.avPlayer.timeControlStatus == .playing
            // guard: no re-publish when unchanged
            if self.isPlaying != playing { self.isPlaying = playing }
            // Playing AND the clock has moved => a picture is on screen.
            if !self.hasFirstFrame, playing, ct > 0 { self.markFirstFrame("AVPlayer") }
            if playing {
                KeepAwake.keep(self)   // re-assert every tick while playing
                // Belt-and-suspenders: a genuinely-playing stream is not stuck, even
                // if its timeline reports a degenerate 0 — cancel the start watchdog.
                if self.stallWatchdog != nil { self.stallWatchdog?.invalidate(); self.stallWatchdog = nil }
            }
            if self.duration == 0, let d = self.avPlayer.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
            self.resumeIfNeeded()
            if self.currentTime - self.lastNP >= 1 { self.lastNP = self.currentTime; self.updateNowPlaying() }
        }
    }

    private func resumeIfNeeded() {
        // `lastRequestedTime == nil` → never override an active/pending user seek
        // (e.g. the user scrubbed before the one-shot resume had a chance to apply).
        guard !didResume, !isLive, duration > 0, lastRequestedTime == nil,
              resumeTarget > 0.02, resumeTarget < 0.95 else { return }
        didResume = true
        avPlayer.seek(to: CMTime(seconds: resumeTarget * duration, preferredTimescale: 600))
    }

    func updateNowPlaying() {
        let t = nowPlayingTitle
        NowPlayingManager.shared.update(title: t.0, subtitle: t.1, duration: duration,
                                        elapsed: currentTime, rate: isPlaying ? rate : 0, isLive: isLive)
    }

    // MARK: Controls
    override func togglePlay() {
        if avPlayer.timeControlStatus == .playing { avPlayer.pause(); isPlaying = false }
        else { avPlayer.play(); if rate != 1.0 { avPlayer.rate = rate }; isPlaying = true }
        updateNowPlaying()
    }
    override func play()  { avPlayer.play(); isPlaying = true;  updateNowPlaying() }
    override func pause() { avPlayer.pause(); isPlaying = false; updateNowPlaying() }

    override func skip(_ seconds: Int32) {
        // Accumulate off the pending target so rapid taps land where the badge says
        // (currentTime alone is up to ~0.5s stale). Modest tolerance = fast + smooth.
        didResume = true                                // manual navigation cancels auto-resume
        let base = lastRequestedTime ?? currentTime
        let cap = duration > 0 ? duration : .greatestFiniteMagnitude
        let target = max(0, min(cap, base + Double(seconds)))
        lastRequestedTime = target
        chaseSeek(toSeconds: target, precise: false)
    }
    override func seek(to progress: Double) {
        guard duration > 0 else { return }
        let target = min(1, max(0, progress)) * duration
        lastRequestedTime = target
        chaseSeek(toSeconds: target, precise: true)
    }
    override func seekToTime(_ seconds: Double) {
        let target = max(0, seconds)
        lastRequestedTime = target
        chaseSeek(toSeconds: target, precise: true)
    }

    // Two-phase scrubbing: freeze audio, fast-preview while dragging, precise on release.
    override func beginScrub() {
        didResume = true                                // user is navigating → cancel one-shot auto-resume
        wasPlayingBeforeScrub = avPlayer.timeControlStatus == .playing
        if wasPlayingBeforeScrub { avPlayer.pause() }   // frame still updates on seek → live preview
    }
    override func scrub(to progress: Double) {
        guard duration > 0 else { return }
        let target = min(1, max(0, progress)) * duration
        lastRequestedTime = target
        chaseSeek(toSeconds: target, precise: false)     // fast (I-frame) preview
    }
    override func endScrub(to progress: Double) {
        guard duration > 0 else { if wasPlayingBeforeScrub { avPlayer.play() }; return }
        let target = min(1, max(0, progress)) * duration
        lastRequestedTime = target
        chaseSeek(toSeconds: target, precise: true)       // precise landing
        if wasPlayingBeforeScrub { avPlayer.play(); wasPlayingBeforeScrub = false }
    }

    /// Coalesced seek — keep only the newest target; re-issue when the last lands.
    private func chaseSeek(toSeconds seconds: Double, precise: Bool) {
        guard avPlayer.currentItem?.status == .readyToPlay else { return }
        chaseTarget = CMTime(seconds: seconds, preferredTimescale: 600)
        chasePrecise = precise
        if !isChasing { runChase() }
    }
    private func runChase() {
        isChasing = true
        let target = chaseTarget
        let precise = chasePrecise
        // NOT .zero. Zero tolerance forces the decoder to walk from the preceding
        // keyframe to the exact frame, which on a networked movie is seconds. A bounded
        // window lands on the next keyframe instead — invisible to the viewer, and the
        // difference between a seek that feels instant and one that does not.
        // Still bounded rather than .positiveInfinity, which would let it land anywhere.
        let tol: CMTime = precise ? CMTime(seconds: 0.6, preferredTimescale: 600)
                                  : .positiveInfinity
        avPlayer.seek(to: target, toleranceBefore: tol, toleranceAfter: tol) { [weak self] _ in
            guard let self else { return }
            // Target moved (or precision changed) while seeking → chase the newest.
            if CMTimeCompare(self.chaseTarget, target) != 0 || self.chasePrecise != precise {
                self.runChase()
            } else {
                self.isChasing = false
            }
        }
    }

    override func toggleMute() { isMuted.toggle(); avPlayer.isMuted = isMuted }
    override var currentVolume: Double { Double(avPlayer.volume) }
    override func setVolume(_ v: Double) {
        let vol = Float(max(0, min(1, v)))
        avPlayer.volume = vol; isMuted = vol <= 0.001
    }

    override func setRate(_ r: Float) {
        guard !isLive else { return }
        rate = r
        if avPlayer.timeControlStatus == .playing { avPlayer.rate = r }
        updateNowPlaying()
    }
    override func boostSpeed(_ on: Bool) {
        guard !isLive else { return }
        if on { avPlayer.rate = 2.0 }
        else if avPlayer.timeControlStatus == .playing { avPlayer.rate = rate }
    }

    override func cycleAspect() {
        aspectIndex = (aspectIndex + 1) % gravities.count
        surface?.playerLayer.videoGravity = gravityForCurrentAspect()
    }
    /// "ملء" (fill / .resizeAspectFill) covers the whole surface, which zooms
    /// ~16:9 content enormously in PORTRAIT. So in portrait we render fill as fit
    /// (.resizeAspect); landscape keeps the true edge-to-edge fill. Recomputed on
    /// rotation via the surface's onLayout, so flipping upright auto-returns to normal.
    private func gravityForCurrentAspect() -> AVLayerVideoGravity {
        let idx = min(max(aspectIndex, 0), gravities.count - 1)
        if idx == 1, let s = surface, s.bounds.height > s.bounds.width {
            return .resizeAspect
        }
        return gravities[idx].gravity
    }

    // MARK: Subtitles / audio via AVMediaSelectionGroup
    // MEDIA SELECTION IS LOADED ASYNCHRONOUSLY NOW, CACHED, AND REUSED.
    //
    // `asset.mediaSelectionGroup(forMediaCharacteristic:)` is synchronous and has been
    // deprecated since iOS 16. Apple states the reason plainly: if the property has not
    // already been loaded, the framework may need to do a significant amount of work to
    // return a value, and doing that on the main thread can leave the interface
    // unresponsive.
    //
    // For an HLS stream that work is a NETWORK FETCH of the master playlist media
    // groups. Both loaders were called from the `.readyToPlay` handler, on the main
    // actor, one line after `playImmediately(atRate: 1.0)` — so the app could block the
    // main thread on I/O at the exact moment the first frame is due. In an IPTV player,
    // time to first frame is the number a user judges everything else by.
    //
    // The groups are CACHED because `selectSubtitle` / `selectAudio` need the same
    // object on a user tap. Re-fetching there would move the stall rather than remove
    // it. The cache is cleared whenever the item changes.
    private var legibleGroup: AVMediaSelectionGroup?
    private var audibleGroup: AVMediaSelectionGroup?

    /// Load one selection group off the main actor, then hand it back on it.
    private func loadGroup(_ characteristic: AVMediaCharacteristic,
                           _ apply: @escaping @MainActor (AVMediaSelectionGroup?, AVPlayerItem) -> Void) {
        guard let pItem = avPlayer.currentItem else { return }
        let asset = pItem.asset
        Task.detached(priority: .userInitiated) { [weak self] in
            let group = try? await asset.loadMediaSelectionGroup(for: characteristic)
            await MainActor.run {
                // THE ITEM CAN CHANGE WHILE THIS IS IN FLIGHT — a zap, or the next
                // episode. Without this guard the late result describes the PREVIOUS
                // asset: it would list that asset's tracks against the new one, and
                // refill the cache `load()` has just cleared with a group belonging to
                // a playlist that is no longer playing. Dropping a stale answer is
                // free; the live item's own load is already on its way.
                guard let self, self.avPlayer.currentItem === pItem else { return }
                apply(group, pItem)
            }
        }
    }

    override func loadSubtitles() {
        if let group = legibleGroup, let pItem = avPlayer.currentItem {
            applyLegible(group, pItem); return
        }
        loadGroup(.legible) { [weak self] group, pItem in
            guard let self else { return }
            self.legibleGroup = group
            guard let group else { self.subtitleTracks = []; self.currentSubtitle = -1; return }
            self.applyLegible(group, pItem)
        }
    }

    /// No `@MainActor` attribute, and that is deliberate rather than an omission.
    ///
    /// `BasePlayerVM` is a plain class in this build — Swift 5 language mode, no
    /// default isolation — so `loadSubtitles()` overrides a nonisolated method and
    /// cannot call a main-actor one synchronously. Marking these two produced exactly
    /// that error on the CACHED path, which is the one that skips the await and is the
    /// whole reason the cache exists.
    ///
    /// Isolation still holds where it matters: the async path applies inside
    /// `MainActor.run`, and both callers of `loadSubtitles()` — the .readyToPlay
    /// handler and a button tap — are already on the main actor. Under default
    /// MainActor isolation this distinction disappears entirely.
    private func applyLegible(_ group: AVMediaSelectionGroup, _ pItem: AVPlayerItem) {
        subtitleTracks = group.options.enumerated().map { (id: Int32($0.offset), name: $0.element.displayName) }
        if let sel = pItem.currentMediaSelection.selectedMediaOption(in: group),
           let idx = group.options.firstIndex(of: sel) {
            currentSubtitle = Int32(idx)
        } else {
            currentSubtitle = -1
        }
        if let want = Store.shared.lastSubtitleName,
           let match = subtitleTracks.first(where: { $0.name == want }), match.id != currentSubtitle {
            selectSubtitle(match.id)
        }
    }

    override func selectSubtitle(_ id: Int32) {
        // The CACHED group only. A tap can reach this only after `loadSubtitles` filled
        // the sheet, so a miss means the item changed underneath us — and a synchronous
        // re-fetch here would reinstate the very stall this change removes.
        guard let pItem = avPlayer.currentItem, let group = legibleGroup else { return }
        if id < 0 {
            pItem.select(nil, in: group); currentSubtitle = -1; Store.shared.lastSubtitleName = nil; return
        }
        let i = Int(id)
        guard i < group.options.count else { return }
        pItem.select(group.options[i], in: group)
        currentSubtitle = id
        Store.shared.lastSubtitleName = group.options[i].displayName
    }

    override func loadAudioTracks() {
        if let group = audibleGroup, let pItem = avPlayer.currentItem {
            applyAudible(group, pItem); return
        }
        loadGroup(.audible) { [weak self] group, pItem in
            guard let self else { return }
            self.audibleGroup = group
            guard let group else { self.audioTracks = []; self.currentAudio = -1; return }
            self.applyAudible(group, pItem)
        }
    }

    /// Nonisolated for the same reason as `applyLegible` — see the note there.
    private func applyAudible(_ group: AVMediaSelectionGroup, _ pItem: AVPlayerItem) {
        audioTracks = group.options.enumerated().map { (id: Int32($0.offset), name: $0.element.displayName) }
        if let sel = pItem.currentMediaSelection.selectedMediaOption(in: group),
           let idx = group.options.firstIndex(of: sel) {
            currentAudio = Int32(idx)
        } else {
            currentAudio = audioTracks.isEmpty ? -1 : 0
        }
        if let want = Store.shared.lastAudioName,
           let match = audioTracks.first(where: { $0.name == want }), match.id != currentAudio {
            selectAudio(match.id)
        }
    }

    override func selectAudio(_ id: Int32) {
        guard let pItem = avPlayer.currentItem, let group = audibleGroup else { return }
        let i = Int(id)
        guard i >= 0, i < group.options.count else { return }
        pItem.select(group.options[i], in: group)
        currentAudio = id
        Store.shared.lastAudioName = group.options[i].displayName
    }
}

// MARK: - AVPlayer surface (AVPlayerLayer-backed UIView)
final class AVPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var onLayout: (() -> Void)?
    private var lastSize: CGSize = .zero
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .black }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize { lastSize = bounds.size; onLayout?() }
    }
}

// MARK: - Unified video surface (works for any engine)
struct PlayerSurfaceView: UIViewRepresentable {
    let vm: BasePlayerVM
    func makeUIView(context: Context) -> UIView { vm.makeSurfaceView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Engine selection
// HLS (.m3u8) and progressive mp4/mov/m4v → AVPlayer (hardware decode, native
// PiP, lower battery). Everything else (ts/mkv/avi/unknown) → VLC fallback.
enum PlayerEngineKind: String {
    case av, vlc
    var other: PlayerEngineKind { self == .av ? .vlc : .av }

    /// The engine's own name, and the ONLY place it is written.
    ///
    /// It had been written in two places with two different answers. Settings called
    /// these "Hardware (fastest)" and "Universal (VLC)"; the engine-diagnostics screen
    /// two rows below hard-coded "AVPlayer" and "VLC". Same two engines, four names, and
    /// a user who set one and then read the other had no way to know they were looking
    /// at the same thing. Reported from the device, and correctly.
    ///
    /// Not localised, deliberately: these are product names. AVPlayer is AVPlayer in
    /// every language, and translating it would put the app back to describing one thing
    /// two ways — which is the defect, not the fix. The plain-language part that DOES
    /// need translating lives beside it in `player.engine.av` / `.vlc`.
    var displayName: String {
        switch self {
        case .av:  return "AVPlayer"
        case .vlc: return "VLC"
        }
    }
}

enum PlayerEngineSelector {
    /// The engine to try FIRST. Priority order:
    ///  1) explicit user preference (Settings → Player → Playback engine),
    ///  2) the persistent per-content decision cache — last-known-good engine
    ///     (see EngineDecisionCache), so a replay opens instantly on the right one,
    ///  3) the StreamRouter default (reliability-first: HLS → AVPlayer, else VLC).
    static func initialKind(for item: ContentItem) -> PlayerEngineKind {
        // Measured because it is NOT the trivial lookup it reads as. The first call
        // decodes the whole persisted decision cache (up to 500 entries) out of
        // UserDefaults, and the miss path runs `StreamRouter.defaultEngine`, which
        // resolves the URL — the filesystem walk above, again.
        return S8KPerf.measure("اختيار المحرّك") { () -> PlayerEngineKind in
            switch Store.shared.playerEnginePref {
            case "av":  EngineStats.shared.noteDecision(.forced); return .av
            case "vlc": EngineStats.shared.noteDecision(.forced); return .vlc
            default:
                if let cached = EngineDecisionCache.shared.lastGood(for: item) {
                    EngineStats.shared.noteDecision(.cache); return cached
                }
                EngineStats.shared.noteDecision(.defaultRoute)
                return StreamRouter.defaultEngine(for: item)
            }
        }
    }
    /// Build a specific engine (used by the auto-failover wrapper).
    static func make(item: ContentItem, kind: PlayerEngineKind) -> BasePlayerVM {
        kind == .av ? AVPlayerVM(item: item) : VLCPlayerVM(item: item)
    }
    /// Build the preferred engine for an item (called on the main thread).
    static func make(item: ContentItem) -> BasePlayerVM {
        make(item: item, kind: initialKind(for: item))
    }
}
