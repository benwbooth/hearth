#!/usr/bin/env python3
"""The global menu checklist: one row per app, its solution and progress.

menu-survey/checklist.tsv is the source of truth (in git, diffable). This
script (re)builds it from the measurements (data/survey.sqlite, made by
build_db.py) and KEEPS every hand-set column of existing rows: `solution`,
`status`, `notes`, `checked` are only filled in where empty or still
machine-made (status in AUTO).

Columns
  rank attr source toolkit pop       from apps.tsv / classification
  measured  full | burger | none | untested | no-window   (installed hearth)
  route     how the menus came today (dbusmenu, gtk, atspi, registrar, x11)
  solution  general:<route>   inherits a general solution (no per-app work)
            module:<file>     a per-app module in menus/<app-id>.yaml
            none-needed       the app has no menus at all (dialog tools, games)
            todo
  status    done        real menus verified in a nested session
            partial     only its ☰ / app actions; a module could add the rest
            todo        needs a solution (general fix or module)
            retest      not measured yet, or the harness couldn't run it
            blocked     can't be tested here (root, hardware, account)
  gap       for apps not done: the general mechanism missing, named so that
            every app with the same gap is fixed together (e.g.
            kirigami-drawer, swt-late-menubar, mpris, gtk4-shortcuts-window)
  checked   date of the last verification
  notes     free text

Usage: checklist.py            rebuild/merge checklist.tsv
       checklist.py --summary  progress counts (weighted by popularity too)
"""
import argparse
import csv
import glob
import os
import re
import sqlite3
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
# MENU_SURVEY_LOCAL=1: this machine's installed apps too, into
# data/local/checklist.tsv (gitignored; run build_db.py the same way first).
LOCAL = os.environ.get("MENU_SURVEY_LOCAL") == "1"
TSV = os.path.join(ROOT, "data", "local", "checklist.tsv") if LOCAL else os.path.join(ROOT, "checklist.tsv")
DBFILE = os.path.join(ROOT, "data", "local" if LOCAL else "", "survey.sqlite")
COLS = ["rank", "attr", "source", "toolkit", "pop", "measured", "route", "solution", "status",
        "gap", "checked", "notes"]
AUTO = {"", "todo", "retest", "partial", "none-needed", "blocked"}  # statuses the measurements may overwrite


def load_probes():
    """Latest session row per app from data/probe*.jsonl (with inspect)."""
    import glob, json
    rows = {}
    for fn in sorted(glob.glob(os.path.join(ROOT, "data", "probe*.jsonl"))
                     + (glob.glob(os.path.join(ROOT, "data", "local", "probe*.jsonl")) if LOCAL else [])):
        for l in open(fn):
            try:
                j = json.loads(l)
            except ValueError:
                continue
            if j.get("variant") == "session":
                rows[j["attr"]] = j
    return rows


MENU_BUTTON_NAMES = {"menu", "main menu", "application menu", "app menu", "open menu", "primary menu",
                     "more options", "options menu", "more actions", "...", "…", "⋮", "☰", "options",
                     "settings", "help", "help & about", "help and about", "more", "tools", "preferences"}


