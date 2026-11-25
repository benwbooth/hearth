#!/usr/bin/env python3
"""The AppImage catalogs as one survey source: AppImageHub
(appimage.github.io/feed.json) and AM/AppMan (github.com/ivan-hc/AM, its
x86_64-appimages list and install scripts), without duplicates, ranked by
GitHub stars.

Writes data/appimages_apps.tsv (apps.tsv's columns, source "appimage",
attr "appimage:<key>") and data/appimages.json (key -> how to download:
{"repo": "owner/name"} for GitHub releases, or {"url": ...}). Nothing is
downloaded here; menu-probe.py downloads each AppImage when it tests it and
deletes it afterwards.

Usage: fetch_appimages.py   (catalogs cached in ~/.cache/hearth-menu-survey/catalogs)
Needs `gh` (GitHub's GraphQL API for the star counts: public data).
"""
import csv
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CAT = os.path.expanduser("~/.cache/hearth-menu-survey/catalogs")
SKIP_REPOS = re.compile(r"^(ivan-hc/AM|AppImage/appimagetool|AppImage/AppImageKit|probonopd/.*|pkgforge.*|"
                        r"AppImageCommunity/.*|ivan-hc/.*-appimage)$", re.I)


def norm(name):
    return re.sub(r"[^a-z0-9]+", "", name.lower())


def appimagehub():
    fn = os.path.join(CAT, "appimagehub-feed.json")
    if not os.path.exists(fn):
        urllib.request.urlretrieve("https://appimage.github.io/feed.json", fn)
    out = []
    for it in json.load(open(fn))["items"]:
        repo = next((l["url"] for l in it.get("links") or [] if l.get("type") == "GitHub"), "")
        dl = next((l["url"] for l in it.get("links") or [] if l.get("type") == "Download"), "")
        out.append(dict(name=it["name"], repo=repo.strip("/"), url=dl, desc=it.get("description") or "",
                        categories=",".join(c for c in (it.get("categories") or []) if c), src="appimagehub"))
    return out


def am():
    d = os.path.join(CAT, "am")
    if not os.path.isdir(d):
        subprocess.run(["git", "clone", "-q", "--depth", "1", "https://github.com/ivan-hc/AM.git", d], check=True)
    out = []
    for line in open(os.path.join(d, "programs", "x86_64-appimages"), encoding="utf-8", errors="replace"):
        m = re.match(r"◆ (\S+) : (.*)", line.strip())
        if not m:
            continue
        name, desc = m.groups()
        try:
            text = open(os.path.join(d, "programs", "x86_64", name), errors="replace").read()
        except OSError:
            continue
        repos = [r for r in re.findall(r"(?:api\.github\.com/repos|github\.com)/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)", text)
                 if not SKIP_REPOS.match(r.removesuffix(".git"))]
        urls = re.findall(r"https?://[^\s\"'()]*\.[Aa]pp[Ii]mage\b", text)
        repo = repos[0].removesuffix(".git") if repos else ""
        out.append(dict(name=name, repo=repo, url=urls[0] if urls and not repo else "", desc=desc,
                        categories="", src="am"))
    return out


def stars(repos):
    """{owner/name: stars} through GitHub's GraphQL API, 80 per query."""
    res = {}
    repos = sorted(set(repos))
    for i in range(0, len(repos), 80):
        chunk = repos[i:i + 80]
        parts = []
        for j, r in enumerate(chunk):
            o, n = r.split("/", 1)
            parts.append(f'r{j}: repository(owner: {json.dumps(o)}, name: {json.dumps(n)}) {{ stargazerCount }}')
        q = "query { " + " ".join(parts) + " }"
        p = subprocess.run(["gh", "api", "graphql", "-f", f"query={q}"], capture_output=True, text=True)
        try:
            data = json.loads(p.stdout).get("data") or {}
        except ValueError:
            data = {}
        for j, r in enumerate(chunk):
            v = data.get(f"r{j}")
            if v:
                res[r.lower()] = v["stargazerCount"]
        print(f"stars {min(i + 80, len(repos))}/{len(repos)}", file=sys.stderr, flush=True)
    return res


def main():
    merged = {}
    for it in appimagehub() + am():
        key = it["repo"].lower() if it["repo"] else "name:" + norm(it["name"])
        # Same app under another key (AM without a repo, Hub with one)?
        alias = "name:" + norm(it["name"])
        cur = merged.get(key) or merged.get(alias)
        if cur is None:
            merged[key] = dict(it, srcs={it["src"]})
            if key != alias:
                merged.setdefault(alias, merged[key])
            continue
        cur["srcs"].add(it["src"])
        for f in ("repo", "url", "desc", "categories"):
            cur[f] = cur[f] or it[f]
    apps = {id(v): v for v in merged.values()}.values()
    st = stars([a["repo"] for a in apps if a["repo"]])
    rows, how = [], {}
    for a in apps:
        a["stars"] = st.get(a["repo"].lower(), 0) if a["repo"] else 0
    hdr = open(os.path.join(ROOT, "data", "apps.tsv")).readline().rstrip("\n").split("\t")
    ranked = sorted(apps, key=lambda a: (-a["stars"], a["name"].lower()))
    for n, a in enumerate(ranked):
        key = re.sub(r"[^A-Za-z0-9_.+-]+", "-", a["repo"] or a["name"]).strip("-").lower()
        attr = "appimage:" + key
        if not (a["repo"] or a["url"]):
            continue
        how[attr] = {"repo": a["repo"]} if a["repo"] else {"url": a["url"]}
        r = {k: "" for k in hdr}
        r.update(rank=str(200000 + n), attr=attr, include="1", source="appimage", kind="app",
                 pop=f"{a['stars'] / 1000:.3f}", arch="0", debian="0", flathub_pct="0", flathub_installs="0",
                 unfree="0", note=f"{'+'.join(sorted(a['srcs']))} stars={a['stars']} {a['repo'] or a['url']}",
                 desc=(a["desc"] or a["name"]).replace("\t", " ").replace("\n", " ")[:200])
        rows.append(r)
    with open(os.path.join(ROOT, "data", "appimages_apps.tsv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=hdr, delimiter="\t", lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    json.dump(how, open(os.path.join(ROOT, "data", "appimages.json"), "w"), indent=0)
    print(f"{len(rows)} AppImages ({sum(1 for r in rows if 'appimagehub' in r['note'])} on AppImageHub, "
          f"{sum(1 for r in rows if 'am' in r['note'].split()[0].split('+'))} in AM)", file=sys.stderr)


if __name__ == "__main__":
    main()
