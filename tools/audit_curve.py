#!/usr/bin/env python3
"""Audit the teaching curve across every level.

Two questions a par-checker cannot answer, both of which are design claims I have
made in writing and should therefore be able to fail:

  1. TEACHING ORDER - does any level use a mechanic before the level that
     introduces it? `tidepool-ships-24` promises one-way at 13 and sponges at 19,
     and the whole no-tutorial-screens decision rests on that being true.

  2. "COUNTER-CLOCKWISE IS REWARDED, NEVER REQUIRED" - right-click is a shortcut,
     not a skill gate. A player who never discovers it must still finish every
     level at two stars or better. A ccw<n> move costs period-n clockwise clicks
     instead, so the penalty is computable rather than a matter of opinion.

Usage: python3 tools/audit_curve.py [levels_dir]
Exit 1 if either claim is false.
"""
import sys, re, pathlib

PERIOD = {"I": 2, "L": 4, "T": 4, "X": 1, "E": 4, "O": 4, "P": 2, "C": 2}
INTRODUCES = {"one-way": 13, "sponge": 19}   # per tidepool-ships-24
STAR_2_MARGIN = 2                             # 2 stars = par + 2


def parse(path):
    t = path.read_text()
    get = lambda k: re.search(r"^%s:\s*(.+)$" % k, t, re.M).group(1).strip()
    rows = re.search(r"grid:\n((?:\s+.*\n)+)", t).group(1).splitlines()
    cells = {}
    for r, row in enumerate(rows):
        for c, tok in enumerate(row.split()):
            if tok != "..":
                cells[(r, c)] = tok
    moves = []
    for line in t.split("solution:")[1].strip().splitlines():
        p = line.split()
        if len(p) >= 2:
            r, c = p[0][1:].split("c")
            moves.append(((int(r), int(c)), p[1].lower()))
    return int(get("id")), int(get("par")), cells, moves


def features(cells):
    f = set()
    for tok in cells.values():
        s = tok[0].upper()
        f |= {"L": {"corner"}, "T": {"tee"}, "X": {"cross"},
              "O": {"one-way"}, "P": {"sponge"}}.get(s, set())
    return f


def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "levels")
    bad = 0
    print("1. TEACHING ORDER")
    seen = {}
    for path in sorted(root.glob("*.tide")):
        lid, _, cells, _ = parse(path)
        for feat in features(cells):
            seen.setdefault(feat, lid)
            want = INTRODUCES.get(feat)
            if want is not None and lid < want:
                print("   FAIL level %d uses %s, introduced at %d" % (lid, feat, want))
                bad += 1
    for feat, want in INTRODUCES.items():
        got = seen.get(feat)
        ok = got == want
        bad += 0 if ok else 1
        print("   %-8s first appears at %-4s expected %-4s %s"
              % (feat, got, want, "ok" if ok else "FAIL"))

    print("\n2. COUNTER-CLOCKWISE IS REWARDED, NEVER REQUIRED")
    worst = 0
    for path in sorted(root.glob("*.tide")):
        lid, par, cells, moves = parse(path)
        cw, used = 0, 0
        for pos, mv in moves:
            if mv.startswith("ccw"):
                n = int(mv[3:] or 1)
                used += 1
                cw += PERIOD[cells[pos][0].upper()] - n
            else:
                cw += int(mv[2:] or 1)
        if not used:
            continue
        penalty = cw - par
        worst = max(worst, penalty)
        ok = penalty <= STAR_2_MARGIN
        bad += 0 if ok else 1
        print("   level %2d  par %2d  clockwise-only %2d  (+%d)  %s"
              % (lid, par, cw, penalty, "ok, still 2 stars" if ok else "FAIL, below 2 stars"))
    print("   worst clockwise-only penalty: +%d (must be <= +%d)" % (worst, STAR_2_MARGIN))

    print("\n%s" % ("AUDIT CLEAN" if bad == 0 else "%d FAILURE(S)" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
