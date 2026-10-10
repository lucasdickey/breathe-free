#!/usr/bin/env python3
"""
Edits the 10-second time-of-day spot from the frames and sound the apps render for
promo/sun.json (promo/README.md): a Mac window and a phone, each breathing at its true pace,
while a whole day goes by behind them and the light on the orb goes round with the sun. A clock
and a sun dial keep count, two captions say what is happening, and an end card closes, over
the app's own sound at YouTube's loudness, as 1920x1080, 30 fps H.264 with AAC.

usage: sun.py <mac frames> <android frames> <audio folder> <out.mp4> [--stills=0.5,4.4]
       (--stills draws just those moments, as pictures beside out.mp4)
"""

import json
import math
import subprocess
import sys
import tempfile
import wave
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))  # compose.py, beside this file

import compose  # noqa: E402
from compose import (H, RATE, URL, NAVY, W, Backdrop, EndCard, MacWindow, Phone, caption_image,  # noqa: E402
                     composite, ease_out, faded, font, loudness_normalised, read_wav, rounded_mask, shown, smooth)

SPOT = json.loads((HERE / "sun.json").read_text())
FPS = SPOT["fps"]
FRAMES = int(round(SPOT["seconds"] * FPS))
SWEEP = SPOT["sweep"]
LAG = SPOT["session"]["lagSeconds"]
END = SPOT["endCard"]
SETTLE, PHASE = 8.0, 4.0
ZONE = ZoneInfo(SPOT["zone"])
DAY = date.fromisoformat(SPOT["date"])

CAPTIONS = [
    (0.25, 4.30, "Lit by the sun", "The light on the orb follows\nthe time of day"),
    (4.50, 8.30, "Morning to midnight", "The sky keeps your hours"),
]


def hour_at(v):
    """The clock at video time v, as both apps drew it: eased across the sweep."""
    x = smooth((v - SWEEP["start"]) / (SWEEP["end"] - SWEEP["start"]))
    return SWEEP["fromHour"] + (SWEEP["toHour"] - SWEEP["fromHour"]) * x


# The phone's status bar and the end card read these from compose; point them at this spot.
compose.hour_at = hour_at
compose.END = END


def sun_times(day, zone):
    """Sunrise and sunset in hours on the local clock, worked out as DaySky does (latitude 40)."""
    n = day.timetuple().tm_yday
    latitude = math.radians(40.0)
    declination = math.radians(23.44) * math.sin(2 * math.pi * (284 + n) / 365)
    cos_half = (math.sin(math.radians(-0.833)) - math.sin(latitude) * math.sin(declination)) / (
        math.cos(latitude) * math.cos(declination))
    half_day = math.degrees(math.acos(max(-1.0, min(1.0, cos_half)))) / 15
    b = 2 * math.pi * (n - 81) / 364
    equation_of_time = 9.87 * math.sin(2 * b) - 7.53 * math.cos(b) - 1.5 * math.sin(b)
    saving = datetime(day.year, day.month, day.day, 12, tzinfo=zone).dst().total_seconds() / 3600
    noon = 12 + saving - equation_of_time / 60
    return noon - half_day, noon + half_day


RISE, SET = sun_times(DAY, ZONE)


def sun_angle(hour):
    """Where the sun is, as DaySky.sunAngle: π at sunrise (left), π/2 midday (top), 0 sunset
    (right), on round underneath through the night."""
    if RISE <= hour <= SET:
        return math.pi * (1 - (hour - RISE) / (SET - RISE))
    since_sunset = (hour - SET + 24) % 24
    return -math.pi * since_sunset / (24 - (SET - RISE))


def breath_level(v):
    """How full the lungs are at video time v, as the orb shows it (BreathTimeline)."""
    t = v - LAG - SETTLE
    if t < 0:
        return 0.0
    i = int(t // PHASE)
    rise = 0.5 - 0.5 * math.cos(math.pi * ((t - i * PHASE) / PHASE) ** 0.8)
    return (rise, 1.0, 1 - rise, 0.0)[i % 4]


def shadowed(layer, strength=0.55, blur=8):
    """A soft dark shadow under whatever is drawn on `layer`."""
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    shadow.putalpha(layer.getchannel("A").point(lambda a: a * strength))
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)), (0, 3))
    out.alpha_composite(layer)
    return out


