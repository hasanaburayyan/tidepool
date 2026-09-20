extends Node2D
## The title screen. Beach, the game's name, and one pool breathing under it.
##
## NO TEXT BUTTONS, deliberately. `tidepool-beach-map` is explicit that pool numbers are
## "the only text on the screen and the only text in the game besides the title", so a menu
## reading Play / Settings / Quit would break the one rule the whole presentation is built
## on. Any click or key begins -- which is what a cozy game wants anyway, and needs no
## instruction once the pool is visibly waiting for you.
##
## The lettering is placeholder, drawn with the fallback font, exactly as board.gd drew
## placeholder tiles before Cove's art landed. It is the obvious thing to replace with a
## real logo and the game reads fine until then.

signal play_requested()

## The way into settings. A glyph, not the word "Settings", for the no-text reason above.
##
## PROVISIONAL: Maren owns where this lives and I asked her on PR #63; this is the option I
## recommended (an icon on the title screen -- discoverable, one sprite, keeps the rule).
## It is one rect and one draw call, so moving it is cheap if she wants it elsewhere.
signal settings_requested()

## Bottom-right, away from the title and the pool, where it does not compete with either.
const SETTINGS_RECT := Rect2(884, 564, 44, 44)

const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")

const ART_DIR := "res://assets/map"

const TITLE := "Tidepool"
const TITLE_SIZE := 72

## Deep Umber, the same ink the pool numbers use.
const INK := Color("3a2f26")

## Dry Sand. The settings glyph sits in the water band, the lowest-contrast corner of the
## screen, and drawn in ink it was almost invisible (Maren). The fix is contrast, not size
## and not a label -- sand on water, with an ink rim for the same lift the critters get.
const GLYPH := Color("d9bf8f")

## One breath every BREATH_TIME seconds. Slow: the title screen should look like it is
## waiting patiently, not like it wants something.
const BREATH_TIME := 3.2
const BREATH_PIXELS := 3.0

@onready var _font: Font = ThemeDB.fallback_font

var _beach: Texture2D
var _pool: Texture2D
var _t := 0.0


func _ready() -> void:
	_beach = _load("beach")
	# The unplayed pool, not the finished one: the title screen is the game before you have
	# done anything to it.
	_pool = _load("pool_open")


func _load(name: String) -> Texture2D:
	var path := "%s/%s.png" % [ART_DIR, name]
	return load(path) if ResourceLoader.exists(path) else null


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var began := false
	if event is InputEventMouseButton and event.pressed:
		# Checked before "any click begins", or the settings glyph is unreachable: the
		# click that lands on it would start the game instead.
		if SETTINGS_RECT.has_point(event.position):
			settings_requested.emit()
			get_viewport().set_input_as_handled()
			return
		began = true
	elif event is InputEventKey and event.pressed and not event.echo:
		# Escape means leave, not begin. "Any key starts" swallowed it here, so the shell's
		# Escape chain -- pool, map, title, quit -- silently lost its last link and the only
		# way out of the game was the window close button. (Found by Nerite, TIDE-49.)
		began = event.keycode != KEY_ESCAPE
	if began:
		play_requested.emit()
		# Consumed, or the same click carries through to the map underneath and opens
		# whichever pool happens to sit under the cursor. The shell hit this twice already.
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var size := Vector2(MapLayout.SIZE)
	if _beach != null:
		draw_texture(_beach, Vector2.ZERO)

	# Sitting high on the dry sand, where the art has nothing else going on.
	var width := _font.get_string_size(TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
	draw_string(_font, Vector2((size.x - width) * 0.5, 200), TITLE,
		HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, INK)

	if _pool != null:
		# Breathing on a sine: the tide coming in and out, and the only thing on this
		# screen that moves.
		var lift := sin(_t / BREATH_TIME * TAU) * BREATH_PIXELS
		var pos := Vector2((size.x - _pool.get_width()) * 0.5, 380.0 + lift)
		draw_texture(_pool, pos.round())

	_draw_settings_glyph()


## Drawn twice: an ink copy offset by a pixel as a rim, then the sand glyph on top. Same
## shape the settings panel uses to close itself, so open and close read as one control.
func _draw_settings_glyph() -> void:
	SettingsPanel.draw_glyph(self, Rect2(SETTINGS_RECT.position + Vector2.ONE,
		SETTINGS_RECT.size), INK)
	SettingsPanel.draw_glyph(self, SETTINGS_RECT, GLYPH)
