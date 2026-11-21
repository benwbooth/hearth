#!/usr/bin/env python3
"""Render hearth's Plymouth images.

Usage: mkassets.py OUT SNOWFLAKE_SVG

Plymouth's script plugin can only scale images, which blurs them, so every
image comes pre-rendered in a ladder of sizes and hearth.script picks the one
that fits the screen:
  logo-N.png   white snowflake, N px square (48..512 in steps of 8)
  capl-N.png   left/right half of an N px tall pill (even N, 2..128), for the
  capr-N.png   progress bar and the password field
  dot-N.png    filled circle, N px across (even N, 4..48), password bullets
  px.png       white square, stretched into the middle of a pill
Needs resvg on PATH.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw

out, snowflake = sys.argv[1:3]
os.makedirs(out, exist_ok=True)

# The artwork's white logo carries shading where the lambdas overlap; macOS's
# boot logo is a flat silhouette, so keep only the alpha of the colour logo.
for n in range(48, 513, 8):
    dst = f"{out}/logo-{n}.png"
    subprocess.run(["resvg", "-w", str(n), "-h", str(n), snowflake, dst],
                   check=True)
    alpha = Image.open(dst).convert("RGBA").getchannel("A")
    flat = Image.new("RGBA", alpha.size, (255, 255, 255, 255))
    flat.putalpha(alpha)
    flat.save(dst, optimize=True)

SS = 8


def circle(n):
    big = Image.new("RGBA", (n * SS, n * SS), (255, 255, 255, 0))
    ImageDraw.Draw(big).ellipse([0, 0, n * SS - 1, n * SS - 1],
                                fill=(255, 255, 255, 255))
    return big.resize((n, n), Image.LANCZOS)


for n in range(2, 129, 2):
    c = circle(n)
    c.crop((0, 0, n // 2, n)).save(f"{out}/capl-{n}.png")
    c.crop((n // 2, 0, n, n)).save(f"{out}/capr-{n}.png")

for n in range(4, 49, 2):
    circle(n).save(f"{out}/dot-{n}.png")

Image.new("RGBA", (4, 4), (255, 255, 255, 255)).save(f"{out}/px.png")
