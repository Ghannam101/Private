"""ascreview.py — write the App Review Detail record, and nothing else.

Separate from ascwrite.py on purpose. That one owns the STORE CARD, the thing customers
read. This owns the note the reviewer reads, and the two fail differently: a wrong
subtitle is embarrassing, a wrong review note is a rejection and a week.

Why this record matters more here than for most apps. Trex TV opens on a screen asking
for a server address, a username and a password — because it is a player for a
subscription the user already has. A reviewer has none of those. The only way in without
credentials is a button labelled "Browse as Guest (Demo)", and it sits in the FOOTER as
muted text, deliberately: the design allows exactly one accent-filled element on that
screen and it is the sign-in button. That is a good design decision and a bad discovery
path for someone who has ninety seconds and a rejection template open. The note below is
what closes that gap, so it names the button, its exact label, and where it is.

Every claim in the note was checked against the source before it was written. Nothing
here describes a feature that does not exist, and nothing links to a page that is not yet
live — a privacy URL that 404s during review is worse than an empty field, which at least
blocks submission honestly instead of failing it.

    python ascreview.py <ISSUER_ID>            show what is there now
    python ascreview.py <ISSUER_ID> write      create or update the record
"""
import io
import json
import os
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")

import jwt  # noqa: E402

KEY_ID = "5C527D55JX"
KEY_PATH = os.path.join("..", "Strong8K", "iOS", "AuthKey_5C527D55JX.p8")
API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6789773663"          # Trex TV — com.blanktv.player

# ── The record ───────────────────────────────────────────────────────────────
# Contact: the owner. Apple phones this number if a reviewer needs a human, so it is his
# real one and not a support alias, and the email is the account holder's own — a support
# address that has never been proven to receive mail is not a place to send a reviewer.
CONTACT_FIRST = "Ghannam"
CONTACT_LAST = "Alajmi"
CONTACT_PHONE = "+966550050311"
CONTACT_EMAIL = "gr7.alajmi@gmail.com"

# No account exists to hand over. The app has no user accounts at all — the demo is a
# button, not a login — so this is false and the note explains the way in instead.
DEMO_REQUIRED = False

NOTES = """WHAT THIS APP IS

Trex TV is a media player. It does not provide, host, sell or bundle any content,
channels or subscriptions, and it ships with no channel list of its own. Everything the
user sees comes from an IPTV service they already subscribe to and enter themselves,
using either Xtream Codes credentials or an M3U playlist URL. We operate no servers and
no user accounts.

HOW TO REVIEW IT WITHOUT A SUBSCRIPTION

No account or credentials are needed.

On the first screen, at the BOTTOM of the page, tap the text button:

    "Browse as Guest (Demo)"

That opens the complete app with a built-in sample catalogue, so every screen and the
full player can be exercised with no sign-in: live channels, movies, series, search,
downloads, subtitles, audio tracks, playback speed, parental controls and settings.

The sample content is openly licensed and is streamed from public sources: short films
released by the Blender Foundation via archive.org, and public HLS test streams. It is
included solely so the app can be reviewed and evaluated without a subscription.

LANGUAGE

The app follows the device language and supports Arabic, English, French, Turkish and
Spanish. On an English-language device it opens in English. The language can also be
changed directly from the first screen using the globe control at the top, and from
Settings at any time.

AGE RATING

Rated 17+. The app itself contains no objectionable material, but the content it plays
is supplied by a third-party provider that we neither control nor curate, so the rating
reflects what a user could reach through their own subscription rather than what we ship.

PRIVACY

No data is collected. There are no analytics, no tracking and no advertising SDKs, and
the app contains no code that transmits anything to us — we run no servers. The user's
provider credentials are stored in the device Keychain and are sent only to that
provider's own server. Watch history, favourites and downloads never leave the device.

THIRD-PARTY SOFTWARE

MobileVLCKit (LGPL v2.1), GRDB.swift (MIT) and ThumbHash (MIT). Full licence texts,
copyright notices, and links to VLCKit's licence and source are inside the app under
Settings > Licences & Attribution.

CONTACT

Any question during review: gr7.alajmi@gmail.com
"""


def token(issuer):
    import time
    now = int(time.time())
    payload = {"iss": issuer, "iat": now, "exp": now + 19 * 60,
               "aud": "appstoreconnect-v1"}
    with io.open(KEY_PATH) as f:
        key = f.read()
    return jwt.encode(payload, key, algorithm="ES256",
                      headers={"kid": KEY_ID, "typ": "JWT"})


def call(path, tok, payload=None, method="GET"):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Authorization": "Bearer " + tok,
                 "Content-Type": "application/json"},
        method=method)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            body = r.read().decode()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        print("   HTTP %d" % e.code)
        try:
            for err in json.loads(body).get("errors", []):
                print("      %s | %s" % (err.get("title"), err.get("detail")))
        except Exception:
            print("      " + body[:400])
        return None


def version_id(tok):
    vs = call("/apps/%s/appStoreVersions?limit=1" % APP_ID, tok)
    if not vs or not vs["data"]:
        print("no version found"); return None, None
    v = vs["data"][0]
    return v["id"], v["attributes"]["versionString"]


def show(tok, vid):
    d = call("/appStoreVersions/%s/appStoreReviewDetail" % vid, tok)
    if not d or not d.get("data"):
        print("   (no review detail record yet)")
        return None
    a = d["data"]["attributes"]
    for k in ["contactFirstName", "contactLastName", "contactPhone", "contactEmail",
              "demoAccountRequired"]:
        print("   %-22s %s" % (k, a.get(k)))
    n = a.get("notes") or ""
    print("   %-22s %d chars" % ("notes", len(n)))
    print("   " + "-" * 60)
    for line in n.split("\n")[:6]:
        print("   | " + line)
    if len(n.split("\n")) > 6:
        print("   | …")
    return d["data"]["id"]


ATTRS = {
    "contactFirstName": CONTACT_FIRST,
    "contactLastName": CONTACT_LAST,
    "contactPhone": CONTACT_PHONE,
    "contactEmail": CONTACT_EMAIL,
    "demoAccountRequired": DEMO_REQUIRED,
    "notes": NOTES.strip(),
}


def write(tok, vid, existing):
    if existing:
        print("\nUPDATING existing record %s" % existing)
        r = call("/appStoreReviewDetails/%s" % existing, tok,
                 {"data": {"type": "appStoreReviewDetails", "id": existing,
                           "attributes": ATTRS}}, method="PATCH")
    else:
        print("\nCREATING a new record")
        r = call("/appStoreReviewDetails", tok,
                 {"data": {"type": "appStoreReviewDetails", "attributes": ATTRS,
                           "relationships": {"appStoreVersion": {
                               "data": {"type": "appStoreVersions", "id": vid}}}}},
                 method="POST")
    return r is not None


def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    tok = token(sys.argv[1])
    vid, vstr = version_id(tok)
    if not vid:
        return 1
    print("VERSION %s (%s)\n\nBEFORE:" % (vstr, vid))
    existing = show(tok, vid)

    if len(sys.argv) > 2 and sys.argv[2] == "write":
        if not write(tok, vid, existing):
            print("\nWRITE FAILED — nothing was changed"); return 1
        print("\nAFTER (read back from Apple, not echoed):")
        show(tok, vid)
    else:
        print("\n(read-only — pass 'write' to apply)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
