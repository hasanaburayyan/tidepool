"""Tile sprites, generated from a connection mask rather than drawn by hand.

Every rock tile in Tidepool is the same slab with a differently-shaped channel cut into
it, so there is exactly one drawing routine here and the tile's openings are its input.
Corner, tee and cross fall out of the same code as the straight - they ship in their own
PRs, but they are not new art code.

Two rules from the art direction are enforced structurally, not by eye:

1. *Nothing is communicated by hue alone.* The channel is a **shape** cut through the
   slab and outlined in Deep Umber. Desaturate the tile and the route is still legible,
   because the route is geometry. `build.py` emits a greyscale contact sheet as proof.

2. *Dry and wet differ only in channel-floor pixels.* `render()` draws the slab, the
   outline and the speckles once, then paints the floor last according to `wet`. The two
   states are the same function with the same inputs up to that final step, so the
   silhouette cannot drift and the shader's tween cannot wobble.
"""

from png import Canvas, TRANSPARENT

SIZE = 32
## Channel floor occupies rows/cols FLOOR_LO..FLOOR_HI; the 1px Deep Umber bank sits just
## outside it. 10px of water in a 32px tile reads chunky at 3x without going tube-like.
FLOOR_LO = 11
FLOOR_HI = 20

## Bit order matches `Tile.gd`: N, E, S, W. A tile's filename spells its openings in that
## order ("EW", "NE", "NES", "NESW") so a sprite and an engine mask can be checked against
## each other by reading them.
DIR_BITS = {"N": 1, "E": 2, "S": 4, "W": 8}


def mask_from_name(name: str) -> int:
    return sum(DIR_BITS[c] for c in name)


def name_from_mask(mask: int) -> str:
    return "".join(c for c in "NESW" if mask & DIR_BITS[c])


def channel_cells(mask: int) -> set:
    """Pixels belonging to the channel: the centre block plus one arm per opening.

    Each arm runs from the centre block to the tile edge, so a channel that opens on a
    side reaches pixel 0 or 31 there and meets its neighbour with no seam and no cap. A
    side with no opening is never touched, so the outline closes around the channel by
    itself and a dead end gets its cap for free.
    """
    cells = set()
    for y in range(FLOOR_LO, FLOOR_HI + 1):
        for x in range(FLOOR_LO, FLOOR_HI + 1):
            cells.add((x, y))
    if mask & DIR_BITS["N"]:
        cells |= {(x, y) for x in range(FLOOR_LO, FLOOR_HI + 1) for y in range(0, FLOOR_LO)}
    if mask & DIR_BITS["S"]:
        cells |= {(x, y) for x in range(FLOOR_LO, FLOOR_HI + 1) for y in range(FLOOR_HI + 1, SIZE)}
    if mask & DIR_BITS["W"]:
        cells |= {(x, y) for y in range(FLOOR_LO, FLOOR_HI + 1) for x in range(0, FLOOR_LO)}
    if mask & DIR_BITS["E"]:
        cells |= {(x, y) for y in range(FLOOR_LO, FLOOR_HI + 1) for x in range(FLOOR_HI + 1, SIZE)}
    return cells


def _bank_cells(channel: set) -> set:
    """Rock pixels touching the channel: the 1px Deep Umber outline.

    8-adjacency, so the outline stays unbroken around the inside corner of an elbow
    instead of leaking a diagonal pinhole of sand into the water.
    """
    bank = set()
    for (x, y) in channel:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                p = (x + dx, y + dy)
                if p not in channel and 0 <= p[0] < SIZE and 0 <= p[1] < SIZE:
                    bank.add(p)
    return bank


def _is_speckle(x: int, y: int) -> bool:
    """Deterministic grain on the rock body.

    Keyed on absolute pixel position rather than a per-tile random seed, so the speckles
    of two tiles laid side by side line up into one field and the slab reads continuous.
    Sparse on purpose: grain should say "this is stone", not "this is static".
    """
    h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return (h % 37) == 0


def _depth_map(channel: set, bank: set) -> dict:
    """How far each channel pixel sits from the nearest bank, by breadth-first fill.

    Gives the water an inside and an outside without hard-coding any tile's geometry, so
    the gloss and the ripple land correctly on a straight, an elbow or a cross alike.
    """
    depth = {}
    frontier = [p for p in channel if any(
        (p[0] + dx, p[1] + dy) in bank for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)))]
    for p in frontier:
        depth[p] = 1
    while frontier:
        nxt = []
        for (x, y) in frontier:
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                p = (x + dx, y + dy)
                if p in channel and p not in depth:
                    depth[p] = depth[(x, y)] + 1
                    nxt.append(p)
        frontier = nxt
    return depth


