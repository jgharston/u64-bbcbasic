"""Frames from a recorded VIC stream (video.pkts from rec.py).

Each UDP packet carries a 12-byte little-endian header (u16 sequence,
u16 frame, u16 line with bit 15 on the frame's last packet, u16 pixels
per line = 384, u8 lines per packet = 4, u8 bits per pixel = 4, u16
encoding) and 4 lines of 384 pixels, two per byte, the left one in the
low nybble. A PAL frame is 272 lines. Adapted from mandelbrot-upic's
frames.py (video workflow of 2026-10-03).

frames(path) yields (time, frame number, 272x384 bytearray of colour
indexes); to_image(pixels, palette) gives a PIL image.
"""
import struct

W, H, HEADER = 384, 272, 12

# C64 colours (Pepto's palette, as tools/u64shot.py), for the VIC-II
# screens; the Upic Lite and teletext scenes get their own in the edit
C64 = [(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x68, 0x37, 0x2B), (0x70, 0xA4, 0xB2),
       (0x6F, 0x3D, 0x86), (0x58, 0x8D, 0x43), (0x35, 0x28, 0x79), (0xB8, 0xC7, 0x6F),
       (0x6F, 0x4F, 0x25), (0x43, 0x39, 0x00), (0x9A, 0x67, 0x59), (0x44, 0x44, 0x44),
       (0x6C, 0x6C, 0x6C), (0x9A, 0xD2, 0x84), (0x6C, 0x5E, 0xB5), (0x95, 0x95, 0x95)]


def packets(path):
    with open(path, 'rb') as f:
        while True:
            h = f.read(10)
            if len(h) < 10:
                return
            t, n = struct.unpack('<dH', h)
            yield t, f.read(n)


def frames(path):
    cur, pix, t0 = None, None, None
    for t, d in packets(path):
        if len(d) < HEADER:
            continue
        _, frame, line, ppl, lpp, bpp, _ = struct.unpack('<HHHHBBH', d[:HEADER])
        last = line & 0x8000
        line &= 0x7FFF
        if frame != cur:
            cur, pix, t0 = frame, bytearray(W * H), t
        body = d[HEADER:]
        for i, b in enumerate(body):
            p = line * W + 2 * i
            if p + 1 < W * H:
                pix[p] = b & 15
                pix[p + 1] = b >> 4
        if last:
            yield t0, frame, pix
            cur = None


def to_image(pix, palette=C64):
    from PIL import Image
    im = Image.new('RGB', (W, H))
    im.putdata([palette[c] for c in pix])
    return im


# BBC colours for the Upic Lite modes: the VDU drivers write logical
# colour N as palette index N, and the stream carries indexes only
BBC = [(0, 0, 0), (255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255),
       (255, 0, 255), (0, 255, 255), (255, 255, 255)]
PALETTES = {
    'c64': C64,
    'bbc_mode1': [[(0, 0, 0), (255, 0, 0), (255, 255, 0), (255, 255, 255)][i & 3]
                  for i in range(16)],
    'bbc_mode2': [BBC[i & 7] for i in range(16)],
    # 2-colour modes (0, 4, 6 in Upic Lite): entry i = pal[i AND 1]
    'bbc_mode0': [[(0, 0, 0), (255, 255, 255)][i & 1] for i in range(16)],
    # MODE 7 draws teletext colour n with C64 colour tcol[n] (src/mos/ttx.s)
    # and sets those 8 to the BBC's pure RGB
    # SHOW9 (Upic full): *COLOUR 1-13 from its DATA lines, the rest C64
    'show9': [(0, 0, 0)] + [tuple(c) for c in (
        (20, 20, 80), (40, 30, 110), (70, 40, 130), (110, 50, 140), (160, 60, 130),
        (210, 80, 110), (240, 110, 80), (255, 150, 60), (255, 230, 120),
        (40, 60, 120), (30, 50, 100), (60, 80, 140), (15, 15, 30))] + C64[14:],
    # Bubble Universe (demos/archbas/BUBBLE.bas): *COLOUR 0-15 from its DATA
    'bubble': [(0, 0, 0), (255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255), (255, 0, 255),
               (0, 255, 255), (255, 255, 255), (255, 128, 0), (128, 0, 255), (0, 128, 255),
               (255, 0, 128), (128, 255, 0), (0, 255, 128), (128, 128, 128), (64, 64, 64)],
    # the Schraf programs (demos/archbas) and sine: their own *COLOUR /
    # VDU 19 over the MODE's BBC colours
    'field': [BBC[i & 7] for i in range(16)],
    'hat': [BBC[i & 7] for i in range(16)],
    'horizon': [(i * 16, i * 16, i * 16) for i in range(16)],
    'galaxy': [(0, 0, 0), (255, 0, 0), (255, 255, 0), (255, 255, 255)] + [BBC[i & 7] for i in range(4, 16)],
    'xmastree': [BBC[i & 7] for i in range(16)],
    'sine': [(0, 0, 0), (255, 255, 0), (255, 255, 0), (255, 255, 255)] * 4,
    'teletext': [dict(zip((0, 2, 5, 7, 6, 4, 3, 1), BBC)).get(i, C64[i]) for i in range(16)],
}


