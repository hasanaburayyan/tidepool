extends SceneTree
## Loads the game, lets it settle, and saves a PNG. Needs a real window: the headless
## renderer draws nothing, so this must run windowed.
##   godot --path . --script res://tools/shot.gd -- user://shot.png
func _initialize() -> void:
	var out := "res://screenshots/board.png"
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		out = argv[0]
	root.add_child(load("res://scenes/main.tscn").instantiate())
	for _i in 30:
		await process_frame
	await create_timer(0.3).timeout
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	print("screenshot -> %s : %s" % [out, error_string(img.save_png(out))])
	quit(0)
