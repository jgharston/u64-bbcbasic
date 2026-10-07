#!/usr/bin/env python3
"""Convert BBC BASIC for Windows / BBC BASIC for SDL programs (.bbc, the
tokenised format) to plain text, and list what BBC BASIC 3.10 lacks.

    tools/bb4wtxt.py prog.bbc [-o prog.bas] [--number]

Format: per line a length byte, the line number (2 bytes, little endian;
0 for unnumbered lines), the tokenised text and a CR; a 0 length byte
ends the program. Line numbers in GOTO/GOSUB/RESTORE use the Acorn $8D
encoding. --number numbers unnumbered lines 10, 20, ...

The token table is taken from BBC BASIC for SDL 2.0 by Richard Russell
(github.com/rtrussell/BBCSDL: include/BBC.h token values, src/bbmain.c
keyword names; zlib licence). Adapted: a Python table, first name per
token.

Warnings name BBC BASIC V / BB4W features BASIC 3.10 does not have
(CASE, WHILE, multi-line IF, INSTALL, SYS, @-variables, ...), so a port
knows what to rewrite.
"""
import argparse
import re
import sys

TOKENS = {
    0x01: 'CIRCLE', 0x02: 'ELLIPSE', 0x03: 'FILL', 0x04: 'MOUSE',
    0x05: 'ORIGIN', 0x06: 'QUIT', 0x07: 'RECTANGLE', 0x08: 'SWAP',
    0x09: 'SYS', 0x0A: 'TINT', 0x0B: 'WAIT', 0x0C: 'INSTALL',
    0x0E: 'PRIVATE', 0x0F: 'BY', 0x10: 'EXIT', 0x80: 'AND',
    0x81: 'DIV', 0x82: 'EOR', 0x83: 'MOD', 0x84: 'OR',
    0x85: 'ERROR', 0x86: 'LINE', 0x87: 'OFF', 0x88: 'STEP',
    0x89: 'SPC', 0x8A: 'TAB(', 0x8B: 'ELSE', 0x8C: 'THEN',
    0x8E: 'OPENIN', 0x8F: 'PTR', 0x90: 'PAGE', 0x91: 'TIME',
    0x92: 'LOMEM', 0x93: 'HIMEM', 0x94: 'ABS', 0x95: 'ACS',
    0x96: 'ADVAL', 0x97: 'ASC', 0x98: 'ASN', 0x99: 'ATN',
    0x9A: 'BGET', 0x9B: 'COS', 0x9C: 'COUNT', 0x9D: 'DEG',
    0x9E: 'ERL', 0x9F: 'ERR', 0xA0: 'EVAL', 0xA1: 'EXP',
    0xA2: 'EXT', 0xA3: 'FALSE', 0xA4: 'FN', 0xA5: 'GET',
    0xA6: 'INKEY', 0xA7: 'INSTR(', 0xA8: 'INT', 0xA9: 'LEN',
    0xAA: 'LN', 0xAB: 'LOG', 0xAC: 'NOT', 0xAD: 'OPENUP',
    0xAE: 'OPENOUT', 0xAF: 'PI', 0xB0: 'POINT(', 0xB1: 'POS',
    0xB2: 'RAD', 0xB3: 'RND', 0xB4: 'SGN', 0xB5: 'SIN',
    0xB6: 'SQR', 0xB7: 'TAN', 0xB8: 'TO', 0xB9: 'TRUE',
    0xBA: 'USR', 0xBB: 'VAL', 0xBC: 'VPOS', 0xBD: 'CHR$',
    0xBE: 'GET$', 0xBF: 'INKEY$', 0xC0: 'LEFT$(', 0xC1: 'MID$(',
    0xC2: 'RIGHT$(', 0xC3: 'STR$', 0xC4: 'STRING$(', 0xC5: 'EOF',
    0xC6: 'SUM', 0xC7: 'WHILE', 0xC8: 'CASE', 0xC9: 'WHEN',
    0xCA: 'OF', 0xCB: 'ENDCASE', 0xCC: 'OTHERWISE', 0xCD: 'ENDIF',
    0xCE: 'ENDWHILE', 0xCF: 'PTR', 0xD0: 'PAGE', 0xD1: 'TIME',
    0xD2: 'LOMEM', 0xD3: 'HIMEM', 0xD4: 'SOUND', 0xD5: 'BPUT',
    0xD6: 'CALL', 0xD7: 'CHAIN', 0xD8: 'CLEAR', 0xD9: 'CLOSE',
    0xDA: 'CLG', 0xDB: 'CLS', 0xDC: 'DATA', 0xDD: 'DEF',
    0xDE: 'DIM', 0xDF: 'DRAW', 0xE0: 'END', 0xE1: 'ENDPROC',
    0xE2: 'ENVELOPE', 0xE3: 'FOR', 0xE4: 'GOSUB', 0xE5: 'GOTO',
    0xE6: 'GCOL', 0xE7: 'IF', 0xE8: 'INPUT', 0xE9: 'LET',
    0xEA: 'LOCAL', 0xEB: 'MODE', 0xEC: 'MOVE', 0xED: 'NEXT',
    0xEE: 'ON', 0xEF: 'VDU', 0xF0: 'PLOT', 0xF1: 'PRINT',
    0xF2: 'PROC', 0xF3: 'READ', 0xF4: 'REM', 0xF5: 'REPEAT',
    0xF6: 'REPORT', 0xF7: 'RESTORE', 0xF8: 'RETURN', 0xF9: 'RUN',
    0xFA: 'STOP', 0xFB: 'COLOUR', 0xFC: 'TRACE', 0xFD: 'UNTIL',
    0xFE: 'WIDTH', 0xFF: 'OSCLI',
}

