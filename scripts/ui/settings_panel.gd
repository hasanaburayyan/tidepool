extends Node2D
## Settings: volume and fullscreen. Two rows, no words.
##
## NO TEXT, for the same reason the title screen has no buttons: pool numbers and the game's
## name are the only text in Tidepool (tidepool-beach-map). So each row is a glyph that says
## what it controls and a state you can read at a glance.
##
## Volume is COUNTED, NOT MEASURED -- five drops, filled or empty, the same reasoning Maren
## gave for the shells on the map. Counting five objects is instant; judging how full a bar
## is takes a beat, and a bar would also need a number to be precise.
##
## Everything here is drawn placeholder art, the way board.gd drew tiles before Cove's
## sprites landed. It is honest about being provisional and it is the obvious thing to
## replace.

signal closed()

const SAND := Color("d9bf8f")
const PANEL := Color("e8d5ad")
const INK := Color("3a2f26")
const WATER := Color("2e8b9a")
const DIM := Color(0.15, 0.12, 0.10, 0.55)

const STEPS := 5

## Sat at y=200 and cut the wordmark through the middle, which made the title read as
## damaged (Maren). Dropped clear of it: "Tidepool" is drawn on a baseline at y=200, so
## anything above ~y=220 collides with the descenders.
const PANEL_RECT := Rect2(280, 250, 400, 240)

var save: RefCounted

var _drops: Array[Rect2] = []
var _speaker := Rect2()
var _screen := Rect2()
var _close := Rect2()


func _ready() -> void:
	_layout()


func _layout() -> void:
	_speaker = Rect2(PANEL_RECT.position + Vector2(40, 60), Vector2(40, 40))
	_drops.clear()
	for i in STEPS:
		_drops.append(Rect2(PANEL_RECT.position + Vector2(110 + i * 52, 64), Vector2(36, 32)))
	_screen = Rect2(PANEL_RECT.position + Vector2(40, 150), Vector2(56, 44))
	# The same glyph that opened the panel, top-right, closes it. Maren: the way out has to
	# be visible, not just Escape -- "both, not either". Reusing the opening glyph means the
	# player is clicking the thing they already associate with this screen.
	_close = Rect2(PANEL_RECT.end - Vector2(56, 232), Vector2(40, 40))


# --- input ----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_close_panel()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var point: Vector2 = event.position

	if _close.has_point(point):
		_close_panel()
		return

	# The speaker glyph is mute: the only way to reach zero, since the leftmost drop is one
	# step and not silence.
	if _speaker.has_point(point):
		_set_volume(0.0)
		return
	for i in _drops.size():
		if _drops[i].has_point(point):
			_set_volume(float(i + 1) / float(STEPS))
			return
	if _screen.has_point(point):
		_set_fullscreen(not save.get_fullscreen())
		return

	# A click anywhere off the panel closes it -- the usual way out of a dialog, and it
	# needs no button to say so.
	if not PANEL_RECT.has_point(point):
		_close_panel()


func _close_panel() -> void:
	closed.emit()
	# Consumed for the same reason every other screen here consumes its dismissing event:
	# this node stops taking input as a direct result of it, so otherwise the same click or
	# keypress lands on the title underneath and starts the game.
	get_viewport().set_input_as_handled()


# --- applying -------------------------------------------------------------------------

## Applied live and written immediately. A settings screen that only takes effect on the
## way out makes the player guess whether it worked.
func _set_volume(v: float) -> void:
	save.set_volume(v)
	apply_volume(save.get_volume())
	save.save_game()
	queue_redraw()


func _set_fullscreen(on: bool) -> void:
	save.set_fullscreen(on)
	apply_fullscreen(save.get_fullscreen())
	save.save_game()
	queue_redraw()


## Static so the app shell can apply the same settings on startup without a panel existing.
##
## NOTE: Tidepool has no audio yet -- there is not one sound file in assets/ -- so this
## changes nothing you can hear today. It is wired to the master bus so that it is already
## correct when audio arrives, and so the value is being exercised rather than merely
## stored. Do not report "volume works" from a playtest; there is nothing to hear.
static func apply_volume(v: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, v <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))


static func apply_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN
		if on else DisplayServer.WINDOW_MODE_WINDOWED)


# --- drawing --------------------------------------------------------------------------

func _draw() -> void:
	# The screen behind stays visible through the dim, so settings reads as a layer over the
	# game rather than a different place.
	draw_rect(Rect2(Vector2.ZERO, Vector2(MapLayout.SIZE)), DIM)
	draw_rect(PANEL_RECT, PANEL)
	draw_rect(PANEL_RECT, INK, false, 2.0)

	_draw_speaker(_speaker, save.get_volume() <= 0.0)
	var filled := int(round(save.get_volume() * STEPS))
	for i in _drops.size():
		_draw_drop(_drops[i], i < filled)

	_draw_screen_glyph(_screen, save.get_fullscreen())
	draw_glyph(self, _close, INK)


## A speaker: a box and a cone. Crossed out when muted, which is the one convention strong
## enough to carry without a word next to it.
func _draw_speaker(rect: Rect2, muted: bool) -> void:
	var c := rect.get_center()
	draw_rect(Rect2(rect.position.x, c.y - 7, 14, 14), INK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(rect.position.x + 14, c.y - 7),
		Vector2(rect.position.x + 30, rect.position.y),
		Vector2(rect.position.x + 30, rect.end.y),
		Vector2(rect.position.x + 14, c.y + 7),
	]), INK)
	if muted:
		draw_line(rect.position + Vector2(6, 6), rect.end - Vector2(2, 6), INK, 3.0)


## One unit of volume. Filled is water, empty is an outline -- the same filled/outlined
## vocabulary the map's shells use, so the two screens read the same way.
func _draw_drop(rect: Rect2, filled: bool) -> void:
	# Earned = filled with water. Unearned = still there, still the same shape, outlined in
	# Deep Umber -- NEVER a gap. Exactly the shells vocabulary (Maren): if the empty steps
	# vanished, the player would be measuring a bar's length again instead of counting five
	# objects, which is the whole reason this is not a slider.
	if filled:
		draw_rect(rect, WATER)
	draw_rect(rect, INK, false, 2.0)


## A screen. Filled means fullscreen; the small inset rectangle means windowed, which is
## literally what the two states look like.
func _draw_screen_glyph(rect: Rect2, on: bool) -> void:
	draw_rect(rect, WATER if on else SAND)
	draw_rect(rect, INK, false, 2.0)
	if not on:
		draw_rect(Rect2(rect.position + Vector2(10, 8), rect.size - Vector2(20, 16)), INK, false, 2.0)


## The settings glyph: three slider rows with the knob in a different place on each, which
## is what makes it read as "settings" rather than as a menu icon. Shared with the title
## screen so the thing that opens the panel and the thing that closes it are the same shape.
## Placeholder; a real icon is one sprite from Cove and the hit target does not move.
static func draw_glyph(canvas: CanvasItem, r: Rect2, colour: Color) -> void:
	for i in 3:
		var y := r.position.y + 12 + i * 10
		canvas.draw_line(Vector2(r.position.x + 6, y), Vector2(r.end.x - 6, y), colour, 2.0)
		canvas.draw_rect(Rect2(r.position.x + 10 + i * 9, y - 4, 6, 8), colour)
