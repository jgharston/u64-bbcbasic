#!/usr/bin/env python3
"""Remote control of U64 BBC BASIC through the MOS mailbox.

For people (VS Code tasks, the command line) and for AI coding agents:
every command can print one JSON object (--json) and uses fixed exit
codes, so a script or an agent can run a program, read its output and
errors, and react. Protocol: docs/REMOTE_DEV.md. Talks to the Ultimate's
REST API directly (Python 3 standard library only).

Commands:
  status                      mailbox state (prompt/running, last error)
  run PROG.bas                send the program and RUN it, return output
  load PROG.bas               send the program (LOAD), don't run
  exec "LINE" [...]           type lines at the prompt, return output
  input "TEXT"                answer an INPUT statement
  stop                        ESCAPE
  screen                      the 40x25 text screen
  list                        the program in memory as text (LIST)
  debug PROG.bas [--break N ...] [--entry]
                              run under the debugger: stops at breakpoints
  continue | step | vars      while paused: go on, one line, variables

Exit codes: 0 done (also when the program now waits for INPUT: "state"
is "input"), 1 BASIC reported an error, 2 time-out (still running), 3
cannot talk to the machine or the cartridge is not running.

Examples:
  u64remote.py --host 192.168.1.148 run demo.bas --json
  u64remote.py exec "PRINT 6*7"            (host from .env ULTIP1)
"""
import argparse
import json
import os
import re
import signal
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bbctok  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Mailbox layout (src/mos/defs.s)
MBOX = 0xC6E0
MB_MAGIC, MB_VERSION, MB_HSEQ, MB_CSEQ, MB_REQ, MB_STATUS = 0, 4, 5, 6, 7, 8
MB_LINENO, MB_DEBUG = 9, 11
MB_RINGW, MB_RINGR, MB_CAPTURE, MB_LINELEN, MB_PROG = 12, 13, 14, 15, 16
MB_BREAK = 94
REQ_DEBUG = 2
DBG_CONTINUE, DBG_STEP, DBG_STOP = 1, 2, 3
MB_PROMPT, MB_ERRNUM, MB_ERRCNT, MB_LINE, MB_RING = 17, 18, 19, 20, 110
MB_SIZE, MB_LINEMAX, RING = 238, 74, 128
REQ_LINE, REQ_CAPTURE, REQ_PROGRAM = 1, 3, 4
UP_SIG, UP_SHOWING, UP_ENDSHOW = 0x0334, 0x55, 0xAA   # Upic full show (defs.s)
PAGE, HIMEM = 0x1D00, 0x8000            # defaults; read from BASIC when needed
ESCFLG = 0x00FF
SCREEN = 0xC000

EXIT_OK, EXIT_BASIC_ERROR, EXIT_TIMEOUT, EXIT_CONNECTION = 0, 1, 2, 3


class RemoteError(Exception):
    """Cannot talk to the machine, or the cartridge is not running."""


class ShowingError(RemoteError):
    """A Upic full picture is showing: the mailbox is swapped out."""


