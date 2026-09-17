class_name Tile
extends RefCounted
## One cell of the tidepool grid. Pure data: no scene tree, no rendering, no _process.
##
## Connections live in a 4-bit mask, one bit per side, in the fixed order N, E, S, W.
## That order is the whole trick: rotating 90 degrees clockwise shifts every bit up one
## place and wraps W back around into N, so a rotation is two shifts and a mask.

enum Kind {
	EMPTY,    ## Dry sand. Never holds water, never rotates.
	CHANNEL,  ## Ordinary rock channel. Water flows both ways along its connections.
	ONEWAY,   ## Water may only leave through out_dir, and may not enter through it.
	SPONGE,   ## Soaks water up: it gets wet but passes nothing on.
	CRAB,     ## Channel with a crab riding it. Crab walking lands in levels 25-40.
}

const N := 0
const E := 1
const S := 2
const W := 3

const DIRS := [N, E, S, W]
const DIR_NAMES := ["N", "E", "S", "W"]
const DIR_STEPS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var kind: Kind = Kind.CHANNEL
## Bit i is set when this tile has an opening on side i.
var mask: int = 0
## Barnacled. The player cannot rotate it; the solver will not try.
var locked: bool = false
## ONEWAY only: the single side water may leave through. Rotates with the tile.
var out_dir: int = E


static func opposite(dir: int) -> int:
	return (dir + 2) % 4


## "N"/"e"/... -> direction index, or -1 if it is not a direction.
static func dir_from_name(text: String) -> int:
	return DIR_NAMES.find(text.to_upper())


static func make(p_kind: Kind, p_mask: int, p_locked: bool = false, p_out_dir: int = E) -> Tile:
	var t := Tile.new()
	t.kind = p_kind
	t.mask = p_mask
	t.locked = p_locked
	t.out_dir = p_out_dir
	return t


func connects(dir: int) -> bool:
	return (mask & (1 << dir)) != 0


func rotate_cw(times: int = 1) -> void:
	for _i in posmod(times, 4):
		mask = ((mask << 1) | (mask >> 3)) & 0b1111
		out_dir = (out_dir + 1) % 4


func can_rotate() -> bool:
	return not locked and kind != Kind.EMPTY


## How many clockwise rotations bring this tile back to where it started.
## A cross and a blank look identical after every turn, so they are period 1 and the
## solver skips them outright. A straight repeats after two. Everything else, four.
func rotation_period() -> int:
	if kind == Kind.ONEWAY:
		return 4
	if mask == 0b0000 or mask == 0b1111:
		return 1
	if mask == 0b0101 or mask == 0b1010:
		return 2
	return 4


## Can water arrive at this tile through `side`, meaning the side of THIS tile it enters by?
func can_enter_from(side: int) -> bool:
	if kind == Kind.EMPTY:
		return false
	if not connects(side):
		return false
	# A one-way channel's arrow points out. Water cannot swim back in against it.
	if kind == Kind.ONEWAY and side == out_dir:
		return false
	return true


## Can water leave this tile through `side`?
func can_exit_through(side: int) -> bool:
	if kind == Kind.EMPTY:
		return false
	if not connects(side):
		return false
	if kind == Kind.SPONGE:
		return false
	if kind == Kind.ONEWAY:
		return side == out_dir
	return true


func clone() -> Tile:
	return Tile.make(kind, mask, locked, out_dir)


func _to_string() -> String:
	var sides := ""
	for d in DIRS:
		sides += DIR_NAMES[d] if connects(d) else "-"
	return "Tile(%s %s%s)" % [Kind.keys()[kind], sides, " locked" if locked else ""]
