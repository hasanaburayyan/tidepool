extends RefCounted
## Unit tests for the deterministic core. No scene tree, no rendering, no timing.
## Run with ./run_tests.sh, or:
##   godot --headless --path . --script res://tests/run_tests.gd

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


func run() -> int:
	_test_tile_rotation()
	_test_shape_rot()
	_test_refusing()
	_test_distances()
	_test_flow_basics()
	_test_flow_oneway_and_sponge()
	_test_level_io()
	_test_validator()
	_test_debug_levels()
	_test_shipping_levels()

	print("")
	if failures.is_empty():
		print("PASS  %d checks, 0 failures" % checks)
		return 0
	print("FAIL  %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  x %s" % f)
	return failures.size()


# --- Tile ---------------------------------------------------------------------

## shape_rot() is how the renderer picks a sprite and how far to turn it, and it is
## DERIVED from the mask rather than remembered from the level file -- so it has to stay
## right after the player rotates a tile, which is exactly where a remembered value rots.
func _test_shape_rot() -> void:
	_suite("shape_rot")

	# Every rotation of every shape, walked by actually rotating the tile.
	var expected := {
		"i": [0b0101, 0b1010, 0b0101, 0b1010],
		"l": [0b0011, 0b0110, 0b1100, 0b1001],
		"t": [0b0111, 0b1110, 0b1101, 0b1011],
		"e": [0b0001, 0b0010, 0b0100, 0b1000],
	}
	for letter in expected:
		var masks: Array = expected[letter]
		var tile := Tile.make(Tile.Kind.CHANNEL, masks[0])
		for turns in 4:
			_eq(tile.mask, masks[turns], "%s after %d turns has the right mask" % [letter, turns])
			var got := tile.shape_rot()
			_eq(got[0], letter, "%s after %d turns is still shape %s" % [letter, turns, letter])
			# A straight repeats after two turns, so its reported rotation wraps with it.
			_eq(got[1], turns % tile.rotation_period(),
					"%s after %d turns reports rotation %d" % [letter, turns, turns % tile.rotation_period()])
			tile.rotate_cw()

	# A cross looks the same every way up, so it is always rotation 0 -- otherwise the
	# renderer would turn a symmetric sprite for no reason and, with art, shimmer it.
	_eq(Tile.make(Tile.Kind.CHANNEL, 0b1111).shape_rot(), ["x", 0], "cross is always ['x', 0]")

	# Kind overrides shape: a sponge is a straight by mask and must not draw as one.
	_eq(Tile.make(Tile.Kind.SPONGE, 0b0101).shape_rot(), ["p", 0], "sponge N,S is ['p', 0]")
	_eq(Tile.make(Tile.Kind.SPONGE, 0b1010).shape_rot(), ["p", 1], "sponge E,W is ['p', 1]")

	# A one-way's rotation is its exit side, not its mask: two arrows on the same N,S
	# channel pointing opposite ways are different sprites and must not collapse.
	_eq(Tile.make(Tile.Kind.ONEWAY, 0b0101, false, Tile.N).shape_rot(), ["o", Tile.N],
			"one-way exiting N is ['o', N]")
	_eq(Tile.make(Tile.Kind.ONEWAY, 0b0101, false, Tile.S).shape_rot(), ["o", Tile.S],
			"one-way exiting S is ['o', S] on the same mask")


## Refusal is invisible in the wet set -- water simply is not there -- so the board needs
## to be told which arrows are doing the turning away. Levels 14, 16, 17 and 18 depend on
## the player seeing it, and a silent refusal reads as a bug in the flow.
## `distances` drives what the player SEES the water do, so if it ever disagrees with
## `compute` the board would animate water into a tile that is dry, or leave a wet one
## undrawn. Same traversal, two outputs; this pins them together on every shipped level.
func _test_distances() -> void:
	_suite("distances")

	var line := TideFormat.parse("id: 1\nname: line\nsize: 3x1\npar: 1\ntide: 6\n"
			+ "source: r0c0\ngrid:\n  i1 i1 i1\ncritters:\n  r0c2 crab\n", "line")
	_check(line["ok"], "the straight-line board parses: %s" % [line["errors"]])
	if line["ok"]:
		var g: Grid = line["grid"]
		var d := Flow.distances(g)
		_eq(d.get(g.index(Vector2i(0, 0)), -1), 0, "the source is distance 0")
		_eq(d.get(g.index(Vector2i(1, 0)), -1), 1, "its neighbour is 1")
		_eq(d.get(g.index(Vector2i(2, 0)), -1), 2, "and the far end is 2")

	var dir := DirAccess.open("res://levels")
	var names: Array = []
	if dir != null:
		for n in dir.get_files():
			if String(n).ends_with(".tide"):
				names.append(n)
	names.sort()
	_check(names.size() > 0, "found shipped levels to check")
	for n in names:
		var parsed := TideFormat.load_file("res://levels/" + String(n))
		if not parsed["ok"]:
			continue
		var grid: Grid = parsed["grid"]
		var wet_keys: Array = Flow.compute(grid).keys()
		var dist_keys: Array = Flow.distances(grid).keys()
		wet_keys.sort()
		dist_keys.sort()
		_eq(dist_keys, wet_keys, "%s: distances covers exactly the wet set" % n)