class Remote:
    """host: an Ultimate's address (REST), or mem: any object with
    read(address, length) -> bytes and write(address, data), such as the
    E2E suite's c64bridge client (also works with VICE)."""

    def __init__(self, host=None, password=None, timeout=10.0, mem=None):
        self.host = host
        self.password = password
        self.timeout = timeout
        self.mem = mem

    # --- REST -------------------------------------------------------------

    def _request(self, method, path, params=None, body=None):
        url = "http://%s%s" % (self.host, path)
        if params:
            url += "?" + urllib.parse.urlencode(params)
        for attempt in range(6):
            req = urllib.request.Request(url, data=body, method=method)
            if body is not None:
                req.add_header("Content-Type", "application/octet-stream")
            if self.password:
                req.add_header("X-Password", self.password)
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as r:
                    return r.read()
            except urllib.error.HTTPError as e:
                # the firmware refuses DMA while a UCI transfer runs: retry
                if attempt == 5:
                    raise RemoteError("%s %s: HTTP %d" % (method, path, e.code)) from None
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                if attempt == 5:
                    raise RemoteError("%s: %s" % (self.host, e)) from None
            time.sleep(0.2)

    def read(self, address, length):
        if self.mem:
            return bytes(self.mem.read(address, length))
        data = self._request("GET", "/v1/machine:readmem",
                             {"address": "%04X" % address, "length": length})
        if len(data) < length:
            raise RemoteError("short memory read at $%04X" % address)
        return data[:length]

    def write(self, address, data):
        if self.mem:
            return self.mem.write(address, bytes(data))
        self._request("POST", "/v1/machine:writemem",
                      {"address": "%04X" % address}, bytes(data))

    # --- mailbox ------------------------------------------------------------

    def mailbox(self, full=False):
        """The mailbox: its 20-byte header only, unless full. Each REST read
        is a DMA that stops the C64's CPU while it runs; long reads during
        serial-bus transfers (*STATUS, *CP) break their timing (measured:
        *CP 0.4 s -> 11 s and more), so polls stay short."""
        for attempt in range(3):
            mb = self.read(MBOX, MB_SIZE if full else MB_LINE)
            if mb[:4] == b"BBCR":
                return mb
            if self.read(UP_SIG, 1)[0] == UP_SHOWING:
                raise ShowingError("a Upic picture is showing (endshow "
                                   "or stop ends it)")
            time.sleep(0.05)                # (a show may just have ended:
        if mb[:4] != b"BBCR":               # the signal goes after the RAM)
            raise RemoteError("U64 BBC BASIC is not running on %s "
                              "(no mailbox at $%04X)" % (self.host, MBOX))
        return mb

    def state(self, mb=None):
        if mb is None:
            try:
                mb = self.mailbox()
            except ShowingError:
                return {"state": "showing", "line": 0, "debug": False,
                        "error_count": 0, "last_error": 0, "capture": False,
                        "protocol": 0}
        status = mb[MB_STATUS]
        waiting = status == 1
        return {
            "state": ("prompt" if mb[MB_PROMPT] == 0x07 else "input")
                     if waiting else {2: "running", 3: "paused"}.get(status, "idle"),
            "line": mb[MB_LINENO] | mb[MB_LINENO + 1] << 8,
            "debug": bool(mb[MB_DEBUG] & 1),
            "error_count": mb[MB_ERRCNT],
            "last_error": mb[MB_ERRNUM],
            "capture": bool(mb[MB_CAPTURE]),
            "protocol": mb[MB_VERSION],
        }

    def post(self, request, data=b"", timeout=10.0):
        """Post a request; wait until the MOS has taken it."""
        mb = self.mailbox()
        if len(data) > MB_LINEMAX:
            raise ValueError("request data longer than %d bytes" % MB_LINEMAX)
        seq = (mb[MB_HSEQ] + 1) & 0xFF
        if data:                                    # (an empty line: the
            self.write(MBOX + MB_LINE, data)        # length alone)
        self.write(MBOX + MB_LINELEN, [len(data)])
        self.write(MBOX + MB_REQ, [request])
        self.write(MBOX + MB_HSEQ, [seq])           # last: makes it valid
        deadline = time.time() + timeout
        while self.read(MBOX + MB_CSEQ, 1)[0] != seq:
            if time.time() > deadline:
                mb = self.read(MBOX, 24)
                raise TimeoutError("the MOS did not take the request "
                                   "(not waiting for a line?) mailbox: %s"
                                   % mb.hex(" "))
            time.sleep(0.05)

    def ensure_prompt(self):
        """Get BASIC to its prompt: a paused debug session is stopped, a
        running program gets ESCAPE, debug mode goes off."""
        st = self.state()
        if st["state"] == "paused":
            self.post(REQ_DEBUG, bytes([DBG_STOP]))
        elif st["state"] == "running":
            self.stop()
        self.write(MBOX + MB_DEBUG, [0])
        st = self.wait_line_wanted(10)
        if st["state"] != "prompt":
            raise RemoteError("BASIC is waiting for INPUT, not at the prompt")
        return st

    def wait_line_wanted(self, timeout):
        """Wait until BASIC waits for a line (prompt or INPUT)."""
        deadline = time.time() + timeout
        while True:
            st = self.state()
            if st["state"] in ("prompt", "input"):
                return st
            if time.time() > deadline:
                raise TimeoutError("BASIC is busy (state %s)" % st["state"])
            time.sleep(0.1)

    def capture(self, on):
        self.post(REQ_CAPTURE, bytes([1 if on else 0]))

    def capture_direct(self, on):
        """Capture on or off by writing the mailbox byte: works while a
        program runs too (the MOS takes REQ_CAPTURE only at the prompt)."""
        if on:
            self.drain()
        self.write(MBOX + MB_CAPTURE, [1 if on else 0])

    def release(self):
        """Capture off when this host stops reading: otherwise the MOS
        waits on the full ring (up to a second) before it gives up on us.
        Never raises: called on every exit."""
        try:
            self.write(MBOX + MB_CAPTURE, [0])
        except Exception:
            pass

    def drain(self, mb=None):
        """Output captured since the last call (the ring); nothing while
        a Upic picture is showing (the ring is swapped out with BASIC)."""
        if mb is None:
            try:
                mb = self.mailbox()
            except ShowingError:
                return b""
        if getattr(self, "_ring_r", None) is not None:
            # a read position written while a show began went into the
            # picture's RAM and was lost with the swap back: again
            self.write(MBOX + MB_RINGR, [self._ring_r])
            mb = bytearray(mb)
            mb[MB_RINGR] = self._ring_r
            self._ring_r = None
        w, r = mb[MB_RINGW], mb[MB_RINGR]
        if w == r:
            return b""
        if w > r:                           # only the new part of the ring
            out = self.read(MBOX + MB_RING + r, w - r)
        else:
            out = self.read(MBOX + MB_RING + r, RING - r)
            if w:
                out += self.read(MBOX + MB_RING, w)
        self.write(MBOX + MB_RINGR, [w])
        if self.read(MBOX, 4) != b"BBCR":       # a show began meanwhile
            self._ring_r = w
        return out

    # --- operations ----------------------------------------------------------

    def run_lines(self, lines, timeout=30.0, wait=True, prepared=False):
        """Type lines at the prompt (or INPUT); collect output and errors.

        Output is drained from the ring all the time, so the MOS never
        waits on a full ring. Returns a result dict (see main).
        """
        if prepared:                        # send_program: capture is on,
            st = self.state()               # the program may be running
            errors_before = self.errors_before
        else:
            st = self.wait_line_wanted(10)
            errors_before = st["error_count"]
            self.capture(True)
            self.drain()
        out = bytearray()
        start = time.time()
        deadline = time.time() + timeout
        pending = list(lines)
        state = "running"
        first_error = None              # (number, message) of the first
        err_seen = errors_before        # error, taken when it happened
        while True:
            try:
                mb = self.mailbox()
            except ShowingError:            # *UPIC SHOW: wait for its end,
                if time.time() > deadline:  # rarely: every read stops the
                    state = "timeout"       # CPU, which in Upic shows as a
                    break                   # disturbed line
                time.sleep(1.0)
                continue
            out += self.drain(mb)
            st = self.state(mb)
            if st["error_count"] != err_seen and first_error is None and \
                    st["state"] in ("prompt", "input"):
                time.sleep(0.05)
                out += self.drain()
                first_error = (st["last_error"], last_line(clean_output(out)))
            err_seen = st["error_count"]
            if st["state"] == "paused" and not pending:
                state = "paused"
                out += self.drain()
                break
            if st["state"] in ("prompt", "input"):
                if pending:
                    self.post(REQ_LINE, pending.pop(0).encode("latin-1"))
                    continue
                if not wait:
                    state = st["state"]
                    break
                time.sleep(0.05)            # last output bytes
                out += self.drain()
                state = st["state"]
                break
            if time.time() > deadline:
                state = "timeout"
                break
            time.sleep(0.03)
        st = self.state()
        text = clean_output(out)
        result = {"ok": True, "state": state, "output": text,
                  "elapsed_s": round(time.time() - start, 2), "error": None}
        if st["error_count"] != errors_before:
            number, message = first_error or (st["last_error"], last_line(text))
            m = re.search(r"^(.*) at line (\d+)$", message)
            result["ok"] = False
            result["error"] = {"number": number,
                               "message": m.group(1) if m else message,
                               "line": int(m.group(2)) if m else None}
        if state == "timeout":
            result["ok"] = False
        return result

    def page_himem(self):
        """BASIC's PAGE and HIMEM (zero page &18, &06/&07)."""
        zp = self.read(0x0000, 0x19)
        page, himem = zp[0x18] << 8, zp[0x06] | zp[0x07] << 8
        if not (0x0800 <= page < himem <= 0x8000):
            return PAGE, HIMEM
        return page, himem

    def send_program(self, text, run=False, timeout=30.0):
        image = bbctok.tokenise_program(text)
        page, himem = self.page_himem()
        if page + len(image) > himem - 1024:
            raise ValueError("program too big (%d bytes)" % len(image))
        st = self.ensure_prompt()
        errors_before = st["error_count"]
        self.capture(True)
        self.drain()
        self.write(page, image)
        self.post(REQ_PROGRAM, bytes([1 if run else 0]))
        self.errors_before = errors_before
        r = self.run_lines([], timeout=timeout, prepared=True)
        if self.state()["error_count"] != errors_before and r["error"] is None:
            r["ok"] = False
            r["error"] = {"number": self.state()["last_error"],
                          "message": last_line(r["output"]), "line": None}
        r["program_bytes"] = len(image)
        # capture off when BASIC is back at the prompt (only then does the
        # MOS take requests): nobody reads the ring any more, and a program
        # started later with RUN would wait for the host on a full ring,
        # up to a second, before the MOS gives up on it
        if r.get("state") == "prompt":
            self.capture(False)
        return r

    def stop(self):
        self.write(ESCFLG, [0x80])

    def end_show(self):
        """End a Upic full show as a key press would (*UPIC SHOW). False
        if no picture is showing."""
        if self.read(UP_SIG, 1)[0] != UP_SHOWING:
            return False
        self.write(UP_SIG, [UP_ENDSHOW])
        return True

    # --- debugger (TRACE hook, docs/REMOTE_DEV.md) ----------------------------

    def set_breakpoints(self, lines):
        """Up to 8 BASIC line numbers."""
        words = (list(lines)[:8] + [0] * 8)[:8]
        self.write(MBOX + MB_BREAK, b"".join(int(n).to_bytes(2, "little") for n in words))

    def debug_start(self, text, breakpoints=(), stop_on_entry=False, timeout=30.0):
        """Send the program, switch debug mode on, RUN with TRACE ON.
        Returns as run: state "paused" at a breakpoint, with "line"."""
        r = self.send_program(text, run=False, timeout=10)
        if r["error"]:
            return r
        self.set_breakpoints(breakpoints)
        self.write(MBOX + MB_DEBUG, [1 | (2 if stop_on_entry else 0)])
        return self.run_lines(["TRACE ON:RUN"], timeout=timeout)

    def debug_end(self):
        """Debug mode off; at the prompt also TRACE OFF (RUN keeps TRACE,
        so later runs would print "[n]" line numbers otherwise)."""
        self.write(MBOX + MB_DEBUG, [0])
        if self.state()["state"] == "prompt":
            self.run_lines(["TRACE OFF"], timeout=5)

    def debug_resume(self, how, timeout=30.0):
        """how: DBG_CONTINUE, DBG_STEP or DBG_STOP; returns as run."""
        st = self.state()
        if st["state"] != "paused":
            raise RemoteError("not paused (state %s)" % st["state"])
        errors_before = st["error_count"]
        self.capture_direct(True)           # (released after the last call)
        self.post(REQ_DEBUG, bytes([how]))
        self.errors_before = errors_before
        r = self.run_lines([], timeout=timeout, prepared=True)
        if r["state"] == "paused":
            r["line"] = self.state()["line"]
        return r

    def variables(self):
        """BASIC's variables, decoded from memory: resident integers that
        are not 0, and every dynamic variable (arrays listed by name)."""
        ws = self.read(0x0400, 0x100)
        out = {}
        for i, name in enumerate("@ABCDEFGHIJKLMNOPQRSTUVWXYZ"):
            v = int.from_bytes(ws[i * 4:i * 4 + 4], "little", signed=True)
            if v or name == "@":
                out[name + "%"] = v
        zp = self.read(0x0000, 0x52)
        lomem = zp[0x50] | zp[0x51] << 8
        fsa = zp[0x02] | zp[0x03] << 8
        if not (0x0800 <= lomem <= fsa <= 0x8000):
            return out
        heap = self.read(lomem, max(1, fsa - lomem)) if fsa > lomem else b""

        def rd(addr, n):
            if lomem <= addr and addr + n <= fsa:
                return heap[addr - lomem:addr - lomem + n]
            return self.read(addr, n)

        for c in range(0x40, 0x80):
            if c in (0x7B, 0x7C):           # PROC and FN lists
                continue
            ptr = ws[(2 * c) & 0xFF] | ws[((2 * c) & 0xFF) + 1] << 8
            seen = 0
            while ptr >> 8 and seen < 500:      # BASIC ends a list on a zero
                                                # high byte (low byte is junk)
                seen += 1
                rec = rd(ptr, 48)
                link = rec[0] | rec[1] << 8
                j = 2
                while j < len(rec) and rec[j] != 0:
                    j += 1
                name = chr(c) + rec[2:j].decode("latin-1")
                value_at = ptr + j + 1
                if name.endswith("("):
                    out[name + ")"] = "array"
                elif name.endswith("%"):
                    out[name] = int.from_bytes(rd(value_at, 4), "little", signed=True)
                elif name.endswith("$"):
                    a, l = rd(value_at, 4)[0:2], rd(value_at, 4)[3]
                    addr = a[0] | a[1] << 8
                    out[name] = rd(addr, l).decode("latin-1") if l else ""
                else:
                    out[name] = bbc_float(rd(value_at, 5))
                ptr = link
        return out

    def screen(self):
        sys.path.insert(0, os.path.join(ROOT, "tests", "e2e"))
        import screen as scr  # noqa: E402
        return scr.decode_screen(self.read(SCREEN, 1000))

    def program_text(self):
        """The program in memory, detokenised on the host."""
        page = self.page_himem()[0]
        image = b"".join(self.read(page + i, 0x1000) for i in range(0, 0x4000, 0x1000))
        end = image.find(b"\r\xff")
        if image[0] != 0x0D or end < 0:
            raise RemoteError("no program at PAGE")
        return bbctok.detokenise(image[:end + 2])


