"""Video 2 (graphics): the edit (docs/VIDEO_PLAN.md).

  python3 tools/video/v2_edit.py build/video/v2.mp4

Takes: v2 and v2sedit (v2_record.py), show (show_record.py, palettes from
editlib.SHOW_SEGMENTS), v1teaser (Invaders). Voice: build/video/v2voice
(voices.py tools/video/v2_narration.json).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from editlib import HERE, SHOW_SEGMENTS, V, Video  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(V, 'v2.mp4')
v = Video(OUT, os.path.join(V, 'v2voice'), os.path.join(HERE, 'v2_narration.json'))
v.take('show', SHOW_SEGMENTS)
T2 = v.take('v2')
bbc = [e['t'] for e in T2.events if e.get('name') == 'gfxbbc']

v.title('Graphics', 'Screen modes, shapes, Upic, sprites, maps and PETSCII', 'title')

v.u64('v2', bbc[0] + 0.3, bbc[2], 1.0, 'GFXBBC in MODE 1 and 2: lines, circles, ellipses, triangles, rectangles, a pattern fill',
      'shapes', 'BBC graphics')
v.u64('v2', bbc[2], bbc[4], 1.0, 'The same test card in MODE 4 (2 colours) and MODE 5 (4 colours)', 'modes')
v.u64('show', 59.0, 75.2, 1.0, 'Bubble Universe (Eric Schraf, via ArchBAS): Upic Lite, MODE 2', 'upiclite',
      'Upic Lite', sound=True)
v.u64('v2', T2.scene('gfxc64') + 1.0, T2.scene('gfxc64') + 16.0, 1.5,
      'GFXC64: MODE 100 (text), 103 (hires), 104 (multicolour){speed}', 'c64', 'C64 modes and teletext')
v.u64('v2', T2.scene('gfxttx') + 0.2, T2.scene('gfxttx_end'), 1.0, 'GFXTTX: MODE 7, teletext as on the BBC', 'ttx')
v.u64('show', 75.6, 97.3, 2.0, 'SHOW3: *CIRCLE FILL and triangles, counted for 8 s each{speed}', 'race', 'Speed')
v.u64('show', 210.6, 226.0, 1.0, 'SHOW9: Upic full, MODE 110: drawn in the REU, then shown', 'upicfull',
      'Upic full', sound=True)
v.u64('show', 113.0, 121.0, 1.0, 'SHOW5: a cube turned with SIN from *TABLE, drawn with EOR', 'tables',
      'Tables: cube, plasma, spirographs', sound=True)
v.u64('show', 137.0, 148.0, 2.0, 'SHOW7: a plasma from four SIN waves{speed}')
v.u64('show', 148.0, 156.0, 1.0, 'SHOW7: then only the palette changes (VDU 19 with RGB)', sound=True)
v.u64('show', 180.0, 192.0, 1.5, 'SHOW8: spirographs with *LINE{speed}')
v.u64('v2', T2.scene('balls') + 6.0, T2.scene('balls') + 16.0, 1.0, 'BALLS: 32 multiplexed sprites over the text screen',
      'sprites', 'Sprites and the sprite editor', sound=True)
v.u64('v1teaser', v.take('v1teaser').scene('invaders') + 10.0, v.take('v1teaser').scene('invaders') + 21.0, 1.0,
      'INVADERS: a game with multiplexed sprites and SID sound', sound=True)
v.u64('v2sedit', 14.0, 62.0, 3.0, '*SEDIT VIC 0: the sprite editor, a shape in multicolour{speed}', 'sedit')
v.u64('v2', T2.scene('map') + 5.5, T2.scene('map') + 29.5, 2.0,
      'Our own CharPad map (LAND.ctm), *MAP DRAW in a FOR loop{speed}', 'map', 'Maps and PETSCII')
v.u64('v2', T2.scene('petscii') + 2.0, T2.scene('petscii') + 27.5, 1.5,
      'PETSCII: the C64 graphics keys and colours, the idi8b logo (*SEQ){speed}', 'petscii')

v.closing(['BBC BASIC 3.10: Sophie Wilson and Acorn Computers.  The C64 port: Ivo van Poorten',
           'Bubble Universe: Eric Schraf (via ArchBAS).  Upic: Aleksi Eeben, Christian Gleissner',
           'Code, demos and the map: Xander Mol'])
v.finish()
