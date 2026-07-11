// ============================================================
// BLANK TV — PlayerView.swift
// Full-screen VLC player — cinematic, gestures, landscape, subtitles, sleep
// ============================================================

import SwiftUI

// Public player entry. Picks the initial engine, and transparently retries with
// the OTHER engine if the first fails to play — so a stream AVPlayer rejects
// falls back to VLC (and vice-versa) with no error shown. Call sites are
// unchanged: PlayerView(item:) / PlayerView(item:queue:).
struct PlayerView: View {
    let item: ContentItem
    var queue: [Episode] = []
    /// Channels in the current browsing context (for live next/prev zapping).
    /// Empty for movies/episodes.
    var channels: [Channel] = []
    @State private var engine: PlayerEngineKind
    /// The item currently being played — tracks episode advances so a failover
    /// restarts the RIGHT episode (not the original one) on the other engine.
    @State private var playItem: ContentItem
    /// Engines already tried (and failed) for the CURRENT item. Reset whenever
    /// the item changes, so every episode/movie gets its own fresh failover.
    @State private var failedEngines: Set<PlayerEngineKind> = []
    /// Bumped by Retry to force a fresh engine attempt even when the engine kind
    /// is unchanged (a VOD that stays on VLC needs the view rebuilt to re-play).
    @State private var retryNonce = 0

    init(item: ContentItem, queue: [Episode] = [], channels: [Channel] = []) {
        self.item = item
        self.queue = queue
        self.channels = channels
        _engine = State(initialValue: PlayerEngineSelector.initialKind(for: item))
        _playItem = State(initialValue: item)
    }

    private var isLiveItem: Bool { if case .live = playItem { return true }; return false }

    var body: some View {
        // Failover is only offered when the OTHER engine has a REAL chance to play:
        //  • AVPlayer → VLC: always sensible (VLC plays what AVPlayer can't).
        //  • VLC → AVPlayer: only when AVPlayer can actually decode the URL, i.e. an
        //    HLS (.m3u8) LIVE stream. Failing a VOD (mkv/avi) OR a raw-TS live channel
        //    over to AVPlayer is guaranteed to fail (AVPlayer can't decode those),
        //    which produced a fatal "playback failed" overlay on any hiccup. In those
        //    cases we show a retryable error directly instead of a pointless swap.
        let urlIsHLS = (BasePlayerVM.resolvedURL(for: playItem)?.absoluteString.lowercased().contains(".m3u8")) ?? false
        let sensibleFallback = (engine == .av) || (isLiveItem && urlIsHLS)
        PlayerEngineView(item: playItem, queue: queue, channels: channels, engine: engine,
                         canFallback: sensibleFallback && !failedEngines.contains(engine.other),
                         onEngineFailed: { failedItem in
                             playItem = failedItem            // keep the current episode
                             failedEngines.insert(engine)
                             engine = engine.other            // swap → .id triggers a fresh attempt
                         },
                         onRetry: {
                             // Reset the whole failover chain and restart from the
                             // PREFERRED engine (VLC for movies) — a fresh full attempt,
                             // not a re-run of the engine that just failed.
                             failedEngines.removeAll()
                             engine = PlayerEngineSelector.initialKind(for: playItem)
                             retryNonce += 1
                         },
                         onItemChanged: { newItem in
                             playItem = newItem               // episode advanced
                             failedEngines.removeAll()        // both engines fresh for new content
                         })
            .id("\(engine.rawValue)-\(retryNonce)")
            // Orientation + idle timer live on the wrapper (it persists across an
            // engine swap), so auto-failover never snaps orientation nor flickers
            // the idle timer mid-stream. Set once on open, restore on true close.
            .onAppear {
                AppDelegate.orientationLock = .allButUpsideDown
                // Keep-awake is handled by the player engine itself (see KeepAwake),
                // not here — SwiftUI lifecycle proved unreliable for it on iPad.
            }
            .onDisappear {
                // iPad rotates freely everywhere — never force it back to portrait
                // (that would yank a landscape iPad UI to portrait and lock it).
                // Only iPhone returns to the portrait-locked browsing chrome.
                if UIDevice.current.userInterfaceIdiom == .pad {
                    AppDelegate.orientationLock = .all
                } else {
                    AppDelegate.orientationLock = .portrait
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                    }
                }
            }
    }
}

// The actual player UI, bound to ONE concrete engine. The PlayerView wrapper
// (above) recreates this view with the other engine if this one fails, so the
// failover is a clean fresh @StateObject rather than a runtime backend swap.
struct PlayerEngineView: View {
    let item: ContentItem
    /// Season episodes (for auto-next). Empty for live/movies.
    var queue: [Episode] = []
    /// Channels for live next/prev zapping. Empty for movies/episodes.
    var channels: [Channel] = []
    /// The engine backing this instance (av / vlc).
    let engine: PlayerEngineKind
    /// True while the OTHER engine hasn't been tried yet — when so, a failure
    /// silently triggers failover instead of showing the error overlay.
    let canFallback: Bool
    /// Called when this engine fails and a fallback is still available; passes
    /// the item that was playing so the wrapper can retry it on the other engine.
    var onEngineFailed: (ContentItem) -> Void = { _ in }
    /// Called when the user taps Retry on the fatal-error overlay — the wrapper
    /// resets the failover chain and restarts from the preferred engine.
    var onRetry: () -> Void = {}
    /// Called when playback advances to a different item (next/prev episode), so
    /// the wrapper can reset per-item failover state.
    var onItemChanged: (ContentItem) -> Void = { _ in }

    @StateObject private var vm: BasePlayerVM
    @State private var didReportFailure = false
    @Environment(\.dismiss) var dismiss

    /// The item currently playing — changes when auto-advancing to next episode.
    @State private var currentItem: ContentItem

    // Auto-next-episode prompt
    @State private var showNextPrompt = false
    @State private var nextCancelled  = false
    @State private var nextCountdown  = 10

    @State private var showControls   = true
    @State private var controlsTimer: Timer?
    @State private var scrubbing  = false
    @State private var scrubValue = 0.0
    @State private var scrubStartTime = 0.0   // playback position when the drag began (for the delta chip)

