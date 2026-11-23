#!/usr/bin/env python3
"""Classify Flathub-only apps from their Flathub build manifest (no install).

github.com/flathub/<app-id> holds <app-id>.{yml,yaml,json}. The runtime, base
app and SDK extensions say most of it:
  base org.electronjs.Electron2.BaseApp          -> electron
  base org.winehq.Wine / wine modules            -> wine
  sdk-extension openjdk*                         -> java
  runtime org.kde.Platform (+ kirigami/qml hints) -> qt6-widgets / qt6-quick
  runtime org.gnome.Platform (+ libadwaita / blueprint hints) -> gtk4-adwaita / gtk3
  flutter in modules                             -> flutter
  extra-data with chrome/electron-ish bundles    -> electron (proprietary .deb)
Manifests are cached in data/raw/flathub_manifests/. Output appended to
data/classified.jsonl (attr = "flathub:<id>"), replacing flathub-pending rows.
"""
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CACHE = os.path.join(ROOT, "data", "raw", "flathub_manifests")


def get(app_id):
    os.makedirs(CACHE, exist_ok=True)
    for ext in ("yml", "yaml", "json"):
        fn = os.path.join(CACHE, f"{app_id}.{ext}")
        if os.path.exists(fn):
            return open(fn).read()
    for branch in ("HEAD", "master", "beta"):
        for ext in ("yml", "yaml", "json"):
            url = f"https://raw.githubusercontent.com/flathub/{app_id}/{branch}/{app_id}.{ext}"
            try:
                with urllib.request.urlopen(url, timeout=20) as r:
                    text = r.read().decode(errors="replace")
                open(os.path.join(CACHE, f"{app_id}.{ext}"), "w").write(text)
                return text
            except Exception:
                continue
    return ""


def decide(app_id, text, runtime):
    t = text.lower()
    rt = (re.search(r"^\s*\"?runtime\"?\s*:\s*\"?([\w.]+)", text, re.M) or [None, runtime])[1] or runtime or ""
    base = (re.search(r"^\s*\"?base\"?\s*:\s*\"?([\w.]+)", text, re.M) or [None, ""])[1]
    hints = []
    if re.search(r"firefox|gecko|librewolf|waterfox|floorp|zen[-_]browser|betterbird|thunderbird|libxul", t):
        return "firefox-xul", "menubar-hidden", rt, hints
    if "electron2.baseapp" in t or "electron" in base.lower() or re.search(r"\belectron\b", t) and "zypak" in t:
        return "electron", "menubar", base or rt, hints
    if "org.winehq.wine" in t or re.search(r"\bwine\b", t) and "wine" in base.lower():
        return "wine", "custom", base or rt, hints
    if "flutter" in t:
        return "flutter", "custom", rt, hints
    if "openjdk" in t or ".jar" in t:
        return "java-swing", "menubar", rt, hints
    if "zypak" in t or "chrome-sandbox" in t or "cef" in re.findall(r"\b(cef)\b", t):
        return "electron", "menubar", rt, ["zypak/chromium"]
    if "org.kde.platform" in rt.lower() or "org.kde.platform" in t:
        if "kirigami" in t or "qml" in t:
            return "qt6-quick", "custom", rt, ["kirigami/qml"]
        return "qt6-widgets", "menubar", rt, hints
    if "org.gnome.platform" in rt.lower() or "libadwaita" in t:
        if "libadwaita" in t or "blueprint" in t or "gtk4" in t or "gtk-4" in t:
            return "gtk4-adwaita", "gmenu-popover", rt, hints
        return "gtk4-adwaita?", "gmenu-popover", rt, ["gnome runtime"]
    if "extra-data" in t:
        if re.search(r"\.deb|\.appimage|\.tar", t):
            return "proprietary-bundle", "unknown", rt, ["extra-data"]
    if "sdl" in t or "godot" in t or "unity" in t:
        return "sdl-glfw", "none", rt, hints
    if "qt" in t:
        return "qt6-widgets?", "menubar", rt, hints
    return "unknown", "unknown", rt, hints


def main():
    out = os.path.join(ROOT, "data", "classified.jsonl")
    rows = [json.loads(l) for l in open(out)] if os.path.exists(out) else []
    pend = [r for r in rows if r.get("toolkit") == "flathub-pending"]
    apps = {}
    with open(os.path.join(ROOT, "data", "apps.tsv")) as f:
        hdr = f.readline().rstrip("\n").split("\t")
        for line in f:
            r = dict(zip(hdr, line.rstrip("\n").split("\t")))
            apps[r["attr"]] = r
    done = []
    for r in pend:
        fid = r["attr"].split(":", 1)[1]
        text = get(fid)
        tk, hint, rt, hints = decide(fid, text, apps.get(r["attr"], {}).get("runtime", ""))
        done.append(dict(attr=r["attr"], toolkit=tk, menu_hint=hint, runtime=rt, hints=hints,
                         via="flathub-manifest" if text else "flathub-runtime"))
        print(fid, tk, file=sys.stderr)
    keep = [r for r in rows if r.get("toolkit") != "flathub-pending"]
    with open(out, "w") as f:
        for r in keep + done:
            f.write(json.dumps(r) + "\n")


if __name__ == "__main__":
    main()
