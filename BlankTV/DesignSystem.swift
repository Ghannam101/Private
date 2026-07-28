// ============================================================
// BLANK TV — DesignSystem.swift
// Complete Design System — Colors, Fonts, Components
// iOS 17+ • Apple HIG Compliant
// ============================================================
//
// NOTE: the internal color tokens keep their legacy `s8kGold*` names
// (to avoid touching every view file), but they now hold the BLANK TV
// GREEN brand palette — lime #CBFF06 / teal #00BC72 / deep-green #001A0B.
// Treat "gold" in identifiers as "the brand accent".
// ============================================================

import SwiftUI
import ImageIO
import UIKit

// MARK: - Window metrics (device compatibility)
// The size of the WINDOW the app is actually running in — NOT `UIScreen.main.bounds`,
// which always reports the whole physical display and is therefore wrong in iPad
// Split View / Slide Over (panes as narrow as 320pt), Stage Manager, and on Mac
// (a freely resized window). Any layout derived from the screen instead of the window
// renders a phone-sized page inside a small pane, or a giant one inside a big screen.
// Falls back to the screen only if no window scene is available (e.g. very early launch).
/// One pre-warmed selection haptic for the whole app. `UISelectionFeedbackGenerator`
/// needs `prepare()` to spin up the Taptic Engine; a fresh instance per view body is
/// always cold, so the first tap after any idle period feels unacknowledged.
@MainActor let s8kSelectionHaptic: UISelectionFeedbackGenerator = {
    let g = UISelectionFeedbackGenerator()
    g.prepare()
    return g
}()

/// The CURRENT window's safe-area insets, read from the window scene rather than from a
/// GeometryReader — because a reader placed inside a container that already ignored the
/// safe area reports zero, which would make a notch phone look inset-free.
@MainActor func s8kWindowInsets() -> EdgeInsets {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let i = active?.keyWindow?.safeAreaInsets ?? .zero
    return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
}

@MainActor func s8kWindowSize() -> CGSize {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    if let s = active?.keyWindow?.bounds.size, s.width > 1, s.height > 1 { return s }
    if let s = active?.screen.bounds.size, s.width > 1, s.height > 1 { return s }
    return UIScreen.main.bounds.size
}

// ============================================================
// MARK: - S8KMetrics — THE canonical layout system
// ============================================================
// Every layout number in the app should be either an S8KSpace/S8KRadius token or a
// member of this type. It exists because the same numbers were being re-derived
// per page and patched device-by-device: there were THREE near-identical hero
// formulas that disagreed, eleven different width caps, five grid rules and three
// different bottom spacers.
//
// The rule that makes it safe: it is derived from the WINDOW (via `s8kWindowSize()`,
// which is keyboard-immune) and the size classes — it NEVER measures a width from a
// nested GeometryReader. That is what makes the "min(geo.width - 44, 430) went
// negative and the screen collapsed" class of bug unrepresentable.

/// The device classes the app reasons about. Branch on THIS, never on a raw width
/// and never on `UIDevice.current.userInterfaceIdiom`.
enum S8KDeviceClass: Int, Comparable {
    case compactNarrow      // compact, w < 390   — 320pt iPad pane, 375 SE / mini
    case compactRegular     // compact, 390…413   — 390 / 393 / 402
    case compactWide        // compact, w ≥ 414   — 414…440, 566pt split, phone landscape
    case regularMedium      // regular, w < 720   — small Mac window, 2/3 panes
    case regularLarge       // regular, 720…1099  — every iPad portrait
    case regularXL          // regular, w ≥ 1100  — iPad landscape, large Mac

    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }

    static func classify(width w: CGFloat, hClass: UserInterfaceSizeClass?) -> S8KDeviceClass {
        if hClass == .regular {
            if w < 720  { return .regularMedium }
            if w < 1100 { return .regularLarge }
            return .regularXL
        }
        if w < 390 { return .compactNarrow }
        if w < 414 { return .compactRegular }
        return .compactWide
    }
    var isCompact: Bool { self <= .compactWide }
}

struct S8KMetrics: Equatable {
    let size: CGSize                 // the WINDOW, never the screen
    let safeArea: EdgeInsets
    let hClass: UserInterfaceSizeClass?
    let vClass: UserInterfaceSizeClass?
    let cls: S8KDeviceClass

    init(size: CGSize, safeArea: EdgeInsets = EdgeInsets(),
         hClass: UserInterfaceSizeClass?, vClass: UserInterfaceSizeClass?) {
        // max(_, 1): the very first layout pass can report .zero, and every derived
        // value would then be NaN or negative.
        let s = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        self.size = s; self.safeArea = safeArea
        self.hClass = hClass; self.vClass = vClass
        self.cls = S8KDeviceClass.classify(width: s.width, hClass: hClass)
    }

    /// Merge in a page's measured safe area (from its page-root GeometryReader).
    func withSafeArea(_ i: EdgeInsets) -> S8KMetrics {
        S8KMetrics(size: size, safeArea: i, hClass: hClass, vClass: vClass)
    }

    var safeTop: CGFloat    { max(0, safeArea.top) }
    var safeBottom: CGFloat { max(0, safeArea.bottom) }

    private func pick<T>(_ cn: T, _ cr: T, _ cw: T, _ rm: T, _ rl: T, _ rx: T) -> T {
        switch cls {
        case .compactNarrow:  return cn
        case .compactRegular: return cr
        case .compactWide:    return cw
        case .regularMedium:  return rm
        case .regularLarge:   return rl
        case .regularXL:      return rx
        }
    }

    // ---- Margins ----
    var gutter: CGFloat      { pick(16, 20, 20, 24, 28, 32) }
    var gridSpacing: CGFloat { pick(12, 14, 14, 16, 16, 18) }

    // ---- Width caps: three ROLES instead of eleven numbers ----
    /// Feeds, rails, poster grids.
    var contentMaxWidth: CGFloat { pick(.infinity, .infinity, .infinity, 760, 900, 1040) }
    /// Anything read line by line. Apple's readable width tops out ≈672pt.
    var readableMaxWidth: CGFloat { cls.isCompact ? .infinity : 640 }
    /// Every form in the app (login, add playlist, PIN).
    var formMaxWidth: CGFloat { 440 }

    /// The width content actually gets after the cap and both gutters.
    var contentWidth: CGFloat { max(1, min(size.width, contentMaxWidth) - gutter * 2) }

    // ---- Chrome ----
    /// The pinned page-identity bar, EXCLUDING the safe area.
    var topBarHeight: CGFloat { cls.isCompact ? 62 : 68 }
    /// What a full-bleed scroll reserves so content clears that bar.
    var topBarReserve: CGFloat { safeTop + topBarHeight }
    /// The floating AppTabBar's footprint: the 58pt puck + its 10pt bottom padding.
    var tabBarFootprint: CGFloat { 68 }
    /// What a scroll running to the PHYSICAL bottom must reserve. Replaces the
    /// hand-written 110 / 100 / 130 — which over-reserved 42pt on an SE and
    /// under-reserved the comfort gap on a Dynamic Island phone.
    var bottomClearance: CGFloat { tabBarFootprint + S8KSpace.md + safeBottom }

    // ---- Hero ----
    /// How much of the NEXT row must stay visible under the hero: a rail heading
    /// (21pt heavy + 3pt underline + 8pt gap) plus 56pt of the first card.
    var heroPeek: CGFloat { 88 }
    /// + safeTop for the same reason heroHeight adds it: the card reserves that strip
    /// as an empty band so the poster clears the status bar. On a regular window this
    /// cap ALREADY binds (an iPad's ideal is 650-765 against a 560 cap), so without
    /// carrying the strip through, iPad would take the band without the compensating
    /// height — the hero would stay the same size and the artwork inside it would
    /// simply get 24pt smaller. Strictly worse than before on that device class.
    var heroMaxHeight: CGFloat { (cls.isCompact ? 660 : 560) + safeTop }

    /// ONE hero formula for the whole app, full-bleed (it already spans the area
    /// under the status bar — call sites must NOT add `+ topInset`).
    ///
    /// Width × a shape-derived aspect, then clamped by the viewport. The `ceiling`
    /// term is what the old per-page formulas were missing, and its absence is
    /// exactly why an iPhone SE got a hero 78% as tall as the screen and why every
    /// phone in landscape got a hero TALLER than its own viewport.
    var heroHeight: CGFloat {
        let r = size.height / size.width                 // page shape
        let t = min(max((r - 1.15) / 1.15, 0), 1)        // 0 = landscape-ish, 1 = very tall
        let aspect = 0.56 + 0.90 * t                     // 16:9 → tall cinematic crop
        // + safeTop: the card now starts its artwork BELOW the system's reserved strip
        // (see heroCard), because the status bar, the Dynamic Island and the pinned bar
        // were all being drawn over the top of the poster. Without adding that strip
        // back, lowering the artwork would simply have made it shorter. Every clamp
        // below still applies, so a short window is unaffected.
        let ideal = size.width * aspect + safeTop
        let ceiling = size.height - bottomClearance - heroPeek   // the peek guarantee
        let capped = min(ideal, heroMaxHeight, ceiling, size.height * 0.80)
        // FLOOR = the hero card's own incompressible copy stack (tag row + a 2-line
        // title + rule + rating + a 52pt button row + page dots ≈ 248pt). Below that the
        // card cannot lay out: the copy would overflow upward — and the carousel is
        // deliberately un-clipped for the stretch, so it would draw off the top of the
        // screen under the pinned title. The `0.80` keeps the floor itself honest in a
        // pathologically short window.
        return max(capped, min(248, size.height * 0.80))
    }

    @MainActor static var fallback: S8KMetrics {
        S8KMetrics(size: s8kWindowSize(), hClass: nil, vClass: nil)
    }
}

private struct S8KMetricsKey: EnvironmentKey {
    static let defaultValue = S8KMetrics(size: CGSize(width: 393, height: 852),
                                         hClass: .compact, vClass: .regular)
}
extension EnvironmentValues {
    var s8kMetrics: S8KMetrics {
        get { self[S8KMetricsKey.self] }
        set { self[S8KMetricsKey.self] = newValue }
    }
}

