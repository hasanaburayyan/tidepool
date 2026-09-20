extends SceneTree
## Bakes the beach-map layout JSON into scripts/ui/map_layout.gd.
##
##   godot --headless --path . --script res://tools/bake_layout.gd
##
## WHY THIS EXISTS: every preset in export_presets.cfg carries
## exclude_filter="*.json, tools/*, tests/*", so assets/map/layout.json is NOT in an
## exported build. A map that reads the .json directly works perfectly in the editor and
## ships with twenty-four pools stacked at the origin. Adding an include_filter would also
## work, but then the data is only as safe as a filter nobody looks at again; baking makes
## the layout a script, and scripts are always exported.
##
## The .json stays the source of truth -- Cove regenerates it from the art pipeline. Run
## this after any layout change and commit the generated file.
##
## Two inputs, because they have two different owners:
##   assets/map/layout.json        Cove's 24 pools, full pixel positions
##   assets/map/layout_bonus.json  the 25-28 basin block, centres only (Maren's call)

const LAYOUT := "res://assets/map/layout.json"
const BONUS := "res://assets/map/layout_bonus.json"
const OUT := "res://scripts/ui/map_layout.gd"

# Sprite geometry, measured from the art in assets/map/. Used to derive shell and digit
# positions for pools that only give a centre.
const POOL_SIZE := Vector2i(88, 60)
const SHELL_PITCH := 18
const SHELL_DY := -32
const DIGIT_W := 12
const DIGIT_PITCH := 16
const DIGIT_DY := -8


func _initialize() -> void:
	var pools: Array = []
	var failures := 0

	var base: Dictionary = _read_json(LAYOUT)
	if base.is_empty():
		quit(1)
		return
	var size: Array = base.get("size", [960, 640])

	# Cove's entries are baked exactly as authored, not re-derived: if she hand-tweaks a
	# shell to clear a rock in the art, that tweak has to survive the bake. The derivation
	# is still checked against every one of them, so a drift shows up here rather than as a
	# shell floating off a pool three PRs later.
	for entry in base.get("pools", []):
		var pool: Dictionary = entry
		var centre := Vector2i(int(pool["x"]), int(pool["y"]))
		var level := int(pool["level"])
		var derived := _derive(level, centre)
		for key in ["pool", "shells", "digits"]:
			# Compared as ints: JSON has no integer type, so every coordinate arrives as a
			# float and a string compare would report 74.0 != 74 for all 24 pools.
			if _norm(pool.get(key, [])) != _norm(derived[key]):
				print("WARN level %d: authored %s %s, derived %s"
					% [level, key, _norm(pool.get(key, [])), _norm(derived[key])])
				failures += 1
		pools.append(_entry(level, centre, pool["pool"], pool["shells"], pool["digits"], false))

	# The bonus block gives centres only. Everything else is derived, so moving a bonus pool
	# is one pair of numbers rather than eight.
	var bonus: Dictionary = _read_json(BONUS)
	for entry in bonus.get("pools", []):
		var pool: Dictionary = entry
		var centre := Vector2i(int(pool["x"]), int(pool["y"]))
		var level := int(pool["level"])
		var d := _derive(level, centre)
		pools.append(_entry(level, centre, d["pool"], d["shells"], d["digits"], true))

	pools.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	_check_overlaps(pools)

	var text := _render(size, pools)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("FAIL cannot write %s" % OUT)
		quit(1)
		return
	f.store_string(text)
	f.close()

	print("baked %d pools (%d bonus) -> %s%s" % [
		pools.size(), bonus.get("pools", []).size(), OUT,
		"" if failures == 0 else "   (%d derivation warnings)" % failures])
	quit(0)


