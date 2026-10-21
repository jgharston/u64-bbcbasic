"""Recording helpers for the U64 BBC BASIC videos (docs/VIDEO_PLAN.md).

Captures the Ultimate's VIC video stream and its audio stream at the same
time, as raw UDP packets with their receive times, while a scripted take
types on the real keyboard matrix (POST /v1/machine:input: no DMA, so no
disturbed lines). Screen checks read memory over REST, which stalls the
CPU for a moment: at most once a second, and the edit repairs those
frames. Every scene, key press and mode change goes to an event log, so
the edit knows when to switch palettes (the stream has none).

Adapted from the UBoot64 v4 and Mandelbrot Upic video scripts
(~/.claude/tools/youtube-video/, video workflow of 2026-10-03); the audio
stream format was measured for this project (2026-10-21).

Files written to OUT: video.pkts and audio.pkts (each packet: <d receive
time since the take started, H length> then the data), events.json.
"""
import json
import os
import socket
import struct
import sys
import threading
import time
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from u64remote import Remote  # noqa: E402

VIDEO = ('239.0.1.64', 11000)
AUDIO = ('239.0.1.65', 11001)

# characters -> keyboard matrix keys (BBC CAPS LOCK on: capitals plain,
# lower case with SHIFT; the C64's shifted digits give the symbols)
SHIFTED = {'!': '1', '"': '2', '#': '3', '$': '4', '%': '5', '&': '6',
           "'": '7', '(': '8', ')': '9', '<': 'comma', '>': 'period',
           '?': 'slash', '[': 'colon', ']': 'semicolon'}
PLAIN = {' ': 'space', '+': 'plus', '-': 'minus', '*': 'star', '/': 'slash',
         '=': 'equals', ':': 'colon', ';': 'semicolon', ',': 'comma',
         '.': 'period', '@': 'at', '^': 'arrow_up', '_': 'arrow_left',
         '\\': 'pound', '\n': 'return', '\r': 'return'}


def keys_for(text):
    """Text -> a list of key taps (a list is a chord)."""
    out = []
    for c in text:
        if c in PLAIN:
            out.append(PLAIN[c])
        elif c in SHIFTED:
            out.append(['left_shift', SHIFTED[c]])
        elif c.isdigit():
            out.append(c)
        elif c.isalpha() and c.isupper():
            out.append(c.lower())
        elif c.isalpha():
            out.append(['left_shift', c])
        else:
            raise ValueError('no key for %r' % c)
    return out