def gap_of(measured, toolkit, p):
    """Name the general mechanism missing for an app that isn't done.
    Shared names group every app a single fix would cover."""
    if measured == "full":
        return ""
    p = p or {}
    if measured in ("no-window", "untested"):
        if measured != "no-window":
            return ""
        # Why it opened no window in the rig, from its log: most are limits
        # of a private test session, not of hearth.
        log = " ".join(p.get("log_tail") or []).lower()
        for pat, gap in (("only supported under gnome", "blocked:gnome-only"),
                         ("cannot open display", "blocked:needs-root"),
                         ("pkexec", "blocked:needs-root"),
                         ("jack", "blocked:needs-jack"),
                         ("was not provided by any .service files", "blocked:needs-session-service"),
                         ("cannot connect to d-bus service", "blocked:needs-session-service"),
                         ("already running", "harness-single-instance"),
                         ("--help", "harness-needs-arguments"), ("usage:", "harness-needs-arguments"),
                         ("pa_context_connect", "blocked:needs-sound-server"),
                         ("pulseaudio", "blocked:needs-sound-server"),
                         ("namespace xdp not available", "blocked:app-packaging"),
                         ("flatpak-spawn", "blocked:app-packaging"),
                         # Tauri's AppImage check, from runs before the probe
                         # extracted under $TMPDIR/.mount_cache.
                         ("not detected as an appimage", "harness-appimage-tauri"),
                         ("cannot open shared object", "harness-missing-library"),
                         ("version `glibc_", "harness-missing-library"),
                         ("no constructor defined", "blocked:app-crash"),
                         ("panic", "blocked:app-crash"), ("segmentation fault", "blocked:app-crash"),
                         ("traceback", "blocked:app-crash"), ("bail out", "blocked:app-crash")):
            if pat in log:
                return gap
        return "harness-no-window"
    if measured == "burger":
        return "burger-only"
    w = p.get("window") or {}
    ins = p.get("inspect") or {}
    a = ins.get("atspi") or {}
    # A startup error dialog in front (Evolution without its data server).
    shown = " ".join(a.get("texts") or []).lower()
    if "cannot connect to d-bus service" in shown or "was not provided by any .service files" in shown:
        return "blocked:needs-session-service"
    # Refuses to run outside another desktop (Spectacle on Wayland: KWin).
    if any(t in shown for t in ("requires kde plasma", "kwin compositor", "requires gnome",
                                "only supported under gnome", "requires a kde")):
        return "blocked:needs-other-desktop"
    # Stopped at a login or account screen: the main window comes after
    # signing in, which a throwaway home can't (Nheko, cloud sync clients).
    # A small screen with no tabs or menus: a main window with a password
    # field (PDFChain) or an optional sign-in step of a wizard isn't one.
    roles = a.get("roles") or {}
    small = (a.get("nodes") or 0) < 120 and not (roles.get("page tab list") or roles.get("menu item"))
    if small and re.search(r"\b(sign ?in|log ?in|login|password|homeserver|enter the token|create (an )?account|"
                           r"server (address|url)|connect to (your )?server|two-factor)\b", shown):
        return "blocked:needs-account"
    # An exported menu bar that came empty only counts when the app shows
    # menus on AT-SPI (appmenu-gtk-module exports an empty one for every GTK
    # 3 window, dialogs and splash screens included).
    # Combo boxes' popups count as menus on AT-SPI: only a menu bar with
    # items says the app really has menus the export lost.
    if w.get("app_menu") and a.get("menubars") and a.get("menu_items"):
        return "dbusmenu-empty"
    if (w.get("gtk_menu") or {}).get("menubar_path") and a.get("menubars"):
        return "gtkmenu-empty"
    if ins.get("mpris"):
        return "mpris-not-shown"
    if not a.get("found"):
        tk = toolkit or "unknown"
        if tk in ("electron", "chromium", "cef"):
            return "electron-no-a11y"
        if ins.get("flatpak") and tk != "sdl-glfw":  # a Flatpak game is still a game
            return "flatpak-no-a11y"
        return f"no-a11y:{tk}"
    if a.get("menubars") and a.get("menu_items"):
        return "atspi-menubar-not-read"
    # Only a button that opens the app's menu ("Menu", "Main menu (F10)",
    # "Help", "Settings", ☰, unnamed): content dropdowns ("Sort by", "Save
    # Profile", a calendar's month) are no app menu.
    def menuish(b):
        n = (b.get("name") or "").strip().split("\n")[0]
        n = re.sub(r"\s*\((?:F\d{1,2}|(?:Ctrl|Alt|Shift|Super)\s*\+[^)]*)\)$", "", n, flags=re.I).strip().lower()
        pops = b.get("popup") or b.get("role") == "push button menu"
        return (not n and pops) or (pops and n in MENU_BUTTON_NAMES)
    btns = [b for b in a.get("menu_buttons") or [] if menuish(b)]
    if btns:
        return "menu-button-not-read"
    if toolkit in ("qt6-mixed", "qt6-quick", "qt5-quick"):
        return "kirigami-no-menu"
    return "no-menus-visible"  # likely none-needed: check a screenshot


