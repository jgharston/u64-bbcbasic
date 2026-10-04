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
MB_RINGW, MB_RINGR, MB_CAPTURE, MB_LINELEN, MB_PROG = 12, 13, 14, 15, 16
MB_PROMPT, MB_ERRNUM, MB_ERRCNT, MB_LINE, MB_RING = 17, 18, 19, 20, 110
MB_SIZE, MB_LINEMAX, RING = 238, 74, 128
REQ_LINE, REQ_CAPTURE, REQ_PROGRAM = 1, 3, 4
PAGE, HIMEM = 0x0800, 0x8000
ESCFLG = 0x00FF
SCREEN = 0xC000

EXIT_OK, EXIT_BASIC_ERROR, EXIT_TIMEOUT, EXIT_CONNECTION = 0, 1, 2, 3


class RemoteError(Exception):
    """Cannot talk to the machine, or the cartridge is not running."""


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

    def mailbox(self):
        mb = self.read(MBOX, MB_SIZE)
        if mb[:4] != b"BBCR":
            raise RemoteError("U64 BBC BASIC is not running on %s "
                              "(no mailbox at $%04X)" % (self.host, MBOX))
        return mb

    def state(self, mb=None):
        mb = mb or self.mailbox()
        status = mb[MB_STATUS]
        waiting = status == 1
        return {
            "state": ("prompt" if mb[MB_PROMPT] == 0x07 else "input")
                     if waiting else ("running" if status == 2 else "idle"),
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
        self.write(MBOX + MB_LINE, data)
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

    def drain(self, mb=None):
        """Output captured since the last call (the ring)."""
        mb = mb or self.mailbox()
        w, r = mb[MB_RINGW], mb[MB_RINGR]
        if w == r:
            return b""
        ring = mb[MB_RING:MB_RING + RING]
        out = ring[r:w] if w > r else ring[r:] + ring[:w]
        self.write(MBOX + MB_RINGR, [w])
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
        while True:
            mb = self.mailbox()
            out += self.drain(mb)
            st = self.state(mb)
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
            message = last_line(text)
            m = re.search(r"^(.*) at line (\d+)$", message)
            result["ok"] = False
            result["error"] = {"number": st["last_error"],
                               "message": m.group(1) if m else message,
                               "line": int(m.group(2)) if m else None}
        if state == "timeout":
            result["ok"] = False
        return result

    def send_program(self, text, run=False, timeout=30.0):
        image = bbctok.tokenise_program(text)
        if PAGE + len(image) > HIMEM - 1024:
            raise ValueError("program too big (%d bytes)" % len(image))
        st = self.wait_line_wanted(10)
        if st["state"] != "prompt":
            raise RemoteError("BASIC is waiting for INPUT, not at the prompt")
        errors_before = st["error_count"]
        self.capture(True)
        self.drain()
        self.write(PAGE, image)
        self.post(REQ_PROGRAM, bytes([1 if run else 0]))
        self.errors_before = errors_before
        r = self.run_lines([], timeout=timeout, prepared=True)
        if self.state()["error_count"] != errors_before and r["error"] is None:
            r["ok"] = False
            r["error"] = {"number": self.state()["last_error"],
                          "message": last_line(r["output"]), "line": None}
        r["program_bytes"] = len(image)
        return r

    def stop(self):
        self.write(ESCFLG, [0x80])

    def screen(self):
        sys.path.insert(0, os.path.join(ROOT, "tests", "e2e"))
        import screen as scr  # noqa: E402
        return scr.decode_screen(self.read(SCREEN, 1000))

    def program_text(self):
        """The program in memory, detokenised on the host."""
        image = b"".join(self.read(PAGE + i, 0x1000) for i in range(0, 0x4000, 0x1000))
        end = image.find(b"\r\xff")
        if image[0] != 0x0D or end < 0:
            raise RemoteError("no program at PAGE")
        return bbctok.detokenise(image[:end + 2])


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
    sub.add_parser("screen")
    sub.add_parser("list")
    args = ap.parse_args()

    if not args.host:
        sys.exit("no host: --host, U64_HOST or ULTIP1 in .env")
    remote = Remote(args.host, args.password)
    code, result = EXIT_OK, {}
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
        elif args.cmd == "screen":
            result = {"screen": [r.rstrip() for r in remote.screen()]}
        elif args.cmd == "list":
            result = {"program": remote.program_text()}
        if result.get("ok") is False:
            code = EXIT_TIMEOUT if result.get("state") == "timeout" else EXIT_BASIC_ERROR
    except (RemoteError, TimeoutError, ValueError) as e:
        code = EXIT_TIMEOUT if isinstance(e, TimeoutError) else EXIT_CONNECTION
        result = {"ok": False, "error": {"message": str(e)}}

    if args.json:
        print(json.dumps(result, indent=1))
    else:
        if "output" in result:
            sys.stdout.write(result["output"])
        if "screen" in result:
            print("\n".join(result["screen"]))
        if "program" in result:
            sys.stdout.write(result["program"])
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
