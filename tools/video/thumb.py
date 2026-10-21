"""YouTube thumbnails (1280x720 JPG) from captured frames.

  python3 tools/video/thumb.py v1 OUTDIR

Per video two variants (the workflow: a real captured frame, the title
large and bold with a black outline on a dark part of the picture, the
idi8b logo on a dark plate in a corner). Frames come from the takes, in
their own palettes.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from frames import PALETTES, frames, to_image  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
TAKES = os.path.join(ROOT, 'build', 'video', 'takes')
FONTB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
LOGO = '/home/xahmol/git/idreamtin8bits-astro/src/assets/idi8b-logo-lowercase_large.png'
TW, TH = 1280, 720


def frame(take, t, palette):
    for ft, n, pix in frames(os.path.join(TAKES, take, 'video.pkts')):
        if ft >= t:
            return to_image(pix, PALETTES[palette]).crop((0, 8, 384, 264))
    raise ValueError('no frame at %s' % t)


def text(d, xy, s, size, fill=(255, 255, 255), anchor='la'):
    d.text(xy, s, font=ImageFont.truetype(FONTB, size), fill=fill, anchor=anchor,
           stroke_width=max(3, size // 14), stroke_fill=(0, 0, 0))


def logo(im, corner='tr', height=70):
    lg = Image.open(LOGO).convert('RGBA')
    lg = lg.resize((round(lg.width * height / lg.height), height), Image.LANCZOS)
    pad = 14
    w, h = lg.width + 2 * pad, lg.height + 2 * pad
    x = TW - w - 20 if 'r' in corner else 20
    y = 20 if 't' in corner else TH - h - 20
    plate = Image.new('RGBA', (w, h), (0, 0, 0, 200))
    im.paste(plate, (x, y), plate)
    im.paste(lg, (x + pad, y + pad), lg)


def v1(out):
    # A: the rings (BBC MODE 1 colours) on the right, the title in the black
    rings = frame('v1', 78.0, 'bbc_mode1')
    im = Image.new('RGB', (TW, TH), (0, 0, 0))
    pic = rings.resize((round(384 * 720 / 256), 720), Image.NEAREST)
    im.paste(pic, (TW - pic.width + 340, 0))
    d = ImageDraw.Draw(im)
    text(d, (50, 210), 'BBC BASIC', 110, (255, 220, 60))
    text(d, (50, 350), 'on the C64', 100)
    text(d, (54, 490), 'Ultimate 64 / C64 Ultimate', 44, (200, 200, 200))
    logo(im, 'bl')
    im.save(os.path.join(out, 'v1-thumbnail-A.jpg'), quality=92)
    # B: the sunset (Upic full, its own colours), the title over the sea
    sun = frame('v1upic', 21.0, 'show9')
    im = sun.resize((TW, round(256 * TW / 384)), Image.NEAREST).crop((0, 70, TW, 70 + TH))
    d = ImageDraw.Draw(im)
    text(d, (TW // 2, 470), 'BBC BASIC on the C64', 100, anchor='ma')
    text(d, (TW // 2, 610), 'U64 BBC BASIC 1.0', 52, (255, 230, 120), anchor='ma')
    logo(im, 'tr')
    im.save(os.path.join(out, 'v1-thumbnail-B.jpg'), quality=92)


if __name__ == '__main__':
    os.makedirs(sys.argv[2], exist_ok=True)
    {'v1': v1}[sys.argv[1]](sys.argv[2])
