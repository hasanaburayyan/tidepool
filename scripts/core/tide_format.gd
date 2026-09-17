class_name TideFormat
extends RefCounted
## Reads the `.tide` level format (Game Director's spec, `tidepool-design` §4).
##
## A level is plain text a designer can write in any editor. Two characters per cell:
## a shape letter and a rotation digit, UPPERCASE for tiles the player may turn,
## lowercase for barnacled ones, `..` for solid rock. Coordinates are `r<row>c<col>`,
## 0-indexed, row 0 at the top.
##
## Rotation digits are clockwise steps from a base orientation, which means the format
## and `Tile.rotate_cw` share one definition of "turn" -- the parser literally rotates
## the base shape, so the two can never drift apart.

## Shape letter -> base connection mask. Bits are N=1, E=2, S=4, W=8.
const BASE_SHAPES := {
	"I": 0b0101,  # N,S
	"L": 0b0011,  # N,E
	"T": 0b0111,  # N,E,S
	"X": 0b1111,  # all four
	"E": 0b0001,  # N -- a cap, one opening
	"O": 0b0101,  # N,S -- one-way; the digit is the side water EXITS by
	"P": 0b0101,  # N,S -- sponge; drinks from either end, emits from neither
	"C": 0b0101,  # N,S -- crab tile; a plain straight until crab walking lands
}

## Shape letter -> tile kind. Anything not listed is an ordinary channel.
const SHAPE_KINDS := {
	"O": Tile.Kind.ONEWAY,
	"P": Tile.Kind.SPONGE,
	"C": Tile.Kind.CRAB,
}

const ROCK := ".."


## Always returns { "ok": bool, "errors": Array[String], "grid": Grid, "solution": Array }.
## Collects every problem instead of failing on the first, so a designer sees the whole
## list in one run.
static func parse(text: String, source_name: String = "<level>") -> Dictionary:
	var errors: Array[String] = []
	var fields := {}
	var blocks := {"grid": [], "critters": [], "solution": []}
	var current_block := ""

	for raw_line in text.split("\n"):
		var line := String(raw_line)
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue
		var indented := line.begins_with(" ") or line.begins_with("\t")
		if indented and current_block != "":
			blocks[current_block].append(stripped)
			continue
		var colon := stripped.find(":")
		if colon == -1:
			errors.append("%s: cannot read line %s" % [source_name, stripped])
			continue
		var key := stripped.substr(0, colon).strip_edges().to_lower()
		var value := stripped.substr(colon + 1).strip_edges()
		if blocks.has(key):
			current_block = key
			if not value.is_empty():
				errors.append("%s: \"%s:\" takes its entries on the following indented lines" % [
					source_name, key])
			continue
		current_block = ""
		fields[key] = value

	if blocks["grid"].is_empty():
		errors.append("%s: no \"grid:\" block" % source_name)
		return {"ok": false, "errors": errors, "grid": null, "solution": []}

	# Shape the grid, then check it against the declared size so a typo in either one
	# is caught rather than silently believed.
	var rows: Array = []
	for row_text in blocks["grid"]:
		rows.append(row_text.split(" ", false))
	var width: int = rows[0].size()
	for y in rows.size():
		if rows[y].size() != width:
			errors.append("%s: grid row %d has %d cells, expected %d" % [
				source_name, y, rows[y].size(), width])
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "grid": null, "solution": []}

	var grid := Grid.create(width, rows.size())
	grid.id = int(fields.get("id", "0"))
	grid.title = String(fields.get("name", ""))
	grid.par = int(fields.get("par", "0"))
	grid.tide = int(fields.get("tide", "0"))

	if fields.has("size"):
		var parts := String(fields["size"]).to_lower().split("x")
		if parts.size() != 2 or int(parts[0]) != width or int(parts[1]) != rows.size():
			errors.append("%s: size says %s but the grid is %dx%d (cols x rows)" % [
				source_name, fields["size"], width, rows.size()])

	for y in rows.size():
		for x in width:
			var cell := String(rows[y][x])
			var tile := _cell_to_tile(cell)
			if tile == null:
				errors.append("%s: r%dc%d: %s is not a tile" % [source_name, y, x, cell])
				continue
			grid.set_at(Vector2i(x, y), tile)

	for entry in blocks["critters"]:
		var parts := String(entry).split(" ", false)
		var pos := parse_coord(String(parts[0]))
		if not grid.in_bounds(pos):
			errors.append("%s: critter at %s is off the board" % [source_name, parts[0]])
			continue
		if grid.at(pos).kind == Tile.Kind.EMPTY:
			errors.append("%s: critter at %s is on rock, it can never get wet" % [source_name, parts[0]])
			continue
		grid.critters.append({"pos": pos, "type": String(parts[1]) if parts.size() > 1 else "starfish"})
	if grid.critters.is_empty():
		errors.append("%s: a level needs at least one critter to rescue" % source_name)

	var solution: Array[Dictionary] = []
	for entry in blocks["solution"]:
		var parts := String(entry).split(" ", false)
		var pos := parse_coord(String(parts[0]))
		if not grid.in_bounds(pos):
			errors.append("%s: solution step at %s is off the board" % [source_name, parts[0]])
			continue
		var move := String(parts[1]).to_lower() if parts.size() > 1 else "cw1"
		var turns := 0
		if move.begins_with("ccw"):
			turns = posmod(-int(move.substr(3)), 4)
		elif move.begins_with("cw"):
			turns = posmod(int(move.substr(2)), 4)
		else:
			errors.append("%s: solution step %s must be cwN or ccwN" % [source_name, entry])
			continue
		solution.append({"pos": pos, "turns": turns, "clicks": int(move.lstrip("cw"))})

	# The source. The format gives only a cell, because the tide can only come from
	# outside: the edge the cell sits on is the direction water arrives from.
	if not fields.has("source"):
		errors.append("%s: no \"source:\"" % source_name)
	else:
		var pos := parse_coord(String(fields["source"]))
		if not grid.in_bounds(pos):
			errors.append("%s: source at %s is off the board" % [source_name, fields["source"]])
		elif grid.at(pos).kind == Tile.Kind.EMPTY:
			errors.append("%s: source at %s is solid rock" % [source_name, fields["source"]])
		else:
			var from_dir := _edge_dir(grid, pos)
			if from_dir == -1:
				errors.append("%s: source at %s is not on an edge of the board" % [
					source_name, fields["source"]])
			else:
				grid.source_pos = pos
				grid.source_from = from_dir

	if not errors.is_empty():
		return {"ok": false, "errors": errors, "grid": null, "solution": []}
	return {"ok": true, "errors": errors, "grid": grid, "solution": solution}


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["%s: no such file" % path], "grid": null, "solution": []}
	return parse(FileAccess.get_file_as_string(path), path.get_file())


