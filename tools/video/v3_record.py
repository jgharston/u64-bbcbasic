"""Video 3 (sound and music): the takes on the U64 (docs/VIDEO_PLAN.md).

  python3 tools/video/v3_record.py build/video/takes/v3 [scene,...]

  bbc     *SOUND BBC: an ENVELOPE siren, a falling tone, a noise burst
  sid     *SOUND SID: *INSTRUMENT listed, a three-voice chord, then SID24
  music   MUSIC: Canon in D (piece 5) built from SOUND, then played on
          24 voices with the bars
  audio   AUDIO (MODE 7): the MOD Forever Young, the sample effects A-H,
          then Wild Perspective
  sam     *SPEECH LOAD of the owner's S.A.M. (not distributed), *SAY
"""
import sys
import time

sys.path.insert(0, __file__.rsplit('/', 1)[0])
from rec import Take  # noqa: E402

HOST = '192.168.1.148'
CRT = 'build/u64bbc-tmb.crt'
DEMOS = '/SD/idi8b/u64bbcbasic/demos/'
SAM = '/SD/idi8b/u64bbcbasic/sam'


def bbc(T):
    T.scene('bbc')
    T.type('*SOUND BBC\n')
    time.sleep(1)
    T.type('ENVELOPE 1,2,1,-1,1,10,20,10,126,0,0,-126,126,0\n', 'siren envelope')
    T.type('SOUND 1,1,100,60\n', 'the siren')
    time.sleep(4)
    T.type('ENVELOPE 2,1,-2,0,0,60,0,0,126,-1,0,-1,126,0\n', 'falling envelope')
    T.type('SOUND 1,2,200,40\n', 'the falling tone')
    time.sleep(3)
    T.type('SOUND 0,-15,6,30\n', 'noise')
    time.sleep(3)


def sid(T):
    T.scene('sid')
    T.type('CLS\n')
    T.type('*SOUND SID\n')
    time.sleep(1)
    T.type('*INSTRUMENT 1\n', 'an instrument listed')
    time.sleep(3)
    T.type('SOUND 1,-15,101,40:SOUND 2,-15,117,40:SOUND 3,-15,129,40\n', 'a chord')
    time.sleep(4)
    T.scene('sid24')
    T.type('*DIR %ssound\n' % DEMOS)
    T.type('CHAIN "SID24"\n')
    time.sleep(10)
    T.wait_prompt(120)
    time.sleep(1)


def music(T):
    T.scene('music')
    T.type('*DIR %smusic\n' % DEMOS)
    T.type('CHAIN "MUSIC"\n')
    time.sleep(8)
    T.tap(['5'], 'piece 5: Canon in D')
    T.wait_text('Playing', 300)
    T.scene('music_play')
    time.sleep(75)
    T.tap(['space'], 'stop the piece')
    time.sleep(3)
    T.tap(['q'], 'quit')
    T.wait_prompt(20)


def audio(T):
    T.scene('audio', palette='teletext')
    T.type('*DIR %saudio\n' % DEMOS)
    T.type('CHAIN "AUDIO"\n')
    time.sleep(12)
    T.tap(['1'], 'MOD: Forever Young')
    time.sleep(14)
    T.scene('audio_fx')
    for k in 'abcdefg':
        T.tap([k], 'effect ' + k)
        time.sleep(1.6)
    T.tap(['h'], 'alarm on')
    time.sleep(3)
    T.tap(['h'], 'alarm off')
    time.sleep(1)
    T.scene('audio_mod2')
    T.tap(['2'], 'MOD: Wild Perspective')
    time.sleep(16)
    T.tap(['0'], 'stop')
    time.sleep(1)
    T.scene('audio_end', palette='c64')
    T.tap(['q'], 'quit')
    T.wait_prompt(20)
    T.type('MODE 100\n')
    time.sleep(1)


def sam(T):
    T.scene('sam')
    T.type('*DIR %s\n' % SAM)
    T.type('*SPEECH LOAD sam1.prg sam2.prg\n')
    time.sleep(8)
    T.type('*SAY Hello. I am U sixty four BBC BASIC.\n', 'say')
    time.sleep(6)
    T.type('*SAY I speak with your own copy of SAM.\n', 'say')
    time.sleep(6)


SCENES = {'bbc': bbc, 'sid': sid, 'music': music, 'audio': audio, 'sam': sam}


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
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/takes/v3',
         sys.argv[2].split(',') if len(sys.argv) > 2 else list(SCENES))
