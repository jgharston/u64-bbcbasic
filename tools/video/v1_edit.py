"""Video 1 (introduction): the edit (docs/VIDEO_PLAN.md).

  python3 tools/video/v1_edit.py build/video/v1.mp4

1920x1080, 50 fps, H.264, from:
  build/video/takes/v1, v1teaser, v1upic, v1bubble  (v1_record.py, v1_teaser.py)
  build/video/takes/v1vsc                            (v1_vscode.py)
  build/video/{photos,screens,magazine,manual,clips} (the story's stills)
  build/video/v1voice/*.wav                          (Piper "Alba", v1_narration.json)
U64 pictures: stream rows 8-263 at 4x (1536x1024), nearest neighbour, the
palette per take segment (frames.palette_segments, or the scene's own);
captions in a strip below. Each scene stretches to its voice line, the
voice 0.3 s in. Adapted from the UBoot64 v4 edit (~/.claude/tools/
youtube-video/example-uboot64/edit2.py, video workflow of 2026-10-03).
Writes OUT, OUT.chapters.txt and the transcript OUT.transcript.txt.
"""
import json
import os
import struct
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from frames import PALETTES, palette_segments, repaired  # noqa: E402
from written import written  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
V = os.path.join(ROOT, 'build', 'video')
TAKES = os.path.join(V, 'takes')
VOICE = os.path.join(V, 'v1voice')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(V, 'v1.mp4')
W, H, FPS = 1920, 1080, 50
PH = 1024                       # picture height; the caption strip below
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FONTB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
LOGO = '/home/xahmol/git/idreamtin8bits-astro/src/assets/idi8b-logo-lowercase_large.png'
LEAD, TAIL = 0.3, 0.7
NARRATION = json.load(open(os.path.join(HERE, 'v1_narration.json')))

out_time = [0.0]
voice_at = []                   # (time, key)
music_at = []                   # (time, samples float32 stereo)
chapters = []


# --- helpers -------------------------------------------------------------

