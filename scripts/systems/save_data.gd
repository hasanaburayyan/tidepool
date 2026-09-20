class_name SaveData
extends RefCounted
## Player progress, stars and settings, persisted to user:// as versioned JSON.
##
## Deliberately a RefCounted with an injectable path rather than an autoload singleton:
## tests/test_core.gd is a plain RefCounted with no SceneTree, so an autoload would be
## invisible to it. The game wires one instance up in the app shell; tests point their own
## instance at a temp file and never touch the player's real save.
##
## Nothing in here reads the simulation. The map renders its three pool states straight off
## this data, so this is the whole contract between "what the player has done" and the UI.

const DEFAULT_PATH := "user://tidepool_save.json"

## Bump when the on-disk shape changes, and add a migration in _migrate.
const VERSION := 1

const MAX_STARS := 3

## Written next to the real file and renamed over it, so a crash halfway through a write
## costs you the last save rather than every star you have ever earned.
const TMP_SUFFIX := ".tmp"

var path: String

## level number (1-based, matching the pool numbers on the map) -> {"stars": int, "cleared": bool}
var _levels: Dictionary = {}
var _settings: Dictionary = {}

## The version actually found on disk. Kept so callers can tell a fresh save from a migrated one.
var loaded_version := VERSION

## Set when the file on disk came from a NEWER build than this one. A player who opens an old
## build must not have their progress silently truncated to whatever this version understands,
## so we read what we can and refuse to write at all.
var read_only := false


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path
	_settings = _default_settings()


func _default_settings() -> Dictionary:
	return {"volume": 1.0, "fullscreen": false}


# --- progress -------------------------------------------------------------------------

## Record a finished level, keeping the player's best result. A replay that goes worse is
## still worth recording as cleared, but it never takes a shell back: stars are a trophy,
## not a current score (tidepool-beach-map -- "a pool you have finished never looks like a
## pool you have failed").
func record_clear(level_no: int, stars: int) -> void:
	var entry: Dictionary = _levels.get(level_no, {"stars": 0, "cleared": false})
	entry["stars"] = maxi(int(entry.get("stars", 0)), clampi(stars, 0, MAX_STARS))
	entry["cleared"] = true
	_levels[level_no] = entry


func stars_for(level_no: int) -> int:
	return _as_int((_levels.get(level_no, {}) as Dictionary).get("stars", 0), 0)


func is_cleared(level_no: int) -> bool:
	return _as_bool((_levels.get(level_no, {}) as Dictionary).get("cleared", false), false)


## Finishing pool N unlocks pool N+1, and nothing is gated on star count -- a cozy game does
## not make you replay a level to proceed (tidepool-beach-map, Maren's rule).
func is_unlocked(level_no: int) -> bool:
	if level_no <= 1:
		return true
	return is_cleared(level_no - 1)


## The furthest pool the player may open, which is where the map puts the camera on entry.
func highest_unlocked(level_count: int) -> int:
	var highest := 1
	for n in range(2, level_count + 1):
		if is_unlocked(n):
			highest = n
	return highest


func cleared_count() -> int:
	var n := 0
	for level_no in _levels:
		if is_cleared(level_no):
			n += 1
	return n


func total_stars() -> int:
	var n := 0
	for level_no in _levels:
		n += stars_for(level_no)
	return n


func reset_progress() -> void:
	_levels.clear()


# --- settings -------------------------------------------------------------------------

func get_volume() -> float:
	return clampf(_as_float(_settings.get("volume", 1.0), 1.0), 0.0, 1.0)


func set_volume(v: float) -> void:
	_settings["volume"] = clampf(v, 0.0, 1.0)


func get_fullscreen() -> bool:
	return _as_bool(_settings.get("fullscreen", false), false)


func set_fullscreen(on: bool) -> void:
	_settings["fullscreen"] = on


# --- persistence ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	# JSON object keys are always strings, so level numbers go out as strings and come back
	# through int() on load. Sorted so the file diffs readably when a human looks at it.
	var levels := {}
	var keys := _levels.keys()
	keys.sort()
	for level_no in keys:
		levels[str(level_no)] = {
			"stars": stars_for(level_no),
			"cleared": is_cleared(level_no),
		}
	return {"version": VERSION, "levels": levels, "settings": _settings.duplicate()}