def bbc_float(b):
    """BBC BASIC 5-byte real: exponent (excess 128), then 4 mantissa bytes
    most significant first, the sign in the top bit (implied 1)."""
    exp = b[0]
    if exp == 0:
        return 0.0
    mant = int.from_bytes(b[1:5], "big")
    sign = -1 if mant & 0x80000000 else 1
    mant |= 0x80000000
    value = sign * mant / 2.0 ** 32 * 2.0 ** (exp - 128)
    return int(value) if value == int(value) and abs(value) < 1e9 else round(value, 9)


def clean_output(raw):
    """Captured VDU bytes -> text: CR LF -> newline, VDU sequences dropped."""
    out, i = [], 0
    params = [0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 1, 2, 5, 0, 0, 1, 9, 8, 5, 0, 0, 4, 4, 0, 2]
    while i < len(raw):
        b = raw[i]
        if b == 13:
            out.append("\n")
        elif b == 10 or b == 127:
            pass
        elif b < 32:
            i += params[b]
        elif b < 127:
            out.append(chr(b))
        i += 1
    text = "".join(out)
    # the prompt (">" alone on its line) is not program output
    lines = [l for l in text.split("\n") if l.strip() and l != ">"]
    return "".join(l + "\n" for l in lines)


def last_line(text):
    lines = [l for l in text.splitlines() if l.strip()]
    return lines[-1].strip() if lines else ""