func _test_refusing() -> void:
	_suite("refusing")

	# Source, then an arrow pointing back WEST at it: water reaches the arrow's mouth and
	# is refused. This is the shape level 14 is built on.
	var blocked := TideFormat.parse("id: 1\nname: refuse\nsize: 3x1\npar: 1\ntide: 6\n"
			+ "source: r0c0\ngrid:\n  i1 o3 i1\ncritters:\n  r0c2 crab\n", "refuse")
	_check(blocked["ok"], "the refusing board parses: %s" % [blocked["errors"]])
	if blocked["ok"]:
		var grid: Grid = blocked["grid"]
		var wet := Flow.compute(grid)
		var turned := Flow.refusing(grid, wet)
		_eq(turned.has(grid.index(Vector2i(1, 0))), true, "an arrow facing the water refuses")
		_eq(wet.has(grid.index(Vector2i(2, 0))), false, "and nothing flows past it")

	# The same board with the arrow turned around: water enters and passes through, so the
	# arrow is working rather than blocking and must NOT be drawn as refusing.
	var flowing := TideFormat.parse("id: 1\nname: pass\nsize: 3x1\npar: 1\ntide: 6\n"
			+ "source: r0c0\ngrid:\n  i1 o1 i1\ncritters:\n  r0c2 crab\n", "pass")
	_check(flowing["ok"], "the flowing board parses: %s" % [flowing["errors"]])
	if flowing["ok"]:
		var grid2: Grid = flowing["grid"]
		var wet2 := Flow.compute(grid2)
		_eq(Flow.refusing(grid2, wet2).is_empty(), true, "an arrow water flows through does not refuse")
		_eq(wet2.has(grid2.index(Vector2i(2, 0))), true, "and the water gets through")


func _test_tile_rotation() -> void:
	_suite("tile rotation")
	var straight := Tile.make(Tile.Kind.CHANNEL, 0b0101)  # N S
	straight.rotate_cw()
	_eq(straight.mask, 0b1010, "vertical straight turns horizontal")
	straight.rotate_cw()
	_eq(straight.mask, 0b0101, "and back again after two turns")

	var corner := Tile.make(Tile.Kind.CHANNEL, 0b0011)  # N E
	corner.rotate_cw()
	_eq(corner.mask, 0b0110, "N|E corner turns to S|E")
	corner.rotate_cw(3)
	_eq(corner.mask, 0b0011, "four turns is the identity")

	_eq(Tile.make(Tile.Kind.CHANNEL, 0b0011).rotation_period(), 4, "corner period is 4")
	_eq(Tile.make(Tile.Kind.CHANNEL, 0b0101).rotation_period(), 2, "straight period is 2")
	_eq(Tile.make(Tile.Kind.CHANNEL, 0b1111).rotation_period(), 1, "cross period is 1")
	_eq(Tile.make(Tile.Kind.EMPTY, 0).rotation_period(), 1, "sand period is 1")

	# A negative count is the same as turning the other way.
	var back := Tile.make(Tile.Kind.CHANNEL, 0b0011)
	back.rotate_cw(-1)
	_eq(back.mask, 0b1001, "rotating -1 is the same as rotating 3")

	var oneway := Tile.make(Tile.Kind.ONEWAY, 0b1010, false, Tile.E)
	oneway.rotate_cw()
	_eq(oneway.out_dir, Tile.S, "the arrow turns with the tile")

	var locked := Tile.make(Tile.Kind.CHANNEL, 0b0011, true)
	_check(not locked.can_rotate(), "a barnacled tile refuses to turn")
	_check(not Tile.make(Tile.Kind.EMPTY, 0).can_rotate(), "sand refuses to turn")

	_eq(Tile.opposite(Tile.N), Tile.S, "N is opposite S")
	_eq(Tile.opposite(Tile.E), Tile.W, "E is opposite W")
	_eq(Tile.dir_from_name("w"), Tile.W, "direction names are case insensitive")
	_eq(Tile.dir_from_name("up"), -1, "an unknown direction name is -1")


