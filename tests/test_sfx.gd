extends RefCounted
## Unit tests for the sound-effect helper. No audio device and no scene tree: the variant
## picker is pure, and the file check only asks the resource loader what exists.
##
## What this cannot cover is whether anything is audible. That needs ears on a build, and
## it is QA checklist line D8.

const SfxScript := preload("res://scripts/systems/sfx.gd")

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
	_test_every_sound_exists()
	_test_variant_never_repeats()
	_test_variant_edge_cases()

	print("")
	if failures.is_empty():
		print("PASS  sfx: %d checks, 0 failures" % checks)
		return 0
	print("FAIL  sfx: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  x %s" % f)
	return failures.size()


## Every sound the board asks for by name must exist. A renamed or missing file otherwise
## degrades to a one-line warning at runtime and silence in the build -- which is exactly
## the failure nobody notices until a playtester says "I didn't hear anything".
func _test_every_sound_exists() -> void:
	_suite("every sound exists")
	for sound in ["rotate_click_1", "rotate_click_2", "rotate_click_3",
			"locked_thunk", "rescue_chime"]:
		var path := "%s/%s.wav" % [SfxScript.DIR, sound]
		_check(ResourceLoader.exists(path), "%s is present" % path)


## Tern's rule: never the same variant twice running. With three files that is the
## difference between a texture and a tic.
func _test_variant_never_repeats() -> void:
	_suite("variant never repeats")
	var sfx = SfxScript.new()
	var last := 0
	var seen := {}
	for _i in 200:
		var i: int = sfx.pick_variant("rotate_click", 3)
		_check(i != last, "variant %d differs from the one before it" % i)
		_check(i >= 1 and i <= 3, "variant %d is in range" % i)
		seen[i] = true
		last = i
	_eq(seen.size(), 3, "all three variants get used across 200 picks")
	sfx.free()


func _test_variant_edge_cases() -> void:
	_suite("variant edge cases")
	var sfx = SfxScript.new()
	# One file cannot avoid repeating itself, and must not spin forever trying.
	for _i in 5:
		_eq(sfx.pick_variant("solo", 1), 1, "a single variant just plays")
	_eq(sfx.pick_variant("none", 0), 0, "no variants picks nothing")
	# Two bases keep their own history rather than sharing one.
	sfx.pick_variant("a", 3)
	var b_first: int = sfx.pick_variant("b", 3)
	_check(b_first >= 1, "a second base picks independently")
	sfx.free()
