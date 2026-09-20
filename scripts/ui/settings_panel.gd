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

## Emitted on any control in the panel, so the shell can click without the panel owning a
## player of its own.
signal clicked()

const SAND := Color("d9bf8f")
const PANEL := Color("e8d5ad")
const INK := Color("3a2f26")
const WATER := Color("2e8b9a")
const DIM := Color(0.15, 0.12, 0.10, 0.55)

const STEPS := 5

## The quietest audible step, in dB below unattenuated. THE RETUNE KNOB: Maren deliberately
## gave no numbers because picking the curve is a listen judgement and neither of us can
## hear. Expect this to move once the board reports under D9.
##
## -20 dB over four gaps is 5 dB a step. Around 3 dB is the smallest difference a listener
## reliably notices in context, so 5 keeps all five steps distinguishable with headroom,
## and step 1 lands quiet but clearly present rather than as a second mute.
const MIN_VOLUME_DB := -20.0

## Sat at y=200 and cut the wordmark through the middle, which made the title read as
## damaged (Maren). Dropped clear of it: "Tidepool" is drawn on a baseline at y=200, so
## anything above ~y=220 collides with the descenders.
const PANEL_RECT := Rect2(280, 250, 400, 240)

## The settings glyph, TOP-RIGHT, on every screen (Maren). Bottom-right was only free on
## the title -- on the map that corner is pools 25-28. One corner everywhere beats the best
## corner on one screen. The panel deliberately does not cover it, so the glyph stays
## visible through the dim and clicking it again is what closes the panel.
const SETTINGS_RECT := Rect2(884, 20, 44, 44)

var save: RefCounted

var _drops: Array[Rect2] = []
var _speaker := Rect2()
var _screen := Rect2()


func _ready() -> void:
	_layout()


func _layout() -> void:
	_speaker = Rect2(PANEL_RECT.position + Vector2(40, 60), Vector2(40, 40))
	_drops.clear()
	for i in STEPS:
		_drops.append(Rect2(PANEL_RECT.position + Vector2(110 + i * 52, 64), Vector2(36, 32)))
	_screen = Rect2(PANEL_RECT.position + Vector2(40, 150), Vector2(56, 44))


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

	# The screen's own top-right glyph, still visible through the dim, closes the panel. A
	# second glyph inside the panel would just be the same control drawn twice (Maren).
	if SETTINGS_RECT.has_point(point):
		_close_panel()
		return

	# The speaker glyph is mute: the only way to reach zero, since the leftmost drop is one
	# step and not silence.
	if _speaker.has_point(point):
		clicked.emit()
		_set_volume(0.0)
		return
	for i in _drops.size():
		if _drops[i].has_point(point):
			clicked.emit()
			_set_volume(float(i + 1) / float(STEPS))
			return
	if _screen.has_point(point):
		clicked.emit()
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


## The bus level for a stored volume, spaced EVENLY IN DECIBELS.
##
## It used to space the five steps evenly in AMPLITUDE and then convert, which gave roughly
## -14, -8, -4.4, -1.9, 0 dB. Hearing is logarithmic, so steps 3, 4 and 5 sat within about
## 4 dB of each other and were nearly indistinguishable, while step 1 fell off a cliff:
## five positions, about three audible levels, and a hole at the bottom. (Maren, D9.)
##
## The drops are a COUNT of loudness. If three of them sound the same the count is lying,
## and a control the player moves with no effect is worse than no control at all -- the same
## reasoning as the shells on the map.
static func volume_db(v: float) -> float:
	var step := clampi(int(round(v * STEPS)), 0, STEPS)
	if step <= 0:
		return MIN_VOLUME_DB
	return MIN_VOLUME_DB * (1.0 - float(step - 1) / float(STEPS - 1))


## Static so the app shell can apply the same settings on startup without a panel existing.
##
## Mute and step 1 are DIFFERENT THINGS and must stay that way: mute is the crossed-out
## speaker, step 1 is "quiet but present". If step 1 were inaudible we would have shipped
## six states with two of them silence, and the first drop would be a dead entry in a count
## meant to be honest. (Maren.)
static func apply_volume(v: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, v <= 0.0)
	AudioServer.set_bus_volume_db(bus, volume_db(v))


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


## A screen, in two states. THE FRAME STAYS IN BOTH (Maren): dropping it for fullscreen
## turned the glyph into a solid teal block that no longer depicted a screen and read, at a
## glance, as a stray sixth volume drop that had wandered down a row. Only the inside
## changes -- an inset rectangle is windowed, filled to the frame's inner edge is
## fullscreen. Same object, two states, and the frame is what stops it colliding with the
## drops. Teal still means active, consistently with them.
func _draw_screen_glyph(rect: Rect2, on: bool) -> void:
	draw_rect(rect, SAND)
	var inner := Rect2(rect.position + Vector2(6, 6), rect.size - Vector2(12, 12))
	if on:
		draw_rect(inner, WATER)
	else:
		draw_rect(Rect2(rect.position + Vector2(12, 11), rect.size - Vector2(24, 22)), WATER)
	draw_rect(rect, INK, false, 2.0)


## The settings glyph: three slider rows with the knob in a different place on each, which
## is what makes it read as "settings" rather than as a menu icon. Shared with the title
## screen so the thing that opens the panel and the thing that closes it are the same shape.
## Placeholder; a real icon is one sprite from Cove and the hit target does not move.
static func draw_glyph(canvas: CanvasItem, r: Rect2, colour: Color) -> void:
	for i in 3:
		var y := r.position.y + 12 + i * 10
		canvas.draw_line(Vector2(r.position.x + 6, y), Vector2(r.end.x - 6, y), colour, 2.0)
		canvas.draw_rect(Rect2(r.position.x + 10 + i * 9, y - 4, 6, 8), colour)
