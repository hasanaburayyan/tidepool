#!/usr/bin/env python3
"""TIDE-27 spike: probe two candidate mechanics before anyone builds them.

Reproduces the numbers in `tidepool-dynamics-proposals`. Exhaustive BFS over every
reachable rotation state; each mechanic is compared against the same board with the
mechanic neutralised (unlinked tiles / basin treated as a plain cross).

    python3 tools/spikes/dynamics_probe.py

Spike code, not engine code: the basin and link rules live only here until the board
decides. Nothing in scripts/ or levels/ depends on it.
"""
import sys, itertools, collections
import os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import validate_levels as V
N,E,S,W = V.N,V.E,V.S,V.W

def board(rows):
    t={}
    for r,row in enumerate(rows):
        for c,g in enumerate(row.split()):
            if g!="..": t[(r,c)]=g
    return t
def conns(g,rot):
    s=g[0].upper()
    if s=="B": return {N,E,S,W}
    return set(V.rotate(V.BASE[s],rot))
PER={"I":2,"L":4,"T":4,"X":1,"E":4,"B":1}

def flow(tiles,rots,src,basin_rule=True):
    """static BFS; a basin B emits only when fed from >=2 sides (iterated to fixpoint)"""
    wet={src}; changed=True
    while changed:
        changed=False
        feeds=collections.defaultdict(set)
        stack=list(wet); seen=set(wet)
        while stack:
            p=stack.pop(); g=tiles[p]
            if g[0].upper()=="B" and basin_rule and len(feeds[p])<2 and p!=src: continue
            for d in conns(g,rots[p]):
                q=(p[0]+V.DELTA[d][0],p[1]+V.DELTA[d][1])
                if q not in tiles: continue
                if V.OPPOSITE[d] in conns(tiles[q],rots[q]):
                    feeds[q].add(V.OPPOSITE[d])
                    if q not in seen: seen.add(q); stack.append(q)
        if seen!=wet: wet=seen; changed=True
    return wet

def search(tiles,src,goals,links=(),basin_rule=True):
    rot=[p for p,g in tiles.items() if g[0].isupper() and PER[g[0].upper()]>1]
    start={p:int(tiles[p][1]) for p in tiles}
    partner={}
    for a,b in links: partner[a]=b; partner[b]=a
    key=lambda r: tuple(r[p] for p in rot)
    def ok(r): w=flow(tiles,r,src,basin_rule); return all(g in w for g in goals)
    q=collections.deque([(start,0)]); seen={key(start)}; best=None; nsolv=0
    while q:
        r,d=q.popleft()
        if ok(r):
            nsolv+=1
            if best is None: best=d
        for p in rot:
            for s in ((1,) if PER[tiles[p][0].upper()]==2 else (1,-1)):
                r2=dict(r); moved=[p]+([partner[p]] if p in partner else [])
                for m in moved: r2[m]=(r2[m]+s)%PER[tiles[m][0].upper()]
                k=key(r2)
                if k not in seen: seen.add(k); q.append((r2,d+1))
    return best,nsolv,len(seen)

print("=== CANDIDATE 1: LINKED TILES (two marked tiles always turn together) ===")
# A at r2c1 must end E-W. B at r0c3 must end N-S. Linked, they turn together,
# so fixing one un-fixes the other unless the player routes round one of them.
T1=board(["..  ..  ..  L0  e3",
          "..  ..  ..  I1  ..",
          "e1  I0  i1  T1  ..",
          "..  ..  ..  I1  ..",
          "..  ..  ..  L0  e3"])
g1=[(0,4),(4,4)]
for name,lk in (("linked",[((2,1),(1,3))]),("unlinked",[])):
    print("  %-9s min moves %-4s solvable states %-4s reachable %s" % ((name,)+search(T1,(2,0),g1,lk)))

print("\n=== CANDIDATE 2: TIDE BASIN (only overflows once fed from two sides) ===")
T2=board(["..  L0  I1  L0  ..",
          "..  I0  ..  I0  ..",
          "e1  T0  I0  B0  e3",
          "..  ..  ..  ..  .."])
g2=[(2,4)]
print("  basin     min moves %-4s solvable states %-4s reachable %s" % search(T2,(2,0),g2,(),True))
print("  as cross  min moves %-4s solvable states %-4s reachable %s" % search(T2,(2,0),g2,(),False))
