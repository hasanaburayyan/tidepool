extends SceneTree
## Prints the rules and the flow results as JSON, so nothing outside the engine has to
## keep its own copy of either.
##
## ON A FRESH CHECKOUT, IMPORT FIRST:
##   godot --headless --path . --import
##
##   godot --headless --path . --script res://tools/dump_rules.gd [-- res://levels [res://build/rules.json]]
##
## Writes the FILE (default res://build/rules.json); stdout only gets the Godot banner and a one-line
## summary, so do not redirect it into a .json.
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

	var wet_at_start := Flow.compute(grid)
	var wet_solved := Flow.compute(solved)

	return {
		"id": grid.id,
		"name": grid.title,
		"width": grid.width,
		"height": grid.height,
		"par": grid.par,
		"tide": grid.tide,
		# Indices are row-major: index = y * width + x, the same as Grid.index().
		"wet_at_start": _sorted_keys(wet_at_start),
		"wet_when_solved": _sorted_keys(wet_solved),
		# One-ways turning water away (Flow.refusing): a dry arrow with water at its exit mouth.
		"refusing_at_start": _sorted_keys(Flow.refusing(grid, wet_at_start)),
		"refusing_when_solved": _sorted_keys(Flow.refusing(solved, wet_solved)),
		# Every cell, row-major, so a preview can be drawn without parsing .tide a second time.
		"tiles_at_start": _dump_tiles(grid),
		"tiles_when_solved": _dump_tiles(solved),
	}


## Per cell: kind ("empty", "channel", "oneway", "sponge", "crab"), sides (the same key the sprite
## names use, from Tile.sides_key), locked, and for one-ways `out`, the side the water leaves by.
func _dump_tiles(grid) -> Array:
	var out: Array = []
	for tile in grid.tiles:
		if tile == null:
			out.append({"kind": "empty", "sides": "", "locked": true})
			continue
		var cell := {
			"kind": String(Tile.Kind.keys()[tile.kind]).to_lower(),
			"sides": tile.sides_key(),
			"locked": tile.locked,
		}
		if tile.kind == Tile.Kind.ONEWAY:
			cell["out"] = String(Tile.DIR_NAMES[tile.out_dir]).to_lower()
		out.append(cell)
	return out


func _sorted_keys(keyed: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for idx in keyed:
		out.append(idx)
	out.sort()
	return out


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
