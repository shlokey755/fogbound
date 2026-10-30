#!/usr/bin/env python3
"""
Fogbound character sprite generator.

Draws four original 16x16 pixel-art characters procedurally and writes one
sprite sheet PNG per character into assets/sprites/characters/. Re-run this
script after changing a design; the PNGs are checked in so the Godot project
doesn't need Python to run.

    pip install pillow
    python3 tools/make_sprites.py            # writes the sheets
    python3 tools/make_sprites.py --preview  # also writes a scaled contact sheet

Sheet layout (6 columns x 8 rows of 16x16 frames -> 96x128 px). Row meanings
and frame counts are mirrored in scripts/player_sprites.gd -- keep the two in
sync if you add an animation.

    row 0  idle_down    (2 frames)      row 4  idle_side  (2 frames, faces right)
    row 1  walk_down    (4 frames)      row 5  walk_side  (4 frames)
    row 2  idle_up      (2 frames)      row 6  pulled     (2 frames)
    row 3  walk_up      (4 frames)      row 7  eliminated (3 frames)

Facing left is the "side" row flipped horizontally at runtime.

Team colour: the scarf is drawn in two marker colours that scripts/shaders
swap for the player's team colour (shaders/team_palette.gdshader):
    MARKER_SCARF        (255,   0, 255) -> team colour
    MARKER_SCARF_SHADOW (180,   0, 180) -> team colour darkened
"""
import sys
from pathlib import Path

from PIL import Image

SIZE = 16
OUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "sprites" / "characters"

OUTLINE = (24, 20, 32, 255)
BOOT = (58, 44, 42, 255)
PANTS = (60, 56, 72, 255)
EYE = (24, 20, 32, 255)
MARKER_SCARF = (255, 0, 255, 255)
MARKER_SCARF_SHADOW = (180, 0, 180, 255)
SHADOW = (0, 0, 0, 70)

# name, skin, cloth, cloth shade, accent
CHARACTERS = [
    # Wanderer: hooded cloak
    dict(name="wanderer", skin=(233, 190, 150, 255), cloth=(84, 96, 128, 255), shade=(62, 72, 100, 255)),
    # Tinker: cap and goggles, olive vest
    dict(name="tinker", skin=(168, 118, 82, 255), cloth=(110, 120, 70, 255), shade=(84, 92, 52, 255)),
    # Sprout: leaf tuft, tan tunic
    dict(name="sprout", skin=(246, 214, 180, 255), cloth=(190, 160, 100, 255), shade=(150, 124, 76, 255)),
    # Warden: steel helmet, red tunic
    dict(name="warden", skin=(158, 110, 78, 255), cloth=(150, 64, 64, 255), shade=(112, 44, 48, 255)),
]

# (row, frame count) -- mirrored in scripts/player_sprites.gd
ANIMS = [
    ("idle_down", 2), ("walk_down", 4), ("idle_up", 2), ("walk_up", 4),
    ("idle_side", 2), ("walk_side", 4), ("pulled", 2), ("eliminated", 3),
]
COLS = 6


class Canvas:
    """Tiny pixel canvas: paint first, then outline, then draw face details."""

    def __init__(self):
        self.px = {}

    def put(self, x, y, color):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.px[(x, y)] = color

    def rect(self, x0, y0, x1, y1, color):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, color)

    def outline(self):
        filled = set(self.px)
        for (x, y) in filled:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in filled and 0 <= n[0] < SIZE and 0 <= n[1] < SIZE:
                    self.px[n] = OUTLINE

    def to_image(self, alpha_scale=1.0):
        img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        for (x, y), c in self.px.items():
            r, g, b, a = c
            img.putpixel((x, y), (r, g, b, int(a * alpha_scale)))
        return img


def head_mask(c, color, top=2):
    """Rounded 8x6 head."""
    c.rect(6, top, 9, top, color)
    c.rect(5, top + 1, 10, top + 1, color)
    c.rect(4, top + 2, 11, top + 4, color)
    c.rect(5, top + 5, 10, top + 5, color)


