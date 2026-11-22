#!/usr/bin/env python3
"""Coverage tables for the report: what share of the top apps get real menus
in hearth's menu bar today, and with each candidate fix.

Per app the outcome is one of
  full      the app's own menu bar (File, Edit, ...) in hearth's menu bar
  burger    only its ☰ / primary menu (one top-level menu, via AT-SPI)
  none      hearth's app-name + Window menus only
Measured outcomes (data/probe*.jsonl, nested arbor + hearth) win; apps not
measured get the toolkit model below (MODEL), which is calibrated on the
measured ones (`--calibrate` prints measured vs model per toolkit).

Weights: `pop` from data/apps.tsv (estimated % of Linux desktops with the app
installed); also unweighted counts and a Flathub-installs weighting.

Usage: coverage.py [--top N] [--calibrate] [--markdown]
"""
import argparse
import collections
import glob
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# toolkit -> outcome today, and after each strategy (only changes listed).
MODEL = {
    "qt6-widgets":   {"today": "full", "S7_ai_modules": "full"},
    "qt5-widgets":   {"today": "full", "S7_ai_modules": "full"},
    "qt6-mixed":     {"today": "none", "S4_burger_qt": "burger", "S7_ai_modules": "full"},
    "qt6-quick":     {"today": "none", "S4_burger_qt": "burger", "S7_ai_modules": "full"},
    "qt5-quick":     {"today": "none", "S7_ai_modules": "full"},
    "gtk3":          {"today": "full", "S2_gtk_actions": "burger", "S5_shortcuts": "full", "S7_ai_modules": "full"},
    "gtk2":          {"today": "none", "S6_gtk2_module": "full"},
    "wx-gtk3":       {"today": "full"},
    "gtk4":          {"today": "burger", "S2_gtk_actions": "burger", "S5_shortcuts": "full"},
    "gtk4-adwaita":  {"today": "burger", "S2_gtk_actions": "burger", "S5_shortcuts": "full"},
    "gtk4-adwaita?": {"today": "burger", "S2_gtk_actions": "burger", "S5_shortcuts": "full"},
    "electron":      {"today": "none", "S1_electron_dbusmenu": "full"},
    "chromium":      {"today": "full"},
    "cef":           {"today": "none", "S7_ai_modules": "full"},
    "firefox-xul":   {"today": "full"},
    "java-swing":    {"today": "none", "S3_java_atk": "full"},
    "javafx":        {"today": "none", "S3_java_atk": "full"},
    "flutter":       {"today": "none", "S7_ai_modules": "full"},
    "wine":          {"today": "none", "S7_ai_modules": "full"},
    "dotnet":        {"today": "none", "S7_ai_modules": "full"},
    "tk":            {"today": "none", "S7_ai_modules": "full"},
    "fltk":          {"today": "none", "S7_ai_modules": "full"},
    "efl":           {"today": "none", "S7_ai_modules": "full"},
    "sdl-glfw":      {"today": "none", "S7_ai_modules": "full"},
    "game-engine":   {"today": "none", "S7_ai_modules": "full"},
    "custom-drawn":  {"today": "none", "S7_ai_modules": "full"},
    "proprietary-bundle": {"today": "none", "S1_electron_dbusmenu": "full"},
    "qt6-widgets?":  {"today": "full"},
    "unknown":       {"today": "none", "S7_ai_modules": "full"},
    "tui":           {"today": "none"},
}
STRATEGIES = ["S1_electron_dbusmenu", "S2_gtk_actions", "S3_java_atk", "S4_burger_qt", "S5_shortcuts",
              "S6_gtk2_module", "S7_ai_modules"]
SCORE = {"full": 1.0, "burger": 0.5, "none": 0.0}


def load():
    apps = []
    with open(os.path.join(ROOT, "data", "apps.tsv")) as f:
        hdr = f.readline().rstrip("\n").split("\t")
        for line in f:
            r = dict(zip(hdr, line.rstrip("\n").split("\t")))
            if r["include"] == "1":
                apps.append(r)
    cls = {}
    for l in open(os.path.join(ROOT, "data", "classified.jsonl")):
        j = json.loads(l)
        cls[j["attr"]] = j
    for l in open(os.path.join(ROOT, "data", "toolkit_overrides.tsv")):
        if l.strip() and not l.startswith("#"):
            attr, tk = l.split("\t")[:2]
            cls.setdefault(attr, {"attr": attr})["toolkit"] = tk
            cls[attr]["override"] = True
    probe = collections.defaultdict(list)
    for fn in sorted(glob.glob(os.path.join(ROOT, "data", "probe*.jsonl"))):
        for l in open(fn):
            j = json.loads(l)
            probe[j["attr"]].append(j)
    return apps, cls, probe


def measured(rows):
    """(today, best_with_levers, lever) from probe rows, or None if untested."""
    if not rows:
        return None
    sess = [r for r in rows if r.get("variant") == "session"]
    if not sess or sess[-1].get("result") in ("no-window", "error"):
        # not prebuilt / no entry / needs root or D-Bus activation the
        # private bus can't do: unmeasured, the toolkit average applies.
        return None
    def outcome(r):
        if r.get("result") != "menus":
            return "none"
        tops = [m for m in r.get("menus", []) if not m.endswith(":0")]
        return "full" if len(tops) >= 2 else "burger"
    today = outcome(sess[-1])
    best, lever = today, ""
    for r in rows:
        o = outcome(r)
        if SCORE[o] > SCORE[best]:
            best, lever = o, r.get("variant")
    return today, best, lever