def module_attrs():
    """{checklist attr: module file} from the repo's menus/*.yaml."""
    res = {}
    for fn in sorted(glob.glob(os.path.join(ROOT, "..", "menus", "*.yaml"))):
        text = open(fn).read()
        for kind, prefix in (("nixpkgs", ""), ("flatpak", "flathub:")):
            m = re.search(rf"^\s+{kind}:\s*\[([^\]]*)\]", text, re.M)
            for a in (m.group(1).split(",") if m else []):
                a = a.strip().strip("\"'")
                if a:
                    res.setdefault(prefix + a, os.path.basename(fn))
    return res


APPSTREAM = "/var/lib/flatpak/appstream/flathub/x86_64/active/appstream.xml"
NOT_ONLY_GAME = {"Emulator", "Development", "Utility", "Graphics", "AudioVideo", "Audio", "Video",
                 "Office", "Education", "Science", "Network", "System", "Settings", "PackageManager",
                 "Music", "BoardGame", "CardGame", "LogicGame"}


def app_categories():
    """{attr: set of freedesktop Categories}: the app's own desktop files
    (nix-locate's list for nixpkgs) and Flathub's AppStream (Flathub apps,
    and nixpkgs apps through their Flathub twin)."""
    import json
    import xml.etree.ElementTree as ET
    by_path = {}
    try:
        for l in open(os.path.join(ROOT, "data", "desktop_entries.jsonl")):
            d = json.loads(l)
            by_path[d["path"]] = set(c for c in (d.get("Categories") or "").split(";") if c)
    except OSError:
        pass
    cats = {}
    try:
        for l in open(os.path.join(ROOT, "data", "raw", "nixlocate_desktop.tsv")):
            a, _, path = l.rstrip("\n").partition("\t")
            cats.setdefault(a.removesuffix(".out"), set()).update(by_path.get(path, ()))
    except OSError:
        pass
    flat = {}
    try:
        for _, el in ET.iterparse(APPSTREAM):
            if el.tag == "component":
                i = el.findtext("id") or ""
                flat[i.removesuffix(".desktop")] = {c.text for c in el.iter("category") if c.text}
                el.clear()
    except (OSError, ET.ParseError):
        pass
    with open(os.path.join(ROOT, "data", "apps.tsv")) as f:
        for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            fid = r["attr"].removeprefix("flathub:") if r["attr"].startswith("flathub:") else r.get("flathub") or ""
            if fid in flat:
                cats.setdefault(r["attr"], set()).update(flat[fid])
    return cats


# Genres of games played full-window. A bare "Game" is launchers, mod
# managers and companion tools; board, card and logic games are often
# ordinary windows with menus (Scid): those keep their measurement.
GAME_GENRES = {"ActionGame", "AdventureGame", "ArcadeGame", "BlocksGame", "KidsGame", "RolePlaying",
               "Shooter", "Simulation", "SportsGame", "StrategyGame"}


def is_game(cats):
    """A game by its own Categories: Game with a genre, and nothing that
    makes it a tool (emulators, editors, launchers keep their measurement)."""
    return "Game" in cats and bool(cats & GAME_GENRES) and not (cats & NOT_ONLY_GAME)


