#!/usr/bin/env python3
"""Is Linked Tiles a mechanic, or just a difficulty tax?

Linked Tiles is not a new kind of tile. It is a COUPLING between two ordinary
tiles: click either one and both turn. That makes it a constraint, so the usual
probe question ("does it add reachable states?") is the wrong one -- a coupling
can only ever remove states. Asked that way it would always look like scenery.

The right question is whether the player gets anything BACK for the states they
lose. They do, in exactly one currency: a linked pair costs ONE click to turn TWO
tiles. So the mechanic is a discount and a restriction at the same time, and it
is worth shipping only where the discount is real.

This probe measures both halves on the same board:

  par_unlinked  - the two tiles turn independently, one click each
  par_linked    - the two tiles share a rotation, one click turns both

  par_linked < par_unlinked   the link paid the player back. A mechanic.
  par_linked == par_unlinked  the link changed nothing. Scenery.
  no linked solution at all   the board is over-constrained. An authoring error,
                              not a hard level: the player can see no way in.

Boards declare their pairs with a comment line:  # links: r1c1+r1c3
Usage:  python3 tools/spikes/link_probe.py tools/probe_boards/link_*.tide
"""
import sys, re, itertools, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import validate_levels as V


def _coord(tok):
    m = re.fullmatch(r"r(\d+)c(\d+)", tok)
    if not m:
        raise ValueError("bad coordinate %r (want r<row>c<col>)" % tok)
    return (int(m.group(1)), int(m.group(2)))


def read_links(path):
    groups = []
    for line in pathlib.Path(path).read_text().splitlines():
        if line.strip().startswith("# links:"):
            for grp in line.split(":", 1)[1].split(","):
                groups.append(tuple(_coord(p.strip()) for p in grp.strip().split("+")))
    return groups


def steps(a, b, period):
    """Clicks to turn a tile from rotation a to rotation b, either direction."""
    return min((b - a) % period, (a - b) % period)


def probe(path):
    lvl = V.Level(pathlib.Path(path))
    keys = lvl.rotatables()
    periods = [V.PERIOD[lvl.tiles[p].shape] for p in keys]
    start = lvl.state_from_file()
    groups = read_links(path)
    idx = {p: i for i, p in enumerate(keys)}

    for g in groups:
        for p in g:
            if p not in idx:
                sys.exit("%s: linked tile %r is not rotatable" % (path, p))
        if len({periods[idx[p]] for p in g}) != 1:
            sys.exit("%s: linked tiles must share a period" % path)
        if len({start[idx[p]] for p in g}) != 1:
            sys.exit("%s: linked tiles must START at the same rotation" % path)

    solvable = [s for s in itertools.product(*[range(p) for p in periods]) if lvl.solved(s)]
    legal = [s for s in solvable if all(len({s[idx[p]] for p in g}) == 1 for g in groups)]

    def cost(s, linked):
        seen, total = set(), 0
        if linked:
            for g in groups:
                i = idx[g[0]]
                total += steps(start[i], s[i], periods[i])
                seen.update(idx[p] for p in g)
        return total + sum(steps(start[i], s[i], periods[i])
                           for i in range(len(keys)) if i not in seen)

    par_un = min((cost(s, False) for s in solvable), default=None)
    par_li = min((cost(s, True) for s in legal), default=None)

    print("%-22s %d rotatable, %d link group(s)" % (pathlib.Path(path).name, len(keys), len(groups)))
    print("   solvable states  unlinked %3d   linked %3d" % (len(solvable), len(legal)))
    if par_li is None:
        print("   par              unlinked %3s   linked   -- OVER-CONSTRAINED" % par_un)
        print("   VERDICT: no solution survives the link. Authoring error, not a hard level.\n")
        return
    print("   par (clicks)     unlinked %3d   linked %3d" % (par_un, par_li))
    if par_li < par_un:
        print("   VERDICT: MECHANIC. The link saves %d click(s); the player is paid back.\n"
              % (par_un - par_li))
    else:
        print("   VERDICT: SCENERY. The link costs states and returns nothing.\n")


if __name__ == "__main__":
    for a in sys.argv[1:]:
        probe(a)