## "r2c13" -> Vector2i(13, 2). Vector2i(-1, -1) when it is not a coordinate.
static func parse_coord(text: String) -> Vector2i:
	var t := text.strip_edges().to_lower()
	if not t.begins_with("r"):
		return Vector2i(-1, -1)
	var c := t.find("c")
	if c == -1:
		return Vector2i(-1, -1)
	var row := t.substr(1, c - 1)
	var col := t.substr(c + 1)
	if not row.is_valid_int() or not col.is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(col), int(row))


static func coord_string(pos: Vector2i) -> String:
	return "r%dc%d" % [pos.y, pos.x]


## "L2" / "i1" / ".." -> a Tile, or null when the cell is not legal.
static func _cell_to_tile(cell: String) -> Tile:
	if cell == ROCK:
		return Tile.make(Tile.Kind.EMPTY, 0)
	if cell.length() != 2:
		return null
	var letter := cell[0]
	var locked := letter == letter.to_lower()
	var base: Variant = BASE_SHAPES.get(letter.to_upper())
	if base == null:
		return null
	var digit := cell[1]
	if not digit.is_valid_int():
		return null
	# A one-way starts with its arrow pointing N, so rotating it by the digit leaves
	# out_dir == digit: the digit is literally the side water leaves by.
	var kind: Tile.Kind = SHAPE_KINDS.get(letter.to_upper(), Tile.Kind.CHANNEL)
	var tile := Tile.make(kind, int(base), locked, Tile.N)
	tile.rotate_cw(int(digit))
	return tile


## Which outside edge does this cell touch? Corners prefer W, then N, then E, then S,
## which is only ever reached by a level that puts its source in a corner.
static func _edge_dir(grid: Grid, pos: Vector2i) -> int:
	if pos.x == 0:
		return Tile.W
	if pos.y == 0:
		return Tile.N
	if pos.x == grid.width - 1:
		return Tile.E
	if pos.y == grid.height - 1:
		return Tile.S
	return -1
