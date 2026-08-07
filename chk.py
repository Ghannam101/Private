#!/usr/bin/env python3
"""Pre-commit structural gate for the Swift sources.

HISTORY, recorded so this is not weakened again. The first version took files as
arguments and, run with none, silently checked NOTHING and exited 0. It also printed
its findings but ALWAYS exited 0, so `chk.py && build` would run the build on a broken
tree. Both bugs are why an entire 705-line file was once emptied and still "passed".

So: no arguments means the whole tree, a failure means a non-zero exit, and an
implausibly small source file is itself a failure — a truncated file balances its
(nonexistent) brackets perfectly.
"""
import os
import sys

# Windows consoles default to cp1252, which cannot encode Arabic — and this script
# prints Arabic store metadata. Without this the process dies INSIDE a print, after
# the API call succeeded, so the answer is fetched and then thrown away with a
# traceback. That is the brandlint defect again: a tool that fails on its own output
# reports nothing and looks like it found nothing.
sys.stdout.reconfigure(encoding="utf-8")

# A Swift file in this project is never legitimately this small. GatewayView.swift was
# truncated to 0 bytes and the old checker called it OK.
MIN_BYTES = 200


def strip(src):
    """Remove comments and string literals so only structure remains."""
    out = []
    i, n = 0, len(src)
    in_str = in_ml = in_lc = in_bc = False
    while i < n:
        c = src[i]
        nx = src[i + 1] if i + 1 < n else ''
        if in_lc:
            if c == '\n':
                in_lc = False
                out.append(c)
            i += 1
            continue
        if in_bc:
            if c == '*' and nx == '/':
                in_bc = False
                i += 2
                continue
            i += 1
            continue
        if in_ml:
            if src[i:i + 3] == '"""':
                in_ml = False
                i += 3
                continue
            i += 1
            continue
        if in_str:
            if c == '\\':
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if src[i:i + 3] == '"""':
            in_ml = True
            i += 3
            continue
        if c == '/' and nx == '/':
            in_lc = True
            i += 2
            continue
        if c == '/' and nx == '*':
            in_bc = True
            i += 2
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def check(path):
    """Return a failure description, or None when the file is sound."""
    size = os.path.getsize(path)
    if size < MIN_BYTES:
        return f"SUSPICIOUSLY SMALL ({size} bytes) — truncated?"
    s = strip(open(path, encoding='utf-8').read())
    stack = []
    opens = {'(': ')', '[': ']', '{': '}'}
    closes = {')': '(', ']': '[', '}': '{'}
    for ch in s:
        if ch in opens:
            stack.append(ch)
        elif ch in closes:
            if not stack or stack[-1] != closes[ch]:
                return f"MISMATCHED {ch}"
            stack.pop()
    if stack:
        return f"UNCLOSED {''.join(stack[-6:])}"
    return None


def main():
    paths = sys.argv[1:]
    if not paths:                       # no arguments = the whole tree, never nothing
        for root, _, files in os.walk("BlankTV"):
            paths += [os.path.join(root, f) for f in files if f.endswith(".swift")]
    if not paths:
        print("chk: no Swift files found — is this the repo root?", file=sys.stderr)
        return 2

    failures = 0
    for p in sorted(paths):
        problem = check(p)
        if problem:
            print(f"{p}: {problem}")
            failures += 1
    print(f"chk: {len(paths)} file(s), {failures} problem(s)")
    return 1 if failures else 0         # a failure must FAIL, so `chk && build` is real


if __name__ == "__main__":
    sys.exit(main())
