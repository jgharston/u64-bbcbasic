# Classic BBC BASIC programs

Well-known BBC BASIC programs, run unchanged or nearly so, to show that
U64 BBC BASIC runs BBC BASIC programs. Each file's header names the
original author and source and lists every change (zlib licence, see
`LICENCE`). Converted from BBCSDL's tokenised `.bbc` files with
`tools/bb4wtxt.py`.

| Program | Author | Shows | Changes |
|---|---|---|---|
| `sine.bas` | John A. Coll, 1981 | MODE 1, dotted lines (PLOT 21), VDU 5 text along a curve, VDU 19 | BBCSDL first line removed; ends with a key instead of a WAIT loop |
| `hanoi.bas` | Richard T. Russell, 1982 | MODE 3 (80 x 25), recursion, colour codes in strings | BBCSDL first line, OFF, *REFRESH and WAIT removed |

`files/`: the file-handling examples of BBC BASIC (Z80) by Richard T.
Russell (serial, random-access and indexed files, merging, sorting),
unchanged, converted to text. They exercise the filing system: OPENIN,
OPENOUT, OPENUP, PRINT#, INPUT#, BGET#, BPUT#, PTR#, EXT#, EOF#, CLOSE#.
Run them in a directory of your own (`*DIR`); the write programs come
before the read ones (f-wser1 then f-rser1, and so on).

Run one from a PC: `tools/u64remote.py run demos/classics/sine.bas`, or
copy it to the Ultimate's storage and `CHAIN` it.

On a 64 MHz Ultimate (Elite II, C64 Ultimate) these modes use Upic Lite:
256 lines as on the BBC. Elsewhere the VIC-II versions are used.
