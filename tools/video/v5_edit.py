"""Video 5 (demos): the edit (docs/VIDEO_PLAN.md).

  python3 tools/video/v5_edit.py build/video/v5.mp4

The showcase take (show_record.py; palettes editlib.SHOW_SEGMENTS) in full
at 1x with captions per part and its own sound (the SID song, then the
MOD from SHOW6 on: two pieces, each at its own level); then a montage
from v5, v5fern (v5_record.py) and v1bubble, sped up, under Ode to Joy
from the v1teaser take.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from editlib import HERE, SHOW_SEGMENTS, V, Video  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(V, 'v5.mp4')
v = Video(OUT, os.path.join(V, 'v5voice'), os.path.join(HERE, 'v5_narration.json'))
SH = v.take('show', SHOW_SEGMENTS)

v.title('The demos', 'The showcase, Eric Schraf\'s programs and BBC BASIC classics', 'title')

# the showcase: its sound in two pieces (the SID song, then the MOD)
v.chapter('The showcase')
v.sound_at.append((v.t, SH.audio(16.4, 128.5), 1.0))
PARTS = [
    (16.4, 29.4, 'SHOW: the title, the idi8b logo in PETSCII; the song on 8 SIDs starts', 'show'),
    (29.4, 51.2, 'SHOW1: a tunnel of filled circles, then only the palette cycles', None),
    (51.2, 75.5, 'SHOW2: Bubble Universe (Eric Schraf), with SIN from *TABLE', None),
    (75.5, 97.3, 'SHOW3: filled circles and triangles, counted for 8 s each', None),
    (97.3, 112.7, 'SHOW4: 32 multiplexed sprites over the text screen', None),
    (112.7, 128.5, 'SHOW5: a rotating cube, its edges drawn and taken away with EOR', None),
]
for s0, s1, cap, key in PARTS:
    v.u64('show', s0, s1, 1.0, cap, key)
v.sound_at.append((v.t, SH.audio(128.5, 264.0), 1.0))
PARTS = [
    (128.5, 136.0, 'SHOW6: Ultimate Audio takes over: Wild Perspective by Greg Tuby (1996)', None),
    (136.0, 178.7, 'SHOW7: a plasma from four SIN waves; then only the palette moves', None),
    (178.7, 210.5, 'SHOW8: spirographs with *LINE', None),
    (210.5, 226.1, 'SHOW9: Upic full: a sunset drawn in the REU, then shown (the music pauses)', None),
    (226.1, 262.0, 'SHOW10: the credits', None),
]
for s0, s1, cap, key in PARTS:
    v.u64('show', s0, s1, 1.0, cap, key)

# the montage, under Ode to Joy (24 voices from 32 s into the piece)
v.chapter('Schraf and the classics')
TT = v.take('v1teaser')
playing = TT.event('Playing')
music_start = v.t
T5 = v.take('v5')
s = T5.scene
v.u64('v5', s('field') + 1.0, s('field_end'), 10.0, 'Field Lines (Eric Schraf; ArchBAS by Xander Mol){speed}', 'schraf')
v.u64('v5', s('galaxy') + 1.0, s('galaxy_end'), 10.0, 'Galaxy (Eric Schraf){speed}')
v.u64('v1bubble', v.take('v1bubble').scene('bubble') + 0.3, 205.0, 25.0, 'Bubble Universe (Eric Schraf){speed}')
v.u64('v5', s('xmastree') + 1.0, s('xmastree_end'), 10.0, 'Christmas tree (Aurel Wizzard){speed}')
v.u64('v5', s('hanoi') + 6.0, s('hanoi') + 22.0, 2.0, 'The Towers of Hanoi (R.T. Russell, 1982), MODE 3{speed}', 'classics')
v.u64('v5fern', v.take('v5fern').scene('fern') + 1.0, v.take('v5fern').scene('fern_end'), 6.0,
      'A fern: 80,000 points of an iterated function system{speed}')
v.u64('v5', s('persian') + 1.0, s('persian_end'), 3.0, 'Persian (Acorn Computers): EOR line patterns{speed}')
v.u64('v5', s('polygon') + 1.0, s('polygon_end'), 2.0, 'Polygon (J.A. Coll): filled triangles{speed}')
v.u64('v5', s('sine') + 2.0, s('sine_end'), 1.5, 'Sine (J.A. Coll, 1981): text along a curve{speed}')
v.sound_at.append((music_start, TT.audio(playing + 33.0, playing + 33.0 + (v.t - music_start) + 1), 0.6))

v.closing(['BBC BASIC 3.10: Sophie Wilson and Acorn Computers.  The C64 port: Ivo van Poorten',
           'Graphics: Eric Schraf (via ArchBAS), Aurel Wizzard.  Classics: R.T. Russell, J.A. Coll, Acorn, D. Williams',
           'MODs: Greg Tuby, Slice.  MOD player: ModPlayer_16k by Freshness.  Showcase and code: Xander Mol'])
v.finish()