/// Install ONCE, around the TabView. The window size is read by a GeometryReader
/// that lives in a `.background` and ignores the safe area — the only measurement
/// this codebase trusts: a background can never inflate its host, and ignoring the
/// safe area makes the reading keyboard-immune. Seeded from `s8kWindowSize()` so
/// the very first frame is already correct.
struct S8KMetricsRoot<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var h
    @Environment(\.verticalSizeClass) private var v
    @State private var window: CGSize = .zero
    @State private var insets: EdgeInsets = EdgeInsets()
    @ViewBuilder var content: () -> Content

    var body: some View {
        let size = window.width > 1 ? window : s8kWindowSize()
        // Merge PER EDGE, not all-or-nothing. Probe 2 sits inside a container the TabView
        // has already stripped of its BOTTOM safe area, so the realistic failure is a
        // PARTIAL zero — e.g. (top: 0, bottom: 34) — which an `== EdgeInsets()` guard
        // would happily accept, reporting a notch phone as having no top inset.
        let w = s8kWindowInsets()
        let ins = EdgeInsets(top: max(insets.top, w.top),
                             leading: max(insets.leading, w.leading),
                             bottom: max(insets.bottom, w.bottom),
                             trailing: max(insets.trailing, w.trailing))
        content()
            .environment(\.s8kMetrics,
                         S8KMetrics(size: size, safeArea: ins, hClass: h, vClass: v))
            .background {
                ZStack {
                    // Probe 1 — SIZE. Ignores the safe area (and therefore the keyboard),
                    // so the window size never shrinks while typing.
                    GeometryReader { g in
                        Color.clear
                            .onAppear { if g.size.width > 1 { window = g.size } }
                            .onChange(of: g.size) { _, s in if s.width > 1 { window = s } }
                    }
                    .ignoresSafeArea()
                    // Probe 2 — INSETS. Does NOT ignore the safe area, so it reports the
                    // real notch / home-indicator insets. Read separately because a view
                    // that ignores the safe area reports its insets as zero.
                    GeometryReader { g in
                        Color.clear
                            .onAppear { insets = g.safeAreaInsets }
                            .onChange(of: g.safeAreaInsets) { _, i in insets = i }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

/// Publish a page's measured safe area to the metrics in its subtree. Use from a
/// page-root GeometryReader — the ONE placement of GeometryReader this codebase
/// allows — and only ever for insets, never for a width.
extension View {
    func s8kSafeArea(_ insets: EdgeInsets) -> some View {
        modifier(S8KSafeAreaInjector(insets: insets))
    }
}
private struct S8KSafeAreaInjector: ViewModifier {
    let insets: EdgeInsets
    @Environment(\.s8kMetrics) private var m
    func body(content: Content) -> some View {
        content.environment(\.s8kMetrics, m.withSafeArea(insets))
    }
}

// MARK: - Stretchy full-bleed hero header
extension View {
    /// Pull-to-stretch for artwork sitting at the TOP of a vertical ScrollView.
    ///
    /// The naive implementation — recomputing `.frame(height: h + pull)` from a
    /// GeometryReader every frame — is what most sample code does and it is wrong here:
    /// it re-runs LAYOUT on every scroll frame (visible stutter), it makes the header
    /// greedy inside a LazyVStack, and it produces NEGATIVE heights the moment the user
    /// scrolls the other way.
    ///
    /// This scales the already-rendered layer instead, anchored at the BOTTOM:
    ///     scale = (height + pull) / height          ← always ≥ 1, never negative
    /// A bottom anchor pins the bottom edge (nothing below moves) and grows the top edge
    /// upward by exactly the gap the over-scroll opened — so the artwork fills it
    /// *by construction*, with no seam and no tuned constant. `scaleEffect` is a GPU
    /// transform on a rasterised layer: no re-layout, no image re-decode.
    ///
    /// `parallax` lets the artwork lag as the page scrolls over it. DEFAULT 0: this feed
    /// has no opaque rows, so a lagging hero stays visible BEHIND the rails that scroll
    /// over it — and because a visual effect is render-only, its buttons would still be
    /// hit-testable up to 150pt away from where they are drawn.
    func s8kStretchyHeader(parallax: CGFloat = 0) -> some View {
        visualEffect { effect, proxy in
            // max(_, 1): the first layout pass can report a zero size → NaN.
            let h = max(proxy.size.height, 1)
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            let pull = max(0, minY)                 // over-scroll only
            let scale = (h + pull) / h
            return effect
                .scaleEffect(x: scale, y: scale, anchor: .bottom)
                .offset(y: -min(0, minY) * parallax)
        }
    }

    /// iOS 26 draws its own blur/dim where a scroll view meets the safe area. Over a
    /// full-bleed hero that stacks on our scrim and muddies the band under the notch.
    @ViewBuilder func s8kNoScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) { self.scrollEdgeEffectHidden(true, for: .top) }
        else { self }
    }
}

// ============================================================
// MARK: - DETAIL PAGE LANGUAGE — "pinned canvas + editorial plinth"
// ============================================================
// The detail pages are built from these pieces and nothing else. The structure is
// deliberately NOT the universal streaming stack (full-bleed backdrop → title-logo
// PNG on the artwork → full-width Play bar → icon-triplet → 2-line synopsis), which
// every major service ships and which therefore reads as a clone of all of them.
//
// Here the artwork is a FIXED canvas that the content rises over, and the title is
// LIVE TYPE on an opaque plinth — never an image composited onto the artwork. That
// one decision is what makes the page distinct, and it also solves contrast,
// Dynamic Type, RTL and missing artwork at the same time: a title that lives on a
// solid surface cannot become illegible over someone else's poster, and a page
// whose identity is type still works when the catalogue has no backdrop at all
// (the metadata-agnostic rule).

/// Language-driven alignment. The app forces `layoutDirection = .leftToRight`
/// globally, so "leading" is the physical left even in Arabic — text has to be
/// aligned by the LANGUAGE instead.
@MainActor var s8kIsRTL: Bool { LocalizationManager.current.isRTL }

/// Episode numerals, formatted by LOCALE. In Arabic locales this renders ١ ٢ ٣ —
/// which is both correct and an identity marker a Latin-only app cannot reproduce.
/// Never hand-format a number: digit ORDER never reverses in RTL, only the glyphs
/// change, and `NumberFormatter` is the only thing that gets that right.
private let s8kNumberFormatter: NumberFormatter = {
    let f = NumberFormatter(); f.numberStyle = .none; return f
}()
@MainActor func s8kEpisodeNumeral(_ n: Int) -> String {
    s8kNumberFormatter.locale = Locale(identifier: LocalizationManager.current.rawValue)
    return s8kNumberFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
}
@MainActor var s8kTextAlign: HorizontalAlignment { s8kIsRTL ? .trailing : .leading }
@MainActor var s8kFrameAlign: Alignment { s8kIsRTL ? .trailing : .leading }
@MainActor var s8kMultiline: TextAlignment { s8kIsRTL ? .trailing : .leading }

/// The opaque surface the page content rides on. It scrolls UP over the fixed
/// artwork canvas and covers it. Opaque by requirement: Apple's own guidance is
/// that glass belongs to the navigation layer, never to a content background.
struct S8KPlinth<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: 28,
                                       style: .continuous)
                    .fill(Color.s8kBlack)
                    .shadow(color: .black.opacity(0.55), radius: 20, y: -8)
            )
    }
}

/// The primary action. A capsule sized to its CONTENT — not a full-width bar, which
/// is the single most-copied element in the category — with an inset progress rule
/// along its bottom edge when the title is partly watched.
struct S8KPlayCapsule: View {
    let title: String
    var progress: Double = 0
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // The ▶ glyph must NOT mirror in Arabic — media transport controls
                // keep their direction. Only the capsule's POSITION in the row flips.
                Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                Text(title).font(.system(size: 16, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundColor(S8KBrand.accentInk)
            .padding(.horizontal, 26)
            .frame(minHeight: 54)
            .background(Capsule(style: .continuous).fill(Color.s8kGoldHigh))
            .overlay(alignment: .bottom) {
                if progress > 0.02 && progress < 0.98 {
                    GeometryReader { g in
                        Capsule().fill(Color.s8kBlack.opacity(0.30))
                            .frame(width: max(0, (g.size.width - 28) * min(max(progress, 0), 1)),
                                   height: 2)
                            .frame(maxWidth: .infinity, alignment: s8kIsRTL ? .trailing : .leading)
                            .padding(.horizontal, 14)
                    }
                    .frame(height: 2).padding(.bottom, 9)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(S8KButtonStyle())
    }
}

/// A secondary action: a 48pt circular glass satellite. Same object as the tool-row
/// buttons on the main pages, so the app has ONE control vocabulary.
struct S8KSatellite: View {
    let icon: String
    var tint: Color = .s8kGoldHigh
    var label: String = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold)).foregroundColor(tint)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false))
                .contentShape(Circle())
        }
        .buttonStyle(S8KButtonStyle())
        // An EMPTY label wipes the inferred VoiceOver name instead of leaving it —
        // the first call site that forgets the argument would ship a completely silent
        // button. Fall back to the SF Symbol name, which at least says something.
        .accessibilityLabel(label.isEmpty ? icon : label)
    }
}

/// A synopsis that clamps to four lines and expands IN PLACE. Four, not two: at ~41
/// characters per line on a phone, four lines is one whole thought — and a two-line
/// clamp is another service's signature. Expanding in place (rather than opening a
/// sheet) keeps the scroll position, which is the whole point of the pattern.
struct S8KExpandableText: View {
    let text: String
    var lineLimit: Int = 4
    @State private var expanded = false
    var body: some View {
        VStack(alignment: s8kTextAlign, spacing: 8) {
            Text(text)
                .font(.system(size: 16))
                .lineSpacing(9)                       // 1.55 leading: a phone measure is
                .foregroundColor(.s8kTextSecondary)   // short, so compensate with leading
                .multilineTextAlignment(s8kMultiline)
                .lineLimit(expanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
            // Only offer the toggle when there is something to reveal — ~160 characters
            // is four lines at the ~41 characters a phone measure actually fits.
            // Otherwise a one-line synopsis got a "More" chevron that did nothing.
            if text.count > 160 {
                HStack(spacing: 5) {
                    Text(expanded ? L("common.less") : L("common.more"))
                        .font(S8KFont.caption1.weight(.bold))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.s8kGoldHigh)
                .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.3)) { expanded.toggle() } }
    }
}

/// A section heading in the app's OWN motif: heavy title with a short accent rule
/// BENEATH it — the same object as `SectionHeader` on the main pages. (The detail
/// pages used to carry a right-aligned title with a vertical bar beside it, which is
/// the other app's motif and contradicted our own approved pages inside one binary.)
struct S8KDetailHeading: View {
    let title: String
    var body: some View {
        VStack(alignment: s8kTextAlign, spacing: 7) {
            Text(title).font(.system(size: 19, weight: .black)).foregroundColor(.s8kTextPrimary)
            RoundedRectangle(cornerRadius: 2).fill(Color.s8kGoldHigh).frame(width: 30, height: 3)
        }
        .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
    }
}

/// Panels publish a trailer as either a bare YouTube id or a full URL, and a fair
/// number publish junk (an empty string, "n/a", a stray path). Returns nil unless the
/// value resolves to something openable — the trailer button is hidden on nil, so a
/// bad value costs the user nothing instead of a dead tap.
func s8kTrailerURL(_ raw: String?) -> URL? {
    guard var v = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
    if v.lowercased() == "n/a" || v.lowercased() == "null" { return nil }
    if v.hasPrefix("//") { v = "https:" + v }
    if v.lowercased().hasPrefix("http") {
        // HOST ALLOW-LIST. This is the only place in the whole binary where text the
        // PANEL controls becomes a system-browser navigation — streams are opened by
        // the in-app player. Without the gate, a hostile or compromised panel gets a
        // one-tap drive-by under a button the user reads as "the trailer". Panels
        // publish a bare YouTube id in the overwhelming majority of cases, so the
        // user-visible loss is close to nothing.
        guard let u = URL(string: v), let host = u.host?.lowercased(),
              S8KTrailerHosts.allowed.contains(host) else { return nil }
        return u
    }
    // A bare id: YouTube ids are exactly 11 chars of ASCII [A-Za-z0-9_-]. `isLetter`
    // alone is true for Arabic and CJK, which would build a bogus URL.
    let ok = v.count == 11 && v.allSatisfy {
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
    }
    return ok ? URL(string: "https://www.youtube.com/watch?v=\(v)") : nil
}

private enum S8KTrailerHosts {
    static let allowed: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
        "youtube-nocookie.com", "www.youtube-nocookie.com",
        "vimeo.com", "www.vimeo.com", "player.vimeo.com",
    ]
}

@MainActor
func s8kOpenURL(_ url: URL) {
    guard UIApplication.shared.canOpenURL(url) else { return }
    UIApplication.shared.open(url)
}