def machine_row(r):
    today = r["today"] or "untested"
    if today == "no-window":
        status, solution = "retest", "todo"
    elif today == "full":
        status, solution = "done", f"general:{r['route_today']}"
    elif today == "burger":
        status, solution = "partial", f"general:{r['route_today']}-burger"
    elif today == "none":
        status, solution = "todo", "todo"
    elif today == "terminal-only":
        # A terminal program (its desktop file says Terminal=true): its
        # menus are the terminal's. Skipped (Ben, 2026-11-24).
        status, solution = "none-needed", "none-needed:terminal"
    elif today == "tray-only":
        # No window, a tray icon: its menu is the tray icon's.
        status, solution = "none-needed", "none-needed:tray"
    else:
        status, solution = "retest", "todo"
    return {"rank": r["rank"], "attr": r["attr"], "source": r["source"], "toolkit": r["toolkit"] or "",
            "pop": f"{r['pop']:.3f}", "measured": today, "route": r["route_today"] or "",
            "solution": solution, "status": status, "gap": "",
            "checked": time.strftime("%Y-%m-%d") if today in ("full", "burger", "none") else "", "notes": ""}


def rebuild():
    db = sqlite3.connect(DBFILE)
    db.row_factory = sqlite3.Row
    rows = [machine_row(r) for r in db.execute("select * from results order by rank")]
    probes = load_probes()
    cats = app_categories()
    for r in rows:
        if r["status"] != "done":
            r["gap"] = gap_of(r["measured"], r["toolkit"], probes.get(r["attr"]))
            if r["gap"] == "no-a11y:sdl-glfw" or (r["gap"].startswith(("no-a11y:", "flatpak-no-a11y"))
                                                  and is_game(cats.get(r["attr"], set()))):
                # Games (SDL/GLFW/own engine, or Categories=Game with no a11y): their menus are
                # in the game. Ben, 2026-11-23: no global menu needed; the
                # emulators with Qt/GTK front ends are classified by those.
                r["status"], r["solution"], r["gap"] = "none-needed", "none-needed:game", ""
                r["notes"] = r["notes"] or "game: menus are in-game"
            elif r["gap"] == "no-menus-visible":
                # On AT-SPI, but no menu bar, no menu button, no shortcuts
                # window, no commands exported: nothing a menu could show.
                r["status"], r["solution"], r["gap"] = "none-needed", "none-needed", ""
            elif r["gap"].startswith("blocked:"):
                r["status"] = "blocked"
    old = {}
    if os.path.exists(TSV):
        with open(TSV) as f:
            for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
                old[r["attr"]] = r
    out = []
    for r in rows:
        o = old.get(r["attr"])
        if o and o.get("status") not in AUTO:
            # Hand-set (done by a module, blocked, none-needed...): keep it,
            # refresh only the measured facts.
            for k in ("solution", "status", "gap", "checked", "notes"):
                r[k] = o.get(k, r[k])
        elif o:
            if o.get("notes"):
                r["notes"] = o["notes"]
            # A hand-written gap stays while the app is still unsolved.
            if o.get("gap") and not r["gap"] and r["status"] not in ("done", "none-needed"):
                r["gap"] = o["gap"]
            if o.get("solution", "todo") not in ("todo", "") and not o["solution"].startswith("general:"):
                r["solution"] = o["solution"]
        out.append(r)
    # Apps a menu module covers (menus/*.yaml: its nixpkgs and flatpak
    # match lists): done by the module, whatever the measurement found
    # (a module wins over the other routes, so a measured "general:" there
    # was the module).
    mods = module_attrs()
    for r in out:
        m = mods.get(r["attr"])
        if m and r["status"] in AUTO | {"done"}:
            r["status"], r["solution"], r["gap"] = "done", f"module:{m}", ""
    for r in out:
        if r["status"] in ("done", "none-needed"):
            r["gap"] = ""  # solved: whatever gap it had is history
        # Read only with the Java bridge's Flatpak override: these go into
        # hearth.globalMenu.javaFlatpaks (nix/global-menu.nix).
        pr = probes.get(r["attr"]) or {}
        if pr.get("java_override") and r["status"] == "done" and r["solution"].startswith("general:"):
            r["solution"] += "+java-flatpak"
    with open(TSV, "w") as f:
        f.write("\t".join(COLS) + "\n")
        for r in out:
            f.write("\t".join(str(r.get(c, "")).replace("\t", " ") for c in COLS) + "\n")
    return out


