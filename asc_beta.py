"""asc_beta.py — why a VALID build is not reaching a tester.

`asc.py` proved Apple's side is fine: build 109 is VALID, not PROCESSING, and export
compliance is answered. So the build is not stuck — it is not being DISTRIBUTED. That
is a TestFlight configuration question, and this asks it directly:

  * do any beta groups exist on this app at all
  * is each group internal or external, and does it auto-add new builds
  * which testers are in them
  * which groups is the newest build actually assigned to

Usage:  python asc_beta.py <ISSUER_ID>
"""
import json
import os
import sys
import time
import urllib.request

import jwt

# Group and tester names can be Arabic; the default Windows console encoding
# cannot render them and takes the whole run down with it.
sys.stdout.reconfigure(encoding="utf-8")

KEY_ID = "5C527D55JX"
KEY_PATH = os.path.join(".secrets", "AuthKey_%s.p8" % KEY_ID)
APP_ID = "6789773663"


def token(issuer):
    with open(KEY_PATH) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 19 * 60,
                       "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def get(path, tok):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/" + path,
                                 headers={"Authorization": "Bearer " + tok})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        print("HTTP %d on /%s" % (e.code, path))
        try:
            for err in json.loads(e.read().decode()).get("errors", []):
                print("   %s: %s" % (err.get("title"), err.get("detail")))
        except Exception:
            pass
        return None


def main():
    if len(sys.argv) < 2:
        print("usage: python asc_beta.py <ISSUER_ID>")
        return 2
    tok = token(sys.argv[1])

    print("BETA GROUPS")
    groups = get("apps/%s/betaGroups?limit=50" % APP_ID, tok)
    if not groups or not groups["data"]:
        print("   NONE. That is the answer: with no group, a VALID build has nobody")
        print("   to go to. Create an Internal Testing group and add yourself.")
    else:
        for g in groups["data"]:
            a = g["attributes"]
            print("   %-28s internal:%-5s auto-add-new-builds:%-5s public-link:%s"
                  % (a.get("name"), a.get("isInternalGroup"),
                     a.get("hasAccessToAllBuilds"), a.get("publicLinkEnabled")))
            t = get("betaGroups/%s/betaTesters?limit=50" % g["id"], tok)
            if t is not None:
                if not t["data"]:
                    print("      testers: NONE")
                for x in t["data"]:
                    xa = x["attributes"]
                    print("      tester: %s %s <%s>  state:%s"
                          % (xa.get("firstName") or "", xa.get("lastName") or "",
                             xa.get("email"), xa.get("state")))

    # Apple refuses GET on builds/{id}/betaGroups ("does not allow GET_RELATED"),
    # so ask from the group side instead — and ask each build for its own
    # distribution state, which is the field that actually decides delivery.
    print("\nWHICH BUILDS EACH GROUP HAS")
    if groups:
        for g in groups["data"]:
            # This relationship rejects `sort` — take what it gives, unordered.
            gb = get("betaGroups/%s/builds?limit=200" % g["id"], tok)
            vers = [b["attributes"].get("version") for b in gb["data"]] if gb else None
            print("   %-28s %s" % (g["attributes"].get("name"),
                                   ", ".join(vers) if vers else
                                   ("none" if gb else "unreadable")))

    print("\nPER-BUILD DISTRIBUTION STATE")
    builds = get("builds?filter[app]=%s&limit=3&sort=-uploadedDate" % APP_ID, tok)
    if builds:
        for b in builds["data"]:
            v = b["attributes"].get("version")
            d = get("builds/%s/buildBetaDetail" % b["id"], tok)
            if d and d.get("data"):
                a = d["data"]["attributes"]
                print("   build %-5s internal:%-22s external:%-22s auto-notify:%s"
                      % (v, a.get("internalBuildState"),
                         a.get("externalBuildState"), a.get("autoNotifyEnabled")))
            # External groups cannot receive a build until beta review passes.
            s = get("builds/%s/betaAppReviewSubmission" % b["id"], tok)
            if s and s.get("data"):
                print("         beta review: %s"
                      % s["data"]["attributes"].get("betaReviewState"))
            else:
                print("         beta review: NOT SUBMITTED")

    print("\nAPP-LEVEL BETA STATE")
    d = get("apps/%s/betaAppReviewDetail" % APP_ID, tok)
    if d:
        print("   beta review detail present:", bool(d.get("data")))
    lo = get("apps/%s/betaAppLocalizations?limit=5" % APP_ID, tok)
    if lo:
        print("   beta localizations:", len(lo["data"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
