"""A contact sheet of a take: frames every STEP s from START to END, with
their times, in the take's palettes (palette_segments).

  python3 tools/video/contact.py TAKEDIR START END STEP out.png
"""
import json
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from frames import frames, to_image, PALETTES, palette_segments  # noqa: E402


def main(take, start, end, step, out):
    video = os.path.join(take, 'video.pkts')
    segs = palette_segments(json.load(open(os.path.join(take, 'events.json'))), video)
    want = [start + i * step for i in range(int((end - start) / step) + 1)]
    got = []
    for t, n, pix in frames(video):
        if not want:
            break
        if t < want[0]:
            continue
        if t > end:
            break
        while want and t >= want[0]:
            want.pop(0)
            pal = PALETTES[[name for s, name in segs if s <= t][-1]]
            got.append((t, to_image(pix, pal)))
    cols = 5
    sheet = Image.new('RGB', (cols * 384, ((len(got) + cols - 1) // cols) * 290), (40, 40, 40))
    d = ImageDraw.Draw(sheet)
    for i, (t, im) in enumerate(got):
        x, y = (i % cols) * 384, (i // cols) * 290
        sheet.paste(im, (x, y + 18))
        d.text((x + 4, y + 3), '%.1f' % t, fill=(255, 255, 0))
    sheet.save(out)


if __name__ == '__main__':
    a = sys.argv[1:]
    main(a[0], float(a[1]), float(a[2]), float(a[3]), a[4])
