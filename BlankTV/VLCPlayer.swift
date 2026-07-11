// ============================================================
// BLANK TV — VLCPlayer.swift
// MobileVLCKit engine — plays HLS/m3u8/TS/MKV/AVI & all IPTV formats
// ============================================================

import SwiftUI
import MobileVLCKit
import MediaPlayer
import AVFoundation
import AVKit

// MARK: - System volume control (so the gesture moves the real device volume)
final class SystemVolume {
    static let shared = SystemVolume()
    let view = MPVolumeView(frame: .zero)
    private var slider: UISlider? { view.subviews.compactMap { $0 as? UISlider }.first }
    func set(_ v: Float) {
        let clamped = max(0, min(1, v))
        // The volume gesture is already on the main thread — set synchronously so the
        // real volume tracks the finger with no run-loop-hop lag; only hop if off-main.
        if Thread.isMainThread { slider?.value = clamped }
        else { DispatchQueue.main.async { self.slider?.value = clamped } }
    }
    var current: Float { AVAudioSession.sharedInstance().outputVolume }
}

/// VLC renders into this view. It reports layout changes (rotation, size class)
/// so the VM can recompute the "fill" crop — which depends on the live surface size.
final class VLCSurfaceView: UIView {
    var onLayout: (() -> Void)?
    private var lastSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            onLayout?()
        }
    }
}

/// Invisible MPVolumeView that must live in the hierarchy for volume control.
struct SystemVolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = SystemVolume.shared.view
        v.alpha = 0.001
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: MPVolumeView, context: Context) {}
}

// MARK: - VLC ViewModel
// VLCPlayerVM is the universal (software-decoded) engine. It is now a subclass
// of BasePlayerVM (see PlayerEngine.swift) so PlayerView can drive it or the
// hardware AVPlayer engine through one shared API. All @Published playback state
// + helpers (progress, fmt, savedResume, isLive, saveProgress, nowPlayingTitle)
// live in the base; only VLC-specific bits remain here.
final class VLCPlayerVM: BasePlayerVM, VLCMediaPlayerDelegate {

    // `var` (not `let`): the smart-retry path rebuilds a FRESH VLCMediaPlayer on the
    // same surface, because libVLC can stay wedged after a .error state.
    private(set) var player = VLCMediaPlayer()
    private var lastVolume: Int32 = 100
    private var didResume = false
    /// The live render surface — used to size the "fill" crop to the actual screen.
    private weak var surfaceView: UIView?
    /// Fires if playback never starts within a grace window (stuck on "buffering"),
    /// so the wrapper can fail over to the other engine instead of hanging forever.
    private var startWatchdog: Timer?

    // MARK: Smart-retry (Phase 2) — recover intermittent stream/VOD failures
    // On a transient .error, rebuild a fresh player+media and resume at the drop
    // point, up to `maxRetries` times, BEFORE surfacing the fatal overlay. Bounded
    // so a genuinely dead stream can't loop forever: the budget only refreshes
    // after ≥5s of real playback (see mediaPlayerTimeChanged).
    private var retryCount = 0
    private let maxRetries = 2
    private var retryTimer: Timer?
    /// Absolute playback position (seconds) captured when a retry is scheduled. The
    /// budget only refreshes after 5s of playback PAST this anchor — using the
    /// absolute currentTime directly would be wrong for VOD (a resumed retry starts
    /// at e.g. 3600s, instantly > 5), which would make the 2-retry ceiling unbounded.
    private var retryAnchor: Double = 0

    // Aspect/zoom presets cycled by the player's "حجم الشاشة" button.
    // (label, aspectRatio string, cropGeometry string) — "" means auto/none.
    let aspectModes: [(label: String, ratio: String, crop: String)] = [
        ("احتواء",   "",       ""),       // default: fit, preserve aspect (letterbox)
        ("ملء",      "",       "screen"), // crop to the DEVICE screen aspect → true edge-to-edge fill
        ("تمدّد",     "16:9",   ""),       // stretch to 16:9
        ("4:3",      "4:3",   ""),
        ("16:10",    "16:10", "")
    ]

