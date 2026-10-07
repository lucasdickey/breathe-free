#!/usr/bin/env python3
"""
Edits a 30-second promo from the frames and sound the apps render (promo/README.md): the app
in a phone (Android) or a Mac window over its own sky, the taps or the pointer, captions, an
end card, and the app's own sound at YouTube's loudness, as 1920x1080, 30 fps H.264 with AAC.

usage: compose.py android|mac <frames folder> <audio folder> <out.mp4> [--stills=3.6,12.5]
       (--stills draws just those moments, as pictures beside out.mp4)
"""

import json
import math
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
W, H = 1920, 1080
RATE = 48_000
INTER = Path("/usr/share/fonts/opentype/inter")
ICON = REPO / "macos-app/BreatheFree/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
URL = "one-off.dev/breathe-free"
NAVY = (15, 42, 67)
GLOW = np.array([120, 200, 255], np.float32)

SCRIPT = json.loads((HERE / "script.json").read_text())
FPS = SCRIPT["fps"]
SECONDS = SCRIPT["seconds"]
FRAMES = int(round(SECONDS * FPS))
TAPS = SCRIPT["taps"]
LAG = SCRIPT["session"]["lagSeconds"]
END = SCRIPT["endCard"]
SWEEP = SCRIPT["sweep"]
# From the apps' SessionPlan: the session lengths offered, an 8 second settle, 4 second phases.
CHOICES = [2, 6, 10, 20, 36, 50]
SETTLE, PHASE = 8.0, 4.0

# Headline and subline, on the beats of the script: the phases change at session times 8,
# 12, 16, 20 and 24, which is video time + LAG. A line break is where the narrow Android column
# breaks the line; the Mac's wide band runs the lines together.
OPENING = (0.25, 3.05, "Breathe Free", "Box breathing under a sky\nthat follows your day")
SESSION_CAPTIONS = [
    (6.75, 10.40, "Sound made for each breath", "A soft drone and moving air,\nmade as you breathe"),
    (10.60, 14.40, "In for four", "The orb fills as you breathe in"),
    (14.60, 18.40, "Hold for four", "A gentle bell marks every change"),
    (18.60, 22.40, "Out for four", "Sound and picture stay in step"),
    (22.60, 26.30, "Hold, and again", "A light traces the box as you go"),
]
CAPTIONS = {
    "android": [OPENING, (3.30, 6.20, "Pick your session", "Tap the circle, choose a length")] + SESSION_CAPTIONS,
    "mac": [OPENING, (3.30, 6.20, "Pick your session", "Click the circle, choose a length")] + SESSION_CAPTIONS,
}


def font(name, size):
    return ImageFont.truetype(str(INTER / name), size)


def clamp01(x):
    return max(0.0, min(1.0, x))


def smooth(x):
    x = clamp01(x)
    return x * x * (3 - 2 * x)


def ease_out(x):
    x = clamp01(x)
    return 1 - (1 - x) ** 3


def shown(v, start, end, fade_in=0.45, fade_out=0.35):
    """0..1: in from `start`, out by `end`."""
    return smooth((v - start) / fade_in) * (1 - smooth((v - (end - fade_out)) / fade_out))


def hour_at(v):
    x = smooth((v - SWEEP["start"]) / (SWEEP["end"] - SWEEP["start"]))
    return SWEEP["fromHour"] + (SWEEP["toHour"] - SWEEP["fromHour"]) * x


def frame_index_before(v):
    """The last frame drawn before video time v."""
    return int(np.ceil(v * FPS - 1e-9)) - 1


def spring(t, response, damping):
    """SwiftUI's spring(response:dampingFraction:), from rest at 0 towards 1, t seconds in."""
    if t <= 0:
        return 0.0
    w0 = 2 * math.pi / response
    if damping < 1:
        wd = w0 * math.sqrt(1 - damping * damping)
        return 1 - math.exp(-damping * w0 * t) * (math.cos(wd * t) + damping * w0 / wd * math.sin(wd * t))
    return 1 - math.exp(-w0 * t) * (1 + w0 * t)


