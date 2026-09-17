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


static func all_rescued(grid: Grid, wet: Dictionary) -> bool:
	if grid.critters.is_empty():
		return false
	for c in grid.critters:
		if not wet.has(grid.index(c["pos"])):
			return false
	return true


## Convenience for the solver: recompute flow and ask whether the level is cleared.
static func is_solved(grid: Grid) -> bool:
	return all_rescued(grid, compute(grid))
