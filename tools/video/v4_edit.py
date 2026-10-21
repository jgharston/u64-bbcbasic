"""Video 4 (files, the Ultimate, the network): the edit (docs/VIDEO_PLAN.md).

  python3 tools/video/v4_edit.py build/video/v4.mp4

Takes v4, v4b (the RAM disk) and v4c (U64TEXT) from v4_record.py; voice
build/video/v4voice (v4_narration.json).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from editlib import HERE, V, Video  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(V, 'v4.mp4')
v = Video(OUT, os.path.join(V, 'v4voice'), os.path.join(HERE, 'v4_narration.json'))
s = v.take('v4').scene
sb = v.take('v4b').scene
sc = v.take('v4c').scene

v.title('Files, the Ultimate and the network', 'Drives, the file browser, the RAM disk, the clock, HTTP and teletext', 'title')
v.u64('v4', s('files') + 0.2, s('browse') - 0.2, 1.5, '*DIR, *CAT, SAVE and LOAD on the SD card{speed}', 'files', 'Files')
v.u64('v4', s('browse') + 0.2, s('browse_copy'), 1.0, 'F1: the file browser (cursor right: into a folder, left: back)',
      'browse', 'The file browser')
v.u64('v4', s('browse_copy'), s('browse_mod'), 1.5, 'C copies GAMES, V pastes it into BACKUP; D deletes the copy (Y, Y){speed}',
      'copy')
v.u64('v4', s('browse_mod') + 0.2, s('reu') - 1.0, 1.0, 'RETURN on 4ev.mod: *MODPLAY (Forever Young, Slice 1995)',
      'mod', sound=True)
v.u64('v4b', sb('reu') + 0.2, sb('u64text') - 0.5, 1.5, '/REU: the music demo saved to the RAM disk and loaded back{speed}',
      'reu', 'The REU RAM disk')
v.u64('v4', s('mount') + 0.2, s('clock') - 0.2, 1.0, '*MOUNT our own disk image on drive A, then *STATUS',
      'mount', 'The Ultimate')
v.u64('v4', s('clock') + 0.2, s('netget') - 0.2, 1.0, '*TIME, *NET TIME (the clock from the internet), *NET', 'clock')
v.u64('v4', s('netget') + 0.2, s('u64text') - 0.5, 1.0, '*NET GET http://example.com/ to the screen', 'netget', 'The network')
t = sc('u64text')
v.u64('v4c', t + 3.0, t + 52.0, 1.5, 'U64TEXT: index, weather (Open-Meteo), the blog, a post{speed}', 'u64text', 'U64TEXT')
v.u64('v4c', t + 52.0, t + 68.0, 1.0, 'Page 500: where the ISS is now (open-notify.org), every 10 s')
v.u64('v4c', t + 68.0, t + 123.0, 6.0, 'Page 400: the news from Ars Technica, loading over plain HTTP{speed}')
v.u64('v4c', t + 123.0, t + 132.0, 1.0, 'Page 400: the news')
v.closing(['BBC BASIC 3.10: Sophie Wilson and Acorn Computers.  The C64 port: Ivo van Poorten',
           'Data: Open-Meteo, open-notify.org, Ars Technica, idreamtin8bits.com',
           'Code and demos: Xander Mol'])
v.finish()