# --- Flow ---------------------------------------------------------------------

## Build a grid straight from ASCII so the test reads like the level it describes.
func _grid_from(rows: Array, source_pos: Vector2i, source_from: int) -> Grid:
	var g := Grid.create(String(rows[0]).length(), rows.size())
	for y in rows.size():
		for x in g.width:
			var mask: int = LevelIO.SHAPES[String(rows[y])[x]]
			g.set_at(Vector2i(x, y), Tile.make(
				Tile.Kind.EMPTY if mask == 0 else Tile.Kind.CHANNEL, mask))
	g.source_pos = source_pos
	g.source_from = source_from
	return g


func _test_flow_basics() -> void:
	_suite("flow")
	var g := _grid_from(["---"], Vector2i(0, 0), Tile.W)
	_eq(Flow.wet_positions(g, Flow.compute(g)),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		"water runs the length of a connected row")

	_suite("flow stops at a gap")
	var broken := _grid_from(["-|-"], Vector2i(0, 0), Tile.W)
	_eq(Flow.wet_positions(broken, Flow.compute(broken)), [Vector2i(0, 0)],
		"a sideways tile in the middle blocks the run")

	_suite("the source tile is wet by definition")
	# It is fed from the sea, not through one of its own openings, so it fills even with
	# no W connection -- but the water has nowhere to go from there.
	var shut := _grid_from(["|--"], Vector2i(0, 0), Tile.W)
	_eq(Flow.wet_positions(shut, Flow.compute(shut)), [Vector2i(0, 0)],
		"a source tile with no W opening still fills, and leaks nowhere")
	var rock_source := _grid_from([".--"], Vector2i(0, 0), Tile.W)
	_check(Flow.compute(rock_source).is_empty(), "but a source on bare rock is dry")

	_suite("flow needs both halves of a seam")
	# The left tile opens E but the right tile is a vertical straight with no W opening.
	var seam := _grid_from(["-|"], Vector2i(0, 0), Tile.W)
	_eq(Flow.wet_positions(seam, Flow.compute(seam)), [Vector2i(0, 0)],
		"a one-sided seam does not conduct")

	_suite("flow around a corner")
	var corner := _grid_from(["..7", "..|"], Vector2i(2, 0), Tile.W)
	# (2,0) is S|W: enters from W, leaves S into (2,1) which is N|S.
	_eq(Flow.wet_positions(corner, Flow.compute(corner)), [Vector2i(2, 0), Vector2i(2, 1)],
		"water turns the corner and runs down")

	_suite("flow is deterministic")
	var branch := _grid_from(["-+-", ".|."], Vector2i(0, 0), Tile.W)
	var first := Flow.wet_positions(branch, Flow.compute(branch))
	for _i in 5:
		_eq(Flow.wet_positions(branch, Flow.compute(branch)), first,
			"the same board gives the same wet set every time")

	_suite("rescue")
	var pool := _grid_from(["---"], Vector2i(0, 0), Tile.W)
	pool.critters.append({"pos": Vector2i(2, 0), "type": "crab"})
	pool.critters.append({"pos": Vector2i(1, 0), "type": "starfish"})
	var wet := Flow.compute(pool)
	_eq(Flow.rescued(pool, wet), [0, 1], "both critters are in the water")
	_check(Flow.all_rescued(pool, wet), "the level is solved")

	var dry := _grid_from(["-|-"], Vector2i(0, 0), Tile.W)
	dry.critters.append({"pos": Vector2i(2, 0), "type": "crab"})
	_check(not Flow.all_rescued(dry, Flow.compute(dry)), "a stranded critter is not rescued")
	_check(not Flow.is_solved(_grid_from(["---"], Vector2i(0, 0), Tile.W)),
		"a board with no critters is not solved")

	_suite("rotation changes the flow")
	var fixable := _grid_from(["-|-"], Vector2i(0, 0), Tile.W)
	fixable.critters.append({"pos": Vector2i(2, 0), "type": "crab"})
	_check(fixable.rotate_at(Vector2i(1, 0)), "the middle tile turns")
	_check(Flow.is_solved(fixable), "turning it connects the channel")

	_suite("grid guards")
	var guard := _grid_from(["-|-"], Vector2i(0, 0), Tile.W)
	_check(not guard.rotate_at(Vector2i(9, 9)), "rotating off the board is refused")
	guard.at(Vector2i(1, 0)).locked = true
	_check(not guard.rotate_at(Vector2i(1, 0)), "rotating a barnacled tile is refused")
	_eq(guard.rotatable_indices(), [0, 2] as Array[int],
		"locked tiles are not offered to the solver")


