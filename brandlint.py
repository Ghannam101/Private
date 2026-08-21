#!/usr/bin/env python3
"""Brand lint — find every piece of identity that still lives outside S8KBrand.

The point of an identity kit is that re-skinning is ONE edit. That promise decays
silently: the next hard-coded colour or the next `Image("Logo")` costs nothing today
and costs an afternoon at the next rebrand. This turns the decay into a visible list.

Run: python brandlint.py        (exit 1 if anything is loose)
"""
import io
import os
import re
import sys

# Windows consoles default to cp1252, which cannot encode Arabic — and this script
# prints Arabic store metadata. Without this the process dies INSIDE a print, after
# the API call succeeded, so the answer is fetched and then thrown away with a
# traceback. That is the brandlint defect again: a tool that fails on its own output
# reports nothing and looks like it found nothing.
sys.stdout.reconfigure(encoding="utf-8")

SRC = "BlankTV"

# DesignSystem.swift IS the design system: the palette definitions, the semantic colour
# tokens and the kit itself all legitimately hold literals there. Flagging them would
# train everyone to ignore this tool, which is worse than not having it.
PALETTE_HOME = "DesignSystem.swift"
HOME_EXEMPT = {"raw colour", "product name", "logo asset"}

def shipped_name():
    """The product name as S8KBrand declares it, read at run time.

    It was hard-coded here as "Blank Prime". That is the very decay this tool exists
    to catch, occurring inside the tool: the identity moved to Trex TV and this check
    went on hunting a name the app no longer wore, then reported CLEAN over a codebase
    it was not really inspecting. A linter that quietly stops looking is worse than no
    linter, because it is believed.
    """
    src = io.open(os.path.join(SRC, "DesignSystem.swift"), encoding="utf-8").read()
    m = re.search(r'static let name\s*=\s*"([^"]+)"', src)
    if not m:
        print("brandlint: cannot find S8KBrand.name — refusing to report clean",
              file=sys.stderr)
        sys.exit(2)
    return m.group(1)


NAME = shipped_name()
# The full name with flexible spacing, plus each word of it on its own — the wordmark
# is rendered in two halves (shortName + markSuffix), so half of it hard-coded
# somewhere is the same defect as the whole of it.
_parts = [re.escape(w) for w in NAME.split() if len(w) > 2]
_alts = [re.escape(NAME).replace(r"\ ", r"\s*")] + _parts
NAME_PATTERN = r'"[^"\n]*(?:' + "|".join(_alts) + r')[^"\n]*"'

CHECKS = [
    # (label, regex, why it matters)
    ("product name",
     re.compile(NAME_PATTERN),
     "the name must come from S8KBrand.name"),
    ("logo asset",
     re.compile(r'Image\(\s*"Logo"\s*\)'),
     "use Image(S8KBrand.logoAsset)"),
    ("raw colour",
     re.compile(r'Color\(\s*(?:red:|hex:)'),
     "every colour resolves through BrandTheme.active"),
    ("ink on an accent surface",
     re.compile(r'foregroundColor\(\s*\.s8kBlack\s*\)|tint\(\s*\.s8kBlack\s*\)'),
     "text drawn ON the accent must use S8KBrand.accentInk, or a dark accent hides it"),
]


def strip_comments(line):
    return re.sub(r'//.*$', '', line)


def main():
    findings = []
    for root, _, files in os.walk(SRC):
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            path = os.path.join(root, f).replace("\\", "/")
            is_home = f == PALETTE_HOME
            for i, raw in enumerate(io.open(path, encoding="utf-8").read().split("\n"), 1):
                line = strip_comments(raw)
                for label, pat, why in CHECKS:
                    if is_home and label in HOME_EXEMPT:
                        continue
                    if pat.search(line):
                        findings.append((path, i, label, why, line.strip()[:72]))

    if not findings:
        print("brandlint: clean — identity is fully inside S8KBrand")
        return 0

    by_label = {}
    for p, i, label, why, src in findings:
        by_label.setdefault(label, []).append((p, i, src, why))
    print(f"brandlint: {len(findings)} identity literal(s) outside the kit\n")
    for label, rows in sorted(by_label.items(), key=lambda kv: -len(kv[1])):
        print(f"— {label}  ({len(rows)}) — {rows[0][3]}")
        for p, i, src, _ in rows[:40]:
            print(f"    {p}:{i}  {src}")
        if len(rows) > 40:
            print(f"    ... and {len(rows) - 40} more")
        print()
    return 1


if __name__ == "__main__":
    sys.exit(main())
