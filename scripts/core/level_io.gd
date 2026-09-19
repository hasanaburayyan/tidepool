class_name LevelIO
extends RefCounted
## Loads a level from JSON into a Grid, and writes one back out.
##
## The grid itself is ASCII art, one character per tile, so a level is readable and
## editable in any text editor without a tool. Everything that is not a shape --
## barnacles, one-way arrows, sponges, critters -- is listed separately by position,
## which keeps the art one character wide and the modifiers explicit.

## Shape character -> connection mask. Bits are N=1, E=2, S=4, W=8.
## The corner and tee glyphs are chosen to look like the pipe they draw.
const SHAPES := {
	".": 0,   # sand, no channel
	"-": 10,  # E W
	"|": 5,   # N S
	"L": 3,   # N E
	"J": 9,   # N W
	"7": 12,  # S W
	"F": 6,   # S E
	">": 7,   # N E S
	"<": 13,  # N S W
	"T": 14,  # E S W
	"t": 11,  # N E W
	"+": 15,  # all four
}


## Parse a level. Always returns { "ok": bool, "errors": Array[String], "grid": Grid }.
## Never pushes errors or asserts: the validator and the loader both want to collect
## every problem in a level and print them together.
static func parse(data: Variant, source_name: String = "<level>") -> Dictionary:
	var errors: Array[String] = []
	var fail := func() -> Dictionary:
		return {"ok": false, "errors": errors, "grid": null}

	if typeof(data) != TYPE_DICTIONARY:
		errors.append("%s: top level must be a JSON object" % source_name)
		return fail.call()

	var rows: Array = data.get("grid", [])
	if rows.is_empty():
		errors.append("%s: \"grid\" is missing or empty" % source_name)
		return fail.call()

	var width: int = String(rows[0]).length()
	for y in rows.size():
		if String(rows[y]).length() != width:
			errors.append("%s: grid row %d is %d chars, expected %d" % [
				source_name, y, String(rows[y]).length(), width])
	if not errors.is_empty():
		return fail.call()

	var grid := Grid.create(width, rows.size())
	grid.id = int(data.get("id", 0))
	grid.title = String(data.get("title", ""))
	grid.par = int(data.get("par", 0))
	grid.tide = int(data.get("tide", 30))

	for y in rows.size():
		var row := String(rows[y])
		for x in width:
			var ch := row[x]
			if not SHAPES.has(ch):
				errors.append("%s: unknown tile character %s at (%d, %d)" % [source_name, ch, x, y])
				continue
			var mask: int = SHAPES[ch]
			var kind := Tile.Kind.EMPTY if mask == 0 else Tile.Kind.CHANNEL
			grid.set_at(Vector2i(x, y), Tile.make(kind, mask))

	# Modifiers, applied on top of the shapes.
	for entry in data.get("locked", []):
		var pos := _to_pos(entry)
		if not _check_pos(grid, pos, "locked", source_name, errors):
			continue
		grid.at(pos).locked = true

	for entry in data.get("sponges", []):
		var pos := _to_pos(entry)
		if not _check_pos(grid, pos, "sponge", source_name, errors):
			continue
		grid.at(pos).kind = Tile.Kind.SPONGE

	for entry in data.get("basins", []):
		var pos := _to_pos(entry)
		if not _check_pos(grid, pos, "basin", source_name, errors):
			continue
		if grid.at(pos).mask != 0b1111:
			errors.append("%s: basin at %s must be a four-way cell" % [source_name, pos])
			continue
		grid.at(pos).kind = Tile.Kind.BASIN

	for entry in data.get("oneway", []):
		var pos := _to_pos(entry.get("pos", []))
		if not _check_pos(grid, pos, "oneway", source_name, errors):
			continue
		var out_dir := Tile.dir_from_name(String(entry.get("out", "")))
		if out_dir == -1:
			errors.append("%s: oneway at (%d, %d) needs \"out\" of N/E/S/W" % [source_name, pos.x, pos.y])
			continue
		var tile := grid.at(pos)
		if not tile.connects(out_dir):
			errors.append("%s: oneway at (%d, %d) points %s but has no opening there" % [
				source_name, pos.x, pos.y, Tile.DIR_NAMES[out_dir]])
			continue
		tile.kind = Tile.Kind.ONEWAY
		tile.out_dir = out_dir

	for entry in data.get("critters", []):
		var pos := _to_pos(entry.get("pos", []))
		if not _check_pos(grid, pos, "critter", source_name, errors):
			continue
		if grid.at(pos).kind == Tile.Kind.EMPTY:
			errors.append("%s: critter at (%d, %d) is standing on sand, it can never get wet" % [
				source_name, pos.x, pos.y])
			continue
		grid.critters.append({"pos": pos, "type": String(entry.get("type", "crab"))})
	if grid.critters.is_empty():
		errors.append("%s: a level needs at least one critter to rescue" % source_name)

	# The source.
	var source: Dictionary = data.get("source", {})
	grid.source_pos = _to_pos(source.get("pos", []))
	var from_dir := Tile.dir_from_name(String(source.get("from", "")))
	if from_dir == -1:
		errors.append("%s: \"source.from\" must be one of N/E/S/W" % source_name)
	elif _check_pos(grid, grid.source_pos, "source", source_name, errors):
		grid.source_from = from_dir
		if not _on_edge(grid, grid.source_pos, from_dir):
			errors.append("%s: source at (%d, %d) enters from %s but is not on that edge" % [
				source_name, grid.source_pos.x, grid.source_pos.y, Tile.DIR_NAMES[from_dir]])

	if not errors.is_empty():
		return fail.call()
	return {"ok": true, "errors": errors, "grid": grid}


