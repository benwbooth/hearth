#!/usr/bin/env python3
"""The apps installed on this machine: system and user profiles (NixOS
modules, home flakes such as Ben's own apps), ~/.local/share/applications
(launchers of flake builds, web apps, Wine, Steam) and Flatpaks.

Each visible launcher is matched to the survey list (apps.tsv: desktop id,
Flathub id, package name or alias). The rest join the survey as source
"installed", attr "installed:<desktop id>", probed from the installed copy:
nothing is downloaded, built or deleted for them.

Writes data/local/ (gitignored: this machine's inventory stays out of the
public repo): installed.tsv (every launcher and its match),
installed_apps.tsv (rows in apps.tsv's format, source "installed") and
installed_exec.tsv (attr -> argv). Run again after installing apps.

Usage: installed_apps.py [--dry-run]
"""
import configparser
import csv
import glob
import json
import os
import re
import shlex
import shutil
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
HOME = os.path.expanduser("~")
DIRS = [
    ("system", "/run/current-system/sw/share/applications"),
    ("user-profile", "/etc/profiles/per-user/" + os.environ.get("USER", "ben") + "/share/applications"),
    ("nix-profile", HOME + "/.nix-profile/share/applications"),
    ("local", HOME + "/.local/share/applications"),
    ("flatpak-system", "/var/lib/flatpak/exports/share/applications"),
    ("flatpak-user", HOME + "/.local/share/flatpak/exports/share/applications"),
]


def entry(fn):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    try:
        cp.read(fn, encoding="utf-8")
        return cp["Desktop Entry"]
    except Exception:
        return None


def pname_of(store):
    base = os.path.basename(store).split("-", 1)[-1]
    for _ in range(2):
        base = re.sub(r"-(\d[^-]*|wrapped|bin|unwrapped)$", "", base)
    return base


def resolve(argv, where):
    """Store path of the launcher's program (flake builds, wrappers)."""
    a = list(argv)
    while a and (a[0] == "env" or "=" in a[0]):
        a = a[1:]
    if not a:
        return ""
    prog = a[0]
    if prog == "flatpak":
        return ""
    if not prog.startswith("/"):
        prog = shutil.which(prog, path="/run/current-system/sw/bin:/etc/profiles/per-user/%s/bin:%s/.nix-profile/bin:%s"
                            % (os.environ.get("USER", "ben"), HOME, os.environ.get("PATH", ""))) or ""
    if not prog:
        return ""
    real = os.path.realpath(prog)
    m = re.match(r"(/nix/store/[^/]+)", real)
    return m.group(1) if m else real


EXEC = {}
SEARCH = "/run/current-system/sw/bin:/etc/profiles/per-user/%s/bin:%s/.nix-profile/bin:%s/.local/bin" % (
    os.environ.get("USER", "ben"), HOME, HOME)
DEVLOOP = HOME + "/.local/state/devloop"
# Not apps to probe: the compositor and shell themselves, servers, deploys,
# terminal UIs, root helpers, URL openers, hearth's own windows.
SKIP_DEVLOOP = {"arbor", "hearth", "tesserad-static", "screentime", "earshot-web", "kog-web", "kog-terminal",
                "treetop-tui"}
SKIP_IDS = re.compile(r"^(hearth-(about|settings)|lights-out-.*|home-services)\.desktop$")
APPIMAGE_SKIP = re.compile(r"(linuxdeploy|appimagetool)", re.I)


def devloop_argv(argv):
    """`devloop start NAME`: run devloop's prebuilt binary directly (never
    devloop itself: that would build, deploy or start on the live display)."""
    if len(argv) < 3 or not argv[0].endswith("/devloop"):
        return None
    verb, name = argv[1], argv[2]
    if verb != "start" or name in SKIP_DEVLOOP:
        return []
    bins = sorted(glob.glob(os.path.join(DEVLOOP, name, "bin", "*")))
    pick = [b for b in bins if os.path.basename(b) == name] or [b for b in bins if name.startswith(os.path.basename(b))] \
        or [b for b in bins if not re.search(r"(server|tui|probe|d)$", os.path.basename(b))][:1]
    return [os.path.realpath(pick[0])] if pick else []


def appimages():
    """AppImages in the home folder (newest copy of each app; build tools and
    flatpak-builder trees left out)."""
    prune = {HOME + "/.cache", HOME + "/.local/share/Steam", HOME + "/.local/share/flatpak", HOME + "/.steam"}
    found = {}
    for dp, dn, fn in os.walk(HOME):
        dn[:] = [d for d in dn if os.path.join(dp, d) not in prune and d not in
                 ("node_modules", ".flatpak-builder", ".git", "target", "tools", "cache", ".snapshots")]
        for f in fn:
            if not f.lower().endswith(".appimage") or APPIMAGE_SKIP.search(f):
                continue
            p = os.path.join(dp, f)
            stem = re.split(r"[-_ ](v?\d)", f[:-len(".appimage")], maxsplit=1)[0].lower()
            try:
                t = os.path.getmtime(p)
            except OSError:
                continue
            if stem not in found or t > found[stem][0]:
                found[stem] = (t, p)
    return sorted((stem, p) for stem, (t, p) in found.items())


