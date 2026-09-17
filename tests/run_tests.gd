extends SceneTree
## Minimal headless test runner. Usage:
##   godot --headless -s tests/run_tests.gd
## Loads every tests/test_*.gd, instantiates it, calls each method named test_*,
## and exits non-zero if any test fails. A test fails by calling `fail("reason")`
## or by any assertion helper below returning false.

const TEST_DIR := "res://tests"

var _failures: Array[String] = []
var _passed := 0


func _init() -> void:
	var files := _find_test_files()
	if files.is_empty():
		print("no tests found in %s" % TEST_DIR)
		quit(1)
		return
	for path in files:
		_run_file(path)
	print("")
	print("%d passed, %d failed" % [_passed, _failures.size()])
	for f in _failures:
		print("FAIL  %s" % f)
	quit(0 if _failures.is_empty() else 1)


func _find_test_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("test_") and name.ends_with(".gd"):
			out.append("%s/%s" % [TEST_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _run_file(path: String) -> void:
	var script := load(path)
	if script == null:
		_failures.append("%s: could not load" % path)
		return
	var inst = script.new()
	if inst == null:
		_failures.append("%s: could not instantiate" % path)
		return
	if inst.has_method("set_runner"):
		inst.set_runner(self)
	for m in inst.get_method_list():
		var mname: String = m["name"]
		if not mname.begins_with("test_"):
			continue
		var before := _failures.size()
		var result = inst.call(mname)
		if result is bool and result == false:
			_failures.append("%s::%s returned false" % [path.get_file(), mname])
		if _failures.size() == before:
			_passed += 1
			print("PASS  %s::%s" % [path.get_file(), mname])
		else:
			print("FAIL  %s::%s" % [path.get_file(), mname])
	if inst is Node:
		inst.free()


## Called by tests via the runner reference.
func fail(reason: String) -> void:
	_failures.append(reason)