func _test_flow_oneway_and_sponge() -> void:
	_suite("one-way")
	# Middle tile is a horizontal channel whose arrow points E.
	var g := _grid_from(["---"], Vector2i(0, 0), Tile.W)
	var mid := g.at(Vector2i(1, 0))
	mid.kind = Tile.Kind.ONEWAY
	mid.out_dir = Tile.E
	_eq(Flow.wet_positions(g, Flow.compute(g)),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		"water passes through an arrow pointing with the current")

	mid.out_dir = Tile.W
	_eq(Flow.wet_positions(g, Flow.compute(g)), [Vector2i(0, 0)],
		"an arrow pointing back at the source blocks entry entirely")

	_suite("sponge")
	var sponge_grid := _grid_from(["---"], Vector2i(0, 0), Tile.W)
	sponge_grid.at(Vector2i(1, 0)).kind = Tile.Kind.SPONGE
	_eq(Flow.wet_positions(sponge_grid, Flow.compute(sponge_grid)),
		[Vector2i(0, 0), Vector2i(1, 0)],
		"a sponge soaks up the water but passes none on")


# --- Level IO -----------------------------------------------------------------

func _test_level_io() -> void:
	_suite("level parse")
	var text := """
	{
	  "id": 7, "title": "Test", "par": 2, "tide": 25,
	  "source": { "pos": [0, 1], "from": "W" },
	  "grid": [ "...", "-|-", "..." ],
	  "locked": [ [2, 1] ],
	  "critters": [ { "pos": [2, 1], "type": "crab" } ]
	}
	"""
	var r := LevelIO.parse_json(text, "inline")
	_check(r["ok"], "a well formed level parses: %s" % [r["errors"]])
	if r["ok"]:
		var g: Grid = r["grid"]
		_eq(g.width, 3, "width comes from the first row")
		_eq(g.height, 3, "height comes from the row count")
		_eq(g.id, 7, "id is read")
		_eq(g.par, 2, "par is read")
		_eq(g.tide, 25.0, "tide is read")
		_eq(g.source_from, Tile.W, "source direction is read")
		_eq(g.at(Vector2i(1, 1)).mask, 0b0101, "the | glyph is a N|S channel")
		_eq(g.at(Vector2i(0, 0)).kind, Tile.Kind.EMPTY, "the . glyph is sand")
		_check(g.at(Vector2i(2, 1)).locked, "the locked list barnacles its tile")
		_eq(g.critters.size(), 1, "one critter")
		_eq(g.critters[0]["pos"], Vector2i(2, 1), "critter position is x,y")

	_suite("level round trip")
	var loaded: Grid = LevelIO.parse_json(text, "inline")["grid"]
	var again := LevelIO.parse_json(LevelIO.to_json(loaded), "round-trip")
	_check(again["ok"], "a written level parses back: %s" % [again["errors"]])
	if again["ok"]:
		var b: Grid = again["grid"]
		_eq(LevelIO.to_dict(b), LevelIO.to_dict(loaded), "the level survives a round trip")

	_suite("level errors")
	var bad := [
		['{ "grid": ["--", "---"], "source": {"pos":[0,0],"from":"W"}, "critters":[{"pos":[1,0]}] }',
			"ragged rows are rejected"],
		['{ "grid": ["-@-"], "source": {"pos":[0,0],"from":"W"}, "critters":[{"pos":[2,0]}] }',
			"an unknown glyph is rejected"],
		['{ "grid": ["---"], "source": {"pos":[1,0],"from":"W"}, "critters":[{"pos":[2,0]}] }',
			"a source that is not on its edge is rejected"],
		['{ "grid": ["---"], "source": {"pos":[0,0],"from":"up"}, "critters":[{"pos":[2,0]}] }',
			"a bad source direction is rejected"],
		['{ "grid": ["-.-"], "source": {"pos":[0,0],"from":"W"}, "critters":[{"pos":[1,0]}] }',
			"a critter stranded on sand is rejected"],
		['{ "grid": ["---"], "source": {"pos":[0,0],"from":"W"}, "critters":[] }',
			"a level with no critters is rejected"],
		['{ "grid": ["---"], "source": {"pos":[0,0],"from":"W"}, "critters":[{"pos":[9,9]}] }',
			"an out of bounds critter is rejected"],
		['{ "grid": ["-|-"], "source": {"pos":[0,0],"from":"W"}, "critters":[{"pos":[2,0]}],'
			+ ' "oneway":[{"pos":[1,0],"out":"E"}] }',
			"an arrow pointing at a wall is rejected"],
		['not json at all', "malformed JSON is rejected"],
	]
	for case in bad:
		_check(not LevelIO.parse_json(case[0], "bad")["ok"], case[1])

	_suite("missing file")
	_check(not LevelIO.load_file("res://levels/does_not_exist.json")["ok"],
		"a missing level file is an error, not a crash")


