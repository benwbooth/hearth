#!/usr/bin/env python3
"""Build hearth's GRUB theme: one theme per screen height, plus the script
that picks a video mode and the theme drawn for it.

Usage: mktheme.py OUT SNOWFLAKE_SVG ICON_DIR INTER_TTC MONO_TTF

GRUB can't scale fonts or pick a theme by resolution, and its "auto" gfxmode
falls back to 800x600 whenever the monitor's preferred mode is 4096 px or
wider (a 5K panel), which drew the 3840x1600 theme zoomed in with its text
overlapping. So every height in HEIGHTS gets its own theme in OUT/h<height>/
(all pixel sizes are baked for it), fonts go to OUT/fonts/, and
OUT/select-mode.cfg tries the modes in MODES from the largest down, keeps the
first the firmware has and switches to that height's theme. OUT/theme.txt is
the 1600 px theme, for configs that don't source the script.
Needs resvg and grub-mkfont on PATH.
"""
import os
import re
import shutil
import textwrap
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

out, snowflake, icon_dir, inter, mono = sys.argv[1:6]

# Theme heights, and the modes to try (largest first) with the theme each one
# uses. A mode between two heights takes the smaller theme so nothing runs off
# the screen. Widths don't matter: the layout is centred and sized by height.
HEIGHTS = (2160, 1600, 1440, 1200, 1080, 1024, 900, 768, 600)
MODES = (
    ("5120x2160", 2160), ("3840x2160", 2160), ("3840x1600", 1600),
    ("2560x1600", 1600), ("3440x1440", 1440), ("2560x1440", 1440),
    ("1920x1200", 1200), ("2560x1080", 1080), ("1920x1080", 1080),
    ("1680x1050", 1024), ("1280x1024", 1024), ("1600x900", 900),
    ("1440x900", 900), ("1280x800", 768), ("1366x768", 768),
    ("1024x768", 768), ("1280x720", 600), ("800x600", 600),
)
assert {h for _, h in MODES} == set(HEIGHTS)
os.makedirs(f"{out}/fonts", exist_ok=True)


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
    # Themes of nearby heights share sizes; GRUB loads every .pf2 in the
    # theme, so each (face, size) is made once.
    dst = f"{out}/fonts/{fname}"
    if not os.path.exists(dst):
        cmd = ["grub-mkfont", "-s", str(size), "-n", name, "-r", RANGE,
               "-o", dst, src]
        if index is not None:
            cmd[1:1] = ["-i", str(index)]
        subprocess.run(cmd, check=True)
    return pf2_name(dst)