def breath_level(v):
    """How full the lungs are at video time v, as the orb shows it (BreathTimeline.kt)."""
    t = v - LAG - SETTLE
    if t < 0:
        return 0.0
    i = int(t // PHASE)
    rise = 0.5 - 0.5 * math.cos(math.pi * ((t - i * PHASE) / PHASE) ** 0.8)
    return (rise, 1.0, 1 - rise, 0.0)[i % 4]


def zoom_at(v, most):
    """The camera pushes in on session length while it is used, and back out for the session."""
    return 1 + (most - 1) * (smooth((v - (TAPS["open"] - 0.65)) / 0.6) - smooth((v - (TAPS["begin"] - 0.25)) / 0.8))


def rounded_mask(w, h, r, scale=4):
    big = Image.new("L", (w * scale, h * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * scale - 1, h * scale - 1], r * scale, fill=255)
    return big.resize((w, h), Image.LANCZOS)


def disc_mask(size, radius, feather=1.5):
    c = (size - 1) / 2
    ys, xs = np.mgrid[0:size, 0:size]
    d = np.hypot(xs - c, ys - c)
    return Image.fromarray((np.clip((radius + feather - d) / feather, 0, 1) * 255).astype(np.uint8))


def composite(canvas, img, x, y):
    """alpha_composite, letting the image hang off the canvas's edges."""
    x, y = int(round(x)), int(round(y))
    left, top = max(0, -x), max(0, -y)
    right, bottom = min(img.width, W - x), min(img.height, H - y)
    if right > left and bottom > top:
        canvas.alpha_composite(img.crop((left, top, right, bottom)), (x + left, y + top))


def faded(img, alpha):
    if alpha >= 1:
        return img
    out = img.copy()
    out.putalpha(out.getchannel("A").point(lambda a: a * alpha))
    return out


def runs(mask):
    """(start, end) of each run of True."""
    out, start = [], None
    for i, on in enumerate(list(mask) + [False]):
        if on and start is None:
            start = i
        elif not on and start is not None:
            out.append((start, i))
            start = None
    return out


def wrap(text, f, width):
    lines = []
    for paragraph in text.split("\n"):
        line = ""
        for word in paragraph.split():
            trial = (line + " " + word).strip()
            if f.getlength(trial) <= width or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


def caption_image(title, sub, width, title_size, sub_size, align):
    """A headline over a subline in white, with a soft shadow, on a transparent image."""
    tf, sf = font("InterDisplay-SemiBold.otf", title_size), font("Inter-Medium.otf", sub_size)
    title_lines, sub_lines = wrap(title, tf, width), wrap(sub, sf, width)
    title_lh, sub_lh = int(title_size * 1.12), int(sub_size * 1.35)
    pad = 24
    height = pad * 2 + title_lh * len(title_lines) + int(sub_size * 0.6) + sub_lh * len(sub_lines)
    text = Image.new("RGBA", (width + pad * 2, height), (255, 255, 255, 0))  # white, so edges stay white
    d = ImageDraw.Draw(text)
    y = pad
    for lines, f, lh, fill in ((title_lines, tf, title_lh, (255, 255, 255, 255)),
                               (sub_lines, sf, sub_lh, (255, 255, 255, 225))):
        for line in lines:
            x = pad + (0 if align == "left" else (width - f.getlength(line)) / 2)
            d.text((x, y), line, font=f, fill=fill)
            y += lh
        y += int(sub_size * 0.6)
    shadow = Image.new("RGBA", text.size, (0, 0, 0, 0))
    shadow.putalpha(text.getchannel("A").point(lambda a: a * 0.6))
    out = Image.new("RGBA", text.size, (0, 0, 0, 0))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(8)), (0, 3))
    out.alpha_composite(text)
    return out


