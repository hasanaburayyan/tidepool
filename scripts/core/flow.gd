class_name Flow
extends RefCounted
## Where the water is. A breadth-first search from the tide source over connected
## channels; the answer is the set of wet tiles. No per-move simulation, no timers,
## no state carried between calls: same grid in, same wet set out, every time.

## Returns the wet set keyed by grid index, so membership is a hash lookup and two
## results compare cleanly in a test.
static func compute(grid: Grid) -> Dictionary:
	var wet := {}
	var start := grid.at(grid.source_pos)
	if start == null or start.kind == Tile.Kind.EMPTY:
		return wet
	# The source tile is the mouth of the tide and is wet by definition -- it is fed from
	# outside the board, not through one of its own openings. The only thing that can stop
	# the water there is a one-way arrow pointing back out to sea.
	if start.kind == Tile.Kind.ONEWAY and start.out_dir == grid.source_from:
		return wet

	var queue: Array[Vector2i] = [grid.source_pos]
	wet[grid.index(grid.source_pos)] = true
	var head := 0
	while head < queue.size():
		var pos: Vector2i = queue[head]
		head += 1
		var tile := grid.at(pos)
		for dir in Tile.DIRS:
			if not tile.can_exit_through(dir):
				continue
			var npos: Vector2i = pos + Tile.DIR_STEPS[dir]
			if not grid.in_bounds(npos):
				continue
			var nidx := grid.index(npos)
			if wet.has(nidx):
				continue
			if not grid.tiles[nidx].can_enter_from(Tile.opposite(dir)):
				continue
			wet[nidx] = true
			queue.append(npos)
	return wet


## How many tiles the water travels to reach each wet tile: the source is 0, its
## neighbours 1, and so on. The same walk as `compute`, carrying the depth along.
##
## Display only. The sim has no notion of water taking time -- flow is one instant
## recompute -- but twelve tiles turning blue in the same frame reads as a state change
## rather than water moving, and the player loses the one cue that says which way it went.
static func distances(grid: Grid) -> Dictionary:
	var depth := {}
	var start := grid.at(grid.source_pos)
	if start == null or start.kind == Tile.Kind.EMPTY:
		return depth
	if start.kind == Tile.Kind.ONEWAY and start.out_dir == grid.source_from:
		return depth
	var queue: Array[Vector2i] = [grid.source_pos]
	depth[grid.index(grid.source_pos)] = 0
	var head := 0
	while head < queue.size():
		var pos: Vector2i = queue[head]
		head += 1
		var here: int = depth[grid.index(pos)]
		var tile := grid.at(pos)
		for dir in Tile.DIRS:
			if not tile.can_exit_through(dir):
				continue
			var npos: Vector2i = pos + Tile.DIR_STEPS[dir]
			if not grid.in_bounds(npos):
				continue
			var nidx := grid.index(npos)
			if depth.has(nidx):
				continue
			if not grid.tiles[nidx].can_enter_from(Tile.opposite(dir)):
				continue
			depth[nidx] = here + 1
			queue.append(npos)
	return depth


## The wet set as sorted positions. For readable test failures and debug draws.
static func wet_positions(grid: Grid, wet: Dictionary) -> Array[Vector2i]:
	var keys := wet.keys()
	keys.sort()
	var out: Array[Vector2i] = []
	for k in keys:
		out.append(grid.pos_of(k))
	return out


## Indices into grid.critters of the critters standing in water.
static func rescued(grid: Grid, wet: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for i in grid.critters.size():
		if wet.has(grid.index(grid.critters[i]["pos"])):
			out.append(i)
	return out


## Which one-ways are visibly turning water away: water has reached the mouth the arrow
## points out of, and the arrow will not let it in. Keyed by grid index, like `wet`.
##
## This changes nothing about where the water goes -- refusal is already baked into
## `can_enter_from`. It exists so the board can SHOW it. Levels 14, 16, 17 and 18 are
## built on the player seeing an arrow refuse and understanding why, and an invisible
## refusal reads as a bug in the flow (Maren, design doc; `tidepool-engineering` §9).
static func refusing(grid: Grid, wet: Dictionary) -> Dictionary:
	var out := {}
	for y in grid.height:
		for x in grid.width:
			var pos := Vector2i(x, y)
			var tile := grid.at(pos)
			if tile.kind != Tile.Kind.ONEWAY:
				continue
			# The exit side is the only side that refuses. Water sitting anywhere else is
			# simply flowing in, which is the arrow working rather than the arrow blocking.
			# A wet arrow is one water got into and is flowing out of -- that is the arrow
			# working, not blocking. Only a DRY arrow with water at its mouth is refusing.
			if wet.has(grid.index(pos)):
				continue
			var outside: Vector2i = pos + Tile.DIR_STEPS[tile.out_dir]
			if not grid.in_bounds(outside) or not wet.has(grid.index(outside)):
				continue
			# Only a neighbour that is actually open towards us is being turned away; a
			# wet tile with a wall facing the arrow was never going to enter it.
			if grid.at(outside).connects(Tile.opposite(tile.out_dir)):
				out[grid.index(pos)] = true
	return out


static func all_rescued(grid: Grid, wet: Dictionary) -> bool:
	if grid.critters.is_empty():
		return false
	for c in grid.critters:
		if not wet.has(grid.index(c["pos"])):
			return false
	return true


## A sponge is thirsty rock (`tidepool-sponge-rules` v2): it drinks from either end and
## emits from neither, so you can never route *through* one -- but the level does not
## clear until every sponge is soaked, which means each one costs a dedicated dead-end
## branch. Derived from the wet set on every call, never stored, so flow stays stateless.
static func all_sponges_wet(grid: Grid, wet: Dictionary) -> bool:
	for i in grid.tiles.size():
		var t: Tile = grid.tiles[i]
		if t != null and t.kind == Tile.Kind.SPONGE and not wet.has(i):
			return false
	return true


## The clear condition: every critter standing in water and every sponge soaked.
static func is_cleared(grid: Grid, wet: Dictionary) -> bool:
	return all_rescued(grid, wet) and all_sponges_wet(grid, wet)


## Convenience for the solver: recompute flow and ask whether the level is cleared.
static func is_solved(grid: Grid) -> bool:
	return is_cleared(grid, compute(grid))
