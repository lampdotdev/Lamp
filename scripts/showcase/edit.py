"""Edits a recorded showcase take into a reel: the take filling the frame under Lamp's logo, with a camera
that eases to what the app's showcase.json focused on, a cursor that glides to each thing it acted on, the app's voice and the person's where they
were heard with captions under the window, notifications as banners, waits for the AI at double speed, cuts where the
storyboard marks them, and an end card, Made with Lamp. Writes reel.mp4 (1080p, with sound), loop.webp (a silent loop for a README, which can't
play a video it holds) and poster.png into the output folder.

    python edit.py <take folder> <app folder> <output folder> <Lamp's logo> <the site's font>

The take folder is what scripts/showcase-starters.sh leaves: raw.mp4, record.log, events.tsv (LampShowcase's log),
the voice files it names and showcase.json, whose `reel` may name `speaker` (who the app's voice is),
`you` (who the person is, "You") and `voice` (macOS's voice for the person's lines, "Samantha")."""
import json, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

take, app, outdir = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
logo = Image.open(sys.argv[4]).convert("RGBA")
site_font = sys.argv[5]
outdir.mkdir(parents=True, exist_ok=True)
script = json.loads((take / "showcase.json").read_text())
reel = script.get("reel", {})

W, H, FPS = 1920, 1080, 30
PAPER, INK, ACCENT = (243, 238, 228), (31, 52, 120), (238, 205, 92)
FONTS = "/System/Library/Fonts"
def font(name, size): return ImageFont.truetype(f"{FONTS}/{name}", size)
SERIF_I = lambda s: font("NewYorkItalic.ttf", s)
SANS = lambda s: font("SFNS.ttf", s)

# --- what the reel says around the app --------------------------------------------------------------------------
about = json.loads((app / "lamp-app.json").read_text()) if (app / "lamp-app.json").exists() else {}
title = about.get("name") or app.name
icon_path = next((p for p in [app / "icon.png", app / ".github/icon/icon.png"] if p.exists()), None)
icon = Image.open(icon_path).convert("RGBA") if icon_path else None

# --- what happened, on the take's clock -------------------------------------------------------------------------
log = (take / "record.log").read_text().split("\n")
window_line = next(l for l in log if l.startswith("window "))
start = float(next(l for l in log if l.startswith("start ")).split()[1])
_, _, _, ww, wh, scale = window_line.split()
SRC_W, SRC_H = int(float(ww) * float(scale)), int(float(wh) * float(scale))
events = []
for row in (take / "events.tsv").read_text().strip().split("\n"):
    t, kind, *rest = row.split("\t")
    events.append((float(t) - start, kind, rest))
def first(kind, after=-1e9):
    return next((e for e in events if e[1] == kind and e[0] > after), None)
def rect(text): return [float(v) for v in text.split(",")]

