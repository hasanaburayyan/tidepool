extends SceneTree
## Headless entry point for the test suite. Exits non-zero when anything fails, so
## CI and run_tests.sh can just check the status code.

const TestCore := preload("res://tests/test_core.gd")


func _initialize() -> void:
	var failures: int = TestCore.new().run()
	quit(1 if failures > 0 else 0)
