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
import os
import sqlite3
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TSV = os.path.join(ROOT, "checklist.tsv")
COLS = ["rank", "attr", "source", "toolkit", "pop", "measured", "route", "solution", "status",
        "gap", "checked", "notes"]
AUTO = {"", "todo", "retest", "partial"}  # statuses the measurements may overwrite


def load_probes():
    """Latest session row per app from data/probe*.jsonl (with inspect)."""
    import glob, json
    rows = {}
    for fn in sorted(glob.glob(os.path.join(ROOT, "data", "probe*.jsonl"))):
        for l in open(fn):
            try:
                j = json.loads(l)
            except ValueError:
                continue
            if j.get("variant") == "session":
                rows[j["attr"]] = j
    return rows


def gap_of(measured, toolkit, p):
    """Name the general mechanism missing for an app that isn't done.
    Shared names group every app a single fix would cover."""
    if measured == "full":
        return ""
    if measured in ("no-window", "untested"):
        return "harness-no-window" if measured == "no-window" else ""
    p = p or {}
    if measured == "burger":
        return "burger-only"
    w = p.get("window") or {}
    if w.get("app_menu"):
        return "dbusmenu-empty"
    if (w.get("gtk_menu") or {}).get("menubar_path"):
        return "gtkmenu-empty"
    ins = p.get("inspect") or {}
    a = ins.get("atspi") or {}
    if ins.get("mpris"):
        return "mpris-not-shown"
    if not a.get("found"):
        tk = toolkit or "unknown"
        if tk in ("electron", "chromium", "cef"):
            return "electron-no-a11y"
        if ins.get("flatpak"):
            return "flatpak-no-a11y"
        return f"no-a11y:{tk}"
    if a.get("menubars"):
        return "atspi-menubar-not-read"
    if a.get("menu_buttons"):
        return "menu-button-not-read"
    if a.get("menus") or a.get("menu_items"):
        return "atspi-menus-not-read"
    if toolkit in ("qt6-mixed", "qt6-quick", "qt5-quick"):
        return "kirigami-no-menu"
    return "no-menus-visible"  # likely none-needed: check a screenshot


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
    else:
        status, solution = "retest", "todo"
    return {"rank": r["rank"], "attr": r["attr"], "source": r["source"], "toolkit": r["toolkit"] or "",
            "pop": f"{r['pop']:.3f}", "measured": today, "route": r["route_today"] or "",
            "solution": solution, "status": status, "gap": "",
            "checked": time.strftime("%Y-%m-%d") if today in ("full", "burger", "none") else "", "notes": ""}


def rebuild():
    db = sqlite3.connect(os.path.join(ROOT, "data", "survey.sqlite"))
    db.row_factory = sqlite3.Row
    rows = [machine_row(r) for r in db.execute("select * from results order by rank")]
    probes = load_probes()
    for r in rows:
        if r["status"] != "done":
            r["gap"] = gap_of(r["measured"], r["toolkit"], probes.get(r["attr"]))
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
            for k in ("notes", "gap"):
                if o.get(k):
                    r[k] = o[k]
            if o.get("solution", "todo") not in ("todo", "") and not o["solution"].startswith("general:"):
                r["solution"] = o["solution"]
        out.append(r)
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
    for s in ("done", "partial", "todo", "retest", "blocked"):
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true")
    a = ap.parse_args()
    if not a.summary:
        rebuild()
    summary()


if __name__ == "__main__":
    main()
