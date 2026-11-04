#!/usr/bin/env python3
"""
Fogbound icon generator.

Draws a 64x64 pixel-art icon -- two tethered teammates standing in a pool of
lantern light inside the fog -- and writes:

    icon.svg                              project icon (crisp vector, one <rect> per pixel run)
    assets/icon/fogbound_icon_512.png     store / README size
    assets/icon/fogbound_icon_192.png     Android launcher size

The characters come from tools/make_sprites.py so the icon always matches the
in-game art. Re-run after changing either script:

    pip install pillow
    python3 tools/make_icon.py
"""
import math
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import make_sprites as ms  # noqa: E402

N = 64
RADIUS = 9  # rounded-corner radius, in icon pixels

BG = (20, 24, 36, 255)
FOG = [(34, 40, 58, 255), (46, 54, 76, 255), (62, 72, 98, 255)]
# brightest first: index 0 is the core of the lantern light, 3 the faint outer halo
GLOW = [(176, 150, 92, 255), (132, 112, 72, 255), (92, 82, 64, 255), (58, 58, 70, 255)]
ROPE = (96, 232, 118, 255)
ROPE_SHADE = (44, 120, 62, 255)
TEAM = (230, 89, 64)
TEAM_SHADE = (161, 62, 45)

BAYER = [[0, 2], [3, 1]]  # 2x2 ordered dither


def dither(x, y):
    return BAYER[y % 2][x % 2] / 4.0 - 0.375


def make_icon():
    img = Image.new("RGBA", (N, N), BG)
    px = img.load()

    # fog: wavy horizontal bands that get lighter toward the top
    for y in range(N):
        for x in range(N):
            wave = math.sin(x / 7.0 + y / 5.0) * 2.0 + math.sin(x / 3.0 - y / 9.0)
            level = (N - y) / N * 3.2 + wave * 0.35 + dither(x, y)
            idx = int(level) - 1
            if idx >= 0:
                px[x, y] = FOG[min(idx, len(FOG) - 1)]

    # lantern light: banded radial glow centred between the two figures
    cx, cy = 32.0, 38.0
    for y in range(N):
        for x in range(N):
            d = math.hypot(x - cx, (y - cy) * 1.15) + dither(x, y) * 3.0
            for i, edge in enumerate((8, 14, 20, 26)):  # innermost ring first
                if d < edge:
                    base = px[x, y]
                    glow = GLOW[i]
                    # blend so the fog texture still shows through the light
                    px[x, y] = tuple(min(255, (base[k] + glow[k] * 2) // 3) for k in range(3)) + (255,)
                    break

    # characters (same team -> same scarf colour)
    def recolour(frame_img):
        out = frame_img.copy()
        p = out.load()
        for yy in range(out.height):
            for xx in range(out.width):
                r, g, b, a = p[xx, yy]
                if (r, g, b) == (255, 0, 255):
                    p[xx, yy] = TEAM + (a,)
                elif (r, g, b) == (180, 0, 180):
                    p[xx, yy] = TEAM_SHADE + (a,)
        return out

    left = recolour(ms.frame(ms.CHARACTERS[0], "idle_down", 0))
    right = recolour(ms.frame(ms.CHARACTERS[1], "idle_down", 0))
    top = 24
    img.alpha_composite(left, (14, top))
    img.alpha_composite(right, (34, top))

    # tether between the clasped hands, sagging slightly
    x0, x1, y_hand = 26, 37, top + 11
    for x in range(x0, x1 + 1):
        t = (x - x0) / (x1 - x0)
        sag = round(2.0 * math.sin(math.pi * t))
        px[x, y_hand + sag] = ROPE
        px[x, y_hand + sag + 1] = ROPE_SHADE

    # rounded corners
    for y in range(N):
        for x in range(N):
            dx = max(RADIUS - x, x - (N - 1 - RADIUS), 0)
            dy = max(RADIUS - y, y - (N - 1 - RADIUS), 0)
            if dx * dx + dy * dy > RADIUS * RADIUS:
                px[x, y] = (0, 0, 0, 0)
    return img


def to_svg(img, display=128):
    w, h = img.size
    px = img.load()
    rects = []
    for y in range(h):
        x = 0
        while x < w:
            c = px[x, y]
            if c[3] == 0:
                x += 1
                continue
            run = 1
            while x + run < w and px[x + run, y] == c:
                run += 1
            fill = "#%02x%02x%02x" % c[:3]
            op = "" if c[3] == 255 else ' fill-opacity="%.2f"' % (c[3] / 255)
            rects.append('<rect x="%d" y="%d" width="%d" height="1" fill="%s"%s/>' % (x, y, run, fill, op))
            x += run
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
        'shape-rendering="crispEdges">\n  %s\n</svg>\n' % (display, display, w, h, "\n  ".join(rects))
    )


def main():
    icon = make_icon()
    (ROOT / "icon.svg").write_text(to_svg(icon))
    out = ROOT / "assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)
    icon.resize((512, 512), Image.NEAREST).save(out / "fogbound_icon_512.png")
    icon.resize((192, 192), Image.NEAREST).save(out / "fogbound_icon_192.png")
    print("wrote icon.svg, assets/icon/fogbound_icon_512.png, assets/icon/fogbound_icon_192.png")


if __name__ == "__main__":
    main()