## A nested coordinate list flattened to ints, so authored and derived values compare on
## their numbers rather than on how JSON happened to spell them.
func _norm(v: Variant) -> Array:
	var out: Array = []
	for item in (v as Array):
		if item is Array:
			out.append(_norm(item))
		else:
			out.append(int(item))
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		print("WARN %s not found" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		print("FAIL %s is not a JSON object" % path)
		return {}
	return parsed as Dictionary


## Where the sprites go for a pool centred at `centre`. Reproduces Cove's authored numbers
## exactly for all 24 of hers, which is what makes it safe to use for the bonus block.
func _derive(level: int, centre: Vector2i) -> Dictionary:
	var shells: Array = []
	for i in 3:
		shells.append([centre.x - 28 + SHELL_PITCH * i, centre.y + SHELL_DY])
	var digit_count := str(level).length()
	var total := DIGIT_PITCH * digit_count - (DIGIT_PITCH - DIGIT_W)
	var digits: Array = []
	for i in digit_count:
		digits.append([centre.x - total / 2 + DIGIT_PITCH * i, centre.y + DIGIT_DY])
	return {
		"pool": [centre.x - POOL_SIZE.x / 2, centre.y - POOL_SIZE.y / 2],
		"shells": shells,
		"digits": digits,
	}


func _entry(level: int, centre: Vector2i, pool: Variant, shells: Variant, digits: Variant,
		bonus: bool) -> Dictionary:
	return {"level": level, "x": centre.x, "y": centre.y,
		"pool": pool, "shells": shells, "digits": digits, "bonus": bonus}


## Two pools sharing pixels is a hit-testing bug the player meets as "I clicked 26 and got
## 27". Cheaper to catch here than in a screenshot.
func _check_overlaps(pools: Array) -> void:
	for i in pools.size():
		for j in range(i + 1, pools.size()):
			var a: Array = pools[i]["pool"]
			var b: Array = pools[j]["pool"]
			var ra := Rect2i(Vector2i(int(a[0]), int(a[1])), POOL_SIZE)
			var rb := Rect2i(Vector2i(int(b[0]), int(b[1])), POOL_SIZE)
			if ra.intersects(rb):
				print("WARN pools %d and %d overlap on screen (%s vs %s)"
					% [pools[i]["level"], pools[j]["level"], ra, rb])


func _render(size: Array, pools: Array) -> String:
	var lines := PackedStringArray()
	lines.append("class_name MapLayout")
	lines.append("extends RefCounted")
	lines.append("## GENERATED FILE -- do not edit by hand.")
	lines.append("##")
	lines.append("## Baked from assets/map/layout.json and assets/map/layout_bonus.json by")
	lines.append("## tools/bake_layout.gd. Edit those and re-run the tool:")
	lines.append("##")
	lines.append("##   godot --headless --path . --script res://tools/bake_layout.gd")
	lines.append("##")
	lines.append("## It is baked rather than read at runtime because export_presets.cfg excludes")
	lines.append("## *.json from every preset, so the .json is not present in a shipped build.")
	lines.append("")
	lines.append("const SIZE := Vector2i(%d, %d)" % [int(size[0]), int(size[1])])
	lines.append("")
	lines.append("## Pool sprite size in pixels; also the click target for a pool.")
	lines.append("const POOL_SIZE := Vector2i(%d, %d)" % [POOL_SIZE.x, POOL_SIZE.y])
	lines.append("")
	lines.append("const POOLS := [")
	for p in pools:
		lines.append("\t{\"level\": %d, \"x\": %d, \"y\": %d, \"pool\": %s, \"shells\": %s, \"digits\": %s, \"bonus\": %s},"
			% [p["level"], p["x"], p["y"], _ints(p["pool"]), _pairs(p["shells"]),
				_pairs(p["digits"]), "true" if p["bonus"] else "false"])
	lines.append("]")
	lines.append("")
	return "\n".join(lines)


func _ints(a: Variant) -> String:
	return "[%d, %d]" % [int((a as Array)[0]), int((a as Array)[1])]


func _pairs(a: Variant) -> String:
	var out := PackedStringArray()
	for pair in (a as Array):
		out.append(_ints(pair))
	return "[%s]" % ", ".join(out)
