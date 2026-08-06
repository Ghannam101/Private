"""build_assets.py — render the Trex TV app icon and logo from the vector.

Everything ships from the SVG, never from the supplied JPEG. The JPEG has compression
artefacts and no clean edge at any scale; the vector is the master and this file is the
only thing that turns it into pixels, so the two can never drift apart.

    python design/brand/build_assets.py

Writes straight into BlankTV/Assets.xcassets. Re-runnable.

Two things here are requirements, not preferences:

  OPAQUE. The 1024 master must have no alpha channel at all — an alpha in an app icon is
  an automatic App Store rejection. Chrome would otherwise hand back an RGBA PNG, so the
  result is composited onto the brand ground and saved as RGB.

  MARGIN. The mark occupies 74% of the tile's width and is optically centred rather than
  geometrically: the left side is a dense full-height cut and the right extremity is a
  single sharp snout tip, and a point needs more clearance than a flat edge. The blend is
  0.60 toward the ink centroid, which leaves the tightest margin at 10.6% instead of 7.3%.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(REPO, "BlankTV", "Assets.xcassets")
CHROME = r"C:/Program Files/Google/Chrome/Application/chrome.exe"

GROUND = (0x0B, 0x0B, 0x17)      # #0B0B17 — the owner's own background pixel
# The CONTAINER width, not the ink width. The mark's ink does not fill its own viewBox —
# it measures 758 of 512-space units wide — so a 0.74 container renders ink at only 62% of
# the tile. Measured on the first render and corrected: 0.882 puts the ink at ~74%, which
# is what the icon actually wants. Do not "simplify" this back to 0.74.
CONTENT = 0.882
NUDGE = 0.35                     # optical-centring blend, see the note above


def svg_source():
    p = os.path.join(HERE, "TrexMark.svg")
    if not os.path.exists(p):
        sys.exit("missing %s — the vector master must be committed first" % p)
    return open(p, encoding="utf-8").read()


def render(svg, px, ground, content=CONTENT, nudge=NUDGE):
    """Rasterise the mark on a tile via headless Chrome, then flatten to RGB."""
    bg = "#%02X%02X%02X" % ground if ground else "transparent"
    w = content * 100.0
    # The horizontal nudge moves the art left of centre: the snout tip on the right needs
    # more air than the flat cut on the left.
    left = (100.0 - w) / 2.0 - (100.0 - w) / 2.0 * nudge * 0.28
    html = (
        "<!doctype html><meta charset=utf-8>"
        "<style>html,body{margin:0;padding:0;background:%s}"
        "#t{position:relative;width:%dpx;height:%dpx;overflow:hidden}"
        "#m{position:absolute;width:%.4f%%;left:%.4f%%;top:50%%;transform:translateY(-50%%)}"
        "#m svg{width:100%%;height:auto;display:block}</style>"
        "<div id=t><div id=m>%s</div></div>" % (bg, px, px, w, left, svg))
    with tempfile.TemporaryDirectory() as tmp:
        page = os.path.join(tmp, "p.html")
        out = os.path.join(tmp, "o.png")
        open(page, "w", encoding="utf-8").write(html)
        subprocess.run([CHROME, "--headless", "--disable-gpu", "--no-sandbox",
                        "--user-data-dir=" + os.path.join(tmp, "prof"),
                        "--default-background-color=00000000" if not ground else
                        "--force-device-scale-factor=1",
                        "--screenshot=" + out, "--window-size=%d,%d" % (px, px),
                        "--hide-scrollbars", "file:///" + page.replace("\\", "/")],
                       check=True, capture_output=True)
        im = Image.open(out)
        if ground:
            flat = Image.new("RGB", im.size, ground)
            flat.paste(im, (0, 0), im if im.mode == "RGBA" else None)
            return flat                      # RGB — no alpha channel, ever
        return im.convert("RGBA")


def write(img, folder, name):
    d = os.path.join(ASSETS, folder)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, name)
    img.save(p)
    print("   %-46s %dx%d  %s" % (folder + "/" + name, img.width, img.height, img.mode))
    return p


def main():
    svg = svg_source()
    print("APP ICON — opaque, on the brand ground")
    icon = render(svg, 1024, GROUND)
    assert icon.mode == "RGB", "icon must have no alpha"
    write(icon, "AppIcon.appiconset", "AppIcon1024.png")

    print("LOGO — transparent, for in-app use at @1x/@2x/@3x")
    for scale, px in (("", 120), ("@2x", 240), ("@3x", 360)):
        write(render(svg, px, None, content=1.0, nudge=0.0),
              "Logo.imageset", "logo%s.png" % scale)
    print("done")


if __name__ == "__main__":
    main()
