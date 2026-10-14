#!/usr/bin/env python3
"""End-to-end tests for U64 BBC BASIC through c64bridge.

Targets:
  vice           the EasyFlash cartridge in VICE (x64sc, started here with
                 its binary monitor; c64bridge attaches to it)
  <ip>/tmb, /ef  each Ultimate in .env (ULTIP1, ULTIP2): the cartridge is
                 uploaded to /Temp over FTP and started with c64bridge's
                 run_crt

Each test clears the screen, types a command line through the keyboard
buffer and waits for the expected text. Failing screens are saved in
build/e2e/<target>/<test>.txt. Python 3 standard library + npx.

Usage: run_e2e.py [--vice-only | --no-vice] [--device IP ...] [--only NAME]
"""
import argparse
import ftplib
import io
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from c64bridge import Bridge, BridgeError  # noqa: E402
import screen  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BUILD = os.path.join(ROOT, "build")
CRT = {"ef": os.path.join(BUILD, "u64bbc-ef.crt"),
       "tmb": os.path.join(BUILD, "u64bbc-tmb.crt")}
VICE_PORT = 6510


def read_env():
    env = {}
    path = os.path.join(ROOT, ".env")
    if os.path.exists(path):
        for line in open(path):
            m = re.match(r"\s*(\w+)\s*=\s*(\S+)", line)
            if m and not line.lstrip().startswith("#"):
                env[m.group(1)] = m.group(2)
    return env


# ----------------------------------------------------------------------------
# Targets

class Target:
    """A machine running the cartridge; .bridge is its c64bridge client."""
    name = "?"
    is_vice = False

    def start(self):
        raise NotImplementedError

    def stop(self):
        if getattr(self, "bridge", None):
            self.bridge.close()

    def press_stop(self):
        """Tap RUN/STOP on the real keyboard matrix. False if unsupported."""
        return False


