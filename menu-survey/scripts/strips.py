#!/usr/bin/env python3
"""Contact sheets of no-tree windows' top strips (data/shots/top/*.png, saved
by ocr-top.py) for a person to say which show a menu bar or a menu button.

    strips.py OUTDIR [PER_SHEET]

Writes OUTDIR/sheet-NN.png (strips stacked, each cut to 1100 px wide, a black
rule between) and prints which app is which strip, top to bottom. The
verdicts go into data/looked.tsv (attr, verdict, note): checklist.py reads
them.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "helpers"))
import hearth_ocr_menu as o  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
out = sys.argv[1]
per = int(sys.argv[2]) if len(sys.argv) > 2 else 8
W = 1100
os.makedirs(out, exist_ok=True)
files = sorted(glob.glob(os.path.join(ROOT, "data", "shots", "top", "*.png")))
for n in range(0, len(files), per):
    rows, names = [], []
    for f in files[n:n + per]:
        try:
            w, h, px = o.read_png(f)
        except Exception:
            continue
        names.append(os.path.basename(f)[:-4])
        for r in px[:110]:
            r = bytes(r[:W])
            rows.append(r + b"\xff" * (W - len(r)))
        rows.extend([b"\x00" * W] * 4)
    if rows:
        fn = os.path.join(out, f"sheet-{n // per:02d}.png")
        o.write_grey_png(fn, W, len(rows), rows)
        print(fn, " | ".join(names))