    // Brightness / volume gestures
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var volume     = 1.0
    // Per-side gesture state, keyed by isVolume, so LEFT (volume) and RIGHT
    // (brightness) can be adjusted at the SAME time with two fingers — they used
    // to share one start/axis/HUD and fight each other.
    @State private var sideStart: [Bool: Double] = [:]
    // Independent HUDs — volume (left) and brightness (right) can show together.
    @State private var volumeHUD: (icon: String, value: Double)? = nil
    @State private var brightHUD: (icon: String, value: Double)? = nil
    @State private var volHudTimer: Timer?
    @State private var briHudTimer: Timer?
    @State private var hudTimer: Timer?   // seek badge / holdSeek only

    // Double-tap seek accumulator badge (right = forward, left = backward)
    @State private var holdSeek: (forward: Bool, secs: Int)? = nil

    // Manual double-tap detection so single-tap stays instant (no count:2 delay)
    @State private var lastTapTime: Date? = nil
    @State private var lastTapSide: Bool = false

    // True when the player is wider than it is tall. Derived from the ACTUAL laid-out
    // size (updated by orientationReader), not the vertical size class — because iPad
    // reports `.regular` height in BOTH orientations, so `vSize == .compact` was always
    // false on iPad (the rotate button + landscape insets never engaged). Geometry is
    // device-independent (iPhone, iPad, Mac resizable window) and reactive on rotation.
    @State private var isLandscape = false

    // Sleep timer
    @State private var sleepActive    = false
    @State private var sleepRemaining = 0
    @State private var sleepTimer: Timer?
    @State private var showSleepSheet    = false
    @State private var showSubtitleSheet = false
    @State private var showSpeedSheet    = false
    @State private var showAudioSheet    = false

    // Screen-lock mode (#package: gesture lock). When on, all controls/gestures
    // are disabled except the unlock button — prevents accidental touches.
    @State private var gestureLocked = false

    // Hold-to-2x speed boost (YouTube style) — replaces hold-to-seek.
    @State private var boosting = false

    // Netflix-style double-tap ripple (visual feedback on the tapped side).
    @State private var ripple: (forward: Bool, id: Int)? = nil
    @State private var rippleSeq = 0

    // Channel-zap name badge (live): shows the channel name briefly on switch.
    @State private var channelBadge: String? = nil
    @State private var channelBadgeSeq = 0
    // Axis lock for a drag: once it starts moving we commit to vertical
    // (volume/brightness) OR horizontal (channel zap) so they never fight.
    private enum DragAxis { case none, vertical, horizontal }
    @State private var sideAxis: [Bool: DragAxis] = [:]   // per-side axis lock (keyed by isVolume)

    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    // A discrete "tick" for scrubbing — selection haptics read as a light,
    // premium click per step (vs. the heavier impact used for actions).
    private let scrubHaptic = UISelectionFeedbackGenerator()
    @State private var lastScrubStep = -1

    // Buffering-UI debounce: only show the spinner if the stall lasts past a
    // short delay, and once shown keep it up a minimum time — kills the flicker
    // on quick re-buffers that plagues IPTV streams.
    @State private var showBufferingUI = false
    @State private var bufferShownAt: Date? = nil
    @State private var bufferShowWork: DispatchWorkItem? = nil

    init(item: ContentItem, queue: [Episode] = [], channels: [Channel] = [], engine: PlayerEngineKind,
         canFallback: Bool, onEngineFailed: @escaping (ContentItem) -> Void = { _ in },
         onRetry: @escaping () -> Void = {},
         onItemChanged: @escaping (ContentItem) -> Void = { _ in }) {
        self.item = item
        self.queue = queue
        self.channels = channels
        self.engine = engine
        self.canFallback = canFallback
        self.onEngineFailed = onEngineFailed
        self.onRetry = onRetry
        self.onItemChanged = onItemChanged
        _currentItem = State(initialValue: item)
        _vm = StateObject(wrappedValue: PlayerEngineSelector.make(item: item, kind: engine))
    }

    private var title: String {
        switch currentItem {
        case .live(let ch):           return ch.name
        case .movie(let m):           return m.name
        case .episode(let ep, let s): return "\(s.name) · \(L("episode.number")) \(ep.episodeNumber)"
        }
    }

    // MARK: - Episode context (auto-next + skip-intro)
    private var episodeContext: (ep: Episode, series: Series)? {
        if case .episode(let ep, let s) = currentItem { return (ep, s) }
        return nil
    }
    private var nextEpisode: Episode? {
        guard let ctx = episodeContext,
              let i = queue.firstIndex(where: { $0.id == ctx.ep.id }),
              i + 1 < queue.count else { return nil }
        return queue[i + 1]
    }
    private var prevEpisode: Episode? {
        guard let ctx = episodeContext,
              let i = queue.firstIndex(where: { $0.id == ctx.ep.id }),
              i - 1 >= 0 else { return nil }
        return queue[i - 1]
    }
    private func goPrev() {
        guard let prv = prevEpisode, let s = episodeContext?.series else { return }
        let prev = ContentItem.episode(prv, s)
        currentItem = prev; vm.load(prev)
        showNextPrompt = false; nextCancelled = false
        resetControlsTimer()
    }
    private var canSkipIntro: Bool {
        Store.shared.skipIntroEnabled && episodeContext != nil
            && vm.currentTime > 1
            && vm.currentTime < Double(Store.shared.skipIntroSeconds)
            && vm.duration > Double(Store.shared.skipIntroSeconds)
    }

    private func playbackTick(_ t: Double) {
        guard Store.shared.autoPlayNext, !nextCancelled,
              nextEpisode != nil, vm.duration > 30 else { return }
        let window = Double(Store.shared.autoNextSeconds)   // user-set countdown
        let remaining = vm.duration - t
        if remaining <= window, remaining > 0 {
            showNextPrompt = true
            nextCountdown = max(1, Int(ceil(remaining)))
        }
        if remaining <= 0.8, showNextPrompt { goNext() }
    }
    private func goNext() {
        guard let nxt = nextEpisode, let s = episodeContext?.series else { return }
        let next = ContentItem.episode(nxt, s)
        currentItem = next
        vm.load(next)
        showNextPrompt = false
        nextCancelled = false
        resetControlsTimer()
    }