class ViceTarget(Target):
    name = "vice"
    is_vice = True

    def start(self):
        subprocess.run(["pkill", "-f", "binarymonitoraddress ip4://127.0.0.1:%d"
                        % VICE_PORT], check=False)
        self.proc = subprocess.Popen(
            ["x64sc", "-default", "-minimized", "+sound", "-binarymonitor",
             "-binarymonitoraddress", "ip4://127.0.0.1:%d" % VICE_PORT,
             "-cartcrt", CRT["ef"]],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(4)
        self.bridge = Bridge({"C64_MODE": "vice", "VICE_PORT": str(VICE_PORT)},
                             self.name, timeout=120)

    def stop(self):
        super().stop()
        self.proc.terminate()


class UltimateTarget(Target):
    def __init__(self, host, kind):
        self.host = host
        self.kind = kind
        self.name = "%s-%s" % (host, kind)

    def start(self):
        password = os.environ.get("ULTIMATE_PASSWORD", "")
        remote = "/Temp/u64bbc-%s.crt" % self.kind
        with ftplib.FTP(self.host, timeout=20) as ftp:
            ftp.login("anonymous", password)
            with open(CRT[self.kind], "rb") as f:
                ftp.storbinary("STOR " + remote, f)
        env = {"C64_MODE": "c64u", "C64U_HOST": self.host}
        if password:
            env["C64U_PASSWORD"] = password
        self.bridge = Bridge(env, self.name, timeout=60)
        # RAM survives the reset: wipe the old screen and mailbox first, so
        # the boot test cannot see the previous session's banner while the
        # cartridge is still starting (that let early mailbox writes be
        # overwritten by the new cold start)
        self.bridge.write(0xC000, [0x20] * 1000)
        self.bridge.write(0xC6E0, [0] * 8)
        self.bridge.call("c64_program", op="run_crt", path=remote)

    def press_stop(self):
        self.bridge.call("c64_input", op="keyboard", inputs=["run_stop"],
                         transition="tap")
        return True


# ----------------------------------------------------------------------------
# Tests: each gets the target and raises AssertionError/TimeoutError on
# failure. Helpers type a line and wait for text.

def run_line(t, line, expect, timeout=20):
    screen.type_text(t.bridge, "CLS\r")
    screen.wait_for(t.bridge, lambda r: r[0].startswith(">"), timeout)
    screen.type_text(t.bridge, line + "\r")
    return screen.wait_for(
        t.bridge, lambda r: any(expect in row for row in r[1:]), timeout)


def test_boot(t):
    rows = screen.wait_text(t.bridge, "U64 BBC BASIC", 30)
    rows = screen.wait_for(t.bridge, lambda r: any(x.startswith(">") for x in r))
    cpu = [r.strip() for r in rows if r.startswith("CPU")]
    assert cpu, "no CPU line"
    if t.is_vice:
        assert cpu[0] == "CPU 1 MHz", cpu[0]
    t.notes.append(cpu[0])


def test_basic_ram(t):
    # BASIC runs from its RAM copy with the cartridge off (resident.s,
    # copy_basic): the Ultimate 64 runs cartridge ROM fetches at 1 MHz.
    # Checked from inside (EOR of 32-bit words as the CPU sees them); the
    # Ultimate's DMA memory read does not see the CPU's memory map.
    rom = open(os.path.join(BUILD, "basic.rom"), "rb").read()
    want = 0
    for i in range(0, 0x4000, 4):
        want ^= int.from_bytes(rom[i:i + 4], "little")
    rows = run_line(t, "S%=0:FOR A%=&8000 TO &BFFC STEP 4:S%=S% EOR !A%:NEXT:"
                       "PRINT ~S%", "", timeout=60)
    rows = screen.wait_for(
        t.bridge, lambda r: any(re.match(r"^\s*[0-9A-F]+\s*$", x) for x in r[1:]), 60)
    got = [x.strip() for x in rows[1:] if re.match(r"^\s*[0-9A-F]+\s*$", x)][0]
    assert int(got, 16) == want, "checksum %s, expected %X" % (got, want)


def test_arith(t):
    run_line(t, "PRINT 1+1", "         2")


def test_line_editor(t):
    # the MOS line editor (lineed.s): editing inside the line, a line
    # longer than the KERNAL's 80 columns, history (UP/DOWN), BBC copy
    # editing (copy cursor, F1 = COPY) and *EDIT
    run_line(t, "PRINT 1+3{LEFT}{LEFT}2", "        15")
    run_line(t, "PRINT 99+1{LEFT}{LEFT}{DEL}", "        10")
    run_line(t, "7*6{HOME}PRINT ", "        42")
    run_line(t, "PRINT 3{LEFT}{INST}{INST}{HOME}{CLR}+4", "         7")
    run_line(t, 'PRINT LEN("' + "AB" * 50 + '")', "       100")
    if not t.is_vice:                   # (the history is in the REU)
        run_line(t, "PRINT 5*5", "        25")
        screen.type_text(t.bridge, "{UP}{DEL}3\r")
        screen.wait_for(t.bridge, lambda r: any("        15" in x for x in r[1:]))
        screen.type_text(t.bridge, "PRINT 1{UP}{DOWN}0\r")
        screen.wait_for(t.bridge, lambda r: any("        10" in x for x in r[1:]))
        # back to an empty line typed (a length-0 REU copy wiped all
        # memory here once): the machine still answers
        run_line(t, "{UP}{UP}{DOWN}{DOWN}{DOWN}PRINT 9*9", "        81")
    run_line(t, "PRINT 4321", "      4321")
    screen.type_text(t.bridge, "{CUP}{CUP}{CLEFT}{CRIGHT}" + "{F1}" * 10 + "0\r")
    screen.wait_for(t.bridge, lambda r: any("     43210" in x for x in r[1:]))
    # MODE 7: a line wrapping over two rows, copy from the screen memory
    def ttx_wait(cond, what):
        deadline = time.time() + 20
        while True:
            ttx = b"".join(bytes(t.bridge.read(0x7C00 + i, 200))
                           for i in range(0, 1000, 200)).decode("latin-1")
            rows = [ttx[i:i + 40].rstrip() for i in range(0, 1000, 40)]
            if cond(rows):
                return rows
            assert time.time() < deadline, (what, rows)
            time.sleep(0.5)
    screen.type_text(t.bridge, "MODE 7\r")
    try:
        ttx_wait(lambda r: r[0] == ">" and not any(r[1:]), "MODE 7")
        screen.type_text(t.bridge, 'PRINT LEN("' + "AB" * 30 + '")\r')
        ttx_wait(lambda r: "        60" in r and r[3] == ">", "long line")
        screen.type_text(t.bridge, "PRINT 4321\r")
        ttx_wait(lambda r: r[5] == ">", "PRINT 4321")
        screen.type_text(t.bridge, "{CUP}{CUP}{CLEFT}{CRIGHT}" + "{F1}" * 10 + "0\r")
        rows = ttx_wait(lambda r: "     43210" in r, "copy")
        assert rows[0].startswith('>PRINT LEN("ABAB') and rows[5] == ">PRINT 43210", rows
    finally:
        screen.type_text(t.bridge, "MODE 100\r")
        time.sleep(1)
    # a remote request while a line is half typed: the line goes, the
    # request is handled
    screen.type_text(t.bridge, "CLS\r")
    screen.wait_for(t.bridge, lambda r: r[0].startswith(">"))
    screen.type_text(t.bridge, "*CAT1")
    screen.wait_for(t.bridge, lambda r: r[0].startswith(">*CAT1"))
    out = remote(t).run_lines(["PRINT 6*7"])
    assert "42" in out["output"], out
    run_line(t, "*EDIT C64", ">")
    run_line(t, "*EDIT", "C64")
    run_line(t, "*EDIT BBC", ">")
    run_line(t, "*EDIT", "BBC")


def test_caps_lock(t):
    # OSBYTE &CA: CAPS LOCK on at the start (bit 4 = 0, SHIFT LOCK off:
    # bit 5); set off and on again (Shift+C= on the keyboard does the same)
    out = remote(t).run_lines([
        "A%=&CA:X%=0:Y%=255:S%=(USR&C7F4 AND &FF00) DIV 256",
        "A%=&CA:X%=&10:Y%=&EF:D%=USR&C7F4",
        "A%=&CA:X%=0:Y%=255:T%=(USR&C7F4 AND &FF00) DIV 256",
        "A%=&CA:X%=0:Y%=&EF:D%=USR&C7F4",
        "A%=&CA:X%=0:Y%=255:U%=(USR&C7F4 AND &FF00) DIV 256",
        'PRINT "C=";S% AND &30;",";T% AND &30;",";U% AND &30'])["output"]
    assert "C=32,48,32" in out, out


def test_key(t):
    # *KEY: F2 types a text at the prompt; *KEY lists; GET$ in a program
    # reads an expansion; *KEY n alone clears (texts in the REU)
    if t.is_vice:
        run_line(t, "*KEY 2 X", "Needs an REU")
        return
    run_line(t, "*KEY 2 PRINT 6*7|M", ">")
    screen.type_text(t.bridge, "CLS\r")
    screen.wait_for(t.bridge, lambda r: r[0].startswith(">"))
    screen.type_text(t.bridge, "{F2}")
    screen.wait_for(t.bridge, lambda r: any("        42" in x for x in r[1:]))
    rows = run_line(t, "*KEY", "*KEY 2")
    assert any("*KEY 2 PRINT 6*7|M" in r for r in rows), rows
    run_line(t, '*KEY 3 "AB"', ">")
    screen.type_text(t.bridge, 'A$=GET$:B$=GET$:PRINT "G=";A$;B$\r{F3}')
    screen.wait_for(t.bridge, lambda r: any("G=AB" in x for x in r))
    run_line(t, "*KEY 2", ">")
    run_line(t, "*KEY 3", ">")
    rows = run_line(t, "*KEY", ">")
    assert not any("*KEY 2" in r or "*KEY 3" in r for r in rows), rows


def test_hex(t):
    run_line(t, "PRINT ~255", "FF")


def test_ascii(t):
    text = "a\\b|c~d{e}f_g^h`i[j]k@Z"
    rows = run_line(t, 'PRINT "%s"' % text, text)
    assert rows[1].rstrip() == text, rows[1]


def test_program(t):
    run_line(t, "NEW", ">")
    screen.type_text(t.bridge, "10 FOR I%=1 TO 3:PRINT I%*7:NEXT\r")
    rows = run_line(t, "RUN", "        21")
    joined = "\n".join(rows)
    assert "         7" in joined and "        14" in joined, joined
    rows = run_line(t, "LIST", "FOR I%=1 TO 3")


def test_error(t):
    run_line(t, "PRINT 1/0", "Division by zero")


def test_mos_error(t):
    # raised in the MOS bank: the error block is copied to RAM (resident.s)
    run_line(t, "*FROBNICATE", "Bad command")


def test_help(t):
    run_line(t, "*HELP", "*HELP KEYWORDS")
    run_line(t, "*HELP PRINT", "Prints values")
    run_line(t, "*HELP *CAT", "Lists the current directory")
    run_line(t, "*HELP OPEN", "OPENUP")
    run_line(t, "*HELP FROB", "No help on FROB")


def help_pages(t, last_text):
    # SPACE at each "SPACE: more" until the topic's last text and the prompt
    for _ in range(10):
        screen.type_text(t.bridge, " ")
        time.sleep(0.5)
        rows = screen.wait_for(t.bridge, lambda r: any("SPACE: more" in x for x in r)
                               or any(x.startswith(">") for x in r))
        if not any("SPACE: more" in x for x in rows):
            assert any(last_text in r for r in rows), rows
            return
    raise AssertionError("no end of the topic: " + last_text)


def test_help_paging(t):
    # MEMORY is longer than one page: the prompt, then SPACE for more
    run_line(t, "*HELP MEMORY", "SPACE: more")
    help_pages(t, "MODE 7.")
    run_line(t, "*HELP KEYWORDS", "SPACE: more")
    help_pages(t, "WIDTH")


def test_bad_number(t):
    run_line(t, "*FX 300", "Bad number")


def test_vdu_overflow(t):
    # OSBYTE &DA can set any VDU queue count; the parameter buffer is 9
    # bytes. 200 swallowed bytes must not overwrite the MOS variables.
    # Output is swallowed until 200 bytes have gone by (as on a BBC), so
    # don't wait for the prompt: the 200 VDU 65s use up the queue.
    screen.type_text(t.bridge, "CLS\r")
    screen.wait_for(t.bridge, lambda r: r[0].startswith(">"))
    screen.type_text(t.bridge, "*FX 218,200\r")
    screen.type_text(t.bridge, 'FOR I%=1 TO 200:VDU 65:NEXT:PRINT "OK";6*7\r')
    screen.wait_text(t.bridge, "AOK42", 20)


def test_fx_escape(t):
    # *FX 125 sets ESCAPE; BASIC must report it and recover
    run_line(t, "NEW", ">")
    screen.type_text(t.bridge, "10 *FX 125\r20 GOTO 20\r")
    run_line(t, "RUN", "Escape at line")
    run_line(t, "PRINT 6*7", "        42")


def test_stop_key(t):
    run_line(t, "NEW", ">")
    screen.type_text(t.bridge, "10 GOTO 10\r")
    screen.type_text(t.bridge, "RUN\r")
    time.sleep(1)
    if not t.press_stop():
        # VICE through c64bridge has no keyboard matrix: set ESCFLG
        # directly, which still tests BASIC's escape handling
        t.notes.append("RUN/STOP key: not available, ESCFLG set directly")
        t.bridge.write(0xFF, [0x80])
    screen.wait_text(t.bridge, "Escape at line 10", 10)


def test_time(t):
    # TIME read twice through the mailbox, wall-clock time around each
    # read: the transport latency cancels out (it skewed a screen-based
    # measurement once on a slow REST round trip)
    rm = u64remote.Remote(mem=t.bridge)

    def sample():
        t0 = time.time()
        r = rm.run_lines(["PRINT TIME"])
        t1 = time.time()
        return int(r["output"].split()[0]), (t0 + t1) / 2

    v1, w1 = sample()
    time.sleep(3)
    v2, w2 = sample()
    rate = (v2 - v1) / (w2 - w1)
    t.notes.append("TIME %.0f/s" % rate)
    assert 85 <= rate <= 115, "TIME runs at %.0f per second" % rate


def test_inkey(t):
    rows = run_line(t, "PRINT INKEY(50)", "-1", timeout=10)


def test_get(t):
    screen.type_text(t.bridge, "CLS\r")
    screen.wait_for(t.bridge, lambda r: r[0].startswith(">"))
    screen.type_text(t.bridge, "A=GET:PRINT A\r")
    time.sleep(0.5)
    screen.type_text(t.bridge, "x")
    screen.wait_for(t.bridge, lambda r: any("       120" in x for x in r[1:]))


def test_long_line(t):
    # the MOS line editor: 219 characters, six rows (BBC limit 238);
    # with *EDIT C64 the KERNAL editor's 77 after the prompt
    s = "X" * 200
    run_line(t, 'A$="%s":PRINT LEN(A$)' % s, "       200")
    run_line(t, "*EDIT C64", ">")
    run_line(t, 'A$="%s":PRINT LEN(A$)' % s[:58], "        58")
    run_line(t, "*EDIT BBC", ">")


def test_speed(t):
    run_line(t, "NEW", ">")
    screen.type_text(t.bridge, "10 T%=TIME:FOR I%=1 TO 5000:NEXT:PRINT TIME-T%\r")
    screen.type_text(t.bridge, "CLS\r")
    screen.wait_for(t.bridge, lambda r: r[0].startswith(">"))
    screen.type_text(t.bridge, "RUN\r")
    rows = screen.wait_for(
        t.bridge, lambda r: any(re.search(r"^\s+\d+\s*$", x) for x in r[1:]), 60)
    cs = [int(x) for r in rows[1:] for x in re.findall(r"^\s+(\d+)\s*$", r)]
    t.notes.append("5000 FOR loops: %d cs" % cs[0])


# --- Filing system and Ultimate commands (bank 2). Work in /Temp, the
# Ultimate's RAM disk; on VICE (no command interface) only the error.

def ult(t):
    """True on an Ultimate (and the current directory is then /Temp, the
    RAM disk); on VICE checks the 'no Ultimate' error instead."""
    if t.is_vice:
        run_line(t, "*CAT", "No Ultimate command interface")
        return False
    run_line(t, "*DIR /Temp", ">")
    return True


def test_fs_uver(t):
    if ult(t):
        run_line(t, "*UVER", "ULTIMATE-II DOS")


def test_fs_time(t):
    if ult(t):
        run_line(t, "*TIME", "/")
        screen.wait_for(t.bridge, lambda rows: any(
            re.search(r"20\d\d/\d\d/\d\d \d\d:\d\d:\d\d", r) for r in rows))


def test_fs_dir(t):
    if ult(t):
        run_line(t, "*DIR /Temp", ">")
        run_line(t, "*PWD", "/Temp")
        # leftovers of an interrupted run (errors for missing files are fine)
        for f in ("e2etest", "e2eren", "e2edata", "e2etext"):
            run_line(t, "*DELETE " + f, ">")


def test_fs_save_load(t):
    if not ult(t):
        return
    run_line(t, "NEW", ">")
    screen.type_text(t.bridge, '10 PRINT "SAVED";6*7\r')
    run_line(t, 'SAVE "e2etest"', ">")
    run_line(t, 'SAVE "e2etest"', ">")          # overwrite an existing file
    run_line(t, 'X=OPENOUT "e2etest":CLOSE#X', ">")   # SAVE after a colon
    run_line(t, 'SAVE "e2etest"', ">")                 # is a syntax error
    run_line(t, "NEW", ">")
    run_line(t, 'LOAD "e2etest"', ">")
    run_line(t, "RUN", "SAVED42")
    run_line(t, "NEW", ">")
    run_line(t, 'CHAIN "e2etest"', "SAVED42")
    run_line(t, "*CAT", "e2etest")


def test_fs_channels(t):
    if not ult(t):
        return
    run_line(t, "NEW", ">")
    lines = ['10 X=OPENOUT "e2edata":FOR I%=1 TO 300:BPUT#X,I% MOD 256:NEXT',
             '20 PRINT#X,"WORD",12345:CLOSE#X',
             '30 Y=OPENIN "e2edata":PRINT "EXT";EXT#Y',
             '40 PTR#Y=99:PRINT "B";BGET#Y;"P";PTR#Y',
             '50 PTR#Y=300:INPUT#Y,A$,N:PRINT A$;N;EOF#Y',
             '60 CLOSE#Y:PRINT "MISSING";OPENIN "e2enone"']
    for l in lines:
        screen.type_text(t.bridge, l + "\r")
    rows = run_line(t, "RUN", "MISSING", timeout=30)
    text = "\n".join(rows)
    assert "EXT" in text and "B100P100" in text.replace(" ", ""), text
    assert "WORD12345-1" in text.replace(" ", ""), text
    assert "MISSING0" in text.replace(" ", ""), text


def test_fs_type(t):
    if not ult(t):
        return
    run_line(t, "NEW", ">")
    screen.type_text(t.bridge, '10 X=OPENOUT "e2etext":FOR I%=1 TO 3\r')
    screen.type_text(t.bridge, '20 FOR J%=1 TO 5:BPUT#X,64+I%:NEXT:BPUT#X,13\r')
    screen.type_text(t.bridge, '30 NEXT:CLOSE#X\r')
    run_line(t, "RUN", ">")
    rows = run_line(t, "*TYPE e2etext", "CCCCC")
    assert "AAAAA" in "\n".join(rows), rows[:5]


def test_fs_errors(t):
    if not ult(t):
        return
    run_line(t, 'LOAD "e2enone"', "doesn't exist")
    run_line(t, "REPORT:PRINT ERR", "214")
    run_line(t, "*DIR /nosuchdir", "directory")
    run_line(t, "*LOAD e2etest &0100", "Address out of range")


def test_fs_rename_delete(t):
    if not ult(t):
        return
    run_line(t, "*RENAME e2etest e2eren", ">")
    run_line(t, "NEW", ">")
    run_line(t, 'CHAIN "e2eren"', "SAVED42")
    for f in ("e2eren", "e2edata", "e2etext"):
        run_line(t, "*DELETE " + f, ">")
    run_line(t, 'PRINT "GONE";OPENIN "e2edata"', "GONE0")


def test_status(t):
    # *STATUS: on VICE no Ultimate and no REU (EasyFlash RAM at $DF00
    # must not look like an REU); on the Ultimates REU, machine, drives
    r = u64remote.Remote(mem=t.bridge).run_lines(["*STATUS"])
    out = r["output"]
    assert "PAGE       &1D00" in out and "HIMEM      &8000" in out, out
    if t.is_vice:
        assert "REU        none" in out and "Machine" not in out, out
    else:
        assert "Machine    Ultimate 64" in out, out
        assert "Drive      15" in out and "Network    " in out, out
        reu = [l for l in out.splitlines() if l.startswith("REU")]
        t.notes.append(reu[0] if reu else "REU line missing")
        assert reu and reu[0] != "REU        none", out
        drives = [l for l in out.splitlines() if l.startswith("Drive")]
        t.notes.extend(drives)
        # the SoftIEC drive must show when it is on, also on firmware 3.15a
        # (whose drive info leaves it out: the serial-bus scan finds it)
        import urllib.request
        with urllib.request.urlopen("http://%s/v1/drives" % t.host, timeout=10) as f:
            info = json.load(f)
        softiec = [list(d.values())[0] for d in info["drives"] if "IEC Drive" in d]
        if softiec and softiec[0].get("enabled"):
            assert any("SoftIEC" in l and "#%d" % softiec[0]["bus_id"] in l
                       for l in drives), drives


# --- Firmware functions, batch A (docs/ULTIMATE_FUNCTIONS.md). Every
# test puts the machine back the way it was (drives, images, partition).

def rest(t, path):
    import urllib.request
    with urllib.request.urlopen("http://%s%s" % (t.host, path), timeout=10) as f:
        return json.load(f)


def drive(t, name):
    for d in rest(t, "/v1/drives")["drives"]:
        if name in d:
            return d[name]
    return {}


def test_a_clock(t):
    if not ult(t):
        return
    r = remote(t).run_lines([
        'DIM B% 30:?B%=0:A%=14:X%=B% MOD 256:Y%=B% DIV 256:CALL &C7F1:PRINT $B%',
        '?B%=1:CALL &C7F1:FOR I%=0 TO 6:PRINT ~B%?I%;" ";:NEXT:PRINT',
        "*TIME"])
    lines = r["output"].splitlines()
    m = re.match(r"^(Sun|Mon|Tue|Wed|Thu|Fri|Sat),(\d\d) (Jan|Feb|Mar|Apr|May|Jun|Jul"
                 r"|Aug|Sep|Oct|Nov|Dec) (\d{4})\.(\d\d):(\d\d):(\d\d)$", lines[0])
    assert m, lines
    bcd = lines[1].split()
    # (BCD bytes printed in hex read as decimal digits: day 10 is "10")
    assert len(bcd) == 7 and bcd[0] == m.group(4)[2:] and int(bcd[2]) == int(m.group(2)) \
        and int(bcd[3]) in range(1, 8), lines
    import datetime
    dow = datetime.date(int(m.group(4)), int(bcd[1]), int(bcd[2])).isoweekday() % 7 + 1
    assert int(bcd[3]) == dow, (lines, dow)
    assert lines[2].startswith(m.group(4) + "/"), lines


def test_a_copy(t):
    # Firmware: *COPY puts the file into a directory, same name, no overwrite
    if not ult(t):
        return
    run_line(t, "NEW", ">")
    screen.type_text(t.bridge, '10 PRINT "COPIED"\r')
    run_line(t, 'SAVE "e2ecopy"', ">")
    run_line(t, "*MKDIR e2ecdir", ">")
    try:
        run_line(t, "*COPY e2ecopy e2ecdir", ">")
        run_line(t, "NEW", ">")
        run_line(t, 'CHAIN "e2ecdir/e2ecopy"', "COPIED")
        run_line(t, "*COPY e2ecopy e2ecdir", "File exists")
    finally:
        run_line(t, "*DELETE e2ecdir/e2ecopy", ">")
        run_line(t, "*DELETE e2ecdir", ">")
        run_line(t, "*DELETE e2ecopy", ">")


def test_a_mount(t):
    if not ult(t):
        return
    image = os.path.join(BUILD, "e2e.d64")
    subprocess.run(["c1541", "-format", "e2e test,01", "d64", image],
                   check=True, capture_output=True)
    with ftplib.FTP(t.host, timeout=20) as ftp:
        ftp.login("anonymous", os.environ.get("ULTIMATE_PASSWORD", ""))
        with open(image, "rb") as f:
            ftp.storbinary("STOR /Temp/e2e.d64", f)
    before = drive(t, "a").get("image_file", "")
    try:
        run_line(t, "*MOUNT /Temp/e2e.d64 A", ">")
        assert drive(t, "a").get("image_file", "").endswith("e2e.d64"), drive(t, "a")
        rows = run_line(t, "*SWAP A", ">")    # next disk of a set: no set here
        assert not any("rror" in r for r in rows), rows
        assert drive(t, "a").get("image_file", "").endswith("e2e.d64"), drive(t, "a")
    finally:
        run_line(t, "*UNMOUNT A", ">")
    assert drive(t, "a").get("image_file", "") in ("", before), drive(t, "a")
    run_line(t, "*DELETE e2e.d64", ">")


def test_a_drive(t):
    if not ult(t):
        return
    was = drive(t, "b").get("enabled")
    try:
        run_line(t, "*DRIVE B ON", ">")
        assert drive(t, "b").get("enabled") is True
        run_line(t, "*DRIVE B OFF", ">")
        assert drive(t, "b").get("enabled") is False
    finally:
        run_line(t, "*DRIVE B %s" % ("ON" if was else "OFF"), ">")


def test_a_settime(t):
    if not ult(t):
        return
    rows = run_line(t, "*TIME", "/")
    now = [r for r in rows if re.match(r"^\d{4}/", r)][0].strip()
    rows = run_line(t, "*SETTIME " + now, ">")
    text = "\n".join(rows)
    assert "rror" not in text or "prohibited" in text.lower(), text
    t.notes.append("SETTIME: " + ("prohibited by the settings" if "prohibited" in text.lower() else "ok"))


def test_a_partition(t):
    # Through the remote interface, not the screen: the harness's screen
    # reads (1000-byte DMA) during serial-bus transfers break their timing
    if not ult(t):
        return
    r = remote(t)
    assert not r.run_lines(["*PARTITION 250 /Temp E2E"])["error"]
    out = r.run_lines(["*PARTITIONS"], timeout=60)["output"]
    assert '"E2E"' in out, out
    assert not r.run_lines(["*CP 250"], timeout=60)["error"]
    assert not r.run_lines(["*CP 0"], timeout=60)["error"]


def test_a_dirhome(t):
    if not ult(t):
        return
    run_line(t, "*DIR ~", ">")
    run_line(t, "*PWD", "/")
    run_line(t, "*DIR /Temp", ">")


# --- Graphics (docs/DESIGN_GRAPHICS.md section 10). Checked from inside
# BASIC (POINT, POS, VPOS), so the same on VICE and the Ultimates.

def gfx_check(t, mode, lines, expect, timeout=60):
    """Run lines in MODE mode, then the check line printing "R=..."; back to
    the C64 text screen (MODE 100; MODE 7 is teletext)."""
    r = remote(t) if ult(t) else None
    prog = ["MODE %d" % mode] + lines
    if r:
        out = r.run_lines(prog + ["MODE 100", "PRINT R$"], timeout=timeout)["output"]
    else:
        for line in prog + ["MODE 100"]:   # typed: the screen is a bitmap
            screen.type_text(t.bridge, line + "\r")
            time.sleep(4)                   # 1 MHz: drawing takes time
        screen.wait_for(t.bridge, lambda r: any(x.startswith(">") for x in r), timeout)
        out = "\n".join(run_line(t, "PRINT R$", "R=", timeout=timeout))
    m = re.search(r"R=(\S*)", out)
    assert m and "R=" + m.group(1) == expect, (mode, out[-300:], expect)


def test_gfx_point_line(t):
    # A point, a line's end points and middle, clipping off screen, POINT
    # outside the screen = -1
    for mode in (0, 1, 2, 4, 5, 103, 104):
        col = {0: 1, 4: 1, 1: 3, 5: 3, 2: 7, 103: 7, 104: 7}[mode]
        gfx_check(t, mode, [
            "GCOL 0,%d:PLOT 69,640,512" % col,
            "MOVE 0,0:DRAW 1279,799:A%=POINT(0,0):B%=POINT(1279,799)",
            "R$=\"R=\"+STR$POINT(640,512)+STR$A%+STR$B%+STR$POINT(-8,0)"],
            "R=%d%d%d-1" % (col, col, col))


def test_gfx_rect_clg_window(t):
    # Filled rectangle; graphics window clips it; CLG clears the window only
    gfx_check(t, 4, [
        "GCOL 0,1:MOVE 100,100:PLOT 101,400,400",
        "A%=POINT(250,250):VDU 24,600;600;800;800;",
        "MOVE 500,500:PLOT 101,900,900:B%=POINT(700,700):C%=POINT(550,550)",
        "GCOL 0,129:PLOT 69,0,0:CLG:D%=POINT(700,700):E%=POINT(250,250)",
        "R$=\"R=\"+STR$A%+STR$B%+STR$C%+STR$D%+STR$E%"],
        "R=11-11-1")


def test_gfx_gcol_actions(t):
    # OR, AND, EOR, invert on a 4-colour mode (BBC semantics)
    gfx_check(t, 1, [
        "GCOL 0,1:PLOT 69,640,512:GCOL 1,2:PLOT 69,640,512:A%=POINT(640,512)",
        "GCOL 2,1:PLOT 69,640,512:B%=POINT(640,512)",
        "GCOL 3,3:PLOT 69,640,512:C%=POINT(640,512)",
        "GCOL 4,0:PLOT 69,640,512:D%=POINT(640,512)",
        "R$=\"R=\"+STR$A%+STR$B%+STR$C%+STR$D%"],
        "R=3121")


def test_gfx_origin_relative(t):
    # VDU 29 origin, relative PLOT (k AND 4 = 0), dotted line every 2nd pixel
    gfx_check(t, 4, [
        "VDU 29,640;512;:PLOT 69,0,0:A%=POINT(0,0)",
        "MOVE 0,0:PLOT 1,100,0:B%=POINT(100,0)",
        "VDU 29,0;0;:C%=POINT(640,512)",
        "MOVE 0,0:PLOT 21,40,0:D%=POINT(0,0)+POINT(4,0)+POINT(8,0)",
        "R$=\"R=\"+STR$A%+STR$B%+STR$C%+STR$D%"],
        "R=1112")


def test_gfx_text(t):
    # Text cursor in a bitmap mode: POS/VPOS, TAB, text window, scrolling
    gfx_check(t, 4, [
        "PRINT TAB(0,3);\"HELLO\";:A%=POS:B%=VPOS",
        "PRINT TAB(10,20);:C%=POS:D%=VPOS",
        "VDU 28,5,10,20,2:E%=VPOS:F%=POS",
        "FOR I%=1 TO 20:PRINT I%:NEXT:G%=VPOS",
        "VDU 26:R$=\"R=\"+STR$A%+STR$B%+STR$C%+STR$D%+STR$E%+STR$F%+STR$G%"],
        "R=531020008")


def test_gfx_shapes(t):
    # Triangle, parallelogram, circle and ellipse fills, outlines (U64
    # codes 216-247), and EOR fills twice = nothing (each pixel once).
    # Lines stay under the remote mailbox's 74 bytes; a text window at the
    # bottom keeps the echoed lines out of the drawing.
    gfx_check(t, 1, [
        "VDU 28,0,31,39,28",
        "GCOL 0,1:MOVE 100,100:MOVE 500,100:PLOT 85,300,500",
        "A%=POINT(300,200)",
        "GCOL 0,2:MOVE 900,500:PLOT 153,100,0",
        "B%=POINT(900,500)+4*POINT(1020,500)",
        "GCOL 0,3:MOVE 600,800:PLOT 149,1000,800",
        "C%=POINT(1000,800)+4*POINT(600,800)",
        "GCOL 0,1:MOVE 100,700:MOVE 300,700:PLOT 117,400,900",
        "D%=POINT(250,800)",
        "GCOL 0,2:MOVE 100,600:PLOT 221,400,680",
        "E%=POINT(100,600)+4*POINT(250,640)",
        "GCOL 3,3:MOVE 900,250:PLOT 153,150,0",
        "MOVE 900,250:PLOT 153,150,0",
        "F%=POINT(900,250)",
        "GCOL 3,3:MOVE 1150,900:MOVE 1250,900:PLOT 205,1150,950",
        "MOVE 1150,900:MOVE 1250,900:PLOT 205,1150,950",
        "G%=POINT(1150,900)+POINT(1230,900)",
        "R$=\"R=\"+STR$A%+STR$B%+STR$C%+STR$D%",
        "R$=R$+STR$E%+STR$F%+STR$G%"],
        "R=1231200")


def test_gfx_flood(t):
    # PLOT 128-135: fill the background-coloured area around the point;
    # PLOT 136-143: fill up to the foreground colour
    gfx_check(t, 1, [
        "VDU 28,0,31,39,28",
        "GCOL 0,1:MOVE 640,600:PLOT 149,840,600",
        "GCOL 0,2:PLOT 133,640,600",
        "A%=POINT(640,600)+4*POINT(700,600)+16*POINT(900,600)",
        "GCOL 0,3:MOVE 100,300:PLOT 221,400,500",
        "PLOT 141,200,400:B%=POINT(250,400)+4*POINT(500,400)",
        "R$=\"R=\"+STR$A%+\",\"+STR$B%"],
        "R=10,3")


def test_gfx_arcs(t):
    # PLOT 176-183 sector, 168-175 segment, 160-167 arc: centre, start
    # point (radius, start angle), end direction; anticlockwise
    gfx_check(t, 1, [
        "VDU 28,0,31,39,28",
        "GCOL 0,1:MOVE 300,400:MOVE 500,400:PLOT 181,300,600",
        "A%=POINT(360,450)+4*POINT(240,450)+16*POINT(360,350)",
        "GCOL 0,2:MOVE 900,400:MOVE 1100,400:PLOT 173,900,600",
        "B%=POINT(1025,525)+4*POINT(960,450)",
        "GCOL 0,3:MOVE 640,800:MOVE 840,800:PLOT 165,640,1000",
        "C%=POINT(840,800)+4*POINT(640,800)",
        "R$=\"R=\"+STR$A%+\",\"+STR$B%+\",\"+STR$C%"],
        "R=1,2,3")


def test_vdu23_chars(t):
    # VDU 23,c,8 rows defines a character; OSWORD 10 reads it back. On the
    # text screen always; with an REU (the Ultimates) also in graphics
    # modes, and kept over MODE changes.
    rd = ("?B%=35:A%=10:X%=B% MOD 256:Y%=B% DIV 256:CALL &C7F1:"
          "PRINT \"R=\";B%?1;B%?8")
    run_line(t, "DIM B% 9:VDU 23,35,1,2,3,4,5,6,7,8", ">")
    run_line(t, rd, "R=18")
    if t.is_vice:
        return
    gfx_check(t, 4, [
        "VDU 28,0,31,39,28",
        "VDU 23,200,255,255,255,255,255,255,255,255",
        "VDU 26:PRINT TAB(0,0);CHR$200;:VDU 28,0,31,39,28",
        "A%=POINT(0,1023)+2*POINT(0,1000)+4*POINT(40,1000)",
        "R$=\"R=\"+STR$A%"],
        "R=3")
    run_line(t, rd, "R=18")                 # after MODE 4 and MODE 100


def test_font(t):
    # *FONT BBC / C64 / DEFAULT; FNG reads row 0 of a character (OSWORD
    # 10): "A" is &3C (60) in the BBC font, &18 (24) in the C64 ROM. On
    # the Ultimates also SAVE/LOAD in two formats and a MODE change.
    run_line(t, "NEW", ">")
    run_line(t, "10 DEF FNG(C%):?B%=C%:A%=10:X%=B% MOD 256:Y%=B% DIV 256:"
                "CALL &C7F1:=B%?1", ">")
    run_line(t, "DIM B% 9:*FONT BBC", ">")
    run_line(t, 'PRINT "R=";FNG(65);FNG(96)', "R=6028")
    run_line(t, "*FONT C64", ">")
    run_line(t, 'PRINT "R=";FNG(65)', "R=24")
    run_line(t, "*FONT BBC", ">")
    run_line(t, "*FONT DEFAULT", ">")
    run_line(t, 'PRINT "R=";FNG(65)', "R=24")
    if not ult(t):
        return
    for line in ("*FONT BBC", "*FONT SAVE FNTB BBC", "*FONT SAVE FNTC",
                 "*FONT DEFAULT", "*FONT LOAD FNTB BBC"):
        run_line(t, line, ">")
    run_line(t, 'PRINT "R=";FNG(65)', "R=60")
    run_line(t, "*FONT DEFAULT", ">")       # (a * command takes the line)
    run_line(t, "*FONT LOAD FNTC", ">")
    run_line(t, 'MODE 4:MODE 100:PRINT \'"R=";FNG(65)', "R=60")
    run_line(t, "*FONT LOAD FNTB", "Bad font file")
    for line in ("*FONT DEFAULT", "*DELETE FNTB", "*DELETE FNTC"):
        run_line(t, line, ">")


def test_palette(t):
    # *PALETTE: saved files show the 16 C64 colours as RGB; BBC makes C64
    # colour 2 (BBC red) pure red; VDU 19,l,16,r,g,b; a VICE .vpl file;
    # RESET back to the start-up palette. Byte n of a file read with BGET.
    if not ult(t):
        return
    rd = ('F%=OPENIN"PT":PTR#F%={0}:A%=BGET#F%:B%=BGET#F%:CLOSE#F%:'
          'PRINT"R=";A%;",";B%')
    run_line(t, "*PALETTE BBC", ">")
    run_line(t, "*PALETTE SAVE PT", ">")
    run_line(t, rd.format(6), "R=255,0")
    run_line(t, "VDU 19,1,16,10,20,30", ">")   # text: BBC 1 is C64 colour 2
    run_line(t, "*PALETTE SAVE PT", ">")
    run_line(t, rd.format(6), "R=10,20")
    run_line(t, 'F%=OPENOUT"PT.VPL":A$="# test"+CHR$10', ">")
    run_line(t, 'FOR I%=1 TO LEN A$:BPUT#F%,ASC MID$(A$,I%,1):NEXT', ">")
    run_line(t, 'A$="11 22 33 0"+CHR$10', ">")  # (a typed FOR: one line)
    run_line(t, "FOR J%=1 TO 16:FOR I%=1 TO 11:BPUT#F%,ASC MID$(A$,I%,1)"
                ":NEXT:NEXT:CLOSE#F%", ">")
    run_line(t, "*PALETTE LOAD PT.VPL VPL", ">")
    run_line(t, "*PALETTE SAVE PT", ">")
    run_line(t, rd.format(45), "R=17,34")
    run_line(t, "*PALETTE LOAD PT.VPL", "Bad palette file")
    run_line(t, "*PALETTE RESET", ">")
    run_line(t, "*PALETTE SAVE PT", ">")
    run_line(t, rd.format(6), "R=")
    for line in ("*DELETE PT", "*DELETE PT.VPL"):
        run_line(t, line, ">")


def test_memory(t):
    # *SHADOW / OSBYTE &72 (BBC Master), *MEMORY. On a 64 MHz Ultimate:
    # MODE 1 is Upic Lite (HIMEM &3000), MODE 129 and *SHADOW modes the
    # VIC-II version (HIMEM &8000), *MEMORY UPIC OFF/AUTO as *SHADOW, and
    # BASIC's "Bad MODE" when variables are in the way. VICE: always &8000.
    rd = 'A%=&72:X%=255:PRINT "R=";(USR&C7F4 AND &FF00) DIV 256'
    run_line(t, "*SHADOW", ">")
    run_line(t, rd, "R=0")
    run_line(t, "*SHADOW 1", ">")
    run_line(t, rd, "R=1")
    run_line(t, "*MEMORY", "HIMEM      &8000")
    up = not t.is_vice
    gfx_check(t, 1, [
        "F%=HIMEM:MODE 129:B%=HIMEM:*MEMORY UPIC OFF",
        "MODE 4:C%=HIMEM:*MEMORY UPIC AUTO",
        "MODE 4:D%=HIMEM:A%=&75:E%=(USR&C7F4 AND &FF00) DIV 256",
        'R$="R="+STR$~F%+","+STR$~B%+","+STR$~C%+","+STR$~D%+","+STR$E%'],
        "R=3000,8000,8000,5800,0" if up else "R=8000,8000,8000,8000,0")
    if up:
        run_line(t, "CLEAR:DIM Z% 20000:MODE 1", "Bad MODE")
        run_line(t, "CLEAR", ">")


def test_sound(t):
    # BBC mode SOUND/ENVELOPE (sound.s): queues (ADVAL(-5..-8) = 15 empty,
    # 4 bytes per waiting note), flush, sync, an envelope note that
    # ends; on the U64 also the chip itself: channel 3 is SID 1 voice 3,
    # whose envelope reads back at &D41C (255 at -15).
    run_line(t, "*SOUND BBC", ">")
    run_line(t, 'PRINT "R=";ADVAL(-5);ADVAL(-6);ADVAL(-8)', "R=151515")
    run_line(t, "SOUND 1,-15,53,100:SOUND 1,-15,57,100:SOUND 1,-15,61,100", ">")
    run_line(t, 'PRINT "R=";ADVAL(-6)', "R=7")      # one plays, two wait
    rows = run_line(t, 'SOUND &11,-10,65,4:PRINT "R=";ADVAL(-6)', "R=1")
    assert any(r.startswith("R=11") or r.startswith("R=15") for r in rows), rows
    # (11: still queued; 15: an interrupt started it already)
    time.sleep(1.0)
    run_line(t, 'PRINT "R=";ADVAL(-6)', "R=15")     # flushed and played
    run_line(t, 'SOUND &101,-15,53,4:PRINT "R=";ADVAL(-6)', "R=11")
    time.sleep(0.5)                                  # waits for its partner
    run_line(t, 'PRINT "R=";ADVAL(-6)', "R=11")
    run_line(t, "SOUND &102,-15,61,4", ">")
    time.sleep(1.0)
    run_line(t, 'PRINT "R=";ADVAL(-6);ADVAL(-7)', "R=1515")
    run_line(t, "ENVELOPE 1,2,1,-1,0,4,4,0,20,-2,-1,-4,120,80", ">")
    run_line(t, "SOUND 2,1,89,10:SOUND 2,1,93,10", ">")
    time.sleep(2.5)
    run_line(t, 'PRINT "R=";ADVAL(-7)', "R=15")
    if not t.is_vice:                                # VICE's ENV3 differs
        run_line(t, 'SOUND 3,-15,89,40:T%=TIME:REPEAT UNTIL TIME>T%+20:'
                    'PRINT "R=";?&D41C', "R=255")
    run_line(t, "*SOUND SID", ">")


def test_sid_mode(t):
    # SID mode (the default): voices 0-23, instruments; ADVAL(-5-v); the
    # default instruments; *INSTRUMENT changes, SAVE/LOAD; on the U64 the
    # chip: voice 2 is SID 1's voice 3, ENV3 at &D41C (instrument 1 =
    # SQUARE, sustain 10 = 170; -5 = 85)
    run_line(t, "*SOUND", "SID mode")
    run_line(t, "SOUND 2,1,53,100:SOUND 2,1,55,100:SOUND 2,1,57,100", ">")
    run_line(t, 'PRINT "R=";ADVAL(-7);ADVAL(-5)', "R=715")   # one plays, two wait
    run_line(t, "*SOUND STOP", ">")
    run_line(t, 'PRINT "R=";ADVAL(-7)', "R=15")
    if not ult(t):
        run_line(t, "*INSTRUMENT 2", "Instruments need an REU")
        return
    run_line(t, "*INSTRUMENT 2", "PIANO")
    run_line(t, "*INSTRUMENT 16", "SYNC")
    run_line(t, "*INSTRUMENT 30 COPY 7 PULSE PW 1000 NAME TEST", ">")
    run_line(t, "*INSTRUMENT 30", "TEST       PULSE ADSR 0 8 4 8 PW 1000")
    run_line(t, "*INSTRUMENT SAVE INSTT", ">")
    run_line(t, "*INSTRUMENT DEFAULT", ">")
    run_line(t, "*INSTRUMENT 30", "SQUARE")
    run_line(t, "*INSTRUMENT LOAD INSTT", ">")
    run_line(t, "*INSTRUMENT 30", "TEST")
    run_line(t, "*INSTRUMENT DEFAULT", ">")
    run_line(t, "*DELETE INSTT", ">")
    run_line(t, 'SOUND 2,1,53,40:T%=TIME:REPEAT UNTIL TIME>T%+30:'
                'PRINT "R=";?&D41C', "R=170")
    run_line(t, 'SOUND &1002,-5,53,40:T%=TIME:REPEAT UNTIL TIME>T%+30:'
                'PRINT "R=";?&D41C', "R=85")
    # instrument + 256 * level: the level scales the instrument's sustain
    # (ORGAN: 15 -> 5; PLUCK, sustain 0, stays percussive)
    run_line(t, 'SOUND &1002,&0503,53,40:T%=TIME:REPEAT UNTIL TIME>T%+30:'
                'PRINT "R=";?&D41C', "R=85")
    run_line(t, 'SOUND &1002,&0F09,53,40:T%=TIME:REPEAT UNTIL TIME>T%+60:'
                'PRINT "R=";?&D41C', "R=0")
    run_line(t, "*SOUND STOP", ">")


def test_inst_mods(t):
    # step b2: the modulation parts of *INSTRUMENT (sweeps, vibrato,
    # portamento, finetune, hard restart, tables) are kept and listed; notes
    # with them play (on the U64: SID 1 voice 3's envelope reads back)
    if not ult(t):
        run_line(t, "*INSTRUMENT 31", "Instruments need an REU")
        return
    for line in ("*INSTRUMENT 31 COPY 1 PW 800 6 14 2",
                 "*INSTRUMENT 31 VIB 20 2 6 PORTA 16 FINE -3 RESTART",
                 "*INSTRUMENT 31 FILTER CUT 40 2 200 30 STOP",
                 "*INSTRUMENT 31 WAVES 65 65 255 0 ARP 0 4 7 SPEED 2"):
        run_line(t, line, ">")
    rows = run_line(t, "*INSTRUMENT 31", "SPEED")
    text = "".join(rows)                    # (40-column rows run on)
    for part in ("PW 800 6 14 2", "CUT 40 2 200 30", "STOP", "VIB 20 2 6",
                 "PORTA 16", "FINE -3", "RESTART", "WAVES 65 65 255",
                 "ARP 0 4 7", "SPEED 2"):
        assert part in text, (part, text)
    run_line(t, 'SOUND 2,31,53,40:SOUND 2,31,69,40:T%=TIME:'
                'REPEAT UNTIL TIME>T%+30:PRINT "R=";?&D41C', "R=")
    run_line(t, 'SOUND 2,15,53,20:T%=TIME:REPEAT UNTIL TIME>T%+20:'
                'PRINT "R=";?&D41C>0', "R=-1")      # ARP: tables
    run_line(t, "*SOUND STOP", ">")
    run_line(t, "*INSTRUMENT 31 COPY 1", ">")
    run_line(t, "*INSTRUMENT 31", "SQUARE")


def test_song(t):
    # *SONG: a song built with SOUND while recording, played in the
    # background (ADVAL(-29-v): the note of voice v), saved and loaded
    if not ult(t):
        run_line(t, "*SONG", "Songs need an REU")
        return
    run_line(t, "*SONG NEW 60", ">")
    run_line(t, "*SONG", "60 bpm, 4 rows per beat, 0 patterns")
    run_line(t, "*SONG RECORD", ">")
    run_line(t, "SOUND 0,1,53,4:SOUND 0,1,57,4:SOUND 0,1,61,4", ">")
    run_line(t, "SOUND 2,2,29,12", ">")
    run_line(t, 'PRINT "R=";ADVAL(-6)', "R=15")      # nothing queued
    run_line(t, "*SONG RECORD OFF", ">")
    run_line(t, "*SONG", "1 patterns")
    run_line(t, "*SONG TITLE TEST SONG", ">")
    run_line(t, "*SONG PLAY", ">")              # rows of 0.25 s
    run_line(t, 'PRINT "N=";ADVAL(-29);",";ADVAL(-31)', "N=49,43")
    run_line(t, "*SONG", "Playing")
    run_line(t, "T%=TIME:REPEAT UNTIL TIME>T%+350", ">")
    rows = run_line(t, "*SONG", "patterns")
    assert not any("Playing" in r for r in rows), rows   # it ended
    run_line(t, "*SONG SAVE TSONG", ">")
    run_line(t, "*SONG NEW", ">")
    run_line(t, "*SONG LOAD TSONG", ">")
    run_line(t, "*SONG", "TEST SONG")
    run_line(t, "*DELETE TSONG", ">")
    run_line(t, "*SOUND BBC", ">")
    run_line(t, "*SONG PLAY", "Songs play in SID mode")
    run_line(t, "*SOUND SID", ">")


def test_star_list(t):
    # *LIST: indented by structure (PROC bodies too), keywords spelt out,
    # line number constants decoded, ranges as LIST
    run_line(t, "NEW", ">")
    for line in ('10 DEF PROCa', '20 FOR I%=1 TO 2', '30 PRINT "FOR";I%',
                 '40 NEXT', '50 ENDPROC', '60 DEF FNb(X)', '70 =X*2',
                 '80 DEF FNc(X)=X', '90 REPEAT:UNTIL TRUE', '100 GOTO 30',
                 '110 REM FOR NEXT'):
        run_line(t, line, ">")
    rows = run_line(t, "*LIST", "110 REM FOR NEXT")
    want = ["   10 DEF PROCa", "   20   FOR I%=1 TO 2", '   30     PRINT "FOR";I%',
            "   40   NEXT", "   50 ENDPROC", "   60 DEF FNb(X)", "   70 =X*2",
            "   80 DEF FNc(X)=X", "   90 REPEAT:UNTIL TRUE", "  100 GOTO 30",
            "  110 REM FOR NEXT"]
    got = [r.rstrip() for r in rows if r[:5].strip().isdigit()]
    for w in want:
        assert w in got, (w, got)
    rows = run_line(t, "*LIST 20,40", ">")
    got = [r.rstrip() for r in rows if r[:5].strip().isdigit()]
    assert got[-3:] == want[1:4], got
    rows = run_line(t, "*LIST 70", ">")
    got = [r.rstrip() for r in rows if r[:5].strip().isdigit()]
    assert got[-1] == "   70 =X*2", got
    run_line(t, "NEW", ">")


def test_net(t):
    # *NET: the Ultimate's address; *NET GET through the firmware's HTTP
    # target (needs the internet: example.com over plain http)
    if not ult(t):
        run_line(t, "*NET", "No Ultimate")
        return
    run_line(t, "*NET", "Gateway")
    run_line(t, "*NET GET http://example.com/ /Temp/TNET", "bytes", timeout=60)
    run_line(t, "*TYPE /Temp/TNET", "</html>")
    # (no 404 check: firmware 3.15a's raw exchange returns no status, so
    # an error page is saved like any reply; DESIGN_NETWORK.md section 8)
    run_line(t, "*DELETE /Temp/TNET", ">")
    rows = run_line(t, "*NET TIME", ">", timeout=30)   # the firmware's SNTP
    assert any(r.count(":") == 2 for r in rows), rows  # "Sat,10 Oct 2026.08:00:00"
    run_line(t, "*NET RANDOM", "RND seeded", timeout=60)


def test_json(t):
    # *JSON through the firmware's HTTP target (needs the internet); the
    # BASIC library (demos/net/JSONLIB) through OSWORD &70
    if not ult(t):
        run_line(t, "*JSON message", "No Ultimate")
        return
    run_line(t, "*JSON GET http://api.open-notify.org/iss-now.json", ">", timeout=60)
    run_line(t, "*JSON message", "success")
    rows = run_line(t, "*JSON timestamp", ">")
    assert any(r.strip().isdigit() for r in rows), rows
    run_line(t, "*JSON nothere", "element nothere")   # (firmware: 400 ...)
    lib = open(os.path.join(os.path.dirname(__file__), "..", "..", "demos", "net",
                            "JSONLIB.bas")).read()
    prog = ('10 PROCjsoninit\n'
            '20 PRINT "T=";FNjsontype("iss_position");" C=";FNjsoncount("iss_position")\n'
            '30 PRINT "M=";FNjson("message")\n'
            '40 PRINT "N=";FNjsonnum("timestamp")>1E9\n'
            '50 END\n' + lib)
    out = remote(t).send_program(prog, run=True, timeout=60)["output"]
    assert "T=4 C=2" in out and "M=success" in out and "N=-1" in out, out


def test_netchan(t):
    # network channels: OPENIN "http://..." read as a file; a TCP socket
    # (an HTTP request sent by hand to example.com:80, the reply's first line)
    if not ult(t):
        run_line(t, 'F%=OPENIN "TCP:example.com:80"', "No Ultimate")
        return
    prog = '''10 F%=OPENIN "http://example.com/"
20 PRINT "H=";EXT#F%>100;
30 A$="":FOR I%=1 TO 15:A$=A$+CHR$BGET#F%:NEXT
40 PRINT " ";A$:CLOSE#F%
50 F%=OPENUP "TCP:example.com:80"
60 PROCsend("GET / HTTP/1.0"):PROCsend("Host: example.com"):PROCsend("")
70 A$="":REPEAT C%=BGET#F%:IF C%>31 A$=A$+CHR$C%
80 UNTIL C%=10 OR EOF#F%
90 PRINT "T=";LEFT$(A$,12)
100 REPEAT C%=BGET#F%:UNTIL EOF#F%
110 PRINT "E=";EOF#F%:CLOSE#F%
120 END
130 DEF PROCsend(A$)
140   LOCAL I%
150   IF A$<>"" FOR I%=1 TO LEN A$:BPUT#F%,ASC MID$(A$,I%,1):NEXT
160   BPUT#F%,13:BPUT#F%,10
170 ENDPROC
'''
    out = remote(t).send_program(prog, run=True, timeout=90)["output"]
    assert "h=-1 <!doctype html>" in out.lower(), out
    assert "T=HTTP/1.0 200" in out or "T=HTTP/1.1 200" in out, out
    assert "E=-1" in out, out
    # UDP: an NTP request (48 bytes, PTR#=0 sends the datagram), the reply's
    # first byte has mode 4 (server) in its low 3 bits, 48 bytes long
    prog = """10 F%=OPENUP "UDP:pool.ntp.org:123"
20 BPUT#F%,&1B:FOR I%=2 TO 48:BPUT#F%,0:NEXT:PTR#F%=0
30 T%=TIME:REPEAT UNTIL EXT#F%>0 OR TIME>T%+500
40 N%=EXT#F%:B%=BGET#F%:PRINT "N=";N%;" M=";B% AND 7
50 CLOSE#F%:END
"""
    out = remote(t).send_program(prog, run=True, timeout=60)["output"]
    assert "N=48 M=4" in out, out


def test_classics(t):
    # the BBC Micro classics in demos/classics run (a few seconds each,
    # then stopped): persian and polygon draw without an error; animal
    # starts (without its ANIMAL.DAT it uses its four built-in lines)
    d = os.path.join(os.path.dirname(__file__), "..", "..", "demos", "classics")
    rm = remote(t)
    progs = []
    if ult(t):                          # (OPENIN needs the filing system)
        # its knowledge file in /Temp (the current directory): read with
        # INPUT# (6502 PRINT# format; the Z80 original gave Type mismatch)
        with ftplib.FTP(t.host, timeout=20) as ftp:
            ftp.login("anonymous", "")
            with open(os.path.join(d, "ANIMAL.DAT"), "rb") as f:
                ftp.storbinary("STOR /Temp/ANIMAL.DAT", f)
        progs.append(("animal", "refresh my memory"))
    # (animal first: after MODE 2, Upic Lite, BASIC runs at 1/6 speed)
    progs += [("persian", None), ("polygon", None)]
    for name, want in progs:
        r = rm.send_program(open(os.path.join(d, name + ".bas")).read(),
                            run=True, timeout=12)
        if name == "animal":            # no animal; don't save: it ends
            rm.wait_line_wanted(30)     # (reading the file takes a while)
            first = rm.run_lines(["N"], timeout=30)  # lists what it knows
            rm.wait_line_wanted(30)
            out = rm.run_lines(["N"], timeout=30)    # don't save: it ends
            assert out["state"] == "prompt", out
            assert "know are" in first["output"], first
            assert "gnat" in first["output"], first  # the file's animals
            run_line(t, "*DELETE ANIMAL.DAT", ">")
        else:
            rm.stop()
            rm.wait_line_wanted(10)     # (else a second ESCAPE follows)
        assert not r["error"], (name, r)
        if want:
            assert want in r["output"], (name, r["output"])
    rm.run_lines(["MODE 100"])


def test_reu_irq(t):
    # REU transfers from BASIC while the SID engine's interrupt reads its
    # instrument tables from the REU (eight ARP voices): the interrupt
    # keeps the REU's registers, so no transfer goes wrong (before the
    # fix, 314 of 483 did; a line editor history UP crashed the machine)
    if t.is_vice:
        return
    prog = "\n".join([
        "10 DIM B% 300,C% 300,K% 16",
        "20 FOR I%=0 TO 255:B%?I%=I%:NEXT",
        "30 FOR V%=1 TO 8:SOUND V%,15,60+V%*8,255:NEXT",
        "40 E%=0:N%=0:T%=TIME",
        "50 REPEAT",
        "60   K%?0=&80:K%?1=B% MOD 256:K%?2=B% DIV 256:K%?5=0:K%?6=1:K%?7=4:K%?8=0:K%?9=N% MOD 256",
        "70   A%=&42:X%=K% MOD 256:Y%=K% DIV 256:CALL &C7F1",
        "80   FOR J%=0 TO 255:C%?J%=0:NEXT",
        "90   K%?0=0:K%?1=C% MOD 256:K%?2=C% DIV 256",
        "100  A%=&42:X%=K% MOD 256:Y%=K% DIV 256:CALL &C7F1",
        "110  F%=0:FOR J%=0 TO 255:IF C%?J%<>J% F%=1",
        "120  NEXT:E%=E%+F%:N%=N%+1",
        "130 UNTIL TIME>T%+500",
        "140 FOR V%=1 TO 8:SOUND &10+V%,0,0,1:NEXT",
        '150 PRINT "E=";E%;" N=";N%', ""])
    r = remote(t).send_program(prog, run=True, timeout=30)
    assert "E=0 " in r["output"], r
    run_line(t, "*SOUND SID", ">")


def test_snapshot(t):
    # *SNAPSHOT: program and variables into a slot and back; the mode
    # with them; a slot to a file and back; refused in a running program
    if t.is_vice:
        run_line(t, "*SNAPSHOT 1", "need an REU")
        return
    ult(t)                              # current directory /Temp
    rm = remote(t)
    rm.run_lines(["NEW", '10 PRINT "SNAP ";X%', 'X%=42:A$="HELLO"', "*SNAPSHOT 1"])
    rm.run_lines(["NEW", 'X%=7:A$="BYE"', "*SNAPSHOT LOAD 1"])
    out = rm.run_lines(['PRINT X%;" ";A$', "RUN"])["output"]
    assert "42 HELLO" in out and "SNAP 42" in out, out
    out = rm.run_lines(["*SNAPSHOT"])["output"]
    assert re.search(r"^1 .*MODE 100", out, re.M), out
    rm.run_lines(["MODE 7", "*SNAPSHOT 2", "MODE 100", "*SNAPSHOT LOAD 2"])
    out = rm.run_lines(["A%=&87:M%=(USR&C7F4 AND &FF0000) DIV &10000",
                        "MODE 100", 'PRINT "M=";M%'])["output"]
    assert "M=7" in out, out
    rm.run_lines(["*SNAPSHOT SAVE 1 SNAPTEST", "NEW", "*SNAPSHOT LOAD SNAPTEST"])
    out = rm.run_lines(["RUN"])["output"]
    assert "SNAP 42" in out, out
    run_line(t, "*DELETE SNAPTEST", ">")
    run_line(t, "*SNAPSHOT 10", "Bad slot")
    r = rm.send_program('10 OSCLI "SNAPSHOT 3"\n', run=True, timeout=10)
    assert r["error"] and "prompt only" in r["error"]["message"], r
    run_line(t, "NEW", ">")


def test_sprite(t):
    # *SPRITE: the multiplexer below HIMEM; a red sprite in the video
    # stream; two overlapping sprites collide (OSWORD &71); MODE hides
    # them; *SPRITE OFF gives HIMEM back
    if t.is_vice:
        run_line(t, "*SPRITE ON", "need an REU")
        return
    rm = remote(t)
    rm.run_lines(["MODE 100", "CLS"])
    out = rm.run_lines(["*SPRITE ON", "PRINT ~HIMEM"])["output"]
    assert "7B00" in out, out
    prog = "\n".join([
        "10 *SPRITE DEFINE 0 " + "F" * 126,
        "20 *SPRITE 0 ON 640,300",
        "30 *SPRITE 0 COLOUR 1",
        "40 *SPRITE 1 ON 660,300",
        "50 *SPRITE 1 COLOUR 2",
        "60 T%=TIME:REPEAT UNTIL TIME>T%+10",
        "70 DIM B% 10:B%?0=0:B%?1=4:A%=&71:X%=B% MOD 256:Y%=B% DIV 256:CALL &C7F1",
        '80 PRINT "C=";B%?6', ""])
    r = rm.send_program(prog, run=True, timeout=20)
    assert "C=1" in r["output"] or "C=3" in r["output"], r
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import u64shot
    rows = u64shot.grab(t.host, 11002)
    red = sum(row.count(2) for row in rows)
    assert red > 300, red                   # sprite 0: 24 x 21, partly under 1
    out = rm.run_lines(["MODE 100", "*SPRITE"])["output"]
    assert "Sprites on" in out and " shape " not in out, out
    out = rm.run_lines(["*SPRITE OFF", "PRINT ~HIMEM"])["output"]
    assert "8000" in out, out


def test_sprite_gfx(t):
    # sprites in a VIC-II graphics mode (MODE 129) and MODE 7: shapes from
    # a SpritePad file (*SPRITE LOAD) copied into the two blocks by the
    # multiplexer; each sprite's colour counts its shape's dots in the
    # video stream; a multicolour sprite (MULTI, COLOURS)
    if not ult(t):
        return
    full = bytes([255] * 63 + [0])                       # 504 dots
    left = bytes([255, 240, 0] * 21 + [0])               # 12 a row: 252
    top = bytes([255] * 30 + [0] * 33 + [0])             # 10 rows: 240
    spd = b"SPD" + bytes([1, 2, 0, 0, 0, 0]) + full + left + top
    with ftplib.FTP(t.host, timeout=20) as ftp:
        ftp.login("anonymous", "")
        ftp.storbinary("STOR /Temp/SHAPES.SPD", io.BytesIO(spd))
    rm = remote(t)
    rm.run_lines(["MODE 100", "*SPRITE ON", "MODE 129"])
    prog = "\n".join([
        "10 *SPRITE LOAD 10 SHAPES.SPD",
        "20 *SPRITE 0 SHAPE 10",
        "30 *SPRITE 0 COLOUR 1",
        "40 *SPRITE 0 ON 100,800",
        "50 *SPRITE 1 SHAPE 11",
        "60 *SPRITE 1 COLOUR 2",
        "70 *SPRITE 1 ON 400,600",
        "80 *SPRITE 2 SHAPE 12",
        "90 *SPRITE 2 COLOUR 3",
        "100 *SPRITE 2 ON 700,400",
        "110 *SPRITE COLOURS 5,6",
        "120 *SPRITE 3 SHAPE 10",
        "130 *SPRITE 3 MULTI ON",
        "140 *SPRITE 3 ON 1000,200", ""])
    r = rm.send_program(prog, run=True, timeout=20)
    assert r["ok"], r
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import u64shot
    time.sleep(0.5)
    rows = u64shot.grab(t.host, 11002)
    count = {c: sum(row.count(c) for row in rows) for c in (2, 5, 7, 3)}
    assert 480 <= count[2] <= 530, count                 # red: full
    assert 240 <= count[5] <= 265, count                 # green: left half
    assert 230 <= count[7] <= 250, count                 # yellow: top rows
    assert 480 <= count[3] <= 530, count                 # cyan: multicolour
    rm.run_lines(["MODE 7", "*SPRITE 0 SHAPE 11", "*SPRITE 0 COLOUR 1",
                  "*SPRITE 0 ON 600,500"])
    time.sleep(0.5)
    rows = u64shot.grab(t.host, 11002)
    red = sum(row.count(2) for row in rows)
    assert 240 <= red <= 265, red
    # MODE 7 -> a bitmap mode: hung once (the mode set $0314 under the
    # multiplexer's raster interrupt)
    out = rm.run_lines(["MODE 129", "*SPRITE", "MODE 100", "*SPRITE OFF",
                        "PRINT ~HIMEM", "*DELETE SHAPES.SPD"])["output"]
    assert "Sprites on at &7B00" in out, out
    assert "8000" in out, out


def upic_bars():
    """A Upic v1.3 file: 16 bars of 24 pixels in colours 0-15."""
    import struct
    hdr = bytearray(256)
    hdr[0:8] = b"Upic1.3\xae"
    hdr[8:16] = struct.pack("<4H", 384, 256, 16, 49152)
    hdr[0x30:0xD0] = b" " * 160
    hdr[0xD0:0x100] = bytes(range(48))
    bm = bytearray(49152)
    for c in range(192):
        v = (c * 2) // 24
        bm[c * 256:(c + 1) * 256] = bytes([v | v << 4]) * 256
    return bytes(hdr) + bytes(bm)


def upic_show(t, rm, program, check):
    """Run program (which shows the picture); while it shows, check(rows)
    on a frame from the video stream, with no memory reads meanwhile (each
    stops the CPU: a disturbed line in Upic); then end the show. Returns
    the program's result."""
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import u64shot
    image = bbctok.tokenise_program(program)
    page, _ = rm.page_himem()
    st = rm.ensure_prompt()
    rm.errors_before = st["error_count"]
    rm.capture(True)
    rm.drain()
    rm.write(page, image)
    rm.post(u64remote.REQ_PROGRAM, bytes([1]))
    deadline = time.time() + 20
    while rm.read(u64remote.UP_SIG, 1)[0] != u64remote.UP_SHOWING:
        assert time.time() < deadline, "no show"
        time.sleep(0.2)
    time.sleep(1.0)
    try:
        check(u64shot.grab(t.host, 11002))
    finally:
        rm.end_show()
    return rm.run_lines([], timeout=20, prepared=True)


def test_upic(t):
    # Upic full's picture: *UPIC LOAD (v1.3), SHOW from a program (the
    # bars in the video stream, pixel-exact; the program goes on with its
    # variables), SAVE (the same bytes), CLEAR c (every pixel c)
    if t.is_vice:
        run_line(t, "*UPIC CLEAR", "REU of 1 MB")
        return
    if not ult(t):
        return
    data = upic_bars()
    with ftplib.FTP(t.host, timeout=20) as ftp:
        ftp.login("anonymous", "")
        ftp.storbinary("STOR /Temp/BARS.UPIC", io.BytesIO(data))
    rm = remote(t)
    rm.run_lines(["MODE 100", "*UPIC LOAD BARS.UPIC"])

    def bars(rows):
        shown = [row for row in rows if row.count(1) == 24]
        assert len(shown) == 256, len(shown)    # every picture line
        for row in shown:
            runs, prev = [], None
            for c in row:
                if c == prev:
                    runs[-1][1] += 1
                else:
                    runs.append([c, 1])
                    prev = c
            assert runs == [[i, 24] for i in range(16)], runs
    r = upic_show(t, rm, "10 A$=\"intact\"\n20 *UPIC SHOW\n30 PRINT A$\n", bars)
    assert "intact" in r.get("output", ""), r
    rm.run_lines(["*UPIC SAVE COPY.UPIC"])
    got = io.BytesIO()
    with ftplib.FTP(t.host, timeout=20) as ftp:
        ftp.login("anonymous", "")
        ftp.retrbinary("RETR /Temp/COPY.UPIC", got.write)
    assert got.getvalue() == data, (len(got.getvalue()), len(data))
    rm.run_lines(["*UPIC CLEAR 3"])

    def cyan(rows):
        n = sum(row.count(3) for row in rows)
        assert n == 384 * 256, n
    upic_show(t, rm, "10 *UPIC SHOW\n", cyan)
    rm.run_lines(["*DELETE BARS.UPIC", "*DELETE COPY.UPIC"])


def test_upic_mode(t):
    # MODE 110/111: text on the console, graphics into the REU picture;
    # dot counts per colour in the video stream while it shows; POINT;
    # MODE 111's 288 logical pixels (3 of every 4); back to MODE 100
    if t.is_vice:
        return                                  # (no REU in VICE)
    rm = remote(t)

    def counts(rows):
        from collections import Counter
        return Counter(c for row in rows for c in row)
    got = {}
    prog = "\n".join([
        "10 MODE 110",
        "20 GCOL 0,1:MOVE 0,0:PLOT 101,767,511",
        "30 GCOL 0,2:MOVE 768,1023:DRAW 1535,512",
        "40 PRINT \"P=\";POINT(100,100);\",\";POINT(1000,100);\",\";POINT(1532,515)",
        "50 *UPIC SHOW",
        "60 PRINT \"back\"", ""])
    r = upic_show(t, rm, prog, lambda rows: got.update(counts(rows)))
    assert "P=1,0,2" in r["output"] and "back" in r["output"], r
    assert got[1] == 24576 and got[2] == 192, got   # 192 x 128; 192 dots
    got.clear()
    prog = "\n".join([
        "10 MODE 111",
        "20 GCOL 0,129:CLG",
        "30 GCOL 0,3:MOVE 0,0:PLOT 101,767,511",
        "40 *UPIC SHOW", ""])
    upic_show(t, rm, prog, lambda rows: got.update(counts(rows)))
    # 768 units = 144 logical pixels (x 3 / 16) = 48 groups of 4 = 192
    # dots, x 128 lines
    assert got[3] == 24576 and got[1] == 98304 - 24576, got
    out = rm.run_lines(["*SPRITE ON"])["output"]
    assert "VIC-II mode" in out, out
    out = rm.run_lines(["MODE 100", "PRINT ~HIMEM"])["output"]
    assert "8000" in out, out


def test_upic_auto(t):
    # MODE 110's automatic shows: in GET (a key ends it and is GET's), in a
    # long INKEY (at most that long; TIME goes on, so INKEY times out),
    # nothing at the prompt when nothing new was drawn; *UPIC AUTO OFF
    if t.is_vice:
        return
    rm = remote(t)
    prog = "\n".join([
        "10 MODE 110",
        "20 GCOL 0,1:PLOT 69,100,100",
        "30 K%=GET",
        "40 PLOT 69,200,200",
        "50 T%=TIME:I%=INKEY(100)",
        '60 PRINT "R=";K%;",";I%;",";TIME-T%', ""])
    image = bbctok.tokenise_program(prog)
    page, _ = rm.page_himem()
    st = rm.ensure_prompt()
    rm.errors_before = st["error_count"]
    rm.capture(True)
    rm.drain()
    rm.write(page, image)
    rm.post(u64remote.REQ_PROGRAM, bytes([1]))

    def showing(timeout):
        end = time.time() + timeout
        while time.time() < end:
            if rm.read(u64remote.UP_SIG, 1)[0] == u64remote.UP_SHOWING:
                return True
            time.sleep(0.3)
        return False
    assert showing(20), "no show in GET"
    rm.end_show()
    time.sleep(0.5)
    rm.write(0x0277, [0x41])                    # the key GET then reads
    rm.write(0xC6, [1])
    assert showing(10), "no show in INKEY"
    r = rm.run_lines([], timeout=20, prepared=True)
    m = re.search(r"R=(\d+),(-?\d+),(\d+)", r["output"])
    assert m and m.group(1) == "97" and m.group(2) == "-1", r
    assert 95 <= int(m.group(3)) <= 130, r     # INKEY(100): about 1 s
    assert rm.state()["state"] == "prompt", "shown at the prompt"
    out = rm.run_lines(["*UPIC AUTO OFF", "PLOT 69,300,300",
                        "PRINT \"none\""])["output"]
    assert "none" in out and rm.state()["state"] == "prompt", out
    rm.run_lines(["MODE 100", "*UPIC AUTO ON"])    # (on in MODE 110: the
                                                # PLOT above would show)


def test_bv_cmds(t):
    # BASIC V graphics as * commands: each shape where POINT finds it,
    # arguments as numbers or A%-Z%; *GCOL c TINT t the nearest palette
    # colour (REU: the Ultimates only)
    prog = "\n".join([
        "10 MODE 132",
        "20 *RECTANGLE FILL 100,100,200,100",
        "30 *CIRCLE FILL 640,512,100",
        "40 *LINE 0,900,1279,900",
        "50 X%=1000:Y%=700:*POINT X%,Y%",
        "60 *ELLIPSE FILL 1000,300,100,50",
        "70 *RECTANGLE 400,100,100",
        "80 *COLOUR 1,255,255,255",
        "90 PRINT \"R=\";POINT(150,150);POINT(50,50);POINT(640,512);"
        "POINT(640,900);POINT(1000,700);POINT(1000,300);POINT(400,150);"
        "POINT(450,150)", ""])
    r = remote(t).send_program(prog, run=True, timeout=30)["output"]
    assert "R=10111110" in r.replace(" ", ""), r
    if t.is_vice:
        r = remote(t).run_lines(["MODE 100", "*GCOL 3 TINT 0"])
        assert r["error"] and "TINT needs an REU" in r["error"]["message"], r
        return
    prog = "\n".join([
        "10 MODE 129",
        "20 *GCOL 3 TINT 192",
        "30 PLOT 69,100,100",
        "40 *GCOL 0,63 TINT 192",
        "50 PLOT 69,200,200",
        "60 PRINT \"G=\";POINT(100,100);POINT(200,200)", ""])
    r = remote(t).send_program(prog, run=True, timeout=30)["output"]
    assert "G=13" in r.replace(" ", ""), r
    remote(t).run_lines(["MODE 100"])


def test_mode1_font(t):
    # MODE 1 on the VIC-II (MODE 129): the 4x6 font in the REU font while
    # it is on (OSWORD 10 reads the glyph the graphics modes draw), the
    # normal glyphs back after it (REU: the Ultimates only)
    if t.is_vice:
        return
    prog = "\n".join([
        "10 DIM B% 9",
        "20 MODE 132:PROCa:N$=G$",
        "30 MODE 129:PROCa:F$=G$",
        "40 MODE 132:PROCa:M$=G$",
        "50 MODE 100",
        '60 PRINT "F=";F$;" ";N$=M$;" ";N$=F$',
        "70 END",
        "80 DEF PROCa",
        "90   ?B%=65:A%=10:X%=B% MOD 256:Y%=B% DIV 256:CALL &C7F1",
        '100   G$="":FOR I%=1 TO 8:G$=G$+STR$~B%?I%+",":NEXT',
        "110 ENDPROC", ""])
    r = remote(t).send_program(prog, run=True, timeout=30)["output"]
    assert "F=40,A0,E0,A0,A0,0,0,0," in r and "-1 0" in r, r


def gxr_file(sprites):
    """A GXR sprite file (BBC Micro / Master format, checked against the
    GXR sprite disc): length (2), count, then per sprite width in bytes -
    1, height - 1, data size (2), mode, number and the mode's screen
    bytes, rows top to bottom, each row's bytes right to left.
    sprites: [(number, mode, rows of logical colours)]."""
    def enc(px, mode):
        if mode == 2:
            b = 0
            for i, c in enumerate(px):          # pixel i: bits 7-i,5-i,3-i,1-i
                for k, bit in enumerate((3, 2, 1, 0)):
                    if c >> bit & 1:
                        b |= 1 << (7 - i - 2 * k)
            return b
        b = 0                                   # MODE 1/5: bits 7-i, 3-i
        for i, c in enumerate(px):
            b |= (c >> 1 & 1) << (7 - i) | (c & 1) << (3 - i)
        return b
    body = bytearray()
    for num, mode, rows in sprites:
        ppb = 2 if mode == 2 else 4
        wb = len(rows[0]) // ppb
        data = bytearray()
        for row in rows:
            bs = [enc(row[i * ppb:(i + 1) * ppb], mode) for i in range(wb)]
            data += bytes(bs[::-1])
        body += bytes([wb - 1, len(rows) - 1, len(data) & 255, len(data) >> 8,
                       mode, num]) + data
    n = len(body) + 3
    return bytes([n & 255, n >> 8, len(sprites)]) + bytes(body)


def test_gxr(t):
    # GXR software sprites (docs/DESIGN_SPRITES.md 6): *SGET, PLOT 237,
    # EOR erases, *SMASK; a replaced sprite; *SRENUMBER, *SDELETE; *SSAVE
    # and *SLOAD back; VDU 23,27; GXR files decoded (MODE 2 and 1)
    if t.is_vice:
        run_line(t, "*SNEW", "Sprites need an REU")
        return
    if not ult(t):
        return
    rm = remote(t)
    prog = "\n".join([
        "10 MODE 132",
        "20 GCOL 0,1:*CIRCLE FILL 100,100,60",
        "30 MOVE 40,40:MOVE 160,160:*SGET 1",
        "40 MOVE 40,40:MOVE 160,160:*SGET 1",
        "50 GCOL 0,0:PLOT 237,600,600",
        '60 A$=STR$POINT(660,660)+STR$POINT(600,600)',
        "70 GCOL 3,0:PLOT 237,600,600",
        "80 A$=A$+STR$POINT(660,660)",
        "90 *SMASK 1 0",
        "100 GCOL 0,1:*RECTANGLE FILL 800,300,200,200",
        "110 GCOL 0,0:PLOT 237,820,320",
        "120 A$=A$+STR$POINT(830,330)+STR$POINT(880,380)",
        "130 *SRENUMBER 1,5",
        "140 *SCHOOSE 5",
        "150 GCOL 0,0:PLOT 237,300,700",
        "160 A$=A$+STR$POINT(360,760)",
        "170 *SSAVE GXRT",
        "180 *SNEW",
        "190 *SLOAD GXRT",
        "200 VDU 23,27,0,5,0,0,0,0,0,0",
        "210 PLOT 237,1000,700",
        "220 A$=A$+STR$POINT(1060,760)",
        "230 *SDELETE 5",
        '240 PRINT "R=";A$', ""])
    rm.run_lines(["*DIR /Temp"])
    r = rm.send_program(prog, run=True, timeout=60)
    assert "R=1001111" in r["output"], r
    out = rm.run_lines(["*SCHOOSE 5"])
    assert out["error"] and "exist" in out["error"]["message"], out
    # GXR files: a MODE 2 sprite (2 x 2 bytes: 4 x 2 pixels) and a MODE 1
    # one (1 byte: 4 x 1); POINT reads them back
    m2 = [[1, 2, 9, 15], [0, 7, 8, 3]]
    m1 = [[0, 1, 2, 3]]
    data = gxr_file([(7, 2, m2), (8, 1, m1)])
    with ftplib.FTP(t.host, timeout=20) as ftp:
        ftp.login("anonymous", "")
        ftp.storbinary("STOR /Temp/GXRF", io.BytesIO(data))
    prog = "\n".join([
        "10 MODE 2",
        "20 *SLOAD GXRF",
        "30 *SCHOOSE 7",
        "40 GCOL 0,0:PLOT 237,0,0",
        '50 A$="":FOR R%=0 TO 1:FOR C%=0 TO 3',
        '60 A$=A$+CHR$(48+POINT(C%*8+4,(1-R%)*4+2)):NEXT:NEXT',
        "70 *SCHOOSE 8",
        "80 PLOT 237,0,100",
        '90 FOR C%=0 TO 3:A$=A$+CHR$(48+POINT(C%*8+4,102)):NEXT',
        '100 PRINT "G=";A$', ""])
    r = rm.send_program(prog, run=True, timeout=60)
    want = "".join(chr(48 + c) for c in m2[0] + m2[1] + m1[0])
    assert "G=" + want in r["output"], (want, r)
    rm.run_lines(["MODE 100", "*SNEW", "*DELETE GXRT", "*DELETE GXRF"])


def test_sound_none(t):
    # *SOUND NONE: no engine, PAGE may go down to &900 (OSBYTE &83 says so);
    # SID / BBC refuse while PAGE is lower than &1D00, then work again
    # (SIDs found again, SOUND queues)
    run_line(t, "*SOUND NONE", ">")
    run_line(t, "*SOUND", "None")
    run_line(t, 'A%=&83:H%=(USR&C7F4 AND &FF0000) DIV &10000:PRINT "H=";~H%', "H=9")
    run_line(t, 'SOUND 1,1,53,10:PRINT "R=";ADVAL(-6)', "R=15")
    run_line(t, "PAGE=&900", ">")
    run_line(t, "NEW", ">")
    run_line(t, '10 PRINT "LOW PAGE"', ">")
    run_line(t, "RUN", "LOW PAGE")
    run_line(t, "*SOUND SID", "PAGE is below &1D00")
    run_line(t, "PAGE=&1D00", ">")
    run_line(t, "NEW", ">")
    run_line(t, "*SOUND SID", ">")
    run_line(t, "*SOUND", "SID mode, on")
    run_line(t, 'A%=&83:H%=(USR&C7F4 AND &FF0000) DIV &10000:PRINT "H=";~H%', "H=1D")
    rows = run_line(t, 'SOUND 1,1,53,100:SOUND 1,1,55,100:PRINT "R=";ADVAL(-6)', "R=")
    assert any(r.startswith("R=11") or r.startswith("R=7") for r in rows), rows
    # (7: the first not started by an interrupt yet)
    run_line(t, "*SOUND STOP", ">")
    run_line(t, "*SOUND BBC", ">")
    run_line(t, "*SOUND", "BBC mode, on")
    run_line(t, "*SOUND SID", ">")
    rows = run_line(t, "*SID", "&D400")
    assert any("&D400" in r for r in rows), rows


def test_sid(t):
    # *SID lists the SIDs probed at start-up (VICE: one at $D400); *SID
    # PAN/VOL set the Ultimate's mixer through a loaded .cfg (UCI $50), here
    # to the values the cartridge's own .cfg sets; a bad value is refused
    rows = run_line(t, "*SID", "&D400")
    assert any("SID" in r and "&D400" in r for r in rows), rows
    if not ult(t):
        run_line(t, "*SID PAN 1 -3", "No Ultimate command interface")
        run_line(t, "*SID SETUP", "No Ultimate command interface")
        return
    # the cartridge started over REST gets no .cfg: start-up set up the
    # 8 SIDs itself; *SID SETUP does it again
    run_line(t, "*SID", "8 SIDs")
    run_line(t, "*SID SETUP", ">")
    run_line(t, "*SID", "8 SIDs")
    run_line(t, "*TYPE /Temp/bbcmix.cfg", "Range Split=1/4")
    for line in ("*SID VOL 1 -6", "*SID VOL 2 -6", "*SID PAN 1 -3",
                 "*SID PAN 2 3"):
        rows = run_line(t, line + ':PRINT "R=OK"', ">")
        assert not any("rror" in r or "errors" in r for r in rows), rows
    run_line(t, "*TYPE /Temp/bbcmix.cfg", "Pan UltiSID 2=Right 3")
    run_line(t, "*SID PAN 1 9", "Syntax")
    run_line(t, "*SID VOL 1 -41", ">")     # rounded to the firmware's -42
    run_line(t, "*SID VOL 1 -6", ">")


def test_text_colours(t):
    # text screen: COLOUR 128+n = reverse video in colour n (screen codes
    # with bit 7, colour RAM = n's C64 colour); COLOUR 128 ends it; VDU
    # 19,0,n sets the screen background ($D021)
    run_line(t, 'COLOUR 130:PRINT "AB";:COLOUR 128:PRINT "C"', "ABC")
    rows = screen.read_screen(t.bridge)
    row = next(i for i, r in enumerate(rows) if r.startswith("ABC"))
    codes = bytes(t.bridge.read(0xC000 + 40 * row, 3))
    assert codes[0] & 0x80 and codes[1] & 0x80 and not codes[2] & 0x80, codes.hex()
    if not t.is_vice:
        col = bytes(t.bridge.read(0xD800 + 40 * row, 2))
        assert col[0] & 15 == 5, col.hex()            # BBC green = C64 5
    run_line(t, "VDU 19,0,4,0,0,0", ">")
    assert bytes(t.bridge.read(0xD021, 1))[0] & 15 == 6   # BBC blue = C64 6
    run_line(t, "VDU 19,0,0,0,0,0", ">")


def test_reu_storage(t):
    # *SRWRITE / *SRREAD and OSWORD &42: a pattern to the REU and back
    if t.is_vice:
        run_line(t, "*SRWRITE &4000 +16 &40000", "No REU")
        return
    run_line(t, "FOR I%=0 TO 255:I%?&4000=I%:NEXT", ">")
    run_line(t, "*SRWRITE &4000 +256 &40100", ">")
    run_line(t, "FOR I%=0 TO 255:I%?&4000=0:NEXT", ">")
    run_line(t, "*SRREAD &4100 &4200 &40100", ">")
    run_line(t, 'PRINT "R=";?&4100;",";?&41FF;",";?&4000', "R=0,255,0")
    run_line(t, "DIM B% 10:B%?0=0:B%!1=&4200:B%?5=0:B%?6=1", ">")
    run_line(t, "B%?7=4:B%?8=0:B%?9=1:A%=&42:X%=B%:Y%=B% DIV 256:CALL &C7F1", ">")
    run_line(t, 'PRINT "R=";?&4280', "R=128")
    run_line(t, "*SRWRITE &4000 +16 &3FFF0", "Bad address")
    run_line(t, "*SRREAD &1000 +16 &40000", "Bad address")


def test_ramdisk(t):
    # the REU RAM disk as /REU: SAVE/LOAD, *SAVE/*LOAD, *CAT, *RENAME,
    # *DELETE, *TYPE, *COPY both ways, full names from elsewhere
    if t.is_vice:
        run_line(t, "*DIR /REU", "No RAM disk")
        return
    ult(t)                                      # current directory /Temp
    run_line(t, "*DIR /REU", ">")
    run_line(t, "*PWD", "/REU")
    run_line(t, "NEW", ">")
    run_line(t, '10 PRINT "RAMDISK OK"', ">")
    run_line(t, 'SAVE "TPROG"', ">")
    run_line(t, "NEW", ">")
    run_line(t, 'LOAD "TPROG"', ">")
    run_line(t, "RUN", "RAMDISK OK")
    run_line(t, "FOR I%=0 TO 99:I%?&4000=I%:NEXT", ">")
    run_line(t, "*SAVE TDATA &4000 +100", ">")
    run_line(t, "*LOAD TDATA &5000", ">")
    run_line(t, 'PRINT "R=";?&5000;",";?&5063', "R=0,99")
    run_line(t, "*RENAME TDATA TDAT2", ">")
    rows = run_line(t, "*CAT", "files")
    assert any("TDAT2" in r for r in rows) and any("TPROG" in r for r in rows), rows
    run_line(t, "*DELETE TPROG", ">")
    rows = run_line(t, "*CAT", "files")
    assert not any("TPROG" in r for r in rows), rows
    run_line(t, "*DIR ..", ">")
    run_line(t, "*PWD", "/Temp")
    rows = run_line(t, "*CAT /REU", "files")
    assert any("TDAT2" in r for r in rows), rows
    run_line(t, 'F%=OPENOUT "/Temp/TTEXT":A$="HELLO REU"', ">")
    run_line(t, "FOR I%=1 TO LEN A$:BPUT#F%,ASC MID$(A$,I%,1):NEXT:CLOSE#F%", ">")
    run_line(t, "*COPY /Temp/TTEXT /REU", ">")
    run_line(t, "*TYPE /REU/TTEXT", "HELLO REU")
    run_line(t, "*COPY /REU/TDAT2 /Temp", ">")
    run_line(t, "*LOAD /Temp/TDAT2 &6000", ">")
    run_line(t, 'PRINT "R=";?&6063', "R=99")
    for line in ("*DELETE /REU/TDAT2", "*DELETE /REU/TTEXT", "*DELETE /Temp/TDAT2",
                 "*DELETE /Temp/TTEXT"):
        run_line(t, line, ">")
    # open files: write, read, PTR#, EOF#; growing a file that is not the
    # last one (it moves to the end); zeros up to PTR#; "Open"
    run_line(t, 'F%=OPENOUT "/REU/TF"', ">")
    run_line(t, "FOR I%=1 TO 300:BPUT#F%,I% MOD 256:NEXT:CLOSE#F%", ">")
    run_line(t, '*SAVE /REU/TG &4000 +100', ">")
    run_line(t, 'F%=OPENIN "/REU/TF":PRINT "E=";EXT#F%', "E=300")
    run_line(t, 'PTR#F%=200:PRINT "B=";BGET#F%;" P=";PTR#F%', "B=201 P=201")
    run_line(t, '*DELETE /REU/TF', "Open")
    run_line(t, 'PTR#F%=300:PRINT "Q=";EOF#F%:CLOSE#F%', "Q=-1")
    run_line(t, 'F%=OPENUP "/REU/TF":PTR#F%=EXT#F%:BPUT#F%,77', ">")
    run_line(t, 'PRINT "E=";EXT#F%:CLOSE#F%', "E=301")
    run_line(t, 'F%=OPENIN "/REU/TF":PTR#F%=300:A%=BGET#F%', ">")
    run_line(t, 'PTR#F%=0:PRINT "L=";A%;",";BGET#F%:CLOSE#F%', "L=77,1")
    run_line(t, "*LOAD /REU/TG &5000", ">")
    run_line(t, 'PRINT "R=";?&5063', "R=99")
    run_line(t, 'F%=OPENOUT "/REU/TH":PTR#F%=10:BPUT#F%,9', ">")
    run_line(t, 'PTR#F%=0:PRINT "Z=";EXT#F%;",";BGET#F%:CLOSE#F%', "Z=11,0")
    run_line(t, 'PRINT "N=";OPENIN "/REU/NONE"', "N=0")
    for line in ("*DELETE /REU/TF", "*DELETE /REU/TG", "*DELETE /REU/TH"):
        run_line(t, line, ">")


def test_gfx_patterns(t):
    # ECF: GCOL 16 + action selects pattern 1 (checker of colours 1, 0);
    # VDU 23,12 redefines pattern 1 (2 x 4 logical colours); VDU 23,11
    # restores the defaults. One pixel = 4 OS units in MODE 1 (Upic
    # Lite) and 8 (VIC-II multicolour): sample pixel pairs by colour.
    gfx_check(t, 1, [
        "VDU 28,0,31,39,28",
        "GCOL 16,0:MOVE 0,400:PLOT 101,400,800",
        "X%=0:FOR I%=0 TO 15:X%=X%+POINT(200+I%*4,600):NEXT",
        "VDU 23,12,3,3,3,3,3,3,3,3:GCOL 16,0:MOVE 600,400:PLOT 101,900,800",
        "Y%=POINT(700,600)+POINT(704,600)",
        "VDU 23,11,0;0;0;0;:GCOL 0,2:MOVE 1000,400:PLOT 101,1200,800",
        "Z%=POINT(1100,600)",
        "R$=\"R=\"+STR$(X%>0 AND X%<16)+STR$Y%+STR$Z%"],
        "R=-162")


def test_gfx_vdu5(t):
    # VDU 5: text at the graphics cursor (top left of the character cell),
    # transparent, graphics colour; VDU 4 back to the text cursor
    gfx_check(t, 4, [
        "VDU 28,0,31,39,28:VDU 5:GCOL 0,1:MOVE 400,1000:PRINT \"W\";",
        "N%=0:FOR I%=0 TO 63:N%=N%-POINT(400+(I%AND7)*4,1000-(I%DIV8)*4):NEXT",
        "VDU 4",
        "R$=\"R=\"+STR$(N%<0)"],
        "R=-1")


def test_gfx_mode3(t):
    # 80 columns are dropped (owner, 2026-10-10): MODE 3 is MODE 6 and MODE 0
    # is MODE 4, their 40-column twins (OSBYTE &87 gives the mode in Y)
    out = remote(t).run_lines([
        "MODE 3:A%=&87:M%=(USR&C7F4 AND &FF0000) DIV &10000:C%=POS",
        "MODE 0:A%=&87:N%=(USR&C7F4 AND &FF0000) DIV &10000",
        "MODE 100", 'PRINT "M=";M%;",";N%'])["output"]
    assert "M=6,4" in out, out


def test_gfx_teletext(t):
    # MODE 7 is teletext: HIMEM &7C00, the codes in the screen memory at
    # &7C00 (OSBYTE &87 reads them back), a colour code colours the cells
    # after it (screen matrix at $C000: foreground high nybble)
    gfx_check(t, 7, [
        "PRINT TAB(0,5);CHR$129;\"RED\";CHR$157;CHR$132;\"X\"",
        "F%=?&7CC8:B%=?&7CC9:C%=HIMEM",
        "PRINT TAB(1,5);:A%=&87:X%=0:D%=(USR(&C7F4) AND &FF00) DIV 256",
        "R$=\"R=\"+STR$~F%+\",\"+STR$B%+\",\"+STR$~C%+\",\"+STR$D%"],
        "R=81,82,7C00,82")
    if t.is_vice:
        return
    # the cell colours as drawn: "RED" red on black, "X" blue on red
    remote(t).run_lines(["MODE 7",
                         "PRINT TAB(0,10);CHR$129;\"RED\";CHR$157;CHR$132;\"X\""])
    m = rest_read(t, 0xC000 + 400, 8)       # row 10 of the screen matrix
    # a direct write to the screen memory shows within a frame or two
    remote(t).run_lines(["?&7F20=145:?&7F21=255"])  # row 20: red graphics block
    time.sleep(1.0)                         # (away from the prompt's rows)
    m2 = rest_read(t, 0xC000 + 800, 2)
    # flashing: a flashing cell's bitmap is empty part of the time
    remote(t).run_lines(["PRINT TAB(0,14);CHR$136;\"FLASH\""])
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import u64shot                          # (REST reads see the KERNAL
    frames = u64shot.grab_frames(t.host, 11002, 9, 0.1)  # ROM at $E000;
    # the stream stops by itself after about a second: 9 frames 0.1 s
    # apart see both flash phases, 0.5 s each)
    seen = {len(set(b"".join(f) for f in frames)) > 1}
    remote(t).run_lines(["MODE 100"])
    assert m[1] >> 4 == 2 and m[1] & 15 == 0 and m[6] >> 4 == 6 and m[6] & 15 == 2, m.hex()
    assert m2[1] >> 4 == 2, m2.hex()
    assert seen == {True}, "no flashing: all frames equal"


def rest_read(t, address, length):
    import urllib.request
    with urllib.request.urlopen("http://%s/v1/machine:readmem?address=%04X&length=%d"
                                % (t.host, address, length), timeout=10) as f:
        return f.read()


def test_gfx_upiclite(t):
    # Upic Lite on 64 MHz Ultimates (docs/DESIGN_GRAPHICS.md 10.8): HIMEM
    # as on the BBC, and the picture pixel-exact in the VIC stream: a
    # vertical line at x = 640 is one dot wide on dot 32 + 160, lines 0-255
    if not ult(t):
        return
    r = remote(t)
    out = r.run_lines(["MODE 4", "PRINT HIMEM", "MOVE 640,0:DRAW 640,1023"])["output"]
    if "32768" in out:
        t.notes.append("Upic Lite: not on this machine (VIC-II modes)")
        r.run_lines(["MODE 100"])
        return
    assert "22528" in out, out
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import u64shot
    rows = u64shot.grab(t.host, 11002)
    top = 9                                 # stream row of picture line 0
    col = [rows[top + y][192] & 1 for y in range(256)]
    side = [(rows[top + y][191] & 1) | (rows[top + y][193] & 1) for y in range(256)]
    assert all(col) and not any(side), (col.count(1), side.count(1))
    out = r.run_lines(["MODE 1", "PRINT HIMEM", "GCOL 0,2:PLOT 69,0,1020"])["output"]
    assert "12288" in out, out
    rows = u64shot.grab(t.host, 11002)
    assert rows[top][32] & 3 == 2, rows[top][28:40]
    out = r.run_lines(["MODE 2", "PRINT HIMEM", "GCOL 0,9:PLOT 69,0,1020",
                       "PRINT POINT(0,1020)"])["output"]
    assert "12288" in out and re.search(r"\b9\b", out), out
    rows = u64shot.grab(t.host, 11002)     # 160 wide: pixel 0 = dots 32, 33
    assert rows[top][32] & 15 == 9 and rows[top][33] & 15 == 9, rows[top][28:40]
    out = r.run_lines(["MODE 5", "PRINT HIMEM"])["output"]
    assert "22528" in out, out
    out = r.run_lines(["MODE 100", "PRINT HIMEM"])["output"]
    assert "32768" in out, out
    t.notes.append("Upic Lite: MODE 4/1/2/5 live, pixel-exact")


def test_classic_files(t):
    # The BBC BASIC (Z80) file examples (demos/classics/files), unchanged:
    # f-wser1 writes names and numbers with PRINT#, f-rser1 reads them back
    # with INPUT# (it checks EOF# after reading, so it skips the last
    # entry: that is the original program)
    if not ult(t):
        return
    r = remote(t)
    d = os.path.join(ROOT, "demos", "classics", "files")
    r.run_lines(["*DIR /Temp"])
    r.send_program(open(os.path.join(d, "f-wser1.bas")).read(), run=True)
    r.run_lines(["ALICE", "0123", "BOB", "0456", ""])
    out = r.send_program(open(os.path.join(d, "f-rser1.bas")).read(), run=True)["output"]
    r.run_lines(["*DELETE PHONENOS"])
    assert "ALICE" in out and "0123" in out, out


def test_turbo_cmd(t):
    if t.is_vice:
        run_line(t, "*TURBO", "No turbo registers")
        return
    run_line(t, "*TURBO", "Turbo speed index 15")
    run_line(t, "*TURBO 0", ">")
    run_line(t, "*TURBO", "Turbo speed index 0")
    run_line(t, "*TURBO MAX", ">")
    run_line(t, "*TURBO", "Turbo speed index 15")


# --- Remote mailbox (docs/REMOTE_DEV.md), through c64bridge memory access

sys.path.insert(0, os.path.join(ROOT, "tools"))
import u64remote  # noqa: E402
import bbctok  # noqa: E402

TOKENISER_LINES = [
    '10 REM tokeniser test: "quotes" & REM text ~ stays',
    '20 TIME=0:PRINT TIME:PTR#X=PTR#X+1:HIMEM=HIMEM',
    '30 IF A%>1 THEN 10 ELSE GOTO 20',
    '40 ON X GOSUB 10,20,30:RESTORE 40',
    '50 DEF PROCtest(A,B$):LOCAL I%:ENDPROC',
    '60 DEF FNsq(X)=X*X:PRINT FNsq(3);~&FF00',
    '70 DATA 1,"TWO",THREE PRINT',
    '80 *CAT',
    '90 A$=STRING$(3,"*")+MID$("HELLO",2,3):P.LEFT$(A$,2)',
    '100 FOR I%=1 TO 10 STEP 2:NEXT:REPEAT UNTIL TRUE',
    '110 COLOUR 1:VDU 7,8;:X=GET:Y=INKEY(10):Z$=GET$',
    '120 CLOSE#0:BPUT#C,65:CALL &C7EE:Q=USR(&C7E0)',
    '130 PRINTTAB(2,3)"X";SPC(4):CLS:CLG',
    '140 TRACE ON:TRACE OFF:TRACE 100:ENDPROC:END',
    '150 GOTO 32767:GOTO 40000',
    '160 a=1:prints=2:PRINTA:TIMER=3:PROCabc',
]


def remote(t):
    return u64remote.Remote(mem=t.bridge)


def test_remote_exec(t):
    r = remote(t).run_lines(["PRINT 6*7", 'PRINT "HELLO"'])
    assert r["ok"] and r["output"] == "        42\nHELLO\n", r


def test_remote_run_error(t):
    prog = '10 FOR I%=1 TO 3\n20 PRINT "LINE ";I%\n30 NEXT\n40 PRINT 1/0\n'
    r = remote(t).send_program(prog, run=True)
    assert r["output"].startswith("LINE 1\nLINE 2\nLINE 3\n"), r
    assert r["error"] == {"number": 18, "message": "Division by zero",
                          "line": 40}, r


def test_remote_input(t):
    rm = remote(t)
    r = rm.send_program('10 INPUT "NAME";N$\n20 PRINT "HI ";N$\n', run=True)
    assert r["state"] == "input" and "NAME?" in r["output"], r
    r = rm.run_lines(["AGENT"])
    assert r["output"] == "HI AGENT\n" and r["state"] == "prompt", r


def test_remote_long_output(t):
    # more than the 128-byte ring: the MOS waits while the host drains
    prog = '10 FOR I%=1 TO 60:PRINT "OUTPUT LINE ";I%:NEXT\n'
    r = remote(t).send_program(prog, run=True, timeout=60)
    lines = r["output"].splitlines()
    assert len(lines) == 60 and lines[-1] == "OUTPUT LINE 60", lines[-3:]


def test_remote_tokeniser(t):
    # the host tokeniser must store exactly what BASIC stores when the
    # same lines are typed in
    rm = remote(t)
    rm.run_lines(["NEW"] + TOKENISER_LINES)
    page = rm.page_himem()[0]
    image = b"".join(rm.read(page + i, 0x400) for i in range(0, 0x800, 0x400))
    want = bbctok.tokenise_program("\n".join(TOKENISER_LINES))
    got = image[:len(want)]
    assert got == want, "differs at offset %d: BASIC %s, host %s" % (
        next(i for i in range(len(want)) if got[i] != want[i]),
        got.hex(" ")[:120], want.hex(" ")[:120])
    assert rm.program_text().splitlines()[0].startswith("10 REM")


def test_remote_stop(t):
    rm = remote(t)
    r = rm.send_program("10 GOTO 10\n", run=True, timeout=2)
    assert r["state"] == "timeout", r
    rm.stop()
    r = rm.run_lines([], timeout=10, prepared=False)
    assert r["state"] == "prompt", r


DEBUG_PROG = """10 A%=5:B=1.5:C$="TEXT"
20 FOR I%=1 TO 3
30 PRINT "I=";I%
40 NEXT
50 X=A%*B
60 PRINT "[NOT A TRACE] [12 X=";X
70 END
"""


def test_remote_debug(t):
    rm = remote(t)
    try:
        r = rm.debug_start(DEBUG_PROG, breakpoints=[40])
        assert r["state"] == "paused" and rm.state()["line"] == 40, r
        v = rm.variables()
        assert v.get("A%") == 5 and v.get("I%") == 1 and v.get("B") == 1.5 \
            and v.get("C$") == "TEXT", v
        r = rm.debug_resume(u64remote.DBG_STEP)       # NEXT jumps back: line
        assert r["state"] == "paused" and r["line"] == 40 and r["output"] == "I=2\n", r
        rm.set_breakpoints([])
        r = rm.debug_resume(u64remote.DBG_CONTINUE)
        # the trace lines are swallowed; a "[" that is no trace is printed
        assert r["state"] == "prompt" and r["output"] == \
            "I=3\n[NOT A TRACE] [12 X=7.5\n", r
        assert rm.variables().get("X") == 7.5
    finally:
        rm.debug_end()


TESTS = [test_boot, test_basic_ram, test_arith, test_hex, test_line_editor, test_caps_lock, test_key, test_ascii, test_program,
         test_error, test_mos_error, test_help, test_help_paging,
         test_bad_number,
         test_vdu_overflow, test_fx_escape, test_stop_key,
         test_time, test_inkey, test_get, test_long_line, test_speed,
         test_fs_uver, test_fs_time, test_fs_dir, test_fs_save_load,
         test_fs_channels, test_fs_type, test_fs_errors,
         test_fs_rename_delete, test_turbo_cmd, test_status,
         test_a_clock, test_a_copy, test_a_mount, test_a_drive,
         test_a_settime, test_a_partition, test_a_dirhome,
         test_gfx_point_line, test_gfx_rect_clg_window, test_gfx_gcol_actions,
         test_gfx_origin_relative, test_gfx_text, test_gfx_shapes,
         test_gfx_patterns, test_gfx_flood, test_gfx_arcs, test_vdu23_chars, test_font,
         test_palette, test_memory, test_sound, test_sid_mode, test_sound_none,
         test_inst_mods, test_song, test_star_list, test_reu_irq, test_snapshot, test_sprite, test_sprite_gfx, test_upic, test_upic_mode, test_upic_auto, test_bv_cmds, test_mode1_font, test_gxr, test_net, test_json, test_netchan, test_classics,
         test_sid, test_text_colours, test_reu_storage,
         test_ramdisk,
         test_gfx_vdu5,
         test_gfx_mode3,
         test_gfx_teletext,
         test_gfx_upiclite, test_classic_files,
         test_remote_exec, test_remote_run_error, test_remote_input,
         test_remote_long_output, test_remote_tokeniser, test_remote_stop,
         test_remote_debug]


# ----------------------------------------------------------------------------

def run_target(t, only):
    outdir = os.path.join(BUILD, "e2e", t.name)
    os.makedirs(outdir, exist_ok=True)
    t.notes = []
    failures = 0
    print("== %s" % t.name, flush=True)
    try:
        t.start()
    except Exception as e:
        print("   START FAILED: %s" % e)
        return 1
    try:
        for test in TESTS:
            name = test.__name__[5:]
            if only and name not in only and name != "boot":
                continue
            try:
                test(t)
                print("   ok    %s" % name, flush=True)
            except (AssertionError, TimeoutError, BridgeError) as e:
                failures += 1
                print("   FAIL  %s: %s" % (name, (str(e).splitlines() or [repr(e)])[0]),
                      flush=True)
                try:
                    rows = screen.read_screen(t.bridge)
                    with open(os.path.join(outdir, name + ".txt"), "w") as f:
                        f.write("%s\n\n%s\n" % (e, "\n".join(rows)))
                except Exception:
                    pass
                if name == "boot":
                    break
        for n in t.notes:
            print("   note  %s" % n)
    finally:
        t.stop()
    return failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vice-only", action="store_true")
    ap.add_argument("--no-vice", action="store_true")
    ap.add_argument("--device", nargs="*")
    ap.add_argument("--kind", nargs="*", default=["tmb", "ef"])
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()

    for path in CRT.values():
        if not os.path.exists(path):
            sys.exit("missing %s: run make first" % path)

    targets = []
    if not args.no_vice:
        targets.append(ViceTarget())
    if not args.vice_only:
        env = read_env()
        hosts = args.device or [env[k] for k in ("ULTIP1", "ULTIP2") if k in env]
        for host in hosts:
            for kind in args.kind:
                targets.append(UltimateTarget(host, kind))

    failures = sum(run_target(t, args.only) for t in targets)
    print("\n%s: %d failure(s)" % ("PASS" if not failures else "FAIL", failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
