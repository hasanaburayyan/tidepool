extends SceneTree
## Does the GAME load -- not the rules, the game? Exits 1 if it does not.
##
## ON A FRESH CHECKOUT, IMPORT FIRST:
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/load_check.gd
##
## Why this exists: on 2026-09-18 main shipped a board.gd that did not parse, so the game could not
## start, and every PR's CI was green -- because CI only ran the core unit tests, and those never
## load board.gd. A script that fails to parse does not throw here; Godot logs an error and hands back
## a node with no script attached. So the test is "does Board have its methods", not "did load work".

func _initialize() -> void:
	var packed = load("res://scenes/main.tscn")
	if packed == null:
		print("FAIL main.tscn did not load")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	var board: Node = scene.get_node_or_null("Board")
	var ok := board != null and board.get_script() != null and board.has_method("load_level")
	scene.free()
	if not ok:
		print("FAIL the board script did not load -- look for a Parse Error above")
		quit(1)
		return
	print("ok   the game loads: main.tscn, Board and its script")

	var missing := _missing_sprites()
	if not missing.is_empty():
		print("FAIL %d tile sprites missing or unloadable." % missing.size())
		print("     Deleted on a Mac clone? `git restore assets/tiles`. New art not imported? `godot --headless --path . --import`.")
		for key in missing.slice(0, 12):
			print("       %s" % key)
		quit(1)
		return
	print("ok   every tile sprite family is complete (%d files)" % _expected_sprites().size())
	quit(0)


## Every tile sprite the board draws, family by family. A hole in a family never errors in the game:
## the board quietly falls back to a drawn placeholder, so a missing file only shows up as ugly art
## in somebody's build. On a case-insensitive Mac clone, pulling #45 deleted 40 of these from disk
## (Nerite, 2026-09-19). CI's fresh clones never hit that, so this runs wherever load_check runs.
static func _expected_sprites() -> Array[String]:
	var dirs := ["n", "e", "s", "w"]
	var out: Array[String] = []
	# Every non-empty set of open sides, named the way Tile.sides_key() names it: N-E-S-W order.
	for mask in range(1, 16):
		var sides := ""
		for d in 4:
			if mask & (1 << d):
				sides += dirs[d]
		for state in ["dry", "wet"]:
			out.append("channel_%s_%s" % [sides, state])
			out.append("locked_%s_%s" % [sides, state])
	for sides in ["ns", "ew"]:
		for state in ["dry", "wet"]:
			out.append("sponge_%s_%s" % [sides, state])
	for state in ["dry", "wait", "over"]:
		out.append("basin_nesw_%s" % state)
	for d in dirs:
		for state in ["dry", "wet"]:
			for refused in ["", "_refused"]:
				out.append("oneway_%s_%s%s" % [d, state, refused])
	return out


## The source file must be on disk, not just in the import cache, which can outlive a deleted PNG
## and hide the loss until the next clean import.
static func _missing_sprites() -> Array[String]:
	var out: Array[String] = []
	for key in _expected_sprites():
		var path := "res://assets/tiles/%s.png" % key
		if not FileAccess.file_exists(path) or not (load(path) is Texture2D):
			out.append(key)
	return out
