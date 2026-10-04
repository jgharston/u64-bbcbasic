#!/usr/bin/env python3
"""Pack the *HELP texts into cartridge banks, and write the reference.

Input: src/help/help.txt (format described at its top).

Output 1, the help banks (raw, a multiple of 16K, mapped at $8000):
  first bank, $8000: "UHLP", entry count (2 bytes, little endian), then
  one index record per name (aliases included), sorted by name:
      name (upper-case ASCII), 0, bank number, address (2 bytes)
  then texts, each: ASCII, lines ended by CR (13), text ended by 0.
  A text never crosses a bank boundary. Bank numbers start at --first.

Output 2: a Markdown reference (docs/HELP_REFERENCE.md).

Checks: names unique, ASCII only, literal lines at most 39 characters
(column 40 would make the C64 screen editor wrap), every text < 16K.

With --commands MOS.s, every name in the MOS command table (lines
"dta 'NAME', 0, a(handler), bank") must have a *NAME help entry.

Usage: genhelp.py SRC OUT.bin OUT.md [--first 3] [--commands MOS.s]
"""
import argparse
import re
import textwrap

WIDTH = 39
BANK = 0x4000


def parse(path):
    entries = []        # (names, lines)
    cur = None
    for n, raw in enumerate(open(path, encoding="ascii"), 1):
        line = raw.rstrip("\n")
        if line.startswith("#"):
            continue
        if line.startswith("@@"):
            names = [x.strip().upper() for x in line[2:].split("|")]
            cur = (names, [], n)
            entries.append(cur)
            continue
        if cur is None:
            if line.strip():
                raise SystemExit("%s:%d: text before the first entry" % (path, n))
            continue
        cur[1].append((n, line))
    return entries


def format_text(src, lines):
    """Source lines -> output lines (paragraphs wrapped)."""
    out, para = [], []

    def flush():
        if para:
            out.extend(textwrap.wrap(" ".join(para), WIDTH,
                                     break_on_hyphens=False))
            para.clear()

    for n, line in lines:
        if not line.strip():
            flush()
            out.append("")
        elif line.startswith("  "):
            flush()
            if len(line) > WIDTH:
                raise SystemExit("%s:%d: literal line over %d characters"
                                 % (src, n, WIDTH))
            out.append(line)
        else:
            para.append(line.strip())
    flush()
    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return out


def columns(names, width=WIDTH):
    """Names in columns of 13 characters, as lines."""
    col = 13
    per = max(1, (width + 1) // col)
    lines, row = [], []
    for name in names:
        row.append(name.ljust(col) if len(row) < per - 1 else name)
        if len(row) == per:
            lines.append("".join(row).rstrip())
            row = []
    if row:
        lines.append("".join(row).rstrip())
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out_bin")
    ap.add_argument("out_md")
    ap.add_argument("--first", type=int, default=3)
    ap.add_argument("--commands")
    args = ap.parse_args()

    entries = parse(args.src)
    seen = {}
    for names, _, n in entries:
        for name in names:
            if name in seen:
                raise SystemExit("%s:%d: %s already defined at line %d"
                                 % (args.src, n, name, seen[name]))
            seen[name] = n

    if args.commands:
        cmds = re.findall(r"dta '([A-Z]+)', 0, a\(\w+\), BANK_\w+",
                          open(args.commands).read())
        missing = [c for c in cmds if "*" + c not in seen]
        if missing:
            raise SystemExit("no help for command(s): " + ", ".join(missing))

    texts = {}
    kinds = {"KEYWORDS": [], "COMMANDS": [], "TOPICS": []}
    for names, lines, _ in entries:
        texts[names[0]] = format_text(args.src, lines)
        if names[0].startswith("*"):
            kinds["COMMANDS"].append(names[0])
    # topics: entries whose first source line is prose; keywords: syntax
    for names, lines, _ in entries:
        main = names[0]
        if main in kinds or main.startswith("*") or main == "HELP":
            continue
        first = next((l for _, l in lines if l.strip()), "")
        (kinds["KEYWORDS"] if first.startswith("  ") else kinds["TOPICS"]).append(main)
    for k, v in kinds.items():
        intro = {"KEYWORDS": "BASIC keywords (*HELP <keyword>):",
                 "COMMANDS": "* commands (*HELP *<command>):",
                 "TOPICS": "Topics (*HELP <topic>):"}[k]
        texts[k] = [intro, ""] + columns(sorted(v))

    # pack the texts, then build the index in front of them
    index_names = sorted(seen)
    index_size = 6 + sum(len(n) + 4 for n in index_names)
    if index_size >= BANK:
        raise SystemExit("help index too big")
    banks = [bytearray()]
    pos = {}
    offset = index_size
    banks[0] += bytes(index_size)
    for main in [names[0] for names, _, _ in entries]:
        blob = ("\r".join(texts[main]) + "\r").encode("ascii") + b"\0"
        if len(blob) > BANK:
            raise SystemExit("%s: text over 16K" % main)
        if len(banks[-1]) + len(blob) > BANK:
            banks.append(bytearray())
        pos[main] = (args.first + len(banks) - 1, 0x8000 + len(banks[-1]))
        banks[-1] += blob

    index = bytearray(b"UHLP") + len(index_names).to_bytes(2, "little")
    for name in index_names:
        main = next(names[0] for names, _, _ in entries if name in names)
        bank, addr = pos[main]
        index += name.encode("ascii") + b"\0" + bytes([bank]) + addr.to_bytes(2, "little")
    banks[0][:index_size] = index

    with open(args.out_bin, "wb") as f:
        for b in banks:
            f.write(bytes(b) + b"\xff" * (BANK - len(b)))

    md = ["# U64 BBC BASIC help reference", "",
          "Generated from `src/help/help.txt` by `tools/genhelp.py`; the same",
          "text is in the cartridge: `*HELP <subject>`.", ""]
    for names, _, _ in entries:
        main = names[0]
        md.append("## %s" % main)
        if len(names) > 1:
            md.append("")
            md.append("Also: " + ", ".join("`%s`" % n for n in names[1:]))
        md.append("")
        md.append("```")
        md.extend(texts[main])
        md.append("```")
        md.append("")
    with open(args.out_md, "w") as f:
        f.write("\n".join(md))

    used = sum(len(b) for b in banks)
    print("help: %d entries, %d names, %d bytes in %d bank(s)"
          % (len(entries), len(index_names), used, len(banks)))


if __name__ == "__main__":
    main()
