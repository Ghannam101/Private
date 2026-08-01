// ============================================================
// BLANK TV — Plate.swift
// The app is fed by the user's own provider, so a poster is missing far more often
// than it is present. Every rival answers that with a grey box. This answers it with
// artwork the app makes itself: a woven plate dyed from the title's own letters, with
// the name set over it in live type.
//
// The consequence is the point — there is no broken-image state anywhere.
//
// A Python reference implementation lives at design/plate/plate_reference.py with the
// three findings that shaped this file. The two that are load-bearing here:
//
//   THE INTERLACE. A first version had weft only — horizontal bands fading into one
//   another — which reads as a coloured blur, and those already exist. What makes a
//   textile read as MADE is two thread directions crossing and, above all, the
//   over/under parity of one thread passing over another. That parity is a single
//   term below and it is the whole difference.
//
//   THREAD COUNT FOLLOWS THE PIXELS. Thread COUNT is seeded, but thread WIDTH is what
//   an eye resolves. A fixed count gave a ~4px thread in a small cell, the parity
//   landed on alternating pixels, and the weave aliased into moire. Rendering one
//   title at 354 / 312 / 192 px showed only the smallest breaking, which is why this
//   would have shipped: it looks right at every size a designer inspects and fails at
//   the size a phone draws a small cell.
// ============================================================

import CryptoKit
import SwiftUI
import UIKit

enum Plate {

    // MARK: Dyeing

    /// Chroma ceiling in OKLab. This single number is the difference between dyed
    /// cloth and a pixel sprite, and it is why a rail of plates sits UNDER real poster
    /// artwork instead of fighting it. Do not raise it without rendering the result.
    private static let chromaCap: CGFloat = 0.055
    private static let lightLow: CGFloat = 0.20
    private static let lightHigh: CGFloat = 0.40

    /// Smallest thread we will draw. Below this the interlace parity lands on
    /// alternating pixels and the weave turns into moire.
    private static let minThread: CGFloat = 7

    // MARK: Cache

    /// Keyed on title AND pixel size, deliberately: because thread count is clamped by
    /// the render size, the same title at two sizes is genuinely two different plates,
    /// and scaling one into the other reintroduces exactly the aliasing the clamp
    /// removes. Small, because plates are cheap to redraw and posters are not.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    /// The plate for a title, at a point size. Rendered once and reused.
    ///
    /// Rendering is a few thousand rect fills, not per-pixel work, so it is cheap
    /// enough to do on demand — but it must never happen inside a scrolling cell's
    /// body. Callers get an `Image` through `PlateView`, which renders in `.task`.
    static func image(for title: String, size: CGSize) -> UIImage? {
        guard size.width >= 8, size.height >= 8 else { return nil }
        let scale = UIScreen.main.scale
        let px = CGSize(width: (size.width * scale).rounded(),
                        height: (size.height * scale).rounded())
        let key = "\(normalised(title))|\(Int(px.width))x\(Int(px.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let img = draw(normalised(title), pixels: px, scale: scale)
        cache.setObject(img, forKey: key, cost: Int(px.width * px.height * 4))
        return img
    }

    // MARK: The weave

