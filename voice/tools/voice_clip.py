"""Cut each spoken take out of the recording, at the sound's own start and end.

Whisper says which words are where, roughly. For each phrase, the loud core of the sound is
found near Whisper's span; the cut then reaches back for the quiet start of the word (a soft
B, the breathy H of "Hold") but no further than 0.2 s, so a breath taken before the word
stays out, and forward for the fading end ("out", "Hold"). Each cut gets a few milliseconds
either side and short fades, so it can't click.

Writes each take as a 48 kHz mono WAV, a takes.json with its timings and where its main vowel
starts (the point to put on the beat), and a picture of every cut for checking by eye.

usage: python3 -I voice_clip.py <recording> <words.json> <out dir>
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw

src, words_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)

sr = 48000
# The two channels are identical, so one channel at 48 kHz, straight from ffmpeg.
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-f", "f32le", "-ac", "1", "-ar", str(sr), "-"],
                     check=True, capture_output=True).stdout
x = np.frombuffer(raw, np.float32).astype(np.float64)

HOP = sr // 200  # 5 ms
WIN = sr // 50   # 20 ms
n = (len(x) - WIN) // HOP
level = np.array([np.sqrt(np.mean(x[i * HOP: i * HOP + WIN] ** 2)) for i in range(n)])
db = 20 * np.log10(level + 1e-9)
t_of = lambda i: i * HOP / sr + WIN / (2 * sr)  # frame middle, seconds
i_of = lambda t: int(round((t - WIN / (2 * sr)) * sr / HOP))
# The room's noise: the middle of everything well below speech.
NOISE = float(np.median(db[db < -45]))
print(f"room noise about {NOISE:.1f} dB")

# Whisper's words, grouped into phrases: "Breathe" joins the word after it.
words = json.load(open(words_path))["plain"]
phrases, k = [], 0
while k < len(words):
    w0 = words[k]
    if w0["word"].lower().startswith("breathe") and k + 1 < len(words):
        w1 = words[k + 1]
        phrases.append({"text": f"Breathe {w1['word'].strip('.').lower()}", "start": w0["start"], "end": w1["end"]})
        k += 2
    else:
        phrases.append({"text": w0["word"].strip("."), "start": w0["start"], "end": w0["end"]})
        k += 1


def runs(mask):
    """(start, end) frame pairs where mask is true."""
    out_, s = [], None
    for i, v in enumerate(mask):
        if v and s is None:
            s = i
        if not v and s is not None:
            out_.append((s, i)); s = None
    if s is not None:
        out_.append((s, len(mask)))
    return out_


takes = []
counts = {}
for p_i, ph in enumerate(phrases):
    # Look a little beyond Whisper's span, but never into the neighbours' spans.
    lo_t = max(ph["start"] - 0.6, phrases[p_i - 1]["end"] if p_i else 0.0)
    hi_t = min(ph["end"] + 0.6, phrases[p_i + 1]["start"] if p_i + 1 < len(phrases) else len(x) / sr)
    lo, hi = max(i_of(lo_t), 0), min(i_of(hi_t), n)
    seg = db[lo:hi]
    peak = seg.max()
    # The core: everything within 22 dB of the phrase's peak, gaps under 150 ms joined.
    core = runs(seg > peak - 22)
    merged = []
    for a, b in core:
        if merged and a - merged[-1][1] < 30:
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    # The phrase runs from the first to the last core part that overlaps Whisper's span, so a
    # dip between "Breathe" and "in" can't split it; a stray click outside the span doesn't count.
    ws, we = i_of(ph["start"] - 0.15) - lo, i_of(ph["end"] + 0.15) - lo
    inside = [r for r in merged if r[1] > ws and r[0] < we] or [max(merged, key=lambda r: r[1] - r[0])]
    a, b = inside[0][0] + lo, inside[-1][1] + lo
    # Reach back for the quiet start (a soft B, the breathy H), at most 0.3 s, while within
    # 35 dB of the peak: a breath before the word is quieter than that and stays out.
    s = a
    while s > lo and a - s < 60 and db[s - 1] > peak - 35:
        s -= 1
    # Reach forward for the fading end, at most 0.5 s: it ends once the sound has sat within
    # 6 dB of the room's noise for 80 ms, which keeps the "t" of "out" after its short gap.
    end_floor = max(NOISE + 6, peak - 45)
    e, quiet = b, 0
    while e < hi and e - b < 100:
        if db[e] > end_floor:
            quiet = 0
        else:
            quiet += 1
            if quiet >= 16:
                e -= quiet - 1
                break
        e += 1
    cut_s = max(t_of(s) - 0.015, lo_t)
    cut_e = min(t_of(e) + 0.040, hi_t)
    # Where the main vowel starts: the first frame within 8 dB of the peak, after the core starts.
    vowel = next(i for i in range(a, b) if db[i] > peak - 8)
    clip = x[int(cut_s * sr): int(cut_e * sr)].copy()
    fi, fo = int(0.008 * sr), int(0.040 * sr)
    clip[:fi] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, fi))
    clip[-fo:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fo))
    key = ph["text"].lower().replace(" ", "-")
    counts[key] = counts.get(key, 0) + 1
    name = f"{key}-{counts[key]}"
    path = os.path.join(out, f"{name}.wav")
    with wave.open(path, "wb") as o:
        o.setnchannels(1); o.setsampwidth(2); o.setframerate(sr)
        o.writeframes((np.clip(clip, -1, 1) * 32767).astype("<i2").tobytes())
    takes.append({
        "name": name, "text": ph["text"], "file": path,
        "whisper": [ph["start"], ph["end"]], "cut": [round(cut_s, 3), round(cut_e, 3)],
        "length": round(cut_e - cut_s, 3), "vowel_at": round(t_of(vowel) - cut_s, 3),
        "peak_db": round(20 * np.log10(np.abs(clip).max() + 1e-12), 1),
        "core_db": round(peak, 1),
        "edge_db": [round(db[max(i_of(cut_s), 0)], 1), round(db[min(i_of(cut_e), n - 1)], 1)],
        "window": [round(lo_t, 3), round(hi_t, 3)],
    })

json.dump(takes, open(os.path.join(out, "takes.json"), "w"), indent=1)
for t in takes:
    print(f"{t['name']:15} cut {t['cut'][0]:6.2f}-{t['cut'][1]:6.2f} s  {t['length']:.2f} s  vowel at {t['vowel_at']:.2f} s  "
          f"peak {t['peak_db']:6.1f} dB  edges {t['edge_db'][0]:6.1f} / {t['edge_db'][1]:6.1f} dB  "
          f"(Whisper {t['whisper'][0]:.2f}-{t['whisper'][1]:.2f})")

# One strip per take: the level over its window, Whisper's span (orange), the cut (green),
# the vowel start (blue).
W, H, M = 900, 120, 16
sheet = Image.new("RGB", (W + 2 * M, len(takes) * (H + 26) + M), (250, 250, 250))
d = ImageDraw.Draw(sheet)
for r, t in enumerate(takes):
    y0 = M + r * (H + 26)
    lo_t, hi_t = t["window"]
    span = hi_t - lo_t
    X = lambda tt: M + int((tt - lo_t) / span * W)
    Y = lambda v: y0 + 18 + int((-(max(min(v, -10), -80)) - 10) / 70 * (H - 18))
    d.text((M, y0), f"{t['name']}  ({lo_t:.2f}-{hi_t:.2f} s)", fill=(0, 0, 0))
    d.rectangle([X(t['whisper'][0]), y0 + 18, X(t['whisper'][1]), y0 + H], fill=(255, 236, 210))
    d.rectangle([X(t['cut'][0]), y0 + 18, X(t['cut'][1]), y0 + H], outline=(30, 150, 60), width=2)
    pts = [(X(t_of(i)), Y(db[i])) for i in range(max(i_of(lo_t), 0), min(i_of(hi_t), n))]
    d.line(pts, fill=(40, 40, 40), width=1)
    vx = X(t['cut'][0] + t['vowel_at'])
    d.line([(vx, y0 + 18), (vx, y0 + H)], fill=(40, 90, 220), width=1)
    for v in (-20, -40, -60):
        d.text((W + M - 30, Y(v) - 6), f"{v}", fill=(150, 150, 150))
sheet.save(os.path.join(out, "cuts.png"))
print("picture:", os.path.join(out, "cuts.png"))
