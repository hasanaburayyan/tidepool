extends Node2D
## The ugly playable. Placeholder shapes drawn straight to the canvas: no sprites, no
## shaders, no art. Its whole job is to prove the core loop is a game you can click on,
## and to give the artist a working target to replace.
##
## All the rules live in scripts/core. This file only draws and takes input.
##
## The tide is a MOVE budget, not a clock (design doc §2.1): one rotation costs one unit,
## thinking is free, and running out is never a fail screen -- the tide comes back in.

## 64, not 72, so Cove's 32 px sprites land at exactly 2x. Pixel art at a fractional
## scale under a Nearest filter drops and doubles rows of pixels; 2x is the whole point.
## The largest board we ship is 7x6, so 7*64 + margins still fits the 960x640 viewport.
const TILE_SIZE := 64
const MARGIN := Vector2(40, 108)
const LEVEL_DIR := "res://levels"
## How long a newly wet tile flashes. Flow itself is an instant BFS recompute; only the
## set difference is animated, so the eye follows the water without the sim faking it.
const SPLASH_TIME := 0.28
## Seconds the water takes to cross one tile. Short on purpose: a cue about direction, not
## a cutscene -- the player may already be clicking again.
const STEP_TIME := 0.045

const SAND := Color("d9bf8f")
## A hovered tile lifts rather than being boxed. The board is meant to read as one
## slab of rock with channels cut into it -- that continuity is how a player sees at a
## glance that two channels are joined -- so a permanent grid would cost the thing it
## was meant to help. The boundary only has to exist at the moment you are about to
## turn something, which is exactly when the cursor is on it.
const HOVER := Color("e6cfa4")
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
## grid index -> seconds until the water reaches it. Display only: to the rules the tile is
## already in `wet`; it just has not been drawn filled yet.
var arriving: Dictionary = {}
var reset_button := Rect2()

@onready var _font: Font = ThemeDB.fallback_font


## Art the artist has landed, keyed "i_wet", "overlay_locked", "crab_rescued". Anything
## absent falls back to the placeholder shapes, so sprites can arrive ONE AT A TIME and be
## seen in the game the same day instead of waiting for a complete sheet.
## Naming and sizes are the contract in tidepool-engineering §9.
var art: Dictionary = {}
## One-ways currently turning water away, recomputed with the wet set. Display only.
var refusing: Dictionary = {}


const KIND_PREFIX := {
	Tile.Kind.CHANNEL: "channel",
	Tile.Kind.CRAB: "channel",
	Tile.Kind.SPONGE: "sponge",
	# A one-way's BASE is an ordinary channel; the arrow goes over it as an overlay.
	Tile.Kind.ONEWAY: "channel",
}


## The name of the sprite for this tile's exact orientation, e.g. "channel_nesw".
## Preferred over the base-shape name because a tileset that is lit from one direction
## cannot be rotated: a corner facing NE and the same corner facing SW want different
## shading. One file per orientation is the artist's call to make, not mine to force.
func _facing_key(tile: Tile) -> String:
	return "%s_%s" % [KIND_PREFIX.get(tile.kind, "channel"), _sides_key(tile)]


## The arrow drawn OVER a one-way's channel, keyed by the side water leaves through.
##
## It is an overlay rather than a whole tile because the two things a one-way is -- a
## shape and a direction -- vary independently. The format lets any mask carry an arrow,
## so baking them together is 28 (mask, exit) pairs and a new file every time a level
## uses a shape nobody anticipated. Level 14's `o3` already sits beside a tee. (Cove's
## call, and they were right.)
func _arrow_key(tile: Tile) -> String:
	return "oneway_%s" % Tile.DIR_NAMES[tile.out_dir].to_lower()


func _sides_key(tile: Tile) -> String:
	return tile.sides_key()


