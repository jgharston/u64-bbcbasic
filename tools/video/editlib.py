"""Shared edit functions for the U64 BBC BASIC videos 2-5 (video 1 has its
own v1_edit.py, from which this is taken).

1920x1080, 50 fps, H.264. U64 pictures: stream rows 8-263 at 4x
(1536x1024), nearest neighbour, in the palette of the moment: from the
take's logged palette events (frames.palette_segments) or a segment list
given by the edit (for the showcase, which chains by itself), including
the showcase's colour cycles (frames.palette_at). Captions in a strip
below. Each scene stretches to its voice line (Piper "Alba"), the voice
0.3 s in. The capture's own sound (SID, Ultimate Audio) can play under a
segment at 1x; it is turned down while the voice speaks.
Adapted from the UBoot64 v4 edit (~/.claude/tools/youtube-video/
example-uboot64/edit2.py, video workflow of 2026-10-03).
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
from frames import palette_at, palette_segments, repaired  # noqa: E402
from written import written  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
V = os.path.join(ROOT, 'build', 'video')
TAKES = os.path.join(V, 'takes')
W, H, FPS = 1920, 1080, 50
PH = 1024
RATE = 48000
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FONTB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
LOGO = '/home/xahmol/git/idreamtin8bits-astro/src/assets/idi8b-logo-lowercase_large.png'
LEAD, TAIL = 0.3, 0.7
WHITE, GREY, DIM = (255, 255, 255), (200, 200, 200), (150, 150, 150)
VOICE_CREDIT = 'Voice: Piper text-to-speech, voice "Alba" (CC BY 4.0)'


def font(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


def speed_text(caption, speed):
    """{speed} in a caption: ' (2.5x speed)', nothing at 1x."""
    return caption.replace('{speed}', '' if speed < 1.05 else
                           ' (%sx speed)' % ('%.1f' % speed).rstrip('0').rstrip('.'))


class Take:
    """A recorded take: repaired frames by time, palettes by time."""

    def __init__(self, name, segments=None):
        d = os.path.join(TAKES, name)
        self.name = name
        self.video = os.path.join(d, 'video.pkts')
        self.events = json.load(open(os.path.join(d, 'events.json')))
        self.segs = segments or palette_segments(self.events, self.video)
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
        return np.array(palette_at(name, t), np.uint8)

    def scene(self, name, n=0):
        return [e['t'] for e in self.events if e.get('kind') == 'scene' and e.get('name') == name][n]

    def event(self, kind, n=0):
        return [e['t'] for e in self.events if e.get('kind') == kind or e.get('text') == kind][n]

    def audio(self, s0, s1):
        """Stereo float32 at 48000 Hz (the stream's 47983 Hz, close
        enough), receive time s0 to s1: 770-byte packets, u16 sequence
        then 192 stereo s16le frames."""
        out = []
        with open(os.path.join(TAKES, self.name, 'audio.pkts'), 'rb') as f:
            while True:
                h = f.read(10)
                if len(h) < 10:
                    break
                t, n = struct.unpack('<dH', h)
                d = f.read(n)
                if s0 <= t < s1 and len(d) == 770:
                    out.append(np.frombuffer(d[2:], '<i2').reshape(-1, 2))
        if not out:
            return np.zeros((0, 2), np.float32)
        return np.concatenate(out).astype(np.float32) / 32768


class Video:
    def __init__(self, out, voice_dir, narration):
        self.out = out
        self.voice_dir = voice_dir
        self.narration = json.load(open(narration))
        self.t = 0.0
        self.voice_at = []
        self.sound_at = []          # (time, samples, gain)
        self.chapters = []
        self.takes = {}
        self._cap = {}
        self.ff = subprocess.Popen(
            ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
             '-s', '%dx%d' % (W, H), '-r', str(FPS), '-i', '-',
             '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p',
             '-movflags', '+faststart', out + '.silent.mp4'], stdin=subprocess.PIPE)

    # --- basics -------------------------------------------------------
    def take(self, name, segments=None):
        if name not in self.takes:
            self.takes[name] = Take(name, segments)
        return self.takes[name]

    def emit(self, img, seconds=None):
        n = int(round((seconds or 1 / FPS) * FPS))
        b = np.ascontiguousarray(img).tobytes()
        for _ in range(n):
            self.ff.stdin.write(b)
        self.t += n / FPS

    def chapter(self, name):
        self.chapters.append((self.t, name))

    def clip_len(self, key):
        if not key:
            return 0.0
        w = wave.open(os.path.join(self.voice_dir, key + '.wav'))
        return w.getnframes() / w.getframerate()

    def voice(self, key):
        """The voice line of the scene starting now; the time it needs."""
        if not key:
            return 0.0
        self.voice_at.append((self.t + LEAD, key))
        return self.clip_len(key) + LEAD + TAIL

    def strip(self, text, height=H - PH, size=30):
        if (text, height) not in self._cap:
            im = Image.new('RGB', (W, height), (0, 0, 0))
            d = ImageDraw.Draw(im)
            f = font(size)
            w = d.textlength(text or '', font=f)
            d.text(((W - w) / 2, (height - size) / 2 - 3), text or '', font=f, fill=(235, 235, 235))
            self._cap[(text, height)] = np.asarray(im)
        return self._cap[(text, height)]

    # --- cards ----------------------------------------------------------
    def card(self, lines, key=None, seconds=5.0, logo_height=0, chapter=None):
        if chapter:
            self.chapter(chapter)
        need = self.voice(key)
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
        self.emit(np.asarray(im), max(seconds, need))

    def title(self, title, subtitle, key):
        self.card([(title, 90, True, WHITE), (subtitle, 40, False, GREY),
                   ('U64 BBC BASIC 1.0: BBC BASIC 3.10 for the Ultimate 64 and C64 Ultimate', 30, False, DIM),
                   ('Recorded on an Ultimate 64 Elite, from its video and audio streams', 26, False, DIM)],
                  key, 6.0, logo_height=280, chapter='Intro')

    def closing(self, lines, key='credits'):
        self.card([('U64 BBC BASIC 1.0.0', 72, True, WHITE),
                   ('Free and open source: github.com/xahmol/u64-bbcbasic', 36, True, WHITE)]
                  + [(l, 30, False, GREY) for l in lines]
                  + [(VOICE_CREDIT, 26, False, DIM)], key, 8.0, logo_height=240, chapter='Credits')

    # --- U64 takes --------------------------------------------------------
    def u64(self, name, s0, s1, speed, caption, key=None, chapter=None, palette=None,
            sound=False, gain=1.0):
        """Take frames s0-s1 at speed (a minimum: slows down to 1x to fit
        the voice line, holds the last frame beyond that). sound: the
        capture's audio under it (at 1x only)."""
        if chapter:
            self.chapter(chapter)
        tk = self.take(name)
        need = self.voice(key)
        if need > (s1 - s0) / speed:
            speed = max(1.0, (s1 - s0) / need)
        if sound and speed < 1.05:
            self.sound_at.append((self.t, tk.audio(s0, s1), gain))
        canvas = np.zeros((H, W, 3), np.uint8)
        canvas[PH:] = self.strip(speed_text(caption, speed))
        t0 = self.t
        n = int(round((s1 - s0) / speed * FPS))
        for k in range(n):
            t = s0 + k * speed / FPS
            f = tk.at(t)
            canvas[:PH, 192:192 + 1536] = tk.palette(t, palette)[f[8:264]].repeat(4, axis=0).repeat(4, axis=1)
            self.emit(canvas)
        if self.t - t0 < need:
            self.emit(canvas, need - (self.t - t0))
        print('%-9s %6.1f-%6.1f x%.2f -> %.1f' % (name, s0, s1, speed, self.t), flush=True)

    # --- the end ----------------------------------------------------------
    def finish(self):
        self.ff.stdin.close()
        self.ff.wait()
        n = int((self.t + 1) * RATE)
        voice = np.zeros(n, np.float32)
        for t, key in self.voice_at:
            w = wave.open(os.path.join(self.voice_dir, key + '.wav'))
            a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
            a = np.interp(np.arange(int(len(a) * RATE / w.getframerate())) * w.getframerate() / RATE,
                          np.arange(len(a)), a)
            i = int(t * RATE)
            m = min(len(a), n - i)
            voice[i:i + m] += a[:m]
        # the capture's sound, turned down to 0.3 while the voice speaks
        talking = np.zeros(n, np.float32)
        for t, key in self.voice_at:
            i, m = int((t - 0.2) * RATE), int((self.clip_len(key) + 0.5) * RATE)
            talking[max(0, i):i + m] = 1
        k = int(0.3 * RATE)
        talking = np.convolve(talking, np.ones(k) / k, mode='same')
        # each segment: the stream's DC offset removed (its silence is a
        # constant ~0.03), then brought to -20 dB RMS (peaks at most 0.9):
        # Ultimate Audio comes out ~12 dB quieter than the SIDs
        sound = np.zeros((n, 2), np.float32)
        for t, a, gain in self.sound_at:
            if not len(a):
                continue
            a = a - a.mean(axis=0)
            rms = np.sqrt((a ** 2).mean()) + 1e-9
            a = a * min(0.1 / rms, 0.9 / (np.abs(a).max() + 1e-9)) * gain
            fade = np.minimum(1, np.minimum(np.arange(len(a)), np.arange(len(a))[::-1]) / (RATE * 0.15))
            i = int(t * RATE)
            m = min(len(a), n - i)
            sound[i:i + m] += a[:m] * fade[:m, None]
        sound *= (1 - 0.7 * talking)[:, None]
        track = np.clip(voice[:, None] + sound, -1, 1)
        wav = self.out + '.audio.wav'
        w = wave.open(wav, 'wb')
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((track * 32767).astype('<i2').tobytes())
        w.close()
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', self.out + '.silent.mp4', '-i', wav,
                        '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
                        '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-ar', '48000',
                        '-shortest', '-movflags', '+faststart', self.out], check=True)
        os.remove(self.out + '.silent.mp4')
        os.remove(wav)
        with open(self.out + '.chapters.txt', 'w') as f:
            for t, name in self.chapters:
                f.write('%d:%02d %s\n' % (int(t) // 60, int(t) % 60, name))
        with open(self.out + '.transcript.txt', 'w') as f:
            for t, key in sorted(self.voice_at):
                f.write(written(self.narration[key]) + '\n')
        print('written', self.out, round(self.t, 1), 's')


# The showcase take (show_record.py): its parts chain by themselves, so the
# palettes are set from the part boundaries (cleared frames, and the frame
# where SHOW1's and SHOW7's drawings end and their colour cycles start;
# a cycle step measured at 0.481 / 0.498 s on the U64)
SHOW_SEGMENTS = [
    (0.0, 'c64'),                       # the title (MODE 100, PETSCII)
    (29.43, 'bbc_mode2'),               # SHOW1 tunnel
    (35.63, 'cycle:6:0.481:35.63'),
    (51.18, 'bbc_mode2'),               # SHOW2 Bubble Universe
    (75.55, 'bbc_mode2'),               # SHOW3 the race
    (97.34, 'c64'),                     # SHOW4 sprites
    (112.68, 'bbc_mode1'),              # SHOW5 the cube
    (128.48, 'teletext'),               # SHOW6 Ultimate Audio
    (136.04, 'bbc_mode2'),              # SHOW7 plasma
    (147.95, 'cycle:5:0.498:147.95'),
    (178.68, 'bbc_mode1'),              # SHOW8 spirographs
    (210.52, 'c64'),                    # SHOW9: the console text
    (220.09, 'show9'),                  # the sunset shown
    (226.08, 'teletext'),               # SHOW10 credits
]
