"""Smooth the "t" at the end of "Breathe out".

The release of the "t" is a sharp spike after a moment of near-silence (the tongue closing),
which is what pops. It is found as the first sudden jump out of that silence once the vowel
has died away. Two versions of each take:

- soft: from just before the release on, 14 dB quieter, and the spike's edge replaced by a
  4 ms ramp, so a faint "ts" is left;
- not: the take ends just before the release, in the near-silence (an unreleased "t").

Adds both to takes.json (as <name>-soft and <name>-not) and prints how sharp the release is
before and after.

usage: python3 -I voice_soft_t.py <takes dir> <name> [<name> ...]
"""
import json
import os
import sys
import wave

import numpy as np

tdir, names = sys.argv[1], sys.argv[2:]
sr = 48000
takes = json.load(open(os.path.join(tdir, "takes.json")))
by_name = {t["name"]: t for t in takes}


def read(path):
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768


def write(path, y):
    with wave.open(path, "wb") as o:
        o.setnchannels(1); o.setsampwidth(2); o.setframerate(sr)
        o.writeframes((np.clip(y, -1, 1) * 32767).round().astype("<i2").tobytes())


def sharpest(y, a, b):
    """Tallest sample and largest sample-to-sample jump in [a, b) seconds, against the vowel's."""
    seg = y[int(a * sr): int(b * sr)]
    return (20 * np.log10(np.abs(seg).max() / np.abs(y).max()),
            20 * np.log10(np.abs(np.diff(seg)).max() / np.abs(np.diff(y)).max()))


for name in names:
    t = by_name[name]
    y = read(t["clean"])
    hop, win = sr // 200, sr // 100
    n = (len(y) - win) // hop
    db = np.array([20 * np.log10(np.sqrt(np.mean(y[i * hop: i * hop + win] ** 2)) + 1e-9) for i in range(n)])
    peak = db.max()
    # The end of "out": the last moment within 15 dB of the peak (the release is far quieter
    # than that on average, though its spike is sharp). Then the closure: the first 40 ms
    # after it that stay more than 30 dB under the peak.
    last_loud = max(i for i in range(n) if db[i] > peak - 15)
    k, run = last_loud, 0
    while k < n and run < 8:
        run = run + 1 if db[k] < peak - 30 else 0
        k += 1
    vowel_end = (k - run) * hop + win
    # The release: the first sample in the closure or after it that jumps to six times the
    # level of the 30 ms before it.
    look = int(0.03 * sr)
    onset = None
    for k in range(vowel_end, len(y)):
        before = np.sqrt(np.mean(y[k - look: k] ** 2)) + 1e-6
        if abs(y[k]) > 6 * before and abs(y[k]) > 0.02 * np.abs(y).max():
            onset = k
            break
    assert onset, f"{name}: no release found"
    on_t = onset / sr
    s_before = sharpest(y, on_t - 0.002, min(on_t + 0.06, len(y) / sr))

    # soft: a 4 ms ramp into 14 dB down, starting 3 ms before the release.
    g = np.ones_like(y)
    a, ramp = onset - int(0.003 * sr), int(0.004 * sr)
    low = 10 ** (-14 / 20)
    g[a: a + ramp] = 1 - (1 - low) * (0.5 - 0.5 * np.cos(np.linspace(0, np.pi, ramp)))
    g[a + ramp:] = low
    # And the spike's own edge: a 4 ms fade-in at the release itself.
    fade = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, ramp))
    g[onset: onset + ramp] *= fade
    soft = y * g
    # not: end in the silence just before the release, with a 15 ms fade.
    stop = onset - int(0.003 * sr)
    fo = int(0.015 * sr)
    nott = y[:stop].copy()
    nott[-fo:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fo))

    for suffix, z in (("soft", soft), ("not", nott)):
        path = os.path.join(tdir, "clean", f"{name}-{suffix}.wav")
        write(path, z)
        entry = dict(t, name=f"{name}-{suffix}", clean=path, length=round(len(z) / sr, 3))
        by_name[entry["name"]] = entry
    s_after = sharpest(soft, on_t - 0.002, min(on_t + 0.06, len(y) / sr))
    print(f"{name}: release at {on_t:.3f} s, {on_t - vowel_end / sr:.3f} s after the vowel dies away; "
          f"tallest sample {s_before[0]:.1f} -> {s_after[0]:.1f} dB, sharpest jump {s_before[1]:.1f} -> {s_after[1]:.1f} dB "
          f"(against the vowel's); without the release the take is {len(nott) / sr:.2f} s")

json.dump(list(by_name.values()), open(os.path.join(tdir, "takes.json"), "w"), indent=1)