def render(mask: int, wet: bool, pal: dict, locked: bool = False) -> Canvas:
    """One 32x32 tile. `pal` maps role name -> (r, g, b)."""
    channel = channel_cells(mask)
    bank = _bank_cells(channel)

    img = Canvas(SIZE, SIZE, pal["rock_body"])

    # Rock body and its grain. Speckles keep clear of the bank so the outline stays a
    # clean 1px line at every zoom.
    for y in range(SIZE):
        for x in range(SIZE):
            if (x, y) in channel or (x, y) in bank:
                continue
            if _is_speckle(x, y):
                img[x, y] = pal["rock_speckle"]

    # Barnacles go down before the bank, never over it: every shell sits at least two
    # pixels out from the channel, so the Deep Umber outline stays exactly 1px wide.
    if locked:
        for (x, y) in _barnacles(channel, bank):
            img[x, y] = pal["outline"]

    for (x, y) in bank:
        img[x, y] = pal["outline"]

    # Channel floor, painted last and the ONLY thing `wet` changes.
    floor = pal["channel_wet"] if wet else pal["channel_dry"]
    for (x, y) in channel:
        img[x, y] = floor
    if wet:
        # Wet water is *textured*; dry channel is flat. That is deliberate and it is the
        # whole reason the wet state survives a greyscale screenshot: Tidewater and Wet
        # Sand are only 19/255 apart in luma, so colour alone cannot tell a player whether
        # a channel is carrying water. Shimmer is 45/255 clear of the dry floor, so the
        # gloss line and the ripple dashes - shapes, not hues - are what actually read.
        depth = _depth_map(channel, bank)
        for (x, y) in channel:
            # Gloss sits where the water meets the bank above it or to its left: one light
            # source, upper-left, the same on every tile in the game.
            if (x, y - 1) in bank or (x - 1, y) in bank:
                img[x, y] = pal["channel_gloss"]
            # Ripples: a broken line of glints three pixels in from the bank. Dashed, so
            # it reads as moving water rather than a second outline.
            elif depth.get((x, y)) == 3 and (x + y) % 5 == 0:
                img[x, y] = pal["channel_gloss"]
    return img


## How far out from the bank a barnacle shell may sit. 1 is banned: a shell touching the
## bank would thicken the 1px Deep Umber outline into a smear and the channel would stop
## reading as a clean cut. 5 is as far as the rock goes on a cross tile before it runs out.
BARNACLE_MIN_DEPTH = 2
BARNACLE_MAX_DEPTH = 5


def _rock_depth(channel: set, bank: set) -> dict:
    """How far each rock pixel sits from the channel, by breadth-first fill outward.

    The mirror of `_depth_map`: that one measures into the water, this one measures into
    the stone. Both exist so texture can be placed by distance from the channel rather
    than by hard-coded coordinates, which is what lets one routine crust a straight, an
    elbow and a cross without knowing which it is looking at.
    """
    depth = {p: 1 for p in bank}
    frontier = list(bank)
    while frontier:
        nxt = []
        for (x, y) in frontier:
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                p = (x + dx, y + dy)
                if (0 <= p[0] < SIZE and 0 <= p[1] < SIZE
                        and p not in channel and p not in depth):
                    depth[p] = depth[(x, y)] + 1
                    nxt.append(p)
        frontier = nxt
    return depth


def _barnacles(channel: set, bank: set) -> set:
    """The locked tile's crust: a rim of little shells clinging to the rock by the water.

    Locked is a *texture*, never a tint. The whole variant is these pixels - same
    silhouette, same palette, same channel - so it survives a greyscale screenshot, which
    a darker rock would not: the player is being told "this tile will not turn", and that
    has to be readable without colour.

    A shell is a ring: four Deep Umber pixels around a centre left as bare rock, so the
    hole in the middle reads as the opening of a limpet rather than as a blob. Rings are
    placed by distance from the channel, not by coordinates, so they crowd the waterline
    on any shape - which is also where real barnacles live, below the dry line.

    Placement is a hash of absolute pixel position, the same field the rock grain uses, so
    two locked tiles side by side crust continuously instead of repeating a stamp.
    """
    depth = _rock_depth(channel, bank)
    shells = set()
    for (x, y), d in depth.items():
        if not (BARNACLE_MIN_DEPTH <= d <= BARNACLE_MAX_DEPTH):
            continue
        h = (x * 2654435761 + y * 40503) & 0xFFFFFFFF
        h = (h ^ (h >> 15)) * 2246822519 & 0xFFFFFFFF
        # Denser at the waterline, thinning out as the rock dries: 1 in 5 at depth 2, 1 in
        # 11 at depth 5. The gradient is what makes it read as growth rather than noise.
        if h % (2 * d + 1) != 0:
            continue
        ring = {(x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)}
        # A shell that would spill onto the bank is dropped whole rather than clipped: half
        # a ring is a smudge, and a smudge on the outline is exactly what rule 1 forbids.
        if any(p in channel or depth.get(p, 0) < BARNACLE_MIN_DEPTH for p in ring):
            continue
        shells |= ring
    return shells


