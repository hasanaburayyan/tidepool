#!/usr/bin/env python3
"""Regenerate every sprite in the game. No arguments, no network, no dependencies.

    python3 art/build.py

Output is deterministic: running it twice with an unchanged palette produces
byte-identical PNGs, so `git status` after a build is the test that nothing drifted.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tiles
from png import Canvas, hex_to_rgb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE_OUT = os.path.join(ROOT, "assets", "tiles")
PREVIEW_OUT = os.path.join(ROOT, "art", "preview")

## Every rock tile that routes water, as a connection mask. These are not seven drawings;
## they are one drawing routine given ten different sets of openings. Adding a shape to
## Tidepool is adding a string to this list.
##
## Rotations are baked as separate PNGs rather than left to a runtime `rotation` on the
## sprite: a 90-degree rotation of a pixel sprite re-samples it, and the upper-left gloss
## would rotate with the tile so a level would end up lit from four different suns.
STRAIGHT_MASKS = ["EW", "NS"]
CORNER_MASKS = ["NE", "ES", "SW", "NW"]
TEE_MASKS = ["NES", "ESW", "NSW", "NEW"]
CROSS_MASKS = ["NESW"]
TILE_MASKS = STRAIGHT_MASKS + CORNER_MASKS + TEE_MASKS + CROSS_MASKS


def load_palette() -> dict:
    with open(os.path.join(ROOT, "art", "palette.json")) as fh:
        data = json.load(fh)
    colors = {k: hex_to_rgb(v) for k, v in data["colors"].items()}
    return {role: colors[key] for role, key in data["roles"].items()}


def scaled(img: Canvas, factor: int) -> Canvas:
    """Nearest-neighbour integer upscale, for contact sheets only. Never for shipped art."""
    out = Canvas(img.width * factor, img.height * factor)
    for y in range(img.height):
        for x in range(img.width):
            rgb = img[x, y]
            for dy in range(factor):
                for dx in range(factor):
                    out[x * factor + dx, y * factor + dy] = rgb
    return out


def greyscale(img: Canvas) -> Canvas:
    """Rec. 709 luma. The proof for rule 1: the board must stay solvable in here."""
    out = Canvas(img.width, img.height)
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = img[x, y]
            v = round(0.2126 * r + 0.7152 * g + 0.0722 * b)
            out[x, y] = (v, v, v)
    return out


def assert_states_match(mask: int, pal: dict, locked: bool = False) -> None:
    """Rule 2, as an assertion instead of a promise.

    Dry and wet must differ on exactly the channel-floor pixels and nowhere else. If a
    future edit puts a highlight on the rock of the wet tile, this fails the build rather
    than shipping a silhouette that pops during the shader tween.
    """
    dry = tiles.render(mask, False, pal, locked=locked)
    wet = tiles.render(mask, True, pal, locked=locked)
    channel = tiles.channel_cells(mask)
    differing = diff_pixels(dry, wet)
    if differing != channel:
        stray = sorted(differing - channel)[:5]
        missing = sorted(channel - differing)[:5]
        raise SystemExit(
            "FAIL %s%s: dry/wet differ outside the channel floor. stray=%s unchanged-floor=%s"
            % (tiles.name_from_mask(mask), " locked" if locked else "", stray, missing)
        )
    print("  ok   %-4s%s dry/wet differ on exactly %d channel pixels"
          % (tiles.name_from_mask(mask), " locked" if locked else "       ", len(channel)))


def diff_pixels(a: Canvas, b: Canvas) -> set:
    return {(x, y) for y in range(a.height) for x in range(a.width) if a[x, y] != b[x, y]}


def assert_locked_is_texture(mask: int, pal: dict) -> None:
    """Locked is a crust on the rock, and the build makes sure it stayed one.

    Three things have to hold or the variant is lying to the player. It may only touch
    rock: not the channel, so the water looks identical and the shader tween is unaffected,
    and not the 1px outline, so the silhouette is pixel-for-pixel the same tile. And it has
    to actually be there in useful quantity - a crust of four pixels is not a signal that a
    tile will refuse to turn.
    """
    name = tiles.name_from_mask(mask)
    plain = tiles.render(mask, True, pal)
    locked = tiles.render(mask, True, pal, locked=True)
    channel = tiles.channel_cells(mask)
    outline = tiles._bank_cells(channel)
    changed = diff_pixels(plain, locked)

    trespass = changed & (channel | outline)
    if trespass:
        raise SystemExit("FAIL %s locked: barnacles touched the channel or outline at %s"
                         % (name, sorted(trespass)[:5]))
    if len(changed) < 20:
        raise SystemExit("FAIL %s locked: only %d barnacle pixels, too faint to read as locked"
                         % (name, len(changed)))
    print("  ok   %-4s locked adds %3d barnacle pixels, none on the channel or outline"
          % (name, len(changed)))


def assert_masks_distinct(pal: dict) -> None:
    """Rule 1, as an assertion instead of a promise.

    Strip the colour out of every tile and they must all still be different pictures. If
    two shapes ever collapse into the same greyscale image, a colourblind player is being
    asked to guess which way the water goes, and the build stops.
    """
    seen = {}
    variants = [(name, lock) for name in TILE_MASKS for lock in (False, True)]
    for name, lock in variants:
        label = name + (" locked" if lock else "")
        img = greyscale(tiles.render(tiles.mask_from_name(name), True, pal, locked=lock))
        key = bytes(v for y in range(img.height) for x in range(img.width) for v in img[x, y])
        if key in seen:
            raise SystemExit("FAIL: %s and %s are the same tile in greyscale" % (seen[key], label))
        seen[key] = label
    print("  ok   %d tile pictures, %d distinct in greyscale" % (len(variants), len(seen)))


def build_family_sheet(pal: dict, locked: bool = False) -> Canvas:
    """Every mask, dry on the top row and wet on the bottom, in mask order.

    Read down a column to check rule 2 by eye - only the channel floor may move. Read
    across a row to check that ten openings produced ten silhouettes.
    """
    sheet = Canvas(tiles.SIZE * len(TILE_MASKS), tiles.SIZE * 2, pal["outline"])
    for i, name in enumerate(TILE_MASKS):
        mask = tiles.mask_from_name(name)
        sheet.blit(tiles.render(mask, False, pal, locked=locked), i * tiles.SIZE, 0)
        sheet.blit(tiles.render(mask, True, pal, locked=locked), i * tiles.SIZE, tiles.SIZE)
    return sheet


def build_locked_comparison(pal: dict) -> Canvas:
    """Free rock on top, barnacled rock below, same mask in each column.

    The comparison is the point: a reviewer has to be able to tell at a glance that only
    the stone changed. Nothing in the channel moves between the two rows, which is what
    lets a locked tile and a free one sit next to each other in a level without the water
    looking like two different substances.
    """
    sheet = Canvas(tiles.SIZE * len(TILE_MASKS), tiles.SIZE * 2, pal["outline"])
    for i, name in enumerate(TILE_MASKS):
        mask = tiles.mask_from_name(name)
        sheet.blit(tiles.render(mask, True, pal), i * tiles.SIZE, 0)
        sheet.blit(tiles.render(mask, True, pal, locked=True), i * tiles.SIZE, tiles.SIZE)
    return sheet


## A 3x3 pool the tide actually crosses, so the new shapes get judged inside a route
## instead of in a row. Tide enters the middle-left tile from the west edge.
JUNCTION_LAYOUT = [
    ["ES", "SW", "NS"],
    ["EW", "NESW", "EW"],
    ["NE", "NEW", "NS"],
]
JUNCTION_SOURCE = (1, 0)  # (row, col)

## (row delta, col delta, opening I need, opening my neighbour needs)
_STEPS = ((-1, 0, "N", "S"), (1, 0, "S", "N"), (0, -1, "W", "E"), (0, 1, "E", "W"))


def flood(layout: list, source: tuple) -> set:
    """Which cells the tide reaches. Two tiles connect only when both open on the shared
    edge, which is the same rule the engine uses, so nothing in the scene is wet because
    I said so."""
    wet = {source}
    frontier = [source]
    while frontier:
        nxt = []
        for (r, c) in frontier:
            mask = tiles.mask_from_name(layout[r][c])
            for dr, dc, mine, theirs in _STEPS:
                nr, nc = r + dr, c + dc
                if not (0 <= nr < len(layout) and 0 <= nc < len(layout[nr])):
                    continue
                if (nr, nc) in wet or not mask & tiles.DIR_BITS[mine]:
                    continue
                if tiles.mask_from_name(layout[nr][nc]) & tiles.DIR_BITS[theirs]:
                    wet.add((nr, nc))
                    nxt.append((nr, nc))
        frontier = nxt
    return wet


def build_junction_scene(pal: dict) -> Canvas:
    """The pool above, wet where the flood fill actually got to.

    Top-right and bottom-right are straights turned the wrong way: the tee below the
    cross pushes water east into solid rock and it stops. That refusal is the whole
    puzzle - a player has to be able to see it before they rotate anything, and here it
    is visible as a channel that ends at a rock face rather than as a colour.
    """
    wet = flood(JUNCTION_LAYOUT, JUNCTION_SOURCE)
    rows, cols = len(JUNCTION_LAYOUT), len(JUNCTION_LAYOUT[0])
    scene = Canvas(tiles.SIZE * cols, tiles.SIZE * rows)
    for r in range(rows):
        for c in range(cols):
            mask = tiles.mask_from_name(JUNCTION_LAYOUT[r][c])
            scene.blit(tiles.render(mask, (r, c) in wet, pal), c * tiles.SIZE, r * tiles.SIZE)
    print("  ok   junction scene: %d of %d tiles reached by the tide" % (len(wet), rows * cols))
    return scene


def build_strip(pal: dict) -> Canvas:
    """Two connected tiles and one that is not, in one image.

    Left and centre are east-west straights: their channels reach the shared edge from
    both sides, so the floor runs through unbroken and the water is continuous. The right
    tile is the same straight rotated - it has no west opening, so the centre tile's
    channel dead-ends into solid rock and the right tile stays dry. Nothing here is
    carried by colour: cover the image in greyscale and the join is still the only place
    two channels meet.
    """
    strip = Canvas(tiles.SIZE * 3, tiles.SIZE)
    strip.blit(tiles.render(tiles.mask_from_name("EW"), True, pal), 0, 0)
    strip.blit(tiles.render(tiles.mask_from_name("EW"), True, pal), tiles.SIZE, 0)
    strip.blit(tiles.render(tiles.mask_from_name("NS"), False, pal), tiles.SIZE * 2, 0)
    return strip


def main() -> None:
    pal = load_palette()
    os.makedirs(TILE_OUT, exist_ok=True)
    os.makedirs(PREVIEW_OUT, exist_ok=True)

    print("checking rule 1 (shape, not hue, carries the route):")
    assert_masks_distinct(pal)

    print("checking rule 2 (dry and wet differ only in channel floor):")
    written = []
    for name in TILE_MASKS:
        mask = tiles.mask_from_name(name)
        for lock in (False, True):
            assert_states_match(mask, pal, locked=lock)
            prefix = "locked" if lock else "channel"
            for wet in (False, True):
                path = os.path.join(TILE_OUT, "%s_%s_%s.png" % (prefix, name, "wet" if wet else "dry"))
                tiles.render(mask, wet, pal, locked=lock).save(path)
                written.append(path)

    print("\nchecking locked is a texture on the rock and nothing else:")
    for name in TILE_MASKS:
        assert_locked_is_texture(tiles.mask_from_name(name), pal)

    strip = build_strip(pal)
    strip.save(os.path.join(PREVIEW_OUT, "strip_1x.png"))
    scaled(strip, 4).save(os.path.join(PREVIEW_OUT, "strip_4x.png"))
    scaled(greyscale(strip), 4).save(os.path.join(PREVIEW_OUT, "strip_4x_greyscale.png"))

    sheet = build_family_sheet(pal)
    scaled(sheet, 3).save(os.path.join(PREVIEW_OUT, "tiles_3x.png"))
    scaled(greyscale(sheet), 3).save(os.path.join(PREVIEW_OUT, "tiles_3x_greyscale.png"))

    compare = build_locked_comparison(pal)
    scaled(compare, 3).save(os.path.join(PREVIEW_OUT, "locked_3x.png"))
    scaled(greyscale(compare), 3).save(os.path.join(PREVIEW_OUT, "locked_3x_greyscale.png"))

    scene = build_junction_scene(pal)
    scaled(scene, 4).save(os.path.join(PREVIEW_OUT, "junction_4x.png"))
    scaled(greyscale(scene), 4).save(os.path.join(PREVIEW_OUT, "junction_4x_greyscale.png"))

    print("\nwrote %d tile sprites to assets/tiles/ and 9 contact sheets to art/preview/" % len(written))
    for p in written:
        print("  " + os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