# Keywords BBC BASIC 3.10 does not have (BASIC V, BB4W)
NOT_310 = {"CASE", "WHEN", "OF", "ENDCASE", "OTHERWISE", "ENDIF", "WHILE",
           "ENDWHILE", "SUM", "EXIT", "INSTALL", "SYS", "QUIT", "LINE",
           "FILL", "CIRCLE", "ELLIPSE", "RECTANGLE", "ORIGIN", "MOUSE",
           "WAIT", "SWAP", "LOCAL", "PRIVATE", "DIM", "COLOR", "TINT",
           "BY", "REPORT$", "DIM("}


def decode_lineno(b1, b2, b3):
    b1 ^= 0x54
    lo = (b2 & 0x3F) | ((b1 << 2) & 0xC0)
    hi = (b3 & 0x3F) | ((b1 << 4) & 0xC0)
    return lo | hi << 8


def line_text(b):
    out, i, quote = [], 0, False
    while i < len(b):
        c = b[i]
        if c == 34:
            quote = not quote
            out.append('"')
            i += 1
            continue
        if not quote and c == 0x8D and i + 3 < len(b):
            out.append(str(decode_lineno(b[i + 1], b[i + 2], b[i + 3])))
            i += 4
            continue
        if not quote and (c >= 0x80 or (c < 0x20 and c in TOKENS)):
            out.append(TOKENS.get(c, "<%02X>" % c))     # BB4W: low tokens too
            i += 1
            continue
        out.append(chr(c))
        i += 1
    return "".join(out)


def convert(data, number=False):
    lines, p, n = [], 0, 0
    while p < len(data):
        ln = data[p]
        if ln == 0 or p + ln > len(data):
            break
        num = data[p + 1] | data[p + 2] << 8
        text = line_text(data[p + 3:p + ln - 1])
        n += 10
        lines.append((num or (n if number else 0), text))
        p += ln
    return lines


def warnings(lines):
    out = []
    for num, text in lines:
        bare = re.sub(r'"[^"]*"', '""', text)
        for kw in ("CASE", "WHILE", "ENDIF", "INSTALL", "SYS", "QUIT",
                   "CIRCLE", "ELLIPSE", "RECTANGLE", "FILL", "ORIGIN",
                   "MOUSE", "WAIT", "SWAP", "EXIT", "PRIVATE", "TINT"):
            if re.search(r"\b%s\b" % kw, bare):
                out.append((num, kw))
        if "@" in bare:
            out.append((num, "@ variables (@lib$, @vdu%, ...)"))
        m = re.search(r"\bMODE\s*(\d+)", bare)
        if m and int(m.group(1)) > 7:
            out.append((num, "MODE %s (not a BBC Micro mode)" % m.group(1)))
        if re.search(r"\bTHEN\s*$", bare):
            out.append((num, "multi-line IF"))
        if re.search(r"\*REFRESH|\*FONT|\*GSAVE", bare):
            out.append((num, "BB4W * command"))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("file")
    ap.add_argument("-o", "--output")
    ap.add_argument("--number", action="store_true")
    a = ap.parse_args()
    lines = convert(open(a.file, "rb").read(), a.number)
    text = "\n".join(("%d %s" % (n, t)) if n else t for n, t in lines) + "\n"
    if a.output:
        open(a.output, "w").write(text)
    else:
        sys.stdout.write(text)
    for num, what in warnings(lines):
        print("warning: line %s: %s" % (num or "?", what), file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
