extends SceneTree
## Drives the whole app shell with real clicks: map -> pool -> clear -> back to the map,
## and proves the stars reached the disk.
##
##   godot --path . --audio-driver Dummy --script res://tools/shell_test.gd
##
## NOT --headless. Like tools/click_test.gd, this clicks the game the way a player does and
## the headless display server never delivers input events -- every click would silently do
## nothing and every check here would fail for the wrong reason. CI runs it under xvfb.
##
## The unit suites cover the save rules and the map's pure logic. What they cannot cover is
## the wiring: that picking a pool opens *that* puzzle, that clearing it writes stars that
## survive a restart, and that a locked pool refuses. That is all this file.

const SaveDataScript := preload("res://scripts/systems/save_data.gd")

var failures := 0
var _emits := 0


func _ok(condition: bool, what: String) -> void:
	if condition:
		print("ok   %s" % what)
	else:
		print("FAIL %s" % what)
		failures += 1


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_ok(actual == expected, "%s (expected %s, got %s)" % [what, expected, actual])


## A click at an arbitrary screen point, pressed and released, the way the map receives one.
func _click_at(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		await process_frame
	for _i in 3:
		await process_frame


func _key(keycode: int) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	for _i in 3:
		await process_frame


func _centre(level_no: int) -> Vector2:
	for entry in MapLayout.POOLS:
		if int(entry["level"]) == level_no:
			return Vector2(int(entry["x"]), int(entry["y"]))
	return Vector2.ZERO


func _initialize() -> void:
	var save_path := "user://shell_test_%d.json" % Time.get_ticks_usec()
	var save = SaveDataScript.new(save_path)

	var app: Node = load("res://scenes/app.tscn").instantiate()
	app.save = save
	root.add_child(app)
	for _i in 10:
		await process_frame

	# --- the map opens on a fresh save -------------------------------------------------
	_ok(app._map != null, "the shell opens on the map")
	_ok(app._level == null, "no pool is open yet")
	_eq(app._map.state_of(1), "open", "pool 1 is open on a fresh save")
	_eq(app._map.state_of(2), "locked", "pool 2 is locked on a fresh save")

	# --- a locked pool refuses ---------------------------------------------------------
	await _click_at(_centre(2))
	_ok(app._level == null, "clicking a locked pool does not open it")

	# --- opening pool 1 ----------------------------------------------------------------
	await _click_at(_centre(1))
	_ok(app._level != null, "clicking pool 1 opens a pool")
	if app._level == null:
		print("\n%d FAILED" % failures)
		quit(1)
		return
	var board = app._level.get_node("Board")
	_eq(board.grid.id, 1, "the pool that opened is level 1, not some other index")
	_ok(board.shell_mode, "the board is in shell mode")

	# Marlow's constraint: emitted once, on the transition, not on the latched value.
	board.level_cleared.connect(func(_l, _s, _m): _emits += 1)

	# --- clear it with its own solution, clicked for real -------------------------------
	for step in board.solution:
		for _k in int(step["clicks"]):
			if board.cleared:
				break
			await _click_at(board._tile_rect(step["pos"]).get_center(),
				MOUSE_BUTTON_RIGHT if step.get("ccw", false) else MOUSE_BUTTON_LEFT)
	_ok(board.cleared, "the solution clicked for real clears the pool")
	_eq(_emits, 1, "level_cleared fired exactly once")

	var stars: int = board.stars()
	_ok(stars >= 1, "clearing it is worth at least one shell")

	# --- the stars are on disk before the player goes anywhere --------------------------
	var on_disk = SaveDataScript.new(save_path)
	_ok(on_disk.load_game(), "a save file exists the moment the pool is cleared")
	_eq(on_disk.stars_for(1), stars, "the stars on disk match what was earned")
	_ok(on_disk.is_unlocked(2), "pool 2 is unlocked on disk")

	# Rotating after the clear must not re-emit: `cleared` latches.
	for step in board.solution:
		await _click_at(board._tile_rect(step["pos"]).get_center())
		break
	_eq(_emits, 1, "a rotation after the clear does not fire level_cleared again")

	# --- back to the map ----------------------------------------------------------------
	# The post-wave click is what leaves; before the wave has washed through it is ignored,
	# so the click that cleared the pool cannot double into a skip.
	await create_timer(board.WIPE_TIME + 0.2).timeout
	# Deliberately clicked ON pool 2's centre: the board is freed by this very click, so if
	# it is not marked handled the event carries on to the map that just came back and opens
	# pool 2 immediately. Landing back on the map is the check; staying there is the point.
	await _click_at(_centre(2))
	_ok(app._level == null, "the post-wave click returns to the map and does NOT fall through"
		+ " and open the pool underneath it")
	_ok(app._map.visible, "the map is showing again")
	_eq(app._map.state_of(1), "done", "pool 1 now reads as completed")
	_eq(app._map.state_of(2), "open", "pool 2 is now open")

	# --- the unlock actually opens the next pool -----------------------------------------
	await _click_at(_centre(2))
	_ok(app._level != null, "pool 2 can now be opened")
	if app._level != null:
		_eq(app._level.get_node("Board").grid.id, 2, "and it really is level 2")

	# Escape backs out rather than quitting the game.
	await _key(KEY_ESCAPE)
	_ok(app._level == null, "Escape inside a pool returns to the map")

	# --- restart persistence (Nerite's check) --------------------------------------------
	# Save twice over an existing file, then read it back cold: this is the DirAccess.rename
	# -onto-an-existing-file path, which is the one unverified on Windows.
	_ok(save.save_game(), "a second save over the existing file succeeds")
	var restarted = SaveDataScript.new(save_path)
	_ok(restarted.load_game(), "the save reloads cold, as if the game had been restarted")
	_eq(restarted.stars_for(1), stars, "pool 1's stars survive a restart")
	_ok(restarted.is_unlocked(2), "pool 2 is still unlocked after a restart")
	_ok(not FileAccess.file_exists(save_path + SaveDataScript.TMP_SUFFIX),
		"no temp file is left behind")

	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	print("")
	if failures == 0:
		print("shell: map -> pool -> clear -> map, 0 FAILED")
	else:
		print("shell: %d FAILED" % failures)
	quit(1 if failures > 0 else 0)
