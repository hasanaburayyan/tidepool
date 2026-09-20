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
	# Escape on the title really does end the game, which would kill this suite mid-run and
	# leave it unable to report anything. The shell emits quit_requested either way, so the
	# assertion watches that and the actual quit is suppressed here and only here.
	app.quit_on_escape = false
	var quits := [0]
	app.quit_requested.connect(func(): quits[0] += 1)
	root.add_child(app)
	for _i in 10:
		await process_frame

	# --- the title screen comes first ---------------------------------------------------
	_ok(app._title != null and app._title.visible, "the shell opens on the title screen")
	_ok(app._map == null or not app._map.visible, "the map is not showing yet")
	_ok(app._level == null, "no pool is open yet")

	# --- Escape on the title leaves, it does not begin (Nerite, TIDE-49) -----------------
	# "Any key starts" swallowed Escape here, so the Escape chain lost its last link and the
	# only way out of the game was the window close button. I had asserted the whole chain
	# "pool -> map -> title -> quit" while only testing two of its three links; this is the
	# third, and it is checked BEFORE anything else so a later screen cannot mask it.
	await _key(KEY_ESCAPE)
	_ok(app._map == null or not app._map.visible, "Escape on the title does NOT start the game")
	_ok(app._title.visible, "the title is still showing after Escape")
	_eq(quits[0], 1, "Escape on the title asks to quit")

	# --- settings opens from the title, over it, and closes again -----------------------
	# The glyph must be hit-tested BEFORE "any click begins", or the click that lands on it
	# starts the game and settings is unreachable.
	await _click_at(app._title.SETTINGS_RECT.get_center())
	_ok(app._settings != null, "the settings glyph opens settings")
	_ok(app._map == null or not app._map.visible, "and does NOT start the game")

	if app._settings != null:
		var panel = app._settings
		# Volume is five drops, counted not measured. Clicking the third sets 3/5.
		await _click_at(panel._drops[2].get_center())
		_eq(snappedf(save.get_volume(), 0.01), 0.6, "clicking the third drop sets volume to 3/5")
		await _click_at(panel._speaker.get_center())
		_eq(save.get_volume(), 0.0, "the speaker glyph mutes")
		await _click_at(panel._drops[4].get_center())
		_eq(save.get_volume(), 1.0, "clicking the last drop sets full volume")

		# Written immediately, not on the way out: a settings screen that only persists when
		# you leave it loses the change to a force-quit.
		var vol_on_disk = SaveDataScript.new(save_path)
		vol_on_disk.load_game()
		_eq(vol_on_disk.get_volume(), 1.0, "the volume is already on disk before closing")

	# Escape closes settings and lands back on the title -- it must not fall through and
	# begin the game, and it must not quit.
	await _key(KEY_ESCAPE)
	_ok(app._settings == null, "Escape closes settings")
	_ok(app._title.visible, "and the title is showing")
	_ok(app._map == null or not app._map.visible, "and the game did not start")
	_eq(quits[0], 1, "and it did not ask to quit -- Escape closed the panel, nothing more")

	# Any click begins. Deliberately clicked on pool 1's centre: the title is dismissed by
	# this very click, so if it is not marked handled the event carries through to the map
	# underneath and opens a pool immediately.
	await _click_at(_centre(1))
	_ok(app._map != null and app._map.visible, "a click on the title opens the map")
	_ok(not app._title.visible, "the title screen is put away")
	_ok(app._level == null, "the click that left the title did NOT fall through into a pool")

	# --- the map on a fresh save ---------------------------------------------------------
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

	# --- the level-change keys must not walk past the unlock rule (Nerite, TIDE-48) -------
	# On the bare board N/P/arrows step between levels, which is a development shortcut. In
	# the shell that shortcut walks into a LOCKED pool, and clearing it records progress the
	# player never earned -- a save with pool 4 cleared and pool 3 not, which the unlock rule
	# says cannot exist. Only pool 1 is open right now, so any movement here is the bug.
	for key in [KEY_N, KEY_P, KEY_RIGHT, KEY_LEFT]:
		await _key(key)
		_eq(board.grid.id, 1, "key %d does not walk the shell off level 1" % key)
	_eq(app._level.get_node("Board"), board, "and the pool was never swapped out underneath")

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
	_ok(app._map.visible, "and the map is what is showing")

	# ...and again from the map back to the title, one screen at a time. If Escape ever
	# reached the quit branch with the map still up, the process would end here and the
	# remaining checks would simply never print.
	await _key(KEY_ESCAPE)
	_ok(app._title.visible, "Escape on the map returns to the title screen")
	_ok(not app._map.visible, "and the map is put away")

	# The last link, walked rather than assumed: from the title the next Escape ends the
	# game. Together with the two above, that is the whole chain actually exercised.
	await _key(KEY_ESCAPE)
	_eq(quits[0], 2, "Escape from the title again asks to quit -- the chain really ends in quit")
	_ok(app._map == null or not app._map.visible, "and it did not bounce back into the map")

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

	# The invariant the key bug broke, checked on the file rather than in memory: a save may
	# never contain a cleared pool whose predecessor is not cleared. However the player got
	# there, that state is unreachable by the rules, so finding it means something bypassed
	# the map.
	_eq(restarted.cleared_count(), 1, "exactly one pool is recorded cleared")
	for n in range(2, MapLayout.POOLS.size() + 1):
		if restarted.is_cleared(n):
			_ok(restarted.is_cleared(n - 1),
				"pool %d is cleared, so pool %d must be too" % [n, n - 1])

	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	print("")
	if failures == 0:
		print("shell: title -> map -> pool -> clear -> map -> title, 0 FAILED")
	else:
		print("shell: %d FAILED" % failures)
	quit(1 if failures > 0 else 0)
