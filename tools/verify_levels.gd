extends SceneTree
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
## Exit code is 1 if anything fails, so CI can gate on it.

const NODE_BUDGET := 2000000


func _initialize() -> void:
	var dir_path := "res://levels"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		dir_path = args[0]

	var files := _tide_files(dir_path)
	if files.is_empty():
		print("no .tide files under %s" % dir_path)
		quit(1)
		return

	var failed := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		failed += _verify(path)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0

	print("")
	print("%d levels, %d FAILED  (%.1fs)" % [files.size(), failed, secs])
	quit(1 if failed > 0 else 0)


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


## Returns 1 when the level failed any claim, 0 when it is clean.
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
	var found := Validator.solve(grid, grid.par, NODE_BUDGET)
	if found["exhausted"]:
		problems.append("search ran out of budget after %d nodes" % found["nodes"])
	elif not found["solved"]:
		problems.append("engine finds NO solution within par %d" % grid.par)
	elif int(found["moves"]) != grid.par:
		problems.append("engine solves in %d, par claims %d" % [found["moves"], grid.par])

	# 3. Tide budget. par+5 up to level 12, par+6 after.
	var want_tide := grid.par + (5 if grid.id <= 12 else 6)
	if grid.tide != want_tide:
		problems.append("tide %d, expected par+%d = %d" % [grid.tide, want_tide - grid.par, want_tide])

	if problems.is_empty():
		print("ok   %-10s par %-2d tide %-2d  %d critters, %d nodes searched"
				% [label, grid.par, grid.tide, grid.critters.size(), found["nodes"]])
		return 0
	for p in problems:
		print("FAIL %-10s %s" % [label, p])
	return 1
