#!/usr/bin/env python3
"""Screenshot of an Ultimate 64 / C64 Ultimate from its VIC video stream.

    tools/u64shot.py --host 192.168.1.148 -o shot.png [--port 11002]

Grabs one complete frame (384 x 272 colour indexes) and writes it as a PNG
in the default C64 palette, scaled 2x. Pixel-exact: no emulator, no camera.

Based on VicStream in mandelbrot-upic (tests/e2e/ultimate.py, Xander Mol):
the stream's packet format, multicast group and per-device port. Adapted:
standalone, one frame, PNG output. Under WSL2 use a port in the firewall
rule's range (11000-11010); OBS must not hold the stream.
"""
import argparse
import urllib.parse
import socket
import struct
import sys
import time
import urllib.request

GROUP = "239.0.1.64"
WIDTH = 384
HEADER = 12

# C64 colours (Pepto's palette), RGB
PALETTE = [
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x68, 0x37, 0x2B), (0x70, 0xA4, 0xB2),
    (0x6F, 0x3D, 0x86), (0x58, 0x8D, 0x43), (0x35, 0x28, 0x79), (0xB8, 0xC7, 0x6F),
    (0x6F, 0x4F, 0x25), (0x43, 0x39, 0x00), (0x9A, 0x67, 0x59), (0x44, 0x44, 0x44),
    (0x6C, 0x6C, 0x6C), (0x9A, 0xD2, 0x84), (0x6C, 0x5E, 0xB5), (0x95, 0x95, 0x95),
]


def rest(host, method, path, params=None):
    url = "http://%s%s" % (host, path)
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, method=method)
    with urllib.request.urlopen(req, timeout=10) as f:
        return f.read()


def local_address(host):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.connect((socket.gethostbyname(host), 80))
        return s.getsockname()[0]


def grab(host, port, timeout=10.0):
    """One complete frame as a list of rows of colour indexes. Tries a
    second time if the stream does not start (seen now and then)."""
    try:
        return grab_frames(host, port, 1, 0.0, timeout)[0]
    except (TimeoutError, socket.timeout):
        time.sleep(1.0)
        return grab_frames(host, port, 1, 0.0, timeout)[0]


def grab_frames(host, port, count, interval, timeout=10.0):
    """count complete frames, at least interval seconds apart, from one
    stream session (starting and stopping the stream in quick succession
    has left an Ultimate's network task hanging). The U64-II's stream
    stops by itself after about a second, so count *
    interval must stay under that."""
    source = socket.gethostbyname(host)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
    sock.bind(("", port))
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                    socket.inet_aton(GROUP) + socket.inet_aton(local_address(host)))
    sock.settimeout(2.0)
    rest(host, "PUT", "/v1/streams/video:start", {"ip": "%s:%d" % (GROUP, port)})
    frames, next_at = [], 0.0
    try:
        deadline = time.monotonic() + timeout + count * interval
        current, lines, started = None, {}, False
        while time.monotonic() < deadline:
            data, addr = sock.recvfrom(2048)
            if addr[0] != source or len(data) < HEADER:
                continue
            _, frame, line, width, per, bpp, _ = struct.unpack_from("<HHHHBBH", data)
            if width != WIDTH or bpp != 4:
                continue
            last = bool(line & 0x8000)
            line &= 0x7FFF
            if frame != current:
                current, lines = frame, {}
            payload = data[HEADER:]
            for i in range(per):
                lines[line + i] = payload[i * 192:(i + 1) * 192]
            if last:
                height = line + per
                if started and len(lines) == height and time.monotonic() >= next_at:
                    rows = []
                    for y in range(height):
                        row = bytearray(WIDTH)
                        row[0::2] = bytes(b & 15 for b in lines[y])
                        row[1::2] = bytes(b >> 4 for b in lines[y])
                        rows.append(bytes(row))
                    frames.append(rows)
                    if len(frames) == count:
                        return frames
                    next_at = time.monotonic() + interval
                started = True
                current, lines = None, {}
        raise SystemExit("no complete frame received")
    finally:
        try:
            rest(host, "PUT", "/v1/streams/video:stop")
        finally:
            sock.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, default=11002)
    ap.add_argument("-o", "--output", default="shot.png")
    ap.add_argument("--scale", type=int, default=2)
    args = ap.parse_args()
    rows = grab(args.host, args.port)
    from PIL import Image
    img = Image.new("RGB", (WIDTH, len(rows)))
    img.putdata([PALETTE[c] for row in rows for c in row])
    if args.scale > 1:
        img = img.resize((WIDTH * args.scale, len(rows) * args.scale), Image.NEAREST)
    img.save(args.output)
    print(args.output)


if __name__ == "__main__":
    sys.exit(main())
