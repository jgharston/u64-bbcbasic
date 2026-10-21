"""Video 1 (introduction): the live scenes on the U64 (docs/VIDEO_PLAN.md).

  python3 tools/video/v1_record.py build/video/takes/v1

Scenes (the event log names them for the edit):
  startup     the cartridge starts: the banner
  type_rings  the rings program typed (the same as the BBC Micro screen
              of scene 4); shown faster in the edit
  run_rings   RUN: MODE 1 (Upic Lite: palette in post, BBC colour of
              index AND 3), circles until a key
  speed       a million empty FOR loops, timed
  editor      the line editor: history (cursor up), copy editing
              (CTRL+cursor, F1)
  help        *HELP PRINT, *HELP KEYWORDS
"""
import sys
import time

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from rec import Take  # noqa: E402

HOST = '192.168.1.148'
CRT = 'build/u64bbc-tmb.crt'
UP = ['left_shift', 'cursor_up_down']
DOWN = 'cursor_up_down'
LEFT = ['left_shift', 'cursor_left_right']
COPY_UP = ['ctrl', 'left_shift', 'cursor_up_down']
COPY_RIGHT = ['ctrl', 'cursor_left_right']

RINGS = '''10 MODE 1
20 PROCrings(640,512)
30 REPEAT UNTIL GET
40 END
50 DEF PROCrings(X%,Y%)
60   LOCAL R%
70   FOR R%=40 TO 400 STEP 40
80     GCOL 0,R% DIV 40 MOD 3+1
90     PROCcircle(X%,Y%,R%)
100   NEXT
110 ENDPROC
120 DEF PROCcircle(X%,Y%,R%)
130   LOCAL A
140   MOVE X%+R%,Y%
150   FOR A=0 TO 2*PI+0.1 STEP PI/16
160     DRAW X%+R%*COS A,Y%+R%*SIN A
170   NEXT
180 ENDPROC
'''


def main(out):
    T = Take(HOST, out)
    try:
        T.start()
        T.scene('startup')
        T.started(CRT)
        time.sleep(2)

        T.scene('type_rings')
        T.type('NEW\n', 'NEW')
        T.type(RINGS, 'rings program')
        time.sleep(1.5)

        T.scene('run_rings', mode=1, palette='bbc_mode1')
        T.type('RUN\n')
        time.sleep(9)
        T.tap(['space'], 'end the program')
        T.wait_prompt(20)
        T.scene('back_to_text', mode=100, palette='c64')
        T.type('MODE 100\n')
        time.sleep(2)

        T.scene('speed')
        T.type('T%=TIME:FOR I%=1 TO 1000000:NEXT:PRINT (TIME-T%)/100;" s"\n',
               'a million FOR loops')
        T.wait_prompt(60)
        time.sleep(3)

        T.scene('editor')
        T.type('PRINT "BBC STYLE LINE EDITING"\n')
        time.sleep(2)
        T.tap([UP], 'history: the line back')
        time.sleep(1.5)
        T.tap([LEFT] * 8, 'cursor before EDITING')
        T.type('AND HISTORY ', 'insert text')
        time.sleep(1)
        T.tap(['return'], 'RETURN')
        time.sleep(2)
        T.type('LIST 20\n')
        time.sleep(1.5)
        T.type('25 ')
        T.tap([COPY_UP], 'copy cursor up to line 20')
        time.sleep(1)
        T.tap([COPY_RIGHT] * 2, 'copy cursor onto PROCrings')
        time.sleep(0.5)
        T.tap(['f1'] * 18, 'F1 copies PROCrings(640,512)')
        time.sleep(1.5)
        T.tap(['return'], 'RETURN')
        time.sleep(1)
        T.type('LIST 20,25\n')
        time.sleep(3)

        T.scene('help')
        T.type('CLS\n')
        T.type('*HELP PRINT\n')
        time.sleep(6)
        T.type('CLS\n')
        T.type('*HELP KEYWORDS\n')
        time.sleep(5)
        T.tap(['run_stop'], 'ESCAPE')
        time.sleep(2)
        T.scene('end')
    finally:
        T.finish()


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/takes/v1')
