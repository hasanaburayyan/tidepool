extends RefCounted
## Unit tests for SaveData. No scene tree, no rendering: every test points a SaveData at a
## temp file under user:// and deletes it afterwards, so the player's real save is never
## touched and the suite can run headless in CI.
##
##   godot --headless --path . --script res://tests/run_tests.gd

const SaveDataScript := preload("res://scripts/systems/save_data.gd")

var failures: Array[String] = []
var checks := 0
var suite := ""

## Every temp file this run has touched, removed in run() even when a check fails.
var _temp_paths: Array[String] = []


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


## A unique path per call, so one test leaking cannot make another test pass.
func _temp_path() -> String:
	var p := "user://test_save_%d_%d.json" % [Time.get_ticks_usec(), randi()]
	_temp_paths.append(p)
	return p


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	return text


func _cleanup() -> void:
	for p in _temp_paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		var tmp := p + SaveDataScript.TMP_SUFFIX
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


func run() -> int:
	_test_round_trip()
	_test_stars_never_downgrade()
	_test_unlock_rule()
	_test_missing_file()
	_test_corrupt_file()
	_test_newer_version_not_clobbered()
	_test_settings()
	_test_hand_edited_file()
	_test_write_is_atomic()

	_cleanup()

	print("")
	if failures.is_empty():
		print("PASS  save: %d checks, 0 failures" % checks)
		return 0
	print("FAIL  save: %d checks, %d failures" % [checks, failures.size()])
	for f in failures:
		print("  x %s" % f)
	return failures.size()


# --- progress -----------------------------------------------------------------

func _test_round_trip() -> void:
	_suite("round trip")
	var path := _temp_path()

	var a = SaveDataScript.new(path)
	a.record_clear(1, 3)
	a.record_clear(2, 1)
	a.record_clear(7, 2)
	_check(a.save_game(), "save_game() reports success")

	var b = SaveDataScript.new(path)
	_check(b.load_game(), "load_game() finds the file it just wrote")
	_eq(b.stars_for(1), 3, "level 1 keeps 3 stars across a reload")
	_eq(b.stars_for(2), 1, "level 2 keeps 1 star across a reload")
	_eq(b.stars_for(7), 2, "level 7 keeps 2 stars across a reload")
	_check(b.is_cleared(7), "level 7 is still cleared after a reload")
	_eq(b.cleared_count(), 3, "three levels cleared")
	_eq(b.total_stars(), 6, "six stars in total")

	# An untouched level reads as zero rather than erroring, so the map can ask about
	# any pool number without checking first.
	_eq(b.stars_for(24), 0, "an unplayed level has no stars")
	_check(not b.is_cleared(24), "an unplayed level is not cleared")


## The board can only award stars on a clear, but a player who replays a 3-star pool and
## stumbles must not lose the shells they already earned.
func _test_stars_never_downgrade() -> void:
	_suite("stars never downgrade")
	var s = SaveDataScript.new(_temp_path())

	s.record_clear(5, 3)
	s.record_clear(5, 1)
	_eq(s.stars_for(5), 3, "a worse replay does not take a shell back")

	s.record_clear(6, 1)
	s.record_clear(6, 3)
	_eq(s.stars_for(6), 3, "a better replay does upgrade the result")

	# Out-of-range values are clamped rather than stored, so a bug elsewhere cannot put a
	# fourth shell on the map.
	s.record_clear(8, 99)
	_eq(s.stars_for(8), 3, "stars are clamped to MAX_STARS")
	s.record_clear(9, -2)
	_eq(s.stars_for(9), 0, "negative stars clamp to zero")
	_check(s.is_cleared(9), "a zero-star clear is still a clear")


## Maren's rule: finishing pool N unlocks pool N+1 and nothing is gated on star count.
func _test_unlock_rule() -> void:
	_suite("unlock rule")
	var s = SaveDataScript.new(_temp_path())

	_check(s.is_unlocked(1), "pool 1 is open on a fresh save")
	_check(not s.is_unlocked(2), "pool 2 is locked before pool 1 is cleared")
	_eq(s.highest_unlocked(24), 1, "a fresh save reaches pool 1")

	# One star, the worst possible clear, still opens the next pool: stars are for the
	# player, never a lock.
	s.record_clear(1, 1)
	_check(s.is_unlocked(2), "a 1-star clear of pool 1 opens pool 2")
	_check(not s.is_unlocked(3), "pool 3 stays locked")
	_eq(s.highest_unlocked(24), 2, "highest_unlocked follows the chain")

	s.record_clear(2, 3)
	s.record_clear(3, 2)
	_eq(s.highest_unlocked(24), 4, "clearing 2 and 3 reaches pool 4")

	# Clearing a pool out of order does not open a hole further down the beach: 6 is still
	# gated on 5, which nobody has finished.
	s.record_clear(10, 3)
	_check(not s.is_unlocked(6), "an out-of-order clear does not unlock the chain behind it")
	_check(s.is_unlocked(11), "but it does open the pool right after it")
	_eq(s.highest_unlocked(24), 11, "highest_unlocked reports the furthest open pool")


# --- robustness ---------------------------------------------------------------

## A new player is the common case, not an error case.
func _test_missing_file() -> void:
	_suite("missing file")
	var s = SaveDataScript.new(_temp_path())
	_check(not s.load_game(), "load_game() reports no file was read")
	_eq(s.stars_for(1), 0, "a fresh save has no stars")
	_check(s.is_unlocked(1), "pool 1 is open")
	_eq(s.get_volume(), 1.0, "volume falls back to the default")


