extends Node2D
## The ugly playable. Placeholder shapes drawn straight to the canvas: no sprites, no
## shaders, no art. Its whole job is to prove the core loop is a game you can click on,
## and to give the artist a working target to replace.
##
## All the rules live in scripts/core. This file only draws and takes input.
##
## The tide is a MOVE budget, not a clock (design doc §2.1): one rotation costs one unit,
## thinking is free, and running out is never a fail screen -- the tide comes back in.

const TILE_SIZE := 72
const MARGIN := Vector2(40, 108)
const LEVEL_DIR := "res://levels"
## How long a newly wet tile flashes. Flow itself is an instant BFS recompute; only the
## set difference is animated, so the eye follows the water without the sim faking it.
const SPLASH_TIME := 0.28

const SAND := Color("d9bf8f")
const ROCK := Color("6b5b4a")
const WATER := Color("2e8b9a")
const WATER_DEEP := Color("1d5f6b")
const SPLASH := Color("9fe8f0")
const LOCKED := Color("8a6f5a")
const CRITTER := Color("e06a4a")
const CRITTER_SAFE := Color("f0c34a")
const TEXT := Color("3a2f26")
const BUTTON := Color("c2a878")

var levels: Array[String] = []
var grid: Grid
var wet: Dictionary = {}
var level_index := 0
var moves := 0
## Rotations left before the tide comes back in. An int, not a float: same currency as par.
var tide_left := 0
var cleared := false
## Latched, never recomputed from the wet set: once a critter is rescued it stays rescued
## even if a later rotation dries its tile (Maren, design doc §2.3).
var rescued: Dictionary = {}
## Counts down during the "tide comes back in" pause, then the level resets.
var resetting := 0.0
## grid index -> seconds of splash left, for tiles that just became wet.
var splashes: Dictionary = {}
var reset_button := Rect2()

@onready var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	levels = _find_levels()
	if levels.is_empty():
		push_error("no .tide levels found in %s" % LEVEL_DIR)
		return
	load_level(0)


## Every level in the folder, sorted by filename. Discovery rather than a hard-coded
## list so dropping a new .tide in from the Director needs no code change.
func _find_levels() -> Array[String]:
	var out: Array[String] = []
	for entry in DirAccess.get_files_at(LEVEL_DIR):
		var file := String(entry).trim_suffix(".remap")
		if file.ends_with(".tide"):
			out.append("%s/%s" % [LEVEL_DIR, file])
	out.sort()
	return out


func load_level(idx: int) -> void:
	level_index = posmod(idx, levels.size())
	restart()


## Also the free Reset Pool action: rereads the level from disk so the board really is
## the authored one again, and costs nothing (design doc §2.2 -- retrying is not punished).
func restart() -> void:
	var result := TideFormat.load_file(levels[level_index])
	if not result["ok"]:
		# A broken level is a build error, not something to paper over at runtime.
		for e in result["errors"]:
			push_error(e)
		grid = null
		queue_redraw()
		return
	grid = result["grid"]
	moves = 0
	cleared = false
	resetting = 0.0
	rescued = {}
	splashes = {}
	tide_left = grid.tide
	wet = {}
	_recompute()


func _recompute() -> void:
	var before := wet
	wet = Flow.compute(grid)
	# Animate only the difference: tiles that were dry a moment ago.
	for idx in wet:
		if not before.has(idx):
			splashes[idx] = SPLASH_TIME
	for i in Flow.rescued(grid, wet):
		rescued[i] = true
	if rescued.size() == grid.critters.size() and not grid.critters.is_empty():
		cleared = true
	queue_redraw()


## 3 stars at or under par, 2 within par+2, 1 for solving it at all (design doc §2.4).
func stars() -> int:
	if moves <= grid.par:
		return 3
	return 2 if moves <= grid.par + 2 else 1


func _process(delta: float) -> void:
	if grid == null:
		return
	var dirty := false
	for idx in splashes.keys():
		splashes[idx] -= delta
		if splashes[idx] <= 0.0:
			splashes.erase(idx)
		dirty = true
	if resetting > 0.0:
		resetting -= delta
		dirty = true
		if resetting <= 0.0:
			restart()
			return
	if dirty:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if grid == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				restart()
			KEY_RIGHT, KEY_N:
				load_level(level_index + 1)
			KEY_LEFT, KEY_P:
				load_level(level_index - 1)
			KEY_ESCAPE:
				get_tree().quit()
		return

	if not (event is InputEventMouseButton and event.pressed):
		return
	if reset_button.has_point(event.position):
		restart()
		return
	if cleared:
		# Clearing a level is the only thing that moves you on, and any click does it.
		load_level(level_index + 1)
		return
	if resetting > 0.0:
		return

	var turns := 0
	if event.button_index == MOUSE_BUTTON_LEFT:
		turns = 1
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		turns = 3  # counter-clockwise, and it costs the same one unit of tide
	else:
		return
	_try_rotate(_tile_at(event.position), turns)


## A rotation that changes nothing is free: barnacled tiles, bare sand and crosses all
## refuse, and a refused turn never costs the player tide.
func _try_rotate(pos: Vector2i, turns: int) -> void:
	var tile := grid.at(pos)
	if tile == null or not tile.can_rotate() or tile.rotation_period() <= 1:
		return
	if not grid.rotate_at(pos, turns):
		return
	moves += 1
	tide_left -= 1
	_recompute()
	if not cleared and tide_left <= 0:
		# Pillar one: the tide running out is never a fail screen. It comes back in.
		resetting = 1.4