    // MARK: - Live channel zapping (next / previous)
    private var currentChannel: Channel? {
        if case .live(let ch) = currentItem { return ch }
        return nil
    }
    /// True when zapping is available (live + a non-trivial channel list).
    private var canZap: Bool { currentChannel != nil && channels.count > 1 }
    private func channelOffset(_ delta: Int) -> Channel? {
        guard let cur = currentChannel,
              let i = channels.firstIndex(where: { $0.id == cur.id }) else { return nil }
        let n = channels.count
        let j = ((i + delta) % n + n) % n     // wrap-around both directions
        return channels[j]
    }
    private func zap(_ delta: Int) {
        guard let ch = channelOffset(delta) else { return }
        currentItem = .live(ch)
        vm.load(.live(ch))
        showChannelBadge(ch.name)
        haptic.impactOccurred()
        resetControlsTimer()
    }
    private func showChannelBadge(_ name: String) {
        channelBadge = name
        channelBadgeSeq += 1
        let seq = channelBadgeSeq
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if channelBadgeSeq == seq { withAnimation { channelBadge = nil } }
        }
    }

    var body: some View {
        ZStack {
            // Video fills the entire screen (cinematic)
            Color.black.ignoresSafeArea()
            PlayerSurfaceView(vm: vm).ignoresSafeArea()

            // Loading / buffering — debounced (see updateBufferingUI) so a quick
            // re-buffer doesn't flash the spinner on and off.
            if showBufferingUI {
                VStack(spacing: 12) {
                    ProgressView().progressViewStyle(.circular).tint(.s8kGoldHigh).scaleEffect(1.3)
                    Text(vm.reconnecting ? L("play.reconnecting")
                         : vm.buffering ? L("play.buffering") : L("play.starting"))
                        .font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                }
                .transition(.opacity)
            }

            // (Scrub time bubble now lives ABOVE the seek bar, following the thumb —
            //  see the Slider overlay below — so it never sits under the play button.)

            // (The fatal-error overlay is rendered LAST in this ZStack — see the end
            //  of the stack — so it sits ABOVE the gesture + controls layers and its
            //  Retry button actually receives taps. It used to live here, below the
            //  full-screen gesture zone, which swallowed every tap on the button.)

            // Invisible system-volume bridge (keeps the gesture tied to the
            // real device volume, #6). Zero-size, never interactive.
            SystemVolumeHost().frame(width: 0, height: 0)

            // Gesture layer: LEFT half = volume, RIGHT half = brightness
            // (vertical drag). Tap toggles controls; long-press = 2x boost.
            // Disabled while the screen is locked (#package: gesture lock).
            if !gestureLocked {
                HStack(spacing: 0) {
                    gestureZone(isVolume: true)
                    gestureZone(isVolume: false)
                }
            }

            // Volume HUD (left) and brightness HUD (right) — independent, so both
            // can appear at once when two fingers adjust each side simultaneously.
            if let v = volumeHUD {
                HStack { levelHUDView(icon: v.icon, value: v.value); Spacer() }
                    .padding(.horizontal, 30).transition(.opacity)
            }
            if let b = brightHUD {
                HStack { Spacer(); levelHUDView(icon: b.icon, value: b.value) }
                    .padding(.horizontal, 30).transition(.opacity)
            }

            // Hold-to-seek visual feedback (#7)
            if let hs = holdSeek {
                HStack {
                    if !hs.forward { Spacer() }
                    seekHoldBadge(hs)
                    if hs.forward { Spacer() }
                }
                .padding(.horizontal, 24)
                .transition(.opacity)
            }

            // Netflix-style double-tap ripple
            if let r = ripple {
                HStack {
                    if !r.forward { Spacer() }
                    rippleBadge(r.forward)
                    if r.forward { Spacer() }
                }
                .id(r.id)
                .allowsHitTesting(false)
            }

            // 2x speed-boost badge (while long-pressing)
            if boosting {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("2x").font(.system(size: 15, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(S8KGradient.goldFlat).clipShape(Capsule())
                    .padding(.top, isLandscape ? 24 : 70)
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // Channel-zap name badge (brief, after a swipe/next/prev)
            if let name = channelBadge {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "tv.fill").font(.system(size: 13))
                        Text(name).font(S8KFont.subhead.weight(.bold)).lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.ultraThinMaterial).background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.s8kBorderGold, lineWidth: 1))
                    .padding(.top, isLandscape ? 24 : 70)
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // Always-mounted + opacity (not an if-insert): SwiftUI just
            // interpolates opacity instead of building/tearing down the whole
            // control tree each toggle — smooth fade, no lag/flicker. Hidden =
            // no hit-testing so taps fall through to the gesture zones (show).
            // NOTE: no .ignoresSafeArea() here — the dimming gradient bleeds full
            // screen on its own (below), but the CONTROLS must inset from the safe
            // area so buttons/seek-bar clear the notch / Dynamic Island / home
            // indicator in landscape (the primary player orientation).
            controlsOverlay
                .opacity(showControls && !gestureLocked ? 1 : 0)
                .allowsHitTesting(showControls && !gestureLocked)

            // Screen-lock mode: tap anywhere reveals a single unlock button.
            if gestureLocked { lockOverlay }

            // Skip-intro (episodes, first ~85s) + auto-next prompt (last 10s)
            if canSkipIntro && !gestureLocked {
                VStack { Spacer(); HStack { Spacer(); skipIntroButton } }
                    .padding(.horizontal, 24)
                    .padding(.bottom, isLandscape ? 28 : 104)
            }
            if showNextPrompt, let nxt = nextEpisode, !gestureLocked {
                VStack { Spacer(); HStack { Spacer(); nextPromptCard(nxt) } }
                    .padding(.horizontal, 24)
                    .padding(.bottom, isLandscape ? 28 : 104)
                    .transition(.opacity)
            }

            // Brand watermark — always visible (owner-controlled, not the customer)
            S8KWatermark(opacity: 0.16, alignment: .bottomLeading)

            // Fatal error (both engines tried & failed): a MODAL overlay rendered
            // LAST, so it sits above the gesture + controls + watermark layers and
            // its Retry button actually receives taps. (It previously lived below the
            // full-screen gesture zone, which swallowed every tap → "button dead".)
            if let err = vm.errorMsg, !canFallback {
                Color.black.opacity(0.9).ignoresSafeArea()
                    .contentShape(Rectangle())           // absorb taps; nothing leaks below
                // Back button — the user must ALWAYS be able to leave (never trapped).
                VStack {
                    HStack {
                        iconCircle("chevron.down") { dismiss() }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, S8KSpace.lg).padding(.top, isLandscape ? S8KSpace.md : 50)
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34)).foregroundColor(.s8kTextDisabled)
                    Text(err).font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                    GoldButton(title: L("common.retry"), icon: "arrow.clockwise") {
                        // Full fresh attempt from the preferred engine (resets the
                        // failover chain in the wrapper) — not a re-run of the engine
                        // that just failed. Recovers transient drops AND wrong-engine
                        // dead-ends.
                        didReportFailure = false
                        vm.errorMsg = nil
                        onRetry()
                    }
                    .frame(width: 200)
                }
            }
        }
        .background(orientationReader)   // keep isLandscape in sync with the real size
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        // Hide the system Home Indicator (the bottom bar) during fullscreen playback.
        // SwiftUI equivalent of a UIViewController's prefersHomeIndicatorAutoHidden:
        // the system still flashes it briefly on touch, then auto-hides (Netflix/
        // YouTube behavior). iOS 16+; app targets iOS 17+.
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.18), value: showControls)
        .animation(.easeInOut(duration: 0.15), value: volumeHUD?.value)
        .animation(.easeInOut(duration: 0.15), value: brightHUD?.value)
        .animation(.easeInOut(duration: 0.15), value: holdSeek?.secs)
        .animation(.easeInOut(duration: 0.2), value: showNextPrompt)
        .animation(.easeInOut(duration: 0.15), value: boosting)
        .animation(.easeInOut(duration: 0.2), value: gestureLocked)
        .animation(.easeOut(duration: 0.35), value: rippleSeq)
        .animation(.easeInOut(duration: 0.2), value: channelBadge)
        .onChange(of: vm.currentTime) { _, t in playbackTick(t) }
        // Auto-failover: if this engine fails and the other hasn't been tried,
        // tell the wrapper to swap engines (no error shown to the user).
        .onChange(of: vm.errorMsg) { _, msg in
            if msg != nil, canFallback, !didReportFailure {
                didReportFailure = true
                onEngineFailed(currentItem)
            }
        }
        // Episode advanced (next/prev/auto-next) → let the wrapper reset per-item
        // failover state and re-arm failure reporting for the new item.
        .onChange(of: currentItem.id) { _, _ in
            didReportFailure = false
            onItemChanged(currentItem)
        }
        .onAppear { vm.setup(); resetControlsTimer(); haptic.prepare(); scrubHaptic.prepare() }
        .onChange(of: vm.isLoading) { _, _ in updateBufferingUI() }
        .onChange(of: vm.buffering) { _, _ in updateBufferingUI() }
        .onChange(of: vm.isPlaying) { _, _ in
            // resetControlsTimer re-arms auto-hide when playing and cancels it when
            // paused — so controls stay up while paused without popping up on stalls.
            resetControlsTimer()
        }
        .onDisappear {
            // Engine teardown only. Orientation is owned by the PlayerView wrapper
            // (it persists across an engine swap), so a failover doesn't snap the
            // device to portrait mid-stream.
            vm.cleanup(); controlsTimer?.invalidate(); sleepTimer?.invalidate()
            hudTimer?.invalidate(); volHudTimer?.invalidate(); briHudTimer?.invalidate()
            bufferShowWork?.cancel()   // don't flip buffering UI on a dismissed view
        }
        .sheet(isPresented: $showSleepSheet)    { sleepSheet }
        .sheet(isPresented: $showSubtitleSheet) { subtitleSheet }
        .sheet(isPresented: $showSpeedSheet)    { speedSheet }
        .sheet(isPresented: $showAudioSheet)    { audioSheet }
    }

    // MARK: - Gesture zones (volume / brightness / seek) + tap-to-toggle
    private func gestureZone(isVolume: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            // Single tap toggles controls INSTANTLY; a quick second tap on the
            // same side is detected manually as a ±10s seek (no count:2 delay).
            .onTapGesture { handleTap(isVolume: isVolume) }
            // Vertical drag = volume (left) / brightness (right).
            // Horizontal drag (live only) = next/previous channel.
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { v in handleDrag(isVolume: isVolume, translation: v.translation) }
                    .onEnded { v in endDrag(isVolume: isVolume, translation: v.translation) }
            )
            // Long press (stationary hold) = 2x playback speed boost (YouTube)
            .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 14,
                pressing: { pressing in if !pressing { stopBoost() } },
                perform: { startBoost() })
    }

    // MARK: - Hold-to-2x speed boost (#package)
    private func startBoost() {
        guard !vm.isLive else { return }
        boosting = true
        vm.boostSpeed(true)
        haptic.impactOccurred()
        resetControlsTimer()
    }
    private func stopBoost() {
        guard boosting else { return }
        boosting = false
        vm.boostSpeed(false)
    }

    private func handleDrag(isVolume: Bool, translation: CGSize) {
        // Commit THIS side to an axis on its first significant movement so a
        // horizontal channel-swipe never nudges volume/brightness and vice-versa.
        // State is per-side (keyed by isVolume) so the two sides never interfere.
        if (sideAxis[isVolume] ?? .none) == .none {
            sideAxis[isVolume] = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
            haptic.prepare()   // warm the Taptic engine so the zap/boundary tap has no latency
        }
        guard sideAxis[isVolume] == .vertical else { return }   // horizontal handled on .onEnded (zap)
        let dy = translation.height
        let start = sideStart[isVolume] ?? (isVolume ? Double(SystemVolume.shared.current)
                                                     : Double(UIScreen.main.brightness))
        if sideStart[isVolume] == nil { sideStart[isVolume] = start }
        let newVal = min(1, max(0, start - Double(dy) / 260.0))   // up = increase
        if isVolume {
            volume = newVal
            SystemVolume.shared.set(Float(newVal))   // moves the real device volume (#6)
            volumeHUD = (newVal <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill", newVal)
        } else {
            brightness = newVal; UIScreen.main.brightness = CGFloat(newVal)
            brightHUD = ("sun.max.fill", newVal)
        }
    }

    private func endDrag(isVolume: Bool, translation: CGSize) {
        // A committed horizontal swipe (live + ≥70pt) zaps channels:
        // swipe left → next, swipe right → previous.
        if sideAxis[isVolume] == .horizontal, canZap, abs(translation.width) > 70 {
            zap(translation.width < 0 ? 1 : -1)
        }
        sideAxis[isVolume] = nil
        sideStart[isVolume] = nil
        scheduleHideHUD(isVolume: isVolume)
    }

    private func scheduleHideHUD(isVolume: Bool) {
        if isVolume {
            volHudTimer?.invalidate()
            volHudTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { _ in
                withAnimation { volumeHUD = nil }
            }
        } else {
            briHudTimer?.invalidate()
            briHudTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { _ in
                withAnimation { brightHUD = nil }
            }
        }
    }

    // Instant single tap toggles controls; a quick second tap on the same side
    // starts a YouTube-style ±10s seek, and EVERY further tap on that side while
    // the indicator is up keeps adding +10 (accumulating), with no toggle.
    private func handleTap(isVolume: Bool) {
        let forward = !isVolume   // right half (isVolume == false) = forward
        // Already seeking on this side → keep accumulating (+10 each), no toggle.
        if !vm.isLive, let hs = holdSeek, hs.forward == forward {
            doubleTapSeek(forward: forward)        // adds +10 and refreshes the timer
            return
        }
        let now = Date()
        if let last = lastTapTime, now.timeIntervalSince(last) < 0.32, lastTapSide == isVolume {
            lastTapTime = nil
            showControls.toggle()                  // revert the optimistic single-tap toggle
            doubleTapSeek(forward: forward)        // activate the seek (+10)
        } else {
            lastTapTime = now
            lastTapSide = isVolume
            toggleControls()                       // instant single-tap response
        }
    }

    // MARK: - Double-tap seek (±10s, accumulating) + Netflix ripple
    private func doubleTapSeek(forward: Bool) {
        guard !vm.isLive else { return }
        vm.skip(forward ? 10 : -10)
        haptic.impactOccurred()
        let base = (holdSeek?.forward == forward) ? (holdSeek?.secs ?? 0) : 0
        holdSeek = (forward, base + 10)
        rippleSeq += 1
        ripple = (forward, rippleSeq)
        hudTimer?.invalidate()
        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
            withAnimation { holdSeek = nil; ripple = nil }
        }
        resetControlsTimer()
    }

    // MARK: - Side HUD views
    private func levelHUDView(icon: String, value: Double) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 24)).foregroundColor(.white)
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.2)).frame(width: 5, height: 110)
                Capsule().fill(S8KGradient.goldFlat).frame(width: 5, height: 110 * value)
            }
        }
        .padding(16).background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg))
    }

    private func seekHoldBadge(_ hs: (forward: Bool, secs: Int)) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                Image(systemName: hs.forward ? "forward.fill" : "backward.fill")
                Image(systemName: hs.forward ? "forward.fill" : "backward.fill")
            }
            .font(.system(size: 22)).foregroundColor(.s8kGoldHigh)
            Text("\(hs.forward ? "+" : "-")\(hs.secs)s")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg))
    }

    // Netflix-style expanding ripple on the double-tapped side.
    private func rippleBadge(_ forward: Bool) -> some View {
        Image(systemName: forward ? "goforward.10" : "gobackward.10")
            .font(.system(size: 40, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 150, height: 150)
            .background(Color.white.opacity(0.10))
            .clipShape(Circle())
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: - Screen-lock overlay (#package: gesture lock)
    private var lockOverlay: some View {
        VStack {
            Spacer()
            Button(action: {
                gestureLocked = false; haptic.impactOccurred(); resetControlsTimer()
            }) {
                Label(L("play.unlock"), systemImage: "lock.open.fill")
                    .font(S8KFont.subhead).foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.s8kBorderGold, lineWidth: 1))
            }
            .buttonStyle(S8KButtonStyle())
            .padding(.bottom, isLandscape ? 30 : 60)
        }
    }

    // MARK: - Skip-intro + auto-next overlays
    private var skipIntroButton: some View {
        Button(action: {
            vm.seekToTime(Double(Store.shared.skipIntroSeconds))
            resetControlsTimer()
        }) {
            Label(L("play.skip_intro"), systemImage: "forward.end.fill")
                .font(S8KFont.subhead).foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func nextPromptCard(_ ep: Episode) -> some View {
        let art = ep.posterURL ?? episodeContext?.series.backdropURL ?? episodeContext?.series.coverURL
        return HStack(spacing: 12) {
            // Next-episode thumbnail with a circular countdown ring
            ZStack {
                S8KImage(url: art, placeholder: "play.tv.fill")
                    .frame(width: 96, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Color.black.opacity(0.35)
                    .frame(width: 96, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
                    Circle().trim(from: 0, to: CGFloat(nextCountdown) / CGFloat(max(1, Store.shared.autoNextSeconds)))
                        .stroke(S8KGradient.goldFlat, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(nextCountdown)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 34, height: 34)
                .animation(.linear(duration: 0.9), value: nextCountdown)
            }
            VStack(alignment: .trailing, spacing: 6) {
                Text(L("play.next_episode"))
                    .font(S8KFont.caption2.weight(.semibold)).foregroundColor(.s8kGoldMid)
                Text("\(L("episode.number")) \(ep.episodeNumber)")
                    .font(S8KFont.subhead).foregroundColor(.white).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                HStack(spacing: 8) {
                    Button(action: { nextCancelled = true; showNextPrompt = false }) {
                        Text(L("common.cancel")).font(S8KFont.caption2.weight(.semibold))
                            .foregroundColor(.s8kTextSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(S8KButtonStyle())
                    Button(action: { goNext() }) {
                        Label(L("common.play"), systemImage: "play.fill")
                            .font(S8KFont.caption2.weight(.bold)).foregroundColor(.black)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(S8KGradient.goldFlat).clipShape(Capsule())
                    }
                    .buttonStyle(S8KButtonStyle())
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
            .strokeBorder(Color.s8kBorderGold, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .frame(maxWidth: 340)
    }

    // MARK: - Controls overlay (cinematic, over the video)
    private var controlsOverlay: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.7), .clear, .clear, Color.black.opacity(0.78)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()   // dimming bleeds edge-to-edge; controls below stay inset
                // Tapping the dimmed background (not a control) hides the overlay,
                // so "tap again to hide" works even though the overlay sits above
                // the gesture zones while visible.
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            VStack(spacing: 0) {
                // Top bar
                HStack(spacing: 12) {
                    iconCircle("chevron.down") { dismiss() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(S8KFont.subhead).foregroundColor(.white).lineLimit(1)
                        if vm.isLive {
                            HStack(spacing: 5) {
                                Circle().fill(Color.s8kRed).frame(width: 6, height: 6)
                                Text(L("play.live_now")).font(S8KFont.caption2).foregroundColor(.s8kTextSecondary)
                            }
                        }
                    }
                    Spacer()
                    // AirPlay (native route picker)
                    AirPlayButton(tint: .white)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.4)).clipShape(Circle())
                    // Native Picture-in-Picture (AVPlayer engine only)
                    if vm.pipSupported {
                        iconCircle("pip.enter") { vm.startPiP() }
                    }
                    // Lock the screen (disable gestures/controls)
                    iconCircle("lock.fill") {
                        gestureLocked = true; haptic.impactOccurred(); showControls = false
                    }
                    iconCircle(isLandscape ? "arrow.down.right.and.arrow.up.left" : "rotate.right") {
                        toggleOrientation()
                    }
                }
                .padding(.horizontal, S8KSpace.lg)
                .padding(.top, isLandscape ? S8KSpace.md : 50)

                Spacer()

                // Center transport
                HStack(spacing: 36) {
                    if episodeContext != nil {
                        ctrlBtn(icon: "backward.end.fill", size: 22) { goPrev() }
                            .opacity(prevEpisode == nil ? 0.3 : 1)
                            .disabled(prevEpisode == nil)
                    } else if canZap {
                        ctrlBtn(icon: "backward.end.fill", size: 22) { zap(-1) }   // previous channel
                    }
                    if !vm.isLive {
                        ctrlBtn(icon: "gobackward.10", size: 28) { vm.skip(-10) }
                    }
                    Button(action: { vm.togglePlay(); resetControlsTimer() }) {
                        Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64)).foregroundColor(.s8kGoldHigh)
                            .shadow(color: .s8kGoldHigh.opacity(0.35), radius: 12)
                    }
                    .buttonStyle(S8KButtonStyle())
                    if !vm.isLive {
                        ctrlBtn(icon: "goforward.10", size: 28) { vm.skip(10) }
                    }
                    if episodeContext != nil {
                        ctrlBtn(icon: "forward.end.fill", size: 22) { goNext() }
                            .opacity(nextEpisode == nil ? 0.3 : 1)
                            .disabled(nextEpisode == nil)
                    } else if canZap {
                        ctrlBtn(icon: "forward.end.fill", size: 22) { zap(1) }      // next channel
                    }
                }

                Spacer()

                // Bottom: progress + actions
                VStack(spacing: 10) {
                    if sleepActive {
                        HStack(spacing: 5) {
                            Image(systemName: "moon.fill").font(.system(size: 10))
                            Text(sleepText).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(.s8kGoldMid)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.black.opacity(0.5)).clipShape(Capsule())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if vm.duration > 0 {
                        Slider(value: $scrubValue, in: 0...1, onEditingChanged: { editing in
                            if editing {
                                scrubStartTime = vm.currentTime   // anchor for the delta chip
                                withAnimation(.easeInOut(duration: 0.15)) { scrubbing = true }
                                lastScrubStep = -1
                                scrubHaptic.prepare()         // warm the Taptic engine for zero-latency ticks
                                vm.beginScrub()               // freeze audio, ready for live preview
                            } else {
                                vm.endScrub(to: scrubValue)   // precise landing + resume
                                withAnimation(.easeInOut(duration: 0.15)) { scrubbing = false }
                                resetControlsTimer()
                            }
                        })
                        .tint(.s8kGoldHigh)
                        .onChange(of: scrubValue) { _, v in
                            guard scrubbing else { return }
                            vm.scrub(to: v)                   // fast preview seek while dragging (engine coalesces)
                            // Distance-based detents (~one per 5% of the bar) so the tactile
                            // rhythm is constant regardless of content length — not per-pixel,
                            // not a fixed 5s (which machine-guns on long movies).
                            let step = Int(v * 20)
                            if step != lastScrubStep {
                                lastScrubStep = step
                                scrubHaptic.selectionChanged()
                                scrubHaptic.prepare()
                            }
                        }
                        .onChange(of: vm.currentTime) { _, _ in
                            if !scrubbing { scrubValue = vm.progress }
                        }
                        // Time bubble floats just ABOVE the seek bar and tracks the
                        // thumb horizontally (YouTube/Infuse style) — never under the
                        // centre play/pause button.
                        .overlay {
                            if scrubbing, vm.duration > 0 {
                                GeometryReader { geo in
                                    scrubBubbleView()
                                        .fixedSize()
                                        .position(x: scrubBubbleX(geo.size.width), y: -32)
                                }
                                .allowsHitTesting(false)
                                .transition(.opacity)
                            }
                        }
                        HStack {
                            Text(scrubbing ? fmtTime(scrubValue * vm.duration, forceHours: vm.duration >= 3600) : vm.currentFmt)
                            Spacer()
                            Text(vm.durationFmt)
                        }
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundColor(.s8kTextTertiary)
                    }

                    // Live program guide (now playing + progress)
                    if case .live(let ch) = currentItem {
                        EPGNowNext(channel: ch, compact: true)
                    }
                    // Action row — spacing 6 (not 10) so all 6 chips (VOD) clear the
                    // 48pt circles on a 375pt phone (iPhone SE/8) without clipping.
                    HStack(spacing: 6) {
                        actionChip(vm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                   L("play.audio"), active: vm.isMuted) { vm.toggleMute() }
                        actionChip("waveform", L("play.audio_track"), active: false) {
                            vm.loadAudioTracks(); showAudioSheet = true
                        }
                        actionChip("captions.bubble", L("play.subtitle"), active: vm.currentSubtitle >= 0) {
                            vm.loadSubtitles(); showSubtitleSheet = true
                        }
                        if !vm.isLive {
                            actionChip("speedometer",
                                       vm.rate == 1.0 ? L("play.speed") : speedLabel(vm.rate),
                                       active: vm.rate != 1.0) { showSpeedSheet = true }
                        }
                        actionChip("aspectratio", vm.aspectLabel, active: vm.aspectIndex != 0) {
                            vm.cycleAspect()
                        }
                        actionChip("moon.stars", sleepActive ? sleepText : L("play.sleep"), active: sleepActive) {
                            showSleepSheet = true
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, S8KSpace.xl)
                .padding(.bottom, isLandscape ? S8KSpace.md : 36)
            }
        }
    }

    private func iconCircle(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: { action(); resetControlsTimer() }) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                .frame(width: 38, height: 38).background(Color.black.opacity(0.4)).clipShape(Circle())
        }
        .buttonStyle(S8KButtonStyle())
    }
    private func ctrlBtn(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: { action(); resetControlsTimer() }) {
            Image(systemName: icon).font(.system(size: size, weight: .medium)).foregroundColor(.white)
        }
        .buttonStyle(S8KButtonStyle())
    }
    private func actionChip(_ icon: String, _ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { action(); resetControlsTimer() }) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(active ? AnyShapeStyle(S8KGradient.goldFlat)
                                     : AnyShapeStyle(Color.white.opacity(0.10)))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().strokeBorder(
                            active ? Color.clear : Color.white.opacity(0.16), lineWidth: 1))
                        .shadow(color: active ? .s8kGoldMid.opacity(0.4) : .clear, radius: 8, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(active ? .black : .white)
                }
                Text(label)
                    .font(S8KFont.caption3)
                    .foregroundColor(active ? .s8kGoldMid : .s8kTextSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(S8KButtonStyle())
    }

    // MARK: - Orientation
    /// A zero-cost, full-size probe that reports the player's actual dimensions so
    /// `isLandscape` reflects the true orientation on every device (fixes the iPad
    /// rotate button + landscape insets, where `vSize` was always `.regular`).
    private var orientationReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { updateLandscape(geo.size) }
                .onChange(of: geo.size) { _, s in updateLandscape(s) }
        }
    }
    private func updateLandscape(_ size: CGSize) {
        let land = size.width > size.height
        if isLandscape != land { isLandscape = land }
    }

    private func toggleOrientation() {
        // Free rotation is already allowed; the button just nudges to the
        // opposite orientation for convenience.
        let target: UIInterfaceOrientationMask = isLandscape ? .portrait : .landscapeRight
        AppDelegate.orientationLock = .allButUpsideDown
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
        }
        resetControlsTimer()
    }
    // (Portrait restore moved to the PlayerView wrapper's onDisappear.)

    // MARK: - Controls auto-hide
    private func toggleControls() {
        // The implicit `.animation(value: showControls)` modifier drives the
        // fade — toggling the plain @State is instant and avoids a double
        // animation that made show/hide feel laggy (#8).
        showControls.toggle()
        if showControls { resetControlsTimer() }
    }
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        // Don't auto-hide while paused/stalled — only run the countdown when playing.
        guard vm.isPlaying else { return }
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { _ in
            showControls = false
        }
    }

    // Debounced buffering indicator: show only if the stall outlasts ~0.3s, and
    // once shown keep it visible ≥1.2s so a brief re-buffer can't blink it.
    private func updateBufferingUI() {
        let busy = vm.isLoading || vm.buffering
        bufferShowWork?.cancel()
        if busy {
            let work = DispatchWorkItem {
                guard vm.isLoading || vm.buffering else { return }
                withAnimation { showBufferingUI = true }
                bufferShownAt = Date()
            }
            bufferShowWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        } else if showBufferingUI {
            let elapsed = bufferShownAt.map { Date().timeIntervalSince($0) } ?? 1.2
            let remaining = max(0, 1.2 - elapsed)
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                if !(vm.isLoading || vm.buffering) { withAnimation { showBufferingUI = false } }
            }
        } else {
            showBufferingUI = false
        }
    }

    // MARK: - Sleep timer
    private var sleepText: String { String(format: "%02d:%02d", sleepRemaining / 60, sleepRemaining % 60) }
    private func fmtTime(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "--:--" }
        let h = Int(t) / 3600, m = Int(t) % 3600 / 60, s = Int(t) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
    // Same formatter but with a fixed field count decided by the asset length, so
    // a >1h movie keeps a constant width while scrubbing (no mm:ss→h:mm:ss jump).
    private func fmtTime(_ t: Double, forceHours: Bool) -> String {
        guard t.isFinite, t >= 0 else { return "--:--" }
        let h = Int(t) / 3600, m = Int(t) % 3600 / 60, s = Int(t) % 60
        return (h > 0 || forceHours) ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    // Horizontal centre for the scrub bubble = the seek thumb position, clamped
    // so the bubble never runs off either edge of the bar.
    private func scrubBubbleX(_ width: CGFloat) -> CGFloat {
        let inset: CGFloat = 14                       // ~half the iOS slider thumb
        let x = inset + CGFloat(scrubValue) * max(width - inset * 2, 1)
        return min(max(x, 58), max(width - 58, 58))
    }

    // The compact, elegant scrub read-out: target time + a gold delta chip
    // (how far from where the drag began). Frosted glass, hairline, soft shadow.
    @ViewBuilder
    private func scrubBubbleView() -> some View {
        let target   = scrubValue * vm.duration
        let delta    = target - scrubStartTime
        let longForm = vm.duration >= 3600
        VStack(spacing: 2) {
            Text(fmtTime(target, forceHours: longForm))
                .font(.system(size: 16, weight: .bold)).monospacedDigit()
                .foregroundColor(.white)
            if abs(delta) >= 1 {
                Text("\(delta >= 0 ? "+" : "−")\(fmtTime(abs(delta)))")
                    .font(.system(size: 10.5, weight: .bold)).monospacedDigit()
                    .foregroundColor(.s8kGoldHigh)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        // Frosted glass over a dark scrim → the timecode stays legible even on a
        // bright frame (blur alone can wash out over high-key video).
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }
    private func startSleep(mins: Int) {
        sleepActive = true; sleepRemaining = mins * 60
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if sleepRemaining > 0 { sleepRemaining -= 1 }
            else { vm.pause(); sleepActive = false; sleepTimer?.invalidate() }
        }
    }
    private func cancelSleep() { sleepTimer?.invalidate(); sleepActive = false; sleepRemaining = 0 }

    private var sleepSheet: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                VStack(spacing: 0) {
                    if sleepActive {
                        VStack(spacing: 20) {
                            ZStack {
                                Circle().stroke(Color.s8kCard, lineWidth: 8).frame(width: 120)
                                Circle()
                                    .trim(from: 0, to: CGFloat(sleepRemaining) / CGFloat(max(1, Store.shared.sleepTimerMins * 60)))
                                    .stroke(S8KGradient.goldFlat, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                    .frame(width: 120).rotationEffect(.degrees(-90))
                                Text(sleepText).font(.system(size: 26, weight: .black, design: .monospaced)).foregroundColor(.white)
                            }
                            .padding(.vertical, 24)
                            Text(L("play.sleep.will_stop")).font(S8KFont.callout).foregroundColor(.s8kTextTertiary)
                            OutlineButton(title: L("play.sleep.cancel"), icon: "xmark.circle") { cancelSleep(); showSleepSheet = false }
                                .padding(.horizontal, 40)
                        }
                    } else {
                        VStack(spacing: 4) {
                            Text(L("play.sleep.choose")).font(S8KFont.subhead).foregroundColor(.s8kTextTertiary).padding(.vertical, 14)
                            ForEach([15, 30, 45, 60, 90, 120], id: \.self) { mins in
                                Button(action: { Store.shared.sleepTimerMins = mins; startSleep(mins: mins); showSleepSheet = false }) {
                                    HStack {
                                        Image(systemName: "moon.stars.fill").foregroundColor(.s8kGoldMid)
                                        Text("\(mins) \(L("unit.minute"))").font(S8KFont.headline).foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "chevron.left").font(.system(size: 12)).foregroundColor(.s8kTextDisabled)
                                    }
                                    .padding(.horizontal, S8KSpace.xl).padding(.vertical, 15)
                                    .background(Color.s8kSurface).clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                                }
                                .buttonStyle(S8KButtonStyle()).padding(.horizontal, S8KSpace.xl)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(L("play.sleep.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.close")) { showSleepSheet = false }.foregroundColor(.s8kGoldMid) } }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Subtitle sheet
    private var subtitleSheet: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                if vm.subtitleTracks.isEmpty {
                    EmptyState(icon: "captions.bubble", title: L("play.subtitle.empty.title"),
                               subtitle: L("play.subtitle.empty.sub"))
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            subtitleSizeRow
                            subtitleRow(title: L("play.subtitle.none"), isOn: vm.currentSubtitle < 0) {
                                vm.selectSubtitle(-1); showSubtitleSheet = false
                            }
                            ForEach(vm.subtitleTracks, id: \.id) { track in
                                subtitleRow(title: track.name, isOn: vm.currentSubtitle == track.id) {
                                    vm.selectSubtitle(track.id); showSubtitleSheet = false
                                }
                            }
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .navigationTitle(L("play.subtitle.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.close")) { showSubtitleSheet = false }.foregroundColor(.s8kGoldMid) } }
        }
        .presentationDetents([.medium])
    }
    // Subtitle-size presets (VLC engine): tap to change size live while watching.
    // NOTE: libVLC's rel-fontsize is INVERSE — a SMALLER number renders BIGGER text —
    // so the values below descend from صغير→ضخم. (16 ≈ VLC's Normal default.) We never
    // send 0: it's a divisor in the renderer, so 0 could divide-by-zero.
    private var subtitleSizeRow: some View {
        let presets: [(String, Int)] = [
            (L("subsize.small"), 22), (L("subsize.medium"), 16),
            (L("subsize.large"), 12), (L("subsize.xl"), 8)
        ]
        return VStack(alignment: .trailing, spacing: 8) {
            Text(L("play.subtitle.size"))
                .font(S8KFont.caption1).foregroundColor(.s8kTextTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.1) { label, px in
                        // Highlight Medium when unset (0 = VLC default ≈ Normal/16).
                        FilterPill(title: label,
                                   isOn: vm.subtitleFontSize == px || (vm.subtitleFontSize == 0 && px == 16)) {
                            vm.setSubtitleFontSize(px)   // applies live on the VLC engine
                        }
                    }
                }
            }
        }
        .padding(.horizontal, S8KSpace.xl).padding(.bottom, 8)
    }
    private func subtitleRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isOn { Image(systemName: "checkmark.circle.fill").foregroundColor(.s8kGoldMid) }
                Spacer()
                Text(title).font(S8KFont.headline).foregroundColor(isOn ? .s8kGoldMid : .white)
            }
            .padding(.horizontal, S8KSpace.xl).padding(.vertical, 15)
            .background(Color.s8kSurface).clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
        }
        .buttonStyle(S8KButtonStyle()).padding(.horizontal, S8KSpace.xl)
    }

    // MARK: - Playback speed sheet (#package)
    private func speedLabel(_ r: Float) -> String {
        // Trim trailing ".0" → "2x", keep "1.5x"
        let s = String(format: "%g", Double(r))
        return "\(s)x"
    }
    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private var speedSheet: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(speedOptions, id: \.self) { r in
                            let isOn = abs(vm.rate - r) < 0.001
                            Button(action: { vm.setRate(r); showSpeedSheet = false }) {
                                HStack {
                                    if isOn { Image(systemName: "checkmark.circle.fill").foregroundColor(.s8kGoldMid) }
                                    Spacer()
                                    Text(r == 1.0 ? L("play.speed.normal") : speedLabel(r))
                                        .font(S8KFont.headline).foregroundColor(isOn ? .s8kGoldMid : .white)
                                }
                                .padding(.horizontal, S8KSpace.xl).padding(.vertical, 15)
                                .background(Color.s8kSurface).clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                            }
                            .buttonStyle(S8KButtonStyle()).padding(.horizontal, S8KSpace.xl)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            .navigationTitle(L("play.speed.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.close")) { showSpeedSheet = false }.foregroundColor(.s8kGoldMid) } }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Audio track sheet (#package: audio selection + remember)
    private var audioSheet: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                if vm.audioTracks.isEmpty {
                    EmptyState(icon: "waveform", title: L("play.audio_track.empty.title"),
                               subtitle: L("play.audio_track.empty.sub"))
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(vm.audioTracks, id: \.id) { track in
                                subtitleRow(title: track.name, isOn: vm.currentAudio == track.id) {
                                    vm.selectAudio(track.id); showAudioSheet = false
                                }
                            }
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .navigationTitle(L("play.audio_track.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(L("common.close")) { showAudioSheet = false }.foregroundColor(.s8kGoldMid) } }
        }
        .presentationDetents([.medium])
    }
}