# --- Validator ----------------------------------------------------------------

func _test_validator() -> void:
	_suite("validator")
	var one_move := _grid_from(["-|-"], Vector2i(0, 0), Tile.W)
	one_move.critters.append({"pos": Vector2i(2, 0), "type": "crab"})
	var r := Validator.solve(one_move, 4)
	_check(r["solved"], "a one move level is solved")
	_eq(r["moves"], 1, "and it takes exactly one move")
	_eq(r["plan"].size(), 1, "the plan has one step")
	_eq(r["plan"][0]["pos"], Vector2i(1, 0), "the plan names the tile to turn")

	_suite("validator leaves the board alone")
	var before := LevelIO.to_dict(one_move)
	Validator.solve(one_move, 4)
	_eq(LevelIO.to_dict(one_move), before, "solving does not mutate the caller's grid")

	_suite("validator finds the minimum")
	# Two tiles are wrong, so it cannot be done in fewer than two moves.
	var two := _grid_from(["-|-|-"], Vector2i(0, 0), Tile.W)
	two.critters.append({"pos": Vector2i(4, 0), "type": "crab"})
	var r2 := Validator.solve(two, 5)
	_check(r2["solved"], "a two move level is solved")
	_eq(r2["moves"], 2, "and the minimum really is two")

	_suite("validator counts clicks, not clockwise steps")
	# The corner at r0c0 starts at L3 = {W,N} and has to reach {S,W} to feed the critter
	# below it. That is three clockwise steps, or one right-click, and the player is only
	# charged for the right-click. Level 07 is built on exactly this; before the fix the
	# search charged three and called a one-tide level unsolvable.
	var ccw := TideFormat.parse("id: 1\nname: ccw\nsize: 2x2\npar: 1\ntide: 6\n"
			+ "source: r0c0\ngrid:\n  L3 ..\n  i0 ..\ncritters:\n  r1c0 crab\n", "ccw")
	_check(ccw["ok"], "the right-click level parses: %s" % [ccw["errors"]])
	if ccw["ok"]:
		var rc := Validator.solve(ccw["grid"], 3)
		_check(rc["solved"], "a right-click level is solved")
		_eq(rc["moves"], 1, "three clockwise steps cost one click")

	_suite("a sponge is thirsty rock")
	# tidepool-sponge-rules v2: a sponge never emits, so it is a wall you cannot route
	# through -- but it must end up wet for the level to clear, exactly like a critter
	# must be rescued. Unlike a rescue it does not latch; wring it out and the level
	# un-clears. Levels 19-20 are built on this.
	var sp := TideFormat.parse("id: 1\nname: sponge\nsize: 3x2\npar: 1\ntide: 6\n"
			+ "source: r0c0\ngrid:\n  i1 t2 P0\n  .. p0 ..\ncritters:\n  r0c2 crab\n", "sp")
	_check(sp["ok"], "a level with a sponge parses: %s" % [sp["errors"]])
	if sp["ok"]:
		var sg: Grid = sp["grid"]
		var sw := Flow.compute(sg)
		_check(not sw.has(sg.index(Vector2i(2, 0))),
				"a sponge passes nothing on: the tile past it stays dry")
		_check(sw.has(sg.index(Vector2i(1, 1))), "but the sponge itself drinks")
		_check(not Flow.is_cleared(sg, sw), "a dry sponge keeps the level uncleared")
		_check(not Flow.all_sponges_wet(sg, sw),
				"the sponge behind the first one is dry, so the board is not cleared")

	_suite("one-way and sponge glyphs parse")
	var glyphs := TideFormat.parse("id: 1\nname: g\nsize: 3x1\npar: 1\ntide: 6\n"
			+ "source: r0c0\ngrid:\n  e1 o1 p0\ncritters:\n  r0c1 crab\n", "glyphs")
	_check(glyphs["ok"], "a level using O and P parses: %s" % [glyphs["errors"]])
	if glyphs["ok"]:
		var gg: Grid = glyphs["grid"]
		var oneway := gg.at(Vector2i(1, 0))
		_eq(oneway.kind, Tile.Kind.ONEWAY, "O is a one-way")
		_eq(oneway.out_dir, Tile.E, "the digit is the side water leaves by")
		_check(not oneway.can_enter_from(Tile.E), "water is refused at the arrow end")
		_check(oneway.can_enter_from(Tile.W), "and accepted at the other end")
		_eq(gg.at(Vector2i(2, 0)).kind, Tile.Kind.SPONGE, "P is a sponge")
		_check(not gg.at(Vector2i(2, 0)).can_exit_through(Tile.N), "a sponge never emits")

	_suite("validator reports impossible")
	var impossible := _grid_from(["-.-"], Vector2i(0, 0), Tile.W)
	impossible.at(Vector2i(2, 0)).kind = Tile.Kind.CHANNEL
	impossible.critters.append({"pos": Vector2i(2, 0), "type": "crab"})
	var r3 := Validator.solve(impossible, 4)
	_check(not r3["solved"], "sand in the way cannot be rotated away")
	_check(not r3["exhausted"], "and the search finished rather than gave up")

	_suite("validator respects its budget")
	var wide := _grid_from(["-L7L7L7L7L7L7"], Vector2i(0, 0), Tile.W)
	wide.critters.append({"pos": Vector2i(12, 0), "type": "crab"})
	var r4 := Validator.solve(wide, 12, 500)
	_check(r4["exhausted"], "a tiny node budget stops the search")
	_check(not r4["solved"], "and an exhausted search does not claim a solution")


