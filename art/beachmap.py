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
from png import Canvas, TRANSPARENT, hex_to_rgb

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


def paint_pool(img: Canvas, cells: set, cx: int, cy: int, locked: bool, pal: dict) -> set:
    """Outline and interior of one pool. Shared by the mock and the shipped sprites, so the
    art the Director signed off on is literally the art that ships."""
    ring = {q for p in cells for q in neighbours8(p) if q not in cells}
    for p in ring:
        img[p] = pal["outline"]

    if locked:
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
    return ring


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
        paint_pool(img, cells, cx, cy, state == "locked", pal)

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


## ===========================================================================
## The shipped map. Keys fixed by Marlow, all in assets/map/:
##   beach  pool_locked|open|done  shell_filled|empty  digit_0..9  layout.json
##
## Everything is authored at 1x (480x320) and shipped at SCALE=2 (960x640), baked with
## nearest-neighbour, so the scene draws every asset 1:1 in beach pixels and never has to
## scale pixel art itself. layout.json holds exact top-left placements for every pool,
## shell and digit, exported from here - nobody copies a coordinate by hand.
## ===========================================================================

MAP_W, MAP_H, SCALE = 480, 320, 2
POOL_SEED = 7               # the generic pool shape; per-pool shapes are Maren's call later
POOL_BOX = (44, 30)         # 1x canvas for one pool, centred on its middle pixel

## (first level, last level, row y). Tier breaks land exactly at 13 and 19, per the spec:
## the vocabulary changes there, and the player should SEE they have moved down the beach.
ROWS = [(1, 6, 64), (7, 12, 118), (13, 18, 194)]      # 19-24 sit on the waterline itself


def wetline(x: int) -> int:
    """Where dry sand turns to wet. Above it: high beach, pools 1-12."""
    return 152 + int(4 * math.sin(x / 23.0) + 2 * math.sin(x / 9.1))


def waterline(x: int) -> int:
    """Where wet sand meets the shallows. Pools 19-24 sit ON this line, not near it."""
    return 268 + int(3 * math.sin(x / 19.0) + 2 * math.sin(x / 7.3))


def terrain(x: int, y: int) -> str:
    if y >= waterline(x):
        return "water"
    return "wet" if y >= wetline(x) else "dry"


def pool_centres() -> dict:
    """Two arcs of six on the high beach, one row on the wet sand, one at the water's edge.

    Irregular on purpose - jitter keyed to the level number, so a pool's place is part of
    its identity and someone looking for number 17 finds it by where it sits.
    """
    out = {}
    for first, last, y0 in ROWS + [(19, 24, None)]:
        n = last - first + 1
        for i in range(n):
            lvl = first + i
            x = 60 + i * 72 + ((lvl * 37) % 11 - 5)
            if y0 is None:
                # Derived from the water, not tuned by eye: the pool's lower rim sits in the
                # shallows, which is the spec's "shallow water lapping the lower rim".
                y = waterline(x) - RY + 1
            else:
                y = y0 - int(8 * math.sin(math.pi * (i + 0.5) / n)) + ((lvl * 53) % 7 - 3)
            out[lvl] = (x, y)
    return out


