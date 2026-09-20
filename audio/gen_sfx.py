#!/usr/bin/env python3
"""Procedural Tidepool SFX. Deterministic (fixed seeds). Run: python3 audio/gen_sfx.py
Writes 16-bit mono 44.1k WAVs to audio/sfx/. Parameters live in PARAMS."""
import wave, pathlib
import numpy as np

SR = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"

# Peak targets in dBFS (raised so they read at volume step 1 = bus -14 dB). The rescue chime sits at -3; nothing is louder.
PARAMS = {
    "click": {"peak_db": -9.0, "variants": 3, "freqs": [610, 655, 575], "len": 0.075},
    "chime": {"peak_db": -3.0, "f1": 880, "f2": 1318.5, "len": 0.9},
    "plink": {"peak_db": -7.0, "freq": 1568, "len": 0.25},
    "wave": {"peak_db": -6.0, "len": 1.2, "peak_at": 0.35},
    "gate": {"peak_db": -9.0, "len": 0.30},
    "basin_held": {"peak_db": -10.0, "len": 0.35},
    "basin_overflow": {"peak_db": -7.0, "len": 0.9},
    "menu": {"peak_db": -11.0, "freq": 740, "len": 0.06},
    "amb_waves": {"peak_db": -18.0, "secs": 24},
    "thunk": {"peak_db": -8.0, "freq": 118, "len": 0.20},
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
    x = fade(x, 8)
    return norm(x, p["peak_db"])  # normalize last so file peak equals PARAMS

def write(name, x):
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())

def chime():
    p = PARAMS["chime"]; rng = np.random.default_rng(11)
    n = int(SR * p["len"]); x = np.zeros(n)
    # two bell notes (rising fifth = "yes", never falling) + a small bubble blip: bright, the only bright sound
    for start, f in ((0.0, p["f1"]), (0.11, p["f2"])):
        t = np.arange(n - int(start*SR)) / SR
        note = (np.sin(2*np.pi*f*t) + 0.3*np.sin(2*np.pi*f*2.01*t)*np.exp(-t*12)) * np.exp(-t*7)
        note[:int(SR*0.004)] *= np.linspace(0, 1, int(SR*0.004))
        x[int(start*SR):] += note
    t = np.arange(int(SR*0.09)) / SR
    bub = np.sin(2*np.pi*np.cumsum(500 + 2500*t)/SR) * np.exp(-t*40) * 0.25
    x[int(0.05*SR):int(0.05*SR)+len(bub)] += bub
    return fade(norm(x, p["peak_db"]), 30)

def plink():
    p = PARAMS["plink"]; t = np.arange(int(SR*p["len"])) / SR
    x = (np.sin(2*np.pi*p["freq"]*t) + 0.2*np.sin(2*np.pi*p["freq"]*2.7*t)*np.exp(-t*30)) * np.exp(-t*16)
    x[:int(SR*0.003)] *= np.linspace(0, 1, int(SR*0.003))
    return norm(fade(x, 20), p["peak_db"])

def wash():
    # one soft wash: rounded rise to peak_at, long fall; a single event, not a loop
    p = PARAMS["wave"]; rng = np.random.default_rng(23)
    t = np.arange(int(SR*p["len"])) / SR
    env = np.where(t < p["peak_at"], np.sin(0.5*np.pi*t/p["peak_at"])**2, np.exp(-(t-p["peak_at"])*3.2))
    x = lp(lp(rng.standard_normal(len(t)), 1800), 1800) * env
    return norm(fade(x, 40), p["peak_db"])

def _body(t, f=150, rng=None):
    """Shared 'water in a stone basin' body: soft low tone + low-passed noise. Flat pitch."""
    x = np.sin(2*np.pi*f*t) * np.exp(-t*9)
    x += 0.5 * lp(rng.standard_normal(len(t)), 420) * np.exp(-t*7)
    x[:int(SR*0.01)] *= np.linspace(0, 1, int(SR*0.01))
    return x

