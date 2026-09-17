class_name Grid
extends RefCounted
## The board: tiles in row-major order plus everything a level needs to be played.
## Pure data. Coordinates are Vector2i(x, y) with x = column, y = row, origin top-left.

var width: int = 0
var height: int = 0
var tiles: Array[Tile] = []

## Where the tide enters, and which side of that tile it enters through.
var source_pos: Vector2i = Vector2i.ZERO
var source_from: int = Tile.W

## Each entry: { "pos": Vector2i, "type": String }
var critters: Array[Dictionary] = []

var id: int = 0
var title: String = ""
var par: int = 0
## Rotations the player may spend before the tide comes back in. A move budget, not a
## clock: thinking is free (design doc §2.1).
var tide: int = 0


static func create(p_width: int, p_height: int) -> Grid:
	var g := Grid.new()
	g.width = p_width
	g.height = p_height
	for _i in p_width * p_height:
		g.tiles.append(Tile.make(Tile.Kind.EMPTY, 0))
	return g


func index(pos: Vector2i) -> int:
	return pos.y * width + pos.x


func pos_of(idx: int) -> Vector2i:
	return Vector2i(idx % width, idx / width)


func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height


func at(pos: Vector2i) -> Tile:
	return tiles[index(pos)] if in_bounds(pos) else null


func set_at(pos: Vector2i, tile: Tile) -> void:
	tiles[index(pos)] = tile


## Rotate the tile at `pos`. Returns false when the tile refuses: out of bounds,
## barnacled, or bare sand. Callers use the return value to decide whether the move counts.
func rotate_at(pos: Vector2i, times: int = 1) -> bool:
	var tile := at(pos)
	if tile == null or not tile.can_rotate():
		return false
	tile.rotate_cw(times)
	return true


## Indices of tiles a player could usefully turn. Skips locked tiles, sand, and
## tiles that look the same after every rotation.
func rotatable_indices() -> Array[int]:
	var out: Array[int] = []
	for i in tiles.size():
		var tile := tiles[i]
		if tile.can_rotate() and tile.rotation_period() > 1:
			out.append(i)
	return out


func clone() -> Grid:
	var g := Grid.new()
	g.width = width
	g.height = height
	g.source_pos = source_pos
	g.source_from = source_from
	g.id = id
	g.title = title
	g.par = par
	g.tide = tide
	for t in tiles:
		g.tiles.append(t.clone())
	for c in critters:
		g.critters.append(c.duplicate())
	return g
