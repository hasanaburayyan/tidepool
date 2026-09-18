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
            r, g, b, a = img[x, y]
            v = round(0.2126 * r + 0.7152 * g + 0.0722 * b)
            out[x, y] = (v, v, v, a)
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


## The format only allows a sponge on a straight, so this is the whole family: four files.
SPONGE_MASKS = ["EW", "NS"]


def assert_sponge_swells(mask: int, pal: dict) -> None:
    """"Full" is an objective complete, so it has to be a change of silhouette.

    Three claims, all checkable. The sponge only ever grows, so the change reads as
    swelling rather than as a different tile appearing. It grows enough to see from across
    the board. And the dry sponge is not just a channel with a lump in it - desaturated,
    it is a different picture from the plain channel of the same mask, because a player has
    to know a tile is thirsty *before* they route water into it.
    """
    name = tiles.name_from_mask(mask)
    dry_body = tiles.sponge_body(mask, False)
    full_body = tiles.sponge_body(mask, True)

    if not dry_body < full_body:
        raise SystemExit("FAIL sponge %s: full is not a strict superset of dry - it must only swell" % name)
    growth = len(full_body) - len(dry_body)
    if growth < 150:
        raise SystemExit("FAIL sponge %s: swells by only %d pixels, too quiet for an objective" % (name, growth))

    plain = greyscale(tiles.render(mask, False, pal))
    thirsty = greyscale(tiles.render_sponge(mask, False, pal))
    if not diff_pixels(plain, thirsty):
        raise SystemExit("FAIL sponge %s: dry sponge is indistinguishable from a plain channel" % name)
    print("  ok   %-4s swells %d -> %d pixels (+%d), and reads as thirsty rock when dry"
          % (name, len(dry_body), len(full_body), growth))


def build_sponge_sheet(pal: dict) -> Canvas:
    """Plain channel, dry sponge, full sponge - in a row, per mask.

    Three tiles because the sponge has to lose two arguments at once: it must not look like
    a channel, and full must not look like dry.
    """
    cols = []
    for name in SPONGE_MASKS:
        mask = tiles.mask_from_name(name)
        cols += [tiles.render(mask, False, pal), tiles.render_sponge(mask, False, pal),
                 tiles.render_sponge(mask, True, pal)]
    sheet = Canvas(tiles.SIZE * len(cols), tiles.SIZE, pal["outline"])
    for i, img in enumerate(cols):
        sheet.blit(img, i * tiles.SIZE, 0)
    return sheet


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


def parse_cell(cell: str) -> tuple:
    """"EW" is a plain channel; "EW>E" is the same channel as a one-way exiting east."""
    if ">" in cell:
        name, out = cell.split(">")
        return name, out
    return cell, None


def _can_exit(cell: str, side: str) -> bool:
    name, out = parse_cell(cell)
    if not tiles.mask_from_name(name) & tiles.DIR_BITS[side]:
        return False
    return out is None or side == out


def _can_enter(cell: str, side: str) -> bool:
    name, out = parse_cell(cell)
    if not tiles.mask_from_name(name) & tiles.DIR_BITS[side]:
        return False
    # `tile.gd:can_enter_from` - water cannot swim back in against the arrow.
    return out is None or side != out


def flood(layout: list, source: tuple) -> set:
    """Which cells the tide reaches, by the engine's rules rather than by my say-so.

    Two plain tiles connect only when both open on the shared edge. A one-way additionally
    refuses to be entered through the side its arrow points out of, which is the whole
    mechanic of levels 13 to 18 - so the preview cannot show an arrow passing water it
    would actually stop, and cannot show one refusing water it would actually pass.
    """
    wet = {source}
    frontier = [source]
    while frontier:
        nxt = []
        for (r, c) in frontier:
            for dr, dc, mine, theirs in _STEPS:
                nr, nc = r + dr, c + dc
                if not (0 <= nr < len(layout) and 0 <= nc < len(layout[nr])):
                    continue
                if (nr, nc) in wet or not _can_exit(layout[r][c], mine):
                    continue
                if _can_enter(layout[nr][nc], theirs):
                    wet.add((nr, nc))
                    nxt.append((nr, nc))
        frontier = nxt
    return wet


def refusals(layout: list, wet: set) -> set:
    """One-way cells that are dry while wet water presses on the side they point out of.

    This is the exact situation level 14 builds its lesson around: a locked tee staring
    into an arrow that points back at it. Computing it rather than declaring it means the
    contact sheet cannot label a tile "refusing" unless it really is.
    """
    out = set()
    for r, row in enumerate(layout):
        for c, cell in enumerate(row):
            _, exit_dir = parse_cell(cell)
            if exit_dir is None or (r, c) in wet:
                continue
            for dr, dc, mine, theirs in _STEPS:
                nr, nc = r + dr, c + dc
                if not (0 <= nr < len(layout) and 0 <= nc < len(layout[nr])):
                    continue
                if mine == exit_dir and (nr, nc) in wet and _can_exit(layout[nr][nc], theirs):
                    out.add((r, c))
    return out


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


