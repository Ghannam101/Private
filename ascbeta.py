#!/usr/bin/env python3
"""ascbeta.py — put a build in front of testers, and prove it landed.

Why it exists: the external group carrying the PUBLIC TestFlight link had
`hasAccessToAllBuilds: null` — that flag only applies to internal groups, so an
external group never picks up a new build by itself. Ours sat on build 110 from
July while ten newer builds shipped past it, and nothing anywhere said so. Anyone
opening the public link was installing a two-week-old binary.

Companion to asc_beta.py, which only ever reads. This one CHANGES what testers can
install, so it is deliberately narrow, like ascwrite.py: one command, nothing runs
by default, and every write is followed by a read-back. A write nobody verified is
a write nobody made.

Usage, from the repo root:
    python ascbeta.py <ISSUER_ID> show                    groups, links, and their builds
    python ascbeta.py <ISSUER_ID> add <GROUP> <BUILD_NO>  add one build to one group
    python ascbeta.py <ISSUER_ID> add <GROUP> latest      ... or whatever is newest

GROUP is matched on the group's name, exactly as App Store Connect spells it.

EXTERNAL GROUPS NEED BETA REVIEW. Apple will refuse a build that has not cleared
it, and the refusal is reported here rather than swallowed — a link that silently
keeps serving the old build is the failure this tool was written for.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

# Windows consoles default to cp1252 and this prints Arabic group names. Without
# this the process dies INSIDE a print, after the call succeeded — the answer is
# fetched and then thrown away with a traceback.
sys.stdout.reconfigure(encoding="utf-8")

KEY_ID = "5C527D55JX"
KEY_PATH = os.path.join(".secrets", "AuthKey_%s.p8" % KEY_ID)
APP_ID = "6789773663"
BASE = "https://api.appstoreconnect.apple.com/v1/"


def token(issuer):
    with open(KEY_PATH) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 19 * 60,
                       "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def call(path, tok, payload=None, method="GET"):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + tok,
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode()
            return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as e:
        print("HTTP %d on %s %s" % (e.code, method, path))
        try:
            for err in json.loads(e.read().decode()).get("errors", []):
                print("   %s: %s" % (err.get("title"), err.get("detail")))
        except Exception:
            pass
        raise SystemExit(1)


def groups(tok):
    return call("apps/%s/betaGroups?limit=50" % APP_ID, tok)["data"]


def builds(tok, limit=25):
    return call("apps/%s/builds?limit=%d&sort=-version" % (APP_ID, limit), tok)["data"]


def group_builds(tok, gid):
    d = call("betaGroups/%s/builds?limit=200" % gid, tok)["data"]
    return sorted((b["attributes"].get("version") for b in d),
                  key=lambda v: int(v) if str(v).isdigit() else -1, reverse=True)


def show(tok):
    for g in groups(tok):
        a = g["attributes"]
        kind = "internal" if a.get("isInternalGroup") else "external"
        print("%-16s %-9s link=%s" % (a.get("name"), kind, a.get("publicLink") or "—"))
        have = group_builds(tok, g["id"])
        print("   builds: %s" % (", ".join(have[:12]) or "NONE"))


def add(tok, group_name, want):
    g = next((x for x in groups(tok) if x["attributes"].get("name") == group_name), None)
    if g is None:
        print("no group named %r. Names on this app:" % group_name)
        for x in groups(tok):
            print("   %s" % x["attributes"].get("name"))
        raise SystemExit(1)

    bs = builds(tok)
    if want == "latest":
        b = bs[0]
    else:
        b = next((x for x in bs if x["attributes"].get("version") == str(want)), None)
        if b is None:
            print("build %s is not among the %d most recent." % (want, len(bs)))
            raise SystemExit(1)

    ver = b["attributes"].get("version")
    state = b["attributes"].get("processingState")
    print("group : %s (%s)" % (group_name, g["id"]))
    print("build : %s  processing=%s" % (ver, state))
    # A build Apple is still processing cannot be distributed, and adding it fails
    # with an error that reads like a permissions problem. Say the real reason here.
    if state != "VALID":
        print("   refusing: Apple has not finished processing this build yet.")
        raise SystemExit(1)

    before = group_builds(tok, g["id"])
    call("betaGroups/%s/relationships/builds" % g["id"], tok, method="POST",
         payload={"data": [{"type": "builds", "id": b["id"]}]})

    after = group_builds(tok, g["id"])
    print("   written. reading back:")
    print("      before: %s" % (", ".join(before[:8]) or "NONE"))
    print("      after : %s" % (", ".join(after[:8]) or "NONE"))
    if ver in after:
        print("   OK — build %s is now on %s" % (ver, a_link(g)))
    else:
        print("   FAILED — the group still does not list build %s" % ver)
        raise SystemExit(1)


def a_link(g):
    return g["attributes"].get("publicLink") or "(no public link on this group)"


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    issuer, cmd = sys.argv[1], sys.argv[2]
    tok = token(issuer)
    if cmd == "show":
        show(tok)
        return 0
    if cmd == "add" and len(sys.argv) == 5:
        add(tok, sys.argv[3], sys.argv[4])
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
