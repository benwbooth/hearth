#!/usr/bin/env python3
"""Build the ranked app list: nixpkgs GUI apps + Flathub-only apps, by popularity.

Inputs (data/raw, fetched by scripts/fetch_sources.sh; data/desktop_entries.jsonl
from scripts/fetch_desktop.py):
  nixlocate_desktop.tsv   attr<TAB>/nix/store/.../share/applications/X.desktop
                          (nix-locate over the nix-index db = what cache.nixos.org
                          has built: free, prebuilt packages)
  ../nixpkgs_meta.tsv     every nixpkgs attr incl. unfree (nix-env -qa --meta)
  flathub_popular.jsonl   every Flathub app with installs_last_month
  pkgstats_*.json         Arch pkgstats: popularity = % of submitting systems
  popcon_by_inst.gz       Debian popcon (installs; "vote" is unreliable on noatime systems)

App universe: a nixpkgs attr with at least one desktop entry that is
Type=Application, not NoDisplay/Hidden, not a demo/test entry. Terminal=true
entries are kept but marked kind=tui (the terminal's menu covers them, so they
are left out of the coverage percentages). Flathub apps that match no nixpkgs
app are added as source=flathub; Flathub apps matching an unfree or uncached
nixpkgs attr are added as source=nixpkgs-unfree / nixpkgs-uncached.

Popularity, as an estimated "% of Linux desktops with it installed":
  arch    pkgstats popularity (a %), but only for packages whose name is the
          app's (not a library that ships a demo, e.g. gtk3) -- see LIB below
  debian  popcon inst / submissions * 100
  flathub installs_last_month mapped to % by a log-log fit against Arch % over
          apps in both (capped at 100)
pop = max of the three (each source misses some apps: Arch has no proprietary
apps, Flathub misses what distros ship, Debian is server-heavy).

Output: data/apps.tsv, best first.
"""
import glob
import gzip
import json
import math
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RAW = os.path.join(ROOT, "data", "raw")

SKIP_PREFIX = re.compile(
    r"^(tests\.|haskellPackages|python3\d*Packages|perl\d*Packages|ocamlPackages|"
    r"rPackages|vimPlugins|emacsPackages|nodePackages|luaPackages|lua\d|chickenPackages|"
    r"coqPackages|linuxKernel|pkgsCross|pkgsi686Linux|pkgsStatic|pkgsMusl|pkgsLLVM|"
    r"libsForQt5\.|plasma5Packages\.|qt5\.|qt6\.|gnome2\.|sgt-puzzles-mobile|"
    r"gnomeExtensions\.|openraPackages|libretro\.|godotPackages|.*Packages_\d|"
    r"(haskell|python|perl|ocaml|r|lua|node|emacs|vim|coq|chicken|idris|agda|beam|elm|julia|dotnet|php|ruby|go|rust|nim|tcl|octave|sbcl|lisp|texlive)Packages\.)")
VARIANT = re.compile(r"(-unwrapped|-with-plugins|-with-packages|-full|-bin|-wayland|-qt[56]?|-gtk[234]?|"
                     r"-nox|-minimal|-beta|-dev|-nightly|-git|-insiders|-fhs|-wrapped|-flutter|-esr)$")
DEMO = re.compile(r"(demo|widget-factory|icon-browser|example|test|debug|-viewer-qt$|uninstall)", re.I)
# Packages that are libraries/frameworks/system services: their Arch/Debian
# install counts say nothing about the app (gtk3 -> gtk3-demo, cups -> printer
# settings). They keep only Flathub numbers.
LIB = re.compile(r"^(lib|gtk[234]?$|gtk\+|qt[56]?|kdePackages\.(k[a-z]+addons|kio|kwallet|kirigami|kaccounts|"
                 r"knewstuff|kguiaddons|kded|kcmutils|kconfig|kdeclarative|frameworkintegration|kinit|"
                 r"kservice|kglobalaccel|kactivities|plasma-workspace|polkit-kde-agent|kdeconnect-kde$)|"
                 r"cups|geoclue|v4l-utils|xdg-|zenity|pinentry|snappy|gst_all_1|glib|dconf|pipewire|"
                 r"pulseaudio$|networkmanager|bluez|ibus$|fcitx5$|wine.*\.base|ffmpeg|imagemagick|ghostscript|"
                 r"util-linux|file$|xterm$|nvidia|mesa|vulkan|gnupg|python3$|perl$|openjdk|jdk|jre)")


