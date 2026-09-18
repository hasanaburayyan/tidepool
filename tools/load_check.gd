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
	quit(0)