/// Removes UIScrollView's ~150ms content-touch delay for the enclosing scroll view.
///
/// UIKit holds a touch back to decide whether it is the start of a scroll, so a button
/// inside a ScrollView does not highlight until the finger has been down long enough to
/// rule that out. On a browsing app that reads as lag on EVERY tap. The gateway already
/// carried a private copy of this — it is what fixed the "sticky fields" — and this is
/// the same probe promoted so the rest of the app can have it too.
///
/// `canCancelContentTouches` stays true, so a drag that starts on a button still scrolls;
/// only the highlight becomes immediate.
struct S8KNoTouchDelay: UIViewRepresentable {
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

/// Decode budget for hero artwork. One function so the PREFETCH and the VIEW cannot
/// disagree: `S8KImageCache` keys on the URL alone and ignores `maxPixel`, so whoever
/// asks first fixes the size for everyone — and the prefetch always runs first.
/// 2000 clears an iPad Pro's 2732px at a magnification no one can see after the crop,
/// and keeps eight heroes inside the 96 MB cache. 2600 does not.
func s8kHeroPixels(_ compact: Bool) -> CGFloat { compact ? 1400 : 2000 }

extension View {
    /// Attach to a scroll view's CONTENT (not the ScrollView itself) — the probe walks
    /// up from where it is planted to find the enclosing UIScrollView.
    func s8kInstantTaps() -> some View {
        background(S8KNoTouchDelay().frame(width: 0, height: 0))
    }
}

// MARK: - Details sheet
/// The extra facts a panel publishes about a title, in this app's own language.
///
/// Deliberately NOT the two-column "Label ……… Value" table every IPTV player ships:
/// the descriptive facts are STACKED (a small tertiary caption with the value beneath
/// it, so an Arabic value is never squeezed against a leader), and the technical facts
/// are CHIPS — short tokens the eye takes in at a glance, which is how anyone actually
/// reads "4K · H264 · AAC".
///
/// Every section disappears when it has nothing to say. A panel that publishes only a
/// country gets a sheet with one line, not a page of empty rows — that is the whole
/// point of a metadata-agnostic UI.
struct S8KDetailsSheet: View {
    let title: String
    let details: S8KTitleDetails
    var onTrailer: (() -> Void)? = nil

    private var chipColumns: [GridItem] { [GridItem(.adaptive(minimum: 104), spacing: 10)] }

    /// The sheet already prints the title, so a panel that repeats it as "original
    /// name" — which most do for anything not foreign-language — would open with the
    /// same words twice. Drop that row rather than show the user nothing new.
    private var editorial: [(String, String)] {
        details.editorial.filter { key, value in
            !(key == "details.original_name" && value.caseInsensitiveCompare(title) == .orderedSame)
        }
    }

    /// A fixed detent is wrong at both ends: this sheet's payload runs from one row
    /// to a dozen, so a fraction sized for the full case opens a sparse one mostly
    /// empty, and one sized for the sparse case opens the full one cropped. The row
    /// count is known at build time, so size to it. `.large` stays as the fallback.
    private var detent: Double {
        let chipRows = details.technical.isEmpty ? 0 : 2
        return min(0.9, max(0.32, 0.24 + 0.07 * Double(editorial.count + chipRows)))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: s8kTextAlign, spacing: S8KSpace.xl) {
                S8KDetailHeading(title: L("details.title"))
                    .padding(.top, S8KSpace.lg)

                Text(title)
                    .font(S8KFont.subhead.weight(.semibold))
                    .foregroundColor(.s8kTextSecondary)
                    .multilineTextAlignment(s8kIsRTL ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: s8kFrameAlign)

                if !editorial.isEmpty {
                    section(L("details.about")) {
                        VStack(alignment: s8kTextAlign, spacing: 14) {
                            ForEach(editorial, id: \.0) { key, value in
                                VStack(alignment: s8kTextAlign, spacing: 3) {
                                    Text(L(key))
                                        .font(S8KFont.caption3)
                                        .foregroundColor(.s8kTextTertiary)
                                    Text(value)
                                        .font(S8KFont.subhead)
                                        .foregroundColor(.s8kTextPrimary)
                                        .multilineTextAlignment(s8kIsRTL ? .trailing : .leading)
                                }
                                .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
                            }
                        }
                    }
                }

                if !details.technical.isEmpty {
                    section(L("details.file")) {
                        LazyVGrid(columns: chipColumns, alignment: .center, spacing: 10) {
                            ForEach(details.technical, id: \.0) { key, value in
                                VStack(spacing: 3) {
                                    Text(value)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundColor(.s8kGoldHigh)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                    Text(L(key))
                                        .font(S8KFont.caption3)
                                        .foregroundColor(.s8kTextTertiary)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12).padding(.horizontal, 8)
                                .background(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                                    .fill(Color.white.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                            }
                        }
                    }
                }

                if let onTrailer {
                    Button(action: onTrailer) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill").font(.system(size: 15, weight: .semibold))
                            Text(L("details.trailer")).font(S8KFont.subhead.weight(.semibold))
                        }
                        .foregroundColor(.s8kTextPrimary)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                            .fill(Color.white.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(S8KButtonStyle())
                }

                Color.clear.frame(height: S8KSpace.xl)
            }
            .padding(.horizontal, S8KSpace.xl)
        }
        .background(Color.s8kBlack)
        .presentationDragIndicator(.visible)
        // A height, never .medium alone: the sheet's content ranges from one line to a
        // dozen, and a fixed detent would either crop the full case or leave the sparse
        // one mostly empty. `.large` is the fallback for the tallest payloads.
        .presentationDetents([.fraction(detent), .large])
    }

    @ViewBuilder
    private func section(_ heading: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: s8kTextAlign, spacing: 12) {
            Text(heading)
                .font(S8KFont.caption2.weight(.bold))
                .foregroundColor(.s8kGoldHigh)
                .frame(maxWidth: .infinity, alignment: s8kFrameAlign)
            content()
        }
    }
}

// MARK: - Pinned page identity bar (Movies / Series)
/// The section's name, in the WORDMARK's typeface, inside a frosted capsule beside the
/// app mark — so the page identifies itself over any artwork and stays legible while the
/// poster scrolls underneath it. Purely decorative: it must never intercept a scroll.
struct S8KSectionBar: View {
    let title: String
    var body: some View {
        HStack(spacing: 9) {
            BrandLogo(size: 22)
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                // Tracking ONLY for Latin. Arabic is cursive — inter-glyph tracking
                // breaks the joining stroke, and this is the app's most prominent label
                // in its default language.
                .tracking(LocalizationManager.current.isRTL ? 0 : 1.2)
                .foregroundColor(.s8kTextPrimary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.22)))
        .overlay(Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .allowsHitTesting(false)
    }
}

/// Hosts a pinned top bar over full-bleed artwork, at the correct height on every device.
///
/// This exists because of a trap this project has already paid for twice: a ZStack that
/// contains an `.ignoresSafeArea()` child is itself inflated to the FULL SCREEN, so
/// `.overlay(alignment: .top)` on it aligns to the physical top — under the Dynamic
/// Island — not to the safe area. The fix is to stop relying on the container's frame:
/// the overlay explicitly ignores the top safe area (so its own origin is the physical
/// top, deterministically) and then pads down by the measured inset.
/// It also carries the scrim that keeps the status bar legible over bright posters.
struct S8KPinnedPageBar<Content: View>: View {
    let topInset: CGFloat
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, max(0, topInset))
        .background(alignment: .top) {
            // Middle stop 0.45 (not 0.25): on a Dynamic Island phone the logo sits about
            // halfway down this ramp, and 0.25 left the wordmark soft over bright artwork.
            LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.45), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: max(0, topInset) + 78)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Brand theme (ready-made palettes + per-reseller re-skin)
// The whole app's brand colors read from `BrandTheme.active`, so swapping ONE
// palette (a ready-made brand, or a reseller's accent color) re-skins the entire
// app. Text/status colors stay neutral. See DESIGN.md §white-label.
struct BrandTheme {
    var base: Color        // app background
    var surface: Color
    var card: Color
    var elevated: Color
    var accentHigh: Color  // primary accent — buttons, highlights, indicators
    var accentMid: Color
    var accentLow: Color
    var accentDeep: Color

    /// The active theme the whole app renders with. Change it → the app re-skins.
    static var active: BrandTheme = .blankGreen

    // ---- Ready-made palettes ----
    static let blankGreen = BrandTheme(
        base:     Color(red: 0.000, green: 0.102, blue: 0.043),   // #001A0B
        surface:  Color(red: 0.016, green: 0.133, blue: 0.059),   // #04220F
        card:     Color(red: 0.027, green: 0.169, blue: 0.078),   // #072B14
        elevated: Color(red: 0.043, green: 0.212, blue: 0.110),   // #0B361C
        accentHigh: Color(red: 0.796, green: 1.000, blue: 0.024), // #CBFF06 lime
        accentMid:  Color(red: 0.000, green: 0.737, blue: 0.447), // #00BC72 teal
        accentLow:  Color(red: 0.000, green: 0.569, blue: 0.349), // #009159
        accentDeep: Color(red: 0.000, green: 0.451, blue: 0.290)  // #00734A
    )
    // NOTE: a `strongGold` palette used to live here — it reproduced the OTHER app's
    // exact base (#0A0A0A) and accent (#FFD700 / #C8860A). It was never referenced, but
    // it shipped inside the binary of the app we argue is a distinct product. Deleted:
    // an unused palette is not worth handing a reviewer a colour-for-colour match.

    /// Build a premium theme from a SINGLE reseller accent color: a neutral dark
    /// base (looks good with any hue) + an accent ramp derived from the color.
    static func fromAccent(_ hex: String) -> BrandTheme {
        let a = Color(hex: hex)
        return BrandTheme(
            base:     Color(red: 0.039, green: 0.039, blue: 0.043),
            surface:  Color(red: 0.055, green: 0.055, blue: 0.063),
            card:     Color(red: 0.082, green: 0.082, blue: 0.094),
            elevated: Color(red: 0.110, green: 0.110, blue: 0.125),
            accentHigh: a,
            accentMid:  a.adjusted(brightness: 0.80),
            accentLow:  a.adjusted(brightness: 0.62),
            accentDeep: a.adjusted(brightness: 0.48)
        )
    }
}

// MARK: - Color System — brand tokens read from the active BrandTheme
extension Color {
    // Brand-driven (re-skin with the active theme):
    static var s8kBlack:      Color { BrandTheme.active.base }
    static var s8kSurface:    Color { BrandTheme.active.surface }
    static var s8kCard:       Color { BrandTheme.active.card }
    static var s8kElevated:   Color { BrandTheme.active.elevated }
    static let s8kBorder     = Color.white.opacity(0.07)                       // neutral
    static var s8kBorderGold: Color { BrandTheme.active.accentMid.opacity(0.25) }

    static var s8kGoldHigh:   Color { BrandTheme.active.accentHigh }
    static var s8kGoldMid:    Color { BrandTheme.active.accentMid }
    static var s8kGoldLow:    Color { BrandTheme.active.accentLow }
    static var s8kGoldDeep:   Color { BrandTheme.active.accentDeep }

    // Neutral text — not brand-driven.
    static let s8kTextPrimary   = Color.white
    static let s8kTextSecondary = Color.white.opacity(0.60)
    static let s8kTextTertiary  = Color.white.opacity(0.35)
    static let s8kTextDisabled  = Color.white.opacity(0.20)