def font(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


def clip_len(key):
    if not key:
        return 0.0
    w = wave.open(os.path.join(VOICE, key + '.wav'))
    return w.getnframes() / w.getframerate()


def voice(key):
    """The voice line of the scene starting now; the time it needs."""
    if not key:
        return 0.0
    voice_at.append((out_time[0] + LEAD, key))
    return clip_len(key) + LEAD + TAIL


_cap = {}


def speed_text(caption, speed):
    """{speed} in a caption: ', 2.5x speed' (nothing at 1x)."""
    return caption.replace('{speed}', '' if speed < 1.05 else ' (%sx speed)' % ('%.1f' % speed).rstrip('0').rstrip('.'))


def strip(text, height=H - PH, size=30):
    if (text, height) not in _cap:
        im = Image.new('RGB', (W, height), (0, 0, 0))
        d = ImageDraw.Draw(im)
        f = font(size)
        w = d.textlength(text or '', font=f)
        d.text(((W - w) / 2, (height - size) / 2 - 3), text or '', font=f, fill=(235, 235, 235))
        _cap[(text, height)] = np.asarray(im)
    return _cap[(text, height)]


def card(lines, logo_height=0):
    im = Image.new('RGB', (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)
    total = sum(s * 1.6 for _, s, _, _ in lines)
    gap = 70 if logo_height else 0
    y = (H - total - logo_height - gap) / 2
    if logo_height:
        lg = Image.open(LOGO).convert('RGBA')
        lg = lg.resize((round(lg.width * logo_height / lg.height), logo_height), Image.LANCZOS)
        im.paste(lg, ((W - lg.width) // 2, int(y)), lg)
        y += logo_height + gap
    for text, size, bold, col in lines:
        f = font(size, bold)
        w = d.textlength(text, font=f)
        d.text(((W - w) / 2, y), text, font=f, fill=col)
        y += size * 1.6
    return np.asarray(im)


ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
                       '-s', '%dx%d' % (W, H), '-r', str(FPS), '-i', '-',
                       '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p',
                       '-movflags', '+faststart', OUT + '.silent.mp4'], stdin=subprocess.PIPE)


def emit(img, seconds=None):
    n = int(round((seconds or 1 / FPS) * FPS))
    b = np.ascontiguousarray(img).tobytes()
    for _ in range(n):
        ff.stdin.write(b)
    out_time[0] += n / FPS


def chapter(name):
    chapters.append((out_time[0], name))


# --- stills --------------------------------------------------------------

def fit(path, zoom_room=1.0):
    """The image fitted into the picture area: pixel screens (small) at an
    integer scale, nearest neighbour; photos and scans smoothly."""
    im = Image.open(path).convert('RGB')
    if os.path.basename(path).startswith('c128-'):
        # VDC 80 columns: 640 x 200 pixels fill a 4:3 screen, so the
        # lines are 2.4 times as high as the pixels are wide (5 across,
        # 12 down, nearest neighbour; then scaled down smoothly)
        im = im.resize((im.width * 5, im.height * 12), Image.NEAREST)
    s = min(W / im.width, PH / im.height)
    if im.width <= 900 and int(s) >= 2:
        s = int(s)
        return im.resize((im.width * s, im.height * s), Image.NEAREST), False
    s *= zoom_room
    return im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS), True


def still(path, seconds, caption, zoom=0.06):
    im, smooth = fit(path, 1 + zoom)
    cap = strip(caption)
    canvas = np.zeros((H, W, 3), np.uint8)
    canvas[PH:] = cap
    n = int(round(seconds * FPS))
    if not smooth or not zoom:
        x, y = (W - im.width) // 2, (PH - im.height) // 2
        canvas[max(0, y):max(0, y) + min(PH, im.height), max(0, x):max(0, x) + min(W, im.width)] = \
            np.asarray(im)[max(0, -y):max(0, -y) + min(PH, im.height), max(0, -x):max(0, -x) + min(W, im.width)]
        emit(canvas, seconds)
        return
    # slow zoom in: from the whole image (scaled down) to 1+zoom
    base = im
    for k in range(n):
        z = 1 / (1 + zoom) * (1 + zoom * k / max(1, n - 1))
        w, h = round(base.width * z), round(base.height * z)
        fr = base.resize((w, h), Image.BILINEAR) if k % 2 == 0 or k == 0 else fr
        canvas[:PH] = 0
        x, y = (W - fr.width) // 2, (PH - fr.height) // 2
        a = np.asarray(fr)
        sx, sy = max(0, -x), max(0, -y)
        cw, ch = min(W, fr.width), min(PH, fr.height)
        canvas[max(0, y):max(0, y) + ch, max(0, x):max(0, x) + cw] = a[sy:sy + ch, sx:sx + cw]
        emit(canvas)


def stills(group, key, chapter_name=None):
    """A group of (path, seconds, caption, zoom) under one voice line: the
    times stretch together to fit it."""
    if chapter_name:
        chapter(chapter_name)
    need = voice(key)
    total = sum(g[1] for g in group)
    k = max(1.0, need / total)
    for path, secs, cap, zoom in group:
        still(os.path.join(V, path), secs * k, cap, zoom)


# --- video clips (ffmpeg) -----------------------------------------------

def ffmpeg_frames(path, start, dur, speed, size, crop=None):
    vf = []
    if crop:
        vf.append('crop=%d:%d:%d:%d' % crop)
    vf += ['setpts=PTS/%f' % speed, 'fps=%d' % FPS, 'scale=%d:%d:flags=lanczos' % size]
    p = subprocess.Popen(['ffmpeg', '-loglevel', 'error', '-ss', str(start), '-t', str(dur), '-i', path,
                          '-vf', ','.join(vf), '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                         stdout=subprocess.PIPE)
    n = size[0] * size[1] * 3
    while True:
        b = p.stdout.read(n)
        if len(b) < n:
            break
        yield np.frombuffer(b, np.uint8).reshape(size[1], size[0], 3)
    p.wait()


def clip(path, start, dur, speed, caption, key=None):
    need = voice(key)
    probe = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v', '-show_entries',
                            'stream=width,height', '-of', 'csv=p=0', path], capture_output=True, text=True)
    w, h = map(int, probe.stdout.strip().split(','))
    s = min(W / w, PH / h)
    size = (round(w * s) // 2 * 2, round(h * s) // 2 * 2)
    canvas = np.zeros((H, W, 3), np.uint8)
    canvas[PH:] = strip(caption)
    x, y = (W - size[0]) // 2, (PH - size[1]) // 2
    t0 = out_time[0]
    for fr in ffmpeg_frames(path, start, dur, speed, size):
        canvas[y:y + size[1], x:x + size[0]] = fr
        emit(canvas)
    if out_time[0] - t0 < need:
        emit(canvas, need - (out_time[0] - t0))


# --- U64 takes -------------------------------------------------------------

class Take:
    def __init__(self, name, extra=None):
        d = os.path.join(TAKES, name)
        self.video = os.path.join(d, 'video.pkts')
        self.events = json.load(open(os.path.join(d, 'events.json')))
        self.segs = palette_segments(self.events + (extra or []), self.video)
        self.reset()

    def reset(self):
        self.it = repaired(self.video)
        self.cur = next(self.it)
        self.nxt = next(self.it)

    def at(self, t):
        if self.cur[0] > t + 0.5:
            self.reset()
        while self.nxt[0] <= t:
            self.cur = self.nxt
            try:
                self.nxt = next(self.it)
            except StopIteration:
                break
        return self.cur[1]

    def palette(self, t, force=None):
        name = force or [n for s, n in self.segs if s <= t][-1]
        return np.array(PALETTES[name], np.uint8)

    def scene(self, name, n=0):
        return [e['t'] for e in self.events if e.get('kind') == 'scene' and e.get('name') == name][n]


TK = {}


def take(name, extra=None):
    if name not in TK:
        TK[name] = Take(name, extra)
    return TK[name]


def u64(name, s0, s1, speed, caption, key=None, chapter_name=None, palette=None):
    """Take frames s0-s1 at speed (a minimum: slows down to 1x to fit the
    voice line, holds the last frame beyond that)."""
    if chapter_name:
        chapter(chapter_name)
    tk = take(name)
    need = voice(key)
    if need > (s1 - s0) / speed:
        speed = max(1.0, (s1 - s0) / need)
    canvas = np.zeros((H, W, 3), np.uint8)
    canvas[PH:] = strip(speed_text(caption, speed))
    t0 = out_time[0]
    n = int(round((s1 - s0) / speed * FPS))
    for k in range(n):
        t = s0 + k * speed / FPS
        f = tk.at(t)
        canvas[:PH, 192:192 + 1536] = tk.palette(t, palette)[f[8:264]].repeat(4, axis=0).repeat(4, axis=1)
        emit(canvas)
    if out_time[0] - t0 < need:
        emit(canvas, need - (out_time[0] - t0))
    print('%-8s %6.1f-%6.1f x%.2f -> %.1f' % (name, s0, s1, speed, out_time[0]), flush=True)


# --- U64 audio stream --------------------------------------------------------

def stream_audio(name, s0, s1):
    """Stereo float32 at 48000 Hz (the stream's 47983 Hz, close enough)
    from receive time s0 to s1: 770-byte packets, u16 sequence then 192
    stereo s16le frames."""
    out = []
    with open(os.path.join(TAKES, name, 'audio.pkts'), 'rb') as f:
        while True:
            h = f.read(10)
            if len(h) < 10:
                break
            t, n = struct.unpack('<dH', h)
            d = f.read(n)
            if s0 <= t < s1 and len(d) == 770:
                out.append(np.frombuffer(d[2:], '<i2').reshape(-1, 2))
    return np.concatenate(out).astype(np.float32) / 32768


# --- the VS Code take ----------------------------------------------------

def vscode(s0, s1, speed, caption, key=None, inset=None, chapter_name=None):
    """The VS Code window (1928x1084 grab, title bar cropped: 1920x1050),
    caption strip of 30 px below. inset: (take, offset) shows the U64
    picture at 2x in the bottom right (U64 time = mkv time + offset)."""
    if chapter_name:
        chapter(chapter_name)
    need = voice(key)
    if need > (s1 - s0) / speed:
        speed = max(1.0, (s1 - s0) / need)
    canvas = np.zeros((H, W, 3), np.uint8)
    canvas[1050:] = strip(speed_text(caption, speed), 30, 22)
    t0 = out_time[0]
    k = 0
    for fr in ffmpeg_frames(os.path.join(TAKES, 'v1vsc', 'vscode.mkv'), s0, s1 - s0, speed, (1920, 1050),
                            crop=(1920, 1050, 4, 34)):
        canvas[:1050] = fr
        if inset:
            tk, off = inset
            t = s0 + k * speed / FPS + off
            f = tk.at(t)
            pic = tk.palette(t)[f[8:264]].repeat(2, axis=0).repeat(2, axis=1)
            y, x = 1050 - 512 - 60, 1920 - 768 - 40
            canvas[y - 4:y + 516, x - 4:x + 772] = (90, 90, 90)
            canvas[y:y + 512, x:x + 768] = pic
        emit(canvas)
        k += 1
    if out_time[0] - t0 < need:
        emit(canvas, need - (out_time[0] - t0))
    print('vscode   %6.1f-%6.1f x%.2f -> %.1f' % (s0, s1, speed, out_time[0]), flush=True)


# --- the video -----------------------------------------------------------

WHITE, GREY, DIM = (255, 255, 255), (200, 200, 200), (150, 150, 150)

chapter('Intro')
need = voice('title')
emit(card([('U64 BBC BASIC', 96, True, WHITE),
           ('BBC BASIC 3.10 for the Ultimate 64 and C64 Ultimate', 40, False, GREY),
           ('Recorded on an Ultimate 64 Elite, from its video and audio streams', 30, False, DIM)],
          logo_height=300), max(6.0, need))

stills([('photos/01-kid-ti99-spectrum.jpg', 5.0, 'Xander as a kid: a TI-99/4A, a ZX Spectrum beside it', 0.08),
        ('screens/ti99-basic-list.png', 2.0, 'TI BASIC (Classic99)', 0.0),
        ('screens/ti99-basic-run.png', 2.0, 'TI BASIC (Classic99)', 0.0)], 'kid', 'Where it started')
stills([('manual/zx-manual-cover.png', 1.5, 'ZX Spectrum BASIC programming, Steven Vickers, Sinclair Research 1983', 0.04),
        ('manual/zx-manual-lesson.png', 1.5, 'ZX Spectrum BASIC programming, chapter 2', 0.06)], 'zx_manual')
stills([('magazine/su33-cover.png', 2.0, 'Sinclair User 33, December 1984 (scan: World of Spectrum archive)', 0.04),
        ('magazine/su33-p126-127.png', 1.6, 'On the Road, by Ges and Hilary Taylor: six pages of type-in', 0.10),
        ('magazine/su33-p128-129.png', 1.6, 'On the Road, by Ges and Hilary Taylor: six pages of type-in', 0.10),
        ('magazine/su33-p130-131.png', 1.6, 'On the Road, by Ges and Hilary Taylor: six pages of type-in', 0.10),
        ('screens/zx-ontheroad-list.png', 2.0, 'On the Road on the ZX Spectrum (Fuse)', 0.0),
        ('screens/zx-ontheroad-game.png', 2.0, 'On the Road on the ZX Spectrum (Fuse)', 0.0)], 'zx_mag')
stills([('manual/oric-manual-cover.png', 1.5, 'The ORIC ATMOS Manual, Ian Adamson, Pan Books 1984 (scan: defence-force.org)', 0.04),
        ('manual/oric-manual-lesson.png', 2.0, 'The ORIC ATMOS Manual: PRINT "MESSAGE"', 0.08),
        ('screens/oric-ludo-list.png', 2.0, 'His Ludo in Oric Atmos BASIC (Phosphoric)', 0.0),
        ('screens/oric-ludo-title.png', 2.0, 'His Ludo in Oric Atmos BASIC (Phosphoric)', 0.0)], 'oric')
stills([('screens/c64-v2-list.png', 2.0, 'Commodore 64 BASIC V2: POKE and PEEK (VICE)', 0.0),
        ('screens/c64-v2-run.png', 2.0, 'Commodore 64 BASIC V2 (VICE)', 0.0)], 'c64')
stills([('screens/c128-mejn-title.png', 2.0, 'Mens Erger Je Niet, C128 BASIC 7.0, 1992 (VICE, original disk)', 0.0),
        ('screens/c128-carriere-title.png', 2.0, 'Carriere, C128 BASIC 7.0, 1992 (VICE, original disk)', 0.0),
        ('screens/c128-mejn-list-crop.png', 2.5, 'BASIC 7.0: DO ... LOOP, and GOSUB 15520', 0.0)], 'c128')
stills([('screens/bbc-list.png', 2.5, 'BBC BASIC on a BBC Micro: PROC, LOCAL, REPEAT (B-em)', 0.0),
        ('screens/bbc-run.png', 2.5, 'BBC BASIC on a BBC Micro (B-em)', 0.0)], 'bbc')
stills([('photos/crop-archimedes.png', 3.0, 'His Acorn Archimedes A305 today', 0.06),
        ('screens/archbas-bubble.png', 2.5, 'ArchBAS on the Archimedes: Bubble Universe (Eric Schraf), real hardware', 0.04)], 'arch')
clip(os.path.join(V, 'clips', 'archimedes-bubble-30x.mp4'), 0, 4.9, 1.0,
     'Acorn Archimedes, real hardware, 30x speed')
u64('v1bubble', take('v1bubble').scene('bubble') + 0.3, 205.0, 30.0,
    'The same program in U64 BBC BASIC: MODE 2{speed}', 'bubble')

T1 = take('v1')
u64('v1', 7.4, 13.1, 1.0, 'U64 BBC BASIC 1.0.0 starts: BASIC 3.10, unchanged', 'startup', 'U64 BBC BASIC')
u64('v1', T1.scene('type_rings'), 53.3, 4.0, 'A structured program, typed on the keyboard{speed}', 'type', 'Programs')
u64('v1', 70.3, 79.5, 1.0, 'RUN: MODE 1, in the BBC colours', 'rings')
emit(np.zeros((H, W, 3), np.uint8), 0.04)
u64('v1', T1.scene('speed'), 92.0, 2.0, 'A million empty FOR loops, timed{speed}', 'speed', 'Speed')
still(os.path.join(V, 'screens', 'bbc-speed.png'), 3.0, 'A BBC Micro: 178 cs for ten thousand loops, about 3 minutes for a million (B-em)', 0)
u64('v1', 96.0, 99.0, 1.0, 'U64 BBC BASIC: 5.44 s for a million: about 33x a BBC Micro')
u64('v1', T1.scene('editor'), T1.scene('help'), 1.5, 'The line editor: history (cursor up), copy editing (CTRL+cursor, F1){speed}',
    'editor', 'Line editor and help')
u64('v1', T1.scene('help'), 140.0, 1.0, '*HELP: every keyword and command', 'help')

# VS Code: times in the window recording from the scene's own event log
VE = json.load(open(os.path.join(TAKES, 'v1vsc', 'vscode_events.json')))
TE = json.load(open(os.path.join(TAKES, 'v1vsc', 'events.json')))
GRAB = [e['epoch'] for e in TE if e['kind'] == 'vscode_grab'][0]
EPOCH0 = [e['epoch'] for e in TE if e['kind'] == 'epoch0'][0]
def vt(name, n=0):
    return [e['epoch'] for e in VE if e.get('name', e['kind']) == name][n] - GRAB
VSC_U64 = take('v1vsc', [{'kind': 'scene', 't': vt('vsc_run') + GRAB - EPOCH0, 'palette': 'bbc_mode1'}])
vscode(vt('vsc_type'), vt('vsc_format'), 3.0, 'VS Code: the rings program typed{speed}', key='vscode', chapter_name='VS Code')
vscode(vt('vsc_format'), vt('vsc_hover'), 1.0, 'Format Document: indentation by the extension')
vscode(vt('vsc_hover'), vt('vsc_run'), 1.0, 'Hover help from *HELP')
vscode(vt('vsc_run'), vt('vsc_key'), 1.0, 'Ctrl+F5: run on the U64 (its screen in the corner)',
       inset=(VSC_U64, GRAB - EPOCH0))
vscode(vt('vsc_debug'), vt('continue') + 3.0, 1.5, 'The debugger: a breakpoint, variables, stepping{speed}')

# teaser montage under Ode to Joy (all 24 voices from 32 s into the piece)
chapter('The Ultimate')
TT = take('v1teaser')
playing = [e['t'] for e in TT.events if e.get('text') == 'Playing'][0]
need = voice('teaser')
shots = [('v1teaser', playing + 36.0, '24 voices on 8 SIDs: the music demo', None),
         ('v1upic', take('v1upic').scene('upic') + 9.0, 'Upic full: 384 x 256, 16 colours of its own', None),
         ('v1teaser', TT.scene('invaders') + 17.0, 'Invaders: multiplexed sprites', None),
         ('v1teaser', TT.scene('ttx') + 19.5, 'U64TEXT: teletext pages from the internet', None),
         ('v1teaser', TT.scene('ttx') + 32.0, 'U64TEXT: teletext pages from the internet', None),
         ('v1teaser', TT.scene('browse') + 5.0, '*BROWSE: the file browser', None)]
each = max(2.5, need / len(shots))
music_at.append((out_time[0], stream_audio('v1teaser', playing + 33.0, playing + 33.0 + each * len(shots) + 1)))
for name, s, cap, pal in shots:
    u64(name, s, s + each, 1.0, cap, palette=pal)

chapter('Credits')
need = voice('credits')
emit(card([('U64 BBC BASIC 1.0.0', 72, True, WHITE),
           ('Free and open source: github.com/xahmol/u64-bbcbasic', 36, True, WHITE),
           ('BBC BASIC 3.10: Sophie Wilson and Acorn Computers', 30, False, GREY),
           ('The annotated source: Ivo van Poorten.  Acorn documentation: J.G. Harston', 30, False, GREY),
           ('Code: Xander Mol.  Schraf programs: Eric Schraf (via ArchBAS)', 30, False, GREY),
           ('Voice: Piper text-to-speech, voice "Alba" (CC BY 4.0)', 26, False, DIM)],
          logo_height=240), max(8.0, need + 1.0))
ff.stdin.close()
ff.wait()

# --- audio: the voice lines and the music, then loudness ------------------
RATE = 48000
track = np.zeros((int((out_time[0] + 1) * RATE), 2), np.float32)
for t, key in voice_at:
    w = wave.open(os.path.join(VOICE, key + '.wav'))
    a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
    a = np.interp(np.arange(int(len(a) * RATE / w.getframerate())) * w.getframerate() / RATE,
                  np.arange(len(a)), a)
    i = int(t * RATE)
    n = min(len(a), len(track) - i)
    track[i:i + n] += a[:n, None]
for t, a in music_at:
    a = a / max(1e-6, np.abs(a).max()) * 0.3
    fade = np.minimum(1, np.minimum(np.arange(len(a)), np.arange(len(a))[::-1]) / (RATE * 0.8))
    a = a * fade[:, None]
    i = int(t * RATE)
    n = min(len(a), len(track) - i)
    track[i:i + n] += a[:n]
track = np.clip(track, -1, 1)
wav = OUT + '.audio.wav'
w = wave.open(wav, 'wb')
w.setnchannels(2)
w.setsampwidth(2)
w.setframerate(RATE)
w.writeframes((track * 32767).astype('<i2').tobytes())
w.close()
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', OUT + '.silent.mp4', '-i', wav,
                '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
                '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-ar', '48000',
                '-shortest', '-movflags', '+faststart', OUT], check=True)
os.remove(OUT + '.silent.mp4')
os.remove(wav)
with open(OUT + '.chapters.txt', 'w') as f:
    for t, name in chapters:
        f.write('%d:%02d %s\n' % (int(t) // 60, int(t) % 60, name))
with open(OUT + '.transcript.txt', 'w') as f:
    for t, key in sorted(voice_at):
        f.write(written(NARRATION[key]) + '\n')
print('written', OUT, round(out_time[0], 1), 's')
