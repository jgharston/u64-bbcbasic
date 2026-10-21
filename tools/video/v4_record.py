"""Video 4 (files, the Ultimate, the network): the takes on the U64
(docs/VIDEO_PLAN.md).

  python3 tools/video/v4_record.py build/video/takes/v4 [scene,...]

All file work in a sandbox prepared over FTP (SD/idi8b/u64bbcbasic/video/
files: GAMES/ with two programs, MUSIC/ with a MOD, BACKUP/, U64BBC.D64);
the files a take makes are deleted afterwards and drive A gets back the
image it had.
  files    *DIR, *CAT, SAVE, LOAD on the SD card
  browse   F1: the file browser: folders, copy a folder (C, V), delete it
           (D, Y, Y), RETURN on a MOD plays it
  reu      /REU: the music demo saved to the RAM disk and loaded back
  mount    *MOUNT our disk image, *STATUS
  clock    *TIME, *NET TIME, *NET
  netget   *NET GET http://example.com/ to the screen
  u64text  U64TEXT: index, weather, blog, a post, news, the ISS map
"""
import json
import sys
import time

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from rec import Take  # noqa: E402

HOST = '192.168.1.148'
CRT = 'build/u64bbc-tmb.crt'
BASE = '/SD/idi8b/u64bbcbasic'
FILES = BASE + '/video/files'
DOWN = 'cursor_up_down'
UP = ['left_shift', 'cursor_up_down']
RIGHT = 'cursor_left_right'
LEFT = ['left_shift', 'cursor_left_right']


def files(T):
    T.scene('files')
    T.type('*DIR %s\n' % FILES)
    T.type('*CAT\n')
    time.sleep(3)
    T.type('NEW\n')
    T.type('10 PRINT "HELLO FROM THE SD CARD"\n')
    T.type('SAVE "HELLO"\n')
    time.sleep(1)
    T.type('NEW\n')
    T.type('LOAD "HELLO"\n')
    time.sleep(1)
    T.type('RUN\n')
    time.sleep(1)
    T.type('*CAT\n')
    time.sleep(4)


def listing(T):
    return [r.strip() for r in T.screen()[2:22]]


def select(T, name):
    """The browser's bar onto name (from the top of the list)."""
    rows = listing(T)
    i = [r.lower() for r in rows].index(name.lower())
    T.tap([UP] * 20 + [DOWN] * i)
    time.sleep(1)


def wait_screen(T, check, what, timeout=30):
    t = time.monotonic()
    while time.monotonic() - t < timeout:
        try:
            rows = T.screen()
            if check(rows):
                T.ev('seen', text=what)
                return rows
        except Exception as e:
            print('screen:', e, flush=True)
        time.sleep(1)
    raise RuntimeError('timeout: ' + what)


def browse(T):
    T.scene('browse')
    T.type('CLS\n')
    T.tap(['f1'], 'F1: the browser')
    wait_screen(T, lambda r: 'GAMES/' in [x.strip() for x in r[2:22]], 'browser')
    time.sleep(2)
    T.scene('browse_into')
    select(T, 'GAMES/')
    T.tap([RIGHT], 'into GAMES')
    time.sleep(3)
    T.tap([LEFT], 'back')
    time.sleep(2)
    T.scene('browse_copy')
    select(T, 'GAMES/')
    T.tap(['c'], 'C: copy')
    time.sleep(2)
    select(T, 'BACKUP/')
    T.tap([RIGHT], 'into BACKUP')
    time.sleep(2)
    T.tap(['v'], 'V: paste')
    wait_screen(T, lambda r: 'GAMES/' in [x.strip() for x in r[2:22]], 'pasted')
    time.sleep(2)
    select(T, 'GAMES/')
    T.tap([RIGHT], 'into the copy')
    time.sleep(3)
    T.tap([LEFT], 'back')
    time.sleep(2)
    T.scene('browse_delete')
    wait_screen(T, lambda r: r[1].strip().endswith('BACKUP/'), 'in BACKUP')
    select(T, 'GAMES/')
    T.tap(['d'], 'D: delete')
    time.sleep(2)
    T.tap(['y'], 'Y')
    time.sleep(2)
    T.tap(['y'], 'Y: and all in it')
    wait_screen(T, lambda r: 'GAMES/' not in [x.strip() for x in r[2:22]], 'deleted')
    time.sleep(2)
    T.tap([LEFT], 'back')
    wait_screen(T, lambda r: r[1].strip().endswith('files/'), 'in files')
    time.sleep(1)
    T.scene('browse_mod')
    select(T, 'MUSIC/')
    T.tap([RIGHT], 'into MUSIC')
    time.sleep(2)
    select(T, '4ev.mod')
    T.tap(['return'], 'RETURN: play the MOD')
    time.sleep(14)
    if T.rm.state()['state'] != 'prompt':
        T.tap(['q'], 'quit the browser')
        time.sleep(1)
    T.type('*MODSTOP\n')
    time.sleep(1)


