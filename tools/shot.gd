extends SceneTree

## Tools run with `--script` do NOT get the global class registry the editor builds, so a
## bare `class_name` is undeclared here unless the project happens to have been imported
## already. Preloading by path makes the tool work on a fresh checkout, which is exactly
## where it is most needed. (Cove hit this on main.)
const TideFormat = preload("res://scripts/core/tide_format.gd")

## Loads the game, optionally plays a few moves, and saves a PNG. Needs a real window:
## the headless renderer draws nothing, so this must run windowed.
##   godot --path . --script res://tools/shot.gd -- res://screenshots/x.png [level] [moves]
## `level` is a 0-based index into the sorted levels folder; `moves` is a comma-separated
## list of `r<row>c<col>` clicks (append `:3` for a counter-clockwise turn), so a shot can
## show water actually flowing instead of the untouched board.
func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var out: String = argv[0] if argv.size() > 0 else "res://screenshots/board.png"
	var level := int(argv[1]) if argv.size() > 1 else 0
	var moves: String = argv[2] if argv.size() > 2 else ""

	# Deliberately untyped: the board is reached dynamically so this tool never has to
	# be kept in step with its class.
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var board = scene.get_node("Board")
	for _i in 10:
		await process_frame

	if board.levels.is_empty():
		print("no levels found")
		quit(1)
		return
	board.load_level(level)
	for step in moves.split(",", false):
		var parts := String(step).split(":", false)
		var turns := int(parts[1]) if parts.size() > 1 else 1
		board._try_rotate(TideFormat.parse_coord(String(parts[0])), turns)
	for _i in 20:
		await process_frame
	await create_timer(0.3).timeout

	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	print("screenshot -> %s : %s (level %d, moves %d, tide %d, rescued %d/%d)" % [
		out, error_string(img.save_png(out)), board.grid.id, board.moves, board.tide_left,
		board.rescued.size(), board.grid.critters.size()])
	quit(0)
