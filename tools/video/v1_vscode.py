"""Video 1: the VS Code take (docs/VIDEO_PLAN.md, decision 4).

  python3 tools/video/v1_vscode.py build/video/takes/v1vsc

Starts the Linux VS Code of the extension's tests (vscode/.vscode-test)
with a clean video profile (no welcome dialog, 1920x1080, larger font,
no pop-up suggestions), the extension under development and the driver
extension tools/video/vscode-driver, which plays the scene and quits. At the
same time it records:
  vscode.mkv           the VS Code window (ffmpeg x11grab, 30 fps)
  video.pkts/audio.pkts the U64's streams (rec.py), for the picture on
                        the machine while VS Code runs and debugs
  events.json          the take's events; vscode_events.json the scene's
                        steps; times as epoch seconds (vscode_start, epoch0)
VS Code reads a piped stdin into its editor: it gets /dev/null.
"""
import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rec import Take  # noqa: E402

HOST = '192.168.1.148'
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXT = os.path.join(ROOT, 'vscode')
CODE = os.path.join(EXT, '.vscode-test', 'vscode-linux-x64-1.140.0', 'code')
DRIVER = os.path.join(ROOT, 'tools', 'video', 'vscode-driver')

SETTINGS = {
    'workbench.startupEditor': 'none',
    'chat.disableAIFeatures': True,
    'workbench.welcomePage.walkthroughs.openOnInstall': False,
    'workbench.tips.enabled': False,
    'update.mode': 'none',
    'telemetry.telemetryLevel': 'off',
    'extensions.ignoreRecommendations': True,
    'workbench.colorTheme': 'Default Dark Modern',
    'editor.fontSize': 20,
    'editor.minimap.enabled': False,
    'editor.autoClosingBrackets': 'never',
    'editor.autoClosingQuotes': 'never',
    'editor.quickSuggestions': {'other': False, 'comments': False, 'strings': False},
    'editor.suggestOnTriggerCharacters': False,
    'editor.wordBasedSuggestions': 'off',
    'editor.hover.delay': 100000,
    'window.restoreWindows': 'none',
    'security.workspace.trust.enabled': False,
    'files.autoSave': 'off',
    'breadcrumbs.enabled': False,
    'u64bbc.host': HOST,
    'u64bbc.promptForInput': False,
}

SQUARES = '''10 FOR N=1 TO 5
20   SQ=N*N
30   PRINT N;" squared is ";SQ
40 NEXT
50 END
'''

def window_id(timeout=90):
    """The VS Code window once it shows the workspace and its size has
    been steady for 2 s (it opens small and then resizes; x11grab fails
    on a window that changes size)."""
    t = time.monotonic()
    last, since = None, time.monotonic()
    while time.monotonic() - t < timeout:
        out = subprocess.run(['xwininfo', '-root', '-tree'], capture_output=True, text=True).stdout
        line = next((l.strip() for l in out.splitlines()
                     if 'Visual Studio Code' in l and 'U64 BBC BASIC' in l), None)
        if line != last:
            last, since = line, time.monotonic()
        elif line and time.monotonic() - since > 2.0:
            print('window:', line, flush=True)
            return line.split()[0]
        time.sleep(0.5)
    raise RuntimeError('no VS Code window')


def main(out):
    out = os.path.abspath(out)
    os.makedirs(out, exist_ok=True)
    work = os.path.join(out, 'work')
    shutil.rmtree(work, ignore_errors=True)
    ws, ud = os.path.join(work, 'U64 BBC BASIC'), os.path.join(work, 'profile')
    os.makedirs(ws)
    os.makedirs(os.path.join(ud, 'User', 'globalStorage'))
    open(os.path.join(ws, 'rings.bas'), 'w').close()
    open(os.path.join(ws, 'squares.bas'), 'w').write(SQUARES)
    json.dump(SETTINGS, open(os.path.join(ud, 'User', 'settings.json'), 'w'), indent=1)
    # an extension development window takes its size from its own entry
    ui = {'uiState': {'mode': 1, 'x': 0, 'y': 0, 'width': 1920, 'height': 1080}}
    json.dump({'windowsState': {'lastActiveWindow': ui, 'lastPluginDevelopmentHostWindow': ui}},
        open(os.path.join(ud, 'User', 'globalStorage', 'storage.json'), 'w'))
    env = dict(os.environ, U64_VIDEO_EVENTS=os.path.join(out, 'vscode_events.json'), U64_HOST=HOST)

    T = Take(HOST, out)
    T.ev('epoch0', epoch=time.time() - (time.monotonic() - T.t0))
    grab = None
    try:
        T.start()
        T.scene('vscode')
        code = subprocess.Popen([CODE, '--extensionDevelopmentPath=' + EXT,
                                 '--extensionDevelopmentPath=' + DRIVER, '--user-data-dir=' + ud,
                                 '--extensions-dir=' + os.path.join(work, 'ext'), '--disable-gpu',
                                 '--new-window', '--wait', ws],
                                env=env, stdin=subprocess.DEVNULL,
                                stdout=open(os.path.join(work, 'code.log'), 'w'),
                                stderr=subprocess.STDOUT)
        wid = window_id()
        grab = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'x11grab', '-window_id', wid,
                                 '-framerate', '30', '-draw_mouse', '0', '-i', os.environ.get('DISPLAY', ':0'),
                                 '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '16',
                                 '-pix_fmt', 'yuv444p', os.path.join(out, 'vscode.mkv')],
                                stdin=subprocess.PIPE)
        T.ev('vscode_grab', epoch=time.time())
        rc = code.wait(timeout=600)
        T.ev('vscode_exit', rc=rc)
    finally:
        if grab:
            grab.communicate(b'q', timeout=30)
        T.finish()


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'build/video/takes/v1vsc')