def draw_head(c, ch, d, bob, worried=False):
    skin, name = ch["skin"], ch["name"]
    t = 2 + bob
    head_mask(c, skin, t)

    if name == "wanderer":
        hood, hood_s = ch["cloth"], ch["shade"]
        c.rect(6, t, 9, t, hood)
        c.rect(5, t + 1, 10, t + 1, hood)
        c.rect(4, t + 2, 11, t + 2, hood)
        c.rect(5, t + 2, 10, t + 2, hood_s) if d != "up" else None
        if d == "down":
            c.rect(4, t + 3, 4, t + 4, hood); c.rect(11, t + 3, 11, t + 4, hood)
        elif d == "up":
            c.rect(4, t + 3, 11, t + 5, hood)
            c.rect(5, t + 5, 10, t + 5, hood_s)
        else:  # side, faces right
            c.rect(4, t + 3, 7, t + 5, hood)
    elif name == "tinker":
        cap, brim = (140, 92, 60, 255), (104, 66, 44, 255)
        c.rect(5, t, 10, t + 1, cap)
        if d == "up":
            c.rect(4, t + 2, 11, t + 4, cap)
            c.rect(4, t + 2, 11, t + 2, brim)
            c.rect(4, t + 3, 11, t + 3, (60, 50, 50, 255))  # goggle strap at the back
        elif d == "down":
            c.rect(4, t + 2, 11, t + 2, brim)
            c.rect(4, t + 3, 11, t + 3, (60, 50, 50, 255))
            c.rect(5, t + 3, 7, t + 3, (150, 220, 230, 255))
            c.rect(8, t + 3, 10, t + 3, (150, 220, 230, 255))
        else:
            c.rect(4, t + 2, 11, t + 2, brim)
            c.rect(4, t + 3, 8, t + 3, (60, 50, 50, 255))
            c.rect(9, t + 3, 11, t + 3, (150, 220, 230, 255))
    elif name == "sprout":
        hair = (120, 84, 56, 255)
        c.rect(5, t, 10, t + 1, hair)
        c.rect(4, t + 2, 11, t + 2, hair)
        if d == "up":
            c.rect(4, t + 3, 11, t + 5, hair)
        elif d == "side":
            c.rect(4, t + 3, 6, t + 4, hair)
        else:
            c.rect(4, t + 3, 4, t + 3, hair); c.rect(11, t + 3, 11, t + 3, hair)
        leaf = (96, 170, 90, 255)
        c.put(8, t - 2, leaf); c.put(7, t - 1, leaf); c.put(8, t - 1, leaf); c.put(9, t - 1, (70, 140, 70, 255))
    else:  # warden
        steel, steel_s = (150, 160, 172, 255), (112, 122, 136, 255)
        c.rect(5, t, 10, t + 1, steel)
        c.rect(4, t + 2, 11, t + 2, steel_s)
        c.rect(7, t - 1, 8, t - 1, (170, 60, 60, 255))  # crest
        if d == "up":
            c.rect(4, t + 3, 11, t + 5, steel)
            c.rect(4, t + 5, 11, t + 5, steel_s)
        elif d == "down":
            c.rect(4, t + 3, 4, t + 4, steel); c.rect(11, t + 3, 11, t + 4, steel)
            c.rect(7, t + 3, 8, t + 5, steel_s)  # nose guard
        else:
            c.rect(4, t + 3, 7, t + 5, steel)
            c.rect(9, t + 3, 9, t + 4, steel_s)


def draw_face(c, d, bob, mood="normal"):
    t = 2 + bob
    if d == "down":
        if mood == "x":
            for ex in (6, 9):
                c.put(ex, t + 4, EYE); c.put(ex + 1, t + 5, EYE)
                c.put(ex + 1, t + 4, EYE); c.put(ex, t + 5, EYE)
        else:
            c.put(6, t + 4, EYE); c.put(9, t + 4, EYE)
            if mood == "worried":
                c.put(6, t + 3, EYE); c.put(9, t + 3, EYE)
    elif d == "side":
        c.put(9, t + 4, EYE)
        if mood == "worried":
            c.put(9, t + 3, EYE)


