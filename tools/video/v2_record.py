"""Video 2 (graphics): the takes on the U64 (docs/VIDEO_PLAN.md).

  python3 tools/video/v2_record.py build/video/takes/v2 [scene,...]

The showcase parts (SHOW3, 5, 7, 8, 9) come from the showcase take
(show_record.py), Bubble Universe from v1bubble, Invaders from v1teaser.
  gfxtour  GFXDEMO: 1 GFXBBC (MODE 1, 2, 4, 5), 2 GFXC64 (100, 103, 104),
           3 GFXTTX (MODE 7); a palette tag before each mode change
  balls    BALLS: 32 multiplexed sprites
  sedit    *SEDIT VIC 0: the sprite editor, a few pixels painted, ESCAPE
  map      MAPSCRL: our own CharPad map (mkmap.py) scrolled with *MAP DRAW
  petscii  PETSCII: typing with the graphics keys, the logo, the end
"""
import sys
import time

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from rec import Take  # noqa: E402

HOST = '192.168.1.148'
CRT = 'build/u64bbc-tmb.crt'
DEMOS = '/SD/idi8b/u64bbcbasic/demos/'
VIDEO = '/SD/idi8b/u64bbcbasic/video'
RIGHT, DOWN = 'cursor_left_right', 'cursor_up_down'


def gfxtour(T):
    T.scene('gfxdemo', palette='c64')
    T.type('*DIR %sgfx\n' % DEMOS)
    T.type('CHAIN "GFXDEMO"\n')
    time.sleep(4)
    for key, pal, wait in (('1', 'bbc_mode1', 7), ('space', 'bbc_mode2', 7),
                           ('space', 'bbc_mode0', 6), ('space', 'bbc_mode1', 6),
                           ('space', 'c64', 3)):
        T.scene('gfxbbc', palette=pal)
        T.tap([key], 'next mode')
        time.sleep(wait)
    T.scene('gfxc64')
    T.tap(['2'], 'C64 modes')
    time.sleep(4)
    for _ in range(3):
        T.tap(['space'], 'next C64 mode')
        time.sleep(5)
    T.scene('gfxttx', palette='teletext')
    T.tap(['3'], 'teletext')
    time.sleep(7)
    T.scene('gfxttx_end', palette='c64')
    T.tap(['space'], 'back to the menu')
    time.sleep(3)
    T.tap(['0'], 'quit')
    T.wait_prompt(20)


def balls(T):
    T.scene('balls')
    T.type('*DIR %ssprites\n' % DEMOS)
    T.type('CHAIN "BALLS"\n')
    time.sleep(18)
    T.tap(['run_stop'], 'end')
    T.wait_prompt(20)
    T.type('CLS\n')


def sedit(T):
    """VIC shape 0 in multicolour (4 colours): cleared, a square outline,
    filled, a diagonal, flipped. One key per request, 0.25 s apart: the
    editor redraws after each key and misses keys sent faster."""
    LEFT = ['left_shift', 'cursor_left_right']
    UP = ['left_shift', 'cursor_up_down']

    def key(k, pause=0.25):
        T.tap([k])
        time.sleep(pause)

    T.scene('sedit')
    T.type('*SEDIT VIC 0\n')
    time.sleep(3)
    key('m', 1.0)
    key('c', 1.0)
    T.ev('cleared, multicolour')
    key('1')
    for move in (RIGHT, DOWN, LEFT, UP):
        for _ in range(8):
            key('space')
            key(move)
    T.ev('outline')
    key(RIGHT)
    key(DOWN)
    key('2')
    key('f', 1.5)
    T.ev('filled')
    key('3')
    for _ in range(7):
        key('space')
        key(RIGHT)
        key(DOWN)
    T.ev('diagonal')
    time.sleep(1.5)
    key('h', 2.0)
    key('v', 2.0)
    T.tap(['run_stop'], 'ESCAPE: leave it as it was')
    T.wait_prompt(20)
    T.type('CLS\n')


def mapscroll(T):
    T.scene('map')
    T.type('*DIR %s\n' % VIDEO)
    T.type('CHAIN "MAPSCRL"\n')
    time.sleep(25)
    T.wait_prompt(60)
    T.type('CLS\n')


def petscii(T):
    T.scene('petscii')
    T.type('*DIR %spetscii\n' % DEMOS)
    T.type('CHAIN "PETSCII"\n')
    time.sleep(5)
    # C= and SHIFT graphics, colours with CTRL+digit
    for ctl, keys in (('3', 'qwertyuiop'), ('6', 'asdfghjkl'), ('8', 'zxcvbnm')):
        T.tap([['ctrl', ctl]], 'colour')
        T.tap([['commodore', k] for k in keys] + [['left_shift', k] for k in keys], 'graphics keys')
        T.tap(['return'])
    time.sleep(2)
    T.tap(['f1'], 'the logo')
    time.sleep(6)
    T.tap(['space'], 'back')
    time.sleep(2)
    T.tap(['f7'], 'end')
    T.wait_prompt(20)


SCENES = {'gfxtour': gfxtour, 'balls': balls, 'sedit': sedit, 'map': mapscroll, 'petscii': petscii}


def main(out, names):
    T = Take(HOST, out)
    try:
        T.start()
        T.started(CRT)
        for n in names:
            SCENES[n](T)
        T.scene('end')
    finally:
        T.finish()


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/takes/v2',
         sys.argv[2].split(',') if len(sys.argv) > 2 else list(SCENES))