## Five straights in a row and two arrows. The tide enters west. The first arrow points
## the way the water is already going and passes it; the second points back the way it
## came, so water arrives at the side the arrow exits through and is refused. The sprites
## are identical apart from facing, which is the point: the only thing a player has to
## read is which way the chevron points.
ONEWAY_LAYOUT = [["EW", "EW>E", "EW", "EW>W", "EW"]]
ONEWAY_SOURCE = (0, 0)
## The three put in front of the Director, and the one she chose. The losers stay in the
## list so the options sheet keeps rendering: the next person to ask "why a gate?" gets to
## see the same comparison rather than take my word for it.
REFUSED_STYLES = ["gate", "grey", "backwash"]
REFUSED_CHOICE = "gate"


def render_cell(cell: str, wet: bool, pal: dict, refused: str = "") -> Canvas:
    """A tile with its arrow already composited, the way board.gd will draw it."""
    name, out = parse_cell(cell)
    img = tiles.render(tiles.mask_from_name(name), wet, pal)
    if out is not None:
        img.over(tiles.render_arrow(out, wet, pal, refused=refused))
    return img


def build_oneway_scene(pal: dict, refused_style: str) -> Canvas:
    wet = flood(ONEWAY_LAYOUT, ONEWAY_SOURCE)
    refused = refusals(ONEWAY_LAYOUT, wet)
    row = ONEWAY_LAYOUT[0]
    scene = Canvas(tiles.SIZE * len(row), tiles.SIZE)
    for c, cell in enumerate(row):
        style = refused_style if (0, c) in refused else ""
        scene.blit(render_cell(cell, (0, c) in wet, pal, refused=style), c * tiles.SIZE, 0)
    return scene


def build_refused_options(pal: dict) -> Canvas:
    """The same strip once per candidate treatment, stacked. A choice made by looking."""
    sheets = [build_oneway_scene(pal, style) for style in REFUSED_STYLES]
    out = Canvas(sheets[0].width, sheets[0].height * len(sheets), pal["outline"])
    for i, s in enumerate(sheets):
        out.blit(s, 0, i * sheets[0].height)
    return out


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
                path = os.path.join(TILE_OUT, "%s_%s_%s.png" % (prefix, name.lower(), "wet" if wet else "dry"))
                tiles.render(mask, wet, pal, locked=lock).save(path)
                written.append(path)

    print("\nchecking locked is a texture on the rock and nothing else:")
    for name in TILE_MASKS:
        assert_locked_is_texture(tiles.mask_from_name(name), pal)

    print("\nthe sponge - full means an objective is complete:")
    for name in SPONGE_MASKS:
        mask = tiles.mask_from_name(name)
        assert_sponge_swells(mask, pal)
        for full in (False, True):
            path = os.path.join(TILE_OUT, "sponge_%s_%s.png" % (name.lower(), "wet" if full else "dry"))
            tiles.render_sponge(mask, full, pal).save(path)
            written.append(path)

    sponges = build_sponge_sheet(pal)
    scaled(sponges, 4).save(os.path.join(PREVIEW_OUT, "sponge_4x.png"))
    scaled(greyscale(sponges), 4).save(os.path.join(PREVIEW_OUT, "sponge_4x_greyscale.png"))

    strip = build_strip(pal)
    strip.save(os.path.join(PREVIEW_OUT, "strip_1x.png"))
    scaled(strip, 4).save(os.path.join(PREVIEW_OUT, "strip_4x.png"))
    scaled(greyscale(strip), 4).save(os.path.join(PREVIEW_OUT, "strip_4x_greyscale.png"))

    sheet = build_family_sheet(pal)
    scaled(sheet, 3).save(os.path.join(PREVIEW_OUT, "tiles_3x.png"))
    scaled(greyscale(sheet), 3).save(os.path.join(PREVIEW_OUT, "tiles_3x_greyscale.png"))

    print("\nthe one-way arrow:")
    wet_cells = flood(ONEWAY_LAYOUT, ONEWAY_SOURCE)
    refused_cells = refusals(ONEWAY_LAYOUT, wet_cells)
    print("  ok   strip: %d of %d tiles reached, %d arrow refusing"
          % (len(wet_cells), len(ONEWAY_LAYOUT[0]), len(refused_cells)))
    if len(refused_cells) != 1:
        raise SystemExit("FAIL: the teaching strip must show exactly one arrow refusing")
    for out_dir in "NESW":
        for wet in (False, True):
            path = os.path.join(TILE_OUT, "oneway_%s_%s.png" % (out_dir.lower(), "wet" if wet else "dry"))
            tiles.render_arrow(out_dir, wet, pal).save(path)
            written.append(path)
            # The refused sprite the engine looks for before falling back to the plain
            # arrow. Maren picked `gate`: a refusing arrow is working perfectly - it is the
            # water that is wrong - and greying out says "disabled", which is the one thing
            # this sprite must never say.
            path = os.path.join(TILE_OUT, "oneway_%s_%s_refused.png" % (out_dir.lower(), "wet" if wet else "dry"))
            tiles.render_arrow(out_dir, wet, pal, refused=REFUSED_CHOICE).save(path)
            written.append(path)

    options = build_refused_options(pal)
    scaled(options, 4).save(os.path.join(PREVIEW_OUT, "oneway_options_4x.png"))
    scaled(greyscale(options), 4).save(os.path.join(PREVIEW_OUT, "oneway_options_4x_greyscale.png"))

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
