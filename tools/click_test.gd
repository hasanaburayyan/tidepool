extends SceneTree
## Clicks the game the way a player does, through the real input stack, and fails if
## nothing rotates. Needs a real window -- Control hit-testing and viewport input do not
## exist headless, which is exactly why this bug reached the board.
##
##   godot --path . --script res://tools/click_test.gd -- [level ...]
##
## TIDE-19: a full-screen ColorRect background sat above the board with the default
## mouse_filter of STOP, so every click was consumed before `_unhandled_input` ran. Keys
## still worked, so the game looked alive and was not playable. `shot.gd` could not catch
## it because it calls `_try_rotate` directly; only a synthetic event pushed through
## `Input.parse_input_event` travels the same path a mouse does.
##
## Exit code is 1 if any level refuses a click, so this can gate an export.

##
## ON A FRESH CHECKOUT, IMPORT FIRST:
##   godot --headless --path . --import
## A `--script` run does not build the global class registry, and `scripts/core` refers to
## itself by `class_name`, so without it the project does not parse and the error points at
## whichever file happened to be read first. CI imports before every step, which is why this
## only bites a clean clone.
func _initialize() -> void:
	var argv := OS.get_cmdline_user_args()
	var levels: Array = []
	for a in argv:
		levels.append(int(a))
	if levels.is_empty():
		levels = [0, 4, 12, 18]  # levels 1, 5, 13 and 19: channel, channel, one-way, sponge

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var board = scene.get_node("Board")
	if board.get_script() == null:
		# A board.gd that does not parse loads as a bare Node2D. Without this the first
		# `board.levels` errors inside a coroutine, quit() is never reached, and the run hangs.
		print("FAIL the board script did not load -- look for a Parse Error above")
		quit(1)
		return
	for _i in 10:
		await process_frame

	var failures := 0
	for level in levels:
		if level >= board.levels.size():
			print("FAIL level index %d does not exist" % level)
			failures += 1
			continue
		board.load_level(level)
		for _i in 5:
			await process_frame

		var target: Variant = _first_rotatable(board)
		if target == null:
			print("FAIL %-16s has no rotatable tile to click" % board.grid.title)
			failures += 1
			continue

		var before: int = board.moves
		var before_mask: int = board.grid.at(target).mask
		await _click(board, target, MOUSE_BUTTON_LEFT)

		if board.moves == before:
			print("FAIL %-16s click at %s did not register" % [board.grid.title, target])
			failures += 1
		elif board.grid.at(target).mask == before_mask:
			print("FAIL %-16s click counted but the tile did not turn" % board.grid.title)
			failures += 1
		else:
			# And right-click has to turn it back the other way.
			var after_left: int = board.grid.at(target).mask
			await _click(board, target, MOUSE_BUTTON_RIGHT)
			if board.grid.at(target).mask == after_left:
				print("FAIL %-16s right-click did not turn the tile back" % board.grid.title)
				failures += 1
			else:
				print("ok   %-16s left-click rotates, right-click rotates back" % board.grid.title)

		# A barnacled tile must answer a click with a shake, and must not spend tide or turn.
		var crust: Variant = _first_locked(board)
		if crust != null:
			var idx: int = board.grid.index(crust)
			var tide_before: int = board.tide_left
			var moves_before: int = board.moves
			var mask_before: int = board.grid.at(crust).mask
			var shook := await _press_and_check(board, crust, idx)
			if not shook:
				print("FAIL %-16s click on barnacles at %s did not shake" % [board.grid.title, crust])
				failures += 1
			elif board.tide_left != tide_before or board.moves != moves_before \
					or board.grid.at(crust).mask != mask_before:
				print("FAIL %-16s click on barnacles spent tide or turned the tile" % board.grid.title)
				failures += 1
			else:
				print("ok   %-16s barnacled tile shakes, costs nothing" % board.grid.title)
		# The level's own solution, clicked for real from a fresh board, must rescue every
		# critter and schedule each one's rescue pop.
		board.restart()
		for step in board.solution:
			for _k in int(step["clicks"]):
				await _click(board, step["pos"], MOUSE_BUTTON_LEFT if int(step["turns"]) > 0 else MOUSE_BUTTON_RIGHT)
		var count: int = board.grid.critters.size()
		if board.rescued.size() != count:
			print("FAIL %-16s the solution clicked for real rescued %d/%d" % [board.grid.title, board.rescued.size(), count])
			failures += 1
		elif board.pop_at.size() != count:
			print("FAIL %-16s %d/%d rescued critters got a rescue pop" % [board.grid.title, board.pop_at.size(), count])
			failures += 1
		else:
			print("ok   %-16s solution clicked: %d/%d rescued, each pops" % [board.grid.title, count, count])

	print("")
	print("%d levels clicked, %d FAILED" % [levels.size(), failures])
	quit(1 if failures > 0 else 0)


## The first tile a player could actually turn, so the test never clicks solid rock.
func _first_rotatable(board) -> Variant:
	for y in board.grid.height:
		for x in board.grid.width:
			var pos := Vector2i(x, y)
			if board.grid.at(pos).can_rotate() and board.grid.at(pos).rotation_period() > 1:
				return pos
	return null


## The first barnacled tile that is not bare sand (mask 0), or null on a level without any.
func _first_locked(board) -> Variant:
	for y in board.grid.height:
		for x in board.grid.width:
			var pos := Vector2i(x, y)
			if board.grid.at(pos).locked and board.grid.at(pos).mask != 0:
				return pos
	return null


## Presses on a tile and reports whether it started shaking. Checked one frame after the press,
## not after the whole click: the shake is a quarter second and a slow CI frame could outlive it.
func _press_and_check(board, tile_pos: Vector2i, idx: int) -> bool:
	var rect: Rect2 = board._tile_rect(tile_pos)
	var shook := false
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = rect.get_center()
		event.global_position = event.position
		Input.parse_input_event(event)
		await process_frame
		if pressed:
			shook = board.shakes.has(idx)
	return shook


## Pushes a real mouse event at the centre of a tile: through the viewport, past any
## Control that might swallow it, and only then into the board.
func _click(board, tile_pos: Vector2i, button: int) -> void:
	var rect: Rect2 = board._tile_rect(tile_pos)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = rect.get_center()
		event.global_position = event.position
		Input.parse_input_event(event)
		await process_frame
	for _i in 3:
		await process_frame
