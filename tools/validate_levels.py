#!/usr/bin/env python3
"""Tidepool level validator - SUPERSEDED as a checker, kept as a parser.

Reference implementation of the level text format specified in `tidepool-design` §4.
Written by Maren (Game Director) so that level data stops being "hand-verified" and
starts being machine-verified.

IT IS NO LONGER THE CI GATE. `tools/verify_levels.gd` replaced it and runs against the
engine's own loader and solver, which is the only copy that cannot disagree with the game.
Nothing runs this file automatically, so treat any rule stated here as documentation and
not as something enforced.

It is NOT dead, which is why it is still here: `tools/probe_mechanic.py` (kept
deliberately - it is what cut crabs) and the two spikes under `tools/spikes/` import it as
their .tide parser and rotation model. Deleting it breaks the mechanic probe, which is the
tool you reach for BEFORE authoring levels for a new mechanic.

What it checks, per level:
  1. PARSE      - the file is well-formed and every glyph is legal.
  2. SOLVE      - replaying `solution:` rescues every critter.        HARD FAIL if not.
  3. PAR        - par == total rotations in `solution:`.              HARD FAIL if not.
  4. TIDE       - gone. The budget rule lives on `Grid.expected_tide()` and is enforced by
                  `tools/verify_levels.gd`. A second copy here is how it went stale.
  5. OPTIMALITY - bounded IDDFS to depth par-1, capped by nodes AND a wall clock.
                  shorter solution found -> HARD FAIL (the declared par is wrong).
                  budget spent first     -> WARN, reported as "par unverified".
                  search exhausted       -> par proven optimal.

An unsolvable shipped level is structurally impossible if this runs in CI.
An unverified par is acceptable to ship. That asymmetry is deliberate.

Usage:  python3 tools/validate_levels.py [levels_dir]
Exit code 0 = all levels valid (warnings allowed), 1 = at least one hard failure.
"""

import sys
import time
import pathlib

# ---------------------------------------------------------------- directions

N, E, S, W = 0, 1, 2, 3
DIR_NAME = ("N", "E", "S", "W")
DELTA = {N: (-1, 0), E: (0, 1), S: (1, 0), W: (0, -1)}
OPPOSITE = {N: S, E: W, S: N, W: E}

# Base connections at rotation digit 0. A rotation digit is the number of 90-degree
# CLOCKWISE steps from the base, which is exactly N->E->S->W->N on each direction.
BASE = {
    "I": frozenset({N, S}),        # straight
    "L": frozenset({N, E}),        # corner
    "T": frozenset({N, E, S}),     # tee
    "X": frozenset({N, E, S, W}),  # cross (rotation is a no-op)
    "E": frozenset({N}),           # cap / dead-end / source / critter seat
    "O": frozenset({N, S}),        # one-way: digit is the direction water EXITS
    "P": frozenset({N, S}),        # sponge: absorbs, never emits
    "C": frozenset({N, S}),        # crab tile: an I-shaped channel carrying a crab
    "B": frozenset({N, E, S, W}),  # tide basin: overflows only when fed from 2+ sides
}
PERIOD = {"I": 2, "L": 4, "T": 4, "X": 1, "E": 4, "O": 4, "P": 2, "C": 2, "B": 1}


def rotate(conns, steps):
    return frozenset((d + steps) % 4 for d in conns)


class Tile:
    __slots__ = ("shape", "rot", "locked")

    def __init__(self, shape, rot, locked):
        self.shape = shape
        self.rot = rot % PERIOD[shape]
        self.locked = locked

    def conns(self, rot=None):
        return rotate(BASE[self.shape], self.rot if rot is None else rot)

    def can_exit(self, d, rot=None):
        """Water may leave this tile through side d."""
        if d not in self.conns(rot):
            return False
        if self.shape == "P":
            return False            # a sponge absorbs; it never emits
        if self.shape == "O":
            # the digit IS the exit direction; refuse every other side
            return d == (self.rot if rot is None else rot)
        return True

    def can_enter(self, d, rot=None):
        """Water may enter this tile through side d."""
        if d not in self.conns(rot):
            return False
        if self.shape == "O":
            # entry only at the end opposite the arrow. Arriving at the exit end is
            # refused outright (tidepool-design: visible refusal beats silent refusal).
            return d == OPPOSITE[(self.rot if rot is None else rot)]
        return True


