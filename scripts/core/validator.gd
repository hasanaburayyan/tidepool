class_name Validator
extends RefCounted
## Proves a level is solvable, and in how few clicks.
##
## Two observations make the search tractable. Rotations commute -- turning tile A then
## tile B leaves the same board as B then A -- so a solution is not an ordered plan but
## a count of turns per tile, and we only ever need combinations, never permutations.
## And most tiles repeat before four turns: a cross and a patch of sand look the same
## after every rotation, a straight repeats after two. Both get pruned out up front.
##
## The search deepens one move at a time, so the first solution it finds is the cheapest
## one, which is exactly the par the level should ship with.

const DEFAULT_NODE_BUDGET := 400000


## Returns:
##   solved       did we find a solution at all
##   moves        fewest clicks that solve it (-1 when unsolved)
##   plan         Array of { "pos": Vector2i, "turns": int }
##   exhausted    true when we ran out of node budget, so "not solved" means "do not know"
##   nodes        boards examined
static func solve(grid: Grid, max_moves: int, node_budget: int = DEFAULT_NODE_BUDGET) -> Dictionary:
	var work := grid.clone()
	var candidates := work.rotatable_indices()
	var state := {"nodes": 0, "budget": node_budget, "exhausted": false}

	for depth in max_moves + 1:
		var plan: Array[Dictionary] = []
		if _search(work, candidates, 0, depth, plan, state):
			plan.reverse()  # _search appends as the recursion unwinds
			return {"solved": true, "moves": depth, "plan": plan,
					"exhausted": false, "nodes": state["nodes"]}
		if state["exhausted"]:
			break
	return {"solved": false, "moves": -1, "plan": [], "exhausted": state["exhausted"],
			"nodes": state["nodes"]}


## Spend exactly `remaining` moves, only on candidates at or after `from`, and report
## whether the board ends up solved. Every tile is turned back before we return, so the
## caller's grid is untouched on the way out.
static func _search(grid: Grid, candidates: Array[int], from: int, remaining: int,
		plan: Array[Dictionary], state: Dictionary) -> bool:
	state["nodes"] += 1
	if state["nodes"] > state["budget"]:
		state["exhausted"] = true
		return false

	if remaining == 0:
		return Flow.is_solved(grid)

	for i in range(from, candidates.size()):
		# Not enough moves left to touch every remaining tile at least once is fine,
		# but we do need at least one move per tile we are still going to visit.
		var idx: int = candidates[i]
		var tile := grid.tiles[idx]
		var max_turns: int = mini(tile.rotation_period() - 1, remaining)
		for turns in range(1, max_turns + 1):
			tile.rotate_cw(turns)
			var found := _search(grid, candidates, i + 1, remaining - turns, plan, state)
			tile.rotate_cw(-turns)
			if found:
				plan.append({"pos": grid.pos_of(idx), "turns": turns})
				return true
			if state["exhausted"]:
				return false
	return false


## Check one level end to end: does it parse, is it solvable, and does par match the
## true minimum. Returns { "ok": bool, "lines": Array[String], "moves": int }.
static func check_level(path: String, node_budget: int = DEFAULT_NODE_BUDGET) -> Dictionary:
	var lines: Array[String] = []
	var result := LevelIO.load_file(path)
	if not result["ok"]:
		for e in result["errors"]:
			lines.append("  " + e)
		return {"ok": false, "lines": lines, "moves": -1}

	var grid: Grid = result["grid"]
	var label := "%s (%dx%d, par %d)" % [path.get_file(), grid.width, grid.height, grid.par]

	if Flow.is_solved(grid):
		lines.append("  %s: already solved before the player touches it" % label)
		return {"ok": false, "lines": lines, "moves": 0}

	# Search one move past par so we can tell "needs more than par" from "impossible".
	var solution := solve(grid, grid.par + 1, node_budget)
	if not solution["solved"]:
		if solution["exhausted"]:
			lines.append("  %s: INCONCLUSIVE, node budget %d spent without an answer" % [
				label, node_budget])
		else:
			lines.append("  %s: NOT SOLVABLE within %d moves" % [label, grid.par + 1])
		return {"ok": false, "lines": lines, "moves": -1}

	var moves: int = solution["moves"]
	if moves > grid.par:
		lines.append("  %s: needs %d moves, par says %d" % [label, moves, grid.par])
		return {"ok": false, "lines": lines, "moves": moves}
	if moves < grid.par:
		lines.append("  %s: solvable in %d, par %d is loose (nodes %d)" % [
			label, moves, grid.par, solution["nodes"]])
		return {"ok": true, "lines": lines, "moves": moves}

	lines.append("  %s: OK, minimum %d moves (nodes %d)" % [label, moves, solution["nodes"]])
	return {"ok": true, "lines": lines, "moves": moves}