def build(height, tdir):
    s = height / 1600
    os.makedirs(f"{tdir}/icons", exist_ok=True)

    def px(v, lo=1):
        return max(lo, int(round(v * s)))

    # Metrics at 3840x1600 (1 px = 1 logical px of hearth at 4/3 on the 5K
    # panel). Text keeps a readable floor on small modes.
    ICON = px(112)
    ITEM_H = px(128)
    RADIUS = px(28)
    # GRUB draws the selection box's 9-slice borders *outside* the item, so
    # the gap between items has to hold two of them or the box covers its
    # neighbours.
    ITEM_PAD = 0
    ITEM_SPACE = 2 * RADIUS + px(12)
    ICON_SPACE = px(30)
    MENU_W = px(700, 340)
    SIZES = {  # name -> (Inter.ttc face, face index, px size)
        "item": ("Inter Medium", 10, px(30, 14)),
        "count": ("Inter Regular", 0, px(20, 12)),
        "hint": ("Inter Regular", 0, px(17, 11)),
    }
    MONO = px(22, 14)

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


    render(snowflake, ICON, f"{tdir}/icons/nixos.png")
    for name in ("windows", "efi", "submenu", "os"):
        render(f"{icon_dir}/{name}.svg", ICON, f"{tdir}/icons/{name}.png")
    # Other class names the same pictures should answer to.
    for alias, src in (("uefi-firmware", "efi"), ("recovery", "submenu"),
                       ("gnu-linux", "os"), ("linux", "os")):
        Image.open(f"{tdir}/icons/{src}.png").save(f"{tdir}/icons/{alias}.png")


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
    bg.save(f"{tdir}/background.png", optimize=True)


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
        box.crop(b).save(f"{tdir}/select_{k}.png")

    # GRUB shifts an item's content by its box's top/left border, so with only the
    # selected item boxed it would jump down by RADIUS. A transparent box of the
    # same size on every item keeps them all on one grid.
    clear = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    for k, b in parts.items():
        clear.crop(b).save(f"{tdir}/item_{k}.png")

    # Terminal box (the "c" console and "e" editor): solid dark panel, same
    # corners.
    term = Image.new("RGBA", (side * SS, side * SS), (0, 0, 0, 0))
    ImageDraw.Draw(term).rounded_rectangle(
        [0, 0, side * SS - 1, side * SS - 1], r, fill=(22, 22, 25, 242),
        outline=(255, 255, 255, 40), width=SS)
    term = term.resize((side, side), Image.LANCZOS)
    for k, b in parts.items():
        term.crop(b).save(f"{tdir}/terminal_{k}.png")


    # --- theme.txt --------------------------------------------------------------
    row = ITEM_H + 2 * ITEM_PAD + ITEM_SPACE
    theme = f"""\
    # hearth GRUB theme, built for a {height} px tall gfxmode.
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
    with open(f"{tdir}/theme.txt", "w") as f:
        f.write(textwrap.dedent(theme))


for h in HEIGHTS:
    build(h, f"{out}/h{h}")
# The plain theme.txt: the 1600 px theme, with its paths into h1600/.
with open(f"{out}/h1600/theme.txt") as f:
    t = f.read()
t = re.sub(r'^(\s*(?:desktop-image|terminal-box)\s*:\s*"|'
           r'\s*(?:selected_)?item_pixmap_style\s*=\s*")',
           r"\1h1600/", t, flags=re.M)
with open(f"{out}/theme.txt", "w") as f:
    f.write(t)
shutil.copytree(f"{out}/h1600/icons", f"{out}/icons")  # GRUB looks in <theme dir>/icons

modes = " ".join(f"{m}:{h}" for m, h in MODES)
with open(f"{out}/select-mode.cfg", "w") as f:
    f.write(f"""\
# hearth: pick a video mode and the GRUB theme drawn for it.
# Generated by boot/grub/mktheme.py. Source it after $theme is set to this
# theme's theme.txt and before the menu (NixOS: boot.loader.grub.extraConfig,
# with boot.loader.grub.font = null so nothing has set a mode yet).
#
# GRUB's own "auto" mode falls back to 800x600 on monitors whose preferred
# mode is 4096 px wide or more, so try real modes from the largest down and
# keep the first the firmware has. Linux keeps it (gfxpayload=keep), so the
# boot splash starts at the same size without a mode switch.
#
# gfxterm appends ";auto" to gfxmode, so a missing mode would quietly become
# "auto" and look like a success. The ",none" after it is not a mode: GRUB
# stops at it with an error instead of reaching "auto", and terminal_output
# fails as it should.
if [ "$grub_platform" = "efi" ]; then
  insmod efi_gop
  insmod efi_uga
else
  insmod vbe
fi
insmod gfxterm
insmod regexp
regexp --set=1:hearth_dir '^(.*)/[^/]*$' "$theme"
set gfxpayload=keep
set hearth_height=""
for hearth_mode in {modes}; do
  regexp --set=1:hearth_wxh '^([^:]*):' "$hearth_mode"
  set gfxmode="$hearth_wxh,none"
  if terminal_output gfxterm; then
    set gfxmode="$hearth_wxh"
    regexp --set=1:hearth_height ':(.*)$' "$hearth_mode"
    break
  fi
done
if [ -z "$hearth_height" ]; then
  set gfxmode=auto
  terminal_output gfxterm
  set hearth_height=600
fi
set theme="$hearth_dir/h$hearth_height/theme.txt"
export theme
""")
