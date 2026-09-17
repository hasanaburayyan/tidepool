extends SceneTree
## Renders generated tiles through Godot at game scale and saves a PNG, so a sprite is
## judged as the engine actually draws it rather than as a file viewer shows it. Like
## `shot.gd` this needs a real window - the headless renderer draws nothing.
##
##   godot --path . --script res://tools/art_preview.gd -- res://screenshots/art_strip.png
##
## Tiles are loaded straight off disk with Image.load_from_file instead of as imported
## resources. That keeps the art pipeline's output out of the .import system while it is
## still churning; when the tile set settles, these become ordinary imported textures with
## filter=Nearest, which project.godot already sets globally
## (rendering/textures/canvas_textures/default_texture_filter=0).

## 32px art drawn at an integer multiple. 3x is the largest that keeps a 7-wide board on
## the 640x360 viewport.
const SCALE := 3
const SRC := "res://assets/tiles"

func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var out: String = argv[0] if argv.size() > 0 else "res://screenshots/art_strip.png"

	# Two east-west straights that meet, then the same tile rotated so it cannot.
	var strip := ["channel_EW_wet", "channel_EW_wet", "channel_NS_dry"]

	var root_node := Node2D.new()
	root.add_child(root_node)

	var bg := ColorRect.new()
	# Deliberately NOT Dry Sand: the slab is Dry Sand, and on a matching backdrop the tile
	# silhouette disappears. A dark ground is what lets a reviewer see where a tile ends.
	bg.color = Color("2a2422")
	bg.size = Vector2(640, 360)
	root_node.add_child(bg)

	var origin := Vector2(128, 120)
	for i in strip.size():
		var path := "%s/%s.png" % [SRC, strip[i]]
		var img := Image.load_from_file(path)
		if img == null:
			print("could not load ", path)
			quit(1)
			return
		var sprite := Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(img)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = false
		sprite.scale = Vector2(SCALE, SCALE)
		sprite.position = origin + Vector2(i * 32 * SCALE, 0)
		root_node.add_child(sprite)

	var label := Label.new()
	label.text = "connected            connected            not connected"
	label.position = Vector2(128, 120 + 32 * SCALE + 12)
	label.add_theme_color_override("font_color", Color("f2d8a7"))
	root_node.add_child(label)

	for _i in 20:
		await process_frame
	await create_timer(0.3).timeout

	var shot := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	print("art preview -> %s : %s (%d tiles at %dx)" % [out, error_string(shot.save_png(out)), strip.size(), SCALE])
	quit(0)
