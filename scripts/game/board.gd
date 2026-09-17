extends Node2D
## The ugly playable. Placeholder shapes drawn straight to the canvas: no sprites, no
## shaders, no animation. Its whole job is to prove the core loop is a game you can
## click on, and to give the artist a working target to replace.
##
## All the rules live in scripts/core. This file only draws and takes input.

const TILE_SIZE := 72
const MARGIN := Vector2(40, 96)
const LEVELS := [
	"res://levels/debug_01.json",
	"res://levels/debug_02.json",
	"res://levels/debug_03.json",
	"res://levels/debug_04.json",
	"res://levels/debug_05.json",
]

const SAND := Color("d9bf8f")
const ROCK := Color("6b5b4a")
const WATER := Color("2e8b9a")
const WATER_DEEP := Color("1d5f6b")
const LOCKED := Color("8a6f5a")
const CRITTER := Color("e06a4a")
const CRITTER_SAFE := Color("f0c34a")
const TEXT := Color("3a2f26")

var grid: Grid
var wet: Dictionary = {}
var level_index := 0
var moves := 0
var tide_left := 0.0
var cleared := false
## Counts up during the "tide comes back in" pause, then the level resets.
var resetting := 0.0

@onready var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	load_level(0)


func load_level(idx: int) -> void:
	level_index = posmod(idx, LEVELS.size())
	var result := LevelIO.load_file(LEVELS[level_index])
	if not result["ok"]:
		# A broken level is a build error, not something to paper over at runtime.
		for e in result["errors"]:
			push_error(e)
		return
	grid = result["grid"]
	restart()


func restart() -> void:
	moves = 0
	cleared = false
	resetting = 0.0
	tide_left = grid.tide
	# Reload from disk so the soft reset really is the authored board again.
	var result := LevelIO.load_file(LEVELS[level_index])
	if result["ok"]:
		grid = result["grid"]
	_recompute()


func _recompute() -> void:
	wet = Flow.compute(grid)
	if Flow.all_rescued(grid, wet):
		cleared = true
	queue_redraw()


func _process(delta: float) -> void:
	if grid == null:
		return
	if resetting > 0.0:
		resetting -= delta
		if resetting <= 0.0:
			restart()
		else:
			queue_redraw()
		return
	if cleared:
		return

	tide_left -= delta
	if tide_left <= 0.0:
		# Pillar one: the tide running out is never a fail screen. It comes back in.
		tide_left = 0.0
		resetting = 1.5
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

	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if cleared or resetting > 0.0:
			return
		var pos := _tile_at(event.position)
		# rotate_at refuses barnacled tiles and bare sand, and a refused turn is
		# not a move, so a misclick never costs the player anything.
		if grid.rotate_at(pos):
			moves += 1
			_recompute()


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
	for c in grid.critters:
		_draw_critter(c)
	_draw_hud()


func _draw_tile(pos: Vector2i) -> void:
	var tile := grid.at(pos)
	var rect := _tile_rect(pos)
	var is_wet := wet.has(grid.index(pos))

	draw_rect(rect.grow(-2), SAND)
	if tile.kind == Tile.Kind.EMPTY:
		return

	# The channel is a stub from the tile centre out to each open side, so the shape
	# of the pipe is readable at a glance. Pillar two: no hidden state.
	var centre := rect.get_center()
	var channel := WATER if is_wet else ROCK
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
		# Barnacles: a corner pip so locked tiles read as "do not bother".
		draw_circle(rect.position + Vector2(10, 10), 5.0, LOCKED)
		draw_circle(rect.end - Vector2(10, 10), 5.0, LOCKED)


func _draw_arrow(centre: Vector2, dir: int, colour: Color) -> void:
	var step := Vector2(Tile.DIR_STEPS[dir])
	var tip := centre + step * 22.0
	var side := step.orthogonal() * 9.0
	draw_colored_polygon([tip, centre + side, centre - side], colour)


func _draw_critter(critter: Dictionary) -> void:
	var rect := _tile_rect(critter["pos"])
	var safe: bool = wet.has(grid.index(critter["pos"]))
	draw_circle(rect.get_center(), 14.0, CRITTER_SAFE if safe else CRITTER)
	var label: String = String(critter["type"]).substr(0, 1).to_upper()
	draw_string(_font, rect.get_center() + Vector2(-5, 5), label, 0, -1, 14, TEXT)


func _draw_hud() -> void:
	var board_bottom: float = MARGIN.y + grid.height * TILE_SIZE

	# Tide bar. Draining, not counting down: it is a tide, not a clock.
	var bar := Rect2(MARGIN.x, 48, grid.width * TILE_SIZE, 20)
	draw_rect(bar, SAND)
	var fraction: float = tide_left / grid.tide if grid.tide > 0.0 else 0.0
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), WATER)

	var rescued := Flow.rescued(grid, wet).size()
	var header := "%d. %s   moves %d / par %d   rescued %d/%d" % [
		grid.id, grid.title, moves, grid.par, rescued, grid.critters.size()]
	draw_string(_font, Vector2(MARGIN.x, 32), header, 0, -1, 18, TEXT)

	var status := ""
	if cleared:
		status = "LEVEL CLEAR in %d moves (par %d) - N for next" % [moves, grid.par]
	elif resetting > 0.0:
		status = "the tide comes back in..."
	else:
		status = "click a tile to rotate   -   R reset, N/P level, Esc quit"
	draw_string(_font, Vector2(MARGIN.x, board_bottom + 32), status, 0, -1, 18, TEXT)
