extends Node2D
## The app shell: map -> pool -> back to the map, and the one place the save is owned.
##
## scenes/main.tscn is instantiated as a CHILD here rather than being the main scene.
## tools/click_test.gd, tools/load_check.gd and tools/shot.gd all do
## `load("res://scenes/main.tscn").instantiate().get_node("Board")`, so rewriting that
## scene into a shell would break all three at once. Instead main.tscn stays exactly what
## it was -- a bare playable board -- and this scene wraps it.
##
## The board only behaves differently because `shell_mode` is set on it: clearing a pool
## hands control back here instead of walking on to the next level, and Escape backs out
## to the map instead of quitting. With the flag off, main.tscn is unchanged.

const TITLE_SCENE := preload("res://scenes/title.tscn")
const SETTINGS_SCENE := preload("res://scenes/settings.tscn")
const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const MAP_SCENE := preload("res://scenes/map.tscn")
const LEVEL_SCENE := preload("res://scenes/main.tscn")
const SaveDataScript := preload("res://scripts/systems/save_data.gd")

## Emitted just before the game closes. Exists so the last link of the Escape chain is
## testable: tools/shell_test.gd watches this instead of actually being terminated.
signal quit_requested()

## Injectable so tools/shell_test.gd can drive the whole shell against a temp save file
## without touching the player's real one.
var save: RefCounted

## Cleared by tools/shell_test.gd only. Escape on the title has to really end the game, and
## an assertion that ends the test process cannot report what it found -- so the suite turns
## the actual quit off and asserts on `quit_requested` instead. Always true in the game.
var quit_on_escape := true

var _title: Node = null
var _map: Node = null
var _level: Node = null
var _settings: Node = null


func _ready() -> void:
	if save == null:
		save = SaveDataScript.new()
		save.load_game()
	_apply_settings()
	show_title()


## Settings are applied on entry rather than only when changed, so a save carried from
## another machine opens the way the player left it.
func _apply_settings() -> void:
	SettingsPanel.apply_fullscreen(save.get_fullscreen())
	SettingsPanel.apply_volume(save.get_volume())


## Hidden is not enough on its own: a node that is invisible still receives unhandled
## input, so a click meant for the board would also land on the pool behind it.
func _set_active(node: Node, active: bool) -> void:
	if node == null:
		return
	node.visible = active
	node.set_process(active)
	node.set_process_unhandled_input(active)


func show_title() -> void:
	if _level != null:
		_level.queue_free()
		_level = null
	if _title == null:
		_title = TITLE_SCENE.instantiate()
		_title.play_requested.connect(show_map)
		_title.settings_requested.connect(show_settings)
		add_child(_title)
	_set_active(_title, true)
	_set_active(_map, false)


## Settings sits OVER the title rather than replacing it: it is a layer, not a place, which
## is why the panel dims what is behind instead of covering it. The title keeps drawing and
## stops taking input, so a click on the panel cannot also start the game.
func show_settings() -> void:
	if _settings == null:
		_settings = SETTINGS_SCENE.instantiate()
		_settings.save = save
		_settings.closed.connect(_close_settings)
		add_child(_settings)
	_title.set_process_unhandled_input(false)
	_set_active(_settings, true)


func _close_settings() -> void:
	if _settings != null:
		_settings.queue_free()
		_settings = null
	if _title != null:
		_title.set_process_unhandled_input(true)


func show_map() -> void:
	if _level != null:
		_level.queue_free()
		_level = null
	_set_active(_title, false)
	if _map == null:
		_map = MAP_SCENE.instantiate()
		_map.save = save
		_map.level_chosen.connect(_on_level_chosen)
		add_child(_map)
	_set_active(_map, true)
	# The map reads its pool states from the save every frame it draws, so returning from a
	# cleared pool needs nothing more than a redraw.
	_map.queue_redraw()


func _on_level_chosen(level_no: int) -> void:
	_set_active(_map, false)
	_level = LEVEL_SCENE.instantiate()
	add_child(_level)
	var board = _level.get_node("Board")
	board.shell_mode = true
	board.level_cleared.connect(_on_level_cleared)
	board.exit_requested.connect(show_map)
	_open(board, level_no)


## levels/ is sorted by filename and the ids run 1..28, so the index is level_no - 1.
## Checked rather than assumed: if a level is ever renamed or inserted, fall back to a scan
## so that picking pool 17 can never quietly open a different puzzle.
func _open(board, level_no: int) -> void:
	board.load_level(level_no - 1)
	if board.grid != null and board.grid.id == level_no:
		return
	for i in board.levels.size():
		board.load_level(i)
		if board.grid != null and board.grid.id == level_no:
			return
	push_warning("shell: no level with id %d" % level_no)


func _on_level_cleared(level_no: int, stars: int, _moves: int) -> void:
	save.record_clear(level_no, stars)
	# Written the moment it is earned, not on the way out: a crash or a force-quit during
	# the celebration must not take the stars back.
	save.save_game()


## Escape walks back out one screen at a time: pool -> map -> title -> quit. Inside a pool
## the board handles it and hands back here, so this only ever sees the map and the title.
func _unhandled_input(event: InputEvent) -> void:
	if _level != null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo
			and event.keycode == KEY_ESCAPE):
		return
	if _map != null and _map.visible:
		show_title()
		return
	quit_requested.emit()
	if quit_on_escape:
		get_tree().quit()