class Backdrop:
    """The app's own sky spread across the frame, dimmed so captions read on it, with a light
    behind the device that brightens as the lungs fill."""

    def __init__(self, center, sigma, vignette, left_scrim=0.0):
        ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
        r2 = ((xs - W / 2) / (W / 2)) ** 2 * 0.6 + ((ys - H / 2) / (H / 2)) ** 2 * 0.8
        shade = 1 - vignette * np.clip(r2, 0, 1.4)
        if left_scrim:
            shade *= 1 - left_scrim * np.clip(1 - xs / 1150, 0, 1) ** 1.4
        self.shade = shade[:, :, None]
        self.glow = np.exp(-((xs - center[0]) ** 2 + (ys - center[1]) ** 2) / (2 * sigma ** 2))[:, :, None] * GLOW

    def render(self, frame, glow, dim=1.0):
        a = np.asarray(frame, dtype=np.float32)
        strip = np.median(a[:, 0:max(8, a.shape[1] // 25), :], axis=1)
        # Bright skies are dimmed more, so white captions read on the day as well as the night.
        dim *= np.clip(1.02 - (strip.mean() - 50) / 380, 0.6, 0.95)
        rows = np.linspace(0, len(strip) - 1, H)
        col = np.stack([np.interp(rows, np.arange(len(strip)), strip[:, c]) for c in range(3)], axis=1) * dim
        img = col[:, None, :] * self.shade + self.glow * glow
        return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")


class EndCard:
    """Icon, name, line and the download pill, each easing in after `END`."""

    def __init__(self, platform):
        self.backdrop = Backdrop((W / 2, 340), 380, 0.35)
        self.icon = Image.open(ICON).convert("RGBA").resize((210, 210), Image.LANCZOS)
        self.title = self.text("Breathe Free", font("InterDisplay-SemiBold.otf", 112), (255, 255, 255, 255))
        self.line = self.text("Box breathing, with sound that keeps time", font("Inter-Regular.otf", 40),
                              (255, 255, 255, 228))
        label = f"Free for {'Android' if platform == 'android' else 'Mac'}   ·   {URL}"
        f = font("Inter-SemiBold.otf", 38)
        pw, ph = int(f.getlength(label)) + 76, 84
        pill = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        pill.paste(Image.new("RGBA", (pw, ph), (255, 255, 255, 245)), (0, 0), rounded_mask(pw, ph, ph // 2))
        ImageDraw.Draw(pill).text((38, ph / 2), label, font=f, fill=NAVY + (255,), anchor="lm")
        self.pill = pill

    @staticmethod
    def text(s, f, fill):
        box = f.getbbox(s)
        img = Image.new("RGBA", (box[2] + 40, box[3] + 40), (255, 255, 255, 0))
        ImageDraw.Draw(img).text((20, 20), s, font=f, fill=fill)
        shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
        shadow.putalpha(img.getchannel("A").point(lambda a: a * 0.5))
        out = Image.new("RGBA", img.size, (0, 0, 0, 0))
        out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(8)), (0, 3))
        out.alpha_composite(img)
        return out

    def render(self, frame, v):
        card = self.backdrop.render(frame, 0.12, dim=0.7)
        for img, y, delay in ((self.icon, 230, 0.1), (self.title, 460, 0.25), (self.line, 608, 0.4), (self.pill, 720, 0.55)):
            p = smooth((v - END - delay) / 0.55)
            if p > 0:
                card.alpha_composite(faded(img, p), ((W - img.width) // 2, int(y + 18 * (1 - ease_out(p)))))
        return card


# ------------------------------------------------------------------ Android: a phone

class Phone:
    """A phone around the app's frames. They fill its screen edge to edge, under the status
    bar and the gesture bar the renderer gave the app; this draws what the system shows there.
    Everything is built at the frames' own scale, then scaled once onto the canvas."""

    BEZEL, MARGIN = 26, 170
    SCREEN_RADIUS, BODY_RADIUS = 92, 118
    HEIGHT = 930          # the screen's height on the canvas at rest
    CENTER = (1350, 540)  # and the phone's centre

    def __init__(self, fw, fh, bars, taps):
        self.fw, self.fh = fw, fh
        self.top, self.bottom = bars
        self.taps = taps
        self.base = self.HEIGHT / fh
        b, m = self.BEZEL, self.MARGIN
        bw, bh = fw + 2 * b, fh + 2 * b
        sprite = Image.new("RGBA", (bw + 2 * m, bh + 2 * m), (0, 0, 0, 0))
        shadow = Image.new("L", sprite.size, 0)
        ImageDraw.Draw(shadow).rounded_rectangle([m, m + 44, m + bw, m + bh + 44], self.BODY_RADIUS, fill=150)
        sprite.putalpha(shadow.filter(ImageFilter.GaussianBlur(56)))
        d = ImageDraw.Draw(sprite)
        for y0, y1 in ((0.2, 0.27), (0.33, 0.45)):  # the power key and the volume rocker
            d.rounded_rectangle([m + bw - 6, m + bh * y0, m + bw + 7, m + bh * y1], 5, fill=(52, 57, 67, 255))
        body = Image.new("RGBA", (bw, bh), (70, 76, 88, 255))
        body.paste(Image.new("RGBA", (bw - 8, bh - 8), (12, 14, 18, 255)), (4, 4),
                   rounded_mask(bw - 8, bh - 8, self.BODY_RADIUS - 4))
        sprite.paste(body, (m, m), rounded_mask(bw, bh, self.BODY_RADIUS))
        self.sprite = sprite
        self.mask = rounded_mask(fw, fh, self.SCREEN_RADIUS)
        self.origin = m + b  # the screen's top-left in the sprite
        self.time_font = font("Inter-SemiBold.otf", 27)
        rest = (self.CENTER[0] - fw / 2 * self.base, self.CENTER[1] - fh / 2 * self.base)
        self.focus = (taps[0]["x"], taps[0]["y"])  # session length, where the camera pushes in
        self.anchor = (rest[0] + self.focus[0] * self.base, rest[1] + self.focus[1] * self.base)

    def system_bars(self, screen, v):
        """The status bar, its clock following the sky's time of day, and the gesture handle."""
        d = ImageDraw.Draw(screen, "RGBA")
        if self.top:
            light = np.asarray(screen.crop((0, 0, self.fw, self.top)).convert("L")).mean() > 150
            ink = (24, 28, 36, 230) if light else (255, 255, 255, 240)
            cy = self.top / 2
            hour = hour_at(v)
            d.text((52, cy), f"{(int(hour) - 1) % 12 + 1}:{int(hour % 1 * 60):02d}", font=self.time_font,
                   fill=ink, anchor="lm")
            x = self.fw - 52
            d.rounded_rectangle([x - 40, cy - 10, x - 4, cy + 10], 5, outline=ink, width=3)  # battery
            d.rectangle([x - 35, cy - 5, x - 13, cy + 5], fill=ink)
            d.rounded_rectangle([x - 3, cy - 5, x + 1, cy + 5], 2, fill=ink)
            d.polygon([(x - 78, cy + 10), (x - 56, cy + 10), (x - 56, cy - 12)], fill=ink)  # signal
            d.pieslice([x - 128, cy - 12, x - 88, cy + 28], 225, 315, fill=ink)  # wi-fi
            d.ellipse([self.fw / 2 - 19, cy - 19, self.fw / 2 + 19, cy + 19], fill=(4, 5, 7, 255),
                      outline=(40, 44, 52, 255), width=2)  # the camera
        if self.bottom:
            box = (0, self.fh - self.bottom, self.fw, self.fh)
            light = np.asarray(screen.crop(box).convert("L")).mean() > 150
            hy = self.fh - self.bottom / 2
            d.rounded_rectangle([self.fw / 2 - 108, hy - 4, self.fw / 2 + 108, hy + 4], 4,
                                fill=(24, 28, 36, 200) if light else (255, 255, 255, 220))

    def touches(self, screen, v):
        """Where the finger lands: a soft dot, and a ring that spreads and fades."""
        d = ImageDraw.Draw(screen, "RGBA")
        for t in self.taps:
            age = v - t["v"]
            x, y = t["x"], t["y"]
            if 0 <= age < 0.3:
                r = 20
                d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, int(120 * (1 - age / 0.3))))
            if 0 <= age < 0.45:
                p = age / 0.45
                r = 22 + 44 * ease_out(p)
                d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 255, 255, int(200 * (1 - p))), width=4)

    def draw(self, canvas, frame, v, zoom):
        screen = frame.copy()
        self.system_bars(screen, v)
        self.touches(screen, v)
        sprite = self.sprite.copy()
        sprite.paste(screen, (self.origin, self.origin), self.mask)
        s = self.base * zoom
        small = sprite.resize((round(sprite.width * s), round(sprite.height * s)), Image.LANCZOS)
        composite(canvas, small, self.anchor[0] - (self.focus[0] + self.origin) * s,
                  self.anchor[1] - (self.focus[1] + self.origin) * s)


# ------------------------------------------------------------------ Mac: a window and a pointer

class MacHome:
    """Where things are on the Mac home screen, measured from its frames, and what the still
    renderer can't show: the volume slider (an AppKit control it leaves a placeholder for) and
    the session-length circles moving. The circles are cut from the real frames and moved on
    the springs CyclePicker uses."""

    def __init__(self, load):
        closed = np.asarray(load(frame_index_before(TAPS["open"]) - 3), dtype=np.int32)
        h, w = closed.shape[:2]
        self.pt = w / 1280  # pixels per point
        cx = w / 2
        white = closed.min(axis=2) > 215
        circle = begin = None
        for y0, y1 in runs(white[:, w // 4: 3 * w // 4].sum(axis=1) > 3):
            if y1 - y0 < 6:
                continue
            for x0, x1 in runs(white[y0:y1].any(axis=0)):
                if not x0 < cx < x1:
                    continue
                if circle is None and 40 * self.pt < x1 - x0 < 56 * self.pt and 40 * self.pt < y1 - y0 < 56 * self.pt:
                    circle = ((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2)
                elif circle is not None and begin is None and x1 - x0 > 4 * (y1 - y0):
                    begin = ((x0 + x1) / 2, (y0 + y1) / 2)
        if not circle or not begin:
            sys.exit("could not find session length and Begin in the Mac frames")
        self.cx, self.cy, self.r = circle
        self.step = (46 + 8) * self.pt  # CyclePicker: 46 point circles, 8 points apart
        self.before = CHOICES.index(SCRIPT["cycles"]["before"])
        self.picked = CHOICES.index(SCRIPT["cycles"]["picked"])
        self.targets = {
            "open": (self.cx, self.cy),
            "pick": (self.cx + self.slot(self.picked), self.cy),
            "begin": begin,
        }
        yellow = (closed[:, :, 0] > 200) & (closed[:, :, 1] > 150) & (closed[:, :, 2] < 110)
        ys, xs = np.nonzero(yellow)
        self.slider = (xs.min() - 2, ys.min() - 2, xs.max() + 3, ys.max() + 3) if len(xs) else None
        self.begin_probe = (int(begin[0] + 100 * self.pt), int(begin[1]))

        # Every circle's look, from a frame with the row settled open (the count before the pick
        # chosen), and the picked count chosen, from one settled after.
        size = int(2 * (self.r + 3)) | 1
        mask = disc_mask(size, self.r + 0.5)

        def cut(img, x, y):
            x0, y0 = round(x) - size // 2, round(y) - size // 2
            patch = img.crop((x0, y0, x0 + size, y0 + size)).convert("RGBA")
            patch.putalpha(mask)
            return patch

        opened = load(frame_index_before(TAPS["pick"]) - 2)
        self.looks = [cut(opened, self.cx + self.slot(i), self.cy) for i in range(len(CHOICES))]
        self.picked_look = cut(load(frame_index_before(TAPS["pick"]) + 12), self.cx, self.cy)
        self.band = (round(self.cy - self.r - 2.5), round(self.cy + self.r + 2.5) + 1,
                     round(self.cx - 2.5 * self.step - self.r - 14), round(self.cx + 2.5 * self.step + self.r + 14))

    def slot(self, i):
        return (i - (len(CHOICES) - 1) / 2) * self.step

    def fix_slider(self, frame):
        """Paints the volume slider where its placeholder is: the sky behind it, a track, the
        level filled to the app's default of 0.85 and a knob."""
        if not self.slider:
            return frame
        x0, y0, x1, y1 = self.slider
        a = np.asarray(frame, dtype=np.float32).copy()
        t = np.linspace(0, 1, y1 - y0)[:, None, None]
        a[y0:y1, x0:x1] = a[y0 - 3, x0:x1][None] * (1 - t) + a[y1 + 3, x0:x1][None] * t
        img = Image.fromarray(a.clip(0, 255).astype(np.uint8))
        night = min(frame.getpixel(self.begin_probe)) > 200  # Begin is white on a night sky
        d = ImageDraw.Draw(img, "RGBA")
        s, cy = self.pt, (y0 + y1) / 2
        left, right = x0 + 6 * s, x1 - 6 * s
        knob = left + (right - left) * 0.85
        d.rounded_rectangle([left, cy - 2 * s, right, cy + 2 * s], 2 * s,
                            fill=(255, 255, 255, 70) if night else (15, 42, 67, 46))
        d.rounded_rectangle([left, cy - 2 * s, knob, cy + 2 * s], 2 * s, fill=(10, 132, 255, 255))
        r = 9 * s
        d.ellipse([knob - r, cy - r + 1.5, knob + r, cy + r + 1.5], fill=(0, 0, 0, 55))
        d.ellipse([knob - r, cy - r, knob + r, cy + r], fill=(255, 255, 255, 255), outline=(0, 0, 0, 38))
        return img

    def clear_row(self, frame):
        """The frame with the row of circles taken out: the sky between the rows just above
        and below it, eased into the frame at the row's ends."""
        y0, y1, x0, x1 = self.band
        a = np.asarray(frame, dtype=np.float32).copy()
        t = np.linspace(0, 1, y1 - y0)[:, None, None]
        fill = a[y0 - 1, x0:x1][None] * (1 - t) + a[y1, x0:x1][None] * t
        edge = np.clip(np.minimum(np.arange(x1 - x0), np.arange(x1 - x0)[::-1]) / 12, 0, 1)[None, :, None]
        a[y0:y1, x0:x1] = fill * edge + a[y0:y1, x0:x1] * (1 - edge)
        return Image.fromarray(a.clip(0, 255).astype(np.uint8)).convert("RGBA")

    def picker_motion(self, frame, v):
        """Session length fanning out from the chosen circle when clicked, and folding into
        the picked one: CyclePicker's springs, on the real circles."""
        opening, picking = v - TAPS["open"], v - TAPS["pick"]
        state = []  # (on top, x offset, scale, opacity, look)
        if 0 <= opening < 0.9:
            for i, look in enumerate(self.looks):
                x = spring(opening - 0.028 * abs(i - self.before), 0.42, 0.68)
                chosen = i == self.before
                state.append((chosen, self.slot(i) * x, 1 if chosen else 0.55 + 0.45 * x,
                              1 if chosen else clamp01(x), look))
        elif 0 <= picking < 0.6:
            x = spring(picking, 0.32, 1.0)
            for i, look in enumerate(self.looks):
                if i == self.picked:
                    state.append((True, self.slot(i) * (1 - x), 1, 1, Image.blend(look, self.picked_look, x)))
                else:
                    state.append((False, self.slot(i) * (1 - x), 1 - 0.45 * x, clamp01(1 - x), look))
        else:
            return frame
        img = self.clear_row(frame)
        for _, dx, scale, alpha, look in sorted(state, key=lambda s: s[0]):
            if alpha <= 0.004:
                continue
            if abs(scale - 1) > 1e-3:
                n = max(3, round(look.width * scale))
                look = look.resize((n, n), Image.LANCZOS)
            look = faded(look, alpha)
            img.alpha_composite(look, (round(self.cx + dx - look.width / 2), round(self.cy - look.height / 2)))
        return img.convert("RGB")


class MacWindow:
    """A Mac window around the app's frames: rounded, shadowed, with its three buttons. Built
    at the frames' own scale, then scaled once onto the canvas."""

    MARGIN, RADIUS = 170, 20
    WIDTH, TOP = 1360, 34  # on the canvas at rest

    def __init__(self, fw, fh, focus):
        self.base = self.WIDTH / fw
        m = self.MARGIN
        sprite = Image.new("RGBA", (fw + 2 * m, fh + 2 * m), (0, 0, 0, 0))
        shadow = Image.new("L", sprite.size, 0)
        ImageDraw.Draw(shadow).rounded_rectangle([m, m + 40, m + fw, m + fh + 40], self.RADIUS, fill=165)
        sprite.putalpha(shadow.filter(ImageFilter.GaussianBlur(60)))
        self.sprite = sprite
        self.mask = rounded_mask(fw, fh, self.RADIUS)
        chrome = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        d = ImageDraw.Draw(chrome)
        d.rounded_rectangle([0, 0, fw - 1, fh - 1], self.RADIUS, outline=(255, 255, 255, 52), width=2)
        for i, (fill, ring) in enumerate((((255, 95, 87), (224, 68, 62)), ((254, 188, 46), (222, 161, 35)),
                                          ((40, 200, 64), (26, 171, 41)))):
            cx, cy = 28 + 25 * i, 28
            d.ellipse([cx - 7.5, cy - 7.5, cx + 7.5, cy + 7.5], fill=fill + (255,), outline=ring + (255,))
        self.chrome = chrome
        self.focus = focus  # session length, where the camera pushes in
        self.anchor = ((W - self.WIDTH) / 2 + focus[0] * self.base, self.TOP + focus[1] * self.base)

    def to_canvas(self, p, zoom):
        s = self.base * zoom
        return self.anchor[0] + (p[0] - self.focus[0]) * s, self.anchor[1] + (p[1] - self.focus[1]) * s

    def draw(self, canvas, frame, v, zoom):
        content = frame.convert("RGBA")
        content.alpha_composite(self.chrome)
        sprite = self.sprite.copy()
        sprite.paste(content, (self.MARGIN, self.MARGIN), self.mask)
        s = self.base * zoom
        small = sprite.resize((round(sprite.width * s), round(sprite.height * s)), Image.LANCZOS)
        composite(canvas, small, *self.to_canvas((-self.MARGIN, -self.MARGIN), zoom))


class Pointer:
    """The Mac arrow, gliding to each click target and clicking on the beat."""

    # The arrow's outline in points, its tip at the origin.
    SHAPE = [(0, 0), (0, 17.5), (4.2, 13.6), (7.1, 20.3), (9.8, 19.1), (6.9, 12.6), (12.6, 12.6)]

    def __init__(self, targets, frame_size):
        fw, fh = frame_size
        o, p, b = TAPS["open"], TAPS["pick"], TAPS["begin"]
        rest, away = (fw * 0.72, fh * 0.88), (fw * 0.8, fh * 0.97)
        # (time, where on the frame): the pointer eases between these.
        self.path = [(2.55, rest), (o - 0.15, targets["open"]), (o + 0.35, targets["open"]),
                     (p - 0.15, targets["pick"]), (p + 0.35, targets["pick"]), (b - 0.15, targets["begin"]),
                     (b + 0.2, targets["begin"]), (b + 0.95, away)]
        self.clicks = [o, p, b]

    def where(self, v):
        if v <= self.path[0][0]:
            return self.path[0][1]
        for (t0, p0), (t1, p1) in zip(self.path, self.path[1:]):
            if v <= t1:
                x = smooth((v - t0) / (t1 - t0))
                return p0[0] + (p1[0] - p0[0]) * x, p0[1] + (p1[1] - p0[1]) * x
        return self.path[-1][1]

    def draw(self, canvas, v, window, zoom):
        alpha = smooth((v - 2.55) / 0.3) * (1 - smooth((v - (TAPS["begin"] + 0.5)) / 0.45))
        if alpha <= 0:
            return
        x, y = window.to_canvas(self.where(v), zoom)
        k = 1.55 * zoom
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer, "RGBA")
        for c in self.clicks:
            age = v - c
            if 0 <= age < 0.45:
                p = age / 0.45
                r = (6 + 22 * ease_out(p)) * zoom
                d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 255, 255, int(210 * (1 - p))), width=3)
        press = 0.88 if any(0 <= v - c < 0.12 for c in self.clicks) else 1.0
        pts = [(x + px * k * press, y + py * k * press) for px, py in self.SHAPE]
        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).polygon([(px + 1, py + 2.5) for px, py in pts], fill=(0, 0, 0, 120))
        layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(2)))
        d.polygon(pts, fill=(0, 0, 0, 255))
        d.line(pts + [pts[0]], fill=(255, 255, 255, 255), width=3, joint="curve")
        canvas.alpha_composite(faded(layer, alpha))


