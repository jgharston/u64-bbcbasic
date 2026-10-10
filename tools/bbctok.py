#!/usr/bin/env python3
"""BBC BASIC 3.10 tokeniser and detokeniser for the host.

A Python port of the interpreter's own tokeniser (MATCH in ivop/bbc-basic
basic.s, "Tokenise line at (zpWORK)", and CONSTQ/CONSTI for line number
constants), with the keyword table read from that same source file, so
the result is byte-for-byte what BBC BASIC stores when a line is typed.
The E2E suite checks this against the real interpreter (write the image
to PAGE, LIST it).

Program image (as at PAGE): CR, then per line: line number high byte,
low byte, length (text length + 4), tokenised text, CR; ends with &FF.

Usage:
  bbctok.py tokenise PROG.bas OUT.bin     text -> program image
  bbctok.py list IMAGE.bin                program image -> text
As a module: tokenise_program(text) -> bytes, detokenise(image) -> str.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASIC_SRC = os.path.join(HERE, "..", "lib", "bbc-basic", "basic.s")

CR = 0x0D
TKN_CONST = 0x8D
TKN_PTR, TKN_PTR2 = 0x8F, 0xCF          # pseudo-variables: +&40 at the
                                        # start of a statement


def load_tokens(path=BASIC_SRC):
    """Keyword table in interpreter order: [(keyword, token, flags)]."""
    src = open(path, encoding="latin-1").read()
    values = {m.group(1): int(m.group(2), 16)
              for m in re.finditer(r"^(tkn\w+)\s*=\s*\$([0-9A-Fa-f]+)", src, re.M)}
    table = src[src.index("\nTOKENS:"):]
    table = table[:table.index("\n\n", table.index("tknWIDTH"))]
    out = []
    skip = False
    for line in table.splitlines():
        s = line.strip()
        # version conditionals in the table: BASIC 3.10 spells COLOUR
        if s.startswith(".if"):
            skip = False
            continue
        if s.startswith(".elseif"):
            skip = True                 # the 3.00 "COLOR" variant
            continue
        if s.startswith(".endif"):
            skip = False
            continue
        m = re.match(r"dta\s+'([^']+)'\s*,\s*(tkn\w+)\s*,\s*\$([0-9A-Fa-f]+)", s)
        if m and not skip:
            out.append((m.group(1), values[m.group(2)], int(m.group(3), 16)))
    return out


TOKENS = load_tokens()
DETOKEN = {}
for _kw, _tok, _flags in TOKENS:
    DETOKEN.setdefault(_tok, _kw)
    if _flags & 0x40:
        DETOKEN.setdefault(_tok + (TKN_PTR2 - TKN_PTR), _kw)


def is_word(c):
    """WORDCQ: digits, A-Z, _, ` and a-z."""
    return (0x30 <= c <= 0x39) or (0x41 <= c <= 0x5A) or (0x5F <= c <= 0x7A)


def is_digit(c):
    return 0x30 <= c <= 0x39


def encode_lineno(n):
    """CONSTI: 3 bytes for a line number constant (0-32767)."""
    lo, hi = n & 0xFF, n >> 8
    b1 = ((((lo & 0xC0) | ((hi & 0xC0) >> 2)) >> 2) ^ 0x54) & 0xFF
    b2 = (lo & 0x3F) | 0x40
    b3 = (hi & 0x3F) | 0x40
    return [b1, b2, b3]


def decode_lineno(b1, b2, b3):
    """SPGETN."""
    x = (b1 << 2) & 0xFF
    lo = (x & 0xC0) ^ b2
    hi = (((x << 2) & 0xFF) ^ b3) & 0xFF
    return lo | (hi << 8)


def tokenise_line(text, start=True, lineno=True):
    """MATCHA on a line (no CR); returns the tokenised bytes (no CR).

    start:  statement start (zpWORK+4 = 0); lineno: tokenise numbers
    (zpWORK+5 <> 0). RUNTHG uses both, so a typed line's own number
    becomes a line number constant too.
    """
    buf = list(text.encode("latin-1")) + [CR]
    i = 0

    def ymatch():
        nonlocal start, lineno
        start, lineno = False, False

    while True:
        c = buf[i]
        if c == CR:
            break
        if c == 0x20:                                   # space
            i += 1
            continue
        if c == 0x26:                                   # & hex: skip digits
            i += 1
            while is_digit(buf[i]) or 0x41 <= buf[i] <= 0x46:
                i += 1
            continue
        if c == 0x22:                                   # string
            i += 1
            while buf[i] not in (0x22, CR):
                i += 1
            if buf[i] == CR:
                break
            i += 1
            continue
        if c == 0x3A:                                   # :
            start, lineno = True, False
            i += 1
            continue
        if c == 0x2C:                                   # ,
            i += 1
            continue
        if c == 0x2A:                                   # * at statement start
            if start:
                break                                   # OSCLI: rest as is
            ymatch()
            i += 1
            continue
        if c == 0x2E or is_digit(c):                    # . or digit
            if c != 0x2E and lineno:
                j, n, ok = i, 0, True
                while is_digit(buf[j]):
                    n = n * 10 + buf[j] - 0x30
                    if n >= 32768:
                        ok = False
                    j += 1
                if ok:
                    buf[i:j] = [TKN_CONST] + encode_lineno(n)
                    i += 4
                    continue
            while buf[i] == 0x2E or is_digit(buf[i]):   # MATCHZ
                i += 1
            ymatch()
            continue
        if c < 0x41:                                    # other symbols
            ymatch()
            i += 1
            continue
        if c >= 0x58:                                   # X..: no keywords
            if not is_word(c):
                ymatch()
                i += 1
                continue
            while is_word(buf[i]):                      # MATCHV
                i += 1
            ymatch()
            continue
        # keyword lookup, table order (IMATCH ... LMATCH)
        found = None
        for kw, tok, flags in TOKENS:
            k = kw.encode("latin-1")
            if c < k[0]:
                break                                   # a variable name
            if c != k[0]:
                continue
            j = 1
            while j < len(k) and buf[i + j] == k[j]:
                j += 1
            if j == len(k):
                found = (tok, flags, j)
                break
            if buf[i + j] == 0x2E:                      # abbreviation
                found = (tok, flags, j + 1)
                break
        if found is None:
            while is_word(buf[i]):                      # variable name
                i += 1
            ymatch()
            continue
        tok, flags, used = found
        if (flags & 0x01) and is_word(buf[i + used]):   # conditional
            while is_word(buf[i]):
                i += 1
            ymatch()
            continue
        if (flags & 0x40) and start:                    # pseudo-variable
            tok += TKN_PTR2 - TKN_PTR
        buf[i:i + used] = [tok]
        if flags & 0x02:
            start, lineno = False, False
        if flags & 0x04:
            start, lineno = True, False
        if flags & 0x08:                                # FN/PROC name
            while is_word(buf[i + 1]):
                i += 1
        if flags & 0x10:
            lineno = True
        if flags & 0x20:                                # REM, DATA: rest raw
            break
        i += 1
    return bytes(buf[:buf.index(CR)])


def tokenise_program(text, indent=False):
    """Program text -> image as stored at PAGE (ends CR &FF).

    The source's indentation (spaces after the line number beyond the
    first, CLAUDE.md: structured, indented sources) is dropped unless
    indent is true, as the VS Code extension does on upload: it costs
    memory, and LISTO 7 indents the listing on the machine again."""
    image = bytearray([CR])
    last = -1
    for n, raw in enumerate(text.splitlines(), 1):
        if not raw.strip():
            continue
        if not indent:
            raw = re.sub(r"^(\s*\d+) +", r"\1 ", raw)
        tok = tokenise_line(raw.rstrip())
        k = 0
        while k < len(tok) and tok[k] == 0x20:
            k += 1
        if k >= len(tok) or tok[k] != TKN_CONST:
            raise ValueError("line %d: no line number: %r" % (n, raw))
        number = decode_lineno(*tok[k + 1:k + 4])
        if number <= last:
            raise ValueError("line %d: line number %d not ascending" % (n, number))
        body = tok[k + 4:]
        if len(body) + 4 > 255:
            raise ValueError("line %d: line too long" % n)
        image += bytes([number >> 8, number & 0xFF, len(body) + 4]) + body + bytes([CR])
        last = number
    image.append(0xFF)
    return bytes(image)


def detokenise(image):
    """Program image -> text, as LIST shows it (no LISTO formatting)."""
    out = []
    i = 1
    while i < len(image) and image[i] != 0xFF:
        number = image[i] << 8 | image[i + 1]
        length = image[i + 2]
        body = image[i + 3:i + length - 1]
        line, j, quote = [], 0, False
        while j < len(body):
            b = body[j]
            if b == 0x22:
                quote = not quote
            if not quote and b == TKN_CONST:
                line.append(str(decode_lineno(*body[j + 1:j + 4])))
                j += 4
                continue
            if not quote and b >= 0x80 and b in DETOKEN:
                line.append(DETOKEN[b])
                if DETOKEN[b] in ("REM", "DATA"):
                    line.append(body[j + 1:].decode("latin-1"))
                    break
            else:
                line.append(chr(b))
            j += 1
        out.append("%d%s" % (number, "".join(line)))
        i += length
    return "\n".join(out) + "\n"


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "tokenise":
        image = tokenise_program(open(sys.argv[2], encoding="latin-1").read())
        open(sys.argv[3], "wb").write(image)
    elif len(sys.argv) == 3 and sys.argv[1] == "list":
        sys.stdout.write(detokenise(open(sys.argv[2], "rb").read()))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
