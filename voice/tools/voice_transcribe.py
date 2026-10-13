"""Every word in the recording with its start and end, by faster-whisper, once plain and once
with the expected phrases as a hint (short single words are easier to catch with one).

usage: python -I voice_transcribe.py <16 kHz wav> <model> <out json>
"""
import json
import sys
import wave

import numpy as np

from faster_whisper import WhisperModel

wav, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
# Read the 16 kHz WAV here: this faster-whisper and PyAV disagree on how to open files.
with wave.open(wav) as w:
    assert w.getframerate() == 16000 and w.getnchannels() == 1 and w.getsampwidth() == 2
    audio = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
model = WhisperModel(name, device="cpu", compute_type="int8")
hint = "Settle in. Soften your shoulders and jaw. Breathe in. Hold. Breathe out. Hold."
runs = {}
for label, prompt in (("plain", None), ("hinted", hint)):
    segments, info = model.transcribe(audio, language="en", beam_size=5, word_timestamps=True,
                                      vad_filter=False, condition_on_previous_text=False,
                                      initial_prompt=prompt)
    words = []
    print(f"== {label}")
    for seg in segments:
        print(f"  [{seg.start:5.2f}-{seg.end:5.2f}] {seg.text.strip()}")
        for w in seg.words:
            words.append({"word": w.word.strip(), "start": round(w.start, 3), "end": round(w.end, 3),
                          "p": round(w.probability, 3)})
    print("  words: " + "  ".join(f"{w['word']}({w['start']:.2f}-{w['end']:.2f}, {w['p']:.2f})" for w in words))
    runs[label] = words
with open(out, "w") as f:
    json.dump(runs, f, indent=1)