    // Status — fixed system colors.
    static let s8kRed    = Color(red: 1.000, green: 0.231, blue: 0.188) // #FF3B30
    static let s8kGreen  = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
    static let s8kBlue   = Color(red: 0.000, green: 0.478, blue: 1.000) // #007AFF
    static let s8kOrange = Color(red: 1.000, green: 0.584, blue: 0.000) // #FF9500

    /// Adjust brightness (and optionally saturation) via HSB — used to derive
    /// accent shades from a single reseller color.
    func adjusted(brightness bScale: CGFloat, saturation sScale: CGFloat = 1) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &al) else { return self }
        return Color(hue: Double(h), saturation: Double(min(1, s * sScale)),
                     brightness: Double(min(1, b * bScale)), opacity: Double(al))
    }

    // Hex initializer
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var val: UInt64 = 0
        Scanner(string: h).scanHexInt64(&val)
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}

// MARK: - Gradient System
struct S8KGradient {
    static var gold: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .init(hex: "F2FFCC"), location: 0.0),
                .init(color: .s8kGoldHigh,         location: 0.22),
                .init(color: .s8kGoldMid,           location: 0.62),
                .init(color: .s8kGoldDeep,          location: 1.0),
            ],
            startPoint: .topLeading,
            endPoint:   .bottomTrailing
        )
    }
    static var goldFlat: LinearGradient {
        LinearGradient(colors: [.s8kGoldHigh, .s8kGoldMid], startPoint: .leading, endPoint: .trailing)
    }
    static var goldVertical: LinearGradient {
        LinearGradient(colors: [.s8kGoldHigh, .s8kGoldLow], startPoint: .top, endPoint: .bottom)
    }
    static var backgroundFade: LinearGradient {
        LinearGradient(colors: [.s8kBlack, .clear], startPoint: .bottom, endPoint: .top)
    }
}

// MARK: - Typography
struct S8KFont {
    static let display    = Font.system(size: 34, weight: .black)
    static let title1     = Font.system(size: 28, weight: .heavy)
    static let title2     = Font.system(size: 22, weight: .bold)
    static let title3     = Font.system(size: 18, weight: .bold)
    static let headline   = Font.system(size: 15, weight: .semibold)
    static let body       = Font.system(size: 15, weight: .regular)
    /// Text INPUT only (S8KTextField). 16pt is Apple's default input size — anything
    /// smaller is the size iOS treats as "needs zooming" and reads cheap on a form.
    static let field      = Font.system(size: 16, weight: .regular)
    static let callout    = Font.system(size: 14, weight: .regular)
    static let subhead    = Font.system(size: 13, weight: .semibold)
    static let footnote   = Font.system(size: 12, weight: .regular)
    static let caption1   = Font.system(size: 11, weight: .medium)
    static let caption2   = Font.system(size: 10, weight: .semibold)
    static let caption3   = Font.system(size: 9,  weight: .bold)
    static let mono       = Font.system(size: 12, weight: .medium, design: .monospaced)
}

// MARK: - Spacing
enum S8KSpace {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 24
    static let h:   CGFloat = 32
    static let hh:  CGFloat = 48
}

// MARK: - Radius
// BLANK TV — Editorial language: crisper, more geometric corners than the
// soft/cinematic reference. Tighter radii read as "modern editorial", not
// "rounded media player".
enum S8KRadius {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 7
    static let md:   CGFloat = 10
    static let lg:   CGFloat = 13
    static let xl:   CGFloat = 16
    static let xxl:  CGFloat = 22
    static let pill: CGFloat = 9999
}

// MARK: - App Theme (Remote Controlled)
@MainActor
final class AppTheme: ObservableObject {
    static let shared = AppTheme()
    private init() { restoreBrand(); loadCached() }

    @Published var primaryColor: Color   = .s8kGoldMid
    @Published var accentColor:  Color   = .s8kGoldHigh
    @Published var serverName:   String  = S8KBrand.name
    @Published var logoURL:      String? = nil
    @Published var isCustom:     Bool    = false
    /// Bumped whenever the active BRAND palette (colors) changes → the root uses
    /// it as an `.id` so the whole app re-renders and the computed Color tokens
    /// pick up the new `BrandTheme.active`.
    @Published var brandTick:    Int     = 0

