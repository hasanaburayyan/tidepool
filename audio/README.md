# Tidepool audio

All sounds are synthesized in-house (numpy DSP, no samples, no downloads). Regenerate:

    python3 audio/gen_sfx.py      # needs python3 + numpy; deterministic (fixed seeds)

Parameters are in `PARAMS` at the top of the script. Output: 16-bit mono 44.1 kHz WAV in `assets/audio/sfx/`
(WAV chosen over OGG: tiny files, no encoder dependency, no import surprises).

## Mix ceiling
Nothing louder than the rescue chime (peak -3 dBFS). Ambience sits under everything.

| file | peak | note |
|---|---|---|
| rotate_click_1..3 | -9 dBFS | three pitch variants; **play round-robin/random-not-same-twice** so 1000s of moves don't repeat one waveform |
| rescue_chime | -3 dBFS | rising fifth + bubble blip; the only bright sound; fire the frame a critter's tile goes wet (C5) |
| locked_thunk | -8 dBFS | flat pitch (falling pitch reads as a rebuke), soft attack, low-passed |

## Hooking up (Limpet)
Route through the existing master bus. Click: pick a variant != last played. Also set
`pitch_scale = randf_range(0.97, 1.03)` if you like, but it's optional.

Thunk must not outlast the tile shake (0.25s, board.gd SHAKE_TIME); it is 0.20s. Click fires on every accepted rotation; thunk only on a click on a locked tile.

## Level-clear
`shell_plink.wav` (-7): once per shell fill, 0.2 s apart, 1-3 times. `clear_wave.wav` (-6, peaks 0.35 s in):
start it at `(shell_count-1)*0.2 s` so its peak lands just after the last shell; a one-shell clear starts it immediately.
Levels raised because step 1 is bus -14 dB (Nerite): a -15 dBFS click was -29 at step 1.

## Gate, basin, menu
- `gate_shut` (-9, 0.30s): soft slide then flat wooden thock; no falling pitch, no buzz. Fire when the sluice bar shuts, only while it is visible.
- `basin_held` (-10) / `basin_overflow` (-7): same body (seed, tone), held is low-passed and dull, overflow adds a rising bright wash. Fire on the frame the basin state is shown.
- `menu_click` (-11): soft tick for menu buttons.

## Ambience (wind cut by Maren)
`amb_waves.wav` (24 s, -18 dBFS peak) and `amb_gulls.wav` (37 s, -22 dBFS, 4 sparse calls that fully decay inside the loop).
Different, coprime-ish lengths so the pair does not audibly repeat together. Waves are FFT-filtered noise, circular by
construction, with three shallow integer-cycle modulations, so there is no seam and no swell to count. Loop in code:
set `AudioStreamWAV.loop_mode = LOOP_FORWARD` with loop_end = sample count (or set it in the .wav import). Play both
continuously across level and map (C6). Far below the chime: at step 1 (bus -14) waves peak about -32 dBFS; needs a listen.
