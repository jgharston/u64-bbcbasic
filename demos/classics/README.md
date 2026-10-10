# Classic BBC BASIC programs

Well-known BBC BASIC programs, run unchanged or nearly so, to show that
U64 BBC BASIC runs BBC BASIC programs. Each file's header names the
original author and source and lists every change (zlib licence, see
`LICENCE`). Converted from BBCSDL's tokenised `.bbc` files with
`tools/bb4wtxt.py`.

| Program | Author | Shows | Changes |
|---|---|---|---|
| `sine.bas` | John A. Coll, 1981 | MODE 1, dotted lines (PLOT 21), VDU 5 text along a curve, VDU 19 | BBCSDL first line removed; ends with a key instead of a WAIT loop |
| `fern.bas` | QBASIC original from PC Magazine; BB4W version by David Williams | MODE 2, 80,000 points of an iterated function system | BBCSDL first line removed; MODE 8 is MODE 2; CASE is four IF lines; GCOL 2 is GCOL 0,2; OFF is VDU 23,1 |
| `persian.bas` | Acorn Computers (IBM version 1986) | MODE 2, GCOL 3 (EOR) line patterns, VDU 29 origin | BBCSDL first line removed; MODE 18 is MODE 2, the origin the screen centre |
| `polygon.bas` | John A. Coll (IBM version 1986) | MODE 2, filled triangles (PLOT 85), arrays, random polygons | BBCSDL first line removed; MODE 18 is MODE 2 |
| `animal.bas` | Teichholtz and North (Creative Computing), BBC BASIC version by Chris Atkinson and Richard Russell | Guess the Animal: a learning game, its knowledge in `ANIMAL.DAT` (OPENIN, PRINT#, INPUT#) | none (from agon-bbc-basic's examples); run it in a writable directory with `ANIMAL.DAT` |

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