func _tile_at(screen_pos: Vector2) -> Vector2i:
	var local := (screen_pos - MARGIN) / float(TILE_SIZE)
	return Vector2i(floori(local.x), floori(local.y))


func _tile_rect(pos: Vector2i) -> Rect2:
	return Rect2(MARGIN + Vector2(pos) * TILE_SIZE, Vector2.ONE * TILE_SIZE)


func _draw() -> void:
	if grid == null:
		draw_string(_font, Vector2(40, 60), "no level loaded (see stderr)", 0, -1, 20, TEXT)
		return

	for y in grid.height:
		for x in grid.width:
			_draw_tile(Vector2i(x, y))
	for i in grid.critters.size():
		_draw_critter(i)
	_draw_hud()


func _draw_tile(pos: Vector2i) -> void:
	var tile := grid.at(pos)
	var rect := _tile_rect(pos)
	var idx := grid.index(pos)
	var is_wet := wet.has(idx)

	draw_rect(rect.grow(-2), SAND)
	if tile.kind == Tile.Kind.EMPTY:
		return

	# The channel is a stub from the tile centre out to each open side, so the shape of
	# the pipe is readable at a glance. Pillar two: no hidden state.
	var centre := rect.get_center()
	var channel := WATER if is_wet else ROCK
	if splashes.has(idx):
		channel = channel.lerp(SPLASH, splashes[idx] / SPLASH_TIME)
	var width := 18.0
	draw_circle(centre, width * 0.5, channel)
	for dir in Tile.DIRS:
		if not tile.connects(dir):
			continue
		draw_line(centre, centre + Vector2(Tile.DIR_STEPS[dir]) * (TILE_SIZE * 0.5), channel, width)

	match tile.kind:
		Tile.Kind.SPONGE:
			# A ring: water gets in and stops there.
			draw_arc(centre, 22.0, 0.0, TAU, 24, WATER_DEEP if is_wet else ROCK, 4.0)
		Tile.Kind.ONEWAY:
			_draw_arrow(centre, tile.out_dir, WATER_DEEP if is_wet else ROCK)
		Tile.Kind.CRAB:
			draw_rect(Rect2(centre - Vector2(8, 8), Vector2(16, 16)), CRITTER)
		_:
			pass

	if tile.locked:
		# Barnacles: corner pips so locked tiles read as "do not bother".
		draw_circle(rect.position + Vector2(10, 10), 5.0, LOCKED)
		draw_circle(rect.end - Vector2(10, 10), 5.0, LOCKED)


func _draw_arrow(centre: Vector2, dir: int, colour: Color) -> void:
	var step := Vector2(Tile.DIR_STEPS[dir])
	var tip := centre + step * 22.0
	var side := step.orthogonal() * 9.0
	draw_colored_polygon([tip, centre + side, centre - side], colour)


func _draw_critter(i: int) -> void:
	var critter: Dictionary = grid.critters[i]
	var rect := _tile_rect(critter["pos"])
	draw_circle(rect.get_center(), 14.0, CRITTER_SAFE if rescued.has(i) else CRITTER)
	var label: String = String(critter["type"]).substr(0, 1).to_upper()
	draw_string(_font, rect.get_center() + Vector2(-5, 5), label, 0, -1, 14, TEXT)


func _draw_hud() -> void:
	var board_bottom: float = MARGIN.y + grid.height * TILE_SIZE
	var bar_width: float = maxf(grid.width * TILE_SIZE, 300.0)

	var header := "%d. %s   moves %d / par %d   rescued %d/%d" % [
		grid.id, grid.title, moves, grid.par, rescued.size(), grid.critters.size()]
	draw_string(_font, Vector2(MARGIN.x, 34), header, 0, -1, 18, TEXT)

	# Tide bar, drawn as one notch per remaining rotation: the budget is countable, so
	# the player can plan the last two moves instead of guessing at a shrinking bar.
	var bar := Rect2(MARGIN.x, 52, bar_width, 20)
	draw_rect(bar, SAND)
	if grid.tide > 0:
		var notch: float = bar.size.x / float(grid.tide)
		for i in tide_left:
			draw_rect(Rect2(bar.position + Vector2(i * notch + 1.0, 0), Vector2(notch - 2.0, 20)), WATER)
	draw_string(_font, Vector2(MARGIN.x + bar_width + 12, 70), "tide %d" % tide_left, 0, -1, 16, TEXT)

	reset_button = Rect2(MARGIN.x, 80, 110, 22)
	draw_rect(reset_button, BUTTON)
	draw_string(_font, reset_button.position + Vector2(10, 17), "Reset Pool", 0, -1, 15, TEXT)

	var status := ""
	if cleared:
		status = "LEVEL CLEAR - %d moves, par %d, %d stars - click for the next pool" % [
			moves, grid.par, stars()]
	elif resetting > 0.0:
		status = "the tide comes back in..."
	else:
		status = "left-click turns, right-click turns back   -   Reset Pool is free, N/P level, Esc quit"
	draw_string(_font, Vector2(MARGIN.x, board_bottom + 32), status, 0, -1, 17, TEXT)
