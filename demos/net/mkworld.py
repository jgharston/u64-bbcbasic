#!/usr/bin/env python3
"""The world map of U64TEXT's ISS page as BASIC DATA lines.

Land from Natural Earth's 1:110m land polygons (public domain,
https://www.naturalearthdata.com/; GeoJSON from
github.com/nvkelso/natural-earth-vector, geojson/ne_110m_land.geojson),
drawn equirectangular: 72 x 48 points for longitude -180..180 and
latitude 80..-80 (5 degrees across, 3.33 down), each point land when
most of it is (drawn 4 times larger, then counted).

Teletext mosaics: 36 x 16 cells of 2 x 3 points. A cell's six points as
the bits 0-5 (top left, top right, middle left, middle right, bottom
left, bottom right), written as CHR$(48 + bits) so the DATA stays plain
ASCII; the program makes the mosaic code 160 + (b AND 31) + (b AND 32) * 2.

    python3 mkworld.py ne_110m_land.geojson [first line number]
"""
import json
import sys

from PIL import Image, ImageDraw

W, H, S = 72, 48, 4
LAT0, LAT1 = 80.0, -80.0


def mask(geojson):
    img = Image.new("1", (W * S, H * S), 0)
    draw = ImageDraw.Draw(img)
    for feat in json.load(open(geojson))["features"]:
        geom = feat["geometry"]
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        for poly in polys:
            for k, ring in enumerate(poly):
                pts = [((lon + 180) / 360 * W * S, (LAT0 - lat) / (LAT0 - LAT1) * H * S)
                       for lon, lat in ring]
                draw.polygon(pts, fill=0 if k else 1)
    px = img.load()
    return [[sum(px[x * S + i, y * S + j] for i in range(S) for j in range(S)) * 2 > S * S
             for x in range(W)] for y in range(H)]


def main():
    m = mask(sys.argv[1])
    line = int(sys.argv[2]) if len(sys.argv) > 2 else 5600
    for cy in range(H // 3):
        row = ""
        for cx in range(W // 2):
            b = 0
            for bit, (dx, dy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2))):
                if m[cy * 3 + dy][cx * 2 + dx]:
                    b |= 1 << bit
            row += chr(48 + b)
        print('%d   DATA "%s"' % (line, row))
        line += 10


if __name__ == "__main__":
    main()