def main():
    dry = "--dry-run" in sys.argv
    apps = os.path.join(ROOT, "data", "apps.tsv")
    with open(apps) as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    hdr = list(rows[0].keys())
    by_desktop, by_flathub, by_name = {}, {}, {}
    for r in rows:
        for d in filter(None, r.get("desktops", "").split(",")):
            by_desktop.setdefault(d, r["attr"])
        if r.get("flathub"):
            by_flathub.setdefault(r["flathub"], r["attr"])
        for n in [r["attr"], r["attr"].split(".")[-1]] + r.get("aliases", "").split(","):
            if n:
                by_name.setdefault(n.lower(), r["attr"])
    have = set()  # rebuilt from scratch each run
    LOCAL = os.path.join(ROOT, "data", "local")
    os.makedirs(LOCAL, exist_ok=True)
    out, new, seen = [], [], set()
    for where, d in DIRS:
        for fn in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            did = os.path.basename(fn)
            if did in seen:
                continue
            e = entry(fn)
            if e is None or e.get("Type", "Application") != "Application" \
                    or e.get("NoDisplay", "").lower() == "true" or e.get("Hidden", "").lower() == "true":
                continue
            seen.add(did)
            ex = e.get("Exec", "")
            try:
                argv = shlex.split(ex)
            except ValueError:
                argv = ex.split()
            term = e.get("Terminal", "").lower() == "true"
            dv = devloop_argv(argv)
            if dv is not None:
                argv = dv
                if not dv:
                    continue
            if SKIP_IDS.match(did):
                continue
            store = resolve(argv, where)
            fid = ""
            if "flatpak" in where or (argv[:2] == ["flatpak", "run"] or (argv and argv[0].endswith("/flatpak"))):
                fid = e.get("X-Flatpak", "") or did[:-len(".desktop")]
            pname = pname_of(store) if store.startswith("/nix/store/") else ""
            match = (by_desktop.get(did) or (fid and by_flathub.get(fid)) or by_desktop.get(did.lower())
                     or (pname and by_name.get(pname.lower())) or "")
            kind = "terminal" if term else ("flatpak" if fid else ("wine" if "wine" in ex.lower() else
                    ("steam" if ex.startswith("steam ") else ("web" if re.search(r"--app=|--app-id=|webapp", ex) else "app"))))
            if dv:
                kind = "devloop"
            row = dict(desktop=did, name=e.get("Name", ""), where=where, kind=kind, store=store, pname=pname,
                       flatpak=fid, match=match, exec=ex)
            out.append(row)
            # Listed ones too: Ben's copy may be another build (overlays, Wayland
            # wrappers, unfree packages the catalog run never gets).
            if not term and kind in ("app", "flatpak", "web", "devloop"):
                attr = "installed:" + did[:-len(".desktop")]
                if attr in have:
                    continue
                r = {k: "" for k in hdr}
                r.update(rank=str(900000 + len(new)), attr=attr, include="1", source="installed", kind=kind,
                         pop="0", arch="0", debian="0", flathub_pct="0", flathub_installs="0", unfree="0", store=store, desktops=did, flathub=fid, note=where + ": " + fn + (" (catalog: %s)" % match if match else ""),
                         desc=e.get("Comment", "") or e.get("Name", ""))
                new.append(r)
                argv = [a for a in argv if not (len(a) == 2 and a.startswith("%"))]
                if argv and not argv[0].startswith("/") and argv[0] not in ("env", "flatpak"):
                    argv[0] = shutil.which(argv[0], path=SEARCH) or argv[0]
                v = ["flatpak", fid] if fid else argv
                if v in EXEC.values():
                    new.pop()  # another launcher of the same program (devloop-almanac, almanac)
                    continue
                EXEC[attr] = v
    for stem, p in appimages():
        if any(r["pname"].lower().startswith(stem) or r["name"].lower().startswith(stem) for r in out if r["kind"] != "steam"):
            continue  # installed some other way too
        attr = "installed:appimage-" + stem.replace(" ", "-")
        out.append(dict(desktop="", name=stem, where="appimage", kind="appimage", store=p, pname=stem, flatpak="",
                        match="", exec=p))
        EXEC[attr] = ["appimage-run", p]
        if attr in have:
            continue
        r = {k: "" for k in hdr}
        r.update(rank=str(900000 + len(new)), attr=attr, include="1", source="installed", kind="appimage",
                 pop="0", arch="0", debian="0", flathub_pct="0", flathub_installs="0", unfree="0", store=p, note="appimage: " + p, desc=os.path.basename(p))
        new.append(r)
    with open(os.path.join(LOCAL, "installed_exec.tsv"), "w") as f:
        for a, v in sorted(EXEC.items()):
            f.write(a + "\t" + json.dumps(v) + "\n")
    with open(os.path.join(LOCAL, "installed.tsv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0].keys()), delimiter="\t", lineterminator="\n")
        w.writeheader()
        w.writerows(out)
    kinds = {}
    for r in out:
        kinds[(r["kind"], bool(r["match"]))] = kinds.get((r["kind"], bool(r["match"])), 0) + 1
    print(f"{len(out)} visible launchers; {sum(1 for r in out if r['match'])} on the survey list; {len(new)} to probe", file=sys.stderr)
    for (k, m), n in sorted(kinds.items()):
        print(f"  {k:9} {'listed' if m else 'unlisted':8} {n}", file=sys.stderr)
    for r in new:
        print("  new", r["attr"], r["store"] or r["flathub"], file=sys.stderr)
    if not dry:
        with open(os.path.join(LOCAL, "installed_apps.tsv"), "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=hdr, delimiter="\t", lineterminator="\n")
            w.writeheader()
            w.writerows(new)


if __name__ == "__main__":
    main()
