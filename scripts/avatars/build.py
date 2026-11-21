#!/usr/bin/env python3
"""Build hearth's built-in user pictures from scripts/avatars/manifest.tsv.

Run through scripts/build-avatars.sh (it supplies Pillow, pngquant and
oxipng). Downloads land in a cache directory and are only read as images;
every Commons file's licence is checked against the API before use.
"""
import argparse
import colorsys
import html
import json
import os
import random
import re
import subprocess
import sys
import urllib.parse
import urllib.request

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 512
UA = "hearth-avatar-build/1.0 (https://github.com/; scripts/build-avatars.sh)"
FLUENT_COMMIT = "1ffb34c752ecf5d402f04cfb4b392c77f57c54bc"
FLUENT_REPO = "https://github.com/microsoft/fluentui-emoji"
OK_LICENCES = {"CC0", "Public domain", "PDM", "Public Domain Mark"}


def fetch(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest + ".part", "wb") as f:
        f.write(r.read())
    os.replace(dest + ".part", dest)
    return dest


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def vgradient(top, bottom, size=SIZE):
    """Vertical gradient (pngquant's dithering keeps it from banding)."""
    g = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((size, size), Image.BICUBIC)


def add_grain(img, amount):
    """Fine noise (+-amount) so gradients survive quantising without banding."""
    rnd = random.Random(7)
    n = Image.new("L", img.size)
    n.putdata([128 + rnd.randint(-amount, amount) for _ in range(img.size[0] * img.size[1])])
    n = Image.merge("RGB", [n] * 3)
    return ImageChops.add(img, n, 1.0, -128)


def auto_bg(emoji):
    """A pastel two-tone gradient in the emoji's own main hue (Memoji-style tile)."""
    small = emoji.resize((64, 64))
    r = g = b = n = 0
    for (pr, pg, pb, pa) in (small.get_flattened_data() if hasattr(small, "get_flattened_data") else small.getdata()):
        if pa > 200:
            h, l, s = colorsys.rgb_to_hls(pr / 255, pg / 255, pb / 255)
            w = s  # saturated pixels say more about the emoji's colour
            r += pr * w; g += pg * w; b += pb * w; n += w
    if n == 0:
        return hexrgb("#e8ecf2"), hexrgb("#bcc6d4")
    h, l, s = colorsys.rgb_to_hls(r / n / 255, g / n / 255, b / n / 255)
    top = colorsys.hls_to_rgb(h, 0.88, min(0.75, s * 0.9 + 0.2))
    bot = colorsys.hls_to_rgb(h, 0.74, min(0.7, s * 0.9 + 0.2))
    return tuple(round(c * 255) for c in top), tuple(round(c * 255) for c in bot)


def compose_fluent(src, opts):
    emoji = Image.open(src).convert("RGBA")
    if "bg" in opts:
        top, bot = (hexrgb(c) for c in opts["bg"].split(","))
    else:
        top, bot = auto_bg(emoji)
    tile = vgradient(top, bot)
    # A soft light from the top, like Apple's tiles.
    glow = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(glow).ellipse((-60, -260, SIZE + 60, 260), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    tile = Image.composite(Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), tile, glow)
    side = round(SIZE * float(opts.get("size", 0.6)))
    emoji = emoji.resize((side, side), Image.LANCZOS)
    x = (SIZE - side) // 2
    y = (SIZE - side) // 2 + round(SIZE * 0.01)
    # Contact shadow under the emoji.
    a = emoji.split()[3]
    shadow = Image.new("L", (SIZE, SIZE), 0)
    shadow.paste(a.point(lambda v: v * 0.28), (x, y + 14))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    tile = Image.composite(Image.new("RGB", (SIZE, SIZE), tuple(round(c * 0.55) for c in bot)), tile, shadow)
    tile.paste(emoji, (x, y), emoji)
    return tile


def compose_photo(src, opts):
    img = Image.open(src).convert("RGB")
    w, h = img.size
    zoom = float(opts.get("zoom", 1))
    side = min(w, h) / zoom
    cx = float(opts.get("x", 0.5)) * w
    cy = float(opts.get("y", 0.5)) * h
    left = min(max(cx - side / 2, 0), w - side)
    top = min(max(cy - side / 2, 0), h - side)
    crop = img.crop((round(left), round(top), round(left + side), round(top + side)))
    return crop.resize((SIZE, SIZE), Image.LANCZOS)


def compose_gradient(colours, seed):
    cols = [hexrgb(c) for c in colours.split(",")]
    rnd = random.Random(seed)
    base = Image.new("RGB", (SIZE, SIZE), cols[0])
    for i, c in enumerate(cols[1:] * 2):
        layer = Image.new("RGB", (SIZE, SIZE), c)
        mask = Image.new("L", (SIZE, SIZE), 0)
        r = rnd.randint(150, 260)
        cx, cy = rnd.randint(-40, SIZE + 40), rnd.randint(-40, SIZE + 40)
        ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=rnd.randint(150, 230))
        mask = mask.filter(ImageFilter.GaussianBlur(rnd.randint(90, 130)))
        base = Image.composite(layer, base, mask)
    return add_grain(base, 3)


