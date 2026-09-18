extends SceneTree

## Tools run with `--script` do NOT get the global class registry the editor builds, so a
## bare `class_name` is undeclared here unless the project happens to have been imported
## already. Preloading by path makes the tool work on a fresh checkout, which is exactly
## where it is most needed. (Cove hit this on main.)
const TideFormat = preload("res://scripts/core/tide_format.gd")
const Grid = preload("res://scripts/core/grid.gd")
const Flow = preload("res://scripts/core/flow.gd")
const Validator = preload("res://scripts/core/validator.gd")

## Cross-checks every .tide level against the engine that will actually play it.
##
##   Godot --headless --path . --script res://tools/verify_levels.gd [-- res://levels]
##
## Three separate claims per level, because they fail for different reasons:
##   replay   the shipped `solution:` block really does rescue every critter, and it
##            costs exactly `par` clicks
##   optimal  no shorter solution exists -- the engine's own search agrees with the
##            declared par (this is the one that catches a rules disagreement between
##            my BFS and the Director's validator)
##   tide     tide == par + 5 for levels 1-12, par + 6 from 13 on
##
## Exit code is 1 if anything FAILS, so CI can gate on it. A level whose optimality
## search runs out of node budget WARNS instead: an unproven par is not a broken level,
## and a check that cannot afford to run must not be able to block the build.

## Cheap enough to sit on every pull request. The release path raises it via
## TIDEPOOL_NODE_BUDGET, because there a slow proof beats no proof.
const NODE_BUDGET := 2000000

static var node_budget := NODE_BUDGET

const OK := 0
const FAILED := 1
const WARNED := 2


func _initialize() -> void:
	var dir_path := "res://levels"
	var env_budget := OS.get_environment("TIDEPOOL_NODE_BUDGET")
	if env_budget.is_valid_int():
		node_budget = maxi(1, env_budget.to_int())

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		dir_path = args[0]

	var files := _tide_files(dir_path)
	if files.is_empty():
		print("no .tide files under %s" % dir_path)
		quit(1)
		return

	var failed := 0
	var warned := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		var code := _verify(path)
		if code == FAILED:
			failed += 1
		elif code == WARNED:
			warned += 1
	var secs := (Time.get_ticks_msec() - t0) / 1000.0

	print("")
	print("%d levels, %d warned, %d FAILED  (%.1fs)" % [files.size(), warned, failed, secs])

	# A warning is "I could not afford to prove this par minimal". That is a fine thing to
	# carry on a pull request and an unacceptable thing to press onto a build: shipping a
	# par no implementation has proven means a player may find a shorter route than the
	# level claims. The v* export workflow sets TIDEPOOL_RELEASE=1 for exactly this.
	var strict := OS.get_environment("TIDEPOOL_RELEASE") == "1"
	if strict and warned > 0:
		print("TIDEPOOL_RELEASE=1: %d warning(s) are failures at release time." % warned)
	quit(1 if failed > 0 or (strict and warned > 0) else 0)


func _tide_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".tide"):
			out.append(dir_path.path_join(name))
	out.sort()
	return out


## OK, or WARNED when a claim could not be checked, or FAILED when one is false.
## The distinction matters in CI: "this level is wrong" must break the build,
## "my search could not afford to prove this level is right" must not.
func _verify(path: String) -> int:
	var parsed := TideFormat.load_file(path)
	var label := path.get_file()
	if not parsed["ok"]:
		for e in parsed["errors"]:
			print("FAIL %s: %s" % [label, e])
		return 1

	var grid: Grid = parsed["grid"]
	var solution: Array = parsed["solution"]
	var problems: Array[String] = []
	var warnings: Array[String] = []

	# 1. Replay.
	var replay := grid.clone()
	var clicks := 0
	for step in solution:
		replay.rotate_at(step["pos"], step["turns"])
		clicks += int(step["clicks"])
	if solution.is_empty():
		problems.append("no solution: block")
	elif not Flow.is_solved(replay):
		problems.append("shipped solution does not rescue every critter")
	elif clicks != grid.par:
		problems.append("solution costs %d clicks but par is %d" % [clicks, grid.par])

	# 2. Optimality. Search one move past par so "par is a move loose" is visible too.
	var found := Validator.solve(grid, grid.par, node_budget)
	if found["exhausted"]:
		# Unproven, not disproven. The replay above already showed the level is
		# beatable in exactly par; all this misses is "and no faster".
		warnings.append("par not proven optimal: search hit its %d node budget" % found["nodes"])
	elif not found["solved"]:
		problems.append("engine finds NO solution within par %d" % grid.par)
	elif int(found["moves"]) != grid.par:
		problems.append("engine solves in %d, par claims %d" % [found["moves"], grid.par])

	# 3. Tide budget. par+5 up to level 12, par+6 after.
	var want_tide := grid.par + (5 if grid.id <= 12 else 6)
	if grid.tide != want_tide:
		problems.append("tide %d, expected par+%d = %d" % [grid.tide, want_tide - grid.par, want_tide])

	if problems.is_empty():
		print("%-4s %-10s par %-2d tide %-2d  %d critters, %d nodes searched"
				% ["warn" if warnings.size() > 0 else "ok", label, grid.par, grid.tide,
				grid.critters.size(), found["nodes"]])
		for w in warnings:
			print("     %-10s %s" % ["", w])
		return WARNED if warnings.size() > 0 else OK
	for p in problems:
		print("FAIL %-10s %s" % [label, p])
	for w in warnings:
		print("WARN %-10s %s" % [label, w])
	return FAILED