static func parse_json(text: String, source_name: String = "<level>") -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {
			"ok": false,
			"errors": ["%s: JSON parse error on line %d: %s" % [
				source_name, json.get_error_line(), json.get_error_message()]],
			"grid": null,
		}
	return parse(json.data, source_name)


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["%s: no such file" % path], "grid": null}
	return parse_json(FileAccess.get_file_as_string(path), path.get_file())


## Grid -> the same dictionary shape `parse` accepts, so a level round-trips.
static func to_dict(grid: Grid) -> Dictionary:
	var shape_of := {}
	for ch in SHAPES:
		# First glyph wins; every mask in SHAPES is unique so there is no ambiguity.
		if not shape_of.has(SHAPES[ch]):
			shape_of[SHAPES[ch]] = ch

	var rows: Array[String] = []
	var locked: Array = []
	var sponges: Array = []
	var basins: Array = []
	var oneway: Array = []
	for y in grid.height:
		var row := ""
		for x in grid.width:
			var pos := Vector2i(x, y)
			var tile := grid.at(pos)
			row += shape_of.get(tile.mask, "?")
			if tile.locked:
				locked.append([x, y])
			match tile.kind:
				Tile.Kind.SPONGE:
					sponges.append([x, y])
				Tile.Kind.BASIN:
					basins.append([x, y])
				Tile.Kind.ONEWAY:
					oneway.append({"pos": [x, y], "out": Tile.DIR_NAMES[tile.out_dir]})
		rows.append(row)

	var critters: Array = []
	for c in grid.critters:
		critters.append({"pos": [c["pos"].x, c["pos"].y], "type": c["type"]})

	return {
		"id": grid.id,
		"title": grid.title,
		"par": grid.par,
		"tide": grid.tide,
		"source": {"pos": [grid.source_pos.x, grid.source_pos.y], "from": Tile.DIR_NAMES[grid.source_from]},
		"grid": rows,
		"locked": locked,
		"sponges": sponges,
		"basins": basins,
		"oneway": oneway,
		"critters": critters,
	}


static func to_json(grid: Grid) -> String:
	return JSON.stringify(to_dict(grid), "  ")


static func _to_pos(entry: Variant) -> Vector2i:
	if typeof(entry) == TYPE_ARRAY and entry.size() == 2:
		return Vector2i(int(entry[0]), int(entry[1]))
	return Vector2i(-1, -1)


static func _check_pos(grid: Grid, pos: Vector2i, what: String, source_name: String,
		errors: Array[String]) -> bool:
	if grid.in_bounds(pos):
		return true
	errors.append("%s: %s position (%d, %d) is outside the %dx%d grid" % [
		source_name, what, pos.x, pos.y, grid.width, grid.height])
	return false


static func _on_edge(grid: Grid, pos: Vector2i, from_dir: int) -> bool:
	match from_dir:
		Tile.N: return pos.y == 0
		Tile.E: return pos.x == grid.width - 1
		Tile.S: return pos.y == grid.height - 1
		Tile.W: return pos.x == 0
	return false
