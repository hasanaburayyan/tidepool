extends RefCounted
## Unit tests for the beach map: the baked layout's invariants and the pure logic in
## beach_map.gd (which pool is under a point, what state a pool is in).
##
## No drawing and no scene tree -- the map node is constructed but never added to the tree,
## so _ready and _draw never run and this stays headless. What is NOT covered here is how
## it looks; that is tools/map_shot.gd and a screenshot.

const BeachMap := preload("res://scripts/ui/beach_map.gd")
const SaveDataScript := preload("res://scripts/systems/save_data.gd")

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


## A map node with a save of its own, never added to the tree. Callers free it.
func _map(save: RefCounted) -> Node:
	var m := BeachMap.new()
	m.save = save
	return m


func run() -> int:
	_test_layout_covers_every_level()
	_test_pools_are_on_screen()
	_test_pools_do_not_overlap()
	_test_sprite_slots()
	_test_hit_testing()
	_test_states_follow_the_save()
	_test_bonus_block()

	print("")
	if failures.is_empty():
		print("PASS  map: %d checks, 0 failures" % checks)
		return 0
	print("FAIL  map: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  x %s" % f)
	return failures.size()


# --- the baked layout ---------------------------------------------------------

## The layout is generated, so the thing worth testing is that the generator produced one
## entry per shipping level. A map missing level 27 is a level the player cannot reach.
func _test_layout_covers_every_level() -> void:
	_suite("layout covers every level")
	var levels := {}
	for entry in MapLayout.POOLS:
		levels[int(entry["level"])] = true

	var tide_count := 0
	for f in DirAccess.get_files_at("res://levels"):
		if String(f).trim_suffix(".remap").ends_with(".tide"):
			tide_count += 1

	_eq(MapLayout.POOLS.size(), tide_count,
		"one pool per shipping .tide level (re-run tools/bake_layout.gd after adding one)")
	_eq(levels.size(), MapLayout.POOLS.size(), "no level number appears twice")
	for n in range(1, tide_count + 1):
		_check(levels.has(n), "level %d has a pool on the map" % n)


## Maren's rule is 28 pools on one screen: no scrolling, no pages. A pool off the edge is
## unreachable and would not show up in any test that only checked the data.
func _test_pools_are_on_screen() -> void:
	_suite("pools are on screen")
	var screen := Rect2i(Vector2i.ZERO, MapLayout.SIZE)
	for entry in MapLayout.POOLS:
		var p: Array = entry["pool"]
		var rect := Rect2i(Vector2i(int(p[0]), int(p[1])), MapLayout.POOL_SIZE)
		_check(screen.encloses(rect),
			"pool %d is fully on screen (%s in %s)" % [entry["level"], rect, screen])
		# Shells sit above the rim and are the thing most likely to poke off the top.
		for s in (entry["shells"] as Array):
			_check(screen.has_point(Vector2i(int(s[0]), int(s[1]))),
				"pool %d shell at %s is on screen" % [entry["level"], s])


## Two pools sharing pixels is a hit-testing bug the player meets as "I clicked 26 and got
## 27". bake_layout.gd warns about it; this fails the build over it.
func _test_pools_do_not_overlap() -> void:
	_suite("pools do not overlap")
	for i in MapLayout.POOLS.size():
		for j in range(i + 1, MapLayout.POOLS.size()):
			var a: Array = MapLayout.POOLS[i]["pool"]
			var b: Array = MapLayout.POOLS[j]["pool"]
			var ra := Rect2i(Vector2i(int(a[0]), int(a[1])), MapLayout.POOL_SIZE)
			var rb := Rect2i(Vector2i(int(b[0]), int(b[1])), MapLayout.POOL_SIZE)
			_check(not ra.intersects(rb), "pools %d and %d do not overlap"
				% [MapLayout.POOLS[i]["level"], MapLayout.POOLS[j]["level"]])


## Three shell slots always, in the same order: stars are counted, not measured.
func _test_sprite_slots() -> void:
	_suite("sprite slots")
	for entry in MapLayout.POOLS:
		var level := int(entry["level"])
		_eq((entry["shells"] as Array).size(), 3,
			"pool %d has three shell positions" % level)
		_eq((entry["digits"] as Array).size(), str(level).length(),
			"pool %d has one digit position per digit" % level)
		# Shells run left to right in a fixed order, so slot 1 is always the same slot.
		var shells: Array = entry["shells"]
		_check(int(shells[0][0]) < int(shells[1][0]) and int(shells[1][0]) < int(shells[2][0]),
			"pool %d shells are ordered left to right" % level)


# --- beach_map.gd -------------------------------------------------------------

func _test_hit_testing() -> void:
	_suite("hit testing")
	var m := _map(SaveDataScript.new())

	for entry in MapLayout.POOLS:
		var centre := Vector2(int(entry["x"]), int(entry["y"]))
		_eq(m.level_at(centre), int(entry["level"]),
			"the centre of pool %d hits pool %d" % [entry["level"], entry["level"]])

	# Bare sand is not a pool. (4, 4) is the top-left corner, which no pool reaches.
	_eq(m.level_at(Vector2(4, 4)), 0, "empty sand hits no pool")
	_eq(m.level_at(Vector2(-50, -50)), 0, "a point off the map hits no pool")
	m.free()


func _test_states_follow_the_save() -> void:
	_suite("states follow the save")
	var save = SaveDataScript.new()
	var m := _map(save)

	_eq(m.state_of(1), "open", "on a fresh save pool 1 is open")
	_eq(m.state_of(2), "locked", "on a fresh save pool 2 is locked")
	_eq(m.state_of(28), "locked", "on a fresh save the last pool is locked")

	save.record_clear(1, 3)
	_eq(m.state_of(1), "done", "a cleared pool is done")
	_eq(m.state_of(2), "open", "clearing 1 opens 2")
	_eq(m.state_of(3), "locked", "but not 3")

	# A one-star clear opens the next pool exactly like a three-star one: stars never gate.
	save.record_clear(2, 1)
	_eq(m.state_of(3), "open", "a one-star clear still opens the next pool")
	m.free()


## Maren's rule for the basin block: it is unlocked by finishing pool 24, not by stars, and
## before that it is dry rock like any other locked pool -- "something is there, later".
func _test_bonus_block() -> void:
	_suite("bonus block")
	var bonus := []
	for entry in MapLayout.POOLS:
		if bool(entry["bonus"]):
			bonus.append(int(entry["level"]))
	bonus.sort()
	_eq(bonus, [25, 26, 27, 28], "25-28 are flagged as the bonus block")

	var save = SaveDataScript.new()
	var m := _map(save)
	for n in range(1, 24):
		save.record_clear(n, 1)
	_eq(m.state_of(25), "locked", "pool 25 is locked until 24 is finished")
	save.record_clear(24, 1)
	_eq(m.state_of(25), "open", "finishing 24 opens 25, on one star")
	m.free()
