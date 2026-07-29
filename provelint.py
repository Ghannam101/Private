"""Prove uilint.py catches what it claims — D-16.

`chk.py` once passed a whole session while verifying nothing, because nobody made it
fail on purpose. A gate is not trusted here until the defect it claims to catch has
been reinstated on a scratch copy and observed to fail.

Each case below is a real defect from DEFECTS.md, written into a throwaway file, run
through the linter, and checked for the expected rule. Then the clean tree is run
again to confirm no false positives were introduced.
"""
import io
import os
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")

SRC = "BlankTV"
PROBE = SRC + "/ZZUILintProbe.swift"

CASES = [
    ("touch-outside-label", '''import SwiftUI
struct ProbeA: View {
    var body: some View {
        Button(action: {}) {
            Image(systemName: "star")
                .frame(width: 30, height: 30)
        }
        .s8kMinTouch(7)
    }
}
'''),
    ("touch-before-clip", '''import SwiftUI
struct ProbeB: View {
    var body: some View {
        Button(action: {}) {
            Text("hi")
                .padding(8)
                .s8kMinTouch(4)
                .clipShape(Capsule())
        }
    }
}
'''),
    ("fill-fullbleed", '''import SwiftUI
struct ProbeC: View {
    var body: some View {
        S8KImage(url: "x", contentMode: .fill)
            .ignoresSafeArea()
    }
}
'''),
    ("banned-pattern", '''import SwiftUI
struct ProbeD: View {
    var body: some View {
        Text("\\(UIScreen.main.bounds.width)")
    }
}
'''),
    ("banned-pattern", '''import SwiftUI
struct ProbeE: View {
    let n = 3
    var body: some View {
        ForEach(0..<n, id: \\.self) { _ in Text("x") }
    }
}
'''),
    ("banned-pattern", '''import SwiftUI
struct ProbeF: View {
    var body: some View {
        GeometryReader { geo in
            Text("\\(geo.size.width)")
        }
    }
}
'''),
]


def run():
    r = subprocess.run([sys.executable, "uilint.py"], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout or "") + (r.stderr or "")


code, out = run()
if code != 0:
    print("ABORT: the tree is not clean before probing.\n" + out)
    sys.exit(2)
print("baseline: clean\n")

ok = True
for rule, body in CASES:
    io.open(PROBE, "w", encoding="utf-8", newline="\n").write(body)
    code, out = run()
    caught = code == 1 and rule in out
    label = body.split("struct ")[1].split(":")[0].strip()
    print("  %-22s %-8s %s" % (rule, label, "CAUGHT" if caught else "MISSED  <-- gate is blind"))
    if not caught:
        ok = False
        print(out)
    os.remove(PROBE)

code, out = run()
print("\nafter probing:", "clean" if code == 0 else "DIRTY\n" + out)
print("\nRESULT:", "every rule proven" if ok and code == 0 else "GATE NOT TRUSTWORTHY")
sys.exit(0 if ok and code == 0 else 1)
