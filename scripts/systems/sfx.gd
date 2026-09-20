extends Node
## One-shot sound effects. A small pool of players, added as a child of whatever wants to
## make noise.
##
## EVERYTHING GOES THROUGH THE MASTER BUS, and that is the whole integration with settings:
## the volume control and the mute in settings_panel.gd set the master bus, so every sound
## here is attenuated and silenced by the player's choice without any per-sound plumbing.
## There must never be a second volume path -- see `tidepool-ui-systems`.
##
## A missing file warns once and plays nothing. The game has to keep working for anyone who
## has not pulled the audio assets, and a silent build is a far better failure than a crash.

const DIR := "res://assets/audio/sfx"

## Enough voices that a fast player clicking through a solution never cuts their own last
## rotation off. Four is the smallest number that sounded like overlapping clicks rather
## than a stutter when I replayed a level's solution at speed.
const VOICES := 4

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_voice := 0

## base name -> the variant index played last, so the picker can avoid repeating it.
var _last_variant: Dictionary = {}

var _warned: Dictionary = {}

## Dedicated looping players; see start_ambience.
var _ambience: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for _i in VOICES:
		var p := AudioStreamPlayer.new()
		# Named explicitly rather than left to the default: this is the bus settings drives,
		# and saying so here is what makes the link greppable from either end.
		p.bus = "Master"
		add_child(p)
		_players.append(p)


## KNOWN, AND MINE: a tool that ends with SceneTree.quit() now prints "ObjectDB instances
## leaked at exit" and "1 resources still in use at exit". It appeared with this file --
## main prints neither -- and it is a shutdown-order complaint, not a failure: every gate
## still exits 0. Clearing the cache and nulling every player's stream in _exit_tree did NOT
## silence it, so _exit_tree is not running before Godot audits, and I have stopped guessing
## rather than leave code that pretends to fix it. Flagged so nobody hunts it as a
## regression. Worth a proper look when the audio work settles.


## Looping ambience, started ONCE and never restarted (Tern, C6). Kept on its own players
## rather than the one-shot pool, which round-robins and would cut a loop off mid-breath.
##
## The two beds are DIFFERENT LENGTHS on purpose and must not be synced: 24s and 37s drift
## against each other so the beach never repeats on a loop the ear can catch.
func start_ambience(sounds: Array) -> void:
	# Idempotent by design. The shell calls this on entry, and entry happens again on every
	# scene swap -- restarting the waves each time the player opens the map would be exactly
	# the seam C6 says must not exist.
	if not _ambience.is_empty():
		return
	for sound in sounds:
		var stream := _stream(str(sound))
		if stream == null:
			continue
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.stream = stream
		add_child(p)
		p.play()
		_ambience.append(p)


func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path := "%s/%s.wav" % [DIR, sound]
	if not ResourceLoader.exists(path):
		if not _warned.has(sound):
			_warned[sound] = true
			push_warning("sfx: no such sound %s" % path)
		return null
	var stream: AudioStream = load(path)
	_streams[sound] = stream
	return stream


## Play a sound by name. Round-robins the voices so a new sound never cuts off the one
## before it.
func play(sound: String) -> void:
	var stream := _stream(sound)
	if stream == null or _players.is_empty():
		return
	var player := _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = stream
	player.play()


## Play one of `<base>_1` .. `<base>_<count>`, never the same one twice running.
func play_variant(base: String, count: int) -> void:
	var i := pick_variant(base, count)
	if i > 0:
		play("%s_%d" % [base, i])


## The choice itself, kept pure and separate from playing so it can be tested without an
## audio device or a scene tree. Returns a 1-based index, or 0 when there is nothing to pick.
##
## Tern's rule: never the same variant twice in a row. With three files that is the
## difference between a texture and a tic.
func pick_variant(base: String, count: int) -> int:
	if count <= 0:
		return 0
	if count == 1:
		_last_variant[base] = 1
		return 1
	var last: int = _last_variant.get(base, 0)
	var i := last
	while i == last:
		i = randi_range(1, count)
	_last_variant[base] = i
	return i
