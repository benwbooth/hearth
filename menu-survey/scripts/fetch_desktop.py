#!/usr/bin/env python3
"""Read every desktop file listed in data/raw/nixlocate_desktop.tsv straight
from cache.nixos.org (`nix store cat --store https://cache.nixos.org`, which
fetches only that file via the NAR listing), and keep the [Desktop Entry]
keys hearth cares about. Output: data/desktop_entries.jsonl (resumable)."""
import concurrent.futures as cf
import json
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "data", "desktop_entries.jsonl")
KEYS = {"Type", "Name", "NoDisplay", "Hidden", "Terminal", "Exec", "Categories", "StartupWMClass",
        "OnlyShowIn", "NotShowIn", "X-GNOME-UsesNotifications", "DBusActivatable"}


def parse(text):
    d, sect = {}, None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("["):
            sect = line
            continue
        if sect == "[Desktop Entry]" and "=" in line:
            k, v = line.split("=", 1)
            k = k.strip()
            if k in KEYS:
                d[k] = v.strip()
    return d


def fetch(path):
    try:
        r = subprocess.run(["nix", "store", "cat", "--store", "https://cache.nixos.org", path],
                           capture_output=True, text=True, timeout=60)
        if r.returncode:
            return {"path": path, "error": r.stderr.strip()[-200:]}
        return {"path": path, **parse(r.stdout)}
    except Exception as e:
        return {"path": path, "error": str(e)}


def main():
    done = set()
    if os.path.exists(OUT):
        for l in open(OUT):
            j = json.loads(l)
            if "error" not in j:
                done.add(j["path"])
    paths = sorted({l.rstrip("\n").split("\t")[1] for l in open(os.path.join(ROOT, "data", "raw", "nixlocate_desktop.tsv"))} - done)
    print(f"{len(paths)} to fetch", file=sys.stderr)
    with open(OUT, "a") as f, cf.ThreadPoolExecutor(24) as ex:
        for i, r in enumerate(ex.map(fetch, paths)):
            f.write(json.dumps(r) + "\n")
            if i % 200 == 0:
                f.flush()
                print(i, file=sys.stderr)


if __name__ == "__main__":
    main()
