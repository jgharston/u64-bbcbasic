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