func _test_debug_levels() -> void:
	_suite("debug levels")
	for i in range(1, 6):
		var path := "res://levels/debug_%02d.json" % i
		var r := Validator.check_level(path)
		for line in r["lines"]:
			print(line.strip_edges(true, false))
		_check(r["ok"], "%s validates" % path.get_file())


## The five shipping levels, in the Game Director's `.tide` format. This is the test that
## replaces hand-tracing: it replays the author's own `solution:` and then has the solver
## find the cheapest one independently, so a level whose par is wrong fails here and not
## in someone's head.
func _test_shipping_levels() -> void:
	_suite("shipping levels 1-5")
	# The Game Director owns levels/, named NN.tide. This suite keeps the first five
	# honest on every run; tools/verify_levels.gd sweeps all of them and is what CI runs.
	var names := ["01", "02", "03", "04", "05"]
	for name in names:
		var path := "res://levels/%s.tide" % name
		var r := TideFormat.load_file(path)
		if not r["ok"]:
			for e in r["errors"]:
				print("      %s" % e)
			_check(false, "%s parses" % name)
			continue
		var grid: Grid = r["grid"]
		var solution: Array = r["solution"]

		# 1. The author's solution actually clears the level, and costs exactly par.
		var replay: Grid = grid.clone()
		var clicks := 0
		for step in solution:
			replay.at(step["pos"]).rotate_cw(step["turns"])
			clicks += step["clicks"]
		_check(Flow.all_rescued(replay, Flow.compute(replay)), "%s: author solution rescues everyone" % name)
		_eq(clicks, grid.par, "%s: author solution costs par" % name)

		# 2. Nothing is rescued before the player touches anything -- a pre-solved level
		#    is the easiest mistake to ship and the hardest to notice.
		_check(not Flow.all_rescued(grid, Flow.compute(grid)), "%s: not already solved" % name)

		# 3. Par is the true minimum, found by search rather than by hand.
		var solved := Validator.solve(grid.clone(), grid.par)
		_check(solved["solved"], "%s: solvable within par" % name)
		if solved["solved"]:
			_eq(solved["moves"], grid.par, "%s: par is the cheapest solution" % name)

		# 4. Tide is a move budget with room to fumble (design doc 2.1).
		var slack := 5 if grid.id <= 12 else 6
		_eq(grid.tide, grid.par + slack, "%s: tide is par+%d exactly" % [name, slack])
		print("      %-16s %dx%d  par %d  tide %d  critters %d  nodes %d" % [
			name, grid.width, grid.height, grid.par, grid.tide, grid.critters.size(), solved["nodes"]])