    override init(item: ContentItem) {
        super.init(item: item)
        player.delegate = self
    }

    /// VLC renders into this UIView (the unified surface used by PlayerView,
    /// replacing the old standalone VLCVideoView).
    override func makeSurfaceView() -> UIView {
        let view = VLCSurfaceView()
        view.backgroundColor = .black
        // On rotation / size change, re-apply the chosen aspect (the "fill" crop is
        // screen-relative, so it must follow the surface).
        view.onLayout = { [weak self] in
            guard let self, self.aspectIndex != 0 else { return }
            self.applyAspect()
        }
        player.drawable = view
        surfaceView = view
        return view
    }

    /// Switch to a new item (e.g. the next episode) without recreating the VM.
    override func load(_ newItem: ContentItem) {
        setItem(newItem)
        // Cancel any in-flight retry from the PREVIOUS item and give the new item a
        // fresh budget (otherwise a pending rebuild could fire onto the new stream).
        retryTimer?.invalidate(); retryTimer = nil
        retryCount = 0; retryAnchor = 0; reconnecting = false
        // If we switch item DURING a retry backoff, scheduleRetry() had nil'd the
        // delegate and the pending rebuild is now cancelled — re-attach so setup()'s
        // fresh media on this player still delivers state/time callbacks.
        player.delegate = self
        lastTickTime = -1   // a stale tick from the previous item must not block "advanced"
        didResume = false
        resumeTarget = BasePlayerVM.savedResume(for: newItem)
        currentTime = 0; duration = 0
        isLoading = true; buffering = false; errorMsg = nil
        // Reset per-stream track state so the NEW item re-discovers its own
        // subtitle/audio tracks (the .playing handler reloads only when these are
        // empty). Without this, next-episode / channel-zap kept the PREVIOUS item's
        // tracks and could re-apply a stale index. Mirrors AVPlayerVM.load().
        subtitleTracks = []; audioTracks = []; currentSubtitle = -1; currentAudio = -1
        setup()
    }

    /// Jump to an absolute time in seconds (used by "skip intro").
    override func seekToTime(_ seconds: Double) {
        guard duration > 0 else { return }
        player.position = Float(min(1, max(0, seconds / duration)))
    }

    /// Seek to the saved position once playback has a known duration (VOD only).
    private func resumeIfNeeded() {
        guard !didResume, !isLive, duration > 0,
              resumeTarget > 0.02, resumeTarget < 0.95 else { return }
        didResume = true
        player.position = Float(resumeTarget)
    }

