"""ascwrite.py — write the store card, one field at a time, and read it back.

Companion to asc.py, which only ever reads. This one CHANGES the owner's live App Store
Connect record, so it is deliberately narrow: every write is a named command, nothing runs
by default, and every write is followed by a read-back that prints what the server now
holds. A write nobody verified is a write nobody made.

Usage, from the repo root:
    python ascwrite.py <ISSUER_ID> show          what is there now
    python ascwrite.py <ISSUER_ID> name          name + subtitle
    python ascwrite.py <ISSUER_ID> rating        the age-rating declaration
    python ascwrite.py <ISSUER_ID> listing       description + keywords
    python ascwrite.py <ISSUER_ID> urls <base>   supportUrl + privacyPolicyUrl on <base>

`urls` is separate and takes an argument on purpose: those two fields need a domain that
actually resolves, Apple opens them during review, and the owner has not settled his yet.
Nothing here invents a URL.
"""
import json
import os
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")

APP_ID = "6789773663"          # Trex TV
LOCALE = "ar-SA"

# ── The copy. Kept here, in one place, so a change is reviewable as a diff. ──────

SUBTITLE = "مشغّل قنوات · IPTV Player"

KEYWORDS = ("iptv,player,مشغل,اشتراك,افلام,مسلسلات,بث,مباشر,قنوات,"
            "xtream,m3u,بلاير,تلفزيون,بلانك")

APP_NAME = "Blank Premium"

DESCRIPTION = """Blank Premium — مشغّل وسائط للآيفون والآيباد، مبنيّ للسرعة والوضوح.

أدخل اشتراكك الخاص (Xtream Codes أو رابط M3U) وستجد مكتبتك منظّمة أمامك: أفلام ومسلسلات وقنوات مباشرة، بواجهة عربية مصمَّمة لتُقرأ من مسافة الأريكة.

• مكتبتك كاملة في مكان واحد — أفلام، مسلسلات، بثّ مباشر
• يفتح على ما تركته: متابعة المشاهدة من حيث توقّفت
• الحلقة التالية تبدأ وحدها، وتخطّي المقدّمة بضغطة
• نافذة عائمة، ومؤقّت نوم، وبحث فوري في مكتبة كبيرة
• تنزيل للمشاهدة بلا اتصال
• رقابة أبوية برمز سرّي
• خمس لغات: العربية والإنجليزية والفرنسية والتركية والإسبانية
• وضع تجريبي تجرّبه قبل أن تُدخل اشتراكك

ملاحظة مهمة
Blank Premium مشغّل فقط. لا يوفّر ولا يستضيف أي قنوات أو أفلام أو محتوى، ولا يأتي بأي محتوى مدمج. يلزمك اشتراك خاص من مزوّد مرخّص، وأنت وحدك مسؤول عن اشتراكك وعن مشروعية ما تصل إليه.

الخصوصية
لا نجمع بياناتك لأغراض التتبّع أو الإعلانات. يمكنك حذف حسابك وبياناتك من داخل التطبيق في أي وقت."""

# Mirrors what the owner's LIVE app declared and Apple accepted five times. The two that
# matter are unrestrictedWebAccess and parentalControls: this app plays whatever stream the
# user supplies, and hiding that is a rejection in itself.
#
# EVERY key must be present. The endpoint rejects a partial PATCH with a 409 listing the
# eighteen it did not receive — it is a full declaration, not a diff. The four non-default
# values are the whole point:
#   unrestrictedWebAccess  the app plays whatever stream the user supplies. Declaring
#                          otherwise is a rejection in itself.
#   parentalControls       there is a PIN and a rating lock, and saying so is what earns
#                          17+ rather than a higher band.
#   the two INFREQUENT_OR_MILD entries mirror what the owner's live app declared and Apple
#                          accepted five times — this is a proven answer, not a guess.
RATING = {
    # NO. Declared YES by mirroring the live sibling without checking whether the field
    # applies here — and it does not: WKWebView, SFSafariViewController, WebKit and
    # SafariServices appear ZERO times in 21,834 lines. The app plays streams through
    # AVPlayer and VLC; it has no browser. Declaring unrestricted web access an app does
    # not have is an inaccurate rating questionnaire under 2.3, and it was caught by an
    # adversarial review pass, not by the person who wrote it.
    "unrestrictedWebAccess":                       False,
    "parentalControls":                            True,
    "gunsOrOtherWeapons":                          "INFREQUENT_OR_MILD",
    "violenceCartoonOrFantasy":                    "INFREQUENT_OR_MILD",
    # 17+ is RAISED here rather than earned by answering a question dishonestly.
    #
    # With unrestrictedWebAccess correctly NO, the questionnaire computes 9+ — and 9+ is
    # wrong for this product, because the app plays whatever stream the user's provider
    # sends and that content is not rated by anyone. No field in the questionnaire
    # describes "third-party video of unknown rating", so the accurate answers stay
    # accurate and the rating is lifted with the instrument Apple provides for exactly
    # this. Declaring a browser we do not have to reach the same number would be a false
    # answer that happens to land on the right rating.
    "ageRatingOverride":                           "SEVENTEEN_PLUS",
    "advertising":                                 False,
    "ageAssurance":                                False,
    "contests":                                    "NONE",
    "gambling":                                    False,
    "gamblingSimulated":                           "NONE",
    "lootBox":                                     False,
    "messagingAndChat":                            False,
    "userGeneratedContent":                        False,
    "alcoholTobaccoOrDrugUseOrReferences":         "NONE",
    "healthOrWellnessTopics":                      False,
    "horrorOrFearThemes":                          "NONE",
    "matureOrSuggestiveThemes":                    "NONE",
    "medicalOrTreatmentInformation":               "NONE",
    "profanityOrCrudeHumor":                       "NONE",
    "sexualContentGraphicAndNudity":               "NONE",
    "sexualContentOrNudity":                       "NONE",
    "violenceRealistic":                           "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
}

