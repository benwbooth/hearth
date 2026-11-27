#!/usr/bin/env python3
"""What hearth's screen reading sees at the top of a window: the text rows of
its top 80 logical pixels and the menu bar it would find there, as JSON.

    ocr-top.py WINDOW_ID HEARTH_HELPERS_DIR [STRIP.png]

STRIP.png: the window's top 120 logical pixels (greyscale) for a person to
look at (scripts/strips.py puts them on contact sheets).

Run inside a rig (arbor msg reaches the rig's arbor). The survey keeps it
with a no-tree app's result: a window whose top reads as words but holds no
menu bar has none; one that reads as noise (xfig's 10 px bitmap buttons)
proves nothing.
"""
import json
import sys

sys.path.insert(0, sys.argv[2])
import hearth_ocr_menu as o  # noqa: E402

window = int(sys.argv[1])
s = o.Session(window)
try:
    p = s.shot()
    if not p:
        print(json.dumps({"error": "no capture"}))
        sys.exit(0)
    w, h, _ = o.read_png(p)
    ws = o.window_size(window)
    k = w / ws[0] if ws and ws[0] else 1.0
    rows = o.ocr_rows(p, (0, 0, w, min(h, int(80 * k))))
    bar = o.menu_bar(rows, k)
    if len(sys.argv) > 3:
        _, _, px = o.read_png(p)
        o.write_grey_png(sys.argv[3], w, min(h, int(120 * k)), px[:min(h, int(120 * k))])
    print(json.dumps({"rows": [r["text"] for r in sorted(rows, key=lambda r: r["y0"])],
                      "bar": [t for t, _ in bar], "size": [w, h]}))
finally:
    s.close()
