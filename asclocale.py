#!/usr/bin/env python3
"""asclocale.py — add the English store card, because the reviewer reads English.

Why it exists: `ar-SA` was the ONLY localization on this record, on both levels.
The name, subtitle, description and keywords were all Arabic, for an app in the
category App Review scrutinises hardest. A reviewer who cannot read the card is a
reviewer who asks questions or declines, and neither is a good outcome for a
listing that is otherwise ready.

ar-SA stays the PRIMARY locale — that is the product's first audience and nothing
here changes it. This adds en-US alongside it.

Companion to ascwrite.py, and deliberately the same shape: one command, nothing
runs by default, every write followed by a read-back. A write nobody verified is a
write nobody made.

Usage, from the repo root:
    python asclocale.py <ISSUER_ID> show      what locales exist, on both levels
    python asclocale.py <ISSUER_ID> en        create or update the en-US card

Two levels, and they hold different fields — a detail worth stating because
getting it wrong writes to the wrong record:
    appInfoLocalizations         name, subtitle, privacyPolicyUrl
    appStoreVersionLocalizations description, keywords, supportUrl, whatsNew
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

sys.stdout.reconfigure(encoding="utf-8")

KEY_ID = "5C527D55JX"
KEY_PATH = os.path.join(".secrets", "AuthKey_%s.p8" % KEY_ID)
APP_ID = "6789773663"
BASE = "https://api.appstoreconnect.apple.com/v1/"
LOCALE = "en-US"

# ── The English copy. One place, so a change is reviewable as a diff. ────────────
#
# Written to mirror the Arabic rather than translate it word for word, and every
# claim in it is one the binary actually keeps. The disclaimer paragraph is not
# decoration: Guideline 5.2.3 turns on whether the app supplies content, and this
# is where we say plainly that it supplies none.

NAME = "Blank Premium"
SUBTITLE = "IPTV Player for your line"          # 25 / 30

# 100-char ceiling. No spaces after commas — Apple counts them.
KEYWORDS = "iptv,m3u,xtream,player,playlist,stream,live tv,movies,series,epg,vod,channels"

DESCRIPTION = """Blank Premium is a media player for iPhone and iPad, built for speed and clarity.

Sign in with your own subscription — Xtream Codes or an M3U link — and your library arrives organised: films, series and live channels, in an interface designed to be read from across the room.

• Your whole library in one place — films, series, live TV
• Opens where you left off, and resumes mid-episode
• Next episode starts on its own; skip the intro with one tap
• Picture in picture, a sleep timer, and instant search across a large catalogue
• Download for offline viewing
• Parental controls with a PIN
• Five languages: Arabic, English, French, Turkish and Spanish
• A demo mode you can try before entering any subscription

IMPORTANT
Blank Premium is a player, and only a player. It does not provide or host any channels, films or content of any kind, and ships with none built in. You need your own subscription from a licensed provider, and you alone are responsible for that subscription and for the legality of what you access through it.

PRIVACY
We collect nothing for tracking or advertising. Your provider sign-in details stay on your device. You can delete your account and your data from inside the app at any time."""


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


def records(tok):
    info = call("apps/%s/appInfos" % APP_ID, tok)["data"][0]["id"]
    vers = call("apps/%s/appStoreVersions?limit=5" % APP_ID, tok)["data"]
    ver = next((v for v in vers
                if v["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION"), vers[0])
    return info, ver["id"]


def show(tok):
    info, ver = records(tok)
    print("appInfoLocalizations (name / subtitle / privacyPolicyUrl)")
    for l in call("appInfos/%s/appInfoLocalizations?limit=20" % info, tok)["data"]:
        a = l["attributes"]
        print("   %-8s name=%r subtitle=%r privacy=%s"
              % (a.get("locale"), a.get("name"), a.get("subtitle"),
                 a.get("privacyPolicyUrl") or "EMPTY"))
    print("appStoreVersionLocalizations (description / keywords / supportUrl)")
    for l in call("appStoreVersions/%s/appStoreVersionLocalizations?limit=20" % ver, tok)["data"]:
        a = l["attributes"]
        print("   %-8s desc=%dch kw=%dch support=%s"
              % (a.get("locale"), len(a.get("description") or ""),
                 len(a.get("keywords") or ""), a.get("supportUrl") or "EMPTY"))


def upsert(tok, kind, parent_rel, parent_id, attrs, existing):
    """PATCH when the locale is already there, POST when it is not."""
    if existing:
        call("%s/%s" % (kind, existing), tok, method="PATCH",
             payload={"data": {"type": kind, "id": existing, "attributes": attrs}})
        return existing
    out = call(kind, tok, method="POST", payload={"data": {
        "type": kind, "attributes": dict(attrs, locale=LOCALE),
        "relationships": {parent_rel: {"data": {"type": parent_rel + "s"
                                                if not parent_rel.endswith("s") else parent_rel,
                                                "id": parent_id}}}}})
    return out["data"]["id"]


def english(tok):
    # Fail BEFORE writing anything if the copy breaks Apple's limits — a 409 halfway
    # through leaves one level written and the other not.
    assert len(NAME) <= 30, "name is %d chars" % len(NAME)
    assert len(SUBTITLE) <= 30, "subtitle is %d chars" % len(SUBTITLE)
    assert len(KEYWORDS) <= 100, "keywords are %d chars" % len(KEYWORDS)
    assert len(DESCRIPTION) <= 4000, "description is %d chars" % len(DESCRIPTION)

    info, ver = records(tok)
    have_info = next((l["id"] for l in call("appInfos/%s/appInfoLocalizations?limit=20" % info, tok)["data"]
                      if l["attributes"].get("locale") == LOCALE), None)

    print("app level    ->", "updating" if have_info else "creating", LOCALE)
    upsert(tok, "appInfoLocalizations", "appInfo", info,
           {"name": NAME, "subtitle": SUBTITLE}, have_info)

    # RE-READ, and the order matters. Creating the app-level localization makes Apple
    # create the matching appStoreVersionLocalization for the same locale as a side
    # effect. Checking for it BEFORE that write returns nothing, and the POST then
    # fails with "Entity with locale: en-US already exists. Try updating." — a 409 that
    # reads like a bug in the caller and is really a stale read.
    have_ver = next((l["id"] for l in call("appStoreVersions/%s/appStoreVersionLocalizations?limit=20" % ver, tok)["data"]
                     if l["attributes"].get("locale") == LOCALE), None)

    print("version level->", "updating" if have_ver else "creating", LOCALE)
    upsert(tok, "appStoreVersionLocalizations", "appStoreVersion", ver,
           {"description": DESCRIPTION, "keywords": KEYWORDS}, have_ver)

    print("\nreading back:")
    show(tok)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    tok = token(sys.argv[1])
    if sys.argv[2] == "show":
        show(tok)
        return 0
    if sys.argv[2] == "en":
        english(tok)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