func _load_art() -> void:
	for dir_path in ["res://assets/tiles", "res://assets/critters"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name in dir.get_files():
			# Godot hands us "x.png.import" in an exported build; the resource is "x.png".
			var clean := file_name.trim_suffix(".import")
			if not clean.ends_with(".png"):
				continue
			var tex := load(dir_path.path_join(clean))
			if tex is Texture2D:
				art[clean.get_basename().to_lower()] = tex


## Draws a base-orientation sprite turned `turns` quarter-turns clockwise about its centre.
func _draw_sprite(tex: Texture2D, rect: Rect2, turns: int = 0) -> void:
	var size := Vector2(TILE_SIZE, TILE_SIZE)
	draw_set_transform(rect.get_center(), turns * TAU * 0.25, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ready() -> void:
	_load_art()
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
	arriving = {}
	tide_left = grid.tide
	wet = {}
	_recompute()


func _recompute() -> void:
	var before := wet
	wet = Flow.compute(grid)
	refusing = Flow.refusing(grid, wet)
	# Animate only the difference, and in route order: each newly-wet tile waits its distance
	# from the nearest newly-wet tile, so the eye follows the path the water actually took.
	var depth := Flow.distances(grid)
	var nearest := -1
	for idx in wet:
		if not before.has(idx):
			var d: int = depth.get(idx, 0)
			if nearest < 0 or d < nearest:
				nearest = d
	for idx in wet:
		if not before.has(idx):
			var delay: float = (int(depth.get(idx, 0)) - nearest) * STEP_TIME
			if delay > 0.0:
				arriving[idx] = delay
			else:
				splashes[idx] = SPLASH_TIME
	for i in Flow.rescued(grid, wet):
		rescued[i] = true
	# Sponges are not latched the way critters are: rotating one off the route wrings it
	# out and the level un-clears. A sponge you cannot route back to is a dead level, so
	# levels/ must never put one on the only path to a critter.
	if rescued.size() == grid.critters.size() and not grid.critters.is_empty() \
			and Flow.all_sponges_wet(grid, wet):
		cleared = true
	queue_redraw()


## How far over par still earns two stars. Named because it is a rule, not a number, and
## tools/audit_curve.py kept its own copy of it -- tools/dump_rules.gd now exports this one.
const STAR_2_MARGIN := 2


## 3 stars at or under par, 2 within par+2, 1 for solving it at all (design doc §2.4).
func stars() -> int:
	if moves <= grid.par:
		return 3
	return 2 if moves <= grid.par + STAR_2_MARGIN else 1


func _process(delta: float) -> void:
	if grid == null:
		return
	var dirty := false
	for idx in arriving.keys():
		arriving[idx] -= delta
		if arriving[idx] <= 0.0:
			arriving.erase(idx)
			splashes[idx] = SPLASH_TIME
		dirty = true
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

	if event is InputEventMouseMotion:
		var over := _tile_at(event.position)
		if over != hover:
			hover = over
			queue_redraw()
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


## The cell the cursor is over, or whatever _tile_at returns off-board. Hit-testing
## lives in _tile_at and nowhere else: hover and click must agree about which tile
## is under the pointer, and two copies of that arithmetic is how they stop agreeing.
var hover := Vector2i(-1, -1)


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
	# Wet to the rules the instant the BFS says so; wet on screen once the water has had time
	# to travel here. Only drawing reads this.
	var is_wet := wet.has(idx) and not arriving.has(idx)

	# Full bleed, no inset: the 2px gap drew a border around every cell and turned one
	# slab of rock into a grid of separate cards, which fights the thing the channel art
	# does on purpose -- an opening runs to the tile edge and fuses with its neighbour.
	draw_rect(rect, SAND)
	# Only a tile the player can actually turn lifts. Promising an affordance on a
	# barnacled tile, bare sand or a cross would be a lie, and a cross is a rotation
	# no-op the engine already excludes.
	if pos == hover and tile.can_rotate() and tile.rotation_period() > 1:
		draw_rect(rect, HOVER)
	if tile.kind == Tile.Kind.EMPTY:
		return

	# Art in this tile's exact orientation wins; a base-orientation image turned by the
	# engine is the fallback; the drawn placeholder is the fallback to that. Every level
	# stays playable no matter how much of the set exists.
	var state := "wet" if is_wet else "dry"

	# A barnacled tile is its own sprite, not a clean tile with a sticker on it: the crust
	# grows over the channel, so it cannot be composited after the fact.
	if tile.locked:
		var crust: Variant = art.get("locked_%s_%s" % [_sides_key(tile), state])
		if crust != null:
			_draw_sprite(crust, rect)
			# A barnacled one-way still has to show its arrow, or levels 16-18 lose the
			# one thing the player is reading.
			_draw_arrow_overlay(tile, rect, idx, state)
			return

	var sprite: Variant = art.get("%s_%s" % [_facing_key(tile), state])
	if sprite != null:
		_draw_sprite(sprite, rect)
		_draw_arrow_overlay(tile, rect, idx, state)
		_draw_locked_pips(tile, rect)
		return
	var shape_rot := tile.shape_rot()
	sprite = art.get("%s_%s" % [shape_rot[0], state])
	if sprite != null:
		_draw_sprite(sprite, rect, shape_rot[1])
		_draw_locked_pips(tile, rect)
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
			# Greyed while it is turning water away -- a placeholder for whatever
			# treatment Cove and Maren settle on, but never an invisible refusal.
			var arrow := LOCKED if refusing.has(idx) else (WATER_DEEP if is_wet else ROCK)
			_draw_arrow(centre, tile.out_dir, arrow)
		Tile.Kind.CRAB:
			draw_rect(Rect2(centre - Vector2(8, 8), Vector2(16, 16)), CRITTER)
		_:
			pass

	_draw_locked_pips(tile, rect)


## Refusing is a treatment on the arrow, not a fifth facing: same key, `_refused` suffix,
## falling back to the plain arrow until that art exists. It is load-bearing -- levels 14,
## 16, 17 and 18 are built on the player seeing an arrow turn water away -- and it is a
## steady state rather than a flash, so it has to stay legible while the player thinks.
func _draw_arrow_overlay(tile: Tile, rect: Rect2, idx: int, state: String) -> void:
	if tile.kind != Tile.Kind.ONEWAY:
		return
	var key := "%s_%s" % [_arrow_key(tile), state]
	var arrow: Variant = null
	if refusing.has(idx):
		arrow = art.get(key + "_refused")
	if arrow == null:
		arrow = art.get(key)
	if arrow != null:
		_draw_sprite(arrow, rect)


func _draw_locked_pips(tile: Tile, rect: Rect2) -> void:
	if not tile.locked:
		return
	var overlay: Variant = art.get("overlay_locked")
	if overlay != null:
		_draw_sprite(overlay, rect)
		return
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
	var state := "rescued" if rescued.has(i) else "stranded"
	var sprite: Variant = art.get("%s_%s" % [critter.get("type", "crab"), state])
	if sprite != null:
		_draw_sprite(sprite, rect)
		return
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
