extends RefCounted
## The soft reset: design pillar one, and until now it had no automated cover at all.
##
## "The tide running out is never a fail screen. It comes back in." Nothing in tests/ mentioned
## `resetting` or `tide_left`, so the whole pillar could have regressed into a game-over screen and
## every suite would have stayed green. Limpet found the gap peer-verifying TIDE-7 and proved the
## behaviour with a throwaway probe; this is that probe made permanent.
##
## Time is driven by calling `_process(delta)` with an explicit delta rather than by waiting for
## frames. That is deliberate: Limpet's probe first reported a FALSE FAILURE because it bounded the
## wait at 400 frames, and with no vsync that is about 0.38s of a 1.4s pause. A test that measures
## the machine instead of the thing under test is worse than no test. Here the clock is an argument.

const BoardScript := preload("res://scripts/game/board.gd")

## Level 5 "Second Pool": 12 notches of tide, and enough rotatable tiles to spend them.
const LEVEL := 4

var failures: Array[String] = []
var checks := 0
var suite := ""


func _suite(name: String) -> void:
	suite = name


func _check(condition: bool, what: String) -> void:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [suite, what])


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s: %s\n      expected %s\n      got      %s" % [
			suite, what, expected, actual])


## A board with a level on it. `_ready` is called by hand: the board is never added to a tree, so
## nothing here depends on frames, rendering or a display server.
func _board():
	var board = BoardScript.new()
	board._ready()
	if board.levels.is_empty():
		return null
	board.load_level(LEVEL)
	return board


## A tile the player could actually turn. Rotating the SAME tile over and over spends tide without
## making progress -- after a full period it is back where it started -- so the level cannot solve
## itself by accident while the tide drains.
func _rotatable(board) -> Vector2i:
	for y in board.grid.height:
		for x in board.grid.width:
			var pos := Vector2i(x, y)
			var tile = board.grid.at(pos)
			if tile != null and tile.can_rotate() and tile.rotation_period() > 1:
				return pos
	return Vector2i(-1, -1)


func run() -> int:
	_suite("soft reset")
	var board = _board()
	if board == null:
		_check(false, "no levels found, so the soft reset could not be exercised")
		return _report()

	var pos := _rotatable(board)
	if pos.x < 0:
		_check(false, "level %d has no rotatable tile to spend the tide on" % LEVEL)
		board.free()
		return _report()

	var full: int = board.grid.tide
	_check(full > 0, "the level starts with tide in the bar")

	# Spend every notch on one tile.
	for i in full:
		board._try_rotate(pos, 1)
	_eq(board.tide_left, 0, "the tide bar empties after %d rotations" % full)

	# Pillar one: this is a pause, not an ending.
	_check(board.resetting > 0.0, "running the tide out schedules a soft reset")
	_check(not board.cleared, "running the tide out does not count as clearing the level")
	_eq(board.level_index, LEVEL, "running the tide out does not advance to another level")

	# Input is refused while the tide comes back in, so a frustrated click cannot spend a notch of
	# the fresh tide before the player can see it.
	var before: int = board.moves
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = board._tile_rect(pos).get_center()
	board._unhandled_input(click)
	_eq(board.moves, before, "clicks are ignored while the tide is coming back in")

	# The pause is real: part-way through, nothing has restarted yet.
	board._process(board.resetting * 0.5)
	_check(board.resetting > 0.0, "the reset is still pending half way through the pause")
	_eq(board.tide_left, 0, "the tide has not refilled before the pause is over")

	# And then the same level comes back, whole.
	board._process(board.resetting + 0.01)
	_eq(board.resetting, 0.0, "the pause ends")
	_eq(board.tide_left, full, "the tide comes back in full")
	_eq(board.moves, 0, "the move count starts again")
	_eq(board.level_index, LEVEL, "the SAME level restarts, not the next one")
	_check(not board.cleared, "the restarted level is not marked cleared")

	board.free()
	return _report()


func _report() -> int:
	print("")
	if failures.is_empty():
		print("PASS  board: %d checks, 0 failures" % checks)
		return 0
	print("FAIL  board: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  x %s" % f)
	return failures.size()
