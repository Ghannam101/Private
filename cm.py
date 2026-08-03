"""cm.py — ask Codemagic, instead of reading a web page over someone's shoulder.

Companion to asc.py. That one asks Apple what it received; this one asks Codemagic what
it built, and can start a build. Between them there is no step in the pipeline we have to
guess at, which is the whole point — this project has twice drawn a wrong conclusion from
a UI instead of an API.

The token is a SECRET and lives in .secrets/codemagic_token (gitignored). It is never
printed, never passed on a command line, and never committed.

Usage, from the repo root:
    python cm.py apps                 list apps and their workflow ids
    python cm.py builds [n]           the n most recent builds (default 8)
    python cm.py build <id>           one build in detail, with the failing step's log url
    python cm.py start [branch]       START a build (default branch: main)

`start` is the only command that changes anything, and it is deliberately explicit —
Apple caps TestFlight uploads per day and this project has already hit that ceiling once.
"""
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.codemagic.io"
TOKEN_PATH = os.path.join(".secrets", "codemagic_token")
WORKFLOW = "ios-release"          # matches codemagic.yaml
# Codemagic names the app after the REPOSITORY, and this repo is `Private` — not
# "blank" or "BlankTV". Matched against the repo url too, so a display-name change
# still finds it. The other app on this account is strong8k-ios: do not build that one.
APP_HINT = "ghannam101/private"


def token():
    with open(TOKEN_PATH) as f:
        return f.read().strip()


def call(path, payload=None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"x-auth-token": token(), "Content-Type": "application/json"},
        method="POST" if payload is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        print("HTTP %d on %s" % (e.code, path))
        print("   " + body[:600])
        return None


def find_app():
    data = call("/apps")
    if not data:
        return None
    apps = data.get("applications", data if isinstance(data, list) else [])
    for a in apps:
        name = (a.get("appName") or "").lower()
        repo = json.dumps(a.get("repository", {})).lower()
        if APP_HINT in name or APP_HINT in repo:
            return a
    return apps[0] if apps else None


def show_builds(limit):
    app = find_app()
    if not app:
        print("no app found")
        return 1
    data = call("/builds?appId=%s&limit=%d" % (app["_id"], limit))
    if not data:
        return 1
    print("BUILDS — %s" % app.get("appName"))
    for b in data.get("builds", []):
        # `version` is only present once the build has produced one, so a running
        # build shows a blank there rather than a lie.
        print("   %-24s %-11s %-16s %s"
              % (b.get("_id"), b.get("status"), b.get("workflowId", ""),
                 b.get("startedAt", "")))
        if b.get("version"):
            print("        version %s" % b["version"])
    return 0


def show_build(build_id):
    data = call("/builds/%s" % build_id)
    if not data:
        return 1
    b = data.get("build", data)
    print("BUILD %s" % build_id)
    print("   status  :", b.get("status"))
    print("   branch  :", b.get("branch"))
    print("   started :", b.get("startedAt"))
    print("   message :", b.get("message"))
    # The top-level message says only "Publishing failed" or similar. The real error
    # lives in the failing action's own log, and that is what this prints the url for.
    for a in b.get("buildActions", []) or []:
        st = a.get("status")
        mark = "  <-- FAILED" if st not in ("success", "skipped", None) else ""
        print("   step %-28s %s%s" % (a.get("name"), st, mark))
        if mark:
            print("        log: %s/builds/%s/step/%s" % (API, build_id, a.get("_id")))
    return 0


def start(branch):
    app = find_app()
    if not app:
        print("no app found")
        return 1
    print("starting %s on %s / branch %s" % (WORKFLOW, app.get("appName"), branch))
    data = call("/builds", {"appId": app["_id"],
                            "workflowId": WORKFLOW,
                            "branch": branch})
    if not data:
        return 1
    bid = data.get("buildId")
    print("buildId:", bid)
    print("watch  : python cm.py build %s" % bid)
    return 0


def main():
    if not os.path.exists(TOKEN_PATH):
        print("missing token:", TOKEN_PATH)
        return 2
    cmd = sys.argv[1] if len(sys.argv) > 1 else "builds"
    if cmd == "apps":
        data = call("/apps")
        if not data:
            return 1
        for a in data.get("applications", []):
            print("%-28s %s" % (a.get("appName"), a.get("_id")))
            for w in (a.get("workflows") or {}).values():
                print("    workflow: %s" % w.get("name"))
        return 0
    if cmd == "builds":
        return show_builds(int(sys.argv[2]) if len(sys.argv) > 2 else 8)
    if cmd == "build":
        return show_build(sys.argv[2])
    if cmd == "start":
        return start(sys.argv[2] if len(sys.argv) > 2 else "main")
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
