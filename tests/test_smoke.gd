extends RefCounted
## Sample test. Each `test_*` method returns true on success; call `runner.fail(msg)` for details.

var runner = null


func set_runner(r) -> void:
	runner = r


func test_main_scene_loads() -> bool:
	var scene := load("res://scenes/main.tscn")
	if scene == null:
		if runner: runner.fail("main.tscn did not load")
		return false
	var node = scene.instantiate()
	var ok := node.has_method("get_title") and node.get_title() == "Tidepool"
	if not ok and runner:
		runner.fail("main scene title mismatch: %s" % node.get_title())
	node.free()
	return ok


func test_arithmetic_sanity() -> bool:
	return 2 + 2 == 4
