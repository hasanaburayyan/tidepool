# Tidepool audio

All sounds are synthesized in-house (numpy DSP, no samples, no downloads). Regenerate:

    python3 audio/gen_sfx.py      # needs python3 + numpy; deterministic (fixed seeds)

Parameters are in `PARAMS` at the top of the script. Output: 16-bit mono 44.1 kHz WAV in `assets/audio/sfx/`
(WAV chosen over OGG: tiny files, no encoder dependency, no import surprises).

## Mix ceiling
Nothing louder than the rescue chime (target peak -6 dBFS). Ambience sits under everything.

| file | peak | note |
|---|---|---|
| rotate_click_1..3 | -15 dBFS | three pitch variants; **play round-robin/random-not-same-twice** so 1000s of moves don't repeat one waveform |
| rescue_chime | -6 dBFS | rising fifth + bubble blip; the only bright sound; fire the frame a critter's tile goes wet (C5) |
| locked_thunk | -14.6 dBFS | flat pitch (falling pitch reads as a rebuke), soft attack, low-passed |

## Hooking up (Limpet)
Route through the existing master bus. Click: pick a variant != last played. Also set
`pitch_scale = randf_range(0.97, 1.03)` if you like, but it's optional.

Thunk must not outlast the tile shake (0.25s, board.gd SHAKE_TIME); it is 0.20s. Click fires on every accepted rotation; thunk only on a click on a locked tile.