def gate():
    # sluice bar slides (soft scrape, rising in level not pitch) then settles with a flat wooden thock. Not a buzz.
    p = PARAMS["gate"]; rng = np.random.default_rng(31)
    t = np.arange(int(SR*p["len"])) / SR
    scrape = lp(rng.standard_normal(len(t)), 900) * np.sin(np.pi*np.clip(t/0.16, 0, 1))**2 * (t < 0.16) * 0.5
    ts = np.clip(t - 0.15, 0, None)
    thock = np.sin(2*np.pi*165*ts) * np.exp(-ts*26) * (t >= 0.15)
    thock[int(0.15*SR):int(0.155*SR)] *= np.linspace(0, 1, int(0.005*SR))
    return norm(fade(scrape + thock, 15), p["peak_db"])

def basin_held():
    p = PARAMS["basin_held"]; rng = np.random.default_rng(41)
    t = np.arange(int(SR*p["len"])) / SR
    return norm(fade(lp(_body(t, rng=rng), 600), 20), p["peak_db"])  # contained, dull

def basin_overflow():
    # SAME body (same seed, same tone) so the ear links the two states, plus a rising bright wash = release
    p = PARAMS["basin_overflow"]; rng = np.random.default_rng(41)
    t = np.arange(int(SR*p["len"])) / SR
    body = _body(t, rng=rng)
    wash = lp(np.random.default_rng(43).standard_normal(len(t)), 3500)
    wash = wash - lp(wash, 900)  # bright band
    env = np.sin(0.5*np.pi*np.clip(t/0.4, 0, 1))**2 * np.exp(-np.clip(t-0.4, 0, None)*3.5)
    return norm(fade(body + 1.4*wash*env, 40), p["peak_db"])

def menu():
    p = PARAMS["menu"]; t = np.arange(int(SR*p["len"])) / SR
    x = np.sin(2*np.pi*p["freq"]*t) * np.exp(-t*70)
    x[:int(SR*0.002)] *= np.linspace(0, 1, int(SR*0.002))
    return norm(fade(x, 5), p["peak_db"])

def _band_circular(x, lo, hi):
    """FFT band-pass: circular by construction, so a loop of this has no seam."""
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR)
    X *= ((f > lo) & (f < hi)) * (1 / (1 + (f / hi) ** 4))
    return np.fft.irfft(X, len(x))

def amb_waves():
    p = PARAMS["amb_waves"]; n = SR * p["secs"]; T = np.arange(n) / SR
    rng = np.random.default_rng(51)
    bed = _band_circular(rng.standard_normal(n), 120, 1800)
    # gentle irregular surf: LFOs with INTEGER cycles per loop (seam-free), shallow depth, none dominant (no swell to count)
    m = 1.0 + 0.10*np.sin(2*np.pi*(T/p["secs"])*5 + 0.7) + 0.08*np.sin(2*np.pi*(T/p["secs"])*8 + 2.1) + 0.05*np.sin(2*np.pi*(T/p["secs"])*13 + 4.0)
    return norm(bed * m, p["peak_db"])

OUT.mkdir(parents=True, exist_ok=True)
for i in range(PARAMS["click"]["variants"]): write(f"rotate_click_{i+1}", click(i))
write("locked_thunk", thunk())
write("rescue_chime", chime())
write("shell_plink", plink())
write("gate_shut", gate())
write("basin_held", basin_held())
write("basin_overflow", basin_overflow())
write("menu_click", menu())
(OUT.parent.parent.parent / "audio" / "fallback").mkdir(exist_ok=True)
# script waves are a non-shipping fallback: the shipping amb_waves.wav is audio/finish_ambience.py (board listen, P0)
FB = OUT.parent.parent.parent / "audio" / "fallback"; OUT, _fb = FB, OUT; write("amb_waves_script", amb_waves()); OUT = _fb
write("clear_wave", wash())
for f in sorted(OUT.glob("*.wav")):
    d = np.frombuffer(wave.open(str(f)).readframes(10**7), np.int16) / 32768
    print(f.name, f"{len(d)/SR*1000:.0f}ms peak {20*np.log10(abs(d).max()):.1f}dBFS rms {20*np.log10(np.sqrt((d**2).mean())):.1f}dBFS")
