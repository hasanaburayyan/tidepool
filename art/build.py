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

## Shipping this PR: the straight channel only. tiles.render() already draws corner, tee
## and cross from the same masks; they land in their own PRs with their own review, per
## the Director's one-family-per-PR rule.
TILE_MASKS = ["EW", "NS"]


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


def assert_states_match(mask: int, pal: dict) -> None:
    """Rule 2, as an assertion instead of a promise.

    Dry and wet must differ on exactly the channel-floor pixels and nowhere else. If a
    future edit puts a highlight on the rock of the wet tile, this fails the build rather
    than shipping a silhouette that pops during the shader tween.
    """
    dry = tiles.render(mask, False, pal)
    wet = tiles.render(mask, True, pal)
    channel = tiles.channel_cells(mask)
    differing = {(x, y) for y in range(tiles.SIZE) for x in range(tiles.SIZE) if dry[x, y] != wet[x, y]}
    if differing != channel:
        stray = sorted(differing - channel)[:5]
        missing = sorted(channel - differing)[:5]
        raise SystemExit(
            "FAIL %s: dry/wet differ outside the channel floor. stray=%s unchanged-floor=%s"
            % (tiles.name_from_mask(mask), stray, missing)
        )
    print("  ok   %-4s dry/wet differ on exactly %d channel pixels" % (tiles.name_from_mask(mask), len(channel)))


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

    print("checking rule 2 (dry and wet differ only in channel floor):")
    written = []
    for name in TILE_MASKS:
        mask = tiles.mask_from_name(name)
        assert_states_match(mask, pal)
        for wet in (False, True):
            path = os.path.join(TILE_OUT, "channel_%s_%s.png" % (name, "wet" if wet else "dry"))
            tiles.render(mask, wet, pal).save(path)
            written.append(path)

    strip = build_strip(pal)
    strip.save(os.path.join(PREVIEW_OUT, "strip_1x.png"))
    scaled(strip, 4).save(os.path.join(PREVIEW_OUT, "strip_4x.png"))
    scaled(greyscale(strip), 4).save(os.path.join(PREVIEW_OUT, "strip_4x_greyscale.png"))

    print("\nwrote %d tile sprites to assets/tiles/ and 3 contact sheets to art/preview/" % len(written))
    for p in written:
        print("  " + os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
