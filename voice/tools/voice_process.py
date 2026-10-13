"""Measure and clean the cut takes.

For each take: its pitch at the start and the end (YIN, 70-300 Hz; a calm phrase ends lower),
then a gentle low cut below 70 Hz and a gain that brings every take to the same loudness
(EBU R128, by ffmpeg's ebur128). Also what the room noise between phrases is made of.
Writes the cleaned takes and a reel of all of them, in order, with gaps.

usage: python3 -I voice_process.py <recording> <takes dir> <target LUFS>
"""
import json
import os
import re
import subprocess
import sys
import wave

import numpy as np

src, tdir, target = sys.argv[1], sys.argv[2], float(sys.argv[3])
sr = 48000
takes = json.load(open(os.path.join(tdir, "takes.json")))
clean = os.path.join(tdir, "clean")
os.makedirs(clean, exist_ok=True)


def read(path):
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768


def write(path, y):
    with wave.open(path, "wb") as o:
        o.setnchannels(1); o.setsampwidth(2); o.setframerate(sr)
        o.writeframes((np.clip(y, -1, 1) * 32767).round().astype("<i2").tobytes())


def yin(frame, fmin=50, fmax=300, threshold=0.2):
    """Pitch of one frame in Hz, or None if it isn't clearly voiced."""
    tau_min, tau_max = int(sr / fmax), int(sr / fmin)
    w = len(frame) - tau_max
    d = np.array([np.sum((frame[:w] - frame[t:t + w]) ** 2) for t in range(tau_max + 1)])
    cmnd = np.ones_like(d)
    cmnd[1:] = d[1:] * np.arange(1, len(d)) / np.maximum(np.cumsum(d[1:]), 1e-12)
    for t in range(tau_min, tau_max):
        if cmnd[t] < threshold and cmnd[t] <= cmnd[t + 1]:
            # Parabolic interpolation around the dip.
            a, b, c = cmnd[t - 1], cmnd[t], cmnd[t + 1]
            shift = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) else 0
            return sr / (t + shift)
    return None


def loudness(path):
    """Integrated loudness (LUFS) and true peak (dBTP), by ffmpeg."""
    err = subprocess.run(["ffmpeg", "-nostats", "-hide_banner", "-i", path, "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    summary = err[err.rfind("Summary:"):]
    i = float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary).group(1))
    tp = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", summary).group(1))
    return i, tp


# What the room noise is made of: the average spectrum of the quiet stretches, by band.
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
                     check=True, capture_output=True).stdout
x = np.frombuffer(raw, np.float32).astype(np.float64)
N = 4096
frames = [x[i:i + N] for i in range(0, len(x) - N, N // 2)]
lv = np.array([20 * np.log10(np.sqrt(np.mean(f ** 2)) + 1e-9) for f in frames])
quiet = [f for f, l in zip(frames, lv) if -66 < l < -50]
loud = [f for f, l in zip(frames, lv) if l > -30]
spec = lambda fs: 10 * np.log10(np.mean([np.abs(np.fft.rfft(f * np.hanning(N))) ** 2 for f in fs], axis=0) + 1e-12)
freqs = np.fft.rfftfreq(N, 1 / sr)
ns, vs = spec(quiet), spec(loud)
print(f"room noise vs voice, by band ({len(quiet)} quiet and {len(loud)} loud stretches):")
for lo, hi in ((20, 70), (70, 150), (150, 500), (500, 2000), (2000, 6000), (6000, 12000), (12000, 20000)):
    m = (freqs >= lo) & (freqs < hi)
    print(f"  {lo:>5}-{hi:<5} Hz  noise {ns[m].mean():6.1f} dB   voice {vs[m].mean():6.1f} dB   gap {vs[m].mean() - ns[m].mean():5.1f} dB")

print(f"\ntakes, each brought to {target} LUFS:")
for t in takes:
    y = read(t["file"])
    # Pitch over the voiced part (within 25 dB of the take's loudest 20 ms).
    hop, win = sr // 100, int(0.04 * sr)
    lev = np.array([np.sqrt(np.mean(y[i:i + win] ** 2)) for i in range(0, len(y) - win, hop)])
    top = 20 * np.log10(lev.max())
    pitches = []
    for k, i in enumerate(range(0, len(y) - win, hop)):
        if 20 * np.log10(lev[k] + 1e-12) > top - 25:
            p = yin(y[i:i + win])
            if p:
                pitches.append((i / sr, p))
    ps = np.array([p for _, p in pitches])
    if len(ps):
        third = max(len(ps) // 3, 1)
        start_p, end_p = np.median(ps[:third]), np.median(ps[-third:])
        t["pitch"] = {"start": round(float(start_p)), "end": round(float(end_p)), "low": round(float(ps.min())),
                      "high": round(float(ps.max())), "voiced_frames": len(ps)}
        pitch_text = f"pitch {start_p:4.0f} -> {end_p:4.0f} Hz (range {ps.min():3.0f}-{ps.max():3.0f}, {len(ps):2} frames)"
    else:
        t["pitch"] = None
        pitch_text = "no steady pitch (breathy or whispered)            "
    # Clean: low cut, then the gain that reaches the target loudness.
    tmp = os.path.join(clean, f"{t['name']}-hp.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", t["file"], "-af", "highpass=f=70:poles=2",
                    "-c:a", "pcm_s16le", tmp], check=True)
    i_lufs, _ = loudness(tmp)
    gain = target - i_lufs
    out = os.path.join(clean, f"{t['name']}.wav")
    write(out, read(tmp) * 10 ** (gain / 20))
    os.remove(tmp)
    i2, tp2 = loudness(out)
    t["clean"], t["lufs_before"], t["gain_db"], t["lufs"], t["true_peak"] = out, i_lufs, round(gain, 1), i2, tp2
    print(f"  {t['name']:15} {t['length']:.2f} s  {pitch_text}  "
          f"loudness {i_lufs:6.1f} -> {i2:6.1f} LUFS (gain {gain:+5.1f} dB)  peak {tp2:6.1f} dB")

json.dump(takes, open(os.path.join(tdir, "takes.json"), "w"), indent=1)

# The reel: every cleaned take in order, 1.2 s apart, with half a second of quiet at each end.
gap = np.zeros(int(1.2 * sr))
reel = [np.zeros(sr // 2)]
for t in takes:
    reel += [read(t["clean"]), gap]
reel[-1] = np.zeros(sr // 2)
write(os.path.join(tdir, "reel.wav"), np.concatenate(reel))
print("\nreel order: " + ", ".join(t["name"] for t in takes))
