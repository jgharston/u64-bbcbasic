"""The showcase (demos/showcase, SHOW ... SHOW10) from start to end, with
its music: videos 2 (parts of it) and 5 (all of it).

  python3 tools/video/show_record.py build/video/takes/show

No keys during the show (it is timed); the parts chain by themselves, so
the palettes per part are set in the edit from the part boundaries.
"""
import sys
import time

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from rec import Take  # noqa: E402

HOST = '192.168.1.148'
CRT = 'build/u64bbc-tmb.crt'
DEMOS = '/SD/idi8b/u64bbcbasic/demos/'


def main(out):
    T = Take(HOST, out)
    try:
        T.start()
        T.started(CRT)
        T.type('*DIR %sshowcase\n' % DEMOS)
        T.scene('show')
        T.type('CHAIN "SHOW"\n')
        # no REST reads while the show runs: a read during the Upic full
        # show (SHOW9) disturbs the viewer racing the beam (two suns in
        # the first take); the show lasts about 245 s
        time.sleep(250)
        T.wait_prompt(120)
        time.sleep(3)
        T.scene('end')
    finally:
        T.finish()


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/takes/show')