## The file lives in user:// where a disk full, a crash or a curious player can mangle it.
## Opening on an error dialog is not acceptable for a cozy game, so it reads as fresh.
func _test_corrupt_file() -> void:
	_suite("corrupt file")
	for junk in ["", "{ not json", "null", "[1,2,3]", "\"a string\""]:
		var path := _temp_path()
		_write(path, junk)
		var s = SaveDataScript.new(path)
		_check(not s.load_game(), "%s does not load as a save" % JSON.stringify(junk))
		_eq(s.stars_for(1), 0, "%s leaves no progress behind" % JSON.stringify(junk))
		# and it must be recoverable: the next save overwrites the junk
		s.record_clear(1, 2)
		_check(s.save_game(), "a corrupt file can be overwritten by the next save")
		var reread = SaveDataScript.new(path)
		_check(reread.load_game(), "the rewritten file loads")
		_eq(reread.stars_for(1), 2, "the rewritten file has the new progress")


## A player who runs a newer build and then an older one must not have the newer save
## truncated to whatever this version understands.
func _test_newer_version_not_clobbered() -> void:
	_suite("newer version")
	var path := _temp_path()
	var future := '{"version": 99, "levels": {"1": {"stars": 3, "cleared": true}}, "settings": {"volume": 0.5}}'
	_write(path, future)

	var s = SaveDataScript.new(path)
	_check(s.load_game(), "a newer save still parses")
	_check(s.read_only, "a newer save is flagged read_only")
	_eq(s.loaded_version, 99, "the on-disk version is remembered")
	# What it can read, it reads -- the player still sees their progress.
	_eq(s.stars_for(1), 3, "readable progress is still shown")

	s.record_clear(2, 3)
	_check(not s.save_game(), "save_game() refuses to write over a newer save")
	_eq(_read(path), future, "the file on disk is byte-identical afterwards")


func _test_settings() -> void:
	_suite("settings")
	var path := _temp_path()
	var a = SaveDataScript.new(path)
	_eq(a.get_volume(), 1.0, "volume defaults to full")
	_check(not a.get_fullscreen(), "fullscreen defaults to off")

	a.set_volume(0.25)
	a.set_fullscreen(true)
	a.save_game()

	var b = SaveDataScript.new(path)
	b.load_game()
	_eq(b.get_volume(), 0.25, "volume survives a reload")
	_check(b.get_fullscreen(), "fullscreen survives a reload")

	# The settings screen uses a slider, so out-of-range values are clamped at the door
	# rather than trusted and written out.
	b.set_volume(4.0)
	_eq(b.get_volume(), 1.0, "volume above 1 clamps")
	b.set_volume(-1.0)
	_eq(b.get_volume(), 0.0, "volume below 0 clamps")


## Every field is coerced on the way in, so one mangled entry costs that entry and not the
## whole save.
func _test_hand_edited_file() -> void:
	_suite("hand-edited file")
	var path := _temp_path()
	_write(path, '{"version": 1, "levels": {' \
		+ '"1": {"stars": 99, "cleared": true},' \
		+ '"2": "not a dictionary",' \
		+ '"3": {"stars": 2},' \
		+ '"0": {"stars": 3, "cleared": true},' \
		+ '"-4": {"stars": 3, "cleared": true},' \
		+ '"5": {"stars": 0, "cleared": false},' \
		+ '"6": {"stars": 1, "cleared": true}' \
		+ '}, "settings": {"volume": "loud"}}')

	var s = SaveDataScript.new(path)
	_check(s.load_game(), "a hand-edited file still loads")
	_eq(s.stars_for(1), 3, "an impossible star count is clamped, not believed")
	_eq(s.stars_for(2), 0, "a non-dictionary entry is skipped")
	_eq(s.stars_for(3), 2, "stars without a cleared flag still count")
	_check(s.is_cleared(3), "and imply the level was cleared -- stars require finishing")
	_check(not s.is_cleared(0), "level 0 does not exist and is dropped")
	_check(not s.is_cleared(-4), "a negative level number is dropped")
	_check(not s.is_cleared(5), "an all-zero entry is dropped rather than stored")
	_eq(s.stars_for(6), 1, "the valid entries around the junk survive")
	# "loud" is not a number; float() makes it 0.0 rather than crashing, and it clamps in range.
	_check(s.get_volume() >= 0.0 and s.get_volume() <= 1.0, "a junk volume stays in range")


## A crash midway through a write should cost the last save, not every star earned. The
## real file is only ever replaced by a rename of a fully-written temp file.
func _test_write_is_atomic() -> void:
	_suite("atomic write")
	var path := _temp_path()
	var s = SaveDataScript.new(path)
	s.record_clear(1, 3)
	_check(s.save_game(), "save succeeds")
	_check(FileAccess.file_exists(path), "the save file exists")
	_check(not FileAccess.file_exists(path + SaveDataScript.TMP_SUFFIX),
		"no temp file is left behind")

	# Saving twice over an existing file must also work -- the rename has to replace, not fail.
	s.record_clear(2, 2)
	_check(s.save_game(), "a second save replaces the first")
	var b = SaveDataScript.new(path)
	b.load_game()
	_eq(b.stars_for(2), 2, "the second save's progress is on disk")
	_eq(b.stars_for(1), 3, "and the first save's progress is still there")