# --- typed reads ----------------------------------------------------------------------
#
# JSON has no schema and this file lives in user://, so any field can hold any shape.
# int() and float() on an Array or Dictionary are runtime ERRORS in GDScript, not
# coercions, and bool() is the same. A raw int(entry["stars"]) therefore does not degrade
# on a hand-edited file -- it aborts from_dict partway, drops every entry after it, and
# then the next save_game() writes that truncated state back over the file. Losing a
# player's progress to one bad field is the exact failure this layer exists to prevent,
# so every read from the parsed dictionary goes through these. (Found by Nerite, TIDE-45.)


static func _as_int(v: Variant, fallback: int) -> int:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return int(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return int(str(v)) if str(v).is_valid_int() else fallback
	return fallback


static func _as_float(v: Variant, fallback: float) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return float(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return float(str(v)) if str(v).is_valid_float() else fallback
	return fallback


static func _as_bool(v: Variant, fallback: bool) -> bool:
	match typeof(v):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return bool(v)
		TYPE_STRING, TYPE_STRING_NAME:
			# Spelled out rather than bool(String), which is true for ANY non-empty string
			# and so reads the hand-written "false" as true -- the opposite of the intent.
			match str(v).strip_edges().to_lower():
				"true", "1", "yes", "on":
					return true
				"false", "0", "no", "off", "":
					return false
	return fallback


## Replace this save's contents from a parsed dictionary. Every field is coerced and
## clamped rather than trusted: this file lives in user:// where a player can hand-edit it,
## and a bad value should cost that one entry, not the whole save.
func from_dict(data: Dictionary) -> void:
	# A version that is not a number is not a newer version -- it is a broken field, and
	# treating it as newer would make the save read_only and lock the player out of saving.
	loaded_version = _as_int(data.get("version", 0), 0)
	read_only = loaded_version > VERSION

	_levels.clear()
	var levels: Variant = data.get("levels", {})
	if levels is Dictionary:
		for key in (levels as Dictionary):
			var level_no := int(str(key))
			if level_no <= 0:
				continue
			var entry: Variant = (levels as Dictionary)[key]
			if not (entry is Dictionary):
				continue
			var stars := clampi(_as_int((entry as Dictionary).get("stars", 0), 0), 0, MAX_STARS)
			var cleared := _as_bool((entry as Dictionary).get("cleared", false), false)
			# A level with stars but no cleared flag is a half-written or hand-edited entry;
			# earning a star is only possible by finishing, so believe the stars.
			if stars > 0:
				cleared = true
			if not cleared and stars == 0:
				continue
			_levels[level_no] = {"stars": stars, "cleared": cleared}

	_settings = _default_settings()
	var settings: Variant = data.get("settings", {})
	if settings is Dictionary:
		if (settings as Dictionary).has("volume"):
			set_volume(_as_float((settings as Dictionary)["volume"], 1.0))
		if (settings as Dictionary).has("fullscreen"):
			set_fullscreen(_as_bool((settings as Dictionary)["fullscreen"], false))

	_migrate()


## Bring an older on-disk shape up to VERSION. Nothing to do at version 1; the hook exists
## so the next change has an obvious place to go instead of growing conditionals in from_dict.
func _migrate() -> void:
	if loaded_version < VERSION:
		loaded_version = VERSION


## Returns true when a real save was read. A missing file is not an error -- it is a new
## player -- and neither is a corrupt one: we fall back to defaults and let the next save
## overwrite it, because a cozy puzzle game must never open on an error dialog.
func load_game() -> bool:
	_levels.clear()
	_settings = _default_settings()
	loaded_version = VERSION
	read_only = false

	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("save: cannot read %s (%d); starting fresh" % [path, FileAccess.get_open_error()])
		return false
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("save: %s is not valid JSON; starting fresh" % path)
		return false

	from_dict(parsed as Dictionary)
	return true


## Returns true when the file was written. Refuses when the save on disk is from a newer
## version: see read_only.
func save_game() -> bool:
	if read_only:
		push_warning("save: %s is version %d, newer than this build (%d); not overwriting it"
			% [path, loaded_version, VERSION])
		return false

	var tmp := path + TMP_SUFFIX
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("save: cannot write %s (%d)" % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()

	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		push_warning("save: cannot open %s" % path.get_base_dir())
		return false
	var err := dir.rename(tmp, path)
	if err != OK:
		push_warning("save: cannot move %s into place (%d)" % [tmp, err])
		return false
	return true
