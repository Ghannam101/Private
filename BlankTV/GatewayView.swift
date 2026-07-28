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

// NOTE: there is deliberately NO `defaultScrollAnchor` here any more.
// It caused the reported "the keyboard is very far away and the screen jumps up" bug.
// Mechanism: keyboard avoidance shrinks the scroll view's FRAME by the keyboard height,
// and a bottom anchor re-pins the content to the bottom of that frame — so the whole
// login block translated upward by the FULL keyboard height as a rigid body, on top of
// (and independently of) UIKit's own "scroll the focused field into view". With no
// anchor, the frame still shrinks but the content stays put and only the minimum
// necessary scrolling happens — which is exactly "the field sits just above the
// keyboard". The resting composition is kept low by padding instead (see loginBlock),
// because padding does not react to the viewport.

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
        // Crisp rounded rect at the system's own radii (track = md 10, indicator = sm 7,
        // nested with a 4pt inset so the corners stay concentric) — NOT a soft capsule.
        // The design system's chips are documented as "crisp rectangular, not a soft
        // capsule"; the capsule here was the outlier fighting its own language.
        .padding(4)
        .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
            .fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
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
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background {
                if on {
                    // ONE indicator that moves between the two segments — flat accent,
                    // no shadow (an animated coloured shadow forces an offscreen pass
                    // every frame over a live poster wall).
                    RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                        .fill(Color.s8kGoldHigh)
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
    // A @State COPY, refreshed on appear and when the picker closes. Reading
    // `Store.shared.savedPlaylists` straight from `body` looks fine but nothing observes
    // it, so adding an account elsewhere would not refresh this screen.
    @State private var accounts: [SavedPlaylist] = Store.shared.savedPlaylists
    /// Full screen height, read from a probe in the background (see `body`). Keyboard-
    /// immune, rotation-aware. Drives `topInset` only — never a width, so it can never
    /// collapse the layout the way the old GeometryReader root did.
    @State private var winH: CGFloat = 0

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
            // (`s8kInstantTaps` below), and the row-wide tap target added to
            // S8KTextField is what actually fixed the "sticky fields".
            ScrollView(.vertical, showsIndicators: false) {
                loginBlock.s8kInstantTaps()
            }
            // 20pt of breathing room under the content: iOS scrolls a focused field
            // FLUSH against the viewport edge, which puts it right on the keyboard.
            .contentMargins(.bottom, 20, for: .scrollContent)
            // `.always` (not `.basedOnSize`): when the form fits there is otherwise no
            // scroll gesture at all, and then `.interactively` has nothing to hook into
            // — the user cannot swipe the keyboard away.
            .scrollBounceBehavior(.always)
            .scrollDismissesKeyboard(.interactively)
        }
        .background {
            ZStack {
                Color.s8kBlack
                GatewayPosterWall(cardW: gwCardW).equatable()
                // The scrim reaches SOLID black by 42% of the screen (was 56%). The card
                // is no longer bottom-anchored, so on a short phone its top edge lands at
                // roughly a third of the way down — at the old stops the poster wall was
                // still ~65% visible straight through the translucent fields.
                LinearGradient(stops: [
                    .init(color: .clear,                       location: 0.00),
                    .init(color: Color.s8kBlack.opacity(0.15), location: 0.16),
                    .init(color: Color.s8kBlack.opacity(0.55), location: 0.26),
                    .init(color: Color.s8kBlack.opacity(0.90), location: 0.36),
                    .init(color: Color.s8kBlack,               location: 0.42),
                    .init(color: Color.s8kBlack,               location: 1.00),
                ], startPoint: .top, endPoint: .bottom)
                // Window-height probe. It lives in the BACKGROUND (which cannot affect
                // layout) and inside `.ignoresSafeArea()` — so it reports the full screen
                // height and, crucially, does NOT shrink when the keyboard appears. That
                // makes `topInset` stable while typing yet correct after an iPad rotation,
                // which changes neither the size class nor the safe area and would
                // otherwise leave a stale inset pushing the fields below the fold.
                GeometryReader { g in
                    Color.clear
                        .onAppear { winH = g.size.height }
                        .onChange(of: g.size.height) { _, h in if h > 1 { winH = h } }
                }
            }
            .ignoresSafeArea()
        }
        // Accessibility text is honoured up to AX1; beyond that a login form cannot
        // stay legible on a 375pt screen, so we clamp instead of breaking the layout.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .task { accounts = Store.shared.savedPlaylists }
        .sheet(isPresented: $showPrivacy) { PrivacyView() }
        .sheet(isPresented: $showTerms)   { TermsView() }
        .sheet(isPresented: $showAccounts, onDismiss: { accounts = Store.shared.savedPlaylists }) {
            accountSheet
        }
    }

    // The foreground column (single call site — inside the ScrollView).
    private var loginBlock: some View {
        VStack(spacing: vSize == .compact ? 14 : 20) {
            brand
            if !accounts.isEmpty { switchAccountButton }
            loginCard
            footer
        }
        // maxWidth (NOT a fixed width): the outer padding takes 24pt off each side
        // BEFORE the frame resolves, so the block is always ≤ width − 48 (272pt in a
        // 320pt iPad Slide Over pane, 327pt on an iPhone SE) and stops at a tidy 400,
        // centred, on iPad/Mac. It can never overflow, and — unlike the old
        // `min(geo.width - 44, 430)` — it can never go negative.
        .frame(maxWidth: 400)   // owner-approved width for this card specifically
        .padding(.horizontal, 24)
        .padding(.top, topInset)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    // Keeps the card sitting LOW over the poster wall now that the scroll view is no
    // longer bottom-anchored — without reintroducing the jump. The inset is derived from
    // the WINDOW height, which (unlike the scroll viewport) does NOT shrink when the
    // keyboard appears, so the layout is stable while typing.
    // Budget: ~150pt of chrome (safe areas + top bar) + ~600pt of card ⇒ every point of
    // window above ~766 is slack that belongs ABOVE the block. A flat 72 left the form
    // stranded in the upper third of an iPad, on the transparent part of the scrim, with
    // posters showing through the translucent fields.
    private var topInset: CGFloat {
        if vSize == .compact { return 16 }          // short window: give the form the room
        let h = winH > 1 ? winH : s8kWindowSize().height   // probe first, singleton as seed
        return max(16, h - 766)
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
                .accessibilityLabel(L("common.close"))
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
    // An IDENTITY ROW, not a button (owner: "the switch-account button is a plain
    // rectangle and not elegant"). It was a full-width tinted capsule the same size and
    // shape as the CTA below it, carrying no information — so it read as a second, weaker
    // primary button. Now it shows WHO you are: a lime beam down the leading edge, the
    // saved accounts as tappable tiles (one tap = straight in, no sheet, no re-typing),
    // and a picker affordance for the rest.
    private var switchAccountButton: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.s8kGoldHigh.opacity(0.9))
                .frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5))

            // Up to 3 accounts as direct-entry tiles.
            HStack(spacing: 8) {
                ForEach(accounts.prefix(3)) { acc in accountTile(acc) }
            }

            VStack(alignment: rowAlign, spacing: 2) {
                Text(accounts.first?.name ?? L("accounts.switch"))
                    .font(S8KFont.headline).foregroundColor(.s8kTextPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text("\(L("accounts.switch")) · \(accounts.count)")
                    .font(S8KFont.caption1).foregroundColor(.s8kTextSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: rowAlign == .leading ? .leading : .trailing)

            // Opens the full picker. `chevron.up.chevron.down` is the standard "this
            // opens a chooser" glyph — a bare chevron.down promises a disclosure.
            Button { showAccounts = true } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.s8kTextTertiary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(S8KButtonStyle())
            .accessibilityLabel(L("accounts.title"))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(minHeight: 60)
        .background(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
            .fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: S8KRadius.lg, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            .allowsHitTesting(false))
    }

    // The app forces layoutDirection .leftToRight globally, so text alignment has to be
    // driven by the LANGUAGE, not by "leading".
    private var rowAlign: HorizontalAlignment {
        LocalizationManager.current.isRTL ? .trailing : .leading
    }

    // One saved account: 34pt tile, tap = sign in immediately with it.
    private func accountTile(_ acc: SavedPlaylist) -> some View {
        let isEntering = entering == acc.id
        return Button { enter(acc) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                    .fill(Color.s8kGoldHigh)
                    .frame(width: 34, height: 34)
                if isEntering {
                    ProgressView().tint(S8KBrand.accentInk).scaleEffect(0.7)
                } else {
                    Text(String(acc.name.prefix(1)).uppercased())
                        .font(S8KFont.headline.weight(.heavy))
                        .foregroundColor(S8KBrand.accentInk)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
        .disabled(entering != nil)
        .accessibilityLabel(acc.name)
    }

    private var accountSheet: some View {
        NavigationStack {
            ZStack {
                Color.s8kBlack.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(accounts) { acc in accountRow(acc) }
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
                        .font(.system(size: 19, weight: .bold)).foregroundColor(S8KBrand.accentInk)
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
            .foregroundColor(S8KBrand.accentInk)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(S8KGradient.goldFlat))
            .shadow(color: .black.opacity(0.4), radius: 9, y: 3)
        }
    }

    // MARK: Brand — the app's OWN logo + wordmark (no tagline)
    // Owner-approved lockup: a SMALL mark above a LARGE wordmark, aligned to the side
    // rather than centred — an editorial signature, deliberately unlike the centred
    // ornamental brand block of the sibling app.
    //
    // THE BRAND IS FIXED. It does NOT mirror with the language (owner: "it must not
    // change no matter what the language is — it is the app's identity"). A logo lockup
    // is an identity mark, not UI chrome: real brands keep the same lockup in every
    // locale. Only the surrounding UI mirrors. It aligns to the LOGIN CARD's edge (it
    // lives inside the same 400pt column), never the screen edge, so the page keeps a
    // single axis.
    private var brand: some View {
        let compactH = (vSize == .compact)
        return VStack(alignment: .leading, spacing: compactH ? 8 : 10) {
            BrandLogo(size: compactH ? 36 : 44)
            S8KWordmark(size: compactH ? 22 : 28)
            // A thin accent rule under the wordmark. Deliberately 2pt and WITHOUT the
            // glow used by section headers, so the brand does not read as a section title.
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.s8kGoldHigh)
                .frame(width: 28, height: 2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
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
                // `.asciiCapable`: IPTV credentials are ASCII. With `.default` a user
                // whose keyboard is set to Arabic can type non-ASCII into a credential
                // field and the login just fails.
                S8KTextField(placeholder: L("login.username"), icon: "person.fill", text: $username,
                             ltr: true, keyboard: .asciiCapable, contentType: .username,
                             disableAutocorrect: true, capitalization: .never)
                // `contentType: .password` is REQUIRED for iOS Password AutoFill: a
                // .username field with no paired .password field breaks the heuristic
                // outright — saved credentials never fill and iOS never offers to save.
                // `ltr: true` was MISSING: without it this field alone laid out
                // right-to-left while its two siblings were left-to-right.
                S8KTextField(placeholder: L("login.password"), icon: "lock.fill", text: $password,
                             isSecure: true, ltr: true, keyboard: .asciiCapable,
                             contentType: .password,
                             disableAutocorrect: true, capitalization: .never)
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
                // Alignment follows the LANGUAGE, not "trailing": the app forces LTR
                // globally, so a hard-coded .trailing right-aligned English errors.
                .foregroundColor(.s8kRed).padding(12)
                .frame(maxWidth: .infinity,
                       alignment: LocalizationManager.current.isRTL ? .trailing : .leading)
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
            // Demoted to neutral text: a coloured link 20pt under the accent CTA was a
            // second "primary" competing with the real one. Exactly ONE accent-filled
            // element belongs on this screen.
            Button { auth.enterDemo() } label: {
                Text(L("login.demo")).font(S8KFont.subhead.weight(.semibold))
                    .foregroundColor(.s8kTextSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .buttonStyle(S8KButtonStyle()).padding(.top, 14)
            // Reseller support — this lived on the retired SubscriptionsGateView, and
            // without it a customer whose line has expired has no way to reach their
            // reseller from the login screen.
            if let support = activation.supportURL, let u = URL(string: support) {
                Button { UIApplication.shared.open(u) } label: {
                    Text(L("login.need_help")).font(S8KFont.caption1.weight(.semibold))
                        .foregroundColor(.s8kTextSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .buttonStyle(S8KButtonStyle())
            }
            HStack(spacing: 5) {
                Button(L("set.terms"))   { showTerms = true }.foregroundColor(.s8kTextTertiary)
                Text("·").foregroundColor(.s8kTextDisabled)
                Button(L("set.privacy")) { showPrivacy = true }.foregroundColor(.s8kTextTertiary)
            }
            .font(S8KFont.caption2)

            // The player-only disclaimer, ON THE FIRST SCREEN. It used to live in
            // Settings -> About and on the activation gate, i.e. two places a reviewer
            // assessing an IPTV app under Guideline 5.2.3 may never open. This is the
            // one screen they are guaranteed to see.
            Text(S8KLegal.disclaimer)
                .font(S8KFont.caption3)
                .foregroundColor(.s8kTextDisabled)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, S8KSpace.xl)
                .padding(.top, 4)
        }
        .padding(.bottom, 22)
    }

    // MARK: Login action (faithful to the proven LoginView logic)
    private func submit() {
        Task {
            if loginMode == .xtream {
                let typed = serverOrCode.trimmingCharacters(in: .whitespacesAndNewlines)
                // A bare token used to be sent to resolveCode, which cannot succeed —
                // the user always got "invalid code" for a feature that does not exist.
                // Say what the field actually wants instead.
                if looksLikeResellerCode(typed) {
                    auth.error = .server(L("login.need_url")); return
                }
                let host = !typed.isEmpty ? typed : (Store.shared.resellerHost ?? "")
                await auth.loginXtream(host: host, username: username, password: password)
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