class Level:
    def __init__(self, path):
        self.path = path
        self.name = ""
        self.id = None
        self.cols = self.rows = 0
        self.par = self.tide = None
        self.par_override = None
        self.source = None
        self.tiles = {}       # (r,c) -> Tile ; missing key == solid rock
        self.critters = []    # [((r,c), species)]
        self.crabs = []       # [(r,c)] - crabs are an OVERLAY on a tile, like critters,
                              # so a crab can sit on a tee or a corner and not only on a
                              # straight. The C glyph still works and means "straight with
                              # a crab on it".
        self.solution = []    # [((r,c), signed_steps)]
        self._parse()

    # ------------------------------------------------------------- parsing

    @staticmethod
    def _coord(tok):
        tok = tok.strip()
        if not (tok.startswith("r") and "c" in tok):
            raise ValueError("bad coordinate %r (want r<row>c<col>)" % tok)
        r, c = tok[1:].split("c", 1)
        return (int(r), int(c))

    def _parse(self):
        lines = self.path.read_text().splitlines()
        block, grid_rows = None, []
        for raw in lines:
            line = raw.split("#", 1)[0].rstrip()
            if not line.strip():
                continue
            indented = line[0] in " \t"
            body = line.strip()

            if not indented and ":" in body:
                key, _, val = body.partition(":")
                key, val = key.strip(), val.strip()
                block = key if not val else None
                if key == "id":
                    self.id = int(val)
                elif key == "name":
                    self.name = val
                elif key == "size":
                    self.cols, self.rows = (int(x) for x in val.lower().split("x"))
                elif key == "par":
                    self.par = int(val)
                elif key == "tide":
                    self.tide = int(val)
                elif key == "par_override":
                    self.par_override = int(val)
                elif key == "source":
                    self.source = self._coord(val)
                elif key in ("grid", "critters", "solution", "crabs"):
                    block = key
                else:
                    raise ValueError("unknown header %r" % key)
                continue

            if block == "grid":
                grid_rows.append(body.split())
            elif block == "critters":
                parts = body.split()
                self.critters.append((self._coord(parts[0]),
                                      parts[1] if len(parts) > 1 else "starfish"))
            elif block == "crabs":
                self.crabs.append(self._coord(body.split()[0]))
            elif block == "solution":
                parts = body.split()
                coord, move = self._coord(parts[0]), parts[1].lower()
                if move.startswith("ccw"):
                    steps = -int(move[3:] or 1)
                elif move.startswith("cw"):
                    steps = int(move[2:] or 1)
                else:
                    raise ValueError("bad move %r (want cw<n> / ccw<n>)" % move)
                self.solution.append((coord, steps))
            else:
                raise ValueError("stray line %r" % body)

        if len(grid_rows) != self.rows:
            raise ValueError("size says %d rows, grid has %d" % (self.rows, len(grid_rows)))
        for r, row in enumerate(grid_rows):
            if len(row) != self.cols:
                raise ValueError("row r%d has %d cells, size says %d"
                                 % (r, len(row), self.cols))
            for c, glyph in enumerate(row):
                if glyph == "..":
                    continue
                if len(glyph) != 2 or glyph[0].upper() not in BASE or not glyph[1].isdigit():
                    raise ValueError("bad glyph %r at r%dc%d" % (glyph, r, c))
                self.tiles[(r, c)] = Tile(glyph[0].upper(), int(glyph[1]),
                                          locked=glyph[0].islower())

        if self.source is None:
            raise ValueError("no source")
        if self.source not in self.tiles:
            raise ValueError("source r%dc%d is solid rock" % self.source)
        for pos, _ in self.critters:
            if pos not in self.tiles:
                raise ValueError("critter at r%dc%d sits on solid rock" % pos)
        if not self.critters:
            raise ValueError("no critters to rescue")

    # -------------------------------------------------------------- solving

    def rotatables(self):
        return sorted(p for p, t in self.tiles.items() if not t.locked and PERIOD[t.shape] > 1)

    def state_from_file(self):
        keys = self.rotatables()
        return tuple(self.tiles[p].rot for p in keys)

    def apply_solution(self):
        keys = self.rotatables()
        idx = {p: i for i, p in enumerate(keys)}
        state = list(self.state_from_file())
        total = 0
        for pos, steps in self.solution:
            if pos not in self.tiles:
                raise ValueError("solution rotates r%dc%d, which is solid rock" % pos)
            if self.tiles[pos].locked:
                raise ValueError("solution rotates r%dc%d, which is LOCKED" % pos)
            if pos not in idx:
                raise ValueError("solution rotates r%dc%d, whose rotation is a no-op" % pos)
            state[idx[pos]] = (state[idx[pos]] + steps) % PERIOD[self.tiles[pos].shape]
            total += abs(steps)
        return tuple(state), total

    def _flow(self, state, crabs):
        """BFS from the source. Returns (wet cells, entry side per cell).

        A cell occupied by a crab is a blocker: water reaches it and stops there.
        Crab occupancy is POSITIONAL, not a property of the tile - crabs walk, and
        the tile one leaves conducts normally afterwards.
        """
        keys = self.rotatables()
        rot = {p: state[i] for i, p in enumerate(keys)}

        def rot_of(p):
            return rot.get(p, self.tiles[p].rot)

        seen = {self.source}
        entry = {}
        stack = [self.source]
        while stack:
            r, c = stack.pop()
            if (r, c) in crabs:
                continue                      # the crab is in the way; water stops
            tile = self.tiles[(r, c)]
            for d in tile.conns(rot_of((r, c))):
                if not tile.can_exit(d, rot_of((r, c))):
                    continue
                dr, dc = DELTA[d]
                nb = (r + dr, c + dc)
                if nb in seen or nb not in self.tiles:
                    continue
                if self.tiles[nb].can_enter(OPPOSITE[d], rot_of(nb)):
                    seen.add(nb)
                    entry[nb] = OPPOSITE[d]   # side of nb the water came in through
                    stack.append(nb)
        return seen, entry

    def resolve(self, state):
        """Settle the board: crabs walk, then report the final wet set.

        A crab walks exactly one tile, once, carrying on in the direction the water
        was already travelling. It vacates the tile it was blocking and blocks the
        one it arrives at - which is the whole mechanic, and why it is worth more
        than a wall. A crab with nowhere to go stays put and waves.

        Iterated to a fixpoint rather than simulated over time: each crab moves at
        most once, so this terminates, and the answer depends only on the board and
        the rotations. Stateless recompute survives, same as every other mechanic.
        """
        keys = self.rotatables()
        rot = {p: state[i] for i, p in enumerate(keys)}

        def rot_of(p):
            return rot.get(p, self.tiles[p].rot)

        def channel_continues(here, d):
            """Can a crab standing on `here` be pushed one more tile in direction d?"""
            nxt = (here[0] + DELTA[d][0], here[1] + DELTA[d][1])
            if nxt not in self.tiles:
                return None
            if not self.tiles[here].can_exit(d, rot_of(here)):
                return None
            if not self.tiles[nxt].can_enter(OPPOSITE[d], rot_of(nxt)):
                return None
            return nxt

        crabs = set(self.crabs) | {p for p, t in self.tiles.items() if t.shape == "C"}
        settled = set()
        for _ in range(len(crabs) + 1):
            wet, entry = self._flow(state, crabs)
            stepped = False
            for c in sorted(crabs - settled):
                if c not in wet or c not in entry:
                    continue                  # not reached yet, or it is the source
                # The tide does not nudge a crab one tile; it pushes it along the
                # channel until something stops it, and there it parks. That is the
                # whole point: the player shapes the channel to choose where the
                # crab ends up, instead of watching a blockage shuffle one step.
                d = OPPOSITE[entry[c]]
                pos = c
                while True:
                    nxt = channel_continues(pos, d)
                    if nxt is None or nxt in crabs:
                        break
                    pos = nxt
                crabs.discard(c)
                crabs.add(pos)
                settled.add(pos)              # parked; it stays and waves from here
                stepped = True
            if not stepped:
                break
        return self._settle_basins(state, crabs), crabs

    def _settle_basins(self, state, crabs):
        """Tide basins (same rule as the engine, PR #44).

        A basin fills from any side but passes water on only once it is fed from two
        or more distinct sides. A part-full basin feeds nobody, so it cannot be its
        own second feed, and a basin that is the source counts the tide as one feed.
        Iterated to a fixpoint: basins only ever gain feeds, so this terminates and
        stays a stateless recompute of the board."""
        basins = {p for p, t in self.tiles.items() if t.shape == "B"}
        if not basins:
            return self._flow(state, crabs)[0]
        keys = self.rotatables()
        rot = {p: state[i] for i, p in enumerate(keys)}
        rot_of = lambda p: rot.get(p, self.tiles[p].rot)
        active = set()
        while True:
            blocked = set(crabs) | (basins - active)
            wet, _ = self._flow(state, blocked)
            newly = set()
            for b in basins - active:
                feeds = 1 if b == self.source else 0
                for d in (N, E, S, W):
                    q = (b[0] + DELTA[d][0], b[1] + DELTA[d][1])
                    if q not in wet or q in blocked or q not in self.tiles:
                        continue
                    if self.tiles[q].can_exit(OPPOSITE[d], rot_of(q)) and \
                            self.tiles[b].can_enter(d, rot_of(b)):
                        feeds += 1
                if feeds >= 2:
                    newly.add(b)
            if not newly:
                return wet
            active |= newly

    def wet(self, state):
        return self.resolve(state)[0]

    def solved(self, state):
        """Every critter rescued AND every sponge satisfied.

        Sponges are thirsty rock: they must end up wet, and they never pass water
        on. So each one costs you a dedicated dead-end branch. An earlier rule had
        them merely absorb-and-block, which a state-space probe showed was exactly
        equivalent to solid rock - same solvable states on every board tested. A
        tile the player cannot act on is not a mechanic.
        """
        w = self.wet(state)
        if not all(pos in w for pos, _ in self.critters):
            return False
        return all(p in w for p, t in self.tiles.items() if t.shape == "P")

    # -------------------------------------------------- bounded optimality

    def shorter_solution_exists(self, limit, node_cap=5_000_000, time_budget=2.0):
        """IDDFS for any solution strictly shorter than `limit`.
        Returns (found: bool, exhausted: bool). exhausted=False means we gave up.

        Bounded by BOTH a node cap and a wall clock. The wall clock is the one that
        matters: this runs in CI on every level, and a gate that can hang is a gate
        that gets switched off. Giving up is a WARN, never a failure, so trading
        search depth for a predictable runtime costs us nothing we care about.
        """
        keys = self.rotatables()
        periods = [PERIOD[self.tiles[p].shape] for p in keys]
        start = self.state_from_file()
        deadline = time.monotonic() + time_budget

        # Breadth-first over rotation states, with a visited set. The obvious
        # implementation here is iterative-deepening DFS, and it is a trap: without
        # a visited set it re-walks the same states exponentially, and a five-tile
        # level can outrun a two-second budget. BFS visits each distinct state once
        # and finds the true minimum, so "proven optimal" now means it.
        frontier = [start]
        seen = {start}
        nodes = 0
        for depth in range(0, limit):
            if not frontier:
                return False, True          # whole reachable space explored
            nxt_frontier = []
            for state in frontier:
                nodes += 1
                if nodes % 1024 == 0 and (nodes >= node_cap or time.monotonic() > deadline):
                    return False, False
                if self.solved(state):
                    return True, True       # a solution shorter than `limit` exists
                if depth + 1 >= limit:
                    continue                # no point expanding the last layer
                for i, period in enumerate(periods):
                    for step in ((1,) if period == 2 else (1, -1)):
                        cand = list(state)
                        cand[i] = (cand[i] + step) % period
                        cand = tuple(cand)
                        if cand not in seen:
                            seen.add(cand)
                            nxt_frontier.append(cand)
            frontier = nxt_frontier
        return False, True


