"""asc.py — read this app's real state straight from App Store Connect.

Why it exists: we kept inferring TestFlight state from Codemagic logs and from what
the owner could see on a web page. This asks Apple.

Auth needs three things and only one of them is secret:
  Key ID     on the App Store Connect integrations page (not secret)
  Issuer ID  a UUID at the top of that same page (not secret)
  .p8 key    downloadable once, at creation (SECRET — kept in .secrets/, gitignored)

Usage, from the repo root:
    python asc.py <ISSUER_ID>

Prints: the app record, which PLATFORMS are enabled (the Mac / Vision Pro question),
and every recent build with its real processing state and export-compliance flag.
"""
import json
import os
import sys
import time
import urllib.request

import jwt

# Windows consoles default to cp1252, which cannot encode Arabic — and this script
# prints Arabic store metadata. Without this the process dies INSIDE a print, after
# the API call succeeded, so the answer is fetched and then thrown away with a
# traceback. That is the brandlint defect again: a tool that fails on its own output
# reports nothing and looks like it found nothing.
sys.stdout.reconfigure(encoding="utf-8")

KEY_ID = "5C527D55JX"
KEY_PATH = os.path.join(".secrets", "AuthKey_%s.p8" % KEY_ID)
BUNDLE_HINT = "blank"          # substring match, so a bundle-id rename still finds it


def token(issuer):
    with open(KEY_PATH, "r") as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": issuer, "iat": now, "exp": now + 19 * 60,
               "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256",
                      headers={"kid": KEY_ID, "typ": "JWT"})


def get(path, tok):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/" + path,
        headers={"Authorization": "Bearer " + tok})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        print("HTTP %d on /%s" % (e.code, path))
        try:
            for err in json.loads(body).get("errors", []):
                print("   %s: %s" % (err.get("title"), err.get("detail")))
        except Exception:
            print("   " + body[:400])
        return None


def main():
    if len(sys.argv) < 2:
        print("usage: python asc.py <ISSUER_ID>")
        return 2
    if not os.path.exists(KEY_PATH):
        print("missing key:", KEY_PATH)
        return 2

    tok = token(sys.argv[1])

    apps = get("apps?limit=200", tok)
    if apps is None:
        return 1
    match = [a for a in apps["data"]
             if BUNDLE_HINT in (a["attributes"].get("bundleId") or "").lower()
             or BUNDLE_HINT in (a["attributes"].get("name") or "").lower()]
    if not match:
        print("no app matched %r. All apps on this account:" % BUNDLE_HINT)
        for a in apps["data"]:
            print("   %-40s %s" % (a["attributes"].get("name"),
                                   a["attributes"].get("bundleId")))
        return 1

    app = match[0]
    at = app["attributes"]
    print("APP")
    print("   name      :", at.get("name"))
    print("   bundle    :", at.get("bundleId"))
    print("   sku       :", at.get("sku"))
    print("   id        :", app["id"])

    # The Mac / Vision Pro question, answered rather than asked.
    infos = get("apps/%s/appInfos" % app["id"], tok)
    if infos:
        for i in infos["data"]:
            a = i["attributes"]
            print("   state     :", a.get("appStoreState"), "| age:", a.get("appStoreAgeRating"))

    print("\nPLATFORMS ENABLED")
    for plat in ("IOS", "MAC_OS", "VISION_OS", "TV_OS"):
        v = get("apps/%s/appStoreVersions?filter[platform]=%s&limit=1"
                % (app["id"], plat), tok)
        n = len(v["data"]) if v else 0
        print("   %-10s %s" % (plat, "YES - has versions" if n else "no"))

    # Metadata blockers live on Apple's side, not in the repo. Asking beats guessing.
    print("\nSTORE METADATA READINESS")
    if infos:
        for i in infos["data"]:
            ar = get("appInfos/%s/ageRatingDeclaration" % i["id"], tok)
            if ar and ar.get("data"):
                a = ar["data"]["attributes"]
                answered = [k for k, v in a.items() if v not in (None, "NONE", False)]
                print("   age rating   : %s"
                      % ("declared (%d fields set)" % len(answered) if answered
                         else "NOT DECLARED"))
            loc = get("appInfos/%s/appInfoLocalizations?limit=20" % i["id"], tok)
            if loc:
                for l in loc["data"]:
                    a = l["attributes"]
                    print("   locale %-6s name=%r privacyPolicyUrl=%s"
                          % (a.get("locale"), a.get("name"),
                             a.get("privacyPolicyUrl") or "MISSING"))

    # This relationship rejects `sort`; the editable version is the one we want anyway.
    vers = get("apps/%s/appStoreVersions?limit=5" % app["id"], tok)
    if vers and vers["data"]:
        v = vers["data"][0]
        print("   version      : %s (%s)"
              % (v["attributes"].get("versionString"),
                 v["attributes"].get("appStoreState")))
        vl = get("appStoreVersions/%s/appStoreVersionLocalizations?limit=20" % v["id"], tok)
        if vl:
            for l in vl["data"]:
                a = l["attributes"]
                d = a.get("description") or ""
                print("   %-6s desc:%-5s keywords=%r"
                      % (a.get("locale"),
                         "%dch" % len(d) if d else "EMPTY",
                         a.get("keywords")))
                # No "IPTV" tripwire here. This account's LIVE app ships
                # "IPTV Player" in its subtitle and "iptv" as a keyword, and has
                # passed review five times — most recently 2026-07-27. The word
                # is not the trigger; unlicensed content and artwork are.

    print("\nRECENT BUILDS")
    builds = get("builds?filter[app]=%s&limit=10&sort=-uploadedDate" % app["id"], tok)
    if builds:
        for b in builds["data"]:
            a = b["attributes"]
            print("   build %-6s %-12s expires:%-6s compliance:%s  %s"
                  % (a.get("version"),
                     a.get("processingState"),
                     a.get("expired"),
                     a.get("usesNonExemptEncryption"),
                     a.get("uploadedDate")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
