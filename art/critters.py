"""Critters, generated from a radius-per-angle function rather than drawn by hand.

A critter is the objective. Everything here exists to make it the thing a player's eye
finds first, and to make "rescued" feel like an ending rather than a state.

Three colours, in three rings, and the order matters:

  Deep Umber outline  - separates the critter from ANY background
  Dry Sand rim, 1px   - the brightest edge on the board, inside the outline
  Coral fill          - the body

That rim is the Director's call and the level 8 greyscale is why. Coral (luma 130) against
Tidewater (138) is eight points apart: a Coral critter sitting in water is invisible the
moment you desaturate it, which is the exact situation the game puts it in. The rim does
not care what is behind it, because the Umber outline isolates the sprite first and the
rim then sits at luma 222 against a fill at 130. Two hard steps, on every background.
"""

import math

from png import Canvas, TRANSPARENT

SIZE = 32
CENTRE = (SIZE - 1) / 2.0


def _body(radius_at) -> set:
    """Fill every pixel whose distance from centre is within radius_at(angle).

    A critter is a silhouette problem, so it is defined as a silhouette: one function from
    angle to reach. Arms, tentacles and the difference between limp and open all fall out
    of changing that function, which keeps "what shape is it" separate from "how is it
    drawn" - and the drawing half is shared by every critter in the game.
    """
    cells = set()
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x - CENTRE, y - CENTRE
            dist = math.hypot(dx, dy)
            if dist <= radius_at(math.atan2(dy, dx)):
                cells.add((x, y))
    return cells


def _ring(body: set) -> tuple:
    """(outline, rim, core). Outline is outside the body, rim is the body's own edge.

    8-adjacency both ways, so a diagonal arm tip still gets a closed outline and a rim
    behind it rather than a single bare Coral pixel hanging off the end.
    """
    def neighbours(p):
        return [(p[0] + dx, p[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx, dy) != (0, 0)]

    outline = {q for p in body for q in neighbours(p)
               if q not in body and 0 <= q[0] < SIZE and 0 <= q[1] < SIZE}
    rim = {p for p in body if any(q in outline for q in neighbours(p))}
    return outline, rim, body - rim


def render(radius_at, pal: dict) -> Canvas:
    """A 32x32 transparent critter sprite: outline, rim, fill."""
    body = _body(radius_at)
    outline, rim, core = _ring(body)
    img = Canvas(SIZE, SIZE, TRANSPARENT)
    for (x, y) in outline:
        img[x, y] = pal["outline"]
    for (x, y) in rim:
        img[x, y] = pal["rock_body"]      # Dry Sand: the brightest thing we own
    for (x, y) in core:
        img[x, y] = pal["critter"]
    return img


## --- the shapes -------------------------------------------------------------------
##
## Stranded and rescued are the same creature, not two drawings. Each is one radius
## function, and the difference between them is what a player is meant to read across the
## board: stranded is drawn IN, rescued is drawn OPEN.


def starfish(rescued: bool):
    """Five arms. Stranded they are short and pulled in; rescued they reach right out.

    The stranded star is also rolled off true and its arms are uneven - a starfish drying
    on sand is not a symmetrical object. Rescue straightens it. That asymmetry is doing
    quiet work: "something is wrong here" is legible before a player knows the rules.
    """
    if rescued:
        return lambda a: 5.8 + 8.6 * max(0.0, math.cos(5 * a - math.pi / 2)) ** 0.55
    return lambda a: 5.6 + 4.4 * max(0.0, math.cos(5 * a - math.pi / 2 + 0.35)) ** 0.8


def anemone(rescued: bool):
    """A column of tentacles. Stranded it is a shut knob; rescued it opens and feeds.

    Eight lobes rather than five, and a fatter base than the starfish, so the two critters
    are told apart by silhouette at a glance and not by counting points.
    """
    if rescued:
        return lambda a: 9.0 + 5.4 * math.cos(8 * a) ** 3
    return lambda a: 7.2 + 1.3 * math.cos(8 * a) ** 3


## How big the STRANDED shape is, and why it is not smaller. Stranded is the state a player
## looks at for almost the whole level - it is the objective, and the eye has to find it
## first. A first cut drew it at 12-15px of a 32px canvas so that rescue would open 2.5x,
## and in the level 8 screenshot that made the goal the smallest thing on the board. Same
## trade the Director made for the sponge: presence at rest beats contrast on change. The
## rescue still has to open by at least 1.4x, and `build.py` enforces that.

SHAPES = {"starfish": starfish, "anemone": anemone}


## --- animation frames --------------------------------------------------------------
##
## Keyed `<type>_<state>_<n>` (Marlow's loader cycles them when `_0` exists and falls
## back to the un-numbered sprite). Frames are not redrawn: each one is the same radius
## function turned by a small angle - rotating the FUNCTION, never the pixels, so every
## frame is as crisp as the still. Frame 0 is the identity, so `_0` is byte-identical to
## the un-numbered sprite and the fallback and the animation can never disagree.
##
## Stranded: a 2-frame twitch. Small and slow - a critter drying on sand is still alive.
## Rescued:  a 4-frame sway, centre / one way / centre / the other. Rescue latches, so this
##           plays for as long as the player looks at the pool, and it has to be something
##           you can watch forever: a creature settling back into water, not a victory dance.

FRAMES = {"stranded": [0.0, 0.07], "rescued": [0.0, 0.09, 0.0, -0.09]}


def frame(kind: str, state: str, n: int):
    base = SHAPES[kind](state == "rescued")
    twist = FRAMES[state][n]
    return lambda a: base(a - twist)