# ------------------------------------------------------------------ sound

def read_wav(path):
    with wave.open(str(path)) as w:
        assert w.getframerate() == RATE and w.getnchannels() == 2 and w.getsampwidth() == 2
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768
    return data.reshape(-1, 2)


def mix_sound(audio_dir, out_wav):
    total = int(SECONDS * RATE)
    mix = np.zeros((total, 2), np.float32)

    def add(sound, at, gain, fade_in=0.0):
        sound = sound * gain
        if fade_in:
            n = int(fade_in * RATE)
            sound[:n] *= np.linspace(0, 1, n)[:, None]
        start = int(round(at * RATE))
        n = min(len(sound), total - start)
        mix[start:start + n] += sound[:n]

    session = read_wav(audio_dir / "session.wav")
    # Session time 0 is video time LAG, so every bell lands on the frame that shows its change.
    t = np.arange(len(session)) / RATE + LAG
    x = np.clip((t - (END + 0.7)) / 2.3, 0, 1)
    session *= (1 - x * x * (3 - 2 * x))[:, None]
    add(session, LAG, 1.0)
    closing = read_wav(audio_dir / "closing.wav")
    add(closing, 0.15, 0.7, fade_in=0.06)        # a warm chord to open
    add(closing, END + 0.45, 0.85, fade_in=0.06)  # and to close
    n = int(0.5 * RATE)
    mix[-n:] *= np.linspace(1, 0, n)[:, None]
    with wave.open(str(out_wav), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(mix, -1, 1) * 32767).astype("<i2").tobytes())


