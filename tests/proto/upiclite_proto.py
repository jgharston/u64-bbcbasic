#!/usr/bin/env python3
"""Upic Lite prototype: a standalone PRG that shows a 320x256 test picture
(1 or 2 bits per pixel) live with the generated renderer, to judge the
picture on hardware (tools/u64shot.py) before it goes into the MOS.

    tests/proto/upiclite_proto.py --bpp 2 [--delay 120] [--run HOST]

The palette is not set here: the VIC stream carries the colour index, and
the screenshot decodes it (index AND 1, or AND 3). The test picture: text in the C64 font (read from VICE's character ROM,
used only for this local test image), 1-pixel stripes, a diagonal, a
circle and colour bars. Builds build/proto/upiclite<bpp>.prg.
"""
import argparse
import math
import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import upiclite_gen  # noqa: E402

CHARGEN = "/usr/local/share/vice/C64/chargen-901225-01.bin"
COLS, TABLES, CODE = 0x3000, 0x9000, 0x8000
W, H = 320, 256


def picture(bpp):
    px = [[0] * W for _ in range(H)]
    rom = open(CHARGEN, "rb").read()
    top = (1 << bpp) - 1

    def text(x, y, s, c):
        for i, ch in enumerate(s):
            o = ord(ch)
            sc = o - 64 if 64 <= o < 96 else (o - 96 + 0 if 96 <= o < 128 else o)
            if 97 <= o <= 122:
                sc = o - 96 + 0       # lower case letters in the lower/upper set
                g = rom[0x800 + (o - 96) * 8:0x800 + (o - 96) * 8 + 8]
            elif 65 <= o <= 90:
                g = rom[0x800 + (o - 64 + 64) * 8:0x800 + (o - 64 + 64) * 8 + 8]
            else:
                g = rom[0x800 + sc * 8:0x800 + sc * 8 + 8]
            for r in range(8):
                for b in range(8):
                    if g[r] & (0x80 >> b):
                        px[y + r][x + i * 8 + b] = c
    lines = ["The quick brown fox jumps over the lazy",
             "dog. THE QUICK BROWN FOX 0123456789 !?",
             "Upic Lite: 320x256 live, %d bit%s/pixel" % (bpp, "s" if bpp > 1 else "")]
    for i, s in enumerate(lines):
        text(0, i * 8, s, top if i != 1 else (2 if bpp == 2 else 1))
    for y in range(32, 64):                     # 1-pixel stripes, 2-pixel stripes
        for x in range(0, 160):
            px[y][x] = top if x % 2 == 0 else 0
        for x in range(160, 320):
            px[y][x] = top if (x // 2) % 2 == 0 else 0
    for x in range(W):                          # diagonal
        y = 64 + x * 191 // (W - 1)
        if y < H:
            px[y][x] = top
    for a in range(720):                        # circle
        x = int(240 + 60 * math.cos(a * math.pi / 360))
        y = int(160 + 60 * math.sin(a * math.pi / 360))
        px[y][x] = 1
    if bpp == 2:
        for c in range(4):                      # colour bars
            for y in range(230, 256):
                for x in range(c * 40, c * 40 + 40):
                    px[y][x] = c
    for y in range(H):                          # frame
        px[y][0] = px[y][W - 1] = top
    for x in range(W):
        px[0][x] = px[H - 1][x] = top if px[0][x] == 0 else px[0][x]
    # pack column-major, leftmost pixel in the lowest bits
    ppb = 8 // bpp
    data = bytearray(W // ppb * 256)
    for c in range(W // ppb):
        for y in range(H):
            v = 0
            for n in range(ppb):
                v |= px[y][c * ppb + n] << (n * bpp)
            data[c * 256 + y] = v
    return data


def build(bpp, delay):
    out = os.path.join(ROOT, "build", "proto")
    os.makedirs(out, exist_ok=True)
    src, times = upiclite_gen.generate(bpp, COLS, TABLES, delay, "ul_line")
    open(os.path.join(out, "renderer%d.s" % bpp), "w").write(src)
    open(os.path.join(out, "picture%d.bin" % bpp), "wb").write(picture(bpp))
    tabs = []
    if bpp == 2:                    # shift tables: b >> 2, 4, 6
        for sh in (2, 4, 6):
            tabs.append(", ".join("$%02X" % (b >> sh) for b in range(256)))
    main = """; Upic Lite prototype (tests/proto/upiclite_proto.py)
    opt h-
    org $0801
    dta a($080B), a(2026), $9E, c'2061', 0, a(0)
start:
    sei
    lda #$35                    ; KERNAL out: no ROM IRQ vector needed
    sta $01
    lda #$7F                    ; CIA interrupts off
    sta $DC0D
    lda $DC0D
    lda #$00                    ; display off: all border
    sta $D011
; frame loop: as uii_upic_frame_asm (ultimate-uci-oscar64, Upic module)
frame:
    lda $D011
    bpl frame
f2:
    lda $D011
    bmi f2
    lda #$18
tw:
    cmp $D012
    bne tw
    ldy #0
line:
    lda $D012
lw:
    cmp $D012
    beq lw
    lda #$80
    ldx #$8F
    sta $D031
    stx $D031
    jsr ul_line
    iny
    bne line
    jmp frame

    :[COLS-*] dta 0             ; one continuous image: MADS leaves
    ins 'picture%(bpp)d.bin'    ; gaps between org segments out
    :[CODE-*] dta 0
    icl 'renderer%(bpp)d.s'
    .if * > TABLES
    .error "renderer too long"
    .endif
    :[TABLES-*] dta 0
""" % {"bpp": bpp}
    main = main.replace("COLS", "$%04X" % COLS).replace("CODE", "$%04X" % CODE) \
               .replace("TABLES", "$%04X" % TABLES)
    for t in tabs:
        main += "    dta " + t + "\n"
    asm = os.path.join(out, "upiclite%d.s" % bpp)
    open(asm, "w").write(main)
    prg = os.path.join(out, "upiclite%d.prg" % bpp)
    r = subprocess.run(["mads", asm, "-o:" + prg, "-i:" + out], capture_output=True, text=True)
    if r.returncode or "ERROR" in r.stdout:
        raise SystemExit(r.stdout[-2000:])
    # MADS writes a raw image from $0801: make it a PRG
    data = open(prg, "rb").read()
    open(prg, "wb").write(bytes([0x01, 0x08]) + data)
    print(prg, len(data), "bytes; last store at cycle %.0f" % times[-1])
    return prg


def run(prg, host):
    req = urllib.request.Request("http://%s/v1/runners:run_prg" % host,
                                 data=open(prg, "rb").read(), method="POST",
                                 headers={"Content-Type": "application/octet-stream"})
    print(urllib.request.urlopen(req, timeout=20).read().decode()[:200])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--bpp", type=int, choices=(1, 2), default=2)
    ap.add_argument("--delay", type=int, default=0, help="0: computed")
    ap.add_argument("--run")
    a = ap.parse_args()
    # pixel 0 on dot 32: Upic's first store, ~616 cycles after entry, is
    # dot 0; + 32 dots = 868 cycles
    d = a.delay or (172 if a.bpp == 1 else 140)
    p = build(a.bpp, d)
    if a.run:
        run(p, a.run)