    func apply(_ theme: ThemeConfig) {
        withAnimation(.easeInOut(duration: 0.3)) {
            primaryColor = Color(hex: theme.primaryColor)
            accentColor  = Color(hex: theme.accentColor)
            serverName   = theme.serverName
            logoURL      = theme.logoURL
            isCustom     = true
        }
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: "s8k.theme.cache")
        }
    }

    func reset() {
        withAnimation(.easeInOut(duration: 0.3)) {
            primaryColor = .s8kGoldMid
            accentColor  = .s8kGoldHigh
            serverName   = S8KBrand.name
            logoURL      = nil
            isCustom     = false
        }
    }

    /// The accent hex currently driving the palette ("" = default BLANK TV).
    private var appliedBrandHex: String = ""

    /// Re-skin the WHOLE app with a reseller's accent color (nil/empty → default
    /// BLANK TV palette). IDEMPOTENT — does nothing if the color is unchanged, so
    /// it is safe to call on every activation check(). Persists via Store.brandColor;
    /// bumps brandTick so the root rebuilds and every `s8k*` token re-resolves.
    func applyBrandTheme(hex: String?) {
        let clean = (hex ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard clean != appliedBrandHex else { return }
        appliedBrandHex = clean
        withAnimation(.easeInOut(duration: 0.3)) {
            BrandTheme.active = clean.isEmpty ? .blankGreen : .fromAccent(clean)
            brandTick += 1
        }
    }

    /// Restore the reseller palette at launch (before the UI builds) from the
    /// persisted Store.brandColor, so a branded device opens already re-skinned.
    private func restoreBrand() {
        let hex = (Store.shared.brandColor ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if !hex.isEmpty { BrandTheme.active = .fromAccent(hex); appliedBrandHex = hex }
    }

    private func loadCached() {
        guard let data = UserDefaults.standard.data(forKey: "s8k.theme.cache"),
              let theme = try? JSONDecoder().decode(ThemeConfig.self, from: data) else { return }
        primaryColor = Color(hex: theme.primaryColor)
        accentColor  = Color(hex: theme.accentColor)
        serverName   = theme.serverName
        logoURL      = theme.logoURL
        isCustom     = true
    }

    var dynamicGold: LinearGradient {
        LinearGradient(colors: [accentColor, primaryColor], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Button Styles
struct S8KButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Gold Primary Button
struct GoldButton: View {
    let title: String
    var icon:      String?  = nil
    var isLoading: Bool     = false
    var isDisabled: Bool    = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // ZStack, not an if/else: swapping the label for the spinner changed the
            // button's intrinsic content, so a wrapped (long Arabic) label collapsed the
            // row back to 52pt the moment you tapped submit — the page jumped under the
            // user's thumb. Both live here and cross-fade instead.
            ZStack {
                HStack(spacing: 8) {
                    if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        // Without these, long labels TRUNCATE — "تفعيل الرقابة الأبوية",
                        // "Añade tu primera suscripción" already did, at 13 call sites.
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().progressViewStyle(.circular).tint(S8KBrand.accentInk).scaleEffect(0.85)
                }
            }
            // Deep-green ink (not pure black) so the CTA re-skins with BrandTheme.
            // Disabled ink is WHITE at 45%: the old black-on-white@0.15 was 1.6:1 —
            // an unreadable empty slab, and that is the button's DEFAULT state on the
            // login gateway (disabled until a username and password are typed).
            .foregroundColor(isDisabled ? Color.white.opacity(0.45) : S8KBrand.accentInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isDisabled ? AnyShapeStyle(Color.white.opacity(0.10))
                                   : AnyShapeStyle(Color.s8kGoldHigh))   // FLAT, not a gradient
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
            // A neutral elevation shadow — the app's standard recipe — instead of a
            // coloured halo. The glow was the one ornament that read as "gold luxury",
            // and over the gateway's animated poster wall it cost an offscreen pass.
            .shadow(color: .black.opacity(isDisabled ? 0 : 0.35), radius: 18, y: 8)
        }
        .disabled(isLoading || isDisabled)
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: - Outline Button
struct OutlineButton: View {
    let title: String
    var icon:  String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(S8KFont.callout.weight(.semibold))
            }
            .foregroundColor(.s8kGoldMid)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.clear)
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.md)
                .strokeBorder(Color.s8kGoldHigh.opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: - Text Field
struct S8KTextField: View {
    let placeholder: String
    let icon: String
    @Binding var text: String
    var isSecure: Bool = false
    var ltr: Bool = false
    // Input behavior (defaults preserve prior behavior for normal text fields).
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var disableAutocorrect: Bool = false
    var capitalization: TextInputAutocapitalization = .sentences

    @State private var visible = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(focused ? .s8kGoldHigh : .s8kTextDisabled)
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.2), value: focused)

            Group {
                if isSecure && !visible {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            // 16pt: Apple's default input size. Smaller reads as cheap on a login card
            // and is the size iOS treats as "needs zooming".
            .font(S8KFont.field)
            .foregroundColor(.s8kTextPrimary)
            .tint(.s8kGoldHigh)          // brand caret + selection handles
            .environment(\.layoutDirection, ltr ? .leftToRight : .rightToLeft)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .autocorrectionDisabled(disableAutocorrect)
            .textInputAutocapitalization(capitalization)
            .focused($focused)
            // Claim the row's full width so the NATIVE hit box (and caret placement)
            // covers the whole field, not just the width of the typed glyphs.
            .frame(maxWidth: .infinity)

            if isSecure {
                // 44×44 — the HIG minimum. This was a bare 14pt image (~14pt target):
                // a near-miss hit the ROW's tap gesture and just focused the field, so
                // the control read as broken. Outline glyph, not `.fill`: a filled eye
                // reads as "currently revealed" even when the password is hidden.
                // Re-assert focus: SecureField and TextField are DIFFERENT view types, so
                // toggling destroys one and creates the other — the first responder dies
                // and the keyboard drops mid-typing. The re-focus must happen on the NEXT
                // runloop: written in the same transaction it would still be bound to the
                // outgoing field and get dropped.
                Button(action: { visible.toggle(); DispatchQueue.main.async { focused = true } }) {
                    Image(systemName: visible ? "eye.slash" : "eye")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(visible ? .s8kGoldHigh : .s8kTextDisabled)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(visible ? L("a11y.hide_password") : L("a11y.show_password"))
            }
        }
        .padding(.horizontal, S8KSpace.lg)
        // 4, not 8: 44 (reveal button) + 4 + 4 = exactly the 52pt row height, so adding a
        // real tap target for the eye did not make every form taller.
        .padding(.vertical, 4)
        // minHeight, NOT a fixed height: keeps the 52pt tap target on every device
        // while letting the row GROW instead of clipping the text at large accessibility
        // type sizes. Used by every login / add-playlist form in the app.
        .frame(minHeight: 52)
        // FLAT surface, not glass. Over the gateway's animated poster wall a material had
        // to re-blur its backdrop every frame and its tone shifted as posters slid past;
        // on every other screen it was blurring solid black — pure cost, zero effect.
        // (It also drops the iOS-17 glass fallback's decorative overlays, which were the
        // original cause of the "field won't take the first tap" bug.)
        .background(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
            .fill(Color.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                .strokeBorder(focused ? Color.s8kGoldHigh.opacity(0.85) : Color.white.opacity(0.12),
                              lineWidth: focused ? 1.5 : 1)
                .allowsHitTesting(false)   // purely decorative border — never intercept taps
        )
        // THE fix for "the fields feel sticky / don't respond to touch": a SwiftUI
        // TextField's hit area is only its intrinsic text box — the icon, the padding
        // and the extra height from `minHeight: 52` were all DEAD space. These two lines
        // make the entire 52pt row a single tap target that focuses the field.
        // (Order matters: after the background/overlay, before the tap gesture. The eye
        // Button is a child, so it still wins its own taps.)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        // (no focus shadow: a coloured glow at 12% was invisible on a dark screen, cost
        //  an offscreen render pass over the moving posters, and was pure ornament.)
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

// MARK: - Filter Pill
// BLANK TV — Editorial: crisp rectangular chip (not a soft capsule). Solid lime
// fill when active, quiet elevated surface + hairline when inactive.
struct FilterPill: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(S8KFont.caption1.weight(.bold))
                .foregroundColor(isOn ? .s8kBlack : .s8kTextSecondary)
                .padding(.horizontal, S8KSpace.lg)
                .padding(.vertical, S8KSpace.sm)
                .background(
                    Group {
                        if isOn {
                            LinearGradient(colors: [.s8kGoldHigh, .s8kGoldMid], startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.s8kElevated
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: S8KRadius.sm, style: .continuous)
                        .strokeBorder(isOn ? Color.clear : Color.s8kBorder, lineWidth: 1)
                )
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: - Section Header
// BLANK TV — Editorial: a heavy bold title with a short lime underline block
// beneath it (magazine-style), replacing the reference's thin left bar.
struct SectionHeader: View {
    let title: String
    var count: Int?       = nil
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundColor(.s8kTextPrimary)

                if let count {
                    Text("\(count)")
                        .font(S8KFont.caption3)
                        .foregroundColor(.s8kGoldHigh)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.s8kGoldHigh.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Spacer()
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text(L("common.all")).font(S8KFont.caption1.weight(.bold))
                            Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.s8kGoldHigh)
                    }
                }
            }
            RoundedRectangle(cornerRadius: 1.5)
                .fill(S8KGradient.goldFlat)
                .frame(width: 32, height: 3)
                .shadow(color: .s8kGoldHigh.opacity(0.5), radius: 4)
        }
        .padding(.horizontal, S8KSpace.xl)
        .padding(.bottom, S8KSpace.md)
    }
}

// MARK: - Image cache (memory + disk) with downsampling
// Replaces raw AsyncImage, which re-downloaded and full-res-decoded every
// poster on every scroll pass — the dominant source of browsing jank. Images
// are cached in memory (NSCache) and on disk (URLCache), and downsampled to
// the cell's point size so a 4K poster never decodes into a 110pt thumbnail.
// @unchecked Sendable: all mutable state (`tasks`/`tokenSeq`) is guarded by
// `tasksLock`, and NSCache/URLSession are themselves thread-safe — so this
// singleton is safe to touch from the detached fetch tasks.
final class S8KImageCache: @unchecked Sendable {
    static let shared = S8KImageCache()
    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession

    init() {
        memory.countLimit = 240
        memory.totalCostLimit = 96 * 1024 * 1024   // ~96 MB of decoded bitmaps
        hashMemory.countLimit = 512                // ThumbHash placeholders are ~32px
        hashMemory.totalCostLimit = 8 * 1024 * 1024
        let disk = URLCache(memoryCapacity: 16 * 1024 * 1024,
                            diskCapacity: 256 * 1024 * 1024)
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = disk
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }

    func cached(_ key: String) -> UIImage? { memory.object(forKey: key as NSString) }

    /// One in-flight fetch Task per key — BOTH the on-screen path (`S8KImage`)
    /// and `prefetch` go through `load`, so concurrent requests for the same
    /// image coalesce into a single network+decode instead of racing/duplicating.
    /// A per-entry token ensures the finishing task only clears its OWN slot
    /// (never a newer task started for the same key after it finished).
    private var tasks: [String: (token: Int, task: Task<UIImage?, Never>)] = [:]
    private var tokenSeq = 0
    private let tasksLock = NSLock()

    func load(_ url: URL, key: String, maxPixel: CGFloat) async -> UIImage? {
        if let img = memory.object(forKey: key as NSString) { return img }
        return await claimTask(key: key, url: url, maxPixel: maxPixel).value
    }

    // Claim/clear run on a SYNC method (NSLock isn't usable from async contexts);
    // the actual network+decode runs in `fetch` which never touches the lock.
    private func claimTask(key: String, url: URL, maxPixel: CGFloat) -> Task<UIImage?, Never> {
        tasksLock.lock(); defer { tasksLock.unlock() }
        if let existing = tasks[key] { return existing.task }
        tokenSeq &+= 1
        let myToken = tokenSeq
        let t = Task.detached(priority: .utility) { [weak self] () -> UIImage? in
            guard let self else { return nil }
            let img = await self.fetch(url: url, key: key, maxPixel: maxPixel)
            self.clearTask(key, token: myToken)   // token-guarded; never clears a newer task
            return img
        }
        tasks[key] = (myToken, t)
        return t
    }
    private func clearTask(_ key: String, token: Int) {
        tasksLock.lock(); defer { tasksLock.unlock() }
        if tasks[key]?.token == token { tasks[key] = nil }
    }
    private func fetch(url: URL, key: String, maxPixel: CGFloat) async -> UIImage? {
        guard let (data, _) = try? await session.data(from: url),
              let down = Self.downsample(data: data, maxPixel: maxPixel) ?? UIImage(data: data)
        else { return nil }
        // Decode into the renderer's format NOW, off the main thread, so
        // scrolling never pays a decode cost on-screen (iOS 15+).
        let img = await down.byPreparingForDisplay() ?? down
        memory.setObject(img, forKey: key as NSString, cost: Int(img.size.width * img.size.height * 4))
        // Encode a ThumbHash for this URL once (idempotent, off-main) so a future
        // cold start can paint an instant blurred placeholder before it re-downloads.
        Self.ensureThumbHash(key: key, image: img)
        return img
    }

    /// Memo for decoded ThumbHash placeholders. Every recycled cell used to hit
    /// SQLite and re-decode the same hash on every appearance. BOTH outcomes are
    /// memoised: the miss is the common case on a catalogue that has never been
    /// scrolled, and without a negative memo each reuse pays a query that can
    /// only ever return nothing.
    private let hashMemory = NSCache<NSString, UIImage>()
    private var hashMisses = Set<String>()
    private let hashLock = NSLock()

    /// Decode the cached ThumbHash for `key` into a tiny blurred placeholder image.
    /// nil when nothing is stored. Cheap; call OFF the main thread.
    func thumbHashImage(_ key: String) -> UIImage? {
        let k = key as NSString
        if let hit = hashMemory.object(forKey: k) { return hit }
        // The lock is held ACROSS the database read, not just around the Set. If it
        // weren't, `forgetHashMiss` could land between the read and the insert, its
        // `remove` would be a no-op, and the stale miss would suppress that key's
        // placeholder for the rest of the process. The read is ~1 ms and always
        // off-main, and it happens at most once per key.
        hashLock.lock()
        defer { hashLock.unlock() }
        if hashMisses.contains(key) { return nil }
        guard let data = CatalogDB.imageHash(key), data.count >= 5 else {
            hashMisses.insert(key)
            return nil
        }
        let img = thumbHashToImage(hash: data)      // non-optional
        hashMemory.setObject(img, forKey: k, cost: Int(img.size.width * img.size.height * 4))
        return img
    }

    /// Drop a negative memo once a hash actually lands for that key, so the
    /// placeholder becomes available without waiting for a relaunch.
    fileprivate func forgetHashMiss(_ key: String) {
        hashLock.lock(); hashMisses.remove(key); hashLock.unlock()
    }

    /// Encode + persist a ThumbHash for `key` once (idempotent). The heavy encode
    /// runs at background priority so it never delays the on-screen image.
    private static func ensureThumbHash(key: String, image: UIImage) {
        Task.detached(priority: .background) {
            // The existence check is a SQLite read — run it INSIDE the background
            // task. On the caller it sat on `fetch`'s return path, so every single
            // image paid a database round trip before it could be handed back.
            guard !CatalogDB.hasImageHash(key) else { return }
            let hash = imageToThumbHash(image: image)
            if !hash.isEmpty {
                CatalogDB.saveImageHash(key, hash)
                S8KImageCache.shared.forgetHashMiss(key)
            }
        }
    }

    /// Warm the cache for posters about to scroll on-screen. Callers pass a
    /// BOUNDED window (e.g. the next ~30 items) — never the whole catalog.
    /// Skips anything already cached; in-flight de-dup is handled by `load`.
    func prefetch(_ urls: [String], maxPixel: CGFloat) {
        for u in urls {
            if memory.object(forKey: u as NSString) != nil { continue }
            guard let url = URL(string: u) else { continue }
            Task.detached(priority: .utility) { [weak self] in
                _ = await self?.load(url, key: u, maxPixel: maxPixel)
            }
        }
    }

    private static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        // `maxPixel` is already the target PIXEL cap (≈800) — generous for the
        // small thumbnails used here. Don't multiply by UIScreen.main.scale: that
        // reads a main-actor-only UIKit API off-thread AND inflates bitmaps to
        // ~2400px, wasting the memory budget.
        let pixel = max(maxPixel, 1)
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Async Image (cached + downsampled)
// No GeometryReader (it forced an extra layout pass per image and made large
// grids/lists — and the whole app — sluggish). Fixed downsample size instead;
// callers already constrain with .frame.
struct S8KImage: View {
    let url: String?
    var placeholder: String = "photo"
    var contentMode: ContentMode = .fill
    /// Max decoded edge in pixels. Default suits posters/backdrops; small cells
    /// (channel logos, chips, watermarks) should pass a much smaller value so a
    /// long list doesn't decode 800px bitmaps for 46pt tiles — that oversampling
    /// blew the image cache (~38 images at 800px) and caused re-decode flicker
    /// while scrolling. Cost scales with maxPixel², so 150 vs 800 is ~28× cheaper.
    var maxPixel: CGFloat = 800

    @State private var image: UIImage?
    @State private var placeholderImage: UIImage?
    @State private var failed = false
    /// The url `image` actually belongs to. `.task(id:)` also refires on plain
    /// re-appearance (sheet dismiss, tab return), so "did the url change?" cannot
    /// be inferred from the task alone.
    @State private var shownURL: String?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if let placeholderImage {
                // Instant ThumbHash placeholder — blurred but structure-preserving.
                Image(uiImage: placeholderImage).resizable().aspectRatio(contentMode: contentMode)
            } else if url == nil || failed {
                placeholderView
            } else {
                shimmer
            }
        }
        .clipped()
        .task(id: url) { await load() }   // reloads on cell reuse, cancels on disappear
    }

    private func load() async {
        guard let u = url, let imageURL = URL(string: u) else {
            image = nil; placeholderImage = nil; shownURL = nil; failed = false; return
        }
        failed = false
        // Warm hit: swap straight to the right bitmap, no flash, no await.
        if let hit = S8KImageCache.shared.cached(u) {
            image = hit; placeholderImage = nil; shownURL = u; return
        }
        // Cache MISS on a RECYCLED cell: `image` still holds the PREVIOUS url's
        // bitmap, and every path from here on awaits — so without this the wrong
        // poster stayed on screen for the whole download. That is the "wrong
        // artwork while scrolling fast" report. Gated on `shownURL` so a plain
        // re-appearance with an evicted bitmap doesn't blank a correct image.
        if shownURL != u { image = nil; placeholderImage = nil }
        // Start the download FIRST and decode the ThumbHash while it is in flight.
        // Awaiting the hash first delayed every real image by a database read plus
        // a decode, for a placeholder that is thrown away moments later.
        // `mp` is a local: an `async let` child task is nonisolated and must not
        // read a main-actor-isolated stored property of this View.
        let mp = maxPixel
        async let downloaded = S8KImageCache.shared.load(imageURL, key: u, maxPixel: mp)
        let ph = await Task.detached(priority: .utility) { S8KImageCache.shared.thumbHashImage(u) }.value
        guard !Task.isCancelled else { return }
        if image == nil { placeholderImage = ph }
        let img = await downloaded
        guard !Task.isCancelled else { return }
        if let img {
            withAnimation(.easeOut(duration: 0.25)) { image = img }
            shownURL = u
        } else { failed = true }
    }

    private var placeholderView: some View {
        ZStack {
            Color.s8kElevated
            Image(systemName: placeholder)
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundColor(.s8kTextDisabled)
        }
    }

    private var shimmer: some View {
        Color.s8kElevated
            .overlay(
                LinearGradient(
                    colors: [Color.clear, Color.white.opacity(0.06), Color.clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
    }
}

// MARK: - Progress bar (geometry-free)
// A leading-anchored `scaleEffect` fills the track WITHOUT a GeometryReader.
// The old GeometryReader-per-cell forced an extra layout pass on every visible
// Continue-Watching / history / episode / EPG cell — real cost when dozens are
// on screen. A transform is far cheaper than a measurement pass; the rounded
// ends come from a Capsule clip. `fraction` is clamped to 0…1.
struct S8KProgressBar<F: BinaryFloatingPoint>: View {
    var fraction: F                                  // accepts CGFloat / Double / Float
    var track: Color = Color.white.opacity(0.12)
    var height: CGFloat = 3

    var body: some View {
        let f = CGFloat(min(1, max(0, Double(fraction))))
        Capsule()
            .fill(track)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(S8KGradient.goldFlat)
                    .scaleEffect(x: f, anchor: .leading)
            }
            .clipShape(Capsule())
            .frame(height: height)
    }
}

// MARK: - Skeleton shimmer (loading placeholders)
// A sweeping highlight for skeleton cards while content loads — the premium
// "the app is working, not frozen" cue. Reusable via `.s8kShimmer()`.
struct S8KShimmer: ViewModifier {
    @State private var animate = false
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.22), .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: animate ? geo.size.width * 1.1 : -geo.size.width * 0.7)
                }
                .allowsHitTesting(false)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}