    /// Try to silently recover from a transient .error (the intermittent Xtream-VOD
    /// failure the customer reported): after a short backoff, rebuild a FRESH
    /// player+media and resume where playback dropped. Returns true if a retry was
    /// scheduled — so the caller MUST NOT show the fatal overlay. Bounded by
    /// `maxRetries`; the budget only refreshes after ≥5s of real playback, so a
    /// stream that errors instantly can never loop forever.
    private func scheduleRetry() -> Bool {
        guard retryCount < maxRetries, streamURL != nil else { return false }
        retryCount += 1
        // Anchor the "5s of real playback" / stuck-start checks to where the FRESH
        // player will resume from: the drop point for VOD, but 0 for LIVE (live
        // rebuild does NOT seek — its clock restarts from ~0, so anchoring to the
        // old player's large time would falsely flag a healthy fresh live stream).
        retryAnchor = isLive ? 0 : currentTime
        // Silence the wedged old player for the whole backoff window so a LATE stale
        // .error from it can't re-enter the funnel and double-consume the retry
        // budget (rebuildAndPlay tears it down fully). The fresh player re-attaches
        // its own delegate.
        player.delegate = nil
        // Resume at the drop point (VOD only), not from the start.
        if !isLive, duration > 0, currentTime > 0 {
            resumeTarget = min(0.95, max(0, currentTime / duration))
            didResume = false
        }
        startWatchdog?.invalidate(); startWatchdog = nil
        stopStallMonitor()
        errorMsg = nil
        isLoading = true; buffering = true; reconnecting = true
        // Short, escalating backoff: 0.6s then 1.2s (matches TiviMate/Smarters-style
        // reconnect cadence) — long enough for a transient drop to clear, short
        // enough to feel instant.
        let delay: TimeInterval = retryCount == 1 ? 0.6 : 1.2
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.rebuildAndPlay()
        }
        return true
    }

    /// Tear down the (possibly wedged) VLC player and start a CLEAN one on the same
    /// surface. A fresh instance is the reliable recovery from libVLC's post-.error
    /// stuck state (mirrors how mature IPTV clients recover). Clearing the track
    /// lists makes the .playing handler re-discover this stream's tracks and re-apply
    /// the remembered subtitle/audio language + custom subtitle size.
    private func rebuildAndPlay() {
        guard let url = streamURL else {
            reconnecting = false
            errorMsg = L("player.err.failed"); isLoading = false; return
        }
        // Detach the old player first (nil drawable before releasing) so the shared
        // surface is never briefly owned by two players.
        let old = player
        old.delegate = nil
        old.stop()
        old.drawable = nil
        let fresh = VLCMediaPlayer()
        fresh.delegate = self
        if let surface = surfaceView { fresh.drawable = surface }
        player = fresh
        lastTickTime = -1   // fresh player: let the first advancing tick register
        subtitleTracks = []; audioTracks = []; currentSubtitle = -1; currentAudio = -1
        player.media = makeMedia(url)
        player.play()
        isPlaying = true
        player.rate = rate
        startStartWatchdog()
        startStallMonitor()
        if aspectIndex != 0 { applyAspect() }   // re-apply the chosen fill/zoom
    }

    /// Single failure funnel (Phase 3). EVERY playback failure — an explicit VLC
    /// .error, a stuck start (watchdog), or a mid-stream stall — routes here. It
    /// first attempts a bounded silent recovery (scheduleRetry → fresh player +
    /// resume); only when the retry budget is exhausted does it surface the terminal
    /// message. This mirrors ExoPlayer's proven model: transient failures retry a
    /// bounded number of times before the error is surfaced. (MobileVLCKit can't
    /// expose the HTTP status to distinguish a 403/404 "terminal" from a timeout
    /// "retryable", so treating every failure as retryable up to the bound is the
    /// correct, safe choice — it recovers the common transient case and still fails
    /// fast enough via the bound.)
    private func attemptRecoveryOrFail(_ terminalMessage: String) {
        if scheduleRetry() { return }
        reconnecting = false
        startWatchdog?.invalidate(); startWatchdog = nil
        stopStallMonitor()
        if errorMsg == nil { errorMsg = terminalMessage }
        isLoading = false; buffering = false
    }

    /// Mid-stream stall (30s frozen) → same bounded recovery as any other failure.
    override func handleStallTimeout() {
        attemptRecoveryOrFail(L("player.err.interrupted"))
    }

    /// Build a VLCMedia with the reliability options. Centralised so the initial
    /// play AND the retry path (below) apply the EXACT same tuning to a fresh media.
    private func makeMedia(_ url: URL) -> VLCMedia {
        let media = VLCMedia(url: url)
        // Identify as a player so strict IPTV panels don't 403 the stream (UA is
        // per-media on purpose — the global UA has a known HTTPS bug in VLC 3.0.x).
        media.addOption(":http-user-agent=VLC/3.0.20 LibVLC/3.0.20")
        // Auto-reconnect on a transient HTTP drop instead of going straight to .error
        // — the #1 intermittent Xtream-VOD failure (default is OFF). Verified against
        // the VideoLAN http module docs.
        media.addOption(":http-reconnect")
        // Prebuffer 1500ms: rides out micro-drops (reliability-leaning; lowering it
        // trades reliability for a little start speed, and the symptom here is failures).
        media.addOption(":network-caching=1500")
        return media
    }

    // MARK: - Setup
    override func setup() {
        guard let url = streamURL else {
            errorMsg = L("player.err.no_url"); isLoading = false; return
        }
        player.media = makeMedia(url)
        player.play()
        isPlaying = true
        isLoading = true
        player.rate = rate
        startStartWatchdog()   // don't hang forever on a stuck "buffering"
        startStallMonitor()    // catch a mid-stream freeze (dead source) → retryable error
        KeepAwake.keep(self)   // keep the screen awake while this engine is live
        // Lock-screen / Control Center / Dynamic Island remote controls
        NowPlayingManager.shared.onTogglePlay = { [weak self] in self?.togglePlay() }
        NowPlayingManager.shared.onSkip = { [weak self] s in self?.skip(Int32(s)) }
        NowPlayingManager.shared.configure()
        updateNowPlaying()
    }

    /// If playback hasn't produced a single advancing frame within the grace
    /// window, the stream is effectively stuck buffering (dead/slow URL, provider
    /// throttling, weak network). Surface an error so PlayerView can fail over to
    /// the other engine or show a retryable message — instead of an endless
    /// "buffering" spinner (the reported bug).
    private func startStartWatchdog() {
        startWatchdog?.invalidate()
        // First attempt: a wide window so a legitimately slow (large-file / weak-
        // network) VOD isn't falsely declared failed. On a RETRY attempt we've
        // already waited the full window once AND rebuilt a fresh player, so a much
        // shorter window is used — a stream that STILL produces no frame is dead,
        // not slow. This keeps total start time bounded across retries.
        let grace: TimeInterval = retryCount > 0 ? (isLive ? 8 : 12) : (isLive ? 15 : 28)
        startWatchdog = Timer.scheduledTimer(withTimeInterval: grace, repeats: false) { [weak self] _ in
            guard let self else { return }
            // No progress PAST the attempt's start position within the window → a
            // (retryable) stuck start. Comparing to `retryAnchor` (0 for a first
            // play, the resume point for a stall-retry) makes the short retry window
            // effective on the mid-stream-stall path too, not just the cold start.
            if self.currentTime <= self.retryAnchor, self.errorMsg == nil {
                self.attemptRecoveryOrFail(L("player.err.start_failed"))
            }
        }
    }

    func updateNowPlaying() {
        let t = nowPlayingTitle
        NowPlayingManager.shared.update(title: t.0, subtitle: t.1, duration: duration,
                                        elapsed: currentTime, rate: isPlaying ? rate : 0, isLive: isLive)
    }

    private var streamURL: URL? {
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

    // MARK: - Controls
    override func togglePlay() {
        if player.isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
        updateNowPlaying()
    }
    override func play()  { player.play();  isPlaying = true;  updateNowPlaying() }
    override func pause() { player.pause(); isPlaying = false; updateNowPlaying() }

    override func skip(_ seconds: Int32) {
        didResume = true   // manual navigation cancels the one-shot auto-resume
        if seconds >= 0 { player.jumpForward(seconds) } else { player.jumpBackward(-seconds) }
    }
    override func seek(to progress: Double) {
        guard duration > 0 else { return }
        player.position = Float(min(1, max(0, progress)))
    }
    // Two-phase scrub. VLC keeps rendering the seeked frame, so setting position
    // while dragging gives a live preview; on release we land on an absolute time.
    override func beginScrub() { didResume = true }             // user navigating → cancel auto-resume
    override func scrub(to progress: Double) {
        player.position = Float(min(1, max(0, progress)))       // live preview
    }
    override func endScrub(to progress: Double) {
        player.position = Float(min(1, max(0, progress)))
    }
    override func toggleMute() {
        isMuted.toggle()
        let m = isMuted
        // Use libVLC's dedicated mute flag. Muting by setting volume to 0 does NOT
        // reliably restart iOS's audio unit on unmute — the sound stays silent
        // (the reported bug). Hop off the main thread: toggling mute on a running
        // stream from the main thread can deadlock it (VLCKit issue #111).
        // Capture the player reference HERE on the main thread — it can be reassigned
        // by a retry rebuild, and reading a `var` from the background queue would race.
        let p = player
        DispatchQueue.global(qos: .userInitiated).async {
            p.audio?.isMuted = m
        }
    }
    /// Set volume from a 0…1 gesture value (mapped to VLC's 0…150 range).
    override func setVolume(_ v: Double) {
        let vol = Int32(max(0, min(1, v)) * 150)
        player.audio?.volume = vol
        isMuted = vol == 0
        lastVolume = vol
    }
    override var currentVolume: Double { Double(player.audio?.volume ?? 100) / 150.0 }

    // MARK: - Aspect ratio / screen size
    override var aspectLabel: String { aspectModes[aspectIndex].label }

    override func cycleAspect() {
        aspectIndex = (aspectIndex + 1) % aspectModes.count
        applyAspect()
    }
    private func applyAspect() {
        let mode = aspectModes[aspectIndex]
        setVLCString(mode.ratio) { player.videoAspectRatio = $0 }
        let crop = (mode.crop == "screen") ? screenCropGeometry() : mode.crop
        setVLCString(crop) { player.videoCropGeometry = $0 }
    }
    /// Aspect-ratio crop ("W:H", same form VLC used for "16:9") matching the current
    /// render surface, so "ملء" (fill) truly reaches every edge on any device —
    /// 19.5:9 iPhone, 4:3 iPad, in either orientation — no black bars, no distortion.
    /// GCD-reduced to keep the ratio small. Falls back to 16:9.
    private func screenCropGeometry() -> String {
        let size = surfaceView?.bounds.size ?? UIScreen.main.bounds.size
        var w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 1, h > 1 else { return "16:9" }
        // Only fill edge-to-edge in LANDSCAPE. In portrait, cropping ~16:9 content
        // to the tall screen aspect would zoom it enormously — fall back to fit (no
        // crop). Recomputed on rotation, so flipping upright returns to normal size.
        guard w > h else { return "" }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = gcd(w, h)
        if g > 1 { w /= g; h /= g }
        return "\(w):\(h)"
    }
    /// VLC's aspect/crop properties take a C string pointer (or NULL to reset).
    private func setVLCString(_ value: String, _ assign: (UnsafeMutablePointer<CChar>?) -> Void) {
        if value.isEmpty { assign(nil) }
        else { value.withCString { assign(UnsafeMutablePointer(mutating: $0)) } }
    }

    // MARK: - Subtitles
    override func loadSubtitles() {
        let ids   = (player.videoSubTitlesIndexes as? [NSNumber]) ?? []
        let names = (player.videoSubTitlesNames as? [String]) ?? []
        var tracks: [(Int32, String)] = []
        for (i, id) in ids.enumerated() {
            let name = i < names.count ? names[i] : "ترجمة \(i)"
            tracks.append((id.int32Value, name))
        }
        subtitleTracks = tracks.map { (id: $0.0, name: $0.1) }
        currentSubtitle = player.currentVideoSubTitleIndex
        // Apply remembered subtitle language by name
        if let want = Store.shared.lastSubtitleName,
           let match = subtitleTracks.first(where: { $0.name == want }), match.id != currentSubtitle {
            selectSubtitle(match.id)
        }
        // Re-apply a custom subtitle size to the newly-loaded track (skip when auto,
        // so default users see no change and no track re-select).
        if subtitleFontSize > 0 { applySubtitleFontSize() }
    }
    override func selectSubtitle(_ id: Int32) {
        player.currentVideoSubTitleIndex = id
        currentSubtitle = id
        // Remember the chosen subtitle language by name (#remember last subtitle)
        if let name = subtitleTracks.first(where: { $0.id == id })?.name, id >= 0 {
            Store.shared.lastSubtitleName = name
        } else if id < 0 { Store.shared.lastSubtitleName = nil }
        if subtitleFontSize > 0 { applySubtitleFontSize() }   // keep a CUSTOM size on the new track
    }

    /// Apply the chosen subtitle font size to the running VLC renderer. The API
    /// (setTextRendererFontSize:) is implemented in MobileVLCKit but NOT declared in
    /// its public header, so we call it through the ObjC runtime GUARDED by
    /// responds(to:) — if a future pod drops it, this silently no-ops (never crashes,
    /// never breaks the build). Re-selecting the current track makes it take effect now.
    override func applySubtitleFontSize() {
        guard subtitleFontSize > 0 else { return }   // 0 = default; never send it (renderer divisor)
        let sel = NSSelectorFromString("setTextRendererFontSize:")
        if player.responds(to: sel) {
            _ = player.perform(sel, with: NSNumber(value: subtitleFontSize))
            let cur = player.currentVideoSubTitleIndex
            if cur >= 0 { player.currentVideoSubTitleIndex = cur }   // rebuild renderer with new size
        }
    }

    // MARK: - Audio tracks
    override func loadAudioTracks() {
        let ids   = (player.audioTrackIndexes as? [NSNumber]) ?? []
        let names = (player.audioTrackNames as? [String]) ?? []
        var tracks: [(Int32, String)] = []
        for (i, id) in ids.enumerated() {
            let name = i < names.count ? names[i] : "Audio \(i)"
            tracks.append((id.int32Value, name))
        }
        audioTracks = tracks.map { (id: $0.0, name: $0.1) }
        currentAudio = player.currentAudioTrackIndex
        // Apply remembered audio language by name (#remember last audio)
        if let want = Store.shared.lastAudioName,
           let match = audioTracks.first(where: { $0.name == want }), match.id != currentAudio {
            selectAudio(match.id)
        }
    }
    override func selectAudio(_ id: Int32) {
        player.currentAudioTrackIndex = id
        currentAudio = id
        if let name = audioTracks.first(where: { $0.id == id })?.name { Store.shared.lastAudioName = name }
    }

    // MARK: - Playback speed
    override func setRate(_ r: Float) {
        guard !isLive else { return }
        player.rate = r; rate = r
        updateNowPlaying()
    }
    /// Hold-to-boost (YouTube style): 2x while held, restore on release.
    override func boostSpeed(_ on: Bool) {
        guard !isLive else { return }
        player.rate = on ? 2.0 : rate
    }

    // MARK: - Cleanup
    // progress / fmt / currentFmt / durationFmt / saveProgress now live in
    // BasePlayerVM (shared by both engines).
    override func cleanup() {
        startWatchdog?.invalidate(); startWatchdog = nil
        retryTimer?.invalidate(); retryTimer = nil
        reconnecting = false
        stopStallMonitor()
        saveProgress()
        player.stop()
        player.delegate = nil
        NowPlayingManager.shared.clear()
        KeepAwake.relinquish(self)   // allow normal auto-lock once this engine stops
    }

    // Safety net: if the VM is ever released without cleanup() (a SwiftUI
    // StateObject edge case), make sure VLC's background decode thread is torn
    // down rather than left running.
    deinit {
        startWatchdog?.invalidate()
        retryTimer?.invalidate()
        stopStallMonitor()
        player.stop()
        player.delegate = nil
        KeepAwake.relinquish(self)
    }

    // MARK: - VLCMediaPlayerDelegate (called on main thread)
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch player.state {
        case .buffering:
            buffering = true
        case .playing:
            startWatchdog?.invalidate(); startWatchdog = nil
            reconnecting = false   // recovered (retry budget refreshes after 5s, in the time handler)
            isLoading = false; buffering = false; isPlaying = true
            if duration == 0, let len = player.media?.length.intValue, len > 0 {
                duration = Double(len) / 1000
            }
            resumeIfNeeded()
            if aspectIndex != 0 { applyAspect() }   // keep the chosen fill/aspect across zap
            if subtitleTracks.isEmpty { loadSubtitles() }
            if audioTracks.isEmpty { loadAudioTracks() }
            updateNowPlaying()
        case .paused:
            isPlaying = false
            updateNowPlaying()
        case .error:
            attemptRecoveryOrFail(L("player.err.failed"))   // retry (bounded) → then terminal
        case .ended:
            isPlaying = false
        case .stopped:
            isPlaying = false
        default:
            break
        }
    }

    private var lastTickTime: Double = -1
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let t = Double(player.time.intValue) / 1000
        let advanced = t > lastTickTime
        lastTickTime = t
        if currentTime != t { currentTime = t }
        // Clear loading/buffering ONLY when time actually ADVANCES — during a stall
        // (time frozen) keep the buffering UI instead of falsely hiding it. Guarding
        // the assignments also stops re-publishing unchanged @Published state every
        // tick (which re-rendered the whole controls tree — visible jank).
        if advanced {
            if isLoading { isLoading = false }
            if buffering { buffering = false }
            if reconnecting { reconnecting = false }
            // 5s of playback PAST the retry anchor = the stream is healthy again →
            // refresh the retry budget so a LATER independent hiccup gets its own
            // retries. Measuring past the anchor (not absolute currentTime) is what
            // keeps it bounded for VOD too: an error-loop that can't advance 5s can
            // never reset the budget (no unbounded retrying, fatal overlay still fires).
            if retryCount > 0, currentTime - retryAnchor > 5 { retryCount = 0 }
        }
        let playing = player.isPlaying
        if isPlaying != playing { isPlaying = playing }
        if playing { KeepAwake.keep(self) }   // re-assert every tick while playing
        if duration == 0, let len = player.media?.length.intValue, len > 0 {
            duration = Double(len) / 1000
        }
        resumeIfNeeded()
        // Keep the lock-screen / Dynamic Island scrubber in sync (~1s throttle)
        if currentTime - lastNowPlaying >= 1 { lastNowPlaying = currentTime; updateNowPlaying() }
    }
    private var lastNowPlaying: Double = -10
}

