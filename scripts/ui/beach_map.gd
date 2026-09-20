extends Node2D
## The beach map: 28 pools on one screen, the tide going out from top to bottom.
##
## Draws only. It owns no progress of its own -- every pool's state is read from SaveData,
## which is where the unlock and star rules live. Ask it to render a different save and it
## renders a different map; that is what makes the states screenshot-testable without
## playing twenty-four levels first.
##
## Positions come from the BAKED layout (scripts/ui/map_layout.gd), never from the .json:
## see tools/bake_layout.gd for why.

## Emitted when the player picks a pool that is actually open. A locked pool is answered
## with a shake rather than silently ignored, and never reaches this signal.
signal level_chosen(level_no: int)

## The top-right settings glyph, same one the title and the board carry.
signal settings_requested()

const SaveDataScript := preload("res://scripts/systems/save_data.gd")
const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const SETTINGS_RECT := SettingsPanel.SETTINGS_RECT

## Dry Sand with an ink rim, so the glyph reads against sand or water alike.
const GLYPH := Color("d9bf8f")
const INK := Color("3a2f26")
const ART_DIR := "res://assets/map"

## How much brighter the water goes under the cursor. Maren asked for "the water in it
## brightens", no bounce and no snap, so this is a flat tint and not a scale.
const HOVER_TINT := Color(1.12, 1.12, 1.12)

## The ripple colour, matching the splash the board uses when water arrives.
const SPLASH := Color("9fe8f0")

## A locked pool answers a click by shaking, the same vocabulary board.gd uses for
## barnacles: silence reads as a dropped click.
const SHAKE_TIME := 0.25
const SHAKE_PIXELS := 3.0

## The level-clear moment (tidepool-beach-map, confirmed by Maren): coming back from a
## cleared pool, its shells fill ONE AT A TIME about 0.2s apart, and then the next pool
## unlocks with a small ripple. It is the only thing on this screen that asks for attention,
## and it is a reward rather than a transition -- so nothing else animates while it runs.
const SHELL_STEP := 0.2
const RIPPLE_TIME := 0.9
const RIPPLE_RADIUS := 46.0

var save: RefCounted

var _art: Dictionary = {}
var _hover := 0
var _shake_level := 0
var _shake_left := 0.0

## The pool whose shells are filling, and how long the celebration has been running. -1.0
## means nothing is celebrating.
var _celebrate_level := 0
var _celebrate_t := -1.0


func _ready() -> void:
	_load_art()
	if save == null:
		save = SaveDataScript.new()
		save.load_game()
	queue_redraw()


func _load_art() -> void:
	var names := ["beach", "pool_locked", "pool_open", "pool_done", "shell_empty", "shell_filled"]
	for i in 10:
		names.append("digit_%d" % i)
	for n in names:
		var path := "%s/%s.png" % [ART_DIR, n]
		if ResourceLoader.exists(path):
			_art[n] = load(path)
		else:
			push_warning("map: missing art %s" % path)


# --- state ----------------------------------------------------------------------------

## One of "locked", "open", "done" -- the three states in tidepool-beach-map, and the
## three pool sprites Cove drew. The load-bearing difference is water versus no water.
func state_of(level_no: int) -> String:
	if not save.is_unlocked(level_no):
		return "locked"
	return "done" if save.is_cleared(level_no) else "open"


func _pool_rect(entry: Dictionary) -> Rect2:
	var p: Array = entry["pool"]
	return Rect2(Vector2(int(p[0]), int(p[1])), Vector2(MapLayout.POOL_SIZE))


## The pool under a point, or 0. The whole pool sprite is the click target: the pools are
## irregular and far apart, so a generous rectangle never steals a neighbour's click.
func level_at(point: Vector2) -> int:
	for entry in MapLayout.POOLS:
		if _pool_rect(entry).has_point(point):
			return int(entry["level"])
	return 0


# --- input ----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over := level_at(event.position)
		if over != _hover:
			_hover = over
			queue_redraw()
		return

	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Checked before the pools, for the same reason the title checks it before "any click
	# begins": otherwise a pool sitting under the glyph would swallow it.
	if SETTINGS_RECT.has_point(event.position):
		settings_requested.emit()
		get_viewport().set_input_as_handled()
		return
	var level := level_at(event.position)
	if level == 0:
		return
	if state_of(level) == "locked":
		_shake_level = level
		_shake_left = SHAKE_TIME
		queue_redraw()
		return
	level_chosen.emit(level)


