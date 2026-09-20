#!/usr/bin/env python3
"""Turn the chosen ElevenLabs candidate into the shipping loop assets/audio/sfx/amb_waves.wav.
Circular FFT high-pass at 70 Hz (rumble below that is inaudible on real speakers and only eats headroom; circular so the
loop seam is untouched), then peak-normalise to -20 dBFS. Prints the measurements used to pick it."""
import subprocess, wave, pathlib, numpy as np
ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/audio/elevenlabs/amb_waves_v2_c3.mp3"
SR = 44100
d = np.frombuffer(subprocess.run(["ffmpeg","-v","error","-i",str(SRC),"-f","s16le","-ac","1","-ar",str(SR),"-"],
                                 capture_output=True).stdout, np.int16).astype(float) / 32768
X = np.fft.rfft(d); f = np.fft.rfftfreq(len(d), 1/SR)
X *= 1 / (1 + (70 / np.maximum(f, 1e-9)) ** 4)
d = np.fft.irfft(X, len(d)); d *= 10 ** (-20 / 20) / abs(d).max()
S = abs(np.fft.rfft(d * np.hanning(len(d)))) ** 2
print(f"secs {len(d)/SR:.1f} centroid {(f*S).sum()/S.sum():.0f}Hz >2k {100*S[f>2000].sum()/S.sum():.4f}% >4k {100*S[f>4000].sum()/S.sum():.4f}% "
      f"seam {abs(d[0]-d[-1])*32768:.0f} vs step {np.abs(np.diff(d)).mean()*32768:.0f} rms {20*np.log10(np.sqrt((d**2).mean())):.1f}dBFS")
w = wave.open(str(ROOT / "assets/audio/sfx/amb_waves.wav"), "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
w.writeframes((d * 32767).astype(np.int16).tobytes()); w.close()
