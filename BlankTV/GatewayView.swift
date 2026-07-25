// ============================================================
// BLANK TV — GatewayView.swift
// The login GATEWAY (owner-approved muvy-style design, distinct from the Strong8K
// reference for App Store distinctiveness): a full-bleed 3-row poster wall that
// scrolls SEAMLESSLY in alternating directions, behind the app's own logo/wordmark
// and a compact Xtream/M3U login card. Responsive across iPhone / iPad / Mac.
//
// Posters are BUNDLED (Assets: gwposter1…6) so they paint instantly (no network).
// Reuses the proven LoginView auth logic verbatim.
// ============================================================

import SwiftUI
import UIKit   // UIViewRepresentable / UIScrollView (touch-delay probe below)

// Bundled poster asset names (owner-supplied art). Swap freely — just data.
private let gatewayPosters = ["gwposter1", "gwposter2", "gwposter3", "gwposter4", "gwposter5", "gwposter6"]

private let gwSpacing: CGFloat = 12

// Poster card size adapts to the CLASS of device, never to a measured width:
// compact (every iPhone, 375→440pt, and iPad Slide Over at 320pt) vs regular
// (iPad / Mac, up to 1376pt). No GeometryReader, no arithmetic that can go negative.
private let gwCardWCompact: CGFloat = 112
private let gwCardWRegular: CGFloat = 152
private func gwCardH(_ w: CGFloat) -> CGFloat { (w * 3.0 / 2.0).rounded() }   // 2:3 poster
private func gwBaseWidth(_ w: CGFloat) -> CGFloat { CGFloat(gatewayPosters.count) * (w + gwSpacing) }

// MARK: - One SEAMLESS infinite marquee row
// The base 6-poster set is repeated `reps` times; the offset animates by EXACTLY
// one base-set width. Because poster[6] is identical to poster[0] and the item
// stride is uniform (cardW+spacing), the loop is perfectly seamless — no jump,
// no gap, never ends.
private struct GatewayMarqueeRow: View, Equatable {
    let posters: [String]
    let reversed: Bool
    let reps: Int
    let cardW: CGFloat
    let speed: Double            // points per second (calm ≈ 16–24)
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Equatable + `.equatable()` at the call site: without it, EVERY keystroke in the
    // login form re-runs GatewayView.body and rebuilds all of these poster images
    // (SwiftUI cannot skip a non-Equatable child's body). Now the wall is rebuilt only
    // when its own inputs actually change.
    static func == (l: Self, r: Self) -> Bool {
        l.cardW == r.cardW && l.reversed == r.reversed && l.reps == r.reps
            && l.speed == r.speed && l.posters == r.posters
    }

    var body: some View {
        let base = gwBaseWidth(cardW)
        HStack(spacing: gwSpacing) {
            // Explicit [Int] (NOT a variable-count Range ForEach, which traps when
            // `reps` changes on resize/rotation — see the launch-crash guardrail).
            ForEach(Array(0 ..< (posters.count * reps)), id: \.self) { i in
                Image(posters[i % posters.count])
                    .resizable()
                    .scaledToFill()
                    .frame(width: cardW, height: gwCardH(cardW))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
        .offset(x: offset)
        // NOTE: deliberately no `.drawingGroup()` here. Placed after `.offset` it would
        // rasterise the ANIMATED transform (re-rendering the whole texture every frame);
        // placed before it, the texture is thousands of points wide. The real win was
        // making this view Equatable so it stops rebuilding on every keystroke.
        .onAppear {
            offset = reversed ? -base : 0
            // Accessibility: users who ask for reduced motion get a still wall, not a
            // marquee (Apple requires this and App Review checks it).
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: Double(base) / max(speed, 1)).repeatForever(autoreverses: false)) {
                offset = reversed ? 0 : -base
            }
        }
    }
}

