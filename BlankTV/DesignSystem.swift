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
    @Published var serverName:   String  = "BLANK TV"
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
            serverName   = "BLANK TV"
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
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().progressViewStyle(.circular).tint(.black).scaleEffect(0.85)
                } else {
                    if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
                    Text(title).font(S8KFont.headline)
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                Group {
                    if isDisabled {
                        Color.white.opacity(0.15)
                    } else {
                        LinearGradient(colors: [.s8kGoldHigh, .s8kGoldMid], startPoint: .leading, endPoint: .trailing)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md))
            .shadow(color: .s8kGoldMid.opacity(isDisabled ? 0 : 0.4), radius: 12, y: 4)
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
                .foregroundColor(focused ? .s8kGoldMid : .s8kTextDisabled)
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.2), value: focused)

            Group {
                if isSecure && !visible {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(S8KFont.body)
            .foregroundColor(.s8kTextPrimary)
            .environment(\.layoutDirection, ltr ? .leftToRight : .rightToLeft)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .autocorrectionDisabled(disableAutocorrect)
            .textInputAutocapitalization(capitalization)
            .focused($focused)

            if isSecure {
                Button(action: { visible.toggle() }) {
                    Image(systemName: visible ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.s8kTextDisabled)
                }
            }
        }
        .padding(.horizontal, S8KSpace.lg)
        .frame(height: 52)
        // Non-interactive glass: an input field must not swallow the first tap for a
        // press animation (that caused the "tap once or twice before typing" issue).
        .s8kGlass(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous), interactive: false)
        .overlay(
            RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous)
                .strokeBorder(focused ? Color.s8kGoldMid : Color.s8kBorder, lineWidth: 1.5)
                .allowsHitTesting(false)   // purely decorative border — never intercept taps
        )
        .shadow(color: focused ? .s8kGoldMid.opacity(0.12) : .clear, radius: 8)
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
        return img
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

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
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
        guard let u = url, let imageURL = URL(string: u) else { image = nil; failed = false; return }
        failed = false
        if let hit = S8KImageCache.shared.cached(u) { image = hit; return }
        let img = await S8KImageCache.shared.load(imageURL, key: u, maxPixel: 800)
        guard !Task.isCancelled else { return }
        if let img { image = img } else { failed = true }
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
                        colors: [.clear, Color.white.opacity(0.09), .clear],
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
            .fill(Color.s8kElevated)
            .s8kShimmer()
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
                    S8KImage(url: logo, placeholder: "play.tv.fill")
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image("Logo").resizable().scaledToFit().frame(width: 22, height: 22)
                }
                Text(BrandKit.customName ?? "BLANK TV")
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
                .foregroundStyle(S8KGradient.goldFlat)
                .lineLimit(1).minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        } else {
            HStack(spacing: size * 0.30) {
                Text("BLANK")
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .tracking(size * 0.16)
                    .foregroundColor(.s8kTextPrimary)
                Text("TV")
                    .font(.system(size: size * 1.02, weight: .heavy, design: .rounded))
                    .tracking(size * 0.06)
                    .foregroundStyle(S8KGradient.goldFlat)
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

            Text(message)
                .font(S8KFont.footnote)
                .foregroundColor(.s8kTextTertiary)
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
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Color.white.opacity(0.12)
                                    S8KGradient.goldFlat
                                        .frame(width: g.size.width * min(1, max(0, p)))
                                }
                            }
                            .frame(height: 3)
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
                    S8KImage(url: logoURL, placeholder: "antenna.radiowaves.left.and.right")
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

    /// Feed the current vertical content offset.
    func report(offsetY newY: CGFloat) {
        // Top bar glass once scrolled past a small threshold.
        let s = newY > 30
        if s != scrolled { withAnimation(.easeInOut(duration: 0.25)) { scrolled = s } }
        // Any real scroll closes the menu (it only opens on a puck tap).
        let delta = newY - lastOffset
        lastOffset = newY
        if abs(delta) > 6 { collapse() }
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
            self.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y }
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
    @Environment(\.horizontalSizeClass) private var hSize
    private let haptic = UISelectionFeedbackGenerator()

    var body: some View {
        Group {
            if vis.minimized {
                collapsedPuck
            } else {
                ExpandedNavBar(selected: $selected)
            }
        }
        // Anchor to the physical RIGHT edge (content hugs trailing); the pill grows left.
        .frame(maxWidth: hSize == .regular ? 560 : .infinity, alignment: .trailing)
        .padding(.trailing, 16)
        .padding(.bottom, 10)
        .environment(\.layoutDirection, .leftToRight)
    }

    // Collapsed — the lime HOME puck in the corner (the persistent marker). Tap to
    // open the menu leftward. (Settings lives on the top-left profile button now.)
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
        }
        .buttonStyle(S8KButtonStyle())
        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
        .accessibilityLabel(L("tab.home"))
    }

    /// Map the active section → the default search scope.
    static func scope(for tab: AppTab) -> SearchVM.SearchScope {
        switch tab {
        case .live:   return .live
        case .series: return .series
        default:      return .movies   // home / movies / settings → movies
        }
    }
}

// The expanded, right-anchored pill: nav circles that reveal with a staggered spring
// from the corner (rightmost first) toward the left. A separate view so its `appeared`
// state drives the per-item stagger on insertion.
private struct ExpandedNavBar: View {
    @Binding var selected: AppTab
    @State private var appeared = false
    private let haptic = UISelectionFeedbackGenerator()

    // Menu sections (Settings removed → it lives on the top-left profile button).
    // Row left→right: Movies · Series · Live · Search · Home(rightmost, by the corner).
    private let sections: [AppTab] = [.movies, .series, .live]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(sections.enumerated()), id: \.element) { idx, tab in
                // stagger counts from the RIGHT (near the corner): home first, movies last.
                navCircle(icon: selected == tab ? tab.activeIcon : tab.icon,
                          active: selected == tab,
                          staggerFromRight: (sections.count - idx) + 1,
                          label: tab.title) { select(tab) }
            }
            navCircle(icon: "magnifyingglass", active: false,
                      staggerFromRight: 1, label: L("search.title")) {
                haptic.selectionChanged()
                AppRouter.shared.searchScope = AppTabBar.scope(for: selected)
                AppRouter.shared.homeSheet = .search
                BarVisibility.shared.collapse()
            }
            navCircle(icon: "house.fill", active: selected == .home,
                      staggerFromRight: 0, label: L("tab.home")) { select(.home) }
        }
        .padding(7)
        .s8kGlass(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }

    /// Navigate to a section and close the menu back to the corner puck.
    private func select(_ tab: AppTab) {
        haptic.selectionChanged()
        if selected != tab { withAnimation(.snappy(duration: 0.3)) { selected = tab } }
        BarVisibility.shared.collapse()
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
        }
        .buttonStyle(S8KButtonStyle())
        // Staggered reveal: each circle slides out of the corner, delayed by its
        // distance from the right edge.
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.5, anchor: .trailing)
        .offset(x: appeared ? 0 : 22)
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
                        Text(confirmTitle).font(S8KFont.headline)
                            .foregroundColor(destructive ? .white : .black)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(destructive ? AnyShapeStyle(Color.s8kRed)
                                                    : AnyShapeStyle(S8KGradient.goldFlat))
                            .clipShape(RoundedRectangle(cornerRadius: S8KRadius.md, style: .continuous))
                            .shadow(color: (destructive ? Color.s8kRed : .s8kGoldMid).opacity(0.35), radius: 10, y: 3)
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
