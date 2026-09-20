#!/usr/bin/env python3
"""Procedural Tidepool SFX. Deterministic (fixed seeds). Run: python3 audio/gen_sfx.py
Writes 16-bit mono 44.1k WAVs to audio/sfx/. Parameters live in PARAMS."""
import wave, pathlib
import numpy as np

SR = 44100
OUT = pathlib.Path(__file__).parent / "sfx"

# Peak targets in dBFS. The rescue chime (later) sits at -6; nothing is louder.
PARAMS = {
    "click": {"peak_db": -15.0, "variants": 3, "freqs": [610, 655, 575], "len": 0.075},
    "thunk": {"peak_db": -13.0, "freq": 118, "len": 0.20},
}

def lp(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x); s = 0.0
    for i, v in enumerate(x):
        s = (1 - a) * v + a * s; y[i] = s
    return y

def norm(x, peak_db):
    return x / np.max(np.abs(x)) * 10 ** (peak_db / 20)

def fade(x, ms=3):
    n = int(SR * ms / 1000); x[:n] *= np.linspace(0, 1, n); x[-n:] *= np.linspace(1, 0, n); return x

def click(i):
    p = PARAMS["click"]; rng = np.random.default_rng(100 + i)
    t = np.arange(int(SR * p["len"])) / SR
    f = p["freqs"][i]
    # soft pebble-on-wood tick: two decaying partials, rounded noise transient, no hard edge
    tone = np.sin(2*np.pi*f*t) * np.exp(-t*55) + 0.35*np.sin(2*np.pi*f*2.4*t) * np.exp(-t*90)
    noise = lp(rng.standard_normal(len(t)), 2500) * np.exp(-t*160) * 0.5
    x = tone + noise
    x[:int(SR*0.002)] *= np.linspace(0, 1, int(SR*0.002))  # 2ms attack, no click artifact
    return fade(norm(x, p["peak_db"]))

def thunk():
    p = PARAMS["thunk"]; rng = np.random.default_rng(7)
    t = np.arange(int(SR * p["len"])) / SR
    # flat pitch (a falling pitch would read as a rebuke), soft attack, low-passed: a hand on a sandbag
    x = np.sin(2*np.pi*p["freq"]*t) * np.exp(-t*24)
    x += 0.3 * lp(rng.standard_normal(len(t)), 500) * np.exp(-t*50)
    x[:int(SR*0.006)] *= np.linspace(0, 1, int(SR*0.006))
    return fade(norm(x, p["peak_db"]), 8)

def write(name, x):
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())

OUT.mkdir(exist_ok=True)
for i in range(PARAMS["click"]["variants"]): write(f"rotate_click_{i+1}", click(i))
write("locked_thunk", thunk())
for f in sorted(OUT.glob("*.wav")):
    d = np.frombuffer(wave.open(str(f)).readframes(10**7), np.int16) / 32768
    print(f.name, f"{len(d)/SR*1000:.0f}ms peak {20*np.log10(abs(d).max()):.1f}dBFS rms {20*np.log10(np.sqrt((d**2).mean())):.1f}dBFS")
