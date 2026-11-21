#!/usr/bin/env python3
"""Build hearth's GRUB theme: theme.txt, background, selection box, icons, fonts.

Usage: mktheme.py OUT SCALE SNOWFLAKE_SVG ICON_DIR INTER_TTC MONO_TTF

SCALE is the screen height divided by 1600 (1.0 for 3840x1600, 1.35 for
5120x2160). GRUB can't scale fonts or pick them by resolution, so every pixel
size here is baked for one gfxmode. Needs resvg and grub-mkfont on PATH.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

out, scale, snowflake, icon_dir, inter, mono = sys.argv[1:7]
s = float(scale)
os.makedirs(f"{out}/icons", exist_ok=True)


def px(v):
    return int(round(v * s))


# Metrics at 3840x1600 (1 px = 1 logical px of hearth at 4/3 on the 5K panel).
ICON = px(112)
ITEM_H = px(128)
RADIUS = px(28)
# GRUB draws the selection box's 9-slice borders *outside* the item, so the
# gap between items has to hold two of them or the box covers its
# neighbours.
ITEM_PAD = 0
ITEM_SPACE = 2 * RADIUS + px(12)
ICON_SPACE = px(30)
MENU_W = px(700)
SIZES = {  # name -> (Inter.ttc face index, px size)
    "item": ("Inter Medium", 10, px(30)),
    "count": ("Inter Regular", 0, px(20)),
    "hint": ("Inter Regular", 0, px(17)),
}
MONO = px(22)


# --- fonts ------------------------------------------------------------------
# Latin, Latin-1/Extended-A, general punctuation, arrows, ⌘ and ⏎. Keeping the
# range small keeps the pf2 files (copied to the ESP) small.
RANGE = "0x20-0x7E,0xA0-0x17F,0x2000-0x206F,0x2190-0x21FF,0x2318-0x2318,0x23CE-0x23CE"


def pf2_name(path):
    # The theme must name a font exactly as its NAME chunk does, and
    # grub-mkfont builds that itself ("<-n> <style> <size>").
    with open(path, "rb") as f:
        data = f.read(512)
    i = data.index(b"NAME") + 4
    length = int.from_bytes(data[i:i + 4], "big")
    return data[i + 4:i + 4 + length].rstrip(b"\0").decode()


def mkfont(name, index, size, src, fname):
    cmd = ["grub-mkfont", "-s", str(size), "-n", name, "-r", RANGE,
           "-o", f"{out}/{fname}", src]
    if index is not None:
        cmd[1:1] = ["-i", str(index)]
    subprocess.run(cmd, check=True)
    return pf2_name(f"{out}/{fname}")


fonts = {}
for key, (name, index, size) in SIZES.items():
    fonts[key] = mkfont(name, index, size, inter,
                        f"inter-{key}-{size}.pf2")
fonts["mono"] = mkfont("DejaVu Sans Mono", None, MONO, mono,
                       f"mono-{MONO}.pf2")


# --- icons ------------------------------------------------------------------
def render(svg, size, dst):
    subprocess.run(["resvg", "-w", str(size), "-h", str(size), svg, dst],
                   check=True)


render(snowflake, ICON, f"{out}/icons/nixos.png")
for name in ("windows", "efi", "submenu", "os"):
    render(f"{icon_dir}/{name}.svg", ICON, f"{out}/icons/{name}.png")
# Other class names the same pictures should answer to.
for alias, src in (("uefi-firmware", "efi"), ("recovery", "submenu"),
                   ("gnu-linux", "os"), ("linux", "os")):
    Image.open(f"{out}/icons/{src}.png").save(f"{out}/icons/{alias}.png")


# --- background -------------------------------------------------------------
# A dark, faintly cool radial wash (macOS's Startup Manager shows a dimmed
# desktop; GRUB has no wallpaper to dim). Drawn small and stretched; the
# ordered noise keeps the stretched gradient from banding.
BW, BH = 960, 400
bg = Image.new("RGB", (BW, BH))
pix = bg.load()
seed = 0x2545F491
for y in range(BH):
    for x in range(BW):
        dx = (x - BW / 2) / (BW / 2)
        dy = (y - BH * 0.45) / (BH / 2)
        d = min(1.0, (dx * dx * 0.55 + dy * dy) ** 0.5)
        t = d * d * (3 - 2 * d)
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        n = ((seed >> 16) % 3) - 1
        r = 34 - 24 * t + n
        g = 35 - 24 * t + n
        b = 41 - 27 * t + n
        pix[x, y] = (int(r), int(g), int(b))
bg.save(f"{out}/background.png", optimize=True)


# --- selection box (9-slice) -----------------------------------------------
# Rounded glass: white 12% fill, a 1 px rim at 20% that brightens along the
# top edge (light from above, as hearth's glass shader), drawn at 4x and
# downsampled for smooth corners.
SS = 4
mid = 8
side = 2 * RADIUS + mid
big = Image.new("RGBA", (side * SS, side * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(big)
r = RADIUS * SS
d.rounded_rectangle([0, 0, side * SS - 1, side * SS - 1], r,
                    fill=(255, 255, 255, 31), outline=(255, 255, 255, 52),
                    width=SS)
# Top sheen: a brighter rim on the upper third.
sheen = Image.new("RGBA", big.size, (0, 0, 0, 0))
ds = ImageDraw.Draw(sheen)
ds.rounded_rectangle([0, 0, side * SS - 1, side * SS - 1], r,
                     outline=(255, 255, 255, 70), width=SS)
mask = Image.new("L", big.size, 0)
ImageDraw.Draw(mask).rectangle([0, 0, side * SS, RADIUS * SS], fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(RADIUS * SS / 3))
big = Image.composite(Image.alpha_composite(big, sheen), big, mask)
box = big.resize((side, side), Image.LANCZOS)

R, M = RADIUS, mid
parts = {
    "nw": (0, 0, R, R), "n": (R, 0, R + M, R), "ne": (R + M, 0, side, R),
    "w": (0, R, R, R + M), "c": (R, R, R + M, R + M),
    "e": (R + M, R, side, R + M),
    "sw": (0, R + M, R, side), "s": (R, R + M, R + M, side),
    "se": (R + M, R + M, side, side),
}
for k, b in parts.items():
    box.crop(b).save(f"{out}/select_{k}.png")

# GRUB shifts an item's content by its box's top/left border, so with only the
# selected item boxed it would jump down by RADIUS. A transparent box of the
# same size on every item keeps them all on one grid.
clear = Image.new("RGBA", (side, side), (0, 0, 0, 0))
for k, b in parts.items():
    clear.crop(b).save(f"{out}/item_{k}.png")

# Terminal box (the "c" console and "e" editor): solid dark panel, same
# corners.
term = Image.new("RGBA", (side * SS, side * SS), (0, 0, 0, 0))
ImageDraw.Draw(term).rounded_rectangle(
    [0, 0, side * SS - 1, side * SS - 1], r, fill=(22, 22, 25, 242),
    outline=(255, 255, 255, 40), width=SS)
term = term.resize((side, side), Image.LANCZOS)
for k, b in parts.items():
    term.crop(b).save(f"{out}/terminal_{k}.png")


# --- theme.txt --------------------------------------------------------------
row = ITEM_H + 2 * ITEM_PAD + ITEM_SPACE
theme = f"""\
# hearth GRUB theme, built for a {round(3840 * s)}x{round(1600 * s)} gfxmode.
# Generated by boot/grub/mktheme.py; edit that, not this.
title-text: ""
desktop-image: "background.png"
desktop-image-scale-method: "stretch"
desktop-color: "#0e0e10"
terminal-font: "{fonts['mono']}"
terminal-box: "terminal_*.png"
terminal-left: "10%"
terminal-top: "10%"
terminal-width: "80%"
terminal-height: "80%"
terminal-border: "{px(24)}"

+ boot_menu {{
  left = 50%-{MENU_W // 2}
  top = 50%-{int(row * 1.75)}
  width = {MENU_W}
  height = {row * 5}
  item_font = "{fonts['item']}"
  selected_item_font = "{fonts['item']}"
  item_color = "#d1d1d6"
  selected_item_color = "#ffffff"
  icon_width = {ICON}
  icon_height = {ICON}
  item_icon_space = {ICON_SPACE}
  item_height = {ITEM_H}
  item_padding = {ITEM_PAD}
  item_spacing = {ITEM_SPACE}
  item_pixmap_style = "item_*.png"
  selected_item_pixmap_style = "select_*.png"
  scrollbar = false
}}

+ label {{
  id = "__timeout__"
  text = "Starting in %d s"
  left = 0
  width = 100%
  top = 100%-{px(118)}
  align = "center"
  font = "{fonts['count']}"
  color = "#8e8e93"
}}

+ label {{
  text = "↑ ↓  choose    ⏎  start    e  edit    c  command line"
  left = 0
  width = 100%
  top = 100%-{px(72)}
  align = "center"
  font = "{fonts['hint']}"
  color = "#5f5f66"
}}
"""
with open(f"{out}/theme.txt", "w") as f:
    f.write(theme)