extension View {
    /// Apply a looping shimmer sweep — use on skeleton placeholder blocks.
    func s8kShimmer() -> some View { modifier(S8KShimmer()) }
}

/// A single skeleton placeholder block (elevated fill + shimmer). Sized by caller.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = S8KRadius.md
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // white@0.13, NOT s8kElevated: the brand base is a deep GREEN, so an
            // `elevated` fill measured only 1.35:1 against the page — the skeleton was
            // invisible on a real screen, which is why loading read as `a plain page`.
            // A neutral white wash is ~3.3:1 and works for every BrandTheme.
            .fill(Color.white.opacity(0.13))
            .s8kShimmer()
    }
}

// A page-shaped skeleton (category chips + poster grid) for Movies/Series while the
// catalog loads — the big-app "the page is drawn, filling in" feel instead of a
// centered spinner + "loading…" text. ONE shimmer sweep over the whole page (not
// per-cell) keeps it cheap. Plain fills for cells (no per-cell GeometryReader).
struct S8KPosterGridSkeleton: View {
    // The skeleton MUST use the same adaptive column rule as the real grid
    // (ContentViews: .adaptive(minimum: regular ? 168 : 116)) — a fixed 3 columns
    // produced ~440pt "posters" on an iPad and looked nothing like what follows.
    @Environment(\.horizontalSizeClass) private var hSize
    private var cols: [GridItem] { [GridItem(.adaptive(minimum: hSize == .regular ? 168 : 116), spacing: 14)] }
    private func cell(_ r: CGFloat = S8KRadius.md) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.white.opacity(0.13))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in cell(S8KRadius.sm).frame(width: 78, height: 30) }
            }
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(0..<12, id: \.self) { _ in cell().aspectRatio(2.0 / 3.0, contentMode: .fit) }
            }
        }
        .padding(.horizontal, S8KSpace.lg).padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .s8kShimmer()
        .background(Color.s8kBlack)
    }
}

// A list-shaped skeleton (logo + two text bars per row) for the Live channel list.
struct S8KListSkeleton: View {
    private func cell(_ r: CGFloat = S8KRadius.sm) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color.white.opacity(0.13))
    }
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<10, id: \.self) { _ in
                HStack(spacing: 12) {
                    cell(S8KRadius.md).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 8) {
                        cell().frame(width: 170, height: 12)
                        cell().frame(width: 92, height: 10)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, S8KSpace.lg).padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .s8kShimmer()
        .background(Color.s8kBlack)
    }
}

// MARK: - Watermark (white-label aware)
// Uses the reseller's logo + name when a brand is active, otherwise the bundled
// BLANK TV mark — so a branded device shows the RESELLER's watermark on video.
struct S8KWatermark: View {
    var opacity: Double = 0.15
    var alignment: Alignment = .bottomTrailing

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 6) {
                // Reseller logo (remote) when set, else the bundled logo.
                if let logo = BrandKit.logoURL {
                    S8KImage(url: logo, placeholder: "play.tv.fill", maxPixel: 120)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(S8KBrand.logoAsset).resizable().scaledToFit().frame(width: 22, height: 22)
                }
                Text(BrandKit.customName ?? S8KBrand.name)
                    .font(S8KFont.caption1.weight(.black))
                    .tracking(1.5)
                    .foregroundColor(.s8kGoldHigh)
                    .lineLimit(1)
            }
            .opacity(opacity)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Brand wordmark (premium "BLANK TV")
// MARK: - Brand kit (per-reseller white-label: name / logo / accent)
/// THE IDENTITY. Everything that makes this app *this* brand is decided here and
/// nowhere else, so changing identity is editing one type rather than hunting through
/// views. `BrandTheme` already owned the palette; this owns the rest of it.
///
/// RULE: never write the app's name into a sentence. Put a `%@` in the localised
/// string and inject `S8KBrand.name`, or the name becomes unchangeable in five
/// languages at once — which is exactly what it was.
enum S8KBrand {
    /// The product name as the user reads it.
    static let name = "Blank Prime"
    /// The short form, for the wordmark and other tight places.
    static let shortName = "Blank"
    /// The bundled logo asset. Swapping identity = replacing the file under this name.
    static let logoAsset = "Logo"
    // NOTE: there is deliberately no `palette` here. The palette's home is
    // `BrandTheme.active`, which the reseller path mutates at runtime; a second copy
    // pinned to `.blankGreen` would only invite ink to be computed against a colour
    // the button is not actually drawn on.

    /// Ink for text and glyphs drawn ON the accent colour.
    ///
    /// COMPUTED, never fixed. It was a hard-coded black, which is right for this app's
    /// lime accent and silently wrong for a dark one — the first buyer who picked a
    /// deep blue would have shipped buttons whose labels were invisible, and nothing
    /// in the code would have complained. Derived from luminance, a rebrand cannot
    /// produce an unreadable button.
    static var accentInk: Color {
        // `.s8kBlack`, NOT `.black`: s8kBlack is BrandTheme.active.base, a deep brand
        // tone rather than #000000, and that was a deliberate choice — the CTA is meant
        // to re-skin with the palette. What was missing is only the white branch, for
        // an accent too dark to read a deep ink on.
        BrandTheme.active.accentHigh.s8kLuminance > 0.55 ? .s8kBlack : .white
    }
}

extension Color {
    /// Relative luminance (Rec. 709). Used to pick legible ink for any accent.
    var s8kLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // Guarded like `adjusted(brightness:)` below, and failing toward 1 (deep ink) —
        // the app's status quo. An unguarded read would leave r/g/b at 0 on failure and
        // silently turn every button's label white.
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return 1 }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

enum BrandKit {
    /// Reseller brand name, or nil for default BLANK TV.
    static var customName: String? {
        let n = (Store.shared.brandName ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? nil : n
    }
    static var logoURL: String? {
        let l = (Store.shared.brandLogo ?? "").trimmingCharacters(in: .whitespaces)
        return l.isEmpty ? nil : l
    }
}

/// The brand logo: the reseller's remote logo if set, otherwise the bundled one.
struct BrandLogo: View {
    var size: CGFloat
    var body: some View {
        if let url = BrandKit.logoURL {
            S8KImage(url: url, placeholder: "play.tv.fill")
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(S8KBrand.logoAsset).resizable().scaledToFit().frame(width: size, height: size)
        }
    }
}

struct S8KWordmark: View {
    var size: CGFloat = 22
    var body: some View {
        if let brand = BrandKit.customName {
            Text(brand)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .tracking(size * 0.05)
                .foregroundColor(.s8kGoldHigh)   // solid, not a gradient (see below)
                .lineLimit(1).minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        } else {
            HStack(spacing: size * 0.24) {
                Text(S8KBrand.shortName)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .tracking(size * 0.10)
                    .foregroundColor(.s8kTextPrimary)
                Text("Prime")
                    .font(.system(size: size * 1.02, weight: .heavy, design: .rounded))
                    .tracking(size * 0.04)
                    // SOLID accent, not a gradient. A 2-stop sweep across ~40pt of glyphs
                    // reads as mud at the 17–18pt sizes used in the Home top bar, and a
                    // metallic sweep is the exact ornament we are moving away from.
                    // (The neutral drop shadow STAYS — on the gateway the wordmark sits
                    //  where posters are still visible through the scrim, and white text
                    //  over moving artwork shimmers without it.)
                    .foregroundColor(.s8kGoldHigh)
            }
            // Keep the wordmark on ONE line, scaling down to fit rather than wrapping
            // to two lines (iPhone 11) or overflowing the nav bar's action buttons on
            // narrow phones (iPhone SE/8, 320–375pt). scale-to-fit > fixed width.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        }
    }
}

// MARK: - Gold Divider
struct GoldDivider: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, .s8kGoldMid.opacity(0.25), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var message: String = L("loading.generic")
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: S8KSpace.lg) {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(
                    AngularGradient(
                        colors: [.s8kGoldHigh, .s8kGoldMid, .s8kGoldHigh],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            // Big-app minimal (owner spec): the spinner alone — no "loading…" text.
            // `message` stays for source-compat with existing call sites (unused).
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.s8kBlack)
    }
}

// MARK: - Error View
struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: S8KSpace.xxl) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.s8kTextDisabled)

            Text(message)
                .font(S8KFont.subhead)
                .foregroundColor(.s8kTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, S8KSpace.h)

            GoldButton(title: L("common.retry"), icon: "arrow.clockwise", action: retry)
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.s8kBlack)
    }
}

// MARK: - Empty State
struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: S8KSpace.lg) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundColor(.s8kTextDisabled)
            Text(title).font(S8KFont.headline).foregroundColor(.s8kTextSecondary)
            Text(subtitle).font(S8KFont.footnote).foregroundColor(.s8kTextTertiary)
                .multilineTextAlignment(.center).padding(.horizontal, S8KSpace.h)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