// MARK: - 3-row poster wall (alternating directions, seamless)
private struct GatewayPosterWall: View, Equatable {
    let cardW: CGFloat
    static func == (l: Self, r: Self) -> Bool { l.cardW == r.cardW }
    // 6 base-sets. The row is CENTRED in a full-width frame, so half of any surplus is
    // spent off the leading edge: full coverage at maximum offset needs
    // reps ≥ screenWidth/baseWidth + 2. Worst case (iPad Pro 13" landscape, 1376pt wide,
    // base 984pt) → 3.4, so 6 keeps a wide margin on every device. (3 was tried and
    // would have left a 202pt black gap at the end of each cycle on iPad.)
    private let reps = 6
    var body: some View {
        // `.id(cardW)`: the row seeds its animation in `.onAppear`, which does NOT fire
        // again when only a property changes. Without a new identity, a rotation that
        // changes cardW would leave the animation cycling over the OLD base width while
        // the layout stride is the new one — a permanent visible jump once per loop.
        VStack(spacing: gwSpacing) {
            GatewayMarqueeRow(posters: rotate(0), reversed: false, reps: reps, cardW: cardW, speed: 20).equatable().id(cardW)
            GatewayMarqueeRow(posters: rotate(2), reversed: true,  reps: reps, cardW: cardW, speed: 16).equatable().id(cardW)
            GatewayMarqueeRow(posters: rotate(4), reversed: false, reps: reps, cardW: cardW, speed: 22).equatable().id(cardW)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 30)
    }
    private func rotate(_ n: Int) -> [String] {
        let a = gatewayPosters
        guard !a.isEmpty else { return a }
        let k = n % a.count
        return Array(a[k...] + a[..<k])
    }
}

// MARK: - Touch responsiveness helpers
// A UIScrollView holds a touch for ~150ms before delivering it, to decide whether the
// gesture is a scroll. Inside a login form that reads as "the field / the toggle didn't
// respond". SwiftUI exposes no API for this, so this zero-size probe walks up to the
// enclosing UIScrollView once and turns the delay off. `canCancelContentTouches` stays
// true, so dragging still cancels an in-progress tap and scrolling is unaffected.
private struct GWNoTouchDelay: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Probe(frame: .zero) }
    func updateUIView(_ v: UIView, context: Context) {}
    private final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v: UIView? = superview
            while let cur = v {
                if let sv = cur as? UIScrollView {
                    sv.delaysContentTouches = false
                    sv.canCancelContentTouches = true
                    break
                }
                v = cur.superview
            }
        }
    }
}

// `.defaultScrollAnchor(.bottom)` on iOS 17 sets THREE behaviours at once: alignment of
// short content, the initial offset, and the response to size changes. We only want the
// first — otherwise, whenever the form is taller than the screen, the gateway opens
// already scrolled to the bottom and the user is looking at "Terms · Privacy" instead of
// the login fields. iOS 18 can separate the roles; on iOS 17 bottom-alignment is the
// more important of the two, so it keeps the combined behaviour.
private struct GWScrollAnchor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .defaultScrollAnchor(.bottom, for: .alignment)
                .defaultScrollAnchor(.top, for: .initialOffset)
        } else {
            content.defaultScrollAnchor(.bottom)
        }
    }
}

// MARK: - Xtream / M3U switcher
// Rebuilt for INSTANT feel (owner: "switching between Xtream and M3U is slow"). Three
// causes were found and all three are addressed here:
//  1. The selected pill used to be each tab's own `.background`, so it CROSSFADED
//     between two capsules. One shared capsule + `matchedGeometryEffect` now SLIDES.
//  2. Press feedback came from `configuration.isPressed`, which is unreliable inside a
//     ScrollView (UIScrollView holds the touch ~150ms to see if it is a drag) — so the
//     control looked dead for the first moment. Motion is now driven by STATE, plus a
//     haptic that fires on touch-up regardless of render timing.
//  3. `withAnimation` was global: it dragged the whole screen (scroll height, safe area,
//     poster wall) into the transaction. The animation is now SCOPED to this control.
// Timing follows the split every motion system prescribes: the pill (spatial) may
// overshoot slightly at 0.26s; the label colour (effect) settles faster at 0.12s, so the
// text reads as being AHEAD of the motion — which is what "instant" feels like.
private struct GatewayModeSwitcher: View {
    @Binding var mode: LoginMode
    var onChange: () -> Void
    @Namespace private var ns
    @State private var haptic = UISelectionFeedbackGenerator()