def loudness_normalised(src, dst):
    """Two-pass loudnorm to YouTube's -14 LUFS, true peak under -1.5 dB."""
    first = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(src), "-af",
                            "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                           capture_output=True, text=True).stderr
    m = json.loads(first[first.rindex("{"):first.rindex("}") + 1])
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(src), "-af",
                    "loudnorm=I=-14:TP=-1.5:LRA=11:linear=true:"
                    f"measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}:"
                    f"measured_thresh={m['input_thresh']}:offset={m['target_offset']}",
                    "-ar", str(RATE), str(dst)], check=True)
    return float(m["input_i"])


# ------------------------------------------------------------------ the edit

class Edit:
    """Draws the promo's frames for one platform."""

    def __init__(self, platform, frames_dir):
        self.platform = platform
        self.frames_dir = frames_dir
        fw, fh = self.load(0).size
        self.pointer = self.home = self.scrim = None
        if platform == "android":
            size = json.loads((frames_dir / "size.json").read_text())
            taps = json.loads((frames_dir / "taps.json").read_text())
            self.device = Phone(fw, fh, (size.get("statusBar", 0), size.get("navigationBar", 0)), taps)
            self.backdrop = Backdrop(Phone.CENTER, 430, 0.24, left_scrim=0.36)
            self.most_zoom = 1.5
            caption_width, title_size, sub_size, self.align = 780, 84, 40, "left"
        else:
            self.home = MacHome(self.load)
            self.device = MacWindow(fw, fh, self.home.targets["open"])
            self.pointer = Pointer(self.home.targets, (fw, fh))
            self.backdrop = Backdrop((W / 2, MacWindow.TOP + fh * self.device.base / 2), 560, 0.3)
            self.most_zoom = 1.25
            caption_width, title_size, sub_size, self.align = 1600, 56, 30, "center"
            # A soft dark band under the captions, for when the window reaches down behind them.
            ys = np.arange(H, dtype=np.float32)[:, None]
            shade = (np.clip((ys - 870) / (H - 870), 0, 1) ** 1.3 * 150).astype(np.uint8)
            self.scrim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            self.scrim.putalpha(Image.fromarray(np.broadcast_to(shade, (H, W)).copy()))
        breaks = (lambda text: text) if self.align == "left" else (lambda text: text.replace("\n", " "))
        self.captions = [(s, e, caption_image(breaks(t), breaks(sub), caption_width, title_size, sub_size, self.align))
                         for s, e, t, sub in CAPTIONS[platform]]
        self.end_card = EndCard(platform)
        self.cache = {}

    def load(self, k):
        return Image.open(self.frames_dir / f"f{k:05d}.jpg").convert("RGB")

    def frame(self, k):
        """The app's frame k, with the Mac's home screen made whole."""
        if k not in self.cache:
            img = self.load(k)
            if self.home and k / FPS < TAPS["begin"]:
                img = self.home.picker_motion(self.home.fix_slider(img), k / FPS)
            if len(self.cache) > 8:
                self.cache.clear()
            self.cache[k] = img
        return self.cache[k]

    def draw(self, k):
        v = k / FPS
        screen = self.frame(k)
        # Begin: the home screen gives way to the session.
        if TAPS["begin"] <= v < TAPS["begin"] + 0.5:
            screen = Image.blend(self.frame(frame_index_before(TAPS["begin"])), screen,
                                 smooth((v - TAPS["begin"]) / 0.5))
        zoom = zoom_at(v, self.most_zoom)
        canvas = self.backdrop.render(screen, 0.06 + 0.16 * breath_level(v))
        self.device.draw(canvas, screen, v, zoom)
        if self.pointer:
            self.pointer.draw(canvas, v, self.device, zoom)
        if self.scrim:
            canvas.alpha_composite(self.scrim)
        for s, e, img in self.captions:
            a = shown(v, s, e)
            if a > 0:
                dy = int(16 * (1 - ease_out((v - s) / 0.5)))
                if self.align == "left":
                    pos = (126, H // 2 - img.height // 2 + dy)
                else:
                    pos = ((W - img.width) // 2, 896 + dy)
                canvas.alpha_composite(faded(img, a), pos)
        if v >= END:
            canvas = Image.blend(canvas, self.end_card.render(screen, v), smooth((v - END) / 0.8))
        return canvas.convert("RGB")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--stills=")]
    stills = [float(t) for a in sys.argv[1:] if a.startswith("--stills=") for t in a[9:].split(",")]
    if len(args) != 4 or args[0] not in CAPTIONS:
        sys.exit(__doc__)
    platform, frames_dir, audio_dir, out = args[0], Path(args[1]), Path(args[2]), Path(args[3])
    edit = Edit(platform, frames_dir)
    if stills:
        # Just these moments, as pictures beside `out`, to check the look before a full encode.
        for t in stills:
            path = out.with_name(f"{out.stem}-{t:05.2f}.png")
            edit.draw(int(round(t * FPS))).save(path)
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
            enc.stdin.write(edit.draw(k).tobytes())
            if k % 150 == 0:
                print(f"frame {k} of {FRAMES}", flush=True)
        enc.stdin.close()
        if enc.wait() != 0:
            sys.exit("ffmpeg failed")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
