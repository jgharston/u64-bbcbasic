"""Screen and keyboard helpers for U64 BBC BASIC (text mode).

The MOS shows text at $C000 in the C64 lower/upper case character set
with eight glyphs replaced by ASCII characters (tools/gentables.py). Keys
are typed by placing PETSCII codes in the KERNAL keyboard buffer, encoded
the way the MOS decodes them (CAPS LOCK swap: 'A' = PETSCII $C1).
"""
import time

SCREEN = 0xC000
KBUF = 0x0277
NDX = 0x00C6
COLS, ROWS = 40, 25

# ASCII characters the C64 lacks: ASCII -> PETSCII (same as gentables.py)
SPECIAL = {0x5C: 0x5C, 0x5E: 0x5E, 0x5F: 0x5F, 0x60: 0xBA,
           0x7B: 0xDB, 0x7C: 0xA9, 0x7D: 0xDD, 0x7E: 0xDE}
KEYS = {"\r": 0x0D, "\n": 0x0D, "{DEL}": 0x14, "{HOME}": 0x13,
        "{CLR}": 0x93, "{LEFT}": 0x9D, "{RIGHT}": 0x1D, "{DOWN}": 0x11,
        "{UP}": 0x91}


def ascii_to_petscii(ch):
    a = ord(ch)
    if a in SPECIAL:
        return SPECIAL[a]
    if 0x41 <= a <= 0x5A:
        return a + 0x80
    if 0x61 <= a <= 0x7A:
        return a - 0x20
    if 0x20 <= a <= 0x5D:
        return a
    raise ValueError("cannot type %r" % ch)


def _screen_table():
    table = {}
    for a in range(0x20, 0x7F):
        p = ascii_to_petscii(chr(a))
        if 0x40 <= p <= 0x5F:
            s = p - 0x40
        elif 0xA0 <= p <= 0xBF:
            s = p - 0x40
        elif 0xC0 <= p <= 0xDF:
            s = p - 0x80
        else:
            s = p
        table[s] = chr(a)
    return table


SCREEN_TO_ASCII = _screen_table()


def decode_screen(data):
    """40x25 screen codes -> list of 25 strings (reverse video ignored,
    codes without an ASCII character shown as '#')."""
    rows = []
    for r in range(ROWS):
        line = data[r * COLS:(r + 1) * COLS]
        rows.append("".join(SCREEN_TO_ASCII.get(c & 0x7F, "#") for c in line))
    return rows


def read_screen(bridge):
    return decode_screen(bridge.read(SCREEN, COLS * ROWS))


def encode_keys(text):
    """Text with {TOKENS} -> PETSCII codes."""
    out = []
    i = 0
    while i < len(text):
        j = text.find("}", i)
        if text[i] == "{" and j > 0 and text[i:j + 1] in KEYS:
            out.append(KEYS[text[i:j + 1]])
            i = j + 1
        else:
            ch = text[i]
            out.append(KEYS[ch] if ch in KEYS else ascii_to_petscii(ch))
            i += 1
    return out


def type_text(bridge, text, timeout=20):
    """Type text through the keyboard buffer, at most 10 keys at a time,
    each batch only once the previous one has been read."""
    codes = encode_keys(text)
    while codes:
        deadline = time.time() + timeout
        while bridge.read(NDX, 1)[0] != 0:
            if time.time() > deadline:
                raise TimeoutError("keyboard buffer not emptied")
            time.sleep(0.05)
        batch, codes = codes[:10], codes[10:]
        bridge.write(KBUF, batch)
        bridge.write(NDX, [len(batch)])


def wait_for(bridge, predicate, timeout=20, interval=0.2):
    """Poll the screen until predicate(rows) is true; return the rows."""
    deadline = time.time() + timeout
    rows = read_screen(bridge)
    while not predicate(rows):
        if time.time() > deadline:
            raise TimeoutError("screen condition not met:\n" + "\n".join(rows))
        time.sleep(interval)
        rows = read_screen(bridge)
    return rows


def wait_text(bridge, text, timeout=20):
    return wait_for(bridge, lambda rows: any(text in r for r in rows), timeout)