    /// Lower-cased, whitespace-collapsed — so "MBC 1  HD" and "mbc 1 hd" are one cloth.
    /// Matches the reference implementation exactly; changing it re-dyes every plate.
    static func normalised(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// SHA-256 read as a field of knobs in 0…1. Deterministic, offline, stateless:
    /// the same title weaves the same cloth forever, on every device.
    private static func knobs(_ normalisedTitle: String) -> [CGFloat] {
        let digest = SHA256.hash(data: Data(normalisedTitle.utf8))
        let bytes = Array(digest)
        return (bytes + bytes).map { CGFloat($0) / 255.0 }   // 64 knobs
    }

    private static func draw(_ title: String, pixels: CGSize, scale: CGFloat) -> UIImage {
        let k = knobs(title)

        // Structure is what separates two plates; hue is what must not. Twelve plates
        // at a clamped chroma would read as one object repeated if only the hue moved.
        var weft = 46 + Int(k[0] * 34)
        var warp = 26 + Int(k[1] * 26)
        weft = max(12, min(weft, Int(pixels.height / minThread)))
        warp = max(8, min(warp, Int(pixels.width / minThread)))

        let hue = k[2] * 2 * .pi
        let skew = (k[3] - 0.5) * 1.1

        // Three low-frequency sinusoids. LOW frequency is the point — high frequency
        // here stops being cloth and becomes a sprite.
        let f1 = 0.6 + k[4] * 1.6, f2 = 1.4 + k[5] * 2.4, f3 = 2.6 + k[6] * 4.0
        let p1 = k[7] * 6.283, p2 = k[8] * 6.283, p3 = k[9] * 6.283
        let a1 = 0.55 + k[10] * 0.45, a2 = 0.30 + k[11] * 0.38, a3 = 0.14 + k[12] * 0.26
        let ribWeft = 0.085 + k[14] * 0.055
        let ribWarp = 0.075 + k[15] * 0.050
        let slub = 0.20 + k[16] * 0.35

        // Per-thread thickness variation, seeded like everything else. A perfectly even
        // weave reads as machine print rather than as something made.
        let slubY = (0...(weft + 1)).map { 1.0 + (k[($0 * 7 + 19) % 64] - 0.5) * slub }
        let slubX = (0...(warp + 1)).map { 1.0 + (k[($0 * 11 + 23) % 64] - 0.5) * slub }

        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = scale
        fmt.opaque = true
        let pointSize = CGSize(width: pixels.width / scale, height: pixels.height / scale)

        return UIGraphicsImageRenderer(size: pointSize, format: fmt).image { ctx in
            let cg = ctx.cgContext
            let cellH = pointSize.height / CGFloat(weft)
            let cellW = pointSize.width / CGFloat(warp)

            // Drawn as a grid of cells rather than per pixel: the interlace varies per
            // cell, not per pixel, so a few thousand fills give the same image for a
            // fraction of the cost. The vertical gradient bands at `weft` steps, which
            // at 46+ rows is below the threshold where an eye reads it as banding.
            for row in 0..<weft {
                let t = CGFloat(row) / CGFloat(weft)
                let s = (a1 * sin(f1 * t * 6.283 + p1)
                       + a2 * sin(f2 * t * 6.283 + p2)
                       + a3 * sin(f3 * t * 6.283 + p3)) / (a1 + a2 + a3)

                let baseL = lightLow + (lightHigh - lightLow) * (0.5 + 0.5 * s)
                let h = hue + s * skew
                let c = chromaCap * (0.55 + 0.45 * abs(s))
                let aStar = c * cos(h), bStar = c * sin(h)

                // Thread thickness reads as how much of the cell the crown occupies.
                let crownY = 0.5 * min(max(slubY[row], 0.4), 1.6)

                for col in 0..<warp {
                    let crownX = 0.5 * min(max(slubX[col], 0.4), 1.6)

                    // THE INTERLACE. On an "over" cell the weft thread lies on top and
                    // catches the light; on "under" the warp does. A plain sine grid
                    // reads as a screen door — this parity is what reads as weaving.
                    let over = (row + col) % 2 == 0
                    let lift = over
                        ? crownY * ribWeft * 1.15 - (1 - crownX) * ribWarp * 0.45
                        : crownX * ribWarp * 1.15 - (1 - crownY) * ribWeft * 0.45

                    cg.setFillColor(srgb(l: baseL + lift, a: aStar, b: bStar))
                    // Overdrawn by a hair so seams between cells cannot show as a grid
                    // of pale hairlines on a non-integral scale.
                    cg.fill(CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH,
                                   width: cellW + 0.5, height: cellH + 0.5))
                }
            }
        }
    }

    // MARK: OKLab → sRGB

    /// OKLab, not HSB: it is perceptually uniform, so a clamped chroma stays visually
    /// constant across hues. In HSB the same saturation number is garish in yellow and
    /// invisible in blue, and the whole idea rests on that ceiling meaning one thing.
    private static func srgb(l: CGFloat, a: CGFloat, b: CGFloat) -> CGColor {
        let L = min(max(l, 0), 1)
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let lc = l_ * l_ * l_, mc = m_ * m_ * m_, sc = s_ * s_ * s_

        func encode(_ v: CGFloat) -> CGFloat {
            let c = min(max(v, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        let r = encode(+4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc)
        let g = encode(-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc)
        let bl = encode(-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc)
        return UIColor(red: r, green: g, blue: bl, alpha: 1).cgColor
    }
}

// MARK: - The view

/// A plate with its title set over it.
///
/// The TYPE carries the meaning and the colour is only texture — which is why this
/// stays legible in greyscale, to a colour-blind user, and to VoiceOver. Nothing here
/// encodes information in hue.
struct PlateView: View {
    let title: String
    /// Point size of the title. Callers in a small cell should come down from this.
    var titleSize: CGFloat = 15

    @State private var plate: UIImage?
    @State private var box: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let plate {
                Image(uiImage: plate).resizable()
            } else {
                // Never a flash of grey: the darkest tone the weave can produce.
                Color(red: 0.055, green: 0.055, blue: 0.060)
            }

            // A short scrim so a title stays readable over the palest weave a hash
            // can produce, without dimming the cloth everywhere.
            LinearGradient(colors: [.black.opacity(0.55), .clear],
                           startPoint: .bottom, endPoint: .center)

            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
        }
        // Measured from the BACKGROUND, never from a root GeometryReader: as the root
        // it reports zero on the first pass, and every derived value — including the
        // thread clamp this whole file depends on — would be computed from nothing.
        .background(
            GeometryReader { g in
                Color.clear.preference(key: PlateBoxKey.self, value: g.size)
            }
        )
        .onPreferenceChange(PlateBoxKey.self) { box = $0 }
        // Rendered off the body: a few thousand fills inside a scrolling cell's body
        // is exactly the stutter this app has already had once.
        .task(id: "\(title)|\(Int(box.width))x\(Int(box.height))") {
            guard box.width >= 8, box.height >= 8 else { return }
            let size = box
            let name = title
            plate = await Task.detached(priority: .userInitiated) {
                Plate.image(for: name, size: size)
            }.value
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private struct PlateBoxKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
