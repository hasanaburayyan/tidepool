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

from png import Canvas

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

    if locked:
        for (x, y) in _barnacles(channel, bank):
            img[x, y] = pal["rock_speckle"]

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


def _barnacles(channel: set, bank: set) -> set:
    """Placeholder hook for the locked variant; its own PR fills this in."""
    return set()
