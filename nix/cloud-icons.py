#!/usr/bin/env python3
"""Write Settings' cloud drive logos (shell/popups/settings/CloudIcons.js)
into OUT: Papirus icons as they are, Simple Icons glyphs on a rounded tile
of the brand's color.  cloud-icons.py MAP.js PAPIRUS_APPS SIMPLE_ICONS OUT"""
import json, os, re, shutil, sys

src, papirus, si, out = sys.argv[1:5]
text = open(src).read()
icons = json.loads(re.search(r"var icons = (\{.*?\});", text, re.S).group(1))
brands = {e["slug"]: e for e in json.load(open(os.path.join(si, "data", "simple-icons.json")))}
os.makedirs(out, exist_ok=True)

def name(key):
    return re.sub(r"[: ]", "_", key) + ".svg"

def luminance(hexc):
    r, g, b = (int(hexc[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

for key, ref in icons.items():
    kind, _, what = ref.partition(":")
    dst = os.path.join(out, name(key))
    if kind == "papirus":
        shutil.copyfile(os.path.realpath(os.path.join(papirus, what + ".svg")), dst)
    elif kind == "si":
        svg = open(os.path.join(si, "icons", what + ".svg")).read()
        path = re.search(r'<path d="([^"]+)"', svg).group(1)
        hexc = brands[what]["hex"]
        glyph = "#1d1d1f" if luminance(hexc) > 0.7 else "#ffffff"
        with open(dst, "w") as f:
            f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">'
                    f'<rect x="4" y="4" width="56" height="56" rx="13" fill="#{hexc}"/>'
                    f'<g transform="translate(16 16) scale(1.3333)" fill="{glyph}"><path d="{path}"/></g></svg>')
    else:
        sys.exit(f"{key}: unknown source {ref}")
    print(key, "->", ref)
