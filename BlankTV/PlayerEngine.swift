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
    @Published var isPlaying:      Bool   = false
    @Published var isLoading:      Bool   = true
    @Published var buffering:      Bool   = false
    // True only while a silent auto-retry is in flight (VLC engine) — lets the
    // spinner say "reconnecting" instead of "buffering" so the user knows we're
    // recovering, not stuck. Cleared the moment playback resumes or fails for good.
    @Published var reconnecting:   Bool   = false
    @Published var errorMsg:       String? = nil
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
    }
    func setItem(_ i: ContentItem) { item = i }

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
        switch item {
        case .movie(let m):
            if let local = DownloadService.completedFileURL(forContentID: m.id) { return local }
        case .episode(let ep, _):
            if let local = DownloadService.completedFileURL(forContentID: ep.id) { return local }
        case .live: break
        }
        return remoteURL(for: item)
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
        // Identify as VLC so strict IPTV panels don't reject the stream.
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": "VLC/3.0.20 LibVLC/3.0.20"]
        ])
        let pItem = AVPlayerItem(asset: asset)
        if !isLive { pItem.preferredForwardBufferDuration = 4 }    // VOD: modest forward buffer
        pItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        observe(pItem)
        avPlayer.replaceCurrentItem(with: pItem)
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
        setItem(newItem)
        didResume = false
        resumeTarget = BasePlayerVM.savedResume(for: newItem)
        currentTime = 0; duration = 0; isLoading = true; buffering = false; errorMsg = nil
        subtitleTracks = []; audioTracks = []; currentSubtitle = -1; currentAudio = -1
        setup()
    }

    override func cleanup() {
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
        statusObs = pItem.observe(\.status) { [weak self] it, _ in
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
                    self.loadSubtitles(); self.loadAudioTracks()
                    self.updateNowPlaying()
                case .failed:
                    self.errorMsg = L("player.err.failed")
                    self.isLoading = false
                default: break
                }
            }
        }
        bufferEmptyObs = pItem.observe(\.isPlaybackBufferEmpty) { [weak self] it, _ in
            let empty = it.isPlaybackBufferEmpty
            Task { @MainActor [weak self] in self?.buffering = empty }
        }
        likelyKeepUpObs = pItem.observe(\.isPlaybackLikelyToKeepUp) { [weak self] it, _ in
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
            // Once playback reaches the last requested seek, drop it so the next
            // ±10 skip accumulates from the live position, not a stale target.
            if let req = self.lastRequestedTime, !self.isChasing, abs(ct - req) < 1.0 {
                self.lastRequestedTime = nil
            }
            let playing = self.avPlayer.timeControlStatus == .playing
            if self.isPlaying != playing { self.isPlaying = playing }   // guard: no re-publish when unchanged
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
        let tol: CMTime = precise ? .zero : .positiveInfinity
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
    override func loadSubtitles() {
        guard let pItem = avPlayer.currentItem,
              let group = pItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            subtitleTracks = []; currentSubtitle = -1; return
        }
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
        guard let pItem = avPlayer.currentItem,
              let group = pItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
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
        guard let pItem = avPlayer.currentItem,
              let group = pItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            audioTracks = []; currentAudio = -1; return
        }
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
        guard let pItem = avPlayer.currentItem,
              let group = pItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else { return }
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
}

enum PlayerEngineSelector {
    static func preferAVPlayer(for item: ContentItem) -> Bool {
        guard let url = BasePlayerVM.resolvedURL(for: item)?.absoluteString.lowercased() else { return false }
        // Reliability-first hybrid: AVPlayer (hardware decode + native PiP) is used
        // ONLY for HLS (.m3u8 — typically live channels), where it clearly wins.
        // ALL VOD (mp4/mkv/avi…) and every LOCAL downloaded file play through VLC,
        // the proven engine for IPTV providers (tolerant of UA quirks + all codecs).
        // Users can still force an engine via Settings → Player → Playback engine.
        if url.hasPrefix("file:") { return false }
        return url.contains(".m3u8")
    }

    /// The engine to try FIRST, honouring the user's "Select Player" preference.
    static func initialKind(for item: ContentItem) -> PlayerEngineKind {
        switch Store.shared.playerEnginePref {
        case "av":  return .av
        case "vlc": return .vlc
        default:    return preferAVPlayer(for: item) ? .av : .vlc
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
