# Design: graphics speed, REU use and maths tables

Status: proposal, 2026-10-07. Decisions: PLAN.md section 19; owner
requirements of 2026-10-07: section 9.

Graphics is the main use case of this BASIC. This document measures where
the time goes today and proposes how to make hires drawing fast, how to
use the REU for BASIC itself (including Upic), and whether maths tables
pay off.

## 1. Measurements (Ultimate 64-II, speed index 15 = 64 MHz)

Per call, loop overhead subtracted, with output capture off.

| Operation | Time | Note |
|---|---|---|
| FOR/NEXT, one pass | ~6 us | ~40x a 2 MHz BBC Micro |
| `A%=I%*3` | 35 us | integer arithmetic |
| `A=I%*1.5` | 100 us | 5-byte real |
| `A=SQR(I%)` | 305 us | |
| `A=EXP(1.5)` | 615 us | |
| `A=SIN(I%)` | 775 us | includes range reduction of I% up to 2000 |
| one VDU byte (`VDU 0`) | 100 us | MOS code in cartridge ROM |
| `LDA zp` / `STA abs` | ~40 / ~115 ns | per instruction with loop: writes are not penalised |

The same SIN loop takes 49 ms per call at 1 MHz: turbo gives the full
61-64x on BASIC itself. The numbers are simply what BBC BASIC's float
routines cost; a BBC Micro needs about twice the 1 MHz time.

Two consequences:

1. **The VDU path is the bottleneck for drawing.** BASIC sends every
   `PLOT k,x,y` as 6 VDU bytes (`VDU 25,k,x;y;`). At 100 us per byte that
   is 600 us of overhead per PLOT before a pixel is drawn: about 1,600
   PLOTs per second. The MOS runs from cartridge ROM, which the Ultimate
   64 reads at 1 MHz (PLAN.md section 12). In RAM the same path costs a
   few microseconds.
2. **Trigonometry dominates generative graphics.** A "Bubble Universe"
   with 62,500 points and 4 SIN/COS each spends 250,000 x 775 us = over
   3 minutes in SIN/COS alone.

## 2. Where the graphics code must run

Drawing code has to run from RAM to get turbo speed. Candidates:

| Place | Size | Free when |
|---|---|---|
| Font area `$C800-$CFFF` | 2K | in bitmap modes (text is drawn into the bitmap from a font kept elsewhere) |
| Resident page `$C400-$C7FF` | ~20 bytes left | never: full |
| Below HIMEM (`&7000-&7FFF`) | as chosen | always, at the cost of program space (as BBC graphics modes lower HIMEM) |
| RAM under the KERNAL `$E000-$FFFF` | 8K | not in bitmap modes (the bitmap lives there) |

Proposal: **REU overlays.** The REU holds the graphics kernel, the fonts
and the tables. On `MODE`, the MOS saves the text screen and font
(`$C000-$CFFF`) to the REU and DMAs the graphics kernel (2K) into
`$C800`. That is 4K at 1 MB/s, about 4 ms. Back to text mode reverses it.
Program space stays 30K in text and hires modes. OSWRCH's fast path
(printable characters, VDU queue, PLOT dispatch) moves into the resident
page or the overlay, so `VDU`/`PLOT` cost microseconds instead of 600 us.

## 3. Screen modes on the VIC-II

| BBC MODE | C64 mode | Resolution, colours | Bitmap | Colour |
|---|---|---|---|---|
| 0, 4 | hires bitmap | 320x200, 2 per 8x8 cell | `$E000` (under the KERNAL) | `$C000` |
| 1, 2, 5 | multicolour bitmap | 160x200, 4 per cell (1 shared) | `$E000` | `$C000` + `$D800` |
| 3, 6, 7 | text | 40x25 | - | - |
| new | Upic | 384x256, 16 per pixel | 48K, see section 5 | palette |

BBC graphics coordinates (1280x1024) are kept: x/4 for hires, x/8 for
multicolour, y via a 1024-entry row table (y*200/1024, flipped so y=0 is
the bottom, as on the BBC). Drawing writes into RAM under the KERNAL: the
kernel banks the KERNAL out around read-modify-write (SEI, `$01=$35`, a
RAM IRQ vector at `$FFFE` for the time it is out).

Per-pixel cost in RAM at 64 MHz: about 40-60 cycles for a line pixel (Bresenham
with incremental row/mask stepping, table lookups) = about 1 us. A full-screen
line is about 300 us; filled rectangles go per byte (8 pixels at once).

## 4. Tables

Tables in cartridge ROM cost about 1 us per byte read (1 MHz bus); in RAM
a few nanoseconds. So: tables are kept in the REU and copied into the RAM
overlay with the kernel.

| Table | Size | Use |
|---|---|---|
| bitmap row address (200 rows) | 400 B | y -> row base |
| BBC y -> row (1024) | 1 K | coordinate scaling (or computed: y*25/128) |
| pixel masks, column offsets | 64 B | x -> byte, bit |
| Upic x scaling (x*3/10, 1280) | 2.5 K | Upic coordinates |
| circle/ellipse octant steps | - | computed (midpoint), no table |
| sine/cosine, 1024 steps, 16-bit fixed point | 2 K | MOS circles, rotations; offered to programs |

**Maths for BASIC programs.** Two options:

Decided 2026-10-07: (a).

- **(a) Integer tables for programs, no interpreter change.** A command
  copies a ready table into the program's memory:
  `DIM S% 4096:*TABLE SIN S%` (1024 x 32-bit, value x 65536).
  `S%!(4*(A% AND 1023))` then costs about 30 us instead of 775 us for
  `SIN`: 25x faster. Fast integer-angle trig is what demos and generative
  graphics need. Also: COS, SQR of integers, 1/x.
- **(b) A "fast maths" BASIC build** with SIN/COS/EXP/LN/SQR patched to
  use tables with interpolation. Gain about 2-3x (the float work around
  the table lookup stays), full 5-byte precision has to be proven, and
  `make compare-core` no longer covers those routines. It was ruled out
  on 2026-10-04 (PLAN.md section 14). (a) gives more for graphics without
  that cost.

**Built (2026-10-16, mathtab.s, bank 8).** `*TABLE SIN|COS addr
[steps]`: steps 1024 (default), 512 or 256, 32-bit values x 65536, a
full turn in that many steps. The cartridge holds a quarter wave (257 x
16 bits, tools/genmath.py); the command unfolds it by symmetry, and
checks that the table lies between PAGE and HIMEM. 256 steps (1K) exist
because MODE 2 on Upic Lite leaves under 5K. Measured at turbo: four
SIN/COS 3.3 ms, the same four table reads (with INT and AND for the
index) 0.7 ms. The Schraf demos and GFXSPR use it; COS comes from the
SIN table a quarter turn on. SQR and 1/x are not done.

## 5. Upic and the REU

A Upic picture is 48K. BASIC needs RAM for itself (16K at `$8000`, at turbo
speed only from RAM), the MOS (4K) and the program. Together that is more
than 64K, so a Upic picture and a running BASIC program cannot both be in
RAM. Options:

- **A. Canvas in the REU, show by swapping (proposed).**
  - Drawing commands work on a Upic canvas kept in the REU, through a RAM
    cache of a few 256-byte columns (the Upic layout is column-major).
    Column-by-column drawing (Mandelbrot style) is fast; scattered points
    cost a column swap now and then (256 bytes, ~0.3 ms).
  - `*UPIC SHOW` (or a MODE) saves all RAM the program uses (`&0400-&7FFF`,
    BASIC's RAM copy, zero page, MOS state) to the REU, loads the canvas,
    and shows it until a key, then swaps everything back.
  - The program keeps its full 30K, and pictures can be saved and loaded
    in the `.upic` format.
  - A program cannot run *while* the picture is shown: the renderer needs
    almost all the CPU time anyway.
- **B. Compact 48 MHz Upic (36K, user idea 2026-10-04).** It still does
  not fit together with BASIC's 16K RAM copy and a usable program.
  Possible only with BASIC running from cartridge ROM (1 MHz) while
  showing. Kept as a later option.
- **C. Upic picture in RAM, BASIC from ROM.** Program space ~6K and BASIC
  at 1 MHz speed in the time the renderer leaves (~18% of the frame): too
  slow to be useful.

For the VIC-II bitmap modes the REU gives:
- double buffering: draw in RAM, store frames, DMA a frame back (8K in
  8 ms), so animation at 50 fps is possible;
- picture libraries;
- the text screen kept while in a graphics mode.

## 6. REU reservation

Assumption (owner): an REU is always present. Proposed layout of a 16 MB
REU:

| REU range | Size | Use |
|---|---|---|
| `$000000-$00FFFF` | 64K | MOS: overlays (graphics kernel, fonts incl. BBC font option, tables), saved text screen and font |
| `$010000-$01FFFF` | 64K | swap area: BASIC RAM while a Upic picture is shown; snapshot 0 (`*UNDO`) |
| `$020000-$02FFFF` | 64K | Upic canvas (48K) + column cache spill |
| `$030000-$0FFFFF` | 832K | bitmap frames and picture banks (`*SCREEN SAVE/LOAD n`), snapshots 1-n, command history, TRACE history |
| `$100000-$FFFFFF` | 15 MB | REU RAM disk (`/REU` drive, LOAD/SAVE/OPENIN at DMA speed), `*REU` commands and OSWORD for programs |

The MOS checks the REU size at start-up (done, `*STATUS`); with less than
1 MB the RAM disk shrinks first, with no REU graphics fall back to RAM
(less program space).

## 7. Order of work

1. OSWRCH fast path and VDU queue in RAM; measure `VDU`/`PLOT` again.
2. Hires/multicolour MODEs, PLOT (points, lines, fills, triangles,
   circles), GCOL, CLG, POINT, VDU 24/26/28/29, palette (VDU 19 ->
   Ultimate palette), graphics kernel as REU overlay.
3. `*TABLE` for programs.
4. Upic canvas, `*UPIC SHOW/LOAD/SAVE`.
5. REU RAM disk, snapshots.
6. SOUND/ENVELOPE (SID, Ultimate Audio) in the same RAM/REU scheme.

## 8. Decisions needed

See the questions asked on 2026-10-07 (recorded in PLAN.md when answered):
graphics kernel placement, Upic approach, maths tables (a)/(b), REU
reservation size, and which batch of firmware functions comes first
(docs/ULTIMATE_FUNCTIONS.md).

## 9. Owner requirements (2026-10-07)

### 9.1 What "BBC compatible" means

Compatibility is at the level of **BBC BASIC programs**, not of the BBC
Micro as a machine. This is not an emulator (not yet, at least).

| Compatible | Not compatible |
|---|---|
| The BBC BASIC 3.10 language, unchanged | The BBC memory map (screen at `&3000`/`&7C00`, MODE 7 teletext memory, `&FE00` SHEILA hardware) |
| The VDU drivers' behaviour: text, windows, VDU 4/5, 17-29, `VDU 23` character definitions | `?`/`!` access to BBC hardware or OS workspace |
| PLOT, DRAW, MOVE, GCOL, CLG, POINT, MODE semantics, palette (VDU 19) | Machine code written for the BBC (`CALL`, `USR`, `*RUN` of BBC binaries) |
| SOUND, ENVELOPE (on SID) | The MOS beyond the calls BASIC uses: the MOS call entry points exist, with the OSBYTE/OSWORD/OSFILE/... functions listed in `*HELP OSBYTE` etc. |
| Filing system statements (LOAD, SAVE, OPENIN, ...) on the Ultimate's storage | Disc/tape formats, DFS/ADFS command details |

Programs that only use BASIC and the VDU/sound interface run; programs
that poke the machine do not. README and `*HELP BBC` say the same.

### 9.2 BBC mode: charset and palette

In BBC mode (`*BBC`, PLAN.md section 16) the screen looks like a BBC Micro:

- **Palette**: the BBC's colours: black, red, green, yellow, blue,
  magenta, cyan, white, set as exact RGB through the Ultimate's palette
  registers (control commands `$51`-`$54`), and BBC logical-to-physical
  colour mapping per MODE (2, 4 or 16 logical colours; VDU 19). The
  flashing colours 8-15 alternate by raster interrupt, as on the BBC.
  Back in Commodore mode the C64 palette returns (`$54` reset).
- **Charset**: the BBC Micro's 8x8 font. The original bitmap is part of
  Acorn's MOS ROM, so it is not shipped; options: a redrawn look-alike
  font under the project's licence (proposed), and `*FONT LOAD <file>`
  for a font the user supplies (for example from their own MOS ROM dump).

### 9.3 Custom charsets and palettes

Both modes:

- `VDU 23,c,b0..b7` redefines a character (BBC standard: all 224 printable
  characters, not only 224-255 as on a BBC with default `*FX20`).
  Implemented: with an REU the definition goes into the REU font (graphics
  modes, codes 32-255) and, for 32-127, into the REU copy of the text font
  (restored on MODE changes) and, on the text screen, the live font at
  `$F000` (that RAM is bitmap in graphics modes, so it is only written on
  the text screen). Without an REU: the text screen only, until the next
  MODE change. MODE 7 keeps its teletext glyphs. OSWORD 10 reads a
  definition back.
- `*FONT LOAD <file> [C64|BBC|ASCII]` / `*FONT SAVE <file> [fmt]` /
  `*FONT DEFAULT` / `*FONT BBC` / `*FONT C64`: whole fonts. Implemented
  (`src/mos/font.s`, bank 2). The format is an explicit word (owner
  decision 2026-10-07; C64 when omitted): C64 = 2048 bytes in screen-code
  order (2050 with a load address also loads), BBC = 768 bytes,
  characters 32-127 in ASCII order (a BBC MOS ROM's `&C000-&C2FF`),
  ASCII = 2048 bytes, 0-255 in ASCII order. Every source goes glyph by
  glyph into the REU fonts (REU_FONT, REU_VICFONT) and, on the text
  screen, the live font; the start-up font is kept at REU `$1000` for
  `*FONT DEFAULT`. `*FONT BBC` uses the MOS 1.20 glyphs, shipped in good
  faith (owner decision; NOTICE.md). Without an REU only the text screen
  changes.
- `VDU 19,l,p,0,0,0` maps logical colour l to physical p (BBC);
  `VDU 19,l,16,r,g,b` sets an RGB colour (BBC Master/RISC OS extension),
  through the Ultimate's palette.
- `*PALETTE LOAD <file> [VPL]` / `SAVE <file>` / `RESET` / `BBC` / `C64`.
  Implemented (`src/mos/ulpal.s`, bank 2) with the firmware's palette
  commands (3.15a+, 1541ultimate #791: `$51` get, `$52` set, `$53` one
  colour, `$54` default). Two RGB tables in the REU (`$1800-$18BF`):
  the 16 C64 colours (read from the Ultimate at start-up, so a palette
  chosen in its menu stays; shown on every VIC-II screen, also after
  leaving Upic Lite and teletext, which used to reset it to the
  firmware's colours), and the logical colours of Upic Lite and teletext
  (the palette decodes their picture). Files: 48 bytes RGB in C64 colour
  order, or VICE `.vpl` text with the `VPL` word (owner decision: both).
  `*PALETTE BBC` gives the C64 colours the BBC colours map to the BBC's
  pure RGB; `C64` the firmware's colours; `RESET` the start-up palette.
  `VDU 19,l,16,r,g,b`: in Upic Lite that logical colour only; on VIC-II
  screens the C64 colour logical colour l shows (all logical colours
  showing it change); ignored in MODE 7. `VDU 19,l,24,...` (border) is
  not supported. Without an REU only `*PALETTE C64`.

### 9.4 Shapes: outline, solid and pattern fill

Every shape comes in three variants, using the BBC GXR/Master plot codes
so existing programs work:

| Shape | Outline | Solid fill | Pattern fill |
|---|---|---|---|
| line, point | PLOT 0-7, 64-71 | - | with a pattern colour |
| triangle | PLOT 224-231 (U64) | PLOT 80-87 | yes |
| rectangle | PLOT 216-223 (U64) | PLOT 96-103 | yes |
| parallelogram | PLOT 240-247 (U64) | PLOT 112-119 | yes |
| circle | PLOT 144-151 | PLOT 152-159 | yes |
| ellipse | PLOT 192-199 | PLOT 200-207 | yes |
| arc, segment, sector | PLOT 160-167 / 168-175 / 176-183 | | yes |
| flood fill | - | PLOT 128-135 / 136-143 | yes |

The BBC has no outline triangle, rectangle or parallelogram codes. The
GXR uses 72-79, 88-95, 104-111 and 120-127 for horizontal line fills
(also supported), so the outline codes go to blocks the GXR and RISC OS
leave free: 216-223 rectangle, 224-231 triangle, 240-247 parallelogram,
documented as U64 extensions. On a real BBC a program would draw these
shapes with DRAW.

**Pattern fill** is the BBC Master's ECF (extended colour fill): `GCOL
16..95` selects one of four patterns (`VDU 23,2..5,b0..b7` defines them,
`VDU 23,11` restores the defaults) for any fill, and a simple pattern
mode `VDU 23,6` for dotted lines. On the C64 bitmaps a pattern is 8x8
pixels (hires) or 4x8 (multicolour), drawn per byte, so a pattern fill
costs no more than a solid one.

### 9.5 Memory modes under program control

Originally planned around section 2's choices (graphics kernel in the REU
or below HIMEM). The RAM kernel of section 10.1 made those choices
disappear: the kernel costs no BASIC memory. One choice is left, and it
is implemented (owner decision 2026-10-08: "both" ways below):

- **Upic Lite or the VIC-II for BBC MODE 0-6.** On a 64 MHz Ultimate,
  Upic Lite shows the exact 320x256 picture, but keeps it below HIMEM
  (`&5800`, or `&3000` for MODE 1 and 2), as a BBC Micro does. The VIC-II
  version keeps HIMEM at `&8000` (200 lines).
- **BBC Master shadow modes** select it, as on a B+/Master where shadow
  RAM keeps the screen out of BASIC's memory: `MODE 128+n`, `*SHADOW`
  (from the next MODE on; `*SHADOW 1` back), OSBYTE `&72` (X = 0 shadow,
  1 normal; returns the old setting), OSBYTE `&75` bit 4 (current mode
  is shadow), OSBYTE `&85` with bit 7 of X. MODE 7 keeps its screen at
  `&7C00` also as a shadow mode (direct writes need it there).
- **`*MEMORY`** shows PAGE, TOP, LOMEM, VARTOP, HIMEM, free memory, the
  screen's place and the Upic Lite setting; `*MEMORY UPIC OFF|ON|AUTO` is
  a readable alias of `*SHADOW` / `*SHADOW 1` (ON and AUTO are the same:
  Upic Lite where the machine can show it).
- `MODE` follows the BBC rule, from BASIC itself: "Bad MODE" when the
  new HIMEM would cut into the variables (tested).

Later, with the REU RAM disk and Upic 64/48: `*MEMORY REU <size>` (how
much REU the system keeps) and the Upic canvas areas.

## 10. Screen modes (2026-10-07)

Owner request: all BBC Micro modes, the C64's own modes (text,
multicolour text, hires, multicolour hires), Upic 64 and Upic 48, and an
investigation of Acorn Archimedes modes inside Upic.

Decisions of 2026-10-07 (PLAN.md section 19): split kernel as in 10.1;
BBC modes 0/1/2/4/5 on Upic by default on a U64 (10.7); 32 text rows with
an 8x6 font on the VIC-II; mode numbers as proposed.

### 10.1 Memory layout: one RAM kernel, no HIMEM loss

A better layout than section 2's (REU overlay, HIMEM fallback): nothing
uses the RAM at `$D000-$DFFF` (under I/O) or `$E000-$FFFF` (under the
KERNAL) yet, and the VIC-II in bank 3 can read all of it.

| Range | Text modes | VIC bitmap modes |
|---|---|---|
| `$C000-$C3FF` | screen (characters) | screen matrix (cell colours) |
| `$C400-$C7FF` | resident MOS | resident MOS |
| `$C800-$CFFF` | **VDU/text core, 2K**: everything that needs I/O (colour RAM, VIC registers), runs with I/O in | the same |
| `$D000-$DFFF` | **drawing engine, 4K** under I/O: pure RAM work, runs with `$01=$34` (one switch pair per PLOT); multicolour cell colours through a core stub | the same |
| `$E000-$EFFF` | kernel tables, fonts in use (4K) | bitmap |
| `$F000-$F7FF` | font shown by the VIC | bitmap |
| `$F800-$FFF9` | tables | bitmap (to `$FF3F`) |
| `$FFFA-$FFFF` | RAM NMI/IRQ vectors into the resident MOS, for when the ROMs are out | the same |

- The kernel is copied from the cartridge into RAM at start-up and stays
  there: VDU, text output, windows, scrolling, and all drawing run at
  turbo speed, in every mode.
- **HIMEM stays `&8000` in all VIC modes.** The REU isn't needed for VIC
  graphics; it is still used for Upic, fonts, saved screens and tables.
- The KERNAL ROM can still be switched in over the bitmap for the serial
  bus routines: the VIC reads the RAM underneath.
- The C64 screen editor works only in text modes. In bitmap modes, line
  input (OSWORD 0) uses the MOS's own BBC-style line editor, with
  DELETE and the copy cursor.

### 10.2 BBC modes on the VIC-II

The VIC-II has 200 lines, the BBC 256. Mapping each BBC mode to the C64
mode that keeps its colours without colour clash where possible:

| MODE | BBC | VIC-II | Note |
|---|---|---|---|
| 0 | 640x256, 2 col, 80x32 text | hires 320x200 | half horizontal resolution; text 80x32 with a 4x6 font |
| 1 | 320x256, 4 col, 40x32 | multicolour 160x200 | 4 global colours, so no clash; half horizontal resolution |
| 2 | 160x256, 16 col, 20x32 | multicolour 160x200 | exact horizontally; at most 4 colours per 4x8 cell |
| 3 | 80x25 text, 2 col | hires bitmap, 4x8 font | exact |
| 4 | 320x256, 2 col, 40x32 | hires 320x200 | exact horizontally, no clash |
| 5 | 160x256, 4 col, 20x32 | multicolour 160x200 | exact horizontally, no clash |
| 6 | 40x25 text, 2 col | text mode | exact |
| 7 | teletext 40x25 | hires bitmap, 8x8 cells | per-cell foreground/background as teletext; mosaics, double height, held graphics |

- Graphics coordinates stay BBC: 1280x1024, y up. y goes through a
  1024-entry row table.
- The 32 text rows of modes 0, 1, 2, 4 and 5 are kept with a 6-pixel-high
  font, so `TAB(x,31)` still works.

### 10.3 C64 modes

| MODE (proposal) | Mode | Pixels, text | Graphics units |
|---|---|---|---|
| 100 | text | 40x25 | - |
| 101 | multicolour text | 40x25, 4x8 multicolour characters | - |
| 102 | extended background colour text | 40x25, 64 characters, 4 backgrounds | - |
| 103 | hires bitmap | 320x200, 2 colours per 8x8 cell, 40x25 text | 1280x800 |
| 104 | multicolour bitmap | 160x200, 4 colours per 4x8 cell, 20x25 text | 1280x800 |

- 1280x800 is RISC OS style: whole OS units per pixel (4x4 in hires, 8x4
  in multicolour), so there is no rounding.
- Colours: the 16 C64 colours, `GCOL`/`COLOUR` with the per-cell rules
  of the VIC. `VDU 19` changes the palette through the Ultimate.

### 10.4 Upic modes

| MODE (proposal) | Mode | Pixels | Units | Machines |
|---|---|---|---|---|
| 110 | Upic 64 | 384x256, 16 colours | 1536x1024 | Ultimate 64 Elite II, C64 Ultimate (64 MHz) |
| 111 | Upic 48 | 288x256 logical, 16 colours | 1536x1024 (x * 3 / 16; was 1152, circles came out 4/3 wide) | all U64 models (the 48 MHz path shows 3 of every 4 stored pixels; drawing uses only the shown ones) |

- A Upic picture is 48K, and BASIC needs RAM besides it, so the canvas
  lives in the REU (section 5).
- Drawing goes straight into the REU by DMA. A pixel is a read and a
  write of one byte, about 3-5 us at 64 MHz. A filled shape writes whole
  columns, because the Upic layout is column-major.
- **Showing**: `*UPIC SHOW` moves the program's RAM to the REU, loads the
  picture, shows it until a key is pressed, and moves everything back.
  This takes about 0.1 s each way.
- **Automatic show**, the proposed default: the picture also shows while
  BASIC waits for a key (GET, INPUT, INKEY with a long time) and when a
  program ends, so "draw, then wait for a key" programs just work.
  `*MEMORY UPIC AUTO|MANUAL` switches this (section 9.5).
- The canvas saves and loads in the Upic 1.3 file format.
- Renderer and timing come from ultimate-uci-oscar64's Upic module
  (Aleksi Eeben's technique, Christian Gleissner's 48 MHz path), ported
  to MADS with credit.

### 10.5 Archimedes modes inside Upic (investigation)

The Archimedes keeps the BBC's 256-line modes and the 1280x1024 OS-unit
system, and Upic has exactly 256 lines. Every Archimedes mode with 256
lines (or fewer), at most 384 pixels wide and at most 16 colours fits
Upic exactly, pixel for pixel:

| Archimedes MODE | Size, colours | On Upic 64 | On Upic 48 (288 logical) |
|---|---|---|---|
| 1, 4, 9 | 320x256, 4/2/16 | exact (32-pixel border left and right) | no: 320 > 288 |
| 2, 5 | 160x256, 16/4 | exact (pixels doubled) | exact |
| 50, 51, 52 | 320x240, 2/4/16 | exact | no |
| 3, 6 | text 80x25 / 40x25 | 40x25 exact; 80 columns with a 4-pixel font | 40x25 |
| 0, 8, 12 | 640x256, 2/4/16 | half horizontal resolution (320) | no |
| 11, 14 | 640x250, 4/16 | half horizontal resolution | no |
| 44, 45, 46 | 640x200, 2/4/16 | half horizontal resolution | no |
| 10, 13, 15, 21, 24, ... | 256 colours | no (Upic has 16 colours) | no |
| 18-20, 25-43 | 352 to 600 lines | no (Upic has 256 lines) | no |

- **Exact**: MODE 1, 2, 4, 5, 9 and 50-52, which are also the BBC's own
  MODE 1, 2, 4 and 5. Upic is the one display that shows BBC/Archimedes
  graphics at the original 256-line resolution.
- **Half horizontal resolution**: 0, 8, 11, 12, 14 and 44-46, with every
  second column of pixels dropped.
- **Not possible**: the 256-colour modes and the modes with more than
  256 lines.
- Proposal: Archimedes mode numbers 8-15 and 44-52 select the Upic
  version directly.
- `*DISPLAY UPIC` makes BBC MODE 0-2, 4 and 5 use Upic (exact, shown on
  demand). `*DISPLAY VIC` is the default: live display, 200 lines.

### 10.7 Live Upic for double-width modes (to prototype)

A full Upic picture can't stay in RAM next to BASIC. Modes with
double-width pixels can:

| Mode | Buffer | Program space |
|---|---|---|
| BBC MODE 2 (160x256, 16 colours) | 20K, 4 bits per pixel | about 12K |
| BBC MODE 5 (160x256, 4 colours) | 10K, 2 bits per pixel | about 22K |

- At 2 dots per pixel the renderer has about 15.75 cycles per pixel at
  64 MHz, double what full-resolution Upic gets. That is enough to unpack
  2- and 4-bit pixels through tables.
- The renderer runs from the raster IRQ and takes about 82% of the CPU.
  BASIC keeps running at about 11 MHz, around 6x a BBC Micro.
- Full-width modes (MODE 0, 1, 4) would need about 9 cycles per pixel
  against 7.9 available, so they are shown by swapping.
- To prove on the U64-II (64 MHz) and a U64 Elite (48 MHz path: 23.5
  cycles per pixel) before relying on it.

### 10.8 Upic Lite: live 320 x 256 with even pixels (proven 2026-10-07)

Instead of squeezing BBC text into 8x6 cells on the VIC-II's 200 lines:
live Upic-style renderers at 1 or 2 bits per pixel. Every pixel is one
dot wide, so the 320 pixels are centred with a 32-dot border on each side
(owner's question: "why not even pixels with a larger border?").

- **The trick**: `$D020` uses only 4 bits, and the Ultimate's palette is
  programmable. The palette follows bit 0 (2 colours) or bits 0-1 (4
  colours) of the colour index, so shifted copies of the picture byte go
  straight to `$D020`, without a colour table:
  - 1 bit: `lda col,y`, then per pixel `sta $d020` / `lsr` = 6 cycles;
  - 2 bits: `ldx col,y` / `stx $d020`, then `lda shr2/4/6,x` /
    `sta $d020` = 8 cycles, with every 4th byte load an immediate operand
    patched before the line (Upic's trick; 20 patches, 160 cycles).
  A dot is 7.875 cycles at 64 MHz. `tools/upiclite_gen.py` schedules each
  store into its pixel's dot and pads with nop/bit; the last store comes
  at cycle 2514.
- **Measured** on the U64-II from the VIC stream
  (`tests/proto/upiclite_proto.py`): picture from dot 32 to 351, 1-pixel
  stripes are exactly 1 dot each, 2-pixel stripes 2 dots, 4-colour bars
  40 pixels each, text and circle as drawn.
- **BBC colours**: in these modes the logical colours *are* the hardware
  palette entries, so VDU 19 just rewrites the palette (UCI, firmware
  3.15+).
- **48 MHz** (5.875 cycles per dot): 1-dot pixels are impossible; the
  160-wide modes (2 dots per pixel) work there.
- **Memory**: column-major buffer below HIMEM where the BBC has its
  screen: MODE 4/0 10K (HIMEM &5800), MODE 1 20K (&3000), MODE 5 10K,
  MODE 2 20K. Frame loop `$E000`, renderer `$E100` (up to `$E8FF`), shift tables
  `$E900`, shapes' RAM copy `$EC00-$FFF9`, all in, which these modes leave free. The engine for these modes
  is a separate 4K image copied to `$D000` on MODE.
- **CPU left for BASIC**: a rendered line takes ~3400 of 4032 cycles;
  with the 56 lines outside the picture about 18% of the CPU, ~11 MHz.
- **Text**: 32 rows of full 8x8 characters, as on the BBC.

### 10.9 Upic Lite in the MOS (integrated 2026-10-07)

- **Choice**: MODE 0, 1 and 4 use Upic Lite when `ul_ok`: the speed probe
  (Christian Gleissner's raster-timed loop, run from RAM) finds 64 MHz
  and the Ultimate accepts a palette reset. The probe is repeated until
  two results agree: right after the cartridge starts the Ultimate ran
  at reduced speed (92 lines instead of 16).
- **Layout**: Upic Lite engine (`gfx.s` with GXUL = 1) at `$D000`, frame
  loop at `$E000`, renderer at `$E100`, shift tables at `$F000`, all from
  bank 3; buffer at &5800 (MODE 0/4) or &3000 (MODE 1); OSBYTE &84/&85
  give these as HIMEM, so BASIC's MODE checks and moves HIMEM as on a
  BBC ("Bad MODE" if the program is in the way).
- **Interrupt**: raster interrupt at line $10 (`ul_irq` in the core):
  one frame from line $18, TIME + 2, then the normal keyboard part
  (`irq_keys`); the CIA timer interrupt is off meanwhile. A frame whose
  interrupt comes too late (an engine call with interrupts off, a long
  DMA) is skipped rather than drawn wrongly.
- **Palette**: entry i = BBC colour pal[i AND 1] or pal[i AND 3], sent as
  RGB with control command $52; VDU 19/20 resend it; leaving Upic Lite
  resets the Ultimate's palette ($54).
- **Measured** (U64-II): HIMEM &5800/&3000, a vertical line one dot wide
  over all 256 lines (E2E test `gfx_upiclite`, from the VIC stream),
  4-colour text and fills; 5000 empty FOR loops take 20 cs while the
  picture shows (3 cs in MODE 7): BASIC keeps ~15% of the CPU, still
  ~2.5x a BBC Micro.
- **MODE 2 and 5** (added 2026-10-07): 160 x 256 with 2-dot pixels, 4
  bits per pixel (low nybble straight to `$D020`, high one through the
  `>>4` table) or 2; 15.75 cycles per pixel, no patching; HIMEM &3000 /
  &5800. Bank 4 holds the Upic Lite images (four renderers, tables,
  engine, shapes), the help moved to bank 5.
- **MODE 3 and 6**: 25 rows of 10 lines (250), as the BBC.
- **To do**: a designed 4x8 font for MODE 0's 80 columns (now pairs of
  pixels ORed together: bold); MODE 2/5 on 48 MHz machines (11.75
  cycles per pixel there: possible, needs calibrating on a U64 Elite);
  flashing colours 8-15.

### 10.10 Teletext MODE 7 (2026-10-07)

- Decision: teletext after an explicit MODE 7; start-up keeps the C64
  text screen and its full-screen editor (MODE 100 returns to it).
- Screen memory at &7C00 (40 x 25 codes, HIMEM &7C00 as on the BBC);
  a third engine image (`ttx.s`, bank 3, 2.2K with the font) draws a row
  into the VIC-II hires bitmap after every change: a teletext cell is an
  8 x 8 cell with one foreground and one background colour, the VIC-II's
  own rule. OSBYTE &87 reads the code at the cursor.
- SAA5050 rules: set-at / set-after control codes, mosaics (2 x 3,
  contiguous and separated, letters stay letters in graphics mode),
  hold graphics, new/black background, double height (a bottom-half row
  shows the lower halves of its own characters and never starts a pair).
- With palette commands (firmware 3.15+) the 8 C64 colours teletext uses
  show the BBC's pure RGB; leaving MODE 7 resets the palette.
- Direct writes to &7C00 and flashing: the 60 Hz interrupt (`tt_irq`)
  compares 5 rows per interrupt with a shadow copy and redraws changed
  rows; every 30 interrupts the flash phase changes. The teletext engine
  never lets interrupts in during a call, so the interrupt can use it.
- Not yet: conceal, the SAA5050's smoothed glyphs and its character set
  differences (# / pound / _).

### 10.11 Upic full: the picture in the REU (step 1, 2026-10-14)

Owner's decisions (PLAN.md section 26): split output (a live VIC-II
console for text, the picture for graphics), automatic showing plus
`*UPIC SHOW`, the picture at REU &90000 and the swap area at &A0000.

- **Picture**: REU bank 9 holds a Upic v1.3 file image: the 256-byte
  header (palette at $D0) at &90000, byte column c at &90100 + c * 256.
  `*UPIC LOAD` takes v1.3 files (49408 bytes) or bare bitmaps (49152:
  a header is made, C64 palette); `*UPIC SAVE` writes v1.3; `*UPIC
  CLEAR c` makes a header and fills the bitmap by REU DMA from one byte
  (fixed C64 address).
- **Showing** (`*UPIC SHOW`, upic.s): interrupts off; &0400-&0FFF to
  the swap bank; the renderer for the machine's speed (`cpu_class` from
  the start-up probe) to &0400 (2440 bytes, from tools/upic_gen.py:
  Aleksi Eeben's renderer via ultimate-uci-oscar64's Upic module, the
  48 MHz path by Christian Gleissner), the frame loop and variables to
  &0D90 (in the gap before the table), the nybble table to &0E00, the
  viewer to &0F00; the picture's palette (UCI). The viewer switches the
  cartridge off (RAM to &CFFF), moves &1000-&CFFF to the swap bank and
  the picture in, shows frames until a key is pressed and released (or
  ESCAPE, or a host's `$0334` = `$AA`), and puts everything back; then
  &0400-&0FFF, the mode's palette, and TIME on by 2 cs per frame.
  About 0.1 s each way.
- **Measured** on the U64-II (64 MHz): a picture of 16 bars of 24
  pixels shows every bar on its 24 dots on all 256 lines; the program
  goes on with its variables after the show; SAVE writes the loaded
  file's bytes; CLEAR 3 gives 98,304 cyan dots (E2E test `upic`). The
  48 MHz path is generated as the library's (tested there on a U64
  Elite) but not yet seen here.
- **Remote**: the mailbox is out during a show; `$0334` tells hosts
  (REMOTE_DEV.md). Each REST read stops the CPU: a disturbed Upic line.

### 10.12 Upic full: MODE 110/111 (step 2, built 2026-10-14)

- **Routing without core space**: the core (2 bytes free) decides text
  vs graphics by `vtype`; MODE 110/111 are graphics modes to it (vtype
  1, `eng_kind` 3), so every VDU code goes to the engine. A third
  engine variant (gfx.s with GXUL = 1 and GXUP = 1) sends text to the
  VIC-II text screen (screen codes at $C000, colour RAM through the
  core's io_colput) and graphics to the REU picture. The only core
  change: `oc_glyph` passes the ASCII code (glyph_get leaves it in X
  with an REU) as the engine's argument (`txa`, 1 byte).
- **The console**: the VIC-II text mode (font at $F000, as MODE 100),
  40 x 25; the BBC line editor works there as in every graphics mode;
  the cursor is a reversed character; COLOUR n sets the character's
  colour (BBC colours as MODE 100), COLOUR 128+n reverses (one
  background, $D021, as the VIC-II's text mode).
- **The picture**: x >> 2 and y >> 2 of the OS units (1536 x 1024 for
  MODE 110: 384 x 256); MODE 111 also 1536 x 1024, x * 3 >> 4 onto its
  288 logical pixels (owner, 2026-10-14: round circles; 1152 units made
  its pixels 4/3 wide on the screen). A
  logical pixel x of MODE 111 is byte column 2 (x div 3) + (x mod 3 >
  0): mod 0 the whole byte (pixels 4m and 4m+1, so it looks the same on
  64 MHz machines), 1 the low nybble, 2 the high one.
- **REU access**: a stub image at $E000 (free with a text console; run
  with $01 = $35, I/O in, KERNAL out) reads and writes picture bytes
  (REU page = column + 1, offset = row: the engine's column-major
  addressing as Upic Lite's), fills, and moves column segments through a
  256-byte buffer; the engine (under I/O) calls it. A pixel is a read
  and a write: about 20 us. Rectangles (CLG, PLOT 101, the shape
  module's spans) go per byte column: one fill DMA per column for
  "store", a read-modify-write of the segment otherwise.
- **Space**: the variant engine, the stub and the Upic renderers in a
  new cartridge bank 8 (the help moves to 9).
- **Not**: VIC-II sprites (Upic shows none: an error, as in Upic Lite).
- **Measured** on the U64-II (E2E `upic_mode`): MODE 110 rectangle
  24,576 dots (192 x 128), a 192-dot line, POINT 1/0/2; MODE 111 144
  logical pixels = 192 dots a line; CLG in colour 1; mode changes in
  every direction; HIMEM &8000 (no sprite pages: sprites are refused).
- **Palette**: the picture's header palette follows the mode's logical
  colours (entry l = the C64 colour pal[l], as MODE 2); VDU 19,l,p and
  VDU 19,l,16,r,g,b change entry l, VDU 20 all (upbank.s).
- **Found on the way**: the KERNAL's cursor blink was switched on at
  waits in every mode (in the graphics modes it toggled a colour-matrix
  byte, in Upic full a console character); now text screen only, and
  the prompt shows the engine's cursor in the graphics modes (it was
  missing until the first key; its blink also stopped after 128
  jiffies).

### 10.13 Upic full: automatic showing (step 3, 2026-10-14)

- The stub sets bit 0 of UP_DIRTY ($0335) on every picture write; a
  show, a MODE and the start clear it; bit 7 is *UPIC AUTO OFF.
- With the picture changed, MODE 110/111 shows it by itself (owner's
  decision): at the BASIC prompt (a program ended; until a key, not
  typed), in OSRDCH (GET: until a key, which a KERNAL SCNKEY then puts
  in the buffer for GET) and in OSBYTE &81 with 50 cs or more (INKEY:
  at most that long; TIME advances by the frames shown, so INKEY times
  out after it). `*UPIC SHOW n` shows for at most n centiseconds.
- The show's variables are in page 3 ($0334-$033A, unused by the
  KERNAL): bank code is ROM, and writes to it land in BASIC's RAM copy
  under the cartridge (found when the first version corrupted BASIC).

### 10.6 Order of work

1. RAM kernel at `$C800-$DFFF`, font moved to `$F000`, RAM vectors; the
   VDU driver moves from cartridge ROM into the kernel. Measure `VDU`
   again; every existing E2E test must still pass.
2. MODE switching and the VIC modes (BBC 0-7, C64 100-104), CLS/CLG,
   COLOUR/GCOL, VDU 19/20/24/26/28/29.
3. PLOT: points, lines (solid, dotted), triangles, rectangles,
   parallelograms, circles, ellipses, arcs/segments/sectors, flood
   fill, each with outline, solid and pattern (ECF) variants; POINT.
4. Text in bitmap modes (VDU 5, the 6-high and 4-wide fonts), the line
   editor, teletext MODE 7.
5. Upic 64/48: REU canvas, DMA drawing, show/auto-show, load/save.
6. Archimedes modes on Upic.

### 10.14 The GXR remainder (2026-10-14)

`src/mos/gxblock.s`, bank 5 (`.local gxb`). It went to bank 5 because
bank 3 was 377 bytes short. The shapes' bank copy hands groups 9, 11
and 23 on (`bs_gxr`, a `farcall`). Upic Lite's engine sends them there
too, as with sprites (group 29): its RAM copy of the shapes has no room.
The bank sets `vmode_ul` back after every group (`bsp_go`). All of it
reads the screen with `GX_POINTDEV` and draws through `gx_call`, so it
works the same in every engine (tested: VIC-II, Upic Lite, Upic full).

- **PLOT 72-79**: the row at the point, left and right over pixels of
  the background colour; **88-95**: to the right over pixels that are
  not the background colour. One `GX_RECT` in the plot colour and
  action, without a pattern (as the flood fill). The graphics cursor is
  not moved to the run's ends.
- **PLOT 184-191**: the rectangle between gq and gp to gc (bottom left);
  k AND 3 = 1 moves (the background colour left behind), 2 and 3 copy.
  Pixel by pixel, rows and columns in the direction that reads every
  pixel before it is overwritten. A move clears each source pixel right
  after reading it, so overlaps are correct. Source pixels outside the
  window are left out; the destination is clipped.
- **VDU 23,2-5**: native ECF patterns. They are decoded from the mode's
  BBC byte layout (2, 4 or 16 colours) into the engine's 2 x 4 patterns
  (`pats`): the first two pixels of the first four bytes.
- **VDU 23,6** and **\*FX 163,242** (dot-dash pattern): accepted, but
  dotted lines keep every second pixel. The pattern needs a 64-byte table
  (one byte per bit keeps the engine's pixel step at +10 bytes), and no
  shared RAM is free for it: the Upic full engine has 12 bytes left.
- **\*FLOOD, \*NOFLOOD, \*GXR, \*NOGXR**: accepted (`gxr.cmd_accept`).

## 11. 80 columns dropped (owner, 2026-10-10)

MODE 0 (80x32 with a 4-pixel font) and MODE 3 (80x25) are gone: the
4-pixel text was hard to read on a C64 picture. A program asking for
them gets the 40-column twin: MODE 0 -> MODE 4 (the same graphics and 2
colours), MODE 3 -> MODE 6 (`bk_mode` maps before the table lookup;
OSBYTE &87 reports the mode actually set). The squeeze of 8-pixel glyphs
to 4 (`e_squeeze`, `sh_squeeze`) and the 80-column cases of
`ul_choose` are removed. The demos needing 80 columns (Hanoi) left the
demo set.

**Back (owner, 2026-10-15)** with the 4x6 font (font46.s): the
squeezed 8-pixel glyphs were what read badly. MODE 0 (80x32 in 6-line
rows, 2 colours, graphics as MODE 4) and MODE 3 (80x25 in 8-line rows)
are in the mode table again; `fnt46` swaps the font in for any mode
with 4-pixel cells (`vmode_cw` = 4: MODE 0, 3 and VIC-II MODE 1). Both
stay on the VIC-II: Upic Lite's 320-wide picture puts colour fringes on
1-pixel strokes (visible in MODE 4 too, but 8-pixel glyphs survive them;
the 4x6 ones do not). HIMEM &8000 (OSBYTE &85 too). *CAT uses as many
20-character columns as the width allows; *HELP texts are wrapped at
39 when built (genhelp.py) and stay 40 wide.

### 11.1 Characters read back in the bitmap modes (2026-10-15)

OSBYTE &87 and the line editor's COPY now read characters in every mode.
Upic full's console is the text screen; it is read at &C000 + row * 40 +
column, by the engine's text cursor. In the bitmap modes, `gxb_chr`
(gxblock.s, bank 5) recognises the character from its pixels, as a BBC
Micro does in its graphics modes:

1. The cell is read with `GX_POINTDEV` (column × cell width, row × cell
   height). A pixel counts as set when it is not the text background
   colour.
2. For each glyph 32-126, `glyph_get` fetches the glyph as the engine
   gets it: the REU font, or the character ROM without an REU.
3. The glyph's rows are laid out as the engine draws them:
   - 8-line cells: as they are.
   - Upic Lite's 10-line cells: the last two rows blank.
   - 6-line cells: the 4x6 font's rows 0-5; for an 8x8 glyph, the six
     rows `e_rows6` keeps. That drops the blank bottom row (else row 0)
     and the first row equal to the next kept one (else row 2).
4. The first glyph whose rows equal the cell's, within the leftmost
   cell-width bits, is the answer.

The line editor hides the copy cursor's mark while it reads, because the
mark is drawn into the cell.

Limits:

- About 30 ms per character on the VIC-II, about 115 ms in Upic Lite.
- Without an REU, the 4-pixel modes (0, 1, 3) draw the left halves of
  the ROM glyphs, which are not unique ("C" matches "@" first).
- Cells outside the graphics window read as set (`GX_POINTDEV` answers
  &FF there).

## 12. CharPad fonts and maps (owner, 2026-10-15)

`*MAP` and `*FONT LOAD` read CharPad's CTM project files, versions 6-9
(82 is an early 8), as the CharPad C64 3.69 Pro help describes them
("File Format - CTM (V6)" to "(V9)"). The code is `src/mos/cmap.s` in
bank 8 (BANK_UP).

- The file is loaded whole into the REU's scratch bank (`$0A`, the
  Upic swap bank, as `*SPRITE LOAD` and the GXR use it) with one
  `LOAD_REU` (or a copy from `/REU`: `fs_reuopen0`, `rd_xopen0`) and
  parsed there with 1- and 2-byte DMA reads. The blocks come in a fixed
  order; their markers are skipped, not checked.
- The character set: the first 256 images become the text font
  (`put_scr` per glyph, then `fo_mkascii`), as `*FONT LOAD` of a C64
  font. `*FONT LOAD` tries CTM first when there is an REU (the file's
  first bytes, not its name).
- The map is expanded once, at load: each cell is a character, tiles
  replaced by their cells. Each cell gets its colour by the project's
  colour method: per project (`COLR_CHR` / the base colour), per tile
  (the tile's colour) or per character (V6/V7: the attribute's low
  nybble; V8/V9: the first byte of each character's colour entry, 1-3
  bytes by display mode). The screen colour (BG0) goes to `$D021`.
  Multicolour, ECM and the bitmap modes' screen-matrix colours are not
  used: the C64 text screen shows the characters hires.
- The map lives in the REU's last bank but one (the last is `*SPOOL`'s
  and speech's), so the RAM disk ends 128K before the REU's end
  (`rd_resbank`). Layout: `&0000` header ("MAP", width and height, 16
  bits each), `&0100` the character colours, `&0200` page `&0700` saved
  during a load (the colour table is built there), `&1000` the
  characters and `&8800` the colours, a row of width bytes per map row
  without gaps: up to 65535 wide or high and 30720 characters in all
  (owner, 2026-10-16; 255 x 255 before). Of CharPad's own examples
  (1814 files) 1659 fit (976 with 255 x 255).
- The load writes the cells as one run through 128-cell buffers
  (characters in MOSBUF, colours at &0600) and flushes them by DMA, so
  a row may be any width; its variables lie at &0680-&06FE (BASIC's
  string buffer page, free between statements).
- `*MAP DRAW mx,my,w,h AT col,row` clips to the map and the 40 x 25
  screen and copies each row twice by DMA (characters to the screen
  at `HIBASE`, colours to `$D800`): a full screen is 50 transfers, well
  within a frame, so a program can scroll by redrawing. Text modes only.
  It keeps ahead of the beam (2026-10-16, scrolling tore after `*FX
  19`, as finding the command and reading its arguments at 1 MHz took
  the copy into the next frame): with the raster at lines 32-250 it
  waits for line 251, then copies top row first at about 6 lines a row
  while the beam needs 8 from line 51. Programs need no `*FX 19`.
- `*MAP LOAD` switches the text screen off (`$D011` bit 4) while it
  installs the font and expands the map: the screen's spaces showed as
  the new set's character 32 meanwhile.
- `*MAP GET mx,my` sets M% to the character (0 outside the map).
  Arguments are numbers or A%-Z% (as the BASIC V commands, bvcmd.s), 16
  bits; DRAW's w and h count as 255 at most.
- Tiles may have at most 127 cells (the offsets in a tile stay 8-bit).
- Loading runs in bank 8 at 1 MHz: one DMA per character, the map
  cell read once per tile row. CharPad's Foodroid (V9, 112 x 44, 4 x 4
  tiles) loads in 2.5 s, Hexagone (40 x 25) in 1.2 s, a 400 x 24 level
  in 5.2 s; the largest map takes about 10 s. To make room, the 4x6
  font (font46.s) moved from bank 8 to bank 6. Checked against a Python model of the format on
  both, and on 1814 example files for the parsing.

## 13. The PETSCII mode (owner, 2026-10-16)

`*PETSCII` / `*ASCII` / `*SEQ file` (petscii.s, bank 6; decisions in
PLAN.md). The ASCII text modes stay as they are: their font's 128 normal
glyphs are full (95 ASCII, 33 graphics) and the reverse half serves the
cursor and COLOUR 128+n, so the PETSCII graphics live in this mode only.

- Output: OSWRCH (core.s) tests `pet_on` after the remote capture and
  the debug filter, so `*SPOOL` and the remote see the bytes. `wr_pet`
  sends a byte to the KERNAL's CHROUT unchanged (quote mode as on a
  C64), except: VDU 22 (MODE) and 23 with their parameters stay BBC's,
  line input (OSWORD 0, `inlinein`) is echoed the BBC way, and LF does
  nothing (CR starts the new line; BBC's new line is LF, CR).
- The font: the character ROM's upper case/graphics set at FONT
  ($F000), its lower/upper set at $F800. $D018 bit 1 selects between
  them, which is what the KERNAL changes for codes 14 and 142, so case
  switching works unchanged. The six bytes from $FFFA (RAM vectors) are
  not written: the last glyph of the lower/upper set loses its bottom
  rows there. SHIFT+C= stays locked ($0291 = $80) unless a program sends
  CHR$(9); every way out locks it again.
- The cursor: MODE 100 starts the KERNAL's blink (BBC-style, a cursor
  while programs run), and a blink showing as the cursor moves on stays
  as a reverse cell (seen in the PETSCII demo's box). `*PETSCII` hides
  it and stops the blink (wk_hide), as a C64 runs programs without one;
  GET shows it while it waits. The ASCII modes keep the BBC behaviour.
- Input: GET and INKEY (OSRDCH, OSBYTE &81) return the PETSCII code
  instead of translating it; typed lines (the line editor) are as ever.
- The way out: `*ASCII`, MODE (bk_mode clears `pet_on`), or an error:
  `*PETSCII` puts `pet_brkv` (core.s) on BRKV, which ends the mode and
  then jumps to BASIC's handler (the old vector, `pet_obrk`), so the
  message is readable. The resident page had no room for a hook in the
  BRK handler. The ASCII font comes back from its REU copy, so the mode
  needs an REU.
- Room: the VDU core in RAM was full; font_to_reu's loop building the
  ASCII-order REU font at start-up moved to bank 2's `fo_mkascii`
  (which already did the same after `*FONT LOAD`).
- `*SEQ file [LOWER|UPPER]`: OSFIND/OSBGET (any filing system), a
  clear screen first, then the character set asked for (screens from
  Petmate and the VDC Screen Editor start without a clear or case code
  and rely on the 40-column wrap), bytes straight to CHROUT, ESCAPE
  stops, a key ends; a mode it switched on ends again with CLS.

## 14. The fast path for the BASIC V graphics commands (2026-10-16)

PLAN.md 27 item 1, after measuring (without the remote's output capture,
which throttles OSWRCH while the PC drains its ring: the "1 ms per VDU
byte" first seen was that): a VDU byte costs about 15 us, PLOT 69 0.06
ms, but *POINT 2 ms, as OSCLI's lookup and the argument parsing run in
cartridge code at 1 MHz. In the Upic Lite modes everything takes about
7-8 times as long (the CPU draws the live picture): *POINT 13.8 ms, PLOT
0.48 ms.

- fastcmd.s, a RAM image on CLIV in the graphics modes (vtype 1): it
  recognises POINT, LINE, RECTANGLE [FILL], CIRCLE [FILL] and ELLIPSE
  [FILL] (whole words, any case), reads the arguments as bvcmd.s does
  (A%-Z%, decimal, &hex, negative) and sends the same VDU bytes at turbo
  speed. Anything else (other commands, abbreviations, anything it does
  not read cleanly) jumps to v_cli, the normal path, which also raises
  the errors: it never raises one itself.
- fastpath.s (bank 5) holds the image twice, assembled at $1000 and
  $2000; copying it to page P, a byte that differs between the copies is
  an internal address's high byte and becomes copy-1's - $10 + P. 767
  bytes in three pages below HIMEM, below the sprite multiplexer when it
  is in (`*SPRITE ON`/`OFF` at the prompt move it); `fp_place` runs at
  the end of every MODE. OSBYTE &84 returns its page, &85 counts 3 pages
  for the graphics modes; text modes and MODE 7 keep CLIV on v_cli.
- Measured on the U64-II: *POINT 2.1 -> 0.08 ms (VIC-II), 13.8 -> 0.40
  ms (Upic Lite); *LINE 0.14 / 0.72 ms. A small circle takes 27 ms in
  the VIC-II modes against 5.7 ms in Upic Lite, with PLOT 149 as much as
  with *CIRCLE: the VIC-II engine's circle, a separate matter.