def summary():
    with open(TSV) as f:
        rows = list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))
    tot = sum(float(r["pop"]) for r in rows) or 1
    by = {}
    for r in rows:
        n, w = by.get(r["status"], (0, 0.0))
        by[r["status"]] = (n + 1, w + float(r["pop"]))
    print(f"{len(rows)} apps")
    for s in ("done", "partial", "none-needed", "todo", "retest", "blocked"):
        n, w = by.get(s, (0, 0.0))
        print(f"  {s:8} {n:5}  {100 * w / tot:5.1f}% of installs")
    sol = {}
    for r in rows:
        k = r["solution"].split(":")[0] + (":" + r["solution"].split(":")[1] if r["solution"].startswith("general:") else "")
        sol[k] = sol.get(k, 0) + 1
    gaps = {}
    for r in rows:
        if r.get("gap"):
            n, w = gaps.get(r["gap"], (0, 0.0))
            gaps[r["gap"]] = (n + 1, w + float(r["pop"]))
    print("  gaps (apps, share of installs):")
    for g, (n, w) in sorted(gaps.items(), key=lambda x: -x[1][1])[:25]:
        print(f"    {g:28} {n:5}  {100 * w / tot:5.1f}%")
    print("  solutions:", ", ".join(f"{k} {v}" for k, v in sorted(sol.items(), key=lambda x: -x[1])))


def markdown():
    """The report's tables, from checklist.tsv (measured apps only)."""
    with open(TSV) as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE)]
    measured = [r for r in rows if r["status"] != "retest" or r["gap"].startswith(("blocked", "harness"))]
    tot = sum(float(r["pop"]) for r in measured) or 1
    print(f"Measured apps: {len(measured)} of {len(rows)}.\n")
    print("| Status | Apps | Share of installs |\n|---|---:|---:|")
    for st in ("done", "partial", "none-needed", "todo", "retest", "blocked"):
        xs = [r for r in measured if r["status"] == st]
        if xs:
            print(f"| {st} | {len(xs)} | {100 * sum(float(r['pop']) for r in xs) / tot:.1f}% |")
    print("\n| Gap | Apps | Share | Examples |\n|---|---:|---:|---|")
    gaps = {}
    for r in measured:
        if r["gap"]:
            gaps.setdefault(r["gap"], []).append(r)
    for g, xs in sorted(gaps.items(), key=lambda kv: -sum(float(r["pop"]) for r in kv[1])):
        ex = ", ".join(r["attr"].replace("kdePackages.", "").replace("flathub:", "") for r in xs[:5])
        print(f"| {g} | {len(xs)} | {100 * sum(float(r['pop']) for r in xs) / tot:.1f}% | {ex} |")
    print("\n| Toolkit | Apps | Done | Partial |\n|---|---:|---:|---:|")
    tks = {}
    for r in measured:
        tks.setdefault(r["toolkit"] or "unknown", []).append(r)
    for tk, xs in sorted(tks.items(), key=lambda kv: -len(kv[1])):
        d = sum(1 for r in xs if r["status"] == "done")
        p_ = sum(1 for r in xs if r["status"] == "partial")
        print(f"| {tk} | {len(xs)} | {100 * d / len(xs):.0f}% | {100 * p_ / len(xs):.0f}% |")