## ---------------------------------------------------------------------------
## One-way arrows
##
## A one-way is not a shape of channel - the engine lets any mask be one, it just needs an
## opening on `out_dir` (`level_io.gd` refuses the level otherwise). So the arrow is an
## overlay composited onto whatever tile is underneath, not eleven more baked sprites, and
## it is named for its exit because that is what the level format stores.
##
## This is the load-bearing sprite in the game. Levels 14, 16, 17 and 18 all teach by
## letting a player watch an arrow refuse water. If "refusing" and "broken" look the same,
## four levels stop teaching what they are for.
## ---------------------------------------------------------------------------

## Quarter-turns counter-clockwise from the canonical chevron, which points EAST. This is
## deliberately not the engine's N,E,S,W side order: that order numbers sides, this one
## counts rotations from the one orientation actually drawn.
ROT_FROM_EAST = {"E": 0, "N": 1, "W": 2, "S": 3}

## The chevron, drawn once pointing east and rotated into the other three facings by
## turning its *coordinates*, not its pixels. Rotating a coordinate is exact; rotating a
## rendered image re-samples it and rounds a crisp diagonal into mush.
def _rot_ccw(p: tuple) -> tuple:
    return (p[1], SIZE - 1 - p[0])


def _chevron_east() -> tuple:
    """Two arms meeting at a point on the east side, spanning the full channel width.

    It fills the channel top to bottom on purpose. A small arrow floating in the middle of
    the water would read as decoration; one that spans the opening reads as a thing water
    has to get past. Returns (body, highlight) - the highlight trails behind the arms so
    the arrow looks like it is cutting forward rather than sitting still.
    """
    body, highlight = set(), set()
    reach = (FLOOR_HI - FLOOR_LO) // 2  # 4: half the channel, so the arms just reach both banks
    for k in range(reach + 1):
        for (x, y) in ((FLOOR_HI - 1 - k, FLOOR_LO + reach - k), (FLOOR_HI - 1 - k, FLOOR_LO + reach + 1 + k)):
            body.add((x, y))
            body.add((x - 1, y))   # 2px thick, or the arms vanish at 1x
            highlight.add((x - 2, y))
    return body, highlight - body


def arrow_cells(out_dir: str) -> tuple:
    """(body, highlight) for an arrow exiting through `out_dir`."""
    body, highlight = _chevron_east()
    for _ in range(ROT_FROM_EAST[out_dir]):
        body = {_rot_ccw(p) for p in body}
        highlight = {_rot_ccw(p) for p in highlight}
    return body, highlight


def _gate_cells(out_dir: str) -> set:
    """A bar across the channel on the entry side of the arrow: the sluice is shut.

    Sits behind the chevron, where water arriving the wrong way would pile up against it.
    """
    bar = set()
    for k in (0, 1):
        for i in range(FLOOR_LO, FLOOR_HI + 1):
            bar.add((FLOOR_LO + k, i))
    for _ in range(ROT_FROM_EAST[out_dir]):
        bar = {_rot_ccw(p) for p in bar}
    return bar


def _backwash_cells(out_dir: str) -> set:
    """Short ticks on the entry side, angled back the way the water came.

    Water reaching the arrow from the wrong side and turning around. Motion rather than
    absence: the tile is doing something, not failing to do something.
    """
    ticks = set()
    for row in (FLOOR_LO + 1, FLOOR_LO + 4, FLOOR_LO + 7):
        for k in range(3):
            ticks.add((FLOOR_LO + 1 + k, row + (k if row < FLOOR_LO + 5 else -k)))
    for _ in range(ROT_FROM_EAST[out_dir]):
        ticks = {_rot_ccw(p) for p in ticks}
    return ticks