def blank(pix):
    """A cleared screen: one colour only (MODE clears before drawing)."""
    return pix.count(pix[0]) == len(pix)


def palette_segments(events, video):
    """[(start time, palette name)] for the edit. A scene event with a
    'palette' takes effect at the first blank frame after it (the MODE
    change), not at the event's own time: a stalled REST call can delay
    the typed command by many seconds (measured: 17 s)."""
    pending = [(e['t'], e['palette']) for e in events
               if e.get('kind') == 'scene' and 'palette' in e]
    segs = [(0.0, 'c64')]
    for t, f, pix in frames(video):
        if not pending:
            break
        if t >= pending[0][0] and blank(pix):
            segs.append((round(t, 3), pending.pop(0)[1]))
    return segs


def repaired(path, stats=None):
    """frames() as 272x384 numpy arrays, with REST-read glitches repaired.
    A REST memory read stalls the CPU (DMA) while the picture is drawn, so
    from some line on the rest of that frame is the picture shifted by a
    line or two. Compared with the last good frame: if the changed lines
    from the first changed one down are (mostly) that frame shifted by 1-2
    lines, they are replaced by the good frame's lines; everything else
    passes unchanged. From mandelbrot-upic's frames.py (2026-10-03)."""
    import numpy as np
    good = None
    for t, n, pix in frames(path):
        f = np.frombuffer(bytes(pix), np.uint8).reshape(H, W)
        if good is None:
            good = f
            yield t, f
            continue
        changed = np.nonzero((f != good).any(axis=1))[0]
        if len(changed) >= 3:
            r = changed[0]
            rows = [y for y in changed if 2 <= y < 270 and y > r]
            shifted = sum(1 for y in rows
                          if any(np.array_equal(f[y], good[y - k]) for k in (1, -1, 2, -2)))
            if rows and shifted >= 2 and shifted >= 0.7 * len(rows):
                out = f.copy()
                out[r:] = good[r:]
                if stats is not None:
                    stats.append((round(t, 2), int(r), len(rows)))
                yield t, out
                continue
        good = f
        yield t, f


def _rainbow(h):
    """FNr of SHOW1/SHOW7: a triangle wave of the hue (0-254)."""
    h %= 255
    return h * 3 if h < 85 else (170 - h) * 3 if h < 170 else 0


def palette_at(name, t):
    """The 16 RGB colours of a palette name at take time t. Besides the
    fixed PALETTES: 'cycle:STEP:PERIOD:START', the showcase's colour
    cycles (SHOW1 STEP 6, SHOW7 STEP 5): from START on, colour L (1-15)
    is hue (L*17 + STEP*k) MOD 255 in step k, a step every PERIOD s
    (measured on the U64: 15 VDU 19 calls take about 0.5 s)."""
    if not name.startswith('cycle:'):
        return PALETTES[name]
    _, step, period, start = name.split(':')
    k = max(0, int((t - float(start)) / float(period)))
    p = int(step) * k
    out = [(0, 0, 0)]
    for L in range(1, 16):
        h = (L * 17 + p) % 255
        out.append((_rainbow(h), _rainbow(h + 85), _rainbow(h + 170)))
    return out


def _schraf_palettes():
    """FIELD: colours 1-4 from DATA; HAT: 1-8 from PROCpalette's formula;
    XMASTREE: 1-12 from DATA (demos/archbas)."""
    for i, c in enumerate([(204, 0, 0), (221, 85, 17), (238, 170, 34), (255, 255, 51)]):
        PALETTES['field'][i + 1] = c
    for L in range(8):
        T = L & 3
        PALETTES['hat'][L + 1] = ((12 + T) * 17, ((L & 3) * 4 + T) * 17, ((L // 4) * 4 + T) * 17)
    xmas = [(220, 220, 110), (120, 220, 210), (130, 100, 0), (30, 120, 40), (200, 220, 200),
            (220, 200, 100), (250, 100, 100), (150, 100, 250), (80, 150, 255),
            (80, 250, 255), (200, 150, 255), (250, 180, 255)]
    for i, c in enumerate(xmas):
        PALETTES['xmastree'][i + 1] = c


_schraf_palettes()
