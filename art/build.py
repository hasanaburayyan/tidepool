#!/usr/bin/env python3
"""Regenerate every sprite in the game. No arguments, no network, no dependencies.

    python3 art/build.py

Output is deterministic: running it twice with an unchanged palette produces
byte-identical PNGs, so `git status` after a build is the test that nothing drifted.
"""

import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import beachmap
import critters
import icon
import tiles
from png import Canvas, hex_to_rgb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE_OUT = os.path.join(ROOT, "assets", "tiles")
CRITTER_OUT = os.path.join(ROOT, "assets", "critters")
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
## Caps: one opening. `tide_format.gd` spells them `E` (0b0001) and every level uses them -
## the tide source and every critter's pool are caps. Until these existed the engine found
## no `channel_n` and fell back to drawing those tiles procedurally, so the two most
## important cells on every board were the only ones not in the art style. No new drawing
## code: `channel_cells` has always capped a dead end for free.
CAP_MASKS = ["N", "E", "S", "W"]
TILE_MASKS = STRAIGHT_MASKS + CORNER_MASKS + TEE_MASKS + CROSS_MASKS + CAP_MASKS


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


## `board.gd:_draw_critter` keys these "<type>_<state>", and rescue latches, so `rescued`
## is a final state rather than a phase. Four files.
CRITTER_TYPES = ["starfish", "anemone"]


def luma(rgb) -> float:
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def assert_critter_reads(kind: str, pal: dict) -> None:
    """A critter is the objective, so it has to survive every background in the game.

    Two claims. The outline must fully enclose the sprite - no body pixel may sit directly
    against the board - because the Umber outline is what isolates the critter from
    whatever is behind it. And against BOTH backgrounds a critter can be on, dry rock and
    open water, that outline must be a hard luma step, so the silhouette holds with the
    colour stripped out.

    This exists because the level 8 greyscale showed the placeholder critters desaturating
    into the sand - the least visible objects on a board where they are the goal. Coral is
    luma 130 and Tidewater is 138. Colour alone was never going to hold them.
    """
    backgrounds = {"dry rock": pal["rock_body"], "open water": pal["channel_wet"]}
    for state in ("stranded", "rescued"):
        img = critters.render(critters.SHAPES[kind](state == "rescued"), pal)
        body = {(x, y) for y in range(critters.SIZE) for x in range(critters.SIZE)
                if img[x, y][3] and img[x, y][:3] != pal["outline"]}
        outline = {(x, y) for y in range(critters.SIZE) for x in range(critters.SIZE)
                   if img[x, y][:3] == pal["outline"] and img[x, y][3]}

        for (x, y) in body:
            for q in ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)):
                inside = 0 <= q[0] < critters.SIZE and 0 <= q[1] < critters.SIZE
                if inside and q not in body and q not in outline:
                    raise SystemExit("FAIL %s_%s: body pixel %s touches the board directly"
                                     % (kind, state, (x, y)))
        step = min(abs(luma(pal["outline"]) - luma(bg)) for bg in backgrounds.values())
        if step < 60:
            raise SystemExit("FAIL %s_%s: outline is only %.0f luma from a background it sits on"
                             % (kind, state, step))
        print("  ok   %-8s %-8s %3d outline px enclose it, %.0f luma clear of every background"
              % (kind, state, len(outline), step))


def assert_rescue_opens(kind: str, pal: dict) -> None:
    """Rescue latches, so it is an ending. It has to look like one from across the board."""
    stranded = critters._body(critters.SHAPES[kind](False))
    opened = critters._body(critters.SHAPES[kind](True))
    if len(opened) <= len(stranded) * 1.4:
        raise SystemExit("FAIL %s: rescued is only %d px against stranded %d - too quiet for an ending"
                         % (kind, len(opened), len(stranded)))
    print("  ok   %-8s opens %d -> %d pixels on rescue (x%.1f)"
          % (kind, len(stranded), len(opened), len(opened) / len(stranded)))


