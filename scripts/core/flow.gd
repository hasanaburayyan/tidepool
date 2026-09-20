class_name Flow
extends RefCounted
## Where the water is. A breadth-first search from the tide source over connected
## channels; the answer is the set of wet tiles. No per-move simulation, no timers,
## no state carried between calls: same grid in, same wet set out, every time.

## Returns the wet set keyed by grid index, so membership is a hash lookup and two
## results compare cleanly in a test.
static func compute(grid: Grid) -> Dictionary:
	return _settle(grid, false)[0]


## How many tiles the water travels to reach each wet tile: the source is 0, its
## neighbours 1, and so on. The same walk as `compute`, carrying the depth along.
##
## Display only. The sim has no notion of water taking time -- flow is one instant
## recompute -- but twelve tiles turning blue in the same frame reads as a state change
## rather than water moving, and the player loses the one cue that says which way it went.
static func distances(grid: Grid) -> Dictionary:
	return _settle(grid, true)[0]


## The basins passing water on, keyed by grid index. A wet basin NOT in here is sitting
## part-full, waiting for a second current. Display only, like `refusing`: the board needs
## it to pick the part-full or overflowing sprite, and "waiting for more" has to be seen.
static func overflowing(grid: Grid) -> Dictionary:
	return _settle(grid, false)[1]


## A basin (`tidepool-dynamics-proposals` §1) fills from any side but only overflows once
## water reaches it from two or more. Whether it has two feeds depends on the flow, and the
## flow depends on which basins overflow, so: walk with the basins known to overflow, count
## feeds, open the ones that now qualify, walk again. The open set only ever grows -- more
## water never takes a feed away -- so this stops, after at most one walk per basin plus
## one. Still no state between calls: same grid in, same answer out.
##
## Returns [reached, open]. A level with no basins pays for exactly one walk.
static func _settle(grid: Grid, with_depth: bool) -> Array:
	var open := {}
	while true:
		var basins: Array[int] = []
		var reached := _walk(grid, open, with_depth, basins)
		var grown := {}
		for idx in basins:
			if _feeds(grid, reached, open, idx) >= 2:
				grown[idx] = true
		if grown.size() == open.size():
			return [reached, open]
		open = grown
	return [{}, {}]


## One breadth-first walk from the source. `open` holds the basins allowed to pass water
## on; every other basin it reaches is recorded in `basins` and treated as a dead end.
## Values are the step count from the source when `with_depth`, otherwise true.
static func _walk(grid: Grid, open: Dictionary, with_depth: bool, basins: Array[int]) -> Dictionary:
	var reached := {}
	var start := grid.at(grid.source_pos)
	if start == null or start.kind == Tile.Kind.EMPTY:
		return reached
	# The source tile is the mouth of the tide and is wet by definition -- it is fed from
	# outside the board, not through one of its own openings. The only thing that can stop
	# the water there is a one-way arrow pointing back out to sea.
	if start.kind == Tile.Kind.ONEWAY and start.out_dir == grid.source_from:
		return reached

	var queue: Array[Vector2i] = [grid.source_pos]
	reached[grid.index(grid.source_pos)] = 0 if with_depth else true
	var head := 0
	while head < queue.size():
		var pos: Vector2i = queue[head]
		head += 1
		var idx := grid.index(pos)
		var tile: Tile = grid.tiles[idx]
		if tile.kind == Tile.Kind.BASIN:
			basins.append(idx)
			if not open.has(idx):
				continue
		var next: Variant = reached[idx] + 1 if with_depth else true
		for dir in Tile.DIRS:
			if not tile.can_exit_through(dir):
				continue
			var npos: Vector2i = pos + Tile.DIR_STEPS[dir]
			if not grid.in_bounds(npos):
				continue
			var nidx := grid.index(npos)
			if reached.has(nidx):
				continue
			if not grid.tiles[nidx].can_enter_from(Tile.opposite(dir)):
				continue
			reached[nidx] = next
			queue.append(npos)
	return reached


## How many sides of the basin at `idx` water is arriving through: a wet neighbour whose
## channel leads in. A neighbouring basin only counts once it overflows itself -- a
## part-full basin passes nothing, so two part-full basins side by side stay part-full.
## The tide itself counts as a feed when the source tile is a basin.
static func _feeds(grid: Grid, wet: Dictionary, open: Dictionary, idx: int) -> int:
	var pos := grid.pos_of(idx)
	var basin: Tile = grid.tiles[idx]
	var n := 0
	for dir in Tile.DIRS:
		if not basin.can_enter_from(dir):
			continue
		if pos == grid.source_pos and dir == grid.source_from:
			n += 1
			continue
		var npos: Vector2i = pos + Tile.DIR_STEPS[dir]
		if not grid.in_bounds(npos):
			continue
		var nidx := grid.index(npos)
		if not wet.has(nidx):
			continue
		var feeder: Tile = grid.tiles[nidx]
		if feeder.kind == Tile.Kind.BASIN and not open.has(nidx):
			continue
		if feeder.can_exit_through(Tile.opposite(dir)):
			n += 1
	return n


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
	var open: Variant = null  # Basin states, only worked out if an arrow faces a basin.
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
			var feeder := grid.at(outside)
			# A part-full basin passes nothing on, so there is nothing at this mouth to
			# turn away. Showing a refusal there would blame the arrow for the basin.
			if feeder.kind == Tile.Kind.BASIN:
				if open == null:
					open = overflowing(grid)
				if not open.has(grid.index(outside)):
					continue
			if feeder.connects(Tile.opposite(tile.out_dir)):
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
