extends Node2D
## Entry scene for Tidepool. Replace with the real game; keep `get_title()` for the smoke test.


func get_title() -> String:
	return "Tidepool"


func _ready() -> void:
	$Title.text = "%s — hello" % get_title()
