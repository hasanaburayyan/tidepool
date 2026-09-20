extends SceneTree
## Screenshot the beach map in an arbitrary save state, without playing anything.
##
##   godot --path . --script res://tools/map_shot.gd -- <out.png> [cleared] [overrides]
##
##     out.png    where to write
##     cleared    how many pools, from 1 up, count as finished (default 0 = a fresh save)
##     overrides  comma list of level:stars, e.g. 1:3,2:1,3:2
##
## NOT --headless: the headless renderer draws nothing, so the image comes out empty. Same
## rule as tools/shot.gd. On macOS add --audio-driver Dummy to keep it quiet.
##
## The map reads its state from an injected SaveData rather than from user://, so this
## never touches the player's real save and every pool state is reachable in one command.
## Stars cycle 3, 1, 2 across the cleared pools so a single shot shows all three shell
## counts side by side -- which is exactly the mock Maren asked to approve placement from.

const SaveDataScript := preload("res://scripts/systems/save_data.gd")


func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var out: String = argv[0] if argv.size() > 0 else "res://screenshots/map.png"
	var cleared: int = int(argv[1]) if argv.size() > 1 else 0
	var overrides: String = argv[2] if argv.size() > 2 else ""

	# A temp path that is never written: SaveData only touches disk on save_game(), and
	# this tool never calls it.
	var save = SaveDataScript.new("user://map_shot_scratch.json")
	for level in range(1, cleared + 1):
		save.record_clear(level, [3, 1, 2][(level - 1) % 3])
	for pair in overrides.split(",", false):
		var parts := String(pair).split(":", false)
		if parts.size() == 2:
			save.record_clear(int(parts[0]), int(parts[1]))

	# The title screen has no save state to vary, so it is a fourth argument rather than a
	# tool of its own: same window, same capture, one place that knows how to take a shot.
	if argv.size() > 3 and String(argv[3]) in ["title", "settings"]:
		var title: Node = load("res://scenes/title.tscn").instantiate()
		root.add_child(title)
		# Settings is drawn OVER the title, so the shot shows the layer as the player sees
		# it rather than a panel floating on nothing.
		if String(argv[3]) == "settings":
			var panel: Node = load("res://scenes/settings.tscn").instantiate()
			panel.save = save
			root.add_child(panel)
		for _i in 20:
			await process_frame
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		print("title -> %s : %s" % [out, error_string(root.get_texture().get_image().save_png(out))])
		quit(0)
		return

	var scene: Node = load("res://scenes/map.tscn").instantiate()
	scene.save = save
	root.add_child(scene)
	for _i in 20:
		await process_frame

	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_png(out)

	var states := {"locked": 0, "open": 0, "done": 0}
	for entry in MapLayout.POOLS:
		states[scene.state_of(int(entry["level"]))] += 1
	print("map -> %s : %s (%d pools: %d locked, %d open, %d done; %d stars)" % [
		out, error_string(err), MapLayout.POOLS.size(),
		states["locked"], states["open"], states["done"], save.total_stars()])
	quit(0)
