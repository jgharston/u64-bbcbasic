"""A CharPad map of our own for the *MAP scene of video 2: a landscape,
200 x 25 characters (colour per character), so the video has no licence
question (docs/VIDEO_PLAN.md).

  python3 tools/video/mkmap.py OUTDIR    -> OUTDIR/LAND.ctm

Written with the E2E suite's CTM writer (tests/e2e/run_e2e.py ctm_file,
version 9, colour method 2 = per character). Background: light blue sky.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'tests', 'e2e'))
from run_e2e import ctm_file  # noqa: E402

W, H = 200, 25
SKY = 14


def glyph(rows):
    return bytes(int(r.replace('.', '0').replace('#', '1'), 2) for r in rows)


FULL = ['########'] * 8
CHARS = {                       # name: (rows, C64 colour)
    'sky': (['........'] * 8, 0),
    'cloud': (FULL, 1),
    'cloud_l': (['....####', '..######', '.#######', '########', '########', '.#######', '..######', '....####'], 1),
    'cloud_r': (['####....', '######..', '#######.', '########', '########', '#######.', '######..', '####....'], 1),
    'rock': (FULL, 12),
    'rock_up': (['.......#', '......##', '.....###', '....####', '...#####', '..######', '.#######', '########'], 12),
    'rock_dn': (['#.......', '##......', '###.....', '####....', '#####...', '######..', '#######.', '########'], 12),
    'snow': (FULL, 1),
    'snow_up': (['.......#', '......##', '.....###', '....####', '...#####', '..######', '.#######', '########'], 1),
    'snow_dn': (['#.......', '##......', '###.....', '####....', '#####...', '######..', '#######.', '########'], 1),
    'grass': (['.#...#..', '.#.#.#.#', '########', '########', '########', '########', '########', '########'], 5),
    'earth': (['########', '##.#####', '########', '#####.##', '########', '#.######', '########', '####.###'], 9),
    'crown': (['..####..', '.######.', '########', '########', '########', '########', '.######.', '..####..'], 13),
    'trunk': (['...##...'] * 8, 8),
    'water': (['........', '..##....', '.#..#..#', '#....##.', '########', '########', '########', '########'], 6),
    'deep': (FULL, 6),
    'brick': (['########', '#...#...', '#...#...', '########', '..#...#.', '..#...#.', '########', '#...#...'], 10),
    'sun': (['..####..', '.######.', '########', '########', '########', '########', '.######.', '..####..'], 7),
}
NAMES = list(CHARS)
IDX = {n: i for i, n in enumerate(NAMES)}


def build():
    rnd = random.Random(1984)
    grid = [['sky'] * W for _ in range(H)]
    # clouds
    for x0 in range(4, W - 8, 23):
        y = rnd.randint(1, 5)
        n = rnd.randint(3, 7)
        grid[y][x0] = 'cloud_l'
        for x in range(x0 + 1, x0 + n):
            grid[y][x] = 'cloud'
        grid[y][x0 + n] = 'cloud_r'
    grid[2][12], grid[2][13] = 'sun', 'sun'
    # mountains: height profile from two sine waves
    ground = 18
    for x in range(W):
        h = int(7 + 4 * math.sin(x / 9.0) + 2 * math.sin(x / 3.7 + 1))
        top = ground - max(0, h)
        for y in range(top, ground):
            grid[y][x] = 'snow' if y - top < 2 and h >= 9 else 'rock'
    for y in range(H):                  # slopes on the edges
        for x in range(1, W - 1):
            if grid[y][x] in ('rock', 'snow') and (y == 0 or grid[y - 1][x] == 'sky'):
                snow = grid[y][x] == 'snow'
                if grid[y][x - 1] == 'sky':
                    grid[y][x] = 'snow_up' if snow else 'rock_up'
                elif grid[y][x + 1] == 'sky':
                    grid[y][x] = 'snow_dn' if snow else 'rock_dn'
    # ground: grass and earth, with lakes and a brick wall
    for x in range(W):
        lake = 30 <= x % 70 < 42
        for y in range(ground, H):
            if lake:
                grid[y][x] = 'water' if y == ground else 'deep'
            else:
                grid[y][x] = 'grass' if y == ground else 'earth'
    for x in range(W):                  # trees on the grass
        if grid[ground][x] == 'grass' and rnd.random() < 0.18 and x + 1 < W:
            grid[ground - 1][x] = 'trunk'
            grid[ground - 2][x] = 'crown'
            grid[ground - 3][x] = 'crown'
    for x in range(56, 62):             # a wall
        for y in range(ground - 3, ground):
            grid[y][x] = 'brick'
    return grid


def main(out):
    os.makedirs(out, exist_ok=True)
    grid = build()
    chars = [glyph(CHARS[n][0]) for n in NAMES]
    ccols = [CHARS[n][1] for n in NAMES]
    cells = [IDX[grid[y][x]] for y in range(H) for x in range(W)]
    data = ctm_file(9, 2, chars, ccols, None, None, W, H, cells, bg=SKY, colr=1)
    open(os.path.join(out, 'LAND.ctm'), 'wb').write(data)
    print('LAND.ctm', len(data), 'bytes,', len(chars), 'characters')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/map')
