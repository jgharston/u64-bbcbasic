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
from frames import frames, palette_at, to_image  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
TAKES = os.path.join(ROOT, 'build', 'video', 'takes')
FONTB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
LOGO = '/home/xahmol/git/idreamtin8bits-astro/src/assets/idi8b-logo-lowercase_large.png'
TW, TH = 1280, 720


def frame(take, t, palette):
    for ft, n, pix in frames(os.path.join(TAKES, take, 'video.pkts')):
        if ft >= t:
            return to_image(pix, palette_at(palette, ft)).crop((0, 8, 384, 264))
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


def framed(pic, title, sub, out, corner='tr', ty=470):
    """A picture filling the thumbnail, the title over its lower part."""
    im = pic.resize((TW, round(256 * TW / 384)), Image.NEAREST).crop((0, 70, TW, 70 + TH))
    d = ImageDraw.Draw(im)
    text(d, (TW // 2, ty), title, 104, anchor='ma')
    text(d, (TW // 2, ty + 140), sub, 50, (255, 230, 120), anchor='ma')
    logo(im, corner)
    im.save(out, quality=92)


def beside(pic, l1, l2, l3, out, col=(255, 220, 60), height=720, dx=340, size2=92):
    """The picture on the right (height px high, dx px of it beyond the
    right edge), the title on the black left."""
    im = Image.new('RGB', (TW, TH), (0, 0, 0))
    p = pic.resize((round(384 * height / 256), height), Image.NEAREST)
    im.paste(p, (TW - p.width + dx, (TH - height) // 2))
    d = ImageDraw.Draw(im)
    text(d, (50, 210), l1, 110, col)
    text(d, (50, 350), l2, size2)
    text(d, (54, 490), l3, 44, (200, 200, 200))
    logo(im, 'bl')
    im.save(out, quality=92)


def v2(out):
    framed(frame('show', 152.0, 'cycle:5:0.498:147.95'), 'Graphics', 'BBC BASIC on the C64',
           os.path.join(out, 'v2-thumbnail-A.jpg'))
    beside(frame('v2', 31.0, 'bbc_mode2'), 'Graphics', 'BBC modes', 'U64 BBC BASIC on the C64',
           os.path.join(out, 'v2-thumbnail-B.jpg'))


def v3(out):
    import json
    ev = json.load(open(os.path.join(TAKES, 'v3', 'events.json')))
    t = [e['t'] for e in ev if e.get('name') == 'music_play'][0] + 45
    beside(frame('v3', t, 'c64'), 'Sound', '24 SID voices', 'and Ultimate Audio',
           os.path.join(out, 'v3-thumbnail-A.jpg'), height=380, dx=-10, size2=80)
    ta = [e['t'] for e in ev if e.get('name') == 'audio_fx'][0]
    beside(frame('v3', ta, 'teletext'), 'Music', 'MOD, samples', 'Ultimate Audio from BBC BASIC',
           os.path.join(out, 'v3-thumbnail-B.jpg'), height=380, dx=-10, size2=80)


def v4(out):
    import json
    ev = json.load(open(os.path.join(TAKES, 'v4c', 'events.json')))
    t = [e['t'] for e in ev if e.get('name') == 'u64text'][0] + 60
    framed(frame('v4c', t, 'teletext'), 'Teletext from the net', 'BBC BASIC on the C64', os.path.join(out, 'v4-thumbnail-A.jpg'),
           ty=300)
    ev = json.load(open(os.path.join(TAKES, 'v4', 'events.json')))
    tb = [e['t'] for e in ev if e.get('name') == 'browse_copy'][0] + 6
    beside(frame('v4', tb, 'c64'), 'Files and', 'the network', 'U64 BBC BASIC on the Ultimate 64',
           os.path.join(out, 'v4-thumbnail-B.jpg'))


def v5(out):
    import json
    ev = json.load(open(os.path.join(TAKES, 'v5', 'events.json')))
    t = [e['t'] for e in ev if e.get('name') == 'xmastree_end'][0] - 3
    beside(frame('v5', t, 'xmastree'), 'The demos', 'in BBC BASIC', 'on the Commodore 64 Ultimate',
           os.path.join(out, 'v5-thumbnail-A.jpg'), dx=420)
    framed(frame('show', 222.0, 'show9'), 'The demos', 'U64 BBC BASIC showcase', os.path.join(out, 'v5-thumbnail-B.jpg'))


if __name__ == '__main__':
    os.makedirs(sys.argv[2], exist_ok=True)
    {'v1': v1, 'v2': v2, 'v3': v3, 'v4': v4, 'v5': v5}[sys.argv[1]](sys.argv[2])