def assert_frames_hold(kind: str, pal: dict) -> None:
    """Every frame has to pass what the still passes - an animation is only as legible as
    its worst frame. Plus two things only frames can get wrong: frame 0 must BE the still
    (the loader falls back to it), and no frame may clip at the canvas edge, where the
    outline would be cut off without any neighbour check noticing."""
    for state, twists in critters.FRAMES.items():
        still = critters.render(critters.SHAPES[kind](state == "rescued"), pal)
        imgs = [critters.render(critters.frame(kind, state, n), pal) for n in range(len(twists))]
        if diff_pixels(still, imgs[0]):
            raise SystemExit("FAIL %s_%s_0 differs from the un-numbered sprite" % (kind, state))
        if all(not diff_pixels(imgs[0], im) for im in imgs[1:]):
            raise SystemExit("FAIL %s_%s: every frame is identical - the animation is a no-op" % (kind, state))
        for n, im in enumerate(imgs):
            edge = [(x, y) for y in range(critters.SIZE) for x in range(critters.SIZE)
                    if im[x, y][3] and (x in (0, critters.SIZE - 1) or y in (0, critters.SIZE - 1))]
            if edge:
                raise SystemExit("FAIL %s_%s_%d clips at the canvas edge at %s" % (kind, state, n, edge[:3]))
    lo = min(len(critters._body(critters.frame(kind, "rescued", n))) for n in range(4))
    hi = max(len(critters._body(critters.frame(kind, "stranded", n))) for n in range(2))
    if lo < hi * 1.4:
        raise SystemExit("FAIL %s: smallest rescued frame %d < 1.4x largest stranded frame %d" % (kind, lo, hi))
    print("  ok   %-8s 2 idle + 4 rescue frames: frame 0 is the still, none clip, rescue still opens x%.1f"
          % (kind, lo / hi))


def build_frames_sheet(pal: dict) -> Canvas:
    """Every frame in a row, stranded then rescued, per critter - read left to right."""
    cells = [critters.render(critters.frame(k, st, n), pal)
             for k in CRITTER_TYPES for st in ("stranded", "rescued") for n in range(len(critters.FRAMES[st]))]
    sheet = Canvas(critters.SIZE * len(cells), critters.SIZE, pal["rock_body"])
    for i, c in enumerate(cells):
        sheet.over(c, i * critters.SIZE, 0)
    return sheet


def build_critter_sheet(pal: dict) -> Canvas:
    """Each critter stranded then rescued, over dry rock and over open water.

    Four columns per critter, because the question is not "does it look good" but "does it
    hold on both of the things the game will put behind it".
    """
    cells = []
    for kind in CRITTER_TYPES:
        for bg in (pal["rock_body"], pal["channel_wet"]):
            for state in (False, True):
                tile = Canvas(critters.SIZE, critters.SIZE, bg)
                tile.over(critters.render(critters.SHAPES[kind](state), pal))
                cells.append(tile)
    sheet = Canvas(critters.SIZE * len(cells), critters.SIZE, pal["outline"])
    for i, c in enumerate(cells):
        sheet.blit(c, i * critters.SIZE, 0)
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


## Previews are drawn from REAL levels, using the engine's own flow results.
##
## These used to be synthetic layouts coloured by `flood`, a Python copy of the engine's
## connection rule. A second copy of a rule is not a backup: when the two disagree, the one
## nobody runs is the one that is wrong. `tools/dump_rules.gd` emits every level's tiles, wet
## sets and refusals, so these previews draw only what the engine decided.
##
## The build stays python3-only. `art/rules.json` is a committed snapshot of the dump,
## stamped with the hash of every level file it came from. If a level changes after the
## snapshot, the build FAILS and says how to refresh, instead of drawing a preview the
## engine would disagree with.
RULES = os.path.join(ROOT, "art", "rules.json")
REFRESH = ("godot --headless --path . --import && "
           "godot --headless --path . --script res://tools/dump_rules.gd && "
           "python3 art/build.py --snapshot-rules")
