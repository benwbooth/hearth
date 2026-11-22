#!/usr/bin/env python3
"""For GTK4/libadwaita apps: does the binary embed a shortcuts window
(GtkShortcutsWindow help-overlay or AdwShortcutsDialog)? Those list every
keyboard shortcut with its title and action, which is what a generated menu
needs. Reads the whole main ELF from cache.nixos.org (nix store cat) and
greps its GResource (.ui files are stored uncompressed or with
xml-stripblanks). Output: data/shortcuts.jsonl."""
import concurrent.futures as cf, json, os, re, subprocess, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
def scan(row):
    path = (row.get("chain") or [None])[-1]
    if not path or not path.startswith("/nix/store"):
        return dict(attr=row["attr"], scanned=False)
    data = subprocess.run(["nix", "store", "cat", "--store", "https://cache.nixos.org", path],
                          capture_output=True, timeout=600).stdout
    sw = bool(re.search(rb"GtkShortcutsWindow|AdwShortcutsDialog|help-overlay\.ui|shortcuts-dialog\.ui", data))
    n = len(re.findall(rb"<object class=\"(?:GtkShortcutsShortcut|AdwShortcutsItem)\"", data))
    acc = len(re.findall(rb"name=\"accelerator\"", data))
    menu = bool(re.search(rb"<menu id=\"(primary|main|app|hamburger)[_-]?menu", data))
    return dict(attr=row["attr"], scanned=True, size=len(data), shortcuts_window=sw, shortcut_items=n,
                accelerators=acc, primary_menu_ui=menu)
rows = [json.loads(l) for l in open(os.path.join(ROOT, "data", "classified.jsonl"))]
rows = [r for r in rows if r.get("toolkit", "").startswith(("gtk4", "gtk3"))]
with open(os.path.join(ROOT, "data", "shortcuts.jsonl"), "w") as f, cf.ThreadPoolExecutor(8) as ex:
    for r in ex.map(scan, rows):
        f.write(json.dumps(r) + "\n")