def draw_torso(c, ch, d, bob, scarf_wave=0, arm_swing=0, reach=False):
    cloth, shade, skin, name = ch["cloth"], ch["shade"], ch["skin"], ch["name"]
    b = bob
    if d == "side":
        c.rect(6, 8 + b, 10, 11 + b, cloth)
        c.rect(6, 11 + b, 10, 11 + b, shade)
        # scarf at the neck, tail streaming behind (left)
        c.rect(6, 8 + b, 10, 8 + b, MARKER_SCARF)
        c.put(5, 9 + b + scarf_wave, MARKER_SCARF); c.put(4, 10 + b + scarf_wave, MARKER_SCARF_SHADOW)
        # near arm and hand
        c.put(9, 9 + b + arm_swing, cloth); c.put(9, 10 + b + arm_swing, cloth)
        c.put(10, 11 + b + arm_swing, skin)
    else:
        c.rect(5, 8 + b, 10, 11 + b, cloth)
        c.rect(5, 11 + b, 10, 11 + b, shade)
        c.rect(5, 8 + b, 10, 8 + b, MARKER_SCARF)
        c.put(10, 9 + b + scarf_wave, MARKER_SCARF); c.put(10, 10 + b + scarf_wave, MARKER_SCARF_SHADOW)
        # arms: hands reach slightly outward ("holding hands")
        up = -2 if reach else 0
        c.put(4, 9 + b - arm_swing, cloth); c.put(4, 10 + b - arm_swing, cloth); c.put(3, 11 + b - arm_swing, skin)
        c.put(11, 9 + b + arm_swing + up, cloth); c.put(11, 10 + b + arm_swing + up, cloth)
        c.put(12, 11 + b + arm_swing + up, skin)
        if name == "warden":
            c.put(4, 8 + b, (150, 160, 172, 255)); c.put(11, 8 + b, (150, 160, 172, 255))


def draw_legs(c, d, left=(6, 0), right=(8, 0), spread=0):
    """Each leg is (x, lift). lift raises the foot by that many rows."""
    for (x, lift), dx in ((left, -spread), (right, spread)):
        x += dx
        c.put(x, 12, PANTS); c.put(x + 1, 12, PANTS)
        if lift == 0:
            c.put(x, 13, PANTS); c.put(x + 1, 13, PANTS)
            c.put(x, 14, BOOT); c.put(x + 1, 14, BOOT)
        else:
            c.put(x, 13, BOOT); c.put(x + 1, 13, BOOT)


def draw_side_legs(c, back_dx, front_dx, back_lift=0, front_lift=0):
    for x, lift in ((6 + back_dx, back_lift), (8 + front_dx, front_lift)):
        c.put(x, 12, PANTS); c.put(x + 1, 12, PANTS)
        if lift == 0:
            c.put(x, 13, PANTS); c.put(x + 1, 13, PANTS)
            c.put(x, 14, BOOT); c.put(x + 1, 14, BOOT)
        else:
            c.put(x, 13, BOOT); c.put(x + 1, 13, BOOT)


def ground_shadow(c):
    for x in range(5, 11):
        c.px.setdefault((x, 15), SHADOW)


WALK_BOB = [0, -1, 0, -1]
WALK_SWING = [1, 0, -1, 0]