def audio(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", "22050", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)

# The app's lines, heard where it began speaking; the person's, as their words began, in a voice made to fit the time
# their words took to appear.
voices = []
speaker, you_name, you_voice = reel.get("speaker", title), reel.get("you", "You"), reel.get("voice", "Samantha")
for e in events:
    if e[1] == "say":
        clip = take / e[2][0]
        samples = audio(clip)
        voices.append(dict(t=e[0], dur=len(samples) / 22050, file=clip, who=speaker, caption=e[2][2] or e[2][1], env=samples))
heard = [e for e in events if e[1] == "hear"]
for i, e in enumerate(heard):
    text, caption = e[2][0], e[2][1] if len(e[2]) > 1 else ""
    target = len(text.split()) * 0.34 + 0.2
    aiff = take / f"you-{i + 1}.aiff"
    subprocess.run(["say", "-v", you_voice, "-r", "170", "-o", str(aiff), text], check=True)
    rate = max(90, min(320, int(170 * (len(audio(aiff)) / 22050) / target)))
    subprocess.run(["say", "-v", you_voice, "-r", str(rate), "-o", str(aiff), text], check=True)
    samples = audio(aiff)
    voices.append(dict(t=e[0] + 0.5, dur=len(samples) / 22050, file=aiff, who=you_name, caption=caption or text, env=samples, you=True))
captioned = bool(voices)

acts = [dict(t=e[0], r=rect(e[2][0])) for e in events if e[1] == "act"]
for a in acts: a["x"], a["y"] = a["r"][0] + a["r"][2] / 2, a["r"][1] + a["r"][3] / 2
notes = [dict(t=e[0], title=e[2][0], body=e[2][1] if len(e[2]) > 1 else "") for e in events if e[1] == "notification"]

# --- the edit: which part of the take plays when, and how fast --------------------------------------------------
END = 3.0
ready = first("ready")
src_from = max(0.0, (acts[0]["t"] - 1.4) if acts else (ready[0] if ready else 0))
end = first("end")
src_to = (end[0] - 0.4) if end else events[-1][0]
fast = []
for e in events:
    if e[1] == "ai":
        done = first("ai-end", e[0])
        if done and done[0] - e[0] > 0.8: fast.append((e[0] + 0.4, done[0] - 0.1))
segments, t = [], src_from
for a, b in sorted(fast):
    if b <= t: continue
    if a > t: segments.append((t, a, 1.0))
    segments.append((max(a, t), b, 2.0)); t = b
segments.append((t, src_to, 1.0))
# A storyboard's {"mark": "cut"} and the next {"mark": "resume"} leave out what's between them: a hard cut. Never over a voice.
marks = [(e[0], e[2][0]) for e in events if e[1] == "mark"]
cuts = [(t, next((u for u, w in marks if w == "resume" and u > t), src_to)) for t, w in marks if w == "cut"]
for v in voices:
    if any(v["t"] < y and x < v["t"] + v["dur"] for x, y in cuts):
        sys.exit(f"A cut would land on what's said at {v['t']:.1f} s: \"{v['caption']}\". Move the storyboard's marks.")
for x, y in cuts:
    segments = [part for a, b, speed in segments for part in ((a, min(b, x), speed), (max(a, y), b, speed)) if part[0] < part[1]]
def out_time(src):
    o = 0.0
    for a, b, speed in segments:
        if src <= a: return o
        if src < b: return o + (src - a) / speed
        o += (b - a) / speed
    return o
def src_time(o):
    for a, b, speed in segments:
        d = (b - a) / speed
        if o < d: return a + o * speed
        o -= d
    return src_to
VIDEO_END = out_time(src_to)
TOTAL = VIDEO_END + END

# --- the camera ----------------------------------------------------------------------------------------------------
# The window fills the frame, a little past its edges so its rounded corners are left out. A storyboard's window is 16:9;
# one that isn't has black beside it.
BASE = min(W / SRC_W, H / SRC_H) * 1.02
win_w, win_h = SRC_W * BASE, SRC_H * BASE
win_x, win_y = (W - win_w) / 2, (H - win_h) / 2
BAND = 200 if captioned else 0
def place(x, y, w, h, area):
    """The camera (a rect of the stage) that shows that part of the window as large as fits in `area` of the frame, never
    so far out or to the side that it shows past the window."""
    ax0, ay0, ax1, ay1 = area
    rw, rh = w * win_w, h * win_h
    z = max(1, min((ax1 - ax0) / rw, (ay1 - ay0) / rh))
    cx, cy = win_x + (x + w / 2) * win_w, win_y + (y + h / 2) * win_h
    cam_w, cam_h = W / z, H / z
    cam_x, cam_y = cx - (ax0 + ax1) / 2 / z, cy - (ay0 + ay1) / 2 / z
    def keep(at, size, low, span): return low + (span - size) / 2 if size >= span else max(low, min(at, low + span - size))
    return (keep(cam_x, cam_w, win_x, win_w), keep(cam_y, cam_h, win_y, win_h), cam_w, cam_h)
FULL = REST = place(0, 0, 1, 1, (0, 0, W, H))
def framing(r):
    if r == [0, 0, 1, 1]: return REST
    pad = 0.06
    x, y, w, h = r[0] - pad / 2, r[1] - pad / 2, r[2] + pad, r[3] + pad
    # Never closer than a third of the window, so a button doesn't fill the frame.
    if w < 0.34: x, w = x - (0.34 - w) / 2, 0.34
    if h < 0.24: y, h = y - (0.24 - h) / 2, 0.24
    return place(x, y, w, h, (0, 0, W, H - BAND))
keys = [(0.0, FULL)]
for e in events:
    if e[1] == "focus":
        o = out_time(e[0])
        keys += [(o, keys[-1][1] if keys else REST), (o + 0.9, framing(rect(e[2][0])))]
keys.sort(key=lambda k: k[0])
keys += [(VIDEO_END - 0.9, keys[-1][1]), (VIDEO_END, FULL)]
def ease(x): return x * x * (3 - 2 * x)
def camera(o):
    if o <= keys[0][0]: return keys[0][1]
    for (t0, c0), (t1, c1) in zip(keys, keys[1:]):
        if o <= t1:
            k = ease(min(1, max(0, (o - t0) / max(1e-6, t1 - t0))))
            return tuple(a + (b - a) * k for a, b in zip(c0, c1))
    return keys[-1][1]

# --- drawing --------------------------------------------------------------------------------------------------------
BLACK = Image.new("RGBA", (W, H), (0, 0, 0, 255))
# Lamp's logo in the corner of the recording, half see-through.
MARK = logo.resize((76, 76), Image.LANCZOS)
MARK.putalpha(MARK.getchannel("A").point(lambda a: int(a * 0.55)))

def size(d, s, f):
    b = d.textbbox((0, 0), s, font=f); return b[2] - b[0], b[3] - b[1]
def wrap(d, s, f, width):
    lines, cur = [], ""
    for word in s.split():
        trial = (cur + " " + word).strip()
        if size(d, trial, f)[0] > width and cur: lines.append(cur); cur = word
        else: cur = trial
    return lines + ([cur] if cur else [])

def caption(frame, who, text, alpha, bars=None):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f, small = SERIF_I(36), SANS(19)
    lines = wrap(d, text, f, 1180)[:3]
    left = 120 if bars is not None else 0
    bw = max(size(d, l, f)[0] for l in lines) + 80 + left
    bh = 46 + 48 * len(lines) + 30
    x0, y0 = (W - bw) / 2, H - bh - 34
    d.rounded_rectangle((x0, y0, x0 + bw, y0 + bh), 26, fill=(*INK, int(235 * alpha)))
    d.text((x0 + 40 + left, y0 + 22), who.upper(), font=small, fill=(*ACCENT, int(255 * alpha)))
    for i, l in enumerate(lines):
        d.text((x0 + 40 + left, y0 + 52 + i * 48), l, font=f, fill=(*PAPER, int(255 * alpha)))
    if bars is not None:
        cx, cy = x0 + 80, y0 + bh / 2
        d.ellipse((cx - 38, cy - 38, cx + 38, cy + 38), fill=(*ACCENT, int(255 * alpha)))
        for i, v in enumerate(bars):
            bx, h = cx - 21 + i * 9, 6 + v * 46
            d.rounded_rectangle((bx - 2.5, cy - h / 2, bx + 2.5, cy + h / 2), 2.5, fill=(*INK, int(255 * alpha)))
    frame.alpha_composite(layer)

def banner(frame, note, alpha, slide):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bw, bh = 560, 110
    x0, y0 = W - bw - 40 + (1 - slide) * (bw + 60), 40
    d.rounded_rectangle((x0, y0, x0 + bw, y0 + bh), 22, fill=(250, 250, 250, int(240 * alpha)), outline=(0, 0, 0, int(30 * alpha)))
    if icon:
        ic = icon.resize((56, 56), Image.LANCZOS)
        layer.alpha_composite(ic, (int(x0 + 22), int(y0 + 27)))
    d.text((x0 + 94, y0 + 24), note["title"], font=SANS(24), fill=(20, 20, 20, int(255 * alpha)))
    body = wrap(d, note["body"], SANS(20), bw - 120)[:2]
    for i, l in enumerate(body):
        d.text((x0 + 94, y0 + 56 + i * 24), l, font=SANS(20), fill=(70, 70, 70, int(255 * alpha)))
    frame.alpha_composite(layer)

CURSOR = [(0, 0), (0, 30), (8, 23), (13, 35), (18, 33), (13, 21), (23, 21)]
def cursor(frame, x, y, pressed):
    d = ImageDraw.Draw(frame)
    s = 1.25 * (0.85 if pressed else 1)
    pts = [(x + px * s, y + py * s) for px, py in CURSOR]
    d.polygon([(px + 2, py + 3) for px, py in pts], fill=(0, 0, 0, 60))
    d.polygon(pts, fill=(20, 20, 20, 255), outline=(255, 255, 255, 255), width=2)

def ring(frame, x, y, k):
    r = 10 + 34 * k
    ImageDraw.Draw(frame).ellipse((x - r, y - r, x + r, y + r), outline=(*INK, int(200 * (1 - k))), width=4)

def centered(d, y, text, f, fill):
    d.text(((W - size(d, text, f)[0]) / 2, y), text, font=f, fill=fill)

def end_card():
    img = BLACK.copy()
    img.alpha_composite(logo.resize((220, 220), Image.LANCZOS), (int(W / 2 - 110), int(H / 2 - 190)))
    f = ImageFont.truetype(site_font, 84)
    f.set_variation_by_axes([600])
    centered(ImageDraw.Draw(img), H / 2 + 70, "Made with Lamp", f, (255, 255, 255))
    return img
END_CARD = end_card()

def stage(src, o):
    cam = camera(o)
    z = W / cam[2]
    rx, ry, rw, rh = (win_x - cam[0]) * z, (win_y - cam[1]) * z, win_w * z, win_h * z
    img = BLACK.copy()
    vx0, vy0, vx1, vy1 = max(0, rx), max(0, ry), min(W, rx + rw), min(H, ry + rh)
    box = ((vx0 - rx) / rw * SRC_W, (vy0 - ry) / rh * SRC_H, (vx1 - rx) / rw * SRC_W, (vy1 - ry) / rh * SRC_H)
    img.paste(src.resize((int(round(vx1 - vx0)), int(round(vy1 - vy0))), Image.LANCZOS, box=box), (int(round(vx0)), int(round(vy0))))
    img.alpha_composite(MARK, (W - 76 - 36, H - 76 - 36))
    return img, (lambda fx, fy: (rx + fx * rw, ry + fy * rh))

def cursor_at(o, to_out):
    """Glides from one thing acted on to the next, arriving just before the action."""
    prev = None
    for a in acts:
        t = out_time(a["t"]) + 0.3
        if o < t:
            if prev is None: return None
            pt, pa = prev
            glide = max(pt + 0.3, t - 0.9)
            k = ease(min(1, max(0, (o - glide) / max(0.01, t - 0.15 - glide))))
            return to_out(pa["x"] + (a["x"] - pa["x"]) * k, pa["y"] + (a["y"] - pa["y"]) * k), False
        prev = (t, a)
    return (to_out(prev[1]["x"], prev[1]["y"]), o - prev[0] < 0.15) if prev else None

def bars(v, o):
    t = src_time(o) - v["t"]
    out = []
    for i in range(6):
        at = int((t - i * 0.04) * 22050)
        seg = v["env"][max(0, at - 600):max(0, at)]
        out.append(min(1.0, float(np.sqrt(np.mean(seg ** 2))) * 5) if len(seg) else 0.0)
    return out

# --- render -------------------------------------------------------------------------------------------------------
reader = subprocess.Popen(["ffmpeg", "-v", "error", "-i", str(take / "raw.mp4"), "-vf", "fps=60", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                          stdout=subprocess.PIPE)
frame_bytes, index, current = SRC_W * SRC_H * 3, -1, None
def source(st):
    global index, current
    while index < int(st * 60):
        buf = reader.stdout.read(frame_bytes)
        if len(buf) < frame_bytes: break
        current = Image.frombuffer("RGB", (SRC_W, SRC_H), buf); index += 1
    return current

silent = outdir / "reel.silent.mp4"
writer = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                           "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p", str(silent)], stdin=subprocess.PIPE)
last_video = None
for i in range(int(TOTAL * FPS)):
    o = i / FPS
    if o < VIDEO_END:
        st = src_time(o)
        frame, to_out = stage(source(st), o)
        for a in acts:
            k = (o - out_time(a["t"]) - 0.3) / 0.6
            if 0 <= k < 1: ring(frame, *to_out(a["x"], a["y"]), k)
        cur = cursor_at(o, to_out)
        if cur: cursor(frame, *cur[0], cur[1])
        for v in voices:
            if v["t"] - 0.3 <= st <= v["t"] + v["dur"] + 0.5:
                alpha = min(1, (st - v["t"] + 0.3) / 0.25, (v["t"] + v["dur"] + 0.5 - st) / 0.25)
                caption(frame, v["who"], v["caption"], alpha, bars(v, o) if v.get("you") else None)
        for n in notes:
            k = st - n["t"]
            if 0 <= k <= 4.0: banner(frame, n, min(1, k / 0.3, (4.0 - k) / 0.4), ease(min(1, k / 0.4)))
        last_video = frame
    else:
        k = (o - VIDEO_END) / 0.6
        frame = Image.blend(last_video, END_CARD, k) if k < 1 and last_video else END_CARD
    writer.stdin.write(frame.tobytes())