# ────────────────────────────────────────────────────────────────────────────────

import time
try:
    import jwt
except ImportError:
    print("PyJWT is required"); sys.exit(2)

KEY_ID = "5C527D55JX"
KEY_PATH = os.path.join(".secrets", "AuthKey_%s.p8" % KEY_ID)
API = "https://api.appstoreconnect.apple.com/v1/"


def token(issuer):
    with open(KEY_PATH) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 19 * 60,
                       "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def call(path, tok, payload=None, method="GET"):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"},
        method=method)
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            body = r.read().decode()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        print("HTTP %d on %s %s" % (e.code, method, path))
        try:
            for err in json.loads(e.read().decode()).get("errors", []):
                print("   %s: %s" % (err.get("title"), err.get("detail")))
        except Exception:
            pass
        return None


def ids(tok):
    """The three record ids every write below needs."""
    infos = call("apps/%s/appInfos" % APP_ID, tok)
    info = infos["data"][0]["id"]
    loc = call("appInfos/%s/appInfoLocalizations?limit=20" % info, tok)
    infoLoc = next((l["id"] for l in loc["data"]
                    if l["attributes"].get("locale") == LOCALE), None)
    rating = call("appInfos/%s/ageRatingDeclaration" % info, tok)
    ratingId = rating["data"]["id"] if rating and rating.get("data") else None
    vers = call("apps/%s/appStoreVersions?limit=5" % APP_ID, tok)
    editable = next((v for v in vers["data"]
                     if v["attributes"].get("appStoreState") == "PREPARE_FOR_SUBMISSION"),
                    vers["data"][0])
    vl = call("appStoreVersions/%s/appStoreVersionLocalizations" % editable["id"], tok)
    verLoc = next((l["id"] for l in vl["data"]
                   if l["attributes"].get("locale") == LOCALE), None)
    return infoLoc, ratingId, verLoc


def show(tok):
    infoLoc, ratingId, verLoc = ids(tok)
    a = call("appInfoLocalizations/%s" % infoLoc, tok)["data"]["attributes"]
    print("NAME     :", a.get("name"))
    print("SUBTITLE :", a.get("subtitle") or "— empty —")
    print("PRIVACY  :", a.get("privacyPolicyUrl") or "— empty —  (blocks submission)")
    b = call("appStoreVersionLocalizations/%s" % verLoc, tok)["data"]["attributes"]
    d = b.get("description") or ""
    print("DESC     :", ("%d chars" % len(d)) if d else "— empty —  (blocks submission)")
    print("KEYWORDS :", b.get("keywords") or "— empty —")
    print("SUPPORT  :", b.get("supportUrl") or "— empty —  (blocks submission)")
    r = call("ageRatingDeclarations/%s" % ratingId, tok) if ratingId else None
    if r:
        set_ = {k: v for k, v in r["data"]["attributes"].items()
                if v not in (None, False, "NONE")}
        print("RATING   :", set_ if set_ else "— NOT DECLARED —  (blocks submission)")
    return 0


def patch(tok, kind, rec_id, attrs):
    out = call("%s/%s" % (kind, rec_id), tok,
               {"data": {"type": kind, "id": rec_id, "attributes": attrs}}, "PATCH")
    if out is None:
        print("   FAILED — nothing was changed")
        return 1
    print("   written. reading back:")
    back = call("%s/%s" % (kind, rec_id), tok)["data"]["attributes"]
    for k in attrs:
        v = back.get(k)
        v = ("%d chars" % len(v)) if isinstance(v, str) and len(v) > 70 else v
        print("      %-26s %s" % (k, v))
    return 0


def main():
    if len(sys.argv) < 3:
        print(__doc__); return 2
    issuer, cmd = sys.argv[1], sys.argv[2]
    if not os.path.exists(KEY_PATH):
        print("missing key:", KEY_PATH); return 2
    tok = token(issuer)
    infoLoc, ratingId, verLoc = ids(tok)

    if cmd == "show":
        return show(tok)
    if cmd == "name":
        print("name + subtitle ->")
        return patch(tok, "appInfoLocalizations", infoLoc,
                     {"name": APP_NAME, "subtitle": SUBTITLE})
    if cmd == "rating":
        print("age rating ->")
        return patch(tok, "ageRatingDeclarations", ratingId, RATING)
    if cmd == "listing":
        print("description + keywords ->")
        return patch(tok, "appStoreVersionLocalizations", verLoc,
                     {"description": DESCRIPTION, "keywords": KEYWORDS})
    if cmd == "urls":
        if len(sys.argv) < 4:
            print("usage: ascwrite.py <ISSUER> urls https://example.com")
            return 2
        base = sys.argv[3].rstrip("/")
        print("support + privacy on", base, "->")
        rc = patch(tok, "appStoreVersionLocalizations", verLoc,
                   {"supportUrl": base})
        return rc or patch(tok, "appInfoLocalizations", infoLoc,
                           {"privacyPolicyUrl": base + "/privacy"})
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