def norm(s):
    s = re.sub(r"\.desktop$", "", s.lower())
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def leaf(attr):
    return attr.rsplit(".", 1)[-1]


def domain_of(app_id):
    p = app_id.lower().split(".")
    return ".".join(reversed(p[:2])) if len(p) >= 3 else ""


def load():
    meta = {}
    with open(os.path.join(ROOT, "data", "nixpkgs_meta.tsv")) as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            meta[p[0]] = dict(attr=p[0], pname=p[1], version=p[2], unfree=p[3] == "1",
                              broken=p[4] == "1", linux=p[5] == "1", main=p[6],
                              homepage=p[7].lower(), desc=p[8])
    arch = {}
    for fn in glob.glob(os.path.join(RAW, "pkgstats_*.json")):
        for x in json.load(open(fn))["packagePopularities"]:
            arch[x["name"]] = float(x["popularity"])
    deb, subs = {}, 0
    with gzip.open(os.path.join(RAW, "popcon_by_inst.gz"), "rt", errors="replace") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            p = line.split()
            if p[0].isdigit() and len(p) > 3 and p[1] != "Total":
                # inst, not vote: vote needs atime, which noatime systems lack
                # (vlc: 45102 inst, 152 vote, 43551 no-files).
                deb[p[1]] = int(p[2])
                subs = max(subs, int(p[2]))  # debconf: on every system
    deb = {k: v * 100.0 / subs for k, v in deb.items()}
    flat = [json.loads(l) for l in open(os.path.join(RAW, "flathub_popular.jsonl"))]
    entries = {}
    dp = os.path.join(ROOT, "data", "desktop_entries.jsonl")
    for l in open(dp):
        j = json.loads(l)
        entries[j["path"]] = j
    return meta, arch, deb, flat, entries


def entry_kind(e):
    """'app', 'tui' or None (not a launchable app)."""
    if not e or "error" in e:
        return "app"  # unknown: keep
    if e.get("Type", "Application") != "Application":
        return None
    if e.get("NoDisplay", "").lower() == "true" or e.get("Hidden", "").lower() == "true":
        return None
    name = os.path.basename(e["path"])
    if DEMO.search(name) or DEMO.search(e.get("Name", "")):
        return None
    if e.get("Terminal", "").lower() == "true":
        return "tui"
    return "app"


