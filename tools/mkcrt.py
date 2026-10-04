#!/usr/bin/env python3
"""Pack 16K bank images into a .crt cartridge file.

Types:
  ef   EasyFlash (CRT type 32), subtype 1: the Ultimate then allows the REU
       and the UCI (moved to $DE1C), not Ultimate Audio. Each bank becomes
       two 8K CHIP packets (ROML at $8000, ROMH at $A000), as VICE and the
       Ultimate expect for EasyFlash. Starts in Ultimax mode (EXROM=1,
       GAME=0).
  tmb  Protovision TwoMegabyter (CRT type 87): one 16K CHIP packet per
       bank at $8000, starts in 16K mode (EXROM=0, GAME=0). Follows
       Protovision's make_crt_twomeg.py (GideonZ/1541ultimate,
       software/6502/megabyter).

CRT format: VICE manual chapter 17 (header $40 bytes, big-endian fields,
subtype at offset $1A).

Usage: mkcrt.py --type ef|tmb --name NAME -o OUT.crt BANK [BANK ...]

Each BANK is a file of 16K banks, all used in order, or FILE:N for only
the N-th 16K bank of FILE. Banks are numbered in the order given.
"""
import argparse
import struct

TYPES = {
    #       type, exrom, game, subtype, version, split banks
    "ef":  (32, 1, 0, 1, 0x0101, True),
    "tmb": (87, 0, 0, 0, 0x0100, False),
}


def chip(bank, load, data, chip_type):
    return (b"CHIP" + struct.pack(">LHHHH", 0x10 + len(data), chip_type,
                                  bank, load, len(data)) + data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", required=True, choices=TYPES)
    ap.add_argument("--name", required=True)
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("banks", nargs="+")
    args = ap.parse_args()

    hwtype, exrom, game, subtype, version, split = TYPES[args.type]
    name = args.name.encode("ascii")[:32].ljust(32, b"\0")
    out = bytearray(b"C64 CARTRIDGE   ")
    out += struct.pack(">LHHBBB", 0x40, version, hwtype, exrom, game, subtype)
    out += b"\0" * (0x20 - len(out))
    out += name
    assert len(out) == 0x40

    banks = []
    for spec in args.banks:
        path, _, index = spec.partition(":")
        data = open(path, "rb").read()
        if len(data) % 0x4000:
            raise SystemExit("%s: %d bytes, not a multiple of 16384" % (path, len(data)))
        chunks = [data[i:i + 0x4000] for i in range(0, len(data), 0x4000)]
        banks += [chunks[int(index)]] if index else chunks

    for n, data in enumerate(banks):
        if split:
            out += chip(n, 0x8000, data[:0x2000], 2)   # 2 = flash
            out += chip(n, 0xA000, data[0x2000:], 2)
        else:
            out += chip(n, 0x8000, data, 0)            # 0 = ROM

    with open(args.output, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    main()
