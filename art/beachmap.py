#!/usr/bin/env python3
"""Beach map mock: a six-pool stretch in all three pool states, colour and greyscale.

    python3 art/beachmap.py

A mock for the Director, not shipped art - kept out of build.py until the look is agreed.
Spec: tidepool-beach-map. The rule it has to pass is hers: "print it in greyscale and it
must still be readable." So the load-bearing difference between states is a silhouette -
water or no water - and stars are shells you COUNT, never a fill you judge.
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tiles
from png import Canvas, hex_to_rgb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "preview")

W, H = 282, 84
RX, RY = 17, 11           # pool half-extents at 1x

## Left to right reads as progress: finished pools, the one you are on, then the ones ahead.
## (number, state, shells) - state is "locked", "open" or "done".
STRETCH = [(7, "done", 3), (8, "done", 2), (9, "done", 1),
           (10, "open", 0), (11, "locked", 0), (12, "locked", 0)]

## 3x5 digits. Numbers are the only text on the map, so they get their own font rather
## than a system one that would anti-alias.
DIGITS = {
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "001", "001", "001"],
    "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
}

## A scallop shell, 7x5. Filled = earned, outline only = not yet.
SHELL = ["..###..", ".#####.", "#######", ".#####.", "..#.#.."]


def neighbours8(p):
    return [(p[0] + dx, p[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx, dy) != (0, 0)]


def pool_cells(cx: int, cy: int, seed: int) -> set:
    """An irregular pool. A coastline is lumpy, and a lumpy pool is also a memorable one -
    the spec wants a player to find number 17 again by its shape and place."""
    cells = set()
    for y in range(cy - RY - 4, cy + RY + 5):
        for x in range(cx - RX - 4, cx + RX + 5):
            nx, ny = (x - cx) / RX, (y - cy) / RY
            a = math.atan2(ny, nx)
            lump = 0.13 * math.cos(3 * a + seed) + 0.08 * math.cos(5 * a + 2.1 * seed)
            if math.hypot(nx, ny) <= 1.0 + lump:
                cells.add((x, y))
    return cells


def draw_text(img: Canvas, text: str, cx: int, cy: int, colour, scale: int = 2) -> None:
    w = (len(text) * 4 - 1) * scale
    x0, y0 = cx - w // 2, cy - (5 * scale) // 2
    for i, ch in enumerate(text):
        for row, bits in enumerate(DIGITS[ch]):
            for col, b in enumerate(bits):
                if b == "1":
                    for dy in range(scale):
                        for dx in range(scale):
                            img[x0 + (i * 4 + col) * scale + dx, y0 + row * scale + dy] = colour


def draw_shell(img: Canvas, x0: int, y0: int, filled: bool, pal: dict) -> None:
    body = {(x0 + c, y0 + r) for r, line in enumerate(SHELL) for c, ch in enumerate(line) if ch == "#"}
    ring = {q for p in body for q in neighbours8(p) if q not in body}
    for p in ring:
        img[p] = pal["outline"]
    for p in body:
        # Unearned is outline-only: the interior is sand, so the shell is a hole you can see
        # the shape of. Earned is a solid Coral shape. A 1-shell and a 3-shell pool differ
        # in how many SOLID things sit on the rim, which survives greyscale and colour-blindness.
        img[p] = pal["critter"] if filled else pal["rock_body"]


def render(pal: dict) -> Canvas:
    img = Canvas(W, H, pal["rock_body"])
    for y in range(H):
        for x in range(W):
            if tiles._is_speckle(x, y):
                img[x, y] = pal["rock_speckle"]

    for i, (num, state, shells) in enumerate(STRETCH):
        # A gentle arc, irregular spacing - no grid, no evenly spaced dots.
        cx = 26 + i * 46 + (3 if i % 2 else -2)
        cy = 50 - int(10 * math.sin(math.pi * (i + 0.5) / len(STRETCH)))
        cells = pool_cells(cx, cy, seed=num)
        ring = {q for p in cells for q in neighbours8(p) if q not in cells}
        for p in ring:
            img[p] = pal["outline"]

        if state == "locked":
            # Dry rock: no water at all. The whole distinction lives here - a pool that
            # holds nothing is a different SHAPE of picture from one that holds water.
            for (x, y) in cells:
                img[x, y] = pal["rock_body"]
                h = (x * 2654435761 + y * 40503) & 0xFFFFFFFF
                # Keep the crust off the number: a locked pool still has to say which pool it is.
                if abs(x - cx) <= 8 and abs(y - cy) <= 7:
                    continue
                if (h ^ (h >> 15)) % 23 == 0:
                    for q in ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)):
                        if q in cells:
                            img[q] = pal["outline"]    # the same limpet ring as locked tiles
        else:
            for (x, y) in cells:
                img[x, y] = pal["channel_wet"]
                # The channel's own vocabulary: gloss where water meets the rim upper-left,
                # a dashed ripple inside. Same sun, same water, as every tile in the game.
                if (x, y - 1) in ring or (x - 1, y) in ring:
                    img[x, y] = pal["channel_gloss"]
                elif (x + y) % 7 == 0 and (x - 3, y) in cells and (x, y - 3) in cells and y > cy:
                    img[x, y] = pal["channel_gloss"]

        # Shells ride the upper rim, three positions, always left to right. Locked pools
        # get none - the spec's "rim: nothing".
        if state != "locked":
            top = min(y for (x, y) in cells if abs(x - cx) <= 1)
            for s in range(3):
                draw_shell(img, cx - 13 + s * 9, top - 4, s < shells, pal)

        draw_text(img, str(num), cx, cy + 1, pal["outline"])
    return img


def scaled(img: Canvas, k: int) -> Canvas:
    out = Canvas(img.width * k, img.height * k)
    for y in range(img.height):
        for x in range(img.width):
            for dy in range(k):
                for dx in range(k):
                    out[x * k + dx, y * k + dy] = img[x, y]
    return out


def greyscale(img: Canvas) -> Canvas:
    out = Canvas(img.width, img.height)
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = img[x, y]
            v = round(0.2126 * r + 0.7152 * g + 0.0722 * b)
            out[x, y] = (v, v, v, a)
    return out


def luma(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def assert_map_reads(pal: dict) -> None:
    """The Director's rule as a check: every signal on the map must survive greyscale."""
    checks = {
        "water vs dry (the state that matters most)": (pal["channel_wet"], pal["rock_body"]),
        "earned shell vs unearned shell": (pal["critter"], pal["rock_body"]),
        "pool number on water": (pal["outline"], pal["channel_wet"]),
        "pool number on dry rock": (pal["outline"], pal["rock_body"]),
    }
    for what, (a, b) in checks.items():
        gap = abs(luma(a) - luma(b))
        if gap < 60:
            raise SystemExit("FAIL beach map: %s is only %.0f luma apart" % (what, gap))
        print("  ok   %-45s %3.0f luma apart" % (what, gap))


if __name__ == "__main__":
    with open(os.path.join(ROOT, "art", "palette.json")) as fh:
        data = json.load(fh)
    colours = {k: hex_to_rgb(v) for k, v in data["colors"].items()}
    pal = {role: colours[key] for role, key in data["roles"].items()}
    assert_map_reads(pal)
    img = render(pal)
    scaled(img, 3).save(os.path.join(OUT, "beachmap_mock_3x.png"))
    scaled(greyscale(img), 3).save(os.path.join(OUT, "beachmap_mock_3x_greyscale.png"))
    print("wrote art/preview/beachmap_mock_3x.png and its greyscale twin")