// MARK: - Content Card (Portrait)
struct ContentCard: View {
    let title: String
    var subtitle: String?  = nil
    var imageURL: String?  = nil
    var badgeText: String? = nil
    var progress: Double?  = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 7) {
                // Image container
                ZStack(alignment: .topTrailing) {
                    S8KImage(url: imageURL, placeholder: "film")
                        .frame(width: 118, height: 166)
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: S8KRadius.md)
                                .strokeBorder(Color.s8kBorder, lineWidth: 1)
                        )

                    // Badge
                    if let badge = badgeText {
                        Text(badge)
                            .font(S8KFont.caption3)
                            .foregroundColor(.black)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(S8KGradient.goldFlat)
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.xs))
                            .padding(7)
                    }

                    // Progress bar
                    if let p = progress, p > 0 {
                        VStack {
                            Spacer()
                            S8KProgressBar(fraction: p, track: Color.white.opacity(0.12))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
                    }
                }
                .frame(width: 118, height: 166)

                // Title
                Text(title)
                    .font(S8KFont.caption1.weight(.semibold))
                    .foregroundColor(.s8kTextPrimary)
                    .lineLimit(1)
                    .frame(width: 118, alignment: .trailing)

                // Subtitle
                if let sub = subtitle {
                    Text(sub)
                        .font(S8KFont.caption2)
                        .foregroundColor(.s8kTextTertiary)
                        .lineLimit(1)
                        .frame(width: 118, alignment: .trailing)
                }
            }
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: - Channel Chip (Live)
struct ChannelChip: View {
    let name: String
    let logoURL: String?
    let isLive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    S8KImage(url: logoURL, placeholder: "antenna.radiowaves.left.and.right", maxPixel: 240)
                        .frame(width: 64, height: 64)
                        .background(Color.s8kElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Color.s8kBorder, lineWidth: 1)
                        )

                    if isLive {
                        Circle()
                            .fill(Color.s8kRed)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.s8kBlack, lineWidth: 2))
                            .shadow(color: .s8kRed.opacity(0.6), radius: 3)
                            .offset(x: 2, y: -2)
                    }
                }

                Text(name)
                    .font(S8KFont.caption2)
                    .foregroundColor(.s8kTextTertiary)
                    .lineLimit(1)
                    .frame(width: 72)
            }
        }
        .buttonStyle(S8KButtonStyle())
    }
}

// MARK: - Tab Bar
enum AppTab: String, CaseIterable, Identifiable {
    // Order places `home` in the CENTER of the 5 tabs (prominent raised button).
    case live, movies, home, series, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:     return L("tab.home")
        case .live:     return L("tab.live")
        case .movies:   return L("tab.movies")
        case .series:   return L("tab.series")
        case .settings: return L("tab.settings")
        }
    }
    var icon: String {
        switch self {
        case .home:     return "house"
        case .live:     return "dot.radiowaves.left.and.right"
        case .movies:   return "film"
        case .series:   return "tv"
        case .settings: return "gearshape"
        }
    }
    var activeIcon: String {
        switch self {
        case .home:     return "house.fill"
        case .live:     return "dot.radiowaves.left.and.right"
        case .movies:   return "film.fill"
        case .series:   return "tv.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Floating tab-bar visibility (collapse on scroll-down / expand on scroll-up|tap)
// A tiny shared model the bar OBSERVES and the scroll views WRITE to. Because our
// AppTabBar is a CUSTOM overlay (the system TabView bar is hidden), iOS 26's native
// `.tabBarMinimizeBehavior` does not apply — so we reproduce it: a coarse scroll-
// direction signal flips one Bool, rate-limited with hysteresis so it never strobes.
// Only AppTabBar reads `minimized`, so a flip re-renders the bar alone (not content).
@MainActor
final class BarVisibility: ObservableObject {
    static let shared = BarVisibility()
    private init() {}

    /// The corner menu is COLLAPSED by default (a home puck); it opens ONLY on a tap
    /// of the puck and closes on scroll / item-select. (Owner spec.)
    @Published var minimized = true
    /// True once the page is scrolled past the top — drives the Home top bar's
    /// transparent→glass transition (logo + profile stay clear on the glass).
    @Published var scrolled = false
    private var lastOffset: CGFloat = 0

    /// Feed the current vertical content offset (already normalised to "distance
    /// scrolled from rest" — see `reportsScrollToTabBar`).
    func report(offsetY newY: CGFloat) {
        // Top bar glass once scrolled past a small threshold.
        let s = newY > 30
        if s != scrolled { withAnimation(.easeInOut(duration: 0.25)) { scrolled = s } }
        // Any real scroll closes the menu (it only opens on a puck tap).
        let delta = newY - lastOffset
        lastOffset = newY
        if abs(delta) > 6 { collapse() }
    }

    /// Switching tabs must not look like a scroll. `lastOffset` and `scrolled` are
    /// single shared fields, so without this the NEXT page's first geometry report is
    /// compared against the PREVIOUS page's offset — an instant fake "scroll" that
    /// closed the menu (it only did so on Movies, the one page whose top bar is a
    /// safe-area inset and therefore rests at a non-zero offset) and left the Home top
    /// bar frosted at rest after scrolling any other tab.
    func pageChanged() {
        lastOffset = 0
        if scrolled { withAnimation(.easeInOut(duration: 0.2)) { scrolled = false } }
    }

    /// Tap the corner puck → open the menu leftward.
    func expand() {
        if minimized { withAnimation(.snappy(duration: 0.35, extraBounce: 0.06)) { minimized = false } }
    }
    /// Close back to the corner puck (scroll / select an item).
    func collapse() {
        if !minimized { withAnimation(.snappy(duration: 0.3)) { minimized = true } }
    }
}

extension View {
    /// Report a scroll view's vertical offset to the floating tab bar so it
    /// collapses on scroll-down and expands on scroll-up. iOS 18+ (a graceful
    /// no-op on iOS 17 — the bar simply stays expanded there).
    @ViewBuilder
    func reportsScrollToTabBar() -> some View {
        if #available(iOS 18.0, *) {
            // `contentOffset.y + contentInsets.top` = distance scrolled FROM REST.
            // Raw contentOffset is 0 on a plain ScrollView but ≈ −174 on a page whose
            // top bar is a `.safeAreaInset` (Movies), so the raw value made simply
            // OPENING that tab register as a 174pt scroll — which slammed the corner
            // menu shut the instant you pressed "Movies", and only there.
            self.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top }
                action: { _, newY in BarVisibility.shared.report(offsetY: newY) }
        } else {
            self
        }
    }
}

// BLANK TV — FLOATING CORNER MENU (Filmm-style). A compact circular glass puck is
// pinned to the PHYSICAL bottom-RIGHT corner; it EXPANDS LEFTWARD into a right-anchored
// pill of nav circles (5 sections + contextual Search) with a staggered spring reveal,
// and collapses back to the puck. Collapses automatically on scroll-DOWN, expands on
// scroll-UP or a tap of the puck. Physical-right anchoring is enforced with a forced
// `.leftToRight` layout so the puck never flips under Arabic RTL (research-backed).
struct AppTabBar: View {
    @Binding var selected: AppTab
    @ObservedObject private var vis = BarVisibility.shared
    @ObservedObject private var alerts = ActivationService.shared   // notification badge
    @ObservedObject private var router = AppRouter.shared           // global search state
    @Environment(\.horizontalSizeClass) private var hSize
    @FocusState private var searchFocused: Bool
    // Typing writes to a LOCAL draft (instant, no global re-render per keystroke);
    // the global query is committed on a short debounce so the per-keystroke
    // catalog filter can't stall the main thread and make typing lag.
    @State private var searchDraft = ""
    @State private var commitTask: Task<Void, Never>?
    // A SHARED, pre-warmed generator. These are structs, so a `let` here allocated a
    // brand-new generator on every body pass and the Taptic Engine was never warm —
    // making the first tap's feedback land ~100-200ms late or be dropped entirely,
    // which is precisely what "the button felt dead" means.
    private var haptic: UISelectionFeedbackGenerator { s8kSelectionHaptic }

    private func commitSearch(_ v: String) {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)   // debounce
            guard !Task.isCancelled else { return }
            router.searchText = v
        }
    }

    var body: some View {
        Group {
            if router.searchActive {
                // Search mode: the pill morphs into an in-place text field that
                // filters the active section live (owner spec — App-Store style,
                // expanding from the corner menu itself).
                searchField
                    .frame(maxWidth: hSize == .regular ? 560 : .infinity)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, S8KSpace.lg)
            } else if vis.minimized {
                // Collapsed: the HOME puck hugs the bottom-RIGHT corner.
                collapsedPuck
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
            } else {
                // Expanded: a FULL-WIDTH glass bar across the bottom (owner spec),
                // capped and RIGHT-anchored on iPad so it grows leftward out of the
                // corner the puck occupies. The cap used to be applied to the whole
                // Group — which also centred the COLLAPSED puck, leaving it floating
                // ~277pt in from the right edge of an iPad instead of in the corner.
                ExpandedNavBar(selected: $selected)
                    .frame(maxWidth: hSize == .regular ? 560 : .infinity)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, S8KSpace.lg)
            }
        }
        .padding(.bottom, 10)
        .environment(\.layoutDirection, .leftToRight)
        .animation(.snappy(duration: 0.3), value: router.searchActive)
    }

    // The morphed search field (glass capsule matching the menu pill): magnifier +
    // live text field (auto-focused) + clear + Cancel. Rises above the keyboard
    // automatically (bottom-anchored, respects the keyboard safe area).
    private var searchField: some View {
        // App-Store layout (owner's reference): a circular X (cancel) on the far
        // left + a rounded search pill on the right holding — RTL — the magnifier
        // (leading), the text, and a clear ⊗ (trailing). Sits at the bottom and
        // rises above the keyboard, exactly like the familiar App Store search.
        HStack(spacing: 10) {
            Button {
                haptic.selectionChanged()
                commitTask?.cancel()   // kill any pending debounce so a stale query can't
                searchDraft = ""       // re-filter the content after search is closed
                router.endSearch()
                searchFocused = false
                BarVisibility.shared.collapse()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.s8kTextSecondary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(S8KButtonStyle())
            .accessibilityLabel(L("common.close"))

            HStack(spacing: 9) {
                // Clear ⊗ on the LEFT, magnifier on the RIGHT (matches the Arabic
                // App Store, where the glyph sits at the leading/right edge).
                if !searchDraft.isEmpty {
                    Button {
                        searchDraft = ""; commitTask?.cancel(); router.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16)).foregroundColor(.s8kTextTertiary)
                    }
                    .buttonStyle(S8KButtonStyle())
                    .accessibilityLabel(L("common.close"))
                }
                TextField(searchPlaceholder, text: $searchDraft)
                    .focused($searchFocused)
                    .foregroundColor(.s8kTextPrimary)
                    .tint(.s8kGoldMid)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)              // Arabic reads right→left
                    .environment(\.layoutDirection, .rightToLeft)
                    .onChange(of: searchDraft) { _, v in commitSearch(v) }
                    .onSubmit { commitTask?.cancel(); router.searchText = searchDraft }
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.s8kTextSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .s8kGlass(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1).allowsHitTesting(false))
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
        .onAppear { searchDraft = router.searchText; searchFocused = true }
    }

    // Placeholder reflects the scope: the active section, or "all content" on Home.
    private var searchPlaceholder: String {
        switch router.searchScope {
        case .all:    return L("search.all")
        case .live:   return L("search.live")
        case .series: return L("search.series")
        case .movies: return L("search.movies")
        }
    }

    // Collapsed — the lime HOME puck in the corner (the persistent marker). Tap to
    // open the menu. A red (n) badge appears when there are unread notifications.
    private var collapsedPuck: some View {
        Button {
            haptic.selectionChanged()
            vis.expand()
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(S8KBrand.accentInk)
                .frame(width: 58, height: 58)
                .background(Circle().fill(S8KGradient.goldFlat))
                .overlay(Circle().strokeBorder(Color.s8kBlack.opacity(0.12), lineWidth: 2))
                .shadow(color: .s8kGoldHigh.opacity(0.45), radius: 12, y: 5)
                .overlay(alignment: .topTrailing) {
                    if alerts.unreadCount > 0 { notifBadge(alerts.unreadCount) }
                }
                .contentShape(Circle())   // solid hit target — taps never fall through
        }
        .buttonStyle(S8KButtonStyle())
        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
        .accessibilityLabel(L("tab.home"))
    }

    /// Map the active section → the default search scope. Home searches ALL
    /// content; each content tab scopes to itself (owner spec).
    static func scope(for tab: AppTab) -> SearchVM.SearchScope {
        switch tab {
        case .live:   return .live
        case .series: return .series
        case .home:   return .all
        default:      return .movies   // movies / settings → movies
        }
    }

    // Small red (n) notification badge — shown on the home puck when unread > 0.
    private func notifBadge(_ n: Int) -> some View {
        Text("\(min(n, 9))")
            .font(S8KFont.caption2.weight(.black)).foregroundColor(.white)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.s8kRed).clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.s8kBlack, lineWidth: 1.5))
            .offset(x: 3, y: -3)
            .allowsHitTesting(false)
    }
}