def render_beach(pal: dict) -> Canvas:
    """Three tiers, top to bottom, and each one reads without colour.

    Dry to wet sand is 65 luma apart and carries itself. Wet sand to water is only 19
    apart - the same trap as the channel floor - so the shoreline is carried by TEXTURE:
    a Shimmer foam line and dashed glints in the water, lighter ripple crests on the wet
    sand. Same answer, same reason, as every wet tile in the game.
    """
    img = Canvas(MAP_W, MAP_H, pal["rock_body"])
    for y in range(MAP_H):
        for x in range(MAP_W):
            t = terrain(x, y)
            if t == "water":
                wl = waterline(x)
                edge = y - wl < 2
                glint = y > wl + 4 and (x + 3 * y) % 11 == 0 and (x // 4 + y) % 3 == 0
                img[x, y] = pal["channel_gloss"] if (edge or glint) else pal["channel_wet"]
            elif t == "wet":
                depth = y - wetline(x)
                crest = depth > 3 and depth % 9 == 0 and (x // 3 + depth) % 4 != 0
                img[x, y] = pal["rock_body"] if crest else pal["channel_dry"]
            elif tiles._is_speckle(x, y):
                img[x, y] = pal["rock_speckle"]
    return img


def _cells_at(cx: int, cy: int) -> set:
    return pool_cells(cx, cy, seed=POOL_SEED)


def pool_sprite(state: str, pal: dict) -> Canvas:
    """One pool on a transparent canvas. open and done are the SAME picture on purpose:
    the spec says both hold water with a glint, and the shells are what differ."""
    w, h = POOL_BOX
    img = Canvas(w, h, TRANSPARENT)
    paint_pool(img, _cells_at(w // 2, h // 2), w // 2, h // 2, state == "locked", pal)
    return img


def shell_sprite(filled: bool, pal: dict) -> Canvas:
    img = Canvas(len(SHELL[0]) + 2, len(SHELL) + 2, TRANSPARENT)
    draw_shell(img, 1, 1, filled, pal)
    return img


def digit_sprite(ch: str, pal: dict) -> Canvas:
    img = Canvas(6, 10, TRANSPARENT)
    draw_text(img, ch, 3, 5, pal["outline"])
    return img


def layout() -> dict:
    """Every placement the scene needs, as absolute top-left positions in beach pixels."""
    w, h = POOL_BOX
    top_rel = min(y for (x, y) in _cells_at(0, 0) if abs(x) <= 1)
    pools = []
    for lvl, (cx, cy) in sorted(pool_centres().items()):
        text = str(lvl)
        x0 = cx - ((len(text) * 4 - 1) * 2) // 2
        y0 = (cy + 1) - 5
        pools.append({
            "level": lvl,
            "x": cx * SCALE, "y": cy * SCALE,
            "pool": [(cx - w // 2) * SCALE, (cy - h // 2) * SCALE],
            "shells": [[(cx - 14 + s * 9) * SCALE, (cy + top_rel - 5) * SCALE] for s in range(3)],
            "digits": [[(x0 + i * 8) * SCALE, y0 * SCALE] for i in range(len(text))],
        })
    return {"scale": SCALE, "size": [MAP_W * SCALE, MAP_H * SCALE], "pools": pools}


def assert_layout() -> None:
    """The spec as checks: 24 pools, one screen, no overlaps, tier breaks at 13 and 19."""
    centres = pool_centres()
    if sorted(centres) != list(range(1, 25)):
        raise SystemExit("FAIL map: levels are not exactly 1..24")
    boxes = {}
    for lvl, (cx, cy) in centres.items():
        cells = _cells_at(cx, cy)
        xs, ys = [p[0] for p in cells], [p[1] for p in cells]
        box = (min(xs) - 1, min(ys) - 7, max(xs) + 1, max(ys) + 1)   # -7: shells on the rim
        if box[0] < 4 or box[1] < 4 or box[2] > MAP_W - 4 or box[3] > MAP_H - 4:
            raise SystemExit("FAIL map: pool %d runs off the one screen %s" % (lvl, box))
        boxes[lvl] = (box, cells)
        low = max(ys)
        lowx = [p[0] for p in cells if p[1] == low][0]
        if lvl <= 12 and low >= wetline(lowx) - 2:
            raise SystemExit("FAIL map: pool %d (high beach) touches wet sand" % lvl)
        if 13 <= lvl <= 18 and not (min(ys) - 7 > wetline(cx) and low < waterline(lowx) - 2):
            raise SystemExit("FAIL map: pool %d (mid beach) is not on the wet sand" % lvl)
        if lvl >= 19 and low < waterline(lowx) - 1:
            raise SystemExit("FAIL map: pool %d (water's edge) is not in the water" % lvl)
    levels = sorted(boxes)
    for i, a in enumerate(levels):
        for b in levels[i + 1:]:
            (ax0, ay0, ax1, ay1), _ = boxes[a]
            (bx0, by0, bx1, by1), _ = boxes[b]
            if ax0 < bx1 + 3 and bx0 < ax1 + 3 and ay0 < by1 + 3 and by0 < ay1 + 3:
                raise SystemExit("FAIL map: pools %d and %d overlap" % (a, b))
    print("  ok   24 pools on one screen, none overlapping, tiers break at 13 and 19")


def write_assets(pal: dict, root: str) -> list:
    assert_map_reads(pal)
    assert_layout()
    out = os.path.join(root, "assets", "map")
    os.makedirs(out, exist_ok=True)
    written = []

    def save(img, name):
        path = os.path.join(out, name + ".png")
        scaled(img, SCALE).save(path)
        written.append(path)

    save(render_beach(pal), "beach")
    for state in ("locked", "open", "done"):
        save(pool_sprite(state, pal), "pool_" + state)
    save(shell_sprite(True, pal), "shell_filled")
    save(shell_sprite(False, pal), "shell_empty")
    for d in "0123456789":
        save(digit_sprite(d, pal), "digit_" + d)
    with open(os.path.join(out, "layout.json"), "w") as fh:
        json.dump(layout(), fh, indent=1)
        fh.write("\n")
    written.append(os.path.join(out, "layout.json"))
    return written


def compose_preview(pal: dict, progress: dict) -> Canvas:
    """The map drawn exactly as the scene will: shipped sprites, blitted 1:1 at layout
    positions. So the preview tests the CONTRACT, not a second drawing of the map."""
    def big(img):
        return scaled(img, SCALE)
    beach = big(render_beach(pal))
    sprites = {s: big(pool_sprite(s, pal)) for s in ("locked", "open", "done")}
    shells = {True: big(shell_sprite(True, pal)), False: big(shell_sprite(False, pal))}
    digits = {d: big(digit_sprite(d, pal)) for d in "0123456789"}
    for p in layout()["pools"]:
        state, stars = progress.get(p["level"], ("locked", 0))
        beach.over(sprites[state], *p["pool"])
        if state != "locked":
            for s, (x, y) in enumerate(p["shells"]):
                beach.over(shells[s < stars], x, y)
        for ch, (x, y) in zip(str(p["level"]), p["digits"]):
            beach.over(digits[ch], x, y)
    return beach


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
