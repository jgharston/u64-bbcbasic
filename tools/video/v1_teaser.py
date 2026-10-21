"""Video 1, scene 10: the teaser montage takes (docs/VIDEO_PLAN.md).

  python3 tools/video/v1_teaser.py build/video/takes/v1teaser [scene,...]

The demos as deployed on the SD card, each started with CHAIN from its
folder; the edit uses about 3 s of each. The Upic picture comes from the
SHOW9 (upic) on its own.
  music     MUSIC: piece 7 (Ode to Joy), the 24 voice bars (MODE 100, C64 palette)
  invaders  INVADERS: a game played with the joystick in port 2 (MODE 132)
  ttx       U64TEXT: the Ceefax pages (MODE 7, teletext palette)
  upic      SHOW9: the sunset drawn and shown (Upic full, MODE 110)
  bubble    SCHRAF, L, 1: Bubble Universe drawn live (MODE 2), for scene 4b
  browse    *BROWSE: the file browser
Between the demos the remote's ESCAPE ends a program (one short DMA).
"""
import random
import sys
import time

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from rec import Take  # noqa: E402

HOST = '192.168.1.148'
CRT = 'build/u64bbc-tmb.crt'
DEMOS = '/SD/idi8b/u64bbcbasic/demos/'
DOWN = 'cursor_up_down'
RIGHT = 'cursor_left_right'
LEFT = ['left_shift', 'cursor_left_right']


def joy(T, inputs, transition):
    import json
    T.rest('POST', '/v1/machine:input', json.dumps({'events': [
        {'kind': 'joystick', 'port': 2, 'inputs': inputs, 'transition': transition}]}).encode(),
        'application/json')


def escape(T):
    T.rm.stop()
    T.ev('escape')
    T.wait_prompt(20)
    time.sleep(1)


def music(T):
    T.scene('music')
    T.type('*DIR %smusic\n' % DEMOS)
    T.type('CHAIN "MUSIC"\n')
    time.sleep(8)
    T.tap(['7'], 'piece 7: Ode to Joy, 24 voices')
    T.wait_text('Playing', 240)
    time.sleep(48)          # all 24 voices from bar 16 (32 s at 120 bpm)
    T.tap(['space'], 'stop the piece')
    time.sleep(3)
    T.tap(['q'], 'quit')
    T.wait_prompt(20)


def invaders(T):
    T.scene('invaders')
    T.type('*DIR %ssprites\n' % DEMOS)
    T.type('CHAIN "INVADERS"\n')
    time.sleep(8)
    T.tap(['space'], 'start a game')
    rnd = random.Random(64)
    t = time.monotonic()
    while time.monotonic() - t < 25:
        d = rnd.choice(['left', 'right'])
        joy(T, [d, 'fire'], 'press')
        time.sleep(rnd.uniform(0.3, 0.8))
        joy(T, [d, 'fire'], 'release')
        time.sleep(0.1)
    T.ev('joystick done')
    T.tap(['run_stop'], 'back to the title')
    time.sleep(3)
    T.tap(['q'], 'quit')
    T.wait_prompt(20)
    T.type('MODE 100\n')


def ttx(T):
    T.scene('ttx', palette='teletext')
    T.type('*DIR %snet\n' % DEMOS)
    T.type('CHAIN "U64TEXT"\n')
    time.sleep(12)
    for page in ('200', '300', '400'):
        T.type(page, 'page ' + page)
        time.sleep(9)
    escape(T)
    T.scene('back_to_text', palette='c64')
    T.type('MODE 100\n')
    time.sleep(2)


def upic(T):
    """SHOW9 on its own: the sunset drawn, then shown (Upic full, its
    palette from SHOW9's DATA lines in post)."""
    T.scene('upic', palette='show9')
    T.type('*DIR %sshowcase\n' % DEMOS)
    T.type('CHAIN "SHOW9"\n')
    T.wait_text('Done. Upic full', 120)
    T.tap(['space'], 'skip the explanation')
    time.sleep(10)
    T.tap(['space'], 'end the show')
    time.sleep(2)
    escape(T)
    T.scene('back_to_text', palette='c64')
    T.type('MODE 100\n')
    time.sleep(2)


def bubble(T):
    """Bubble Universe (Schraf, via ArchBAS) live in MODE 2, as on the
    Archimedes clip of scene 4b; its palette from BUBBLE's DATA in post."""
    T.scene('bubble_menu')
    T.type('*DIR %sarchbas\n' % DEMOS)
    T.type('CHAIN "SCHRAF"\n')
    time.sleep(4)
    T.tap(['l'], 'live mode')
    time.sleep(1)
    T.scene('bubble', palette='bubble')
    T.tap(['1'], 'Bubble Universe')
    time.sleep(180)         # still drawing: ESCAPE chains back to the menu
    T.scene('bubble_back', palette='c64')
    T.rm.stop()
    T.ev('escape')
    time.sleep(4)
    T.tap(['q'], 'quit the menu')
    T.wait_prompt(20)
    T.type('MODE 100\n')
    time.sleep(2)


def browse(T):
    T.scene('browse')
    T.type('*BROWSE\n')
    time.sleep(3)
    T.tap([DOWN] * 3, 'down')
    time.sleep(1)
    T.tap([RIGHT], 'into the folder')
    time.sleep(2)
    T.tap([DOWN] * 4, 'down')
    time.sleep(2)
    T.tap([LEFT], 'up a folder')
    time.sleep(2)
    T.tap(['q'], 'quit')
    time.sleep(2)


SCENES = {'music': music, 'invaders': invaders, 'ttx': ttx, 'upic': upic, 'bubble': bubble, 'browse': browse}


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
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/takes/v1teaser',
         sys.argv[2].split(',') if len(sys.argv) > 2 else list(SCENES))
