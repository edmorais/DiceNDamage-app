#!/usr/bin/env python3
"""Draw the launcher icon: the app's own d20 in front of its own impact burst,
in Dragon's Hoard, the scheme the app opens on.

The Dice Roller's icon is the gold d20 alone. The burst behind this one -- the
same eleven uneven spikes as the Damage tab's icon, in the crit colour -- is
what tells the two apart on a home screen.

Drawn at four times 512 and downsampled, because PIL's polygons have no
anti-aliasing and the mdpi icon is only 48 pixels.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

# Dragon's Hoard, the same hex values palettes.lua carries.
BG    = (0x1C, 0x18, 0x15, 255)      # panel
EDGE  = (0x2E, 0x26, 0x20, 255)
GOLD  = (0xE0, 0xA5, 0x26, 255)      # accent
LIGHT = (0xF2, 0xC1, 0x4E, 255)      # barHigh
CRIT  = (0xFF, 0x7A, 0x45, 255)      # crit
INK   = (0x12, 0x10, 0x0E, 255)      # bg

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# The burst from game/icons.lua, in its 24-unit box.
OUTER = [12, 8, 11, 9.5, 12, 7.5, 10.5, 9, 12, 8.5, 10.2]
INNER = [6.2, 5.6, 6.6, 5.8, 6.2, 5.4, 6.4, 6.0, 5.8, 6.4, 5.6]
SKEW = [0, 6, -4, 5, -3, 4, -6, 2, -2, 5, -4]

# What the LÖVE shell's manifest already points at, per density.
DENSITIES = {
    "res/drawable-mdpi-v4/love.png": 48,
    "res/drawable-hdpi-v4/love.png": 72,
    "res/drawable-xhdpi-v4/love.png": 96,
    "res/drawable-xxhdpi-v4/love.png": 144,
    "res/drawable-xxxhdpi-v4/love.png": 192,
}


def burst(cx, cy, unit):
    pts, n, rot = [], len(OUTER), math.radians(-75)
    for k in range(n):
        a = rot + k * 2 * math.pi / n + math.radians(SKEW[k])
        pts.append((cx + math.cos(a) * OUTER[k] * unit, cy + math.sin(a) * OUTER[k] * unit))
        b = rot + (k + 0.5) * 2 * math.pi / n
        pts.append((cx + math.cos(b) * INNER[k] * unit, cy + math.sin(b) * INNER[k] * unit))
    return pts


def hexagon(cx, cy, r, rot=-math.pi / 2):
    return [(cx + math.cos(rot + i * math.pi / 3) * r,
             cy + math.sin(rot + i * math.pi / 3) * r) for i in range(6)]


def render(size=512, ss=4):
    s = size * ss
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22),
                        fill=BG, outline=EDGE, width=max(1, s // 128))

    c = s / 2
    d.polygon(burst(c, c, s * 0.445 / 12), fill=CRIT)

    r = s * 0.27
    hexa = hexagon(c, c, r)
    d.polygon(hexa, fill=GOLD)
    d.line(hexa + [hexa[0]], fill=LIGHT, width=max(2, s // 48), joint="curve")
    font = ImageFont.truetype(FONT, int(s * 0.21))
    x0, y0, x1, y1 = d.textbbox((0, 0), "20", font=font)
    d.text((c - (x1 - x0) / 2 - x0, c - (y1 - y0) / 2 - y0), "20", font=font, fill=INK)
    return im.resize((size, size), Image.LANCZOS)


def write(root):
    master = render()
    out = []
    for path, px in DENSITIES.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        master.resize((px, px), Image.LANCZOS).save(full, "PNG", optimize=True)
        out.append(full)
    return master, out


if __name__ == "__main__":
    master, files = write("/tmp/icons")
    master.save("/tmp/icon-512.png")
    print("\n".join(files))
