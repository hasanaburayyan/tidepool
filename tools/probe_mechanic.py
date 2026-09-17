#!/usr/bin/env python3
"""Is a mechanic actually a mechanic?

Enumerate EVERY reachable rotation state of a board and record which ones solve the
level. Then neutralise the mechanic under test and do it again. If the two
solvable-sets are the same, the mechanic changes nothing the player can act on: it
is scenery, whatever its sprite and however good the rule sounds written down.

This caught two dead sponge rules before anyone built on them. Point it at a new
mechanic BEFORE authoring levels for it, not after.

Usage:  python3 tools/probe_mechanic.py <board.tide> [board2.tide ...]
"""
import sys, itertools, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import validate_levels as V


def solvable_states(lvl):
    keys = lvl.rotatables()
    periods = [V.PERIOD[lvl.tiles[p].shape] for p in keys]
    return ({s for s in itertools.product(*[range(p) for p in periods]) if lvl.solved(s)},
            keys)


def variant(path, mode):
    lvl = V.Level(path)
    if mode == "as_rock":                       # mechanic tile becomes solid rock
        for pos, t in list(lvl.tiles.items()):
            if t.shape in ("P", "C") or pos in lvl.crabs:
                lvl.tiles.pop(pos, None)
        lvl.crabs = []
    elif mode == "as_plain":                    # mechanic tile becomes an ordinary channel
        for pos, t in list(lvl.tiles.items()):
            if t.shape in ("P", "C"):
                t.shape = "I"
        lvl.crabs = []
    return lvl


def compare(path, mode):
    a, ka = solvable_states(V.Level(path))
    b, kb = solvable_states(variant(path, mode))
    shared = [k for k in ka if k in set(kb)]
    pa = {tuple(s[ka.index(k)] for k in shared) for s in a}
    pb = {tuple(s[kb.index(k)] for k in shared) for s in b}
    return len(pa), len(pb), pa == pb


for path in [pathlib.Path(p) for p in sys.argv[1:]]:
    row = ["%-26s" % path.name]
    for mode in ("as_plain", "as_rock"):
        try:
            n, m, same = compare(path, mode)
            row.append("vs %-8s %3d/%-3d %s" % (mode, n, m, "INERT" if same else "differs"))
        except Exception as exc:
            row.append("vs %-8s ERROR %s" % (mode, exc))
    print("  ".join(row))