JUNCTION_LEVEL = 9     # "Crossroads": a cross inside a real route
REFUSAL_LEVEL = 14     # "Wrong Way": the level built on an arrow refusing

## The three put in front of the Director, and the one she chose. The losers stay so the
## options sheet keeps rendering: whoever asks "why a gate?" sees the comparison.
REFUSED_STYLES = ["gate", "grey", "backwash"]
REFUSED_CHOICE = "gate"


def _level_hashes() -> dict:
    out = {}
    for name in sorted(os.listdir(os.path.join(ROOT, "levels"))):
        if name.endswith(".tide"):
            with open(os.path.join(ROOT, "levels", name), "rb") as fh:
                out[name] = hashlib.sha256(fh.read()).hexdigest()
    return out


def snapshot_rules() -> None:
    """Copy build/rules.json into art/, stamped with the level files it describes."""
    with open(os.path.join(ROOT, "build", "rules.json")) as fh:
        data = json.load(fh)
    data["source_hashes"] = _level_hashes()
    with open(RULES, "w") as fh:
        json.dump(data, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print("snapshot -> art/rules.json (%d levels)" % len(data["levels"]))


def load_rules() -> dict:
    if not os.path.exists(RULES):
        raise SystemExit("FAIL: art/rules.json is missing. Refresh it:\n  " + REFRESH)
    with open(RULES) as fh:
        data = json.load(fh)
    if data.get("source_hashes") != _level_hashes():
        raise SystemExit("FAIL: a level changed since art/rules.json was dumped, so the previews "
                         "would show what the engine no longer does. Refresh it:\n  " + REFRESH)
    return data


def level_by_id(rules: dict, level_id: int) -> dict:
    return next(L for L in rules["levels"] if L["id"] == level_id)


def _out_name(out) -> str:
    return "NESW"[out] if isinstance(out, int) else str(out).upper()


def render_level(level: dict, when: str, pal: dict, refused_style: str = REFUSED_CHOICE) -> Canvas:
    """A whole real level from the engine's tiles, wet set and refusals. Nothing is decided here."""
    w, h = level["width"], level["height"]
    wet = set(level["wet_" + when])
    refusing = set(level["refusing_" + when])
    img = Canvas(tiles.SIZE * w, tiles.SIZE * h, pal["rock_body"])
    for i, c in enumerate(level["tiles_" + when]):
        if c["kind"] == "empty":
            continue
        mask = tiles.mask_from_name(c["sides"].upper())
        if c["kind"] == "sponge":
            tile = tiles.render_sponge(mask, i in wet, pal)
        else:
            tile = tiles.render(mask, i in wet, pal, locked=c["locked"])
        if c["kind"] == "oneway":
            style = refused_style if i in refusing else ""
            tile.over(tiles.render_arrow(_out_name(c["out"]), i in wet, pal, refused=style))
        img.blit(tile, (i % w) * tiles.SIZE, (i // w) * tiles.SIZE)
    return img


def build_refused_options(pal: dict, level: dict) -> Canvas:
    """Level 14 at its start, once per candidate treatment, stacked. A choice made by looking,
    now on the actual level whose lesson depends on it."""
    sheets = [render_level(level, "at_start", pal, style) for style in REFUSED_STYLES]
    out = Canvas(sheets[0].width, sheets[0].height * len(sheets) + 2 * (len(sheets) - 1), pal["outline"])
    for i, sh in enumerate(sheets):
        out.blit(sh, 0, i * (sheets[0].height + 2))
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

    print("\ncritters - the objective has to survive every background:")
    os.makedirs(CRITTER_OUT, exist_ok=True)
    for kind in CRITTER_TYPES:
        assert_critter_reads(kind, pal)
        assert_rescue_opens(kind, pal)
        for state in ("stranded", "rescued"):
            path = os.path.join(CRITTER_OUT, "%s_%s.png" % (kind, state))
            critters.render(critters.SHAPES[kind](state == "rescued"), pal).save(path)
            written.append(path)
            for n in range(len(critters.FRAMES[state])):
                path = os.path.join(CRITTER_OUT, "%s_%s_%d.png" % (kind, state, n))
                critters.render(critters.frame(kind, state, n), pal).save(path)
                written.append(path)
        assert_frames_hold(kind, pal)

    scaled(build_frames_sheet(pal), 4).save(os.path.join(PREVIEW_OUT, "critter_frames_4x.png"))
    crit = build_critter_sheet(pal)
    scaled(crit, 4).save(os.path.join(PREVIEW_OUT, "critters_4x.png"))
    scaled(greyscale(crit), 4).save(os.path.join(PREVIEW_OUT, "critters_4x_greyscale.png"))

    strip = build_strip(pal)
    strip.save(os.path.join(PREVIEW_OUT, "strip_1x.png"))
    scaled(strip, 4).save(os.path.join(PREVIEW_OUT, "strip_4x.png"))
    scaled(greyscale(strip), 4).save(os.path.join(PREVIEW_OUT, "strip_4x_greyscale.png"))

    sheet = build_family_sheet(pal)
    scaled(sheet, 3).save(os.path.join(PREVIEW_OUT, "tiles_3x.png"))
    scaled(greyscale(sheet), 3).save(os.path.join(PREVIEW_OUT, "tiles_3x_greyscale.png"))

    print("\nthe one-way arrow:")
    rules = load_rules()
    wrong_way = level_by_id(rules, REFUSAL_LEVEL)
    for when in ("at_start", "when_solved"):
        n = len(wrong_way["refusing_" + when])
        if n != 1:
            raise SystemExit("FAIL: level %d must show exactly one arrow refusing %s, the engine says %d"
                             % (REFUSAL_LEVEL, when.replace("_", " "), n))
    print("  ok   level %d %s: exactly one arrow refusing, at start and when solved (engine's flow)"
          % (REFUSAL_LEVEL, wrong_way["name"]))
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

    options = build_refused_options(pal, wrong_way)
    scaled(options, 4).save(os.path.join(PREVIEW_OUT, "oneway_options_4x.png"))
    scaled(greyscale(options), 4).save(os.path.join(PREVIEW_OUT, "oneway_options_4x_greyscale.png"))

    compare = build_locked_comparison(pal)
    scaled(compare, 3).save(os.path.join(PREVIEW_OUT, "locked_3x.png"))
    scaled(greyscale(compare), 3).save(os.path.join(PREVIEW_OUT, "locked_3x_greyscale.png"))

    scene = render_level(level_by_id(rules, JUNCTION_LEVEL), "when_solved", pal)
    scaled(scene, 4).save(os.path.join(PREVIEW_OUT, "junction_4x.png"))
    scaled(greyscale(scene), 4).save(os.path.join(PREVIEW_OUT, "junction_4x_greyscale.png"))

    # The app icon is built from the same sprites, so it can never drift off palette again.
    print("\nthe beach map (keys fixed by Marlow, spec tidepool-beach-map):")
    written += beachmap.write_assets(pal, ROOT)
    demo = {i: ("done", [3, 3, 2, 3, 1, 2, 3, 3, 2, 3, 2, 3, 3, 1][i - 1]) for i in range(1, 15)}
    demo[15] = ("open", 0)
    full = beachmap.compose_preview(pal, demo)
    full.save(os.path.join(PREVIEW_OUT, "beachmap_full.png"))
    greyscale(full).save(os.path.join(PREVIEW_OUT, "beachmap_full_greyscale.png"))

    icon_path = icon.write(pal, ROOT)
    scaled(icon.compose(pal), 4).save(os.path.join(PREVIEW_OUT, "icon_4x.png"))
    print("\nwrote %s from the game's own sprites" % os.path.relpath(icon_path, ROOT))
    print("\nwrote %d tile sprites to assets/tiles/ and 9 contact sheets to art/preview/" % len(written))
    for p in written:
        print("  " + os.path.relpath(p, ROOT))


if __name__ == "__main__":
    if "--snapshot-rules" in sys.argv:
        snapshot_rules()
    main()