GAP_NOTES = {
    "no-a11y:unknown": "No accessibility tree, toolkit not recognized (iced, egui, Slint, Flutter, own engines): menu modules from source (gen-module.py) or the local model",
    "no-a11y:custom-drawn": "Draws its own UI (GPU/canvas): menu modules from its key bindings",
    "no-a11y:java-swing": "Java: retest with the bridge (Flatpaks with the javaFlatpaks override); LWJGL games fall to the game rule",
    "no-a11y:javafx": "JavaFX: no AT-SPI on Linux: menu modules",
    "flatpak-no-a11y": "A Flatpak without a reachable tree: per-app look (a11y portal, first-run screen)",
    "no-a11y:gtk4-adwaita": "GTK 4 app without a tree in the rig: mostly mixed toolkits (SDL, EFL) or first-run screens; retest",
    "no-a11y:gtk3": "Links GTK 3 but draws with another kit (SDL, gdraw, giu): modules",
    "no-a11y:dotnet": ".NET (Avalonia, WinForms on Mono): no AT-SPI on Linux: gen-module.py's XAML/WinForms parsers, else modules",
    "no-a11y:game-engine": "A game engine's own UI (Godot, Unity): game rule or modules for editors",
    "no-a11y:fltk": "FLTK: gen-module.py's FLTK parser (menus without keys have nothing to send)",
    "no-a11y:tk": "Tk: gen-module.py's Tk parser (mnemonics reach items without keys)",
    "no-a11y:proprietary-bundle": "Ships its own Qt/GTK without accessibility: modules from documented shortcuts",
    "no-a11y:tui": "A terminal program in a window: its menus are the terminal's",
    "electron-no-a11y": "Electron without its renderer tree: hearth.lib.globalMenu.electronFlags in its wrapper",
    "no-a11y:firefox-xul": "Gecko app whose tree didn't come up in the rig: retest",
    "blocked:app-packaging": "The package itself fails in a private session (missing portal, flatpak-spawn, broken wrapper)",
    "blocked:needs-account": "Stops at a login screen; its main window needs an account",
    "blocked:app-crash": "Crashes at start in the rig",
    "blocked:needs-sound-server": "Refuses to start without PulseAudio/PipeWire",
    "blocked:needs-jack": "Needs a JACK server",
    "blocked:needs-session-service": "Needs a desktop service the rig doesn't start",
    "blocked:needs-root": "Runs as root (pkexec): outside your session's buses; keys still reach it (modules)",
    "blocked:needs-other-desktop": "Refuses to run outside its desktop (KWin, GNOME Shell)",
    "blocked:gnome-only": "Refuses to run outside GNOME",
    "kirigami-no-menu": "Kirigami/Qt Quick with nothing read: page actions route, retest",
    "atspi-menubar-not-read": "A menu bar on AT-SPI the reader missed: reader bug to look at",
    "mpris-not-shown": "Has MPRIS but no menu shown: reader bug to look at",
    "dbusmenu-empty": "Exports an empty dbusmenu: app bug or late fill",
}


def triage():
    """TRIAGE-remaining.md: every unsolved or blocked app under its gap."""
    with open(TSV) as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE)]
    left = [r for r in rows if r["status"] in ("todo", "blocked")]
    by = {}
    for r in left:
        by.setdefault(r["gap"] or "(no gap)", []).append(r)
    out = ["# Global menu: apps still without a menu", "",
           f"Generated by `scripts/checklist.py --triage` from checklist.tsv ({len(left)} apps: "
           f"{sum(r['status'] == 'todo' for r in left)} todo, {sum(r['status'] == 'blocked' for r in left)} blocked; "
           f"{sum(r['status'] == 'retest' for r in rows)} more still to be measured). Decisions and the",
           "reasons per group are in TRIAGE.md.", ""]
    for gap, rs in sorted(by.items(), key=lambda kv: -len(kv[1])):
        out.append(f"## {gap} ({len(rs)})")
        out.append("")
        out.append(GAP_NOTES.get(gap, ""))
        out.append("")
        out.append(", ".join(r["attr"].replace("flathub:", "") for r in sorted(rs, key=lambda r: -float(r["pop"] or 0))))
        out.append("")
    with open(os.path.join(ROOT, "TRIAGE-remaining.md"), "w") as f:
        f.write("\n".join(out))
    print(f"TRIAGE-remaining.md: {len(left)} apps in {len(by)} groups")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--markdown", action="store_true")
    ap.add_argument("--triage", action="store_true")
    a = ap.parse_args()
    if a.markdown:
        markdown()
        return
    if a.triage:
        triage()
        return
    if not a.summary:
        rebuild()
    summary()


if __name__ == "__main__":
    main()
