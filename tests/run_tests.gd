extends SceneTree
## Headless entry point for the test suite. Exits non-zero when anything fails, so
## CI and run_tests.sh can just check the status code.

const TestCore := preload("res://tests/test_core.gd")
const TestSave := preload("res://tests/test_save.gd")
const TestMap := preload("res://tests/test_map.gd")
const TestSfx := preload("res://tests/test_sfx.gd")
const TestBoard := preload("res://tests/test_board.gd")


func _initialize() -> void:
	# Each suite prints its own PASS/FAIL block; the status code is the sum, so a green
	# core suite cannot hide a red one.
	var failures: int = TestCore.new().run()
	failures += TestSave.new().run()
	failures += TestMap.new().run()
	failures += TestSfx.new().run()
	failures += TestBoard.new().run()
	quit(1 if failures > 0 else 0)
