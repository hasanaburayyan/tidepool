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

const SaveDataScript := preload("res://scripts/systems/save_data.gd")
const ART_DIR := "res://assets/map"

## How much brighter the water goes under the cursor. Maren asked for "the water in it
## brightens", no bounce and no snap, so this is a flat tint and not a scale.
const HOVER_TINT := Color(1.12, 1.12, 1.12)

## A locked pool answers a click by shaking, the same vocabulary board.gd uses for
## barnacles: silence reads as a dropped click.
const SHAKE_TIME := 0.25
const SHAKE_PIXELS := 3.0

var save: RefCounted

var _art: Dictionary = {}
var _hover := 0
var _shake_level := 0
var _shake_left := 0.0


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
	var level := level_at(event.position)
	if level == 0:
		return
	if state_of(level) == "locked":
		_shake_level = level
		_shake_left = SHAKE_TIME
		queue_redraw()
		return
	level_chosen.emit(level)


func _process(delta: float) -> void:
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