    var body: some View {
        HStack(spacing: 0) {
            tab(.xtream, "Xtream", "person.badge.key.fill")
            tab(.m3u, "M3U", "link")
        }
        .padding(5)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            .allowsHitTesting(false))
        .animation(.snappy(duration: 0.26, extraBounce: 0.12), value: mode)
        .onAppear { haptic.prepare() }        // cold Taptic engines fire ~100ms late
    }

    @ViewBuilder
    private func tab(_ m: LoginMode, _ title: String, _ icon: String) -> some View {
        let on = (mode == m)
        Button {
            guard mode != m else { return }
            haptic.selectionChanged()          // BEFORE the state change, never inside it
            mode = m
            onChange()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(S8KFont.subhead.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundColor(on ? .s8kBlack : .s8kTextSecondary)
            .animation(.easeOut(duration: 0.12), value: mode)   // colour settles first
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background {
                if on {
                    // ONE capsule that moves between the two segments — no shadow
                    // (an animated coloured shadow forces an offscreen pass every frame
                    //  over a live poster wall).
                    Capsule(style: .continuous)
                        .fill(S8KGradient.goldFlat)
                        .matchedGeometryEffect(id: "gwModePill", in: ns)
                }
            }
            // Rectangle, not Capsule: a capsule hit shape rounds ~22pt off each corner,
            // leaving dead spots exactly where a thumb lands. The pill stays visually
            // a capsule — only the TAP area is square.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)   // NOT S8KButtonStyle: isPressed is unreliable in a ScrollView
    }
}

// MARK: - Gateway
struct GatewayView: View {
    var onClose: (() -> Void)? = nil
    @StateObject private var auth = AuthService.shared
    @StateObject private var activation = ActivationService.shared
    @StateObject private var loc = LocalizationManager.shared
    // Size classes are the ONLY adaptivity input: they are supplied by the system
    // (device + orientation + iPad Split View / Stage Manager + Mac window) and can
    // never yield a bad number, unlike a measured width.
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    @State private var loginMode = LoginMode.xtream
    @State private var serverOrCode = ""
    @State private var username = ""
    @State private var password = ""
    @State private var m3uURL = ""
    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var showAccounts = false          // multi-account picker
    @State private var entering: String? = nil        // account being entered

    // Poster size follows BOTH size classes: only a genuinely large canvas (iPad /
    // Mac, not a Pro Max in landscape) gets the big cards. Keeping it out of the
    // phone-landscape case also stops a 738pt-tall wall in a 390pt-tall window.
    private var gwCardW: CGFloat {
        (hSize == .regular && vSize == .regular) ? gwCardWRegular : gwCardWCompact
    }

    var body: some View {
        // ROOT = a plain VStack — the simplest construction that exists, chosen after
        // three failed attempts:
        //   • GeometryReader root  → reported a bad size, `min(width-44, 430)` went
        //     NEGATIVE, `.frame(width: -44)` collapsed the foreground ("only posters").
        //   • .overlay(alignment:.top) → an `.ignoresSafeArea()` sibling INFLATES the
        //     ZStack's own frame to full screen, so "top" was under the Dynamic Island.
        //   • .safeAreaInset(edge:.top) on that same inflated ZStack → the language
        //     pill still did not show on device.
        // Here the top bar is simply the FIRST CHILD of a VStack that respects the safe
        // area, and the poster wall is a `.background` (a background can never inflate
        // its host). There is nothing left to measure and nothing left to get wrong.
        VStack(spacing: 0) {
            topBar
            // ONE ScrollView, always — deliberately NOT `ViewThatFits`. A ViewThatFits
            // branch swap is a structural identity change: the moment the keyboard
            // appeared the layout would flip branches, every text field would be torn
            // down and rebuilt, focus would be lost and the keyboard would drop again.
            // The touch delay a ScrollView normally adds is removed directly instead
            // (`GWNoTouchDelay` below), and the row-wide tap target added to
            // S8KTextField is what actually fixed the "sticky fields".
            ScrollView(.vertical, showsIndicators: false) {
                loginBlock.background(GWNoTouchDelay().frame(width: 0, height: 0))
            }
            .modifier(GWScrollAnchor())
            .scrollBounceBehavior(.basedOnSize)   // no rubber-band when it already fits
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            ZStack {
                Color.s8kBlack
                GatewayPosterWall(cardW: gwCardW).equatable()
                LinearGradient(stops: [
                    .init(color: .clear,                       location: 0.00),
                    .init(color: Color.s8kBlack.opacity(0.15), location: 0.26),
                    .init(color: Color.s8kBlack.opacity(0.55), location: 0.40),
                    .init(color: Color.s8kBlack.opacity(0.90), location: 0.49),
                    .init(color: Color.s8kBlack,               location: 0.56),
                    .init(color: Color.s8kBlack,               location: 1.00),
                ], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        }
        // Accessibility text is honoured up to AX1; beyond that a login form cannot
        // stay legible on a 375pt screen, so we clamp instead of breaking the layout.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showTerms)   { TermsView() }
        .sheet(isPresented: $showAccounts) { accountSheet }
    }

    // The foreground column (single call site — inside the ScrollView).
    private var loginBlock: some View {
        VStack(spacing: vSize == .compact ? 14 : 20) {
            brand
            if !Store.shared.savedPlaylists.isEmpty { switchAccountButton }
            loginCard
            footer
        }
        // maxWidth (NOT a fixed width): the outer padding takes 24pt off each side
        // BEFORE the frame resolves, so the block is always ≤ width − 48 (272pt in a
        // 320pt iPad Slide Over pane, 327pt on an iPhone SE) and stops at a tidy 400,
        // centred, on iPad/Mac. It can never overflow, and — unlike the old
        // `min(geo.width - 44, 430)` — it can never go negative.
        .frame(maxWidth: 400)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // MARK: Top bar — close (optional) + language pill
    private var topBar: some View {
        HStack(spacing: 12) {
            if onClose != nil {
                Button { onClose?() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(S8KButtonStyle())
            }
            Spacer(minLength: 0)
            langMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: Multi-account — a professional "switch account" entry + picker sheet.
    // Reuses the proven switchPlaylist login so a returning user picks a saved
    // subscription instead of re-typing (owner: avoid entry errors).
    private var switchAccountButton: some View {
        Button { showAccounts = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill").font(.system(size: 13, weight: .semibold))
                Text("\(L("accounts.switch")) · \(Store.shared.savedPlaylists.count)")
                    .font(S8KFont.subhead.weight(.bold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.s8kGoldMid)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.s8kGoldMid.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.s8kBorderGold, lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }

    private var accountSheet: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(Store.shared.savedPlaylists) { acc in accountRow(acc) }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(L("accounts.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(L("common.close")) { showAccounts = false }.foregroundColor(.s8kGoldMid)
            } }
            .toolbarBackground(Color.s8kBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func accountRow(_ acc: SavedPlaylist) -> some View {
        let isEntering = entering == acc.id
        return Button { enter(acc) } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                        .fill(S8KGradient.goldFlat).frame(width: 50, height: 50)
                    Image(systemName: acc.kind == .xtream ? "person.badge.key.fill" : "link")
                        .font(.system(size: 19, weight: .bold)).foregroundColor(.s8kBlack)
                }
                VStack(alignment: .trailing, spacing: 3) {
                    Text(acc.name).font(S8KFont.headline).foregroundColor(.s8kTextPrimary).lineLimit(1)
                    Text(acc.subtitle).font(S8KFont.caption1).foregroundColor(.s8kTextTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                if isEntering { ProgressView().tint(.s8kGoldHigh) }
                else { Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).foregroundColor(.s8kTextTertiary) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous).fill(Color.s8kCard))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous).strokeBorder(Color.s8kBorder, lineWidth: 1))
        }
        .buttonStyle(S8KButtonStyle())
    }

    private func enter(_ acc: SavedPlaylist) {
        guard entering == nil else { return }
        entering = acc.id
        Task {
            await auth.switchPlaylist(acc)
            auth.loggedIn = true
            entering = nil
        }
    }

    // A high-contrast GOLD pill so the user always sees the language switch before login.
    private var langMenu: some View {
        Menu {
            ForEach(AppLang.allCases) { l in
                Button { loc.set(l) } label: {
                    if loc.lang == l { Label(l.display, systemImage: "checkmark") } else { Text(l.display) }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "globe").font(.system(size: 14, weight: .bold))
                Text(loc.lang.display).font(S8KFont.subhead.weight(.heavy))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.s8kBlack)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(S8KGradient.goldFlat))
            .shadow(color: .black.opacity(0.4), radius: 9, y: 3)
        }
    }

    // MARK: Brand — the app's OWN logo + wordmark (no tagline)
    private var brand: some View {
        // Slightly smaller in a short window (phone/iPad landscape) so the form keeps
        // the room it needs; full size everywhere else.
        let compactH = (vSize == .compact)
        return VStack(spacing: compactH ? 8 : 12) {
            BrandLogo(size: compactH ? 48 : 66)
            S8KWordmark(size: compactH ? 24 : 30)
        }
        .padding(.bottom, 2)
    }

    // MARK: Login card
    private var loginCard: some View {
        VStack(spacing: 11) {
            GatewayModeSwitcher(mode: $loginMode) { auth.error = nil }
            if loginMode == .xtream {
                if Store.shared.resellerHost?.isEmpty != false {
                    S8KTextField(placeholder: L("login.server_or_code"), icon: "server.rack", text: $serverOrCode,
                                 ltr: true, keyboard: .URL, contentType: .URL, disableAutocorrect: true, capitalization: .never)
                }
                S8KTextField(placeholder: L("login.username"), icon: "person.fill", text: $username,
                             ltr: true, contentType: .username, disableAutocorrect: true, capitalization: .never)
                S8KTextField(placeholder: L("login.password"), icon: "lock.fill", text: $password,
                             isSecure: true, disableAutocorrect: true, capitalization: .never)
                    .transition(.opacity)
            } else {
                S8KTextField(placeholder: "http://server.com/playlist.m3u", icon: "link", text: $m3uURL,
                             ltr: true, keyboard: .URL, contentType: .URL, disableAutocorrect: true, capitalization: .never)
                    .transition(.opacity)
            }

            if let err = auth.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13))
                    Text(err.errorDescription ?? L("common.error")).font(S8KFont.caption1)
                }
                .foregroundColor(.s8kRed).padding(12).frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color.s8kRed.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm))
                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm).strokeBorder(Color.s8kRed.opacity(0.2), lineWidth: 1))
                .transition(.opacity)
            }

            GoldButton(title: loginMode == .xtream ? L("login.signin") : L("login.load_playlist"),
                       icon: "play.fill", isLoading: auth.isLoading,
                       isDisabled: loginMode == .xtream ? (username.isEmpty || password.isEmpty) : m3uURL.isEmpty) {
                submit()
            }
        }
        // Cross-FADE the field set on a mode change (never a slide — a horizontal push
        // on a 2-way toggle reads as page navigation), and let the card's own height
        // change ride a separate, slightly slower spring than the pill.
        .animation(.easeOut(duration: 0.18), value: loginMode)
    }

    // (the switcher lives in its own `GatewayModeSwitcher` view, defined above)

    // MARK: Footer — demo + legal
    private var footer: some View {
        VStack(spacing: 13) {
            Button { auth.enterDemo() } label: {
                Text(L("login.demo")).font(S8KFont.subhead.weight(.semibold)).foregroundColor(.s8kGoldMid)
            }
            .buttonStyle(S8KButtonStyle()).padding(.top, 14)
            HStack(spacing: 5) {
                Button(L("set.terms"))   { showTerms = true }.foregroundColor(.s8kTextTertiary)
                Text("·").foregroundColor(.s8kTextDisabled)
                Button(L("set.privacy")) { showPrivacy = true }.foregroundColor(.s8kTextTertiary)
            }
            .font(S8KFont.caption2)
        }
        .padding(.bottom, 22)
    }

    // MARK: Login action (faithful to the proven LoginView logic)
    private func submit() {
        Task {
            if loginMode == .xtream {
                let typed = serverOrCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if looksLikeResellerCode(typed) {
                    auth.error = nil; auth.isLoading = true
                    let ok = await activation.resolveCode(typed)
                    guard ok, let host = Store.shared.resellerHost, !host.isEmpty else {
                        auth.isLoading = false; auth.error = .server(L("code.invalid")); return
                    }
                    auth.isLoading = false
                    await auth.loginXtream(host: host, username: username, password: password)
                } else {
                    let host = !typed.isEmpty ? typed : (Store.shared.resellerHost ?? "")
                    await auth.loginXtream(host: host, username: username, password: password)
                }
            } else {
                await auth.loginM3U(urlString: m3uURL)
            }
        }
    }

    private func looksLikeResellerCode(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t.contains("://") || t.contains(".") || t.contains(":") || t.contains("/") { return false }
        return t.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil
    }
}