def reu(T):
    """The music demo saved to /REU and loaded back (no timing on one
    line: in immediate mode BBC BASIC 3.10 refuses SAVE after a colon)."""
    T.scene('reu')
    T.type('CLS\n')
    T.type('LOAD "%s/demos/music/MUSIC"\n' % BASE)
    time.sleep(2)
    T.type('*DIR /REU\n')
    T.type('SAVE "MUSIC"\n')
    time.sleep(1)
    T.type('*CAT\n')
    time.sleep(3)
    T.type('NEW\n')
    T.type('LOAD "MUSIC"\n')
    time.sleep(1)
    T.type('LIST 10,60\n')
    time.sleep(5)


def mount(T):
    T.scene('mount')
    T.type('CLS\n')
    T.type('*MOUNT %s/U64BBC.D64\n' % FILES)
    time.sleep(2)
    T.type('*STATUS\n')
    time.sleep(7)


def clock(T):
    T.scene('clock')
    T.type('CLS\n')
    T.type('*TIME\n')
    time.sleep(1)
    T.type('*NET TIME\n')
    time.sleep(4)
    T.type('*TIME\n')
    time.sleep(1)
    T.type('*NET\n')
    time.sleep(4)


def netget(T):
    T.scene('netget')
    T.type('CLS\n')
    T.type('*NET GET http://example.com/\n')
    time.sleep(10)


def u64text(T):
    T.scene('u64text', palette='teletext')
    T.type('MODE 100\n')
    T.type('*DIR %s/demos/net\n' % BASE)
    T.type('CHAIN "U64TEXT"\n')
    time.sleep(12)
    for page, wait in (('200', 9), ('300', 8), ('301', 16), ('500', 20), ('400', 60)):
        T.type(page, 'page ' + page)
        time.sleep(wait)
    T.rm.stop()
    T.ev('escape')
    T.wait_prompt(20)
    T.scene('u64text_end', palette='c64')
    T.type('MODE 100\n')
    time.sleep(1)


SCENES = {'files': files, 'browse': browse, 'reu': reu, 'mount': mount, 'clock': clock,
          'netget': netget, 'u64text': u64text}


def main(out, names):
    T = Take(HOST, out)
    drives = json.loads(T.rest('GET', '/v1/drives'))
    try:
        T.start()
        T.started(CRT)
        for n in names:
            SCENES[n](T)
        T.scene('end')
    finally:
        T.finish()
        if T.rm.state()['state'] != 'prompt':
            T.tap(['q'])            # a browser left open
            time.sleep(2)
        # the take's files away again, drive A as it was
        for line in ('*DIR %s' % FILES, '*DELETE HELLO', '*DIR /REU', '*DELETE MUSIC',
                     '*DIR %s/video' % BASE):
            try:
                T.rm.run_lines([line], timeout=20)
            except Exception as e:
                print('cleanup:', line, e, flush=True)
        a = [d['a'] for d in drives['drives'] if 'a' in d][0]
        try:
            if a.get('image_path'):
                T.rest('PUT', '/v1/drives/a:mount?image=%s%s' % (a['image_path'], a['image_file']))
            else:
                T.rest('PUT', '/v1/drives/a:remove')
        except Exception as e:
            print('drive A:', e, flush=True)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/takes/v4',
         sys.argv[2].split(',') if len(sys.argv) > 2 else list(SCENES))