def frame(ch, anim, i):
    c = Canvas()
    alpha = 1.0

    if anim.startswith("idle") or anim.startswith("walk"):
        d = anim.split("_")[1]
        walking = anim.startswith("walk")
        bob = WALK_BOB[i] if walking else 0
        swing = WALK_SWING[i] if walking else 0
        wave = i % 2

        if d == "side":
            if walking:
                poses = [(-1, 1, 0, 0), (0, 0, 0, 0), (1, -1, 0, 0), (0, 0, 0, 0)]
                bdx, fdx, bl, fl = poses[i]
                # lift the trailing foot on the passing frames
                if i == 1: fl = 1
                if i == 3: bl = 1
                draw_side_legs(c, bdx, fdx, bl, fl)
            else:
                draw_side_legs(c, 0, 0)
        else:
            if walking:
                legs = [((6, 0), (8, 1)), ((6, 0), (8, 0)), ((6, 1), (8, 0)), ((6, 0), (8, 0))]
                draw_legs(c, d, *legs[i])
            else:
                draw_legs(c, d)

        draw_torso(c, ch, d, bob, scarf_wave=wave, arm_swing=swing)
        draw_head(c, ch, d, bob)
        c.outline()
        draw_face(c, d, bob)
        ground_shadow(c)

    elif anim == "pulled":
        # braced, leaning back, one arm up, wide stance, worried eyes
        draw_legs(c, "down", left=(5, 0), right=(9, 0))
        draw_torso(c, ch, "down", 0, scarf_wave=i, arm_swing=0, reach=True)
        draw_head(c, ch, "down", 0)
        c.outline()
        draw_face(c, "down", 0, mood="worried")
        ground_shadow(c)

    elif anim == "eliminated":
        # sink into the fog: crouch, ghost, then a faded pile of cloth
        if i == 0:
            draw_legs(c, "down", left=(5, 1), right=(9, 1))
            draw_torso(c, ch, "down", 2, scarf_wave=1)
            draw_head(c, ch, "down", 2)
            c.outline()
            draw_face(c, "down", 2, mood="x")
        elif i == 1:
            alpha = 0.6
            draw_torso(c, ch, "down", 3, scarf_wave=1)
            draw_head(c, ch, "down", 3)
            c.outline()
            draw_face(c, "down", 3, mood="x")
        else:
            alpha = 0.35
            c.rect(4, 11, 11, 13, ch["cloth"])
            c.rect(4, 13, 11, 13, ch["shade"])
            c.rect(5, 10, 10, 10, MARKER_SCARF)
            c.outline()
        ground_shadow(c)

    return c.to_image(alpha)


def build_sheet(ch):
    sheet = Image.new("RGBA", (SIZE * COLS, SIZE * len(ANIMS)), (0, 0, 0, 0))
    for row, (anim, count) in enumerate(ANIMS):
        for i in range(count):
            sheet.paste(frame(ch, anim, i), (i * SIZE, row * SIZE))
    return sheet


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheets = []
    for idx, ch in enumerate(CHARACTERS):
        sheet = build_sheet(ch)
        path = OUT_DIR / f"char_{idx}_{ch['name']}.png"
        sheet.save(path)
        sheets.append(sheet)
        print(f"wrote {path.relative_to(OUT_DIR.parent.parent.parent)}")

    if "--preview" in sys.argv:
        scale = 5
        w, h = sheets[0].size
        pad = 8
        preview = Image.new("RGBA", ((w * scale + pad) * len(sheets), h * scale), (46, 48, 62, 255))
        for i, s in enumerate(sheets):
            # recolour marker magenta to a sample team colour for the preview only
            s2 = s.copy()
            for y in range(s2.height):
                for x in range(s2.width):
                    r, g, b, a = s2.getpixel((x, y))
                    if (r, g, b) == (255, 0, 255):
                        s2.putpixel((x, y), (230, 90, 60, a))
                    elif (r, g, b) == (180, 0, 180):
                        s2.putpixel((x, y), (160, 60, 40, a))
            preview.alpha_composite(s2.resize((w * scale, h * scale), Image.NEAREST), ((w * scale + pad) * i, 0))
        out = Path("/tmp/fogbound_sprite_preview.png")
        preview.save(out)
        print(f"preview: {out}")


if __name__ == "__main__":
    main()