## Called by the shell when the player comes back from a pool they just cleared. The map
## does not decide when this happens -- it cannot know, since it reads a save that was
## already written -- so the shell tells it.
func celebrate(level_no: int) -> void:
	_celebrate_level = level_no
	_celebrate_t = 0.0
	queue_redraw()


## Shells first, then the ripple on the pool that just unlocked.
func _shells_done() -> float:
	return float(save.stars_for(_celebrate_level)) * SHELL_STEP


func _celebrating() -> bool:
	return _celebrate_t >= 0.0


func _process(delta: float) -> void:
	if _celebrating():
		_celebrate_t += delta
		if _celebrate_t > _shells_done() + RIPPLE_TIME:
			_celebrate_t = -1.0
			_celebrate_level = 0
		queue_redraw()
	if _shake_left > 0.0:
		_shake_left -= delta
		if _shake_left <= 0.0:
			_shake_level = 0
		queue_redraw()


# --- drawing --------------------------------------------------------------------------

func _draw() -> void:
	if _art.has("beach"):
		draw_texture(_art["beach"], Vector2.ZERO)
	for entry in MapLayout.POOLS:
		_draw_pool(entry)
	_draw_ripple()
	SettingsPanel.draw_glyph(self, Rect2(SETTINGS_RECT.position + Vector2.ONE,
		SETTINGS_RECT.size), INK)
	SettingsPanel.draw_glyph(self, SETTINGS_RECT, GLYPH)


## A ring opening outward on the pool that just unlocked, once its predecessor's shells have
## finished. Drawn over everything so it reads even where pools sit close together.
func _draw_ripple() -> void:
	if not _celebrating():
		return
	var t := _celebrate_t - _shells_done()
	if t < 0.0:
		return
	var next := _celebrate_level + 1
	var centre := Vector2.ZERO
	for entry in MapLayout.POOLS:
		if int(entry["level"]) == next:
			centre = Vector2(int(entry["x"]), int(entry["y"]))
	if centre == Vector2.ZERO:
		return
	var k := clampf(t / RIPPLE_TIME, 0.0, 1.0)
	# Fades as it grows, so it ends by disappearing rather than by being switched off.
	draw_arc(centre, RIPPLE_RADIUS * k, 0.0, TAU, 48,
		Color(SPLASH.r, SPLASH.g, SPLASH.b, 1.0 - k), 3.0)


func _draw_pool(entry: Dictionary) -> void:
	var level := int(entry["level"])
	var state := state_of(level)
	var offset := Vector2.ZERO
	if level == _shake_level and _shake_left > 0.0:
		# A quick horizontal rattle, damped out over SHAKE_TIME.
		offset.x = sin(_shake_left * 60.0) * SHAKE_PIXELS * (_shake_left / SHAKE_TIME)

	var tint := HOVER_TINT if level == _hover and state != "locked" else Color.WHITE
	var pool_tex: Texture2D = _art.get("pool_%s" % state)
	if pool_tex != null:
		draw_texture(pool_tex, _pool_rect(entry).position + offset, tint)

	# A locked pool has no rim shells at all (tidepool-beach-map): dry rock, nothing on it.
	# The shells only ever say how you did, never what you could win.
	if state != "locked":
		var earned := int(save.stars_for(level))
		# During the celebration the cleared pool's shells arrive one at a time. Every other
		# pool draws its full count, so the eye has only one thing to follow.
		if _celebrating() and level == _celebrate_level:
			earned = mini(earned, int(floorf(_celebrate_t / SHELL_STEP)))
		for i in (entry["shells"] as Array).size():
			var s: Array = entry["shells"][i]
			var key := "shell_filled" if i < earned else "shell_empty"
			if _art.has(key):
				draw_texture(_art[key], Vector2(int(s[0]), int(s[1])) + offset)

	for i in (entry["digits"] as Array).size():
		var d: Array = entry["digits"][i]
		var digit := str(level)[i]
		var key := "digit_%s" % digit
		if _art.has(key):
			draw_texture(_art[key], Vector2(int(d[0]), int(d[1])) + offset)
