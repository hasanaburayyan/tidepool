#!/usr/bin/env python3
"""Generate one sound with ElevenLabs sound-generation (board Decision #16). Usage:
  python3 audio/gen_elevenlabs.py NAME "prompt" SECONDS [loop]
Key is read in-process from ~/repos/r2ts-games/.env (ELEVENLABS_API_KEY only), never printed.
Writes assets/audio/elevenlabs/NAME.mp3 + NAME.txt (prompt, model, date). Counts calls in COUNT.txt (cap 60)."""
import sys, os, json, pathlib, datetime, urllib.request, urllib.error
root = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "elevenlabs"
root.mkdir(parents=True, exist_ok=True)
cnt = root / "COUNT.txt"
n = int(cnt.read_text()) if cnt.exists() else 0
if n >= 60: sys.exit("generation cap (60) reached")
key = None
for line in open(os.path.expanduser("~/repos/r2ts-games/.env")):
    if line.startswith("ELEVENLABS_API_KEY="): key = line.split("=", 1)[1].strip().strip('"\'')
if not key: sys.exit("ELEVENLABS_API_KEY not found in ~/repos/r2ts-games/.env")
name, prompt, secs = sys.argv[1], sys.argv[2], float(sys.argv[3])
loop = len(sys.argv) > 4 and sys.argv[4] == "loop"
model = "eleven_text_to_sound_v2"
body = {"text": prompt, "duration_seconds": secs, "prompt_influence": 0.5, "model_id": model}
if loop: body["loop"] = True
req = urllib.request.Request("https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128",
    data=json.dumps(body).encode(), headers={"xi-api-key": key, "Content-Type": "application/json"})
try:
    data = urllib.request.urlopen(req, timeout=120).read()
except urllib.error.HTTPError as e:
    sys.exit(f"HTTP {e.code}: {e.read()[:300].decode(errors='replace')}")
cnt.write_text(str(n + 1))
(root / f"{name}.mp3").write_bytes(data)
(root / f"{name}.txt").write_text(f"prompt: {prompt}\nmodel: {model}\nduration_seconds: {secs}\nloop: {loop}\ndate: {datetime.date.today()}\ndecision: #16\n")
print(f"{name}: {len(data)} bytes; generations used {n+1}/60")
