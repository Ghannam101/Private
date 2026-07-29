"""uilint.py — the UI rules from DEFECTS.md, enforced.

A rule that depends on a human remembering it is a rule that will be broken. Each of
these was learned from a defect that shipped or nearly shipped here, and each is
mechanically detectable — so it is detected, not hoped for.

  touch-outside-label   D-01  s8kMinTouch applied to a Button instead of its label:
                              a no-op that also swallows neighbouring taps
  touch-before-clip     D-02  s8kMinTouch before .clipShape, which clips hit testing
                              too, so the expansion is silently undone
  fill-fullbleed        D-04  .fill artwork in a full-bleed context, where a source
                              whose aspect differs from the screen visibly stretches
  banned-pattern        D-06  layout constructs that each caused a real bug here

Every check is deliberately NARROW. A linter with false positives gets ignored, and an
ignored linter is worse than none — see D-16. Three checks were tightened during
authoring for exactly that reason:

  * `.contentShape` is NOT checked for D-01. It has legitimate homes that have nothing
    to do with a Button — on a card paired with .onTapGesture, and inside a
    `Menu { ... } label: { ... }`. `s8kMinTouch` has exactly one correct home, so it
    can be checked without ambiguity.
  * `UIScreen.main.bounds` is allowed in `s8kWindowSize`, the metrics source itself,
    where it is the last-resort fallback after the key window and the scene's screen.
  * A `GeometryReader { _ in }` root is a sizing container, not the documented defect
    (a root whose geometry was READ and came back zero before layout). Only a root that
    binds its geometry is flagged.

Run from the repo root:  python uilint.py     (exit 1 on any finding)
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

SRC = "BlankTV"

STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
COMMENT = re.compile(r'//.*$')
TOUCH = re.compile(r'\.(?:s8kMinTouch|s8kMinTouchV)\s*\(')
CLIP = re.compile(r'\.clipShape\s*\(')
BUTTON = re.compile(r'\bButton\s*[({]')
DECL = re.compile(r'\b(?:func|var)\s+([A-Za-z_][A-Za-z0-9_]*)')
FORMATTER = re.compile(r'\b(DateFormatter|NumberFormatter|DateComponentsFormatter'
                       r'|ByteCountFormatter|MeasurementFormatter|RelativeDateTimeFormatter)\s*\(\s*\)')
BODY = re.compile(r'\bvar\s+body\s*:\s*some\s+View\s*\{')
# The lookahead sits IMMEDIATELY after `{` on purpose. Written as `\s*\{\s*(?!_\s+in)`
# it silently matched everything: `\s*` backtracks to consume nothing, the lookahead
# then tests against a space, `_` does not match a space, so the negative lookahead
# succeeds and `{ _ in }` was flagged anyway. Found by running the linter on its own
# rule set — which is exactly what D-16 demands of every gate.
GEOROOT = re.compile(r'^GeometryReader\s*\{(?!\s*_\s+in)')
FOREACH = re.compile(r'ForEach\s*\(\s*0\s*\.\.<\s*([A-Za-z_][A-Za-z0-9_.]*)')


def strip(line):
    """Code only. Comments and string bodies are removed, so a rule name written in a
    comment or a user-facing message never counts as a violation."""
    return STRING.sub('""', COMMENT.sub('', line))


def depths(lines):
    """Brace/paren depth at the START of each line."""
    out, d = [], 0
    for raw in lines:
        s = strip(raw)
        out.append(d)
        d += s.count("{") + s.count("(") - s.count("}") - s.count(")")
    return out


def enclosing_decl(lines, i):
    """Name of the nearest func/var declared above line i — enough to exempt the one
    place a banned call legitimately lives."""
    j = i
    while j >= 0 and i - j < 40:
        m = DECL.search(strip(lines[j]))
        if m:
            return m.group(1)
        j -= 1
    return ""


findings = []


def report(path, i, rule, msg, src):
    findings.append((path, i + 1, rule, msg, src.strip()[:96]))


def check_file(path, lines):
    dep = depths(lines)

    for i, raw in enumerate(lines):
        code = strip(raw)

        if TOUCH.search(code):
            # D-01. Walk back to the nearest enclosing Button. If the modifier sits at
            # a depth at or below that Button's own, the label closure has already
            # closed and the modifier is decorating the Button — where it expands
            # nothing and eats the taps around it.
            here = dep[i]
            j = i - 1
            while j >= 0 and i - j < 60:
                if BUTTON.search(strip(lines[j])):
                    if here <= dep[j]:
                        report(path, i, "touch-outside-label",
                               "applied OUTSIDE the Button's label (Button at :%d) - "
                               "expands nothing, and swallows neighbouring taps" % (j + 1),
                               raw)
                    break
                j -= 1

            # D-02. Scan forward only while the modifier chain continues.
            k = i + 1
            while k < len(lines):
                nxt = strip(lines[k]).strip()
                if not nxt:
                    k += 1
                    continue
                if not nxt.startswith("."):
                    break
                if CLIP.search(nxt):
                    report(path, i, "touch-before-clip",
                           "clipShape at :%d clips HIT TESTING as well as drawing, so "
                           "this expansion is silently undone - move it after the clip"
                           % (k + 1), raw)
                    break
                k += 1

        # D-04. `.fill` is only safe when the source's aspect is guaranteed to match
        # the container. Here it is not: an Xtream line carries no backdrop, so every
        # "background" is in practice a portrait poster.
        if "contentMode: .fill" in code or "aspectRatio(contentMode: .fill)" in code:
            for k in range(i + 1, min(i + 8, len(lines))):
                nxt = strip(lines[k]).strip()
                if not nxt:
                    continue
                if not nxt.startswith("."):
                    break
                if "ignoresSafeArea(" in nxt:
                    report(path, i, "fill-fullbleed",
                           "full-bleed .fill (ignoresSafeArea at :%d) - a source whose "
                           "aspect differs from the screen visibly stretches; use .fit, "
                           "or guarantee the aspect" % (k + 1), raw)
                    break

        # D-06. These two run against COMMENT-stripped text rather than fully stripped
        # text, because `strip` blanks whole string literals — and the contents of a
        # `\(...)` interpolation are CODE, not string. The proof harness caught this as
        # a blind spot: `Text("\(UIScreen.main.bounds.width)")` sailed through. Neither
        # pattern can plausibly appear inside a real user-facing message, so reading the
        # unblanked line costs nothing here.
        nostr = COMMENT.sub('', raw)
        if "UIScreen.main.bounds" in nostr and enclosing_decl(lines, i) != "s8kWindowSize":
            report(path, i, "banned-pattern",
                   "UIScreen.main.bounds is wrong in a split window - use S8KMetrics",
                   raw)
        # D-20. A formatter built in code never sees the app's injected locale, so it
        # follows the DEVICE — and on an Arabic device that means Arabic-Indic digits in
        # a product whose standing rule is Western digits in every language. The app
        # pins its numbering system once, in BlankTVApp; anything that builds its own
        # formatter opts out of that and has to say so explicitly.
        fm = FORMATTER.search(code)
        if fm:
            window = "".join(strip(lines[k]) for k in range(i, min(i + 6, len(lines))))
            if ".locale" not in window:
                report(path, i, "formatter-no-locale",
                       "%s() with no explicit .locale - it will follow the DEVICE and "
                       "render Arabic-Indic digits; pin en_US_POSIX or the app language"
                       % fm.group(1), raw)

        m = FOREACH.search(nostr)
        if m:
            report(path, i, "banned-pattern",
                   "ForEach(0..<%s) over a VARIABLE crashes when the count changes - "
                   "iterate the collection with a stable id" % m.group(1), raw)

    # D-06. GeometryReader as the ROOT of a body: it reports zero before layout, and a
    # foreground built inside one disappeared entirely because of it.
    for i, raw in enumerate(lines):
        if BODY.search(strip(raw)):
            for k in range(i + 1, min(i + 3, len(lines))):
                nxt = strip(lines[k]).strip()
                if not nxt:
                    continue
                if GEOROOT.match(nxt):
                    report(path, k, "banned-pattern",
                           "GeometryReader as the ROOT of a body - it reports zero "
                           "before layout; move it inside, or use S8KMetrics", lines[k])
                break


swift = [f for f in sorted(os.listdir(SRC)) if f.endswith(".swift")]
for name in swift:
    p = SRC + "/" + name
    check_file(p, io.open(p, encoding="utf-8").read().split("\n"))

if not findings:
    print("uilint: clean - %d file(s), 0 UI-rule violation(s)" % len(swift))
    sys.exit(0)

print("uilint: %d violation(s)\n" % len(findings))
for path, ln, rule, msg, src in findings:
    print("  %s:%d  [%s]" % (path, ln, rule))
    print("      %s" % msg)
    print("      %s" % src)
    print()
print("Each rule traces to a defect in DEFECTS.md. Fix it; do not suppress it.")
sys.exit(1)
