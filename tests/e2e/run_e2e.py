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


def test_help_paging(t):
    # MEMORY is longer than one page: the prompt, then SPACE for more
    run_line(t, "*HELP MEMORY", "SPACE: more")
    screen.type_text(t.bridge, " ")
    screen.wait_text(t.bridge, "even in turbo mode")
    run_line(t, "*HELP KEYWORDS", "SPACE: more")
    screen.type_text(t.bridge, " ")
    screen.wait_text(t.bridge, "WIDTH")


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
    # 77 characters after the prompt: a wrapped (two-row) logical line.
    # The KERNAL editor's limit is 80 columns including the prompt, and
    # exactly 80 wraps onto an empty third row (docs/PLAN.md, risks).
    s = "X" * 58
    run_line(t, 'A$="%s":PRINT LEN(A$)' % s, "        58")


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
    assert "PAGE       &0800" in out and "HIMEM      &8000" in out, out
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
    assert len(bcd) == 7 and bcd[0] == m.group(4)[2:] and int(bcd[2], 16) == int(m.group(2)) \
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
    if not ult(t):
        return
    run_line(t, "*PARTITION 250 /Temp E2E", ">")
    run_line(t, "*PARTITIONS", '"E2E"')
    run_line(t, "*CP 250", ">")
    run_line(t, "*CP 0", ">")


def test_a_dirhome(t):
    if not ult(t):
        return
    run_line(t, "*DIR ~", ">")
    run_line(t, "*PWD", "/")
    run_line(t, "*DIR /Temp", ">")


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
    image = b"".join(rm.read(0x0800 + i, 0x400) for i in range(0, 0x800, 0x400))
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


TESTS = [test_boot, test_basic_ram, test_arith, test_hex, test_ascii, test_program,
         test_error, test_mos_error, test_help, test_help_paging,
         test_bad_number,
         test_vdu_overflow, test_fx_escape, test_stop_key,
         test_time, test_inkey, test_get, test_long_line, test_speed,
         test_fs_uver, test_fs_time, test_fs_dir, test_fs_save_load,
         test_fs_channels, test_fs_type, test_fs_errors,
         test_fs_rename_delete, test_turbo_cmd, test_status,
         test_a_clock, test_a_copy, test_a_mount, test_a_drive,
         test_a_settime, test_a_partition, test_a_dirhome,
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
                print("   FAIL  %s: %s" % (name, str(e).splitlines()[0]),
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