def render_arrow(out_dir: str, wet: bool, pal: dict, refused: str = "") -> Canvas:
    """A 32x32 transparent overlay: the arrow alone, to composite onto any tile.

    `refused` picks the treatment for an arrow that is being asked to pass water backwards:
    "" (flowing), "gate", "grey" or "backwash". The Director chooses one; the others are
    generated so the choice is made by looking rather than by reading a description.
    """
    img = Canvas(SIZE, SIZE, TRANSPARENT)
    body, highlight = arrow_cells(out_dir)

    if refused == "gate":
        for (x, y) in _gate_cells(out_dir):
            img[x, y] = pal["outline"]
    if refused == "backwash":
        for (x, y) in _backwash_cells(out_dir):
            img[x, y] = pal["outline"]

    # The highlight rides the floor it sits on - Shimmer over water, Dry Sand over a dry
    # channel - so the arrow is legible on either state without the body ever moving. That
    # is the only thing `wet` changes here, which is rule 2 holding for the overlay too.
    edge = pal["channel_gloss"] if wet else pal["rock_body"]
    for (x, y) in highlight:
        img[x, y] = edge
    # "grey" is the one treatment that weakens the arrow instead of adding to it: the body
    # drops from Deep Umber to Wet Sand. Included because the levels describe it, and shown
    # in greyscale next to the others precisely so we can see what that costs.
    for (x, y) in body:
        img[x, y] = pal["rock_speckle"] if refused == "grey" else pal["outline"]
    return img

## ---------------------------------------------------------------------------
## Sponges
##
## The opposite case to the one-way arrow, and the difference is worth naming. An arrow is
## a shape plus a direction - two things that vary independently, so it composites. A
## sponge is a different *material*: thirsty rock that water goes into and never out of.
## It is a whole tile, `sponge_<sides>_<state>`, and the format only allows it on a
## straight, so it is four files.
##
## "Full" means an objective is complete, which makes it the loudest state change in the
## game. So the change is the *silhouette*: a dry sponge is a shrunken, pitted lump and a
## full one is swollen fat enough to bulge past the channel it sits in. That deliberately
## breaks rule 2, which is a channel rule - a channel must not change shape because a
## shader tweens it, and a sponge must, because a player has to read it from across the
## board without looking for it.
## ---------------------------------------------------------------------------

SPONGE_R_DRY = 6.5    # 13px across against a 10px channel: it bulges even when empty
SPONGE_R_FULL = 11.0  # nearly twice the diameter again, swollen well past the banks

## Maren's call, and it is a trade rather than a free win. A dry sponge narrower than its
## channel had the bigger swell, but it sat inside the banks and read as a channel with
## texture in it - a player could route water into a thirsty tile without ever noticing it
## was one. Widening the dry lump until it bulges spends some of the swell contrast to buy
## presence at rest. The resting state has to say "thirsty" before any water arrives; the
## swell only has to say "done", and it still has 184 pixels to say it with.


def _centre_block() -> set:
    return {(x, y) for y in range(FLOOR_LO, FLOOR_HI + 1) for x in range(FLOOR_LO, FLOOR_HI + 1)}


def _wrinkle(x: int, y: int) -> float:
    """How far the dry sponge's edge is pulled in at this pixel. Deterministic.

    Only the dry state is wrinkled. Drying out is what puckers a sponge; a full one is
    taut, so its edge is smooth. The two silhouettes therefore differ in character as well
    as in size, which is the part that survives being glanced at.
    """
    h = (x * 2246822519 + y * 3266489917) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 668265263 & 0xFFFFFFFF
    return (h % 3) * 0.9


def sponge_body(mask: int, full: bool) -> set:
    """The sponge itself plus the channel arms that feed it.

    The arms keep the channel's exact width and position so a sponge meets its neighbours
    the way any other tile does - the water has to visibly arrive. Everything inside is a
    lump instead of a cut, which is what makes it read as a different material rather than
    as a channel with something in it.
    """
    arms = channel_cells(mask) - _centre_block()
    r = SPONGE_R_FULL if full else SPONGE_R_DRY
    c = (SIZE - 1) / 2.0
    blob = set()
    for y in range(SIZE):
        for x in range(SIZE):
            limit = r if full else r - _wrinkle(x, y)
            if ((x - c) ** 2 + (y - c) ** 2) ** 0.5 <= limit:
                blob.add((x, y))
    return arms | blob