writer.stdin.close(); writer.wait(); reader.kill()

# --- sound, the loop and the poster -------------------------------------------------------------------------------
reel_path = outdir / "reel.mp4"
if voices:
    inputs, chains = [], []
    for k, v in enumerate(voices):
        inputs += ["-i", str(v["file"])]
        delay = int(out_time(v["t"]) * 1000)
        chains.append(f"[{k + 1}:a]aresample=48000,adelay={delay}|{delay}[a{k}]")
    chains.append("".join(f"[a{k}]" for k in range(len(voices))) + f"amix=inputs={len(voices)}:normalize=0,apad[aout]")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(silent)] + inputs + ["-filter_complex", ";".join(chains),
                    "-map", "0:v", "-map", "[aout]", "-shortest", "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                    "-movflags", "+faststart", str(reel_path)], check=True)
    silent.unlink()
else:
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(silent), "-c", "copy", "-movflags", "+faststart", str(reel_path)], check=True)
    silent.unlink()
# The loop: from a little before the first voice (or the first action) for about ten seconds, or where `reel` says.
anchor = min([v["t"] for v in voices] or [acts[0]["t"] if acts else src_from])
loop_from = reel.get("loopFrom", max(0.0, out_time(anchor) - 3.5))
loop_length = min(reel.get("loopLength", 10.0), VIDEO_END - loop_from)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{loop_from:.2f}", "-t", f"{loop_length:.2f}", "-i", str(reel_path),
                "-vf", "fps=15,scale=720:-1:flags=lanczos", "-c:v", "libwebp_anim", "-quality", "60", "-loop", "0",
                str(outdir / "loop.webp")], check=True)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{loop_from + loop_length / 2:.2f}", "-i", str(reel_path),
                "-frames:v", "1", "-vf", "scale=1280:-1:flags=lanczos", str(outdir / "poster.png")], check=True)
print(f"{reel_path} ({TOTAL:.1f} s)")
if TOTAL > 30: print(f"That's over the 30 seconds a reel may last: cut more of it (\"mark\": \"cut\").", file=sys.stderr)