class SpotWindow(MacWindow):
    """The Mac window, smaller and to the left of centre, beside the phone."""

    WIDTH, LEFT, TOP = 980, 710, 150

    def __init__(self, fw, fh):
        super().__init__(fw, fh, (fw / 2, fh / 2))
        self.anchor = (self.LEFT + self.focus[0] * self.base, self.TOP + self.focus[1] * self.base)


class SpotPhone(Phone):
    """The phone, standing in front of the window's right-hand edge."""

    HEIGHT = 780
    CENTER = (1690, 610)


class Clock:
    """The time of day, large, with a sun dial beside it: the sun's dot goes round the dial as
    the light goes round the orb, above the horizon by day and below it by night."""

    X, Y = 166, 300  # the dial's centre
    DIAL_R, PAD = 46, 44  # the dial's radius, and room round it for the sun's glow

    def __init__(self):
        self.digits = font("InterDisplay-Light.otf", 124)
        self.half = font("InterDisplay-Medium.otf", 40)

    def text(self, hour):
        h = int(hour) % 24
        m = int(round((hour % 1) * 60)) % 60
        return f"{h % 12 or 12}:{m:02d}", "AM" if h < 12 else "PM"

    def dial(self, angle, scale=4):
        """The dial's lines, and the sun on it, as two images: the lines take the text's shadow,
        the sun's glow doesn't."""
        size = 2 * (self.DIAL_R + self.PAD) * scale
        c, r = size / 2, self.DIAL_R * scale
        lines = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        d = ImageDraw.Draw(lines)
        d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, 80), width=2 * scale)
        d.arc([c - r, c - r, c + r, c + r], 180, 360, fill=(255, 255, 255, 190), width=3 * scale)
        d.line([c - r - 10 * scale, c, c + r + 10 * scale, c], fill=(255, 255, 255, 150), width=2 * scale)
        x, y = c + r * math.cos(angle), c - r * math.sin(angle)
        colour = (255, 214, 140) if math.sin(angle) >= -0.02 else (196, 218, 255)  # sun by day, pale by night
        sun = Image.new("RGBA", (size, size), colour + (0,))
        g = 22 * scale
        ImageDraw.Draw(sun).ellipse([x - g, y - g, x + g, y + g], fill=colour + (120,))
        sun = sun.filter(ImageFilter.GaussianBlur(10 * scale))
        dot = 9 * scale
        ImageDraw.Draw(sun).ellipse([x - dot, y - dot, x + dot, y + dot], fill=colour + (255,))
        small = (size // scale, size // scale)
        return lines.resize(small, Image.LANCZOS), sun.resize(small, Image.LANCZOS)

    def draw(self, canvas, v, alpha):
        hour = hour_at(v)
        digits, half = self.text(hour)
        lines, sun = self.dial(sun_angle(hour))
        dw = self.digits.getlength(digits)
        layer = Image.new("RGBA", (int(lines.width + 8 + dw + 14 + self.half.getlength(half) + 24), 200),
                          (255, 255, 255, 0))
        top = (layer.height - lines.height) // 2
        layer.alpha_composite(lines, (0, top))
        d = ImageDraw.Draw(layer)
        x, base = lines.width + 8, layer.height / 2 + 44
        d.text((x, base), digits, font=self.digits, fill=(255, 255, 255, 255), anchor="ls")
        d.text((x + dw + 14, base), half, font=self.half, fill=(255, 255, 255, 230), anchor="ls")
        out = shadowed(layer)
        out.alpha_composite(sun, (0, top))
        composite(canvas, faded(out, alpha), self.X - self.DIAL_R - self.PAD, self.Y - layer.height / 2)


class SpotEndCard(EndCard):
    """The end card, for both apps and this update."""

    def __init__(self):
        super().__init__("mac")
        self.line = self.text("Now in step with the sun", font("Inter-Regular.otf", 40), (255, 255, 255, 228))
        label = f"Free for Mac and Android   ·   {URL}"
        f = font("Inter-SemiBold.otf", 38)
        pw, ph = int(f.getlength(label)) + 76, 84
        pill = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        pill.paste(Image.new("RGBA", (pw, ph), (255, 255, 255, 245)), (0, 0), rounded_mask(pw, ph, ph // 2))
        ImageDraw.Draw(pill).text((38, ph / 2), label, font=f, fill=NAVY + (255,), anchor="lm")
        self.pill = pill


class Spot:
    def __init__(self, mac_dir, android_dir):
        self.mac_dir, self.android_dir = mac_dir, android_dir
        mw, mh = self.mac(0).size
        aw, ah = self.android(0).size
        size = json.loads((android_dir / "size.json").read_text())
        centre = [{"name": "none", "v": -10.0, "x": aw / 2, "y": ah / 2}]  # no taps in this spot
        self.window = SpotWindow(mw, mh)
        self.phone = SpotPhone(aw, ah, (size.get("statusBar", 0), size.get("navigationBar", 0)), centre)
        self.backdrop = Backdrop((1270, 560), 560, 0.26, left_scrim=0.34)
        self.clock = Clock()
        self.captions = [(s, e, caption_image(t, sub, 580, 60, 34, "left")) for s, e, t, sub in CAPTIONS]
        self.end_card = SpotEndCard()

    def mac(self, k):
        return Image.open(self.mac_dir / f"f{k:05d}.jpg").convert("RGB")

    def android(self, k):
        return Image.open(self.android_dir / f"f{k:05d}.jpg").convert("RGB")

    def draw(self, k):
        v = k / FPS
        mac, phone = self.mac(k), self.android(k)
        zoom = 1 + 0.035 * smooth(v / END)
        canvas = self.backdrop.render(mac, 0.06 + 0.16 * breath_level(v))
        self.window.draw(canvas, mac, v, zoom)
        self.phone.draw(canvas, phone, v, zoom)
        self.clock.draw(canvas, v, shown(v, 0.1, END + 0.3, fade_in=0.5))
        for s, e, img in self.captions:
            a = shown(v, s, e)
            if a > 0:
                dy = int(16 * (1 - ease_out((v - s) / 0.5)))
                canvas.alpha_composite(faded(img, a), (96, 430 + dy))
        if v >= END:
            canvas = Image.blend(canvas, self.end_card.render(mac, v), smooth((v - END) / 0.8))
        return canvas.convert("RGB")


def mix_sound(audio_dir, out_wav):
    """The session's own sound from just before its first breath in, so each bell lands on the
    frame that shows its change, easing out under the end card as the closing chord rings."""
    total = FRAMES * RATE // FPS
    mix = np.zeros((total, 2), np.float32)
    session = read_wav(audio_dir / "session.wav")[int(round(-LAG * RATE)):][:total].copy()
    n = int(0.35 * RATE)
    session[:n] *= np.linspace(0, 1, n)[:, None]
    t = np.arange(len(session)) / RATE
    x = np.clip((t - (END + 0.2)) / 1.4, 0, 1)
    session *= (1 - x * x * (3 - 2 * x))[:, None]
    mix[:len(session)] += session
    closing = read_wav(audio_dir / "closing.wav") * 0.8
    start = int(round((END + 0.15) * RATE))
    m = min(len(closing), total - start)
    mix[start:start + m] += closing[:m]
    n = int(0.4 * RATE)
    mix[-n:] *= np.linspace(1, 0, n)[:, None]
    with wave.open(str(out_wav), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(mix, -1, 1) * 32767).astype("<i2").tobytes())


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--stills=")]
    stills = [float(t) for a in sys.argv[1:] if a.startswith("--stills=") for t in a[9:].split(",")]
    if len(args) != 4:
        sys.exit(__doc__)
    mac_dir, android_dir, audio_dir, out = (Path(a) for a in args)
    spot = Spot(mac_dir, android_dir)
    if stills:
        for t in stills:
            path = out.with_name(f"{out.stem}-{t:05.2f}.png")
            spot.draw(int(round(t * FPS))).save(path)
            print(f"wrote {path}")
        return

    with tempfile.TemporaryDirectory() as tmp:
        raw, wav = Path(tmp) / "mix.wav", Path(tmp) / "sound.wav"
        mix_sound(audio_dir, raw)
        print(f"sound: {loudness_normalised(raw, wav):.1f} LUFS before, -14 after")
        enc = subprocess.Popen(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
             "-i", str(wav), "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p",
             "-profile:v", "high", "-c:a", "aac", "-b:a", "192k", "-ar", str(RATE), "-shortest",
             "-movflags", "+faststart", str(out)],
            stdin=subprocess.PIPE)
        for k in range(FRAMES):
            enc.stdin.write(spot.draw(k).tobytes())
            if k % 60 == 0:
                print(f"frame {k} of {FRAMES}", flush=True)
        enc.stdin.close()
        if enc.wait() != 0:
            sys.exit("ffmpeg failed")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