def default_host():
    env = os.path.join(ROOT, ".env")
    if os.path.exists(env):
        for line in open(env):
            m = re.match(r"\s*ULTIP1\s*=\s*(\S+)", line)
            if m:
                return m.group(1)
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--host", default=os.environ.get("U64_HOST") or default_host())
    ap.add_argument("--password", default=os.environ.get("ULTIMATE_PASSWORD"))
    ap.add_argument("--timeout", type=float, default=30.0)
    ap.add_argument("--json", action="store_true", help="one JSON object on stdout")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    p = sub.add_parser("run")
    p.add_argument("file")
    p = sub.add_parser("load")
    p.add_argument("file")
    p = sub.add_parser("exec")
    p.add_argument("lines", nargs="+")
    p = sub.add_parser("input")
    p.add_argument("text")
    sub.add_parser("stop")
    sub.add_parser("endshow")
    sub.add_parser("screen")
    sub.add_parser("list")
    p = sub.add_parser("debug")
    p.add_argument("file")
    p.add_argument("--break", dest="breaks", type=int, nargs="*", default=[])
    p.add_argument("--entry", action="store_true", help="stop at the first line")
    sub.add_parser("continue")
    sub.add_parser("step")
    sub.add_parser("vars")
    args = ap.parse_args()

    if not args.host:
        sys.exit("no host: --host, U64_HOST or ULTIP1 in .env")
    remote = Remote(args.host, args.password)
    code, result = EXIT_OK, {}
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(EXIT_TIMEOUT))
    try:
        if args.cmd == "status":
            result = remote.state()
        elif args.cmd in ("run", "load"):
            text = open(args.file, encoding="latin-1").read()
            result = remote.send_program(text, run=args.cmd == "run",
                                         timeout=args.timeout)
        elif args.cmd == "exec":
            result = remote.run_lines(args.lines, timeout=args.timeout)
        elif args.cmd == "input":
            result = remote.run_lines([args.text], timeout=args.timeout)
        elif args.cmd == "stop":
            remote.stop()
            result = {"ok": True}
        elif args.cmd == "endshow":
            result = {"ok": remote.end_show()}
        elif args.cmd == "screen":
            result = {"screen": [r.rstrip() for r in remote.screen()]}
        elif args.cmd == "list":
            result = {"program": remote.program_text()}
        elif args.cmd == "debug":
            text = open(args.file, encoding="latin-1").read()
            result = remote.debug_start(text, args.breaks, args.entry, timeout=args.timeout)
            if result["state"] == "paused":
                result["line"] = remote.state()["line"]
        elif args.cmd in ("continue", "step"):
            result = remote.debug_resume(DBG_CONTINUE if args.cmd == "continue" else DBG_STEP,
                                         timeout=args.timeout)
        elif args.cmd == "vars":
            result = {"variables": remote.variables(), "line": remote.state()["line"]}
        if result.get("ok") is False:
            code = EXIT_TIMEOUT if result.get("state") == "timeout" else EXIT_BASIC_ERROR
    except (RemoteError, TimeoutError, ValueError) as e:
        code = EXIT_TIMEOUT if isinstance(e, TimeoutError) else EXIT_CONNECTION
        result = {"ok": False, "error": {"message": str(e)}}
    finally:                                # also Ctrl+C and SIGTERM
        remote.release()

    if args.json:
        print(json.dumps(result, indent=1))
    else:
        if "output" in result:
            sys.stdout.write(result["output"])
        if "screen" in result:
            print("\n".join(result["screen"]))
        if "program" in result:
            sys.stdout.write(result["program"])
        if "variables" in result:
            for k, v in result["variables"].items():
                print("%s = %r" % (k, v))
        if result.get("state") == "paused":
            print("paused before line %s (continue / step / vars / stop)" % result.get("line"),
                  file=sys.stderr)
        if args.cmd == "status":
            print(json.dumps(result))
        if result.get("error"):
            e = result["error"]
            print("error %s: %s%s" % (e.get("number", "-"), e.get("message", ""),
                                      " at line %s" % e["line"] if e.get("line") else ""),
                  file=sys.stderr)
        if result.get("state") == "timeout":
            print("time-out: still running (stop with: u64remote.py stop)", file=sys.stderr)
        if result.get("state") == "input":
            print("waiting for INPUT (answer with: u64remote.py input TEXT)", file=sys.stderr)
    sys.exit(code)


if __name__ == "__main__":
    main()
