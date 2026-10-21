"""Video 5 (demos): the montage takes (docs/VIDEO_PLAN.md). The showcase
itself comes from show_record.py.

  python3 tools/video/v5_record.py build/video/takes/v5 [scene,...]

  schraf    SCHRAF, live mode: Field Lines, Mathematical Hat, Event
            Horizon, Galaxy (75 s each, ESCAPE back to the menu)
  xmas      XMAS, live mode: the Christmas tree (Aurel Wizzard)
  classics  Hanoi (MODE 3), fern, persian, polygon (MODE 2), sine (MODE 1)
A palette tag before each mode change (frames.PALETTES).
"""
import sys
import time

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from rec import Take  # noqa: E402

HOST = '192.168.1.148'
CRT = 'build/u64bbc-tmb.crt'
DEMOS = '/SD/idi8b/u64bbcbasic/demos/'


def escape(T):
    T.rm.stop()
    T.ev('escape')


def schraf(T):
    T.scene('schraf_menu', palette='c64')
    T.type('*DIR %sarchbas\n' % DEMOS)
    T.type('CHAIN "SCHRAF"\n')
    time.sleep(4)
    T.tap(['l'], 'live mode')
    time.sleep(1)
    for key, name in (('2', 'field'), ('3', 'hat'), ('4', 'horizon'), ('5', 'galaxy')):
        T.scene(name, palette=name)
        T.tap([key], name)
        time.sleep(75)
        T.scene(name + '_end', palette='c64')
        escape(T)
        time.sleep(4)
    T.tap(['q'], 'quit the menu')
    T.wait_prompt(20)


def xmas(T):
    T.scene('xmas_menu', palette='c64')
    T.type('*DIR %sarchbas\n' % DEMOS)
    T.type('CHAIN "XMAS"\n')
    time.sleep(4)
    T.tap(['l'], 'live mode')
    time.sleep(1)
    T.scene('xmastree', palette='xmastree')
    T.tap(['space'], 'the tree')
    time.sleep(90)
    T.scene('xmastree_end', palette='c64')
    escape(T)
    time.sleep(4)
    if T.rm.state()['state'] != 'prompt':
        T.tap(['q'], 'quit')
        time.sleep(2)
    if T.rm.state()['state'] != 'prompt':
        escape(T)
    T.wait_prompt(20)
    T.type('MODE 100\n')


def classics(T):
    T.type('*DIR %sclassics\n' % DEMOS)
    T.scene('hanoi')
    T.type('CHAIN "HANOI"\n')
    time.sleep(3)
    T.type('6\n', '6 discs')
    time.sleep(2)
    T.tap(['space'], 'start')
    time.sleep(25)
    escape(T)
    T.wait_prompt(20)
    time.sleep(1.5)         # a key typed right after the prompt got lost
    for name, pal, wait in (('FERN', 'bbc_mode2', 40), ('PERSIAN', 'bbc_mode2', 20),
                            ('POLYGON', 'bbc_mode2', 15), ('SINE', 'sine', 10)):
        T.scene(name.lower(), palette=pal)
        T.type('CHAIN "%s"\n' % name)
        time.sleep(wait)
        T.scene(name.lower() + '_end', palette='c64')
        escape(T)
        T.wait_prompt(20)
        T.type('MODE 100\n')
        time.sleep(1)


def fern(T):
    T.type('*DIR %sclassics\n' % DEMOS)
    T.scene('fern', palette='bbc_mode2')
    T.type('CHAIN "FERN"\n')
    time.sleep(45)
    T.scene('fern_end', palette='c64')
    escape(T)
    T.wait_prompt(20)
    T.type('MODE 100\n')


SCENES = {'schraf': schraf, 'xmas': xmas, 'classics': classics, 'fern': fern}


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
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/takes/v5',
         sys.argv[2].split(',') if len(sys.argv) > 2 else list(SCENES))