TK_AVG = {}
SHORTCUTS = {}


def load_shortcuts():
    fn = os.path.join(ROOT, "data", "shortcuts.jsonl")
    if os.path.exists(fn):
        for l in open(fn):
            j = json.loads(l)
            SHORTCUTS[j["attr"]] = bool(j.get("shortcuts_window"))


def toolkit_averages(apps, cls, probe):
    """Measured mean score per toolkit (today), used for unmeasured apps."""
    acc = {}
    for a in apps:
        m = measured(probe.get(a["attr"]))
        if m:
            tk = cls.get(a["attr"], {}).get("toolkit", "unknown")
            acc.setdefault(tk, []).append(SCORE[m[0]])
    for tk, xs in acc.items():
        if len(xs) >= 5:
            TK_AVG[tk] = (sum(xs) / len(xs), len(xs))


def score_for(app, cls, probe, strategies):
    """Score in [0,1]: measured outcome, or the toolkit's measured average."""
    tk, o, meas = outcome_for(app, cls, probe, strategies)
    if meas or tk not in TK_AVG:
        return SCORE[o]
    base = TK_AVG[tk][0]
    lifted = max([SCORE[MODEL.get(tk, MODEL["unknown"]).get(s, "none")] for s in strategies
                  if not (s == "S5_shortcuts" and not SHORTCUTS.get(app["attr"]))] + [0])
    return max(base, lifted)


def outcome_for(app, cls, probe, strategies):
    tk = cls.get(app["attr"], {}).get("toolkit", "unknown")
    m = measured(probe.get(app["attr"]))
    model = MODEL.get(tk, MODEL["unknown"])
    if m:
        today, best, lever = m
        o = today
        if lever == "electron+libdbusmenu" and "S1_electron_dbusmenu" in strategies:
            o = best
        if lever == "x11" and "S1_electron_dbusmenu" in strategies and tk in ("electron", "chromium"):
            o = best
    else:
        o = model["today"]
    for s in strategies:
        cand = model.get(s)
        if s == "S5_shortcuts" and not SHORTCUTS.get(app["attr"]):
            cand = None
        if cand and SCORE[cand] > SCORE[o]:
            # A measured "full" never drops; a measured none can be lifted by
            # a strategy that applies to its toolkit.
            o = cand
    return tk, o, bool(m)


def table(apps, cls, probe, top, weight="pop"):
    sel = apps[:top]
    w = lambda a: float(a.get(weight) or 0) if weight != "count" else 1.0
    total = sum(w(a) for a in sel) or 1
    cum = []
    steps = [[]]
    for s in STRATEGIES:
        steps.append(steps[-1] + [s])
    for st in steps:
        sc = sum(w(a) * score_for(a, cls, probe, st) for a in sel)
        full = sum(w(a) for a in sel if score_for(a, cls, probe, st) >= 0.999)
        cum.append((st[-1] if st else "today", 100 * full / total, 100 * sc / total))
    by_tk = collections.defaultdict(lambda: [0, 0.0, 0.0, 0.0, 0])
    for a in sel:
        tk, o, meas = outcome_for(a, cls, probe, [])
        tk2, o2, _ = outcome_for(a, cls, probe, STRATEGIES[:6])
        b = by_tk[tk]
        b[0] += 1
        b[1] += w(a)
        b[2] += w(a) * score_for(a, cls, probe, [])
        b[3] += w(a) * score_for(a, cls, probe, STRATEGIES[:6])
        b[4] += meas
    return total, cum, by_tk


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=300)
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--markdown", action="store_true")
    a = ap.parse_args()
    apps, cls, probe = load()
    load_shortcuts()
    toolkit_averages(apps[:a.top], cls, probe)
    if a.calibrate:
        agree = collections.Counter()
        for app in apps[:a.top]:
            m = measured(probe.get(app["attr"]))
            if not m:
                continue
            tk = cls.get(app["attr"], {}).get("toolkit", "unknown")
            agree[(tk, MODEL.get(tk, MODEL["unknown"])["today"], m[0])] += 1
        for (tk, mod, meas), n in sorted(agree.items()):
            print(f"{tk:16} model={mod:7} measured={meas:7} {n}")
        return
    for weight in ("pop", "count", "flathub_installs"):
        total, cum, by_tk = table(apps, cls, probe, a.top, weight)
        print(f"\n### Top {a.top}, weight={weight}\n")
        print("| Toolkit | Apps | Measured | Share | Real menus today | After S1–S6 |")
        print("|---|---:|---:|---:|---:|---:|")
        for tk, (n, wt, sc, sc2, meas) in sorted(by_tk.items(), key=lambda x: -x[1][1]):
            print(f"| {tk} | {n} | {meas} | {100*wt/total:.1f}% | {100*sc/wt if wt else 0:.0f}% | {100*sc2/wt if wt else 0:.0f}% |")
        print("\n| Cumulative strategy | Full menu bar | Score (☰ = ½) |")
        print("|---|---:|---:|")
        for name, full, sc in cum:
            print(f"| + {name} | {full:.1f}% | {sc:.1f}% |")


if __name__ == "__main__":
    main()
