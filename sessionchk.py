"""sessionchk.py — the session-state invariants, enforced.

One rule so far, and it exists because the defect it catches shipped to a device and was
reported by the owner: sign out, move between a real subscription and the demo, and the
subscription would not take.

The cause was not in any screen. `Store.demoMode` had ONE writer setting it true
(`enterDemo`) and two setting it false (`logout`, `deleteAccount`) — while FIVE separate
functions made a real account active and none of them said the demo was over. Entering an
account from inside the demo left the flag standing, and `Store.isDemo` short-circuits
eleven content accessors, so every screen kept answering with `DemoContent` while the app
believed it had signed the user in. Nothing looked broken; nothing the account fetched was
ever displayed.

That is not a bug a UI linter can see, and it is not a bracket problem. It is an
invariant: THE ACTIVE PLAYLIST AND THE DEMO FLAG MOVE TOGETHER, ALWAYS. So it is checked
where it lives — in the one function allowed to change either.

  activate-only     Every non-nil write to `Store.shared.activePlaylistID` is inside
                    `AuthService.activate(playlistID:)`. A sixth caller written next year
                    cannot quietly reintroduce the defect.
  activate-clears   `activate` itself still clears `demoMode`, and still does it BEFORE
                    setting the id. Order is load-bearing: `reloadScopedCaches` reads
                    `scopeID`, which reads `demoMode`, so clearing it afterwards reloads
                    every scoped cache into the "demo" bucket anyway.

D-16 applies: a gate is not trusted here until the defect it claims to catch has been
reinstated and observed to fail. That proof is built in — `selftest()` runs both rules
against a synthetic source carrying the original defect and against a fixed one, and the
tool refuses to report on the real tree unless the broken sample fails and the fixed one
passes.

Run from the repo root:  python sessionchk.py     (exit 1 on any finding)
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

SRC = "BlankTV"

# `(?!=)` is not decoration. Without it this matched `activePlaylistID == id` — the
# COMPARISON that opens deletePlaylist — because `\s*=\s*` happily takes the first half
# of `==` and captures `= id` as the assigned value. The first run against the real tree
# reported two violations and both were this rule's fault, not the app's. Both shapes are
# in the self-test below now, so the rule can never quietly regain either.
ACTIVE_WRITE = re.compile(r'Store\.shared\.activePlaylistID\s*=(?!=)\s*(.+)$')
DEMO_CLEAR = re.compile(r'Store\.shared\.demoMode\s*=\s*false')
ACTIVATE_DECL = re.compile(r'\bfunc\s+activate\s*\(\s*playlistID\s*:')


def decomment(line):
    """Drop a trailing // comment. Crude on purpose — no string literal in this file's
    rules can contain //, and a smarter parser would be more to get wrong."""
    return line.split("//", 1)[0]


def activate_span(lines):
    """(start, end) line indices of activate(playlistID:), or None.

    Brace counting, not indentation: this file is checked by a tool, and a tool that
    trusts whitespace is one reformat away from reporting nothing."""
    for i, raw in enumerate(lines):
        if not ACTIVATE_DECL.search(decomment(raw)):
            continue
        depth = 0
        started = False
        for j in range(i, len(lines)):
            code = decomment(lines[j])
            for ch in code:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
            if started and depth <= 0:
                return (i, j)
        return (i, len(lines) - 1)
    return None


def check_source(name, text):
    """Both rules against one file's text. Returns a list of (line, rule, message)."""
    lines = text.split("\n")
    out = []
    span = activate_span(lines)

    for i, raw in enumerate(lines):
        m = ACTIVE_WRITE.search(decomment(raw))
        if not m:
            continue
        # `= nil` is deactivation, not activation: the last playlist was deleted and
        # nothing is active. It must NOT clear the demo flag, so it is not required to
        # live inside activate().
        # Trailing `}` too: `else { Store.shared.activePlaylistID = nil }` is one line,
        # and without stripping it the captured value is `nil }`, which is not "nil".
        if m.group(1).strip().strip("};").strip() == "nil":
            continue
        if span is None or not (span[0] <= i <= span[1]):
            out.append((i + 1, "activate-only",
                        "activePlaylistID written outside activate(playlistID:) — the "
                        "demo flag will survive into a real account and every content "
                        "accessor keeps returning DemoContent"))

    if span is not None:
        body = lines[span[0]:span[1] + 1]
        clear_at = next((k for k, l in enumerate(body) if DEMO_CLEAR.search(decomment(l))), None)
        set_at = next((k for k, l in enumerate(body)
                       if ACTIVE_WRITE.search(decomment(l))), None)
        if clear_at is None:
            out.append((span[0] + 1, "activate-clears",
                        "activate(playlistID:) no longer clears demoMode — this is the "
                        "whole point of the function"))
        elif set_at is not None and clear_at > set_at:
            out.append((span[0] + clear_at + 1, "activate-clears",
                        "demoMode cleared AFTER activePlaylistID — reloadScopedCaches "
                        "reads scopeID, which reads demoMode, so every scoped cache "
                        "reloads into the \"demo\" bucket"))
    return out


BROKEN = '''
final class AuthService {
    func loginXtream() async {
        Store.shared.activePlaylistID = Store.shared.upsertPlaylist(pl)
        reloadScopedCaches()
    }
    func activate(playlistID: String) {
        Store.shared.demoMode = false
        Store.shared.activePlaylistID = playlistID
        reloadScopedCaches()
    }
}
'''

MISORDERED = '''
final class AuthService {
    func activate(playlistID: String) {
        Store.shared.activePlaylistID = playlistID
        Store.shared.demoMode = false
        reloadScopedCaches()
    }
}
'''

FIXED = '''
final class AuthService {
    func loginXtream() async {
        activate(playlistID: Store.shared.upsertPlaylist(pl))
    }
    func deletePlaylist(_ id: String) {
        let wasActive = Store.shared.activePlaylistID == id
        if wasActive {
            if let next = list.first { switchPlaylist(next) }
            else { Store.shared.activePlaylistID = nil }
        }
    }
    func activate(playlistID: String) {
        Store.shared.demoMode = false          // must precede the scope read below
        Store.shared.activePlaylistID = playlistID
        reloadScopedCaches()
    }
}
'''


def selftest():
    """Prove both rules before trusting either. D-16."""
    cases = [
        ("the original defect", BROKEN, "activate-only"),
        ("cleared too late", MISORDERED, "activate-clears"),
    ]
    for label, src, want in cases:
        rules = {r for _, r, _ in check_source("<selftest>", src)}
        if want not in rules:
            print("sessionchk SELFTEST FAILED: %s not caught by %s" % (label, want))
            return False
    if check_source("<selftest>", FIXED):
        print("sessionchk SELFTEST FAILED: the fixed sample was flagged")
        return False
    return True


def main():
    if not selftest():
        print("refusing to report on the real tree with an unproven rule")
        return 2

    findings = []
    names = [f for f in sorted(os.listdir(SRC)) if f.endswith(".swift")]
    for name in names:
        p = os.path.join(SRC, name)
        for ln, rule, msg in check_source(p, io.open(p, encoding="utf-8").read()):
            findings.append((p, ln, rule, msg))

    if not findings:
        print("sessionchk: clean - %d file(s), rules proven, 0 violation(s)" % len(names))
        return 0

    print("sessionchk: %d violation(s)\n" % len(findings))
    for p, ln, rule, msg in findings:
        print("  %s:%d  [%s]" % (p, ln, rule))
        print("      %s\n" % msg)
    return 1


if __name__ == "__main__":
    sys.exit(main())