class Take:
    def __init__(self, host, out):
        self.host = host
        self.out = out
        os.makedirs(out, exist_ok=True)
        self.rm = Remote(host)
        self.t0 = time.monotonic()
        self.events = []
        self.stop = False
        self.threads = []
        self.src = socket.gethostbyname(host)

    # --- events ---------------------------------------------------------
    def now(self):
        return round(time.monotonic() - self.t0, 3)

    def ev(self, kind, **kw):
        e = dict(t=self.now(), kind=kind, **kw)
        self.events.append(e)
        print(e, flush=True)

    def scene(self, name, **kw):
        self.ev('scene', name=name, **kw)

    # --- REST -----------------------------------------------------------
    def rest(self, method, path, body=None, ctype=None):
        req = urllib.request.Request('http://%s%s' % (self.host, path), data=body,
                                     method=method)
        if ctype:
            req.add_header('Content-Type', ctype)
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=15) as r:
                    return r.read()
            except Exception as e:
                if attempt == 2:
                    raise
                print('REST retry:', e, flush=True)
                time.sleep(2)

    def tap(self, keys, what=''):
        """Taps on the keyboard matrix (about 10 a second). A request may
        hold at most about 4 KB of JSON ("JSON body is too large",
        measured): sent in pieces of under 3.5 KB, each after the one
        before has been typed."""
        events = [{'kind': 'keyboard', 'inputs': k if isinstance(k, list) else [k],
                   'transition': 'tap'} for k in keys]
        i = 0
        while i < len(events):
            j = i + 1
            while j < len(events) and len(json.dumps({'events': events[i:j + 1]})) < 3500:
                j += 1
            self.rest('POST', '/v1/machine:input', json.dumps({'events': events[i:j]}).encode(),
                      'application/json')
            time.sleep((j - i) * 0.1 + 0.05)
            i = j
        if what:
            self.ev('keys', what=what, n=len(keys))

    def type(self, text, what=None):
        self.tap(keys_for(text), what or text.strip()[:40])

    def run_crt(self, path):
        """Start the cartridge. RAM survives the reset: the old screen and
        mailbox are wiped first, so the banner and the prompt are not seen
        before the new start (as the E2E suite does)."""
        self.rm.write(0xC000, b'\x20' * 1000)
        self.rm.write(0xC6E0, bytes(8))
        self.rest('POST', '/v1/runners:run_crt', open(path, 'rb').read(),
                  'application/octet-stream')
        self.ev('run_crt', crt=os.path.basename(path))

    def started(self, path, settle=4.0):
        """run_crt, the banner, BASIC waiting at its prompt, then a pause:
        keys typed while the MOS still sets up (SIDs, network) get lost."""
        self.run_crt(path)
        self.wait_text('U64 BBC BASIC', 40)
        self.wait_prompt(40)
        time.sleep(settle)

    # --- screen checks (DMA: at most once a second) ---------------------
    def screen(self):
        return self.rm.screen()

    def wait_text(self, text, timeout=60):
        t = time.monotonic()
        while time.monotonic() - t < timeout:
            try:
                if any(text in row for row in self.screen()):
                    self.ev('seen', text=text)
                    return True
            except Exception as e:
                print('screen:', e, flush=True)
            time.sleep(1.0)
        self.ev('timeout', text=text)
        raise RuntimeError('timeout waiting for %r' % text)

    def wait_prompt(self, timeout=60):
        """BASIC back at its prompt (the mailbox state, read once a second)."""
        t = time.monotonic()
        while time.monotonic() - t < timeout:
            try:
                if self.rm.state()['state'] == 'prompt':
                    self.ev('prompt')
                    return True
            except Exception as e:
                print('state:', e, flush=True)
            time.sleep(1.0)
        self.ev('timeout', text='prompt')
        raise RuntimeError('timeout waiting for the prompt')

    # --- streams --------------------------------------------------------
    def _sock(self, group, port):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect((self.host, 80))
            local = s.getsockname()[0]
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
        s.bind(('', port))
        s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                     socket.inet_aton(group) + socket.inet_aton(local))
        s.settimeout(0.5)
        return s

    def _capture(self, kind, group, port):
        s = self._sock(group, port)
        f = open(os.path.join(self.out, kind + '.pkts'), 'wb')
        last = time.monotonic()
        while not self.stop:
            try:
                data, addr = s.recvfrom(2048)
            except OSError:
                # the stream stops when a cartridge starts: start it again
                if time.monotonic() - last > 1.0:
                    try:
                        self.rest('PUT', '/v1/streams/%s:start?ip=%s:%d' % (kind, group, port))
                        self.events.append(dict(t=self.now(), kind='stream_restart', stream=kind))
                    except Exception as e:
                        print('restart %s stream:' % kind, e, flush=True)
                    last = time.monotonic()
                continue
            if addr[0] != self.src:
                continue
            last = time.monotonic()
            f.write(struct.pack('<dH', time.monotonic() - self.t0, len(data)) + data)
        f.close()
        s.close()

    def start(self):
        for kind, (group, port) in (('video', VIDEO), ('audio', AUDIO)):
            th = threading.Thread(target=self._capture, args=(kind, group, port), daemon=True)
            th.start()
            self.threads.append(th)
            self.rest('PUT', '/v1/streams/%s:start?ip=%s:%d' % (kind, group, port))
        self.ev('capture_start')
        time.sleep(1.0)

    def finish(self):
        self.ev('capture_end')
        self.stop = True
        for kind in ('audio', 'video'):
            try:
                self.rest('PUT', '/v1/streams/%s:stop' % kind)
            except Exception as e:
                print('stop %s stream:' % kind, e, flush=True)
        for th in self.threads:
            th.join(3)
        json.dump(self.events, open(os.path.join(self.out, 'events.json'), 'w'), indent=1)
