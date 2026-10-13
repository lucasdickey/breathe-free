"""The voice over the app's own session sound, on the beat.

session.wav is PromoAudioTest's six-cycle session from its start (Ambient, full volume), so
its second 0 is the session's: the settle is 8 s, then each phase is 4 s. Each phrase is put
so its main vowel lands on its change (README: "nudged a little early so the stressed word
lands on the change"). The voice sits a set number of loudness units above the session.

usage: python3 -I voice_preview.py <session.wav> <takes.json> <in> <hold> <out> <LU above> <out.wav>
"""
import json
import re
import subprocess
import sys
import wave

import numpy as np

session_path, takes_path, take_in, take_hold, take_out, above, out = sys.argv[1:8]
above = float(above)
sr = 48000


def loudness(path):
    err = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-i", path, "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    summary = err[err.rfind("Summary:"):]
    return float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary).group(1))


with wave.open(session_path) as w:
    assert w.getframerate() == sr and w.getnchannels() == 2
    mix = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64).reshape(-1, 2) / 32768
session_lufs = loudness(session_path)

takes = {t["name"]: t for t in json.load(open(takes_path))}
gain = 10 ** (((session_lufs + above) - takes[take_in]["lufs"]) / 20)


def clip(name):
    with wave.open(takes[name]["clean"]) as w:
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768


SETTLE, PHASE = 8.0, 4.0
order = [take_in, take_hold, take_out, take_hold]
placed = []
k = 0
while True:
    cue = SETTLE + k * PHASE
    if cue >= len(mix) / sr:
        break
    name = order[k % 4]
    y = clip(name) * gain
    start = int(round((cue - takes[name]["vowel_at"]) * sr))
    end = min(start + len(y), len(mix))
    mix[start:end] += y[: end - start, None]
    placed.append(f"{cue:4.0f} s {name}")
    k += 1

peak = np.abs(mix).max()
if peak > 0.89:  # keep 1 dB clear of full scale
    mix *= 0.89 / peak
# 6 s to the end: two seconds before the first "Breathe in"; fade in 0.5 s, out 1.5 s.
mix = mix[int(6 * sr):]
fi, fo = int(0.5 * sr), int(1.5 * sr)
mix[:fi] *= np.linspace(0, 1, fi)[:, None]
mix[-fo:] *= np.linspace(1, 0, fo)[:, None]
with wave.open(out, "wb") as o:
    o.setnchannels(2); o.setsampwidth(2); o.setframerate(sr)
    o.writeframes((np.clip(mix, -1, 1) * 32767).round().astype("<i2").tobytes())
print(f"session {session_lufs:.1f} LUFS; voice set {above:+.1f} LU above it (gain {20*np.log10(gain):+.1f} dB); "
      f"peak before trim {20*np.log10(peak):.1f} dB")
print("placed: " + ", ".join(placed))