# ------------------------------------------------------------------ driver

def check(level, budget=15.0):
    errors, warnings = [], []
    target = level.par_override if level.par_override is not None else level.par

    if level.par_override is not None and level.par_override < len(level.solution):
        errors.append("par_override (%d) is BELOW the declared solution length (%d); "
                      "par_override may only RAISE par" % (level.par_override, len(level.solution)))

    state, moves = level.apply_solution()

    if not level.solved(state):
        w = level.wet(state)
        missed = ["r%dc%d" % p for p, _ in level.critters if p not in w]
        thirsty = ["r%dc%d" % p for p, t in level.tiles.items()
                   if t.shape == "P" and p not in w]
        parts = []
        if missed:
            parts.append("stranded critters: %s" % ", ".join(missed))
        if thirsty:
            parts.append("dry sponges: %s" % ", ".join(sorted(thirsty)))
        errors.append("UNSOLVED after replaying solution; %s" % "; ".join(parts))

        # Marlow's ask, and a fair one: "you walled off the critter" is a far better
        # message than "level 27 is unsolvable" once you have already authored it.
        # If lifting the sponges out would have let the declared solution through,
        # the sponge placement is the bug, not the routing.
        if missed and any(t.shape == "P" for t in level.tiles.values()):
            kept = dict(level.tiles)
            level.tiles = {p: t for p, t in level.tiles.items() if t.shape != "P"}
            freed = all(p in level.wet(state) for p, _ in level.critters)
            level.tiles = kept
            if freed:
                errors.append("^ a sponge is walling off a critter: every critter is "
                              "reachable once the sponges are lifted out, so move the "
                              "sponge off the route rather than re-routing the level")

    if moves != level.par:
        errors.append("par is %d but the solution is %d rotations" % (level.par, moves))

    # The tide-budget check used to live here as `5 if (level.id or 1) <= 12 else 6` - a third
    # copy of a rule that `tools/verify_levels.gd` owns and that now lives on `Grid.expected_tide`.
    # It was keyed to the level NUMBER, which was only ever right by coincidence, and the
    # 2026-09-20 reorder made it wrong. Rather than re-key a copy nobody runs, the check is gone:
    # one rule, one place, and this file is not the place.

    note = "par unchecked"
    if not errors:
        found, exhausted = level.shorter_solution_exists(level.par, time_budget=budget)
        if found:
            errors.append("a SHORTER solution exists; declared par %d is wrong" % level.par)
        elif exhausted:
            note = "par %d proven optimal" % level.par
        else:
            note = "par %d unverified (search budget spent)" % level.par
            warnings.append("optimality search ran out of budget")
    return errors, warnings, note


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    budget = 15.0
    for a in sys.argv[1:]:
        if a.startswith("--budget="):
            budget = float(a.split("=", 1)[1])
    root = pathlib.Path(args[0] if args else "levels")
    files = sorted(root.glob("*.tide"))
    if not files:
        print("no .tide files under %s" % root)
        return 1

    hard = 0
    warned = 0
    print("Tidepool level validator - %d level(s) under %s/\n" % (len(files), root))
    for f in files:
        try:
            lvl = Level(f)
            errors, warnings, note = check(lvl, budget)
        except Exception as exc:                       # noqa: BLE001 - report, don't crash
            print("  FAIL  %-12s %s: %s" % (f.name, type(exc).__name__, exc))
            hard += 1
            continue

        label = "%-12s %-16s" % (f.name, lvl.name)
        if errors:
            hard += 1
            print("  FAIL  %s" % label)
            for e in errors:
                print("          - %s" % e)
        else:
            flag = "WARN" if warnings else "ok  "
            warned += 1 if warnings else 0
            rotatable = len(lvl.rotatables())
            print("  %s  %s par %-3d tide %-3d %dx%d  %d rotatable  %d critter(s)  %s"
                  % (flag, label, lvl.par, lvl.tide, lvl.cols, lvl.rows,
                     rotatable, len(lvl.critters), note))

    print("\n%d passed, %d warned, %d FAILED" % (len(files) - hard, warned, hard))
    return 1 if hard else 0


if __name__ == "__main__":
    sys.exit(main())
