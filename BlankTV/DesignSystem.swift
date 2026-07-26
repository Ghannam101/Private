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

@MainActor func s8kWindowSize() -> CGSize {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    if let s = active?.keyWindow?.bounds.size, s.width > 1, s.height > 1 { return s }
    if let s = active?.screen.bounds.size, s.width > 1, s.height > 1 { return s }
    return UIScreen.main.bounds.size
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
    static let strongGold = BrandTheme(
        base:     Color(red: 0.039, green: 0.039, blue: 0.039),   // #0A0A0A
        surface:  Color(red: 0.055, green: 0.055, blue: 0.063),
        card:     Color(red: 0.082, green: 0.082, blue: 0.094),
        elevated: Color(red: 0.110, green: 0.110, blue: 0.125),
        accentHigh: Color(red: 1.000, green: 0.843, blue: 0.000), // #FFD700 gold
        accentMid:  Color(red: 0.784, green: 0.525, blue: 0.039), // #C8860A
        accentLow:  Color(red: 0.545, green: 0.376, blue: 0.031),
        accentDeep: Color(red: 0.420, green: 0.259, blue: 0.020)
    )

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
    @Published var serverName:   String  = "Blank Prime"
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
            serverName   = "Blank Prime"
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
                    ProgressView().progressViewStyle(.circular).tint(.s8kBlack).scaleEffect(0.85)
                }
            }
            // Deep-green ink (not pure black) so the CTA re-skins with BrandTheme.
            // Disabled ink is WHITE at 45%: the old black-on-white@0.15 was 1.6:1 —
            // an unreadable empty slab, and that is the button's DEFAULT state on the
            // login gateway (disabled until a username and password are typed).
            .foregroundColor(isDisabled ? Color.white.opacity(0.45) : Color.s8kBlack)
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

    /// Decode the cached ThumbHash for `key` into a tiny blurred placeholder image.
    /// nil when nothing is stored. Cheap; call OFF the main thread.
    func thumbHashImage(_ key: String) -> UIImage? {
        guard let data = CatalogDB.imageHash(key), data.count >= 5 else { return nil }
        return thumbHashToImage(hash: data)
    }

    /// Encode + persist a ThumbHash for `key` once (idempotent). The heavy encode
    /// runs at background priority so it never delays the on-screen image.
    private static func ensureThumbHash(key: String, image: UIImage) {
        guard !CatalogDB.hasImageHash(key) else { return }
        Task.detached(priority: .background) {
            let hash = imageToThumbHash(image: image)
            if !hash.isEmpty { CatalogDB.saveImageHash(key, hash) }
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
        guard let u = url, let imageURL = URL(string: u) else { image = nil; placeholderImage = nil; failed = false; return }
        failed = false
        if let hit = S8KImageCache.shared.cached(u) { image = hit; return }
        // Paint an instant blurred ThumbHash placeholder (decoded off-main) while the
        // real image downloads. A nil result for the new url also clears any stale one.
        let ph = await Task.detached(priority: .utility) { S8KImageCache.shared.thumbHashImage(u) }.value
        guard !Task.isCancelled else { return }
        if image == nil { placeholderImage = ph }
        let img = await S8KImageCache.shared.load(imageURL, key: u, maxPixel: maxPixel)
        guard !Task.isCancelled else { return }
        if let img {
            withAnimation(.easeOut(duration: 0.25)) { image = img }
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
                    Image("Logo").resizable().scaledToFit().frame(width: 22, height: 22)
                }
                Text(BrandKit.customName ?? "Blank Prime")
                    .font(.system(size: 11, weight: .black))
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
            Image("Logo").resizable().scaledToFit().frame(width: size, height: size)
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
                Text("Blank")
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
                .foregroundColor(.s8kBlack)
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
            .font(.system(size: 10, weight: .black)).foregroundColor(.white)
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
        .padding(7)
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
                        Text(confirmTitle).font(.system(size: 16, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .foregroundColor(destructive ? .white : .s8kBlack)
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