def _pores(body: set, bank: set, full: bool) -> set:
    """Holes in the sponge. Wide open when dry, squeezed near shut when full.

    A second reading of the same state at a second scale: the silhouette carries it from
    across the board, the pores carry it when a player is looking right at the tile.
    """
    depth = _depth_map(body, bank)
    out = set()
    for (x, y) in body:
        if depth.get((x, y), 0) < 3:
            continue
        h = (x * 374761393 + y * 1274126177) & 0xFFFFFFFF
        h = (h ^ (h >> 11)) * 2654435761 & 0xFFFFFFFF
        if h % 7:
            continue
        if full:
            out.add((x, y))  # pinched shut
        else:
            out |= {(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)}
    return {p for p in out if p in body and depth.get(p, 0) >= 2}


def render_sponge(mask: int, full: bool, pal: dict, locked: bool = False) -> Canvas:
    """One 32x32 sponge tile. `full` is the objective-complete state."""
    body = sponge_body(mask, full)
    bank = _bank_cells(body)

    img = Canvas(SIZE, SIZE, pal["rock_body"])
    for y in range(SIZE):
        for x in range(SIZE):
            if (x, y) not in body and (x, y) not in bank and _is_speckle(x, y):
                img[x, y] = pal["rock_speckle"]

    if locked:
        # Level 19's barnacled sponge used to draw as a plain locked pipe. Crust, not a pipe.
        for p in _barnacles(body, bank):
            img[p] = pal["outline"]
    for (x, y) in bank:
        img[x, y] = pal["outline"]
    for (x, y) in body:
        img[x, y] = pal["channel_wet"] if full else pal["channel_dry"]
    for (x, y) in _pores(body, bank, full):
        img[x, y] = pal["outline"]
    return img


## ---------------------------------------------------------------------------
## Basins (levels 25-28): a four-way pool that never rotates. It fills from any side but
## only passes water on once it is fed from two or more.
##
## The trap is the one the channel floor fell into: Tidewater and Wet Sand are 19 luma apart,
## so "where the water is" cannot carry the state on its own. The answer is a LIP - a Deep
## Umber ring inside the bowl, the darkest thing we own:
##   dry  - bowl, lip, four short mouths, no water. Round, so never mistaken for a cross.
##   wait - water held BELOW the lip; the ring stays visible and every mouth stays dry. It
##          reads as a bowl holding water and passing none on - calm, not broken.
##   over - water rises over the lip, so the ring goes under, and pours out of all four
##          mouths to the tile edges.
## "Ring present" against "ring gone" is a change of shape at luma 48, so it survives
## greyscale; the water's texture is the confirmation, never the signal.
## ---------------------------------------------------------------------------

import math as _math

BASIN_R = 12.5      # bowl radius
BASIN_LIP = 8.5     # the lip ring


def _dist(x, y):
    c = (SIZE - 1) / 2.0
    return _math.hypot(x - c, y - c)


def basin_body() -> set:
    bowl = {(x, y) for y in range(SIZE) for x in range(SIZE) if _dist(x, y) <= BASIN_R}
    return bowl | channel_cells(0b1111)


def basin_lip() -> set:
    return {(x, y) for y in range(SIZE) for x in range(SIZE) if BASIN_LIP <= _dist(x, y) < BASIN_LIP + 1}


def basin_water(state: str) -> set:
    if state == "over":
        return basin_body()
    if state == "wait":
        return {(x, y) for y in range(SIZE) for x in range(SIZE) if _dist(x, y) < BASIN_LIP}
    return set()


def render_basin(state: str, pal: dict, locked: bool = False) -> Canvas:
    body = basin_body()
    bank = _bank_cells(body)
    water = basin_water(state)
    img = Canvas(SIZE, SIZE, pal["rock_body"])
    for y in range(SIZE):
        for x in range(SIZE):
            if (x, y) not in body and (x, y) not in bank and _is_speckle(x, y):
                img[x, y] = pal["rock_speckle"]
    if locked:
        # The same crust as a locked channel, placed by distance from the bowl.
        for p in _barnacles(body, bank):
            img[p] = pal["outline"]
    for p in bank:
        img[p] = pal["outline"]
    for p in body:
        img[p] = pal["channel_dry"]
    for (x, y) in water:
        img[x, y] = pal["channel_wet"]
        # Same water as every channel: gloss where it meets its edge upper-left, dashed ripples.
        if (x, y - 1) not in water or (x - 1, y) not in water:
            img[x, y] = pal["channel_gloss"]
        elif (x + y) % 5 == 0 and (x - 2, y) in water and (x, y - 2) in water:
            img[x, y] = pal["channel_gloss"]
    if state != "over":
        for p in basin_lip():
            img[p] = pal["outline"]
    return img