def commons_info(pageid, cache):
    path = os.path.join(cache, f"commons-{pageid}.json")
    if not os.path.exists(path):
        q = urllib.parse.urlencode({
            "action": "query", "format": "json", "pageids": pageid, "prop": "imageinfo",
            "iiprop": "url|extmetadata|size", "iiurlwidth": 1600,
            "iiextmetadatafilter": "LicenseShortName|LicenseUrl|Artist|Credit"})
        fetch("https://commons.wikimedia.org/w/api.php?" + q, path)
    with open(path) as f:
        page = json.load(f)["query"]["pages"][str(pageid)]
    ii = page["imageinfo"][0]
    meta = ii["extmetadata"]
    lic = meta.get("LicenseShortName", {}).get("value", "")
    if lic not in OK_LICENCES:
        sys.exit(f"commons {pageid} ({page['title']}): licence {lic!r} is not CC0/public domain")
    artist = re.sub(r"<[^>]+>", "", html.unescape(meta.get("Artist", {}).get("value", "unknown")))
    artist = re.sub(r"\s+", " ", artist).strip()
    return {
        "title": page["title"].removeprefix("File:"),
        "page": ii["descriptionurl"],
        "url": ii.get("thumburl") or ii["url"],
        "author": artist,
        "licence": "CC0 1.0" if lic == "CC0" else "Public domain",
    }


def optimise(path):
    subprocess.run(["pngquant", "--force", "--skip-if-larger", "--quality", "65-90",
                    "--speed", "1", "--output", path, path], check=False)
    subprocess.run(["oxipng", "-q", "-o", "4", "--strip", "safe", path], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--only", help="comma-separated ids to rebuild")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    os.makedirs(args.cache, exist_ok=True)
    only = set(args.only.split(",")) if args.only else None

    entries = []
    with open(args.manifest) as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            pid, cat, kind, source, optstr, title = line.rstrip("\n").split("\t")
            opts = dict(kv.split("=", 1) for kv in optstr.split(";") if kv)
            entries.append((pid, cat, kind, source, opts, title))

    lic = fetch(f"https://raw.githubusercontent.com/microsoft/fluentui-emoji/{FLUENT_COMMIT}/LICENSE",
                os.path.join(args.cache, "fluent-LICENSE"))
    with open(lic) as f, open(os.path.join(args.out, "LICENSE.fluentui-emoji"), "w") as o:
        o.write(f.read())

    index, credits = [], {}
    for i, (pid, cat, kind, source, opts, title) in enumerate(entries):
        out = os.path.join(args.out, pid + ".png")
        if kind == "fluent":
            slug = source.lower().replace(" ", "_")
            url = (f"https://raw.githubusercontent.com/microsoft/fluentui-emoji/{FLUENT_COMMIT}/assets/"
                   f"{urllib.parse.quote(source)}/3D/{slug}_3d.png")
            credit = {"source": f"{FLUENT_REPO}/tree/{FLUENT_COMMIT}/assets/{urllib.parse.quote(source)}",
                      "author": "Microsoft (Fluent Emoji)", "licence": "MIT",
                      "note": f"\"{source}\" 3D emoji on a generated gradient tile"}
            if only is None or pid in only:
                src = fetch(url, os.path.join(args.cache, f"fluent-{slug}.png"))
                compose_fluent(src, opts).save(out)
        elif kind == "commons":
            info = commons_info(source, args.cache)
            credit = {"source": info["page"], "author": info["author"], "licence": info["licence"],
                      "note": f"\"{info['title']}\", cropped and scaled"}
            if only is None or pid in only:
                src = fetch(info["url"], os.path.join(args.cache, f"commons-{source}.img"))
                compose_photo(src, opts).save(out)
        elif kind == "gradient":
            credit = {"source": "scripts/avatars/build.py", "author": "hearth", "licence": "CC0 1.0",
                      "note": "generated gradient"}
            if only is None or pid in only:
                compose_gradient(source, i).save(out)
        else:
            sys.exit(f"{pid}: unknown kind {kind}")
        if only is None or pid in only:
            optimise(out)
        index.append({"id": pid, "category": cat, "title": title, "file": pid + ".png",
                      "author": credit["author"], "licence": credit["licence"], "source": credit["source"]})
        credits[pid] = (cat, title, credit)
        print(f"{pid:12} {cat:18} {os.path.getsize(out) // 1024:4d} KB  {credit['licence']}", flush=True)

    with open(os.path.join(args.out, "index.json"), "w") as f:
        json.dump(index, f, indent=1, ensure_ascii=False)
        f.write("\n")

    lines = [
        "# hearth user pictures: credits and licences",
        "",
        "Built by `scripts/build-avatars.sh` from `scripts/avatars/manifest.tsv`.",
        "Every picture is 512x512 PNG. Licences:",
        "",
        "- **Fluent Emoji** (Microsoft, MIT licence, "
        f"[repo]({FLUENT_REPO}) at commit `{FLUENT_COMMIT[:12]}`): the emoji",
        "  are placed on gradient tiles generated by the build. Its licence text",
        "  (MIT, Copyright (c) Microsoft Corporation) is in `LICENSE.fluentui-emoji`.",
        "- **Wikimedia Commons photos**: only files Commons marks CC0 or public",
        "  domain (the build checks each one's licence through the Commons API and",
        "  stops otherwise). Space pictures are NASA works, public domain in the US.",
        "- **Gradients**: generated by `scripts/avatars/build.py`, CC0.",
        "",
        "| Picture | Category | Author | Licence | Source |",
        "|---|---|---|---|---|",
    ]
    for pid, (cat, title, c) in credits.items():
        author = c["author"].replace("|", "/")
        lines.append(f"| `{pid}.png` {title} | {cat} | {author} | {c['licence']} | {c['source']} ({c['note']}) |")
    with open(os.path.join(args.out, "CREDITS.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
