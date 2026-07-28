"""Catch the bug that actually broke the build: a name declared INSIDE a closure and
used after that closure has ended.

The earlier audit looked for "a declaration somewhere above, in the same type". That
passes `let isFav = …` written inside a Button's label and referenced on the modifier
below it — which is exactly what failed to compile. The only way to see it is to track
BRACE DEPTH: a binding introduced at a deeper depth than the line using it is gone.
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

STRING = re.compile(r'"(?:[^"\\]|\\.)*"')
IDENT = re.compile(r'\b([a-z][A-Za-z0-9_]*)\b')
DECL = re.compile(r'\b(?:let|var)\s+([a-z][A-Za-z0-9_]*)\b')
KNOWN = {"true", "false", "nil", "if", "else", "self", "isEmpty", "count", "L"}


def depths(lines):
    """Brace depth AT THE START of each line, comments and strings ignored."""
    out, d = [], 0
    for raw in lines:
        line = STRING.sub('""', re.sub(r'//.*$', '', raw))
        out.append(d)
        d += line.count("{") + line.count("(") - line.count("}") - line.count(")")
    return out


findings = []
for f in sorted(os.listdir("BlankTV")):
    if not f.endswith(".swift"):
        continue
    path = f"BlankTV/{f}"
    lines = io.open(path, encoding="utf-8").read().split("\n")
    dep = depths(lines)
    for i, raw in enumerate(lines):
        if ".accessibilityLabel(" not in raw:
            continue
        arg = STRING.sub('""', raw.split(".accessibilityLabel(", 1)[1])
        used = {m.group(1) for m in IDENT.finditer(arg)} - KNOWN
        used = {n for n in used if not re.search(r'\.\s*' + n + r'\b', arg)}
        here = dep[i]
        # walk up to the top of the enclosing declaration
        j = i - 1
        while j >= 0 and not re.match(r'^(private |public |final )?(struct|enum|extension|class|final class|actor) ', lines[j]):
            m = DECL.search(STRING.sub('""', re.sub(r'//.*$', '', lines[j])))
            if m and m.group(1) in used and dep[j] > here:
                findings.append((path, i + 1, m.group(1), j + 1, dep[j], here,
                                 raw.strip()[:66]))
                used.discard(m.group(1))
            j -= 1

if not findings:
    print("depth audit: no label uses a binding from a closed scope")
else:
    print(f"depth audit: {len(findings)} OUT-OF-SCOPE use(s)\n")
    for p, ln, n, dl, dd, hd, src in findings:
        print(f"  {p}:{ln}  '{n}' declared at :{dl} (depth {dd}) but used at depth {hd}")
        print(f"      {src}")
sys.exit(1 if findings else 0)
