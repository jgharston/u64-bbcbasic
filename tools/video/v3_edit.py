"""Video 3 (sound and music): the edit (docs/VIDEO_PLAN.md).

  python3 tools/video/v3_edit.py build/video/v3.mp4

Take v3 (v3_record.py); voice build/video/v3voice (v3_narration.json).
The capture's own sound under the 1x segments (editlib: DC removed, each
segment at -20 dB RMS, turned down under the voice).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from editlib import HERE, V, Video  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(V, 'v3.mp4')
v = Video(OUT, os.path.join(V, 'v3voice'), os.path.join(HERE, 'v3_narration.json'))
T = v.take('v3')
s = T.scene

v.title('Sound and music', 'BBC sound, 24 SID voices, the song tracker, Ultimate Audio, speech', 'title')
v.u64('v3', s('bbc') + 0.2, s('bbc') + 7.5, 2.5, '*SOUND BBC: ENVELOPE and SOUND as on a BBC Micro{speed}', None, 'BBC sound')
v.u64('v3', s('bbc') + 7.5, s('sid') - 0.2, 1.0, 'A siren envelope, a falling tone, noise (channel 0)', 'bbc', sound=True)
v.u64('v3', s('sid') + 0.2, s('sid') + 12.0, 2.0, '*SOUND SID: *INSTRUMENT 1 listed, then a chord on three voices{speed}',
      'sid', 'SID sound')
v.u64('v3', s('sid') + 12.0, s('sid24') - 0.2, 1.0, 'SOUND 1, 2 and 3: a chord', sound=True)
v.u64('v3', s('sid24') + 0.5, s('music') - 1.0, 1.0, 'SID24: the 8 SIDs written directly, 24 voices', 'sid24', sound=True)
v.u64('v3', s('music') + 8.0, s('music_play'), 4.0, 'MUSIC: Canon in D built from SOUND under *SONG RECORD{speed}',
      'build', 'The music demo')
v.u64('v3', s('music_play'), s('music_play') + 50.0, 1.0,
      'Canon in D (Pachelbel) on 24 voices of 8 SIDs, played by *SONG PLAY', 'play', sound=True)
v.u64('v3', s('audio') + 9.0, s('audio_fx'), 1.0, 'Ultimate Audio: Forever Young by Slice (1995), a ProTracker MOD',
      'audio', 'Ultimate Audio', sound=True)
v.u64('v3', s('audio_fx'), s('audio_mod2'), 1.0,
      'Sample effects by Juhani Junkala (CC0), on channels 4-6 over the MOD', 'fx', sound=True)
v.u64('v3', s('audio_mod2') + 0.5, s('audio_end') - 0.5, 1.0, 'Wild Perspective by Greg Tuby (1996)', sound=True)
v.u64('v3', s('sam') + 0.2, s('sam') + 10.0, 2.0, '*SPEECH LOAD: your own S.A.M. (not included){speed}', None, 'Speech')
v.u64('v3', s('sam') + 10.0, s('end') - 0.3, 1.0,
      '*SAY: S.A.M. (1982, Don\'t Ask Software) is not included: it needs your own copy', 'sam', sound=True)

v.closing(['BBC BASIC 3.10: Sophie Wilson and Acorn Computers.  The C64 port: Ivo van Poorten',
           'MOD player: a port of ModPlayer_16k by Freshness.  MODs: Slice, Greg Tuby',
           'Effects: Juhani Junkala (CC0).  Music arrangements and code: Xander Mol'])
v.finish()
