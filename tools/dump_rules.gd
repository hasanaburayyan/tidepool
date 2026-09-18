extends SceneTree
## Prints the rules and the flow results as JSON, so nothing outside the engine has to
## keep its own copy of either.
##
## ON A FRESH CHECKOUT, IMPORT FIRST:
##   godot --headless --path . --import
##
##   godot --headless --path . --script res://tools/dump_rules.gd [-- res://levels] > rules.json
##
## Two duplications this exists to delete:
##   * `art/build.py`'s `flood` reimplements the connection rule in Python to colour the
##     preview sheets. It can read `levels[].wet` instead.
##   * `tools/audit_curve.py`'s `STAR_2_MARGIN` is a second copy of the `par + 2` literal
##     in `board.gd:stars()`. It can read `stars`.
##
## The rule is that the engine is the only place a rule lives. A second implementation is
## not a backup: when the two disagree, the one nobody is running is the one that is wrong,
## and we find out at level 34. This has already cost us once, when six levels were green
## in the validator and did not load in the game at all.

const TideFormat = preload("res://scripts/core/tide_format.gd")
const Flow = preload("res://scripts/core/flow.gd")
const Board = preload("res://scripts/game/board.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir_path: String = args[0] if args.size() > 0 else "res://levels"
	var out_path: String = args[1] if args.size() > 1 else "res://build/rules.json"

	var levels: Array = []
	for path in _tide_files(dir_path):
		var parsed := TideFormat.load_file(path)
		if not parsed["ok"]:
			printerr("%s: %s" % [path.get_file(), parsed["errors"]])
			quit(1)
			return
		levels.append(_dump_level(parsed))

	var text := JSON.stringify({
		# Read from board.gd rather than restated, so a change there reaches every reader.
		"stars": {"three_at_or_under": "par", "two_within": Board.STAR_2_MARGIN},
		"levels": levels,
	}, "  ")
	# A file, not stdout: Godot prints its version banner to stdout, so the first reader to
	# pipe this into a JSON parser would get a syntax error and blame the tool.
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write %s" % out_path)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("rules -> %s (%d levels)" % [out_path, levels.size()])
	quit(0)


## Per level: the shipped board, and the wet set once its solution has been played. The
## wet set is what a preview wants; recomputing it outside the engine is the duplication.
func _dump_level(parsed: Dictionary) -> Dictionary:
	var grid = parsed["grid"]
	var solved = grid.clone()
	for step in parsed["solution"]:
		solved.rotate_at(step["pos"], step["turns"])

	var wet_start: Array[int] = []
	for idx in Flow.compute(grid):
		wet_start.append(idx)
	var wet_solved: Array[int] = []
	for idx in Flow.compute(solved):
		wet_solved.append(idx)
	wet_start.sort()
	wet_solved.sort()

	return {
		"id": grid.id,
		"name": grid.title,
		"width": grid.width,
		"height": grid.height,
		"par": grid.par,
		"tide": grid.tide,
		# Indices are row-major: index = y * width + x, the same as Grid.index().
		"wet_at_start": wet_start,
		"wet_when_solved": wet_solved,
	}


func _tide_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("no such directory: %s" % dir_path)
		return out
	for name in dir.get_files():
		if name.ends_with(".tide"):
			out.append(dir_path.path_join(name))
	out.sort()
	return out