// The expanded, right-anchored pill: nav circles that reveal with a staggered spring
// from the corner (rightmost first) toward the left. A separate view so its `appeared`
// state drives the per-item stagger on insertion.
private struct ExpandedNavBar: View {
    @Binding var selected: AppTab
    @ObservedObject private var alerts = ActivationService.shared   // notifications
    @State private var appeared = false
    // A SHARED, pre-warmed generator. These are structs, so a `let` here allocated a
    // brand-new generator on every body pass and the Taptic Engine was never warm —
    // making the first tap's feedback land ~100-200ms late or be dropped entirely,
    // which is precisely what "the button felt dead" means.
    private var haptic: UISelectionFeedbackGenerator { s8kSelectionHaptic }

    // Menu sections (Settings removed → it lives on the top-left profile button).
    // FULL-WIDTH row, left→right: Movies · Series · Live · Search · [Bell] · Home.
    private let sections: [AppTab] = [.movies, .series, .live]

    var body: some View {
        // spacing 2 (was 4): with the notifications circle visible the bar needs
        // 6×44 + spacing + padding — at spacing 4 that was 330pt and clipped inside a
        // 320pt iPad Slide Over pane. The cells are distributed with maxWidth:.infinity,
        // so on a phone the change is invisible.
        HStack(spacing: 2) {
            ForEach(Array(sections.enumerated()), id: \.element) { idx, tab in
                // stagger counts from the RIGHT (near the corner): home first, movies last.
                navCircle(icon: selected == tab ? tab.activeIcon : tab.icon,
                          active: selected == tab,
                          staggerFromRight: (sections.count - idx) + 2,
                          label: tab.title) { select(tab) }
            }
            navCircle(icon: "magnifyingglass", active: false,
                      staggerFromRight: 2, label: L("search.title")) {
                haptic.selectionChanged()
                // In-place search (owner spec): morph the bar into a text field for
                // the current scope instead of opening a separate search page.
                AppRouter.shared.searchScope = AppTabBar.scope(for: selected)
                AppRouter.shared.searchText = ""
                AppRouter.shared.searchActive = true
            }
            // Notifications — only appears when there are unread; opens the list and
            // closes the menu. It does NOT mark them read here: doing so removed this
            // circle's own `if` in the same runloop, so the bar reflowed from 6 cells to
            // 5 and every other circle — including Home — jumped sideways under the
            // user's finger. `AlertsView.onDisappear` marks them read anyway, after the
            // bar is gone.
            if alerts.unreadCount > 0 {
                navCircle(icon: "bell.fill", active: false, staggerFromRight: 1,
                          label: L("alerts.title")) {
                    haptic.selectionChanged()
                    AppRouter.shared.homeSheet = .alerts
                    BarVisibility.shared.collapse()
                }
            }
            navCircle(icon: "house.fill", active: selected == .home,
                      staggerFromRight: 0, label: L("tab.home")) { select(.home) }
        }
        // 6, not 7: at a 320pt iPad Slide Over pane the 6-circle bar needed exactly
        // 274 of 274 available points -- zero slack, and pane widths are not even
        // guaranteed to be integral. This buys 2pt on each side.
        .padding(6)
        // interactive: false — iOS 26's interactive glass consumes the FIRST tap for its
        // own press animation, so every nav circle needed two taps. This codebase already
        // hit and documented that on text fields and on the Home top bar.
        .s8kGlass(Capsule(style: .continuous), interactive: false)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .contentShape(Capsule(style: .continuous))   // the whole pill blocks taps to content behind
        .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    /// Navigate to a section — the menu STAYS OPEN (owner spec) so the user can hop
    /// between sections; it auto-collapses when they scroll. Tapping the CURRENT
    /// section closes the menu (a manual collapse available on every page).
    private func select(_ tab: AppTab) {
        haptic.selectionChanged()
        if selected == tab {
            BarVisibility.shared.collapse()
        } else {
            // A page change must not read as a scroll on the shared offset tracker.
            BarVisibility.shared.pageChanged()
            // No withAnimation: a UIKit-backed TabView does not honour a SwiftUI
            // transaction for the page swap, it only picks up whatever implicitly
            // animatable properties the incoming page has — which made arriving at one
            // tab look different from arriving at another.
            selected = tab
        }
    }

    private func navCircle(icon: String, active: Bool, staggerFromRight: Int,
                           label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: active ? .bold : .medium))
                .foregroundColor(active ? .s8kBlack : .s8kTextSecondary)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(active ? AnyShapeStyle(S8KGradient.goldFlat)
                                         : AnyShapeStyle(Color.white.opacity(0.08)))
                )
                // INSIDE the label — this is the whole point. Applied outside the
                // Button (as they were) they only widened the LAYOUT cell: the gesture
                // stayed on the 44pt image, leaving ~12pt of dead glass on each side of
                // every circle — worst at the two ends of the pill, i.e. exactly where
                // the thumb lands. That is the "I pressed it and nothing happened".
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(S8KButtonStyle())
        // Staggered reveal: each circle fades and scales out of the corner, delayed by
        // its distance from the right edge. NOTE: no x-offset any more — during the
        // ~380ms reveal it displaced each circle's hit box 22pt to the right, so the
        // natural "tap the puck, tap again" gesture landed on empty glass.
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.85, anchor: .trailing)
        .animation(.spring(response: 0.38, dampingFraction: 0.72)
                    .delay(Double(staggerFromRight) * 0.045), value: appeared)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// MARK: - Safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Elegant confirmation card (replaces system action sheets)
struct S8KConfirm: View {
    let icon: String
    var iconColor: Color = .s8kGoldMid
    let title: String
    let message: String
    let confirmTitle: String
    var destructive: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.14)).frame(width: 60, height: 60)
                    Image(systemName: icon).font(.system(size: 25, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                VStack(spacing: 8) {
                    Text(title).font(S8KFont.title3).foregroundColor(.s8kTextPrimary)
                    Text(message).font(S8KFont.callout).foregroundColor(.s8kTextSecondary)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }
                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        // Same flat treatment as GoldButton — the app's two primary CTAs
                        // must not disagree (one flat, one gradient-with-a-glow).
                        Text(confirmTitle).font(S8KFont.field.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .foregroundColor(destructive ? .white : S8KBrand.accentInk)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(destructive ? AnyShapeStyle(Color.s8kRed)
                                                    : AnyShapeStyle(Color.s8kGoldHigh))
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    }
                    .buttonStyle(S8KButtonStyle())
                    Button(action: onCancel) {
                        Text(L("common.cancel")).font(S8KFont.subhead).foregroundColor(.s8kTextSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(S8KButtonStyle())
                }
            }
            .padding(26)
            .frame(maxWidth: 340)
            .background(Color.s8kCard)
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: S8KRadius.xl, style: .continuous)
                .strokeBorder(Color.s8kBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(28)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        // The floating tab bar is a SIBLING of the whole TabView, so no zIndex set
        // inside a tab page can out-rank it — its nav puck stayed drawn over this
        // scrim and stayed tappable, which meant the navigation bar could be opened
        // on top of a "delete my account" confirmation. Declaring the block here
        // rather than at each call site means it can never be forgotten.
        .onAppear    { AppRouter.shared.modalDepth += 1 }
        .onDisappear { AppRouter.shared.modalDepth = max(0, AppRouter.shared.modalDepth - 1) }
    }
}

// MARK: ════════════════════════════════════════
// LIQUID GLASS (iOS 26) — with graceful fallback
// ════════════════════════════════════════════
// Real Apple Liquid Glass on iOS 26+; on iOS 17–25 we fall back to a
// hand-tuned material that mirrors the look so the app stays sharp everywhere.

extension View {
    /// Primary glass surface for cards, sheets, and floating controls.
    /// `InsettableShape` is required for `strokeBorder` in the fallback path.
    @ViewBuilder
    func s8kGlass<S: InsettableShape>(_ shape: S, tinted: Bool = false, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            // `.interactive()` glass reacts to touch — great for buttons/pills, but on
            // a TEXT FIELD it consumes the first tap for its own press animation, so
            // the field needs a second tap to focus. Text fields pass interactive:false.
            if interactive {
                self.glassEffect(
                    tinted ? .regular.tint(Color.s8kGoldMid.opacity(0.18)).interactive()
                           : .regular.interactive(),
                    in: shape
                )
            } else {
                self.glassEffect(
                    tinted ? .regular.tint(Color.s8kGoldMid.opacity(0.18)) : .regular,
                    in: shape
                )
            }
        } else {
            // FALLBACK (iOS 17–25): both overlays are PURELY DECORATIVE and MUST NOT
            // capture touches. A filled Shape in an .overlay() is hit-testable by
            // default (visual transparency ≠ hit-test transparency), so without
            // allowsHitTesting(false) the gradient sheen sat on top of every
            // S8KTextField / SearchField and swallowed taps — text fields couldn't
            // become first responder (Xtream/M3U/search "locked"). iOS 26 uses the
            // glassEffect path above and was unaffected, which is why it looked
            // version-specific.
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), .clear, Color.black.opacity(0.10)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
                )
                .overlay(
                    shape.strokeBorder(
                        tinted ? Color.s8kGoldMid.opacity(0.35) : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
                )
        }
    }

    /// Convenience for the common rounded-rect glass card.
    func s8kGlassCard(radius: CGFloat = S8KRadius.xl, tinted: Bool = false) -> some View {
        s8kGlass(RoundedRectangle(cornerRadius: radius, style: .continuous), tinted: tinted)
    }
}

/// Wrap a cluster of nearby glass elements so they can morph/merge on iOS 26.
/// On older systems it is a transparent passthrough container.
struct S8KGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: S8KSpace.lg) { content() }
        } else {
            content()
        }
    }
}

// MARK: - Glass Card container (padding + glass surface)
struct GlassCard<Content: View>: View {
    var radius: CGFloat = S8KRadius.xl
    var tinted: Bool    = false
    var padding: CGFloat = S8KSpace.xl
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .s8kGlassCard(radius: radius, tinted: tinted)
    }
}
