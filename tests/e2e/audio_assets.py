"""Test assets for Ultimate Audio: a small ProTracker MOD and an 8-bit WAV,
made here (no third-party music in the repository).

make_mod(): 31 samples, "M.K.", one pattern of 64 rows: channel 0 plays a
looped square wave (sample 1) on C, E, G every 4 rows; channel 1 a
noise burst (sample 2, not looped) every 16 rows; row 32 sets the speed
(F03) and row 48 has a volume slide (A01), so the effects path runs.
make_wav(n, rate): an 8-bit mono WAV of n bytes (unsigned, a sawtooth).
"""
import struct


def _sample_header(name, length, volume, rep_start=0, rep_len=1):
    return (name.encode()[:22].ljust(22, b"\0")
            + struct.pack(">HBBHH", length // 2, 0, volume,
                          rep_start // 2, max(rep_len // 2, 1)))


def make_mod():
    square = bytes([0x60] * 16 + [0xA0] * 16)          # signed: +96 / -96
    noise = bytes(((i * 73) ^ (i >> 3)) & 0xFF for i in range(2000))
    head = b"U64 BBC BASIC TEST".ljust(20, b"\0")
    head += _sample_header("square", len(square), 64, 0, len(square))
    head += _sample_header("noise", len(noise), 48)
    for _ in range(29):
        head += _sample_header("", 0, 0)
    head += bytes([1, 127]) + bytes(128) + b"M.K."
    assert len(head) == 1084
    rows = []
    notes = [428, 339, 285]                              # C-2, E-2, G-2
    for r in range(64):
        cells = []
        for ch in range(4):
            smp, period, fx, par = 0, 0, 0, 0
            if ch == 0 and r % 4 == 0:
                smp, period = 1, notes[(r // 4) % 3]
            if ch == 1 and r % 16 == 0:
                smp, period = 2, 428
            if ch == 2 and r == 32:
                fx, par = 0xF, 3                         # speed 3
            if ch == 2 and r == 48:
                fx, par = 0xA, 0x01                      # volume slide
            cells.append(bytes([(smp & 0xF0) | (period >> 8), period & 0xFF,
                                ((smp & 0x0F) << 4) | fx, par]))
        rows.append(b"".join(cells))
    return head + b"".join(rows) + square + noise


def make_wav(n=4000, rate=8000):
    data = bytes((i * 4) & 0xFF for i in range(n))
    fmt = struct.pack("<HHIIHH", 1, 1, rate, rate, 1, 8)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt \
        + b"data" + struct.pack("<I", len(data)) + data
    return b"RIFF" + struct.pack("<I", len(body)) + body


if __name__ == "__main__":
    import sys
    open(sys.argv[1], "wb").write(make_mod())
    open(sys.argv[2], "wb").write(make_wav())