def main():
    meta, arch, deb, flat, entries = load()
    apps = {}
    by_store = {}
    for line in open(os.path.join(RAW, "nixlocate_desktop.tsv")):
        attr, path = line.rstrip("\n").split("\t")
        if not attr.endswith(".out"):
            continue
        attr = attr[:-4]
        if SKIP_PREFIX.match(attr):
            continue
        kind = entry_kind(entries.get(path))
        if kind is None:
            continue
        store = "/".join(path.split("/")[:4])
        a = apps.setdefault(attr, dict(attr=attr, store=store, desktops=[], kinds=set(), source="nixpkgs"))
        a["desktops"].append(path)
        a["kinds"].add(kind)
        by_store.setdefault(store, []).append(attr)
    for store, attrs in by_store.items():
        keep = min(attrs, key=lambda a: (a.count("."), len(a)))
        for a in attrs:
            if a != keep:
                apps.pop(a, None)
    # foo-unwrapped / foo-esr / foo-bin next to foo, godotPackages_4_5.godot
    # next to godot: one app, the plain attr.
    plain = {}
    for attr in list(apps):
        base = norm(VARIANT.sub("", leaf(attr)))
        plain.setdefault(base, []).append(attr)
    for base, attrs in plain.items():
        if len(attrs) > 1:
            keep = min(attrs, key=lambda x: (bool(VARIANT.search(leaf(x))), x.count("."), len(x)))
            for x in attrs:
                if x != keep:
                    apps[keep].setdefault("aliases", []).append(x)
                    apps.pop(x)
    # Same desktop file names shipped by several attrs (wrapped/unwrapped,
    # foo/foo-esr...): one app, keep the shortest attr.
    by_dname = {}
    for a in apps.values():
        key = tuple(sorted(os.path.basename(d) for d in a["desktops"]))
        by_dname.setdefault(key, []).append(a["attr"])
    for key, attrs in by_dname.items():
        if len(attrs) > 1:
            keep = min(attrs, key=lambda x: (bool(VARIANT.search(x)), x.count("."), len(x)))
            for x in attrs:
                if x != keep:
                    apps[keep].setdefault("aliases", []).append(x)
                    apps[keep]["aliases"] += apps[x].get("aliases", [])
                    apps.pop(x)

    fl_by_id = {x["app_id"].lower(): x for x in flat}
    fl_by_name, fl_by_last = {}, {}
    for x in flat:
        fl_by_name.setdefault(norm(x["name"]), x)
        fl_by_last.setdefault(norm(x["app_id"].rsplit(".", 1)[-1]), x)
    manual = {}
    for l in open(os.path.join(ROOT, "data", "manual_map.tsv")):
        if l.strip() and not l.startswith("#"):
            fid, attr = l.split("\t")[:2]
            manual[attr.strip()] = fid.strip()

    def keys_for(attr):
        m = meta.get(attr, {})
        ks = {norm(leaf(attr)), norm(VARIANT.sub("", leaf(attr)))}
        if m.get("pname"):
            ks |= {norm(m["pname"]), norm(VARIANT.sub("", m["pname"]))}
        return {k for k in ks if len(k) > 1}

    matched = set()
    for a in apps.values():
        a["keys"] = keys_for(a["attr"])
        m = meta.get(a["attr"], {})
        fx = None
        for d in a["desktops"]:  # desktop id == Flathub app id
            b = os.path.basename(d)[:-8].lower()
            if b in fl_by_id:
                fx = fl_by_id[b]
                break
        if not fx and a["attr"] in manual:
            fx = fl_by_id.get(manual[a["attr"]].lower())
        if not fx:
            # Same name as the package (and a desktop app on both sides): the
            # app id's last part, or the display name when it is distinctive.
            for k in sorted(a["keys"], key=len, reverse=True):
                x = fl_by_last.get(k) or (fl_by_name.get(k) if len(k) >= 5 else None)
                if x:
                    fx = x
                    break
        a["flathub"] = fx["app_id"] if fx else ""
        a["flathub_installs"] = (fx["installs_last_month"] or 0) if fx else 0
        if fx:
            matched.add(fx["app_id"])
        lib = bool(LIB.match(a["attr"]))
        a["lib"] = lib
        a["arch"] = 0.0 if lib else max([arch.get(k, 0.0) for k in a["keys"]] + [0.0])
        a["debian"] = 0.0 if lib else max([deb.get(k, 0.0) for k in a["keys"]] + [0.0])
        a["kind"] = "app" if "app" in a["kinds"] else "tui"

    # Unmatched Flathub apps -> unfree/uncached nixpkgs attr, else Flathub-only.
    in_apps = {k for a in apps.values() for k in a["keys"]}
    meta_by_key = {}
    for m in meta.values():
        if SKIP_PREFIX.match(m["attr"]) or not m["linux"]:
            continue
        ks = {norm(leaf(m["attr"])), norm(m["pname"] or "")}
        ks |= {k.replace("-", "") for k in ks} | {re.sub(r"-(desktop|bin|gui|app|electron|browser|us|launcher|client|ide)$", "", k) for k in ks}
        for k in ks:
            if len(k) > 2:
                cur = meta_by_key.get(k)
                if not cur or (m["attr"].count("."), len(m["attr"])) < (cur["attr"].count("."), len(cur["attr"])):
                    meta_by_key[k] = m
    SUFFIX = re.compile(r"-(desktop|bin|gui|app|electron|browser|us|launcher|client|ide)$")
    manual_rev = {v.lower(): k for k, v in manual.items()}
    for x in flat:
        if x["app_id"] in matched:
            continue
        last, nm = norm(x["app_id"].rsplit(".", 1)[-1]), norm(x["name"])
        dom = domain_of(x["app_id"])
        m = meta.get(manual_rev.get(x["app_id"].lower(), ""))
        cands = []
        for k in (nm, last):
            cands += [k, k.replace("-", ""), SUFFIX.sub("", k), SUFFIX.sub("", k).replace("-", "")]
        for k in ([] if m else cands):
            c = meta_by_key.get(k)
            if c and LIB.match(c["attr"]):
                continue
            # Accept on homepage domain, or on the exact name when the app id's
            # last part is that name too (com.discordapp.Discord ~ discord).
            if c and ((dom and dom in c["homepage"]) or c["unfree"]):
                m = c
                break
        if m and m["attr"] in apps:
            continue  # name already covered by a nixpkgs app
        if m:
            attr = m["attr"]
            ks = keys_for(attr) | {nm, last}
            apps[attr] = dict(attr=attr, store="", desktops=[], keys=ks, kind="app", lib=False,
                              source="nixpkgs-unfree" if m["unfree"] else "nixpkgs-uncached",
                              flathub=x["app_id"], flathub_installs=x["installs_last_month"] or 0,
                              arch=max([arch.get(k, 0.0) for k in ks] + [0.0]),
                              debian=max([deb.get(k, 0.0) for k in ks] + [0.0]))
        else:
            apps["flathub:" + x["app_id"]] = dict(
                attr="flathub:" + x["app_id"], store="", desktops=[], keys={last}, kind="app", lib=False,
                source="flathub", flathub=x["app_id"], flathub_installs=x["installs_last_month"] or 0,
                arch=0.0, debian=0.0, runtime=x.get("runtime") or "")
        matched.add(x["app_id"])

    # Flathub installs -> %: least squares on log(arch%) = a + b log(installs).
    pts = [(math.log(a["flathub_installs"]), math.log(a["arch"])) for a in apps.values()
           if a["arch"] >= 0.3 and a["flathub_installs"] >= 200 and not a["lib"]]
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    b = sum((p[0] - mx) * (p[1] - my) for p in pts) / sum((p[0] - mx) ** 2 for p in pts)
    a0 = my - b * mx
    for a in apps.values():
        i = a["flathub_installs"]
        a["flathub_pct"] = min(100.0, math.exp(a0 + b * math.log(i))) if i > 0 else 0.0
        a["pop"] = max(a["arch"], a["debian"], a["flathub_pct"])
        m = meta.get(a["attr"], {})
        a["pname"] = m.get("pname", "")
        a["desc"] = m.get("desc", "")
        a["unfree"] = m.get("unfree", False)
    excl = {}
    for l in open(os.path.join(ROOT, "data", "not_apps.tsv")):
        if l.strip() and not l.startswith("#"):
            k, why = (l.rstrip("\n").split("\t") + [""])[:2]
            excl[k] = why
    for a in apps.values():
        a["include"] = "0" if a["attr"] in excl or a["kind"] == "tui" else "1"
        a["note"] = excl.get(a["attr"], "terminal app" if a["kind"] == "tui" else "")
    ranked = sorted(apps.values(), key=lambda a: (a["include"] == "0", -a["pop"]))
    cols = ["rank", "attr", "include", "source", "kind", "pop", "arch", "debian", "flathub_pct", "flathub_installs",
            "flathub", "unfree", "store", "desktops", "aliases", "runtime", "note", "desc"]
    with open(os.path.join(ROOT, "data", "apps.tsv"), "w") as f:
        f.write("\t".join(cols) + "\n")
        for i, a in enumerate(ranked, 1):
            a["rank"] = i
            row = []
            for c in cols:
                v = a.get(c, "")
                if c == "desktops":
                    v = ",".join(os.path.basename(d) for d in v)
                elif c == "aliases":
                    v = ",".join(v or [])
                elif isinstance(v, float):
                    v = f"{v:.3f}"
                elif isinstance(v, bool):
                    v = "1" if v else "0"
                row.append(str(v).replace("\t", " "))
            f.write("\t".join(row) + "\n")
    print(f"{len(ranked)} apps; flathub fit: log%={a0:.2f}+{b:.3f}*log(installs) from {n} overlaps",
          file=sys.stderr)


if __name__ == "__main__":
    main()