// MARK: - VLC video surface
struct VLCVideoView: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - UIKit Share Sheet
struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Now Playing (lock screen / Control Center / Dynamic Island)
/// Bridges VLC playback to MPNowPlayingInfoCenter + MPRemoteCommandCenter so the
/// lock screen, Control Center and Dynamic Island show the title, scrubber and
/// play/pause/skip controls. The active player VM wires its callbacks in setup().
final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private init() {}

    var onTogglePlay: (() -> Void)?
    var onSkip: ((Int) -> Void)?          // seconds, signed
    private var configured = false
    private var artwork: MPMediaItemArtwork?

    /// Register remote commands + activate the audio session (call once per playback).
    func configure() {
        // Background audio + remote control require an active playback session.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

        guard !configured else { return }
        configured = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.onTogglePlay?(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.onTogglePlay?(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.onTogglePlay?(); return .success }
        c.skipForwardCommand.preferredIntervals = [10]
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.addTarget { [weak self] e in
            let s = (e as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self?.onSkip?(Int(s)); return .success
        }
        c.skipBackwardCommand.addTarget { [weak self] e in
            let s = (e as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self?.onSkip?(-Int(s)); return .success
        }
    }

    func update(title: String, subtitle: String?, duration: Double,
                elapsed: Double, rate: Float, isLive: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyIsLiveStream: isLive
        ]
        if let subtitle { info[MPMediaItemPropertyArtist] = subtitle }
        if !isLive, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        let c = MPRemoteCommandCenter.shared()
        c.skipForwardCommand.isEnabled = !isLive
        c.skipBackwardCommand.isEnabled = !isLive
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        artwork = nil
        // Intentionally do NOT deactivate the audio session here: on an engine
        // failover the old engine's cleanup runs around the new engine's setup,
        // and a late setActive(false) would mute the freshly-started fallback.
        // iOS deactivates the session automatically when the app is suspended.
    }
}

// MARK: - AirPlay route picker
/// Native AirPlay button (shows the device chooser, highlights when casting).
struct AirPlayButton: UIViewRepresentable {
    var tint: UIColor = .white
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = tint
        v.activeTintColor = UIColor(Color.s8kGoldHigh)
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
