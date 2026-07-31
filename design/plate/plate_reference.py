"""weave2.py — make the cloth actually read as cloth.

v1 proved the idea and failed the eye: it produced a soft vertical gradient, which is
a coloured blur placeholder, and those already exist. The claim in the spec is a WOVEN
textile, and a weave has two thread directions crossing, not one axis fading.

What changed, and why:

  WARP. v1 had weft only — horizontal bands. Real cloth has vertical threads too, and
  their interference with the weft is the whole reason a textile reads as made rather
  than printed. Added as its own seeded frequency.

  THE INTERLACE. Where warp crosses weft, one passes over the other, and that alternation
  is what the eye recognises as weaving. A cheap sine grid does not do it; the over/under
  parity does. That parity is one term and it is the single biggest change here.

  SLUB. Handwoven thread varies in thickness. A perfectly even weave reads as machine
  print. Deterministic per-thread jitter, seeded like everything else, so the same title
  always yields the same cloth.

  RIB CONTRAST. v1's rib was 0.045 of lightness, which is invisible past arm's length.
  It is now a real shadow in the trough with a sharper falloff.

Chroma stays hard-clamped at 0.055 — that number is not the problem, it is the reason
these sit under real poster artwork without fighting it, and it is the difference
between dyed cloth and a pixel sprite.

Note for the Swift port: this is per-pixel Python for judgement only. In the app the
plate is drawn ONCE per title into S8KImageCache and never recomputed in a scrolling
cell — the repo has a stutter history and 100+ bands across 30 visible cells is exactly
how it comes back.
"""
import hashlib
import math
import os

from PIL import Image

W, H = 260, 390
CHROMA_CAP = 0.055
L_LO, L_HI = 0.20, 0.40


def oklab_to_srgb(L, a, b):
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    r = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    def enc(c):
        c = max(0.0, min(1.0, c))
        c = 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055
        return int(round(max(0.0, min(1.0, c)) * 255))

    return enc(r), enc(g), enc(bl)


def knobs(title):
    norm = " ".join(title.strip().lower().split())
    d = hashlib.sha256(norm.encode("utf-8")).digest()
    return [x / 255.0 for x in d] + [x / 255.0 for x in d]      # 64 knobs


def weave(title, w=W, h=H):
    k = knobs(title)

    # Thread COUNT is seeded, but thread WIDTH is what the eye resolves, so the count
    # is capped by the pixels available. Rendering a fixed 26-52 warp into a 192px
    # cell gives a 4px thread: the over/under parity then lands on alternating pixels
    # and the weave aliases into moire and hard stripes. Verified by rendering the
    # same title at 354 / 312 / 192 px — only the smallest broke. MIN_THREAD is the
    # floor that keeps the interlace resolvable at every size the app draws a plate.
    MIN_THREAD = 7.0
    weft = 46 + int(k[0] * 34)                  # horizontal threads, 46..80
    warp = 26 + int(k[1] * 26)                  # vertical threads,   26..52
    weft = max(12, min(weft, int(h / MIN_THREAD)))
    warp = max(8, min(warp, int(w / MIN_THREAD)))
    hue = k[2] * 2 * math.pi
    skew = (k[3] - 0.5) * 1.1

    f1, f2, f3 = 0.6 + k[4] * 1.6, 1.4 + k[5] * 2.4, 2.6 + k[6] * 4.0
    p1, p2, p3 = k[7] * 6.283, k[8] * 6.283, k[9] * 6.283
    a1, a2, a3 = 0.55 + k[10] * 0.45, 0.30 + k[11] * 0.38, 0.14 + k[12] * 0.26

    rib_w = 0.085 + k[14] * 0.055               # weft shadow — was a flat 0.045
    rib_p = 0.075 + k[15] * 0.050               # warp shadow
    slub_amt = 0.20 + k[16] * 0.35

    wh, ww = h / weft, w / warp

    # Per-thread slub, drawn from the digest so a title always weaves identically.
    slub_y = [1.0 + (k[(i * 7 + 19) % 64] - 0.5) * slub_amt for i in range(weft + 2)]
    slub_x = [1.0 + (k[(j * 11 + 23) % 64] - 0.5) * slub_amt for j in range(warp + 2)]

    img = Image.new("RGB", (w, h))
    px = img.load()

    for y in range(h):
        yi = y / wh
        row_i = int(yi)
        t = yi / weft

        fy = (yi - row_i) * slub_y[min(row_i, weft)]
        fy = min(max(fy, 0.0), 1.0)
        ribY = (abs(fy - 0.5) * 2.0) ** 1.7          # trough shadow, sharper than v1

        s = (a1 * math.sin(f1 * t * 6.283 + p1)
             + a2 * math.sin(f2 * t * 6.283 + p2)
             + a3 * math.sin(f3 * t * 6.283 + p3)) / (a1 + a2 + a3)

        L0 = L_LO + (L_HI - L_LO) * (0.5 + 0.5 * s)
        hh = hue + s * skew
        c = CHROMA_CAP * (0.55 + 0.45 * abs(s))
        a_, b_ = c * math.cos(hh), c * math.sin(hh)

        for x in range(w):
            xi = x / ww
            col_i = int(xi)
            fx = (xi - col_i) * slub_x[min(col_i, warp)]
            fx = min(max(fx, 0.0), 1.0)
            ribX = (abs(fx - 0.5) * 2.0) ** 1.7

            # THE INTERLACE. Over/under parity is what the eye reads as weaving; a
            # plain sine grid reads as a screen door. On an "over" cell the weft
            # thread is on top and catches the light, on "under" it is in shadow.
            over = (row_i + col_i) & 1
            if over:
                L = L0 + (0.5 - ribY) * rib_w * 1.15 - ribX * rib_p * 0.45
            else:
                L = L0 + (0.5 - ribX) * rib_p * 1.15 - ribY * rib_w * 0.45

            px[x, y] = oklab_to_srgb(max(0.0, min(1.0, L)), a_, b_)
    return img


TITLES = [
    "AR| MBC 1 HD", "beIN SPORTS 1 HD", "قناة الجزيرة الاخبارية", "EN: HBO 4K",
    "ROTANA CINEMA MASR", "مسلسل الصندوق الأسود", "SSC SPORT 5", "FR| CANAL+ CINEMA",
    "TR| TRT 1 FHD", "Untitled_stream_0041", "###  NO NAME  ###", "VOD | The Long Night",
]

if __name__ == "__main__":
    out = os.path.dirname(os.path.abspath(__file__))
    g = 12
    sheet = Image.new("RGB", (W * 6 + g * 7, H * 2 + g * 3), (0, 0, 0))
    for i, t in enumerate(TITLES):
        sheet.paste(weave(t), (g + (i % 6) * (W + g), g + (i // 6) * (H + g)))
    sheet.save(os.path.join(out, "weave2_sheet.png"))

    # Detail crop: the claim is that the weave is VISIBLE, so show it at 1:1.
    big = weave("AR| MBC 1 HD", 520, 780).crop((0, 0, 260, 260)).resize(
        (520, 520), Image.NEAREST)
    big.save(os.path.join(out, "weave2_detail.png"))

    # The near-collision test again — the tuning must not have cost separation.
    pair = Image.new("RGB", (W * 4 + g * 5, H + g * 2), (0, 0, 0))
    for i, t in enumerate(["MBC 1", "MBC 2", "MBC 3", "MBC 4"]):
        pair.paste(weave(t), (g + i * (W + g), g))
    pair.save(os.path.join(out, "weave2_near.png"))
    print("wrote weave2_sheet.png, weave2_detail.png, weave2_near.png")
