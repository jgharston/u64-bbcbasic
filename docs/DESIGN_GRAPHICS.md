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
- `*FONT LOAD <file>` / `*FONT SAVE <file>` / `*FONT DEFAULT` / `*FONT BBC`
  / `*FONT C64`: whole fonts, 2K files (C64 charset format, so existing
  C64 fonts work). Fonts are kept in the REU; switching is a DMA.
- `VDU 19,l,p,0,0,0` maps logical colour l to physical p (BBC);
  `VDU 19,l,16,r,g,b` sets an RGB colour (BBC Master/RISC OS extension),
  through the Ultimate's palette.
- `*PALETTE LOAD <file>` / `SAVE` / `RESET` / `BBC` / `C64`.

### 9.4 Shapes: outline, solid and pattern fill

Every shape comes in three variants, using the BBC GXR/Master plot codes
so existing programs work:

| Shape | Outline | Solid fill | Pattern fill |
|---|---|---|---|
| line, point | PLOT 0-7, 64-71 | - | with a pattern colour |
| triangle | PLOT 88-95 (U64) | PLOT 80-87 | yes |
| rectangle | PLOT 104-111 (U64) | PLOT 96-103 | yes |
| parallelogram | PLOT 120-127 (U64) | PLOT 112-119 | yes |
| circle | PLOT 144-151 | PLOT 152-159 | yes |
| ellipse | PLOT 192-199 | PLOT 200-207 | yes |
| arc, segment, sector | PLOT 160-167 / 168-175 / 176-183 | | yes |
| flood fill | - | PLOT 128-135 / 136-143 | yes |

The BBC has no outline triangle, rectangle or parallelogram codes. The
MOS adds them on the plot codes the GXR leaves for them in its numbering
(88-95, 104-111, 120-127), documented as U64 extensions; on a real BBC a
program would draw them with DRAW. (To check against the GXR manual
before implementing: 88-95 may be "triangle in background" there.)

**Pattern fill** is the BBC Master's ECF (extended colour fill): `GCOL
16..95` selects one of four patterns (`VDU 23,2..5,b0..b7` defines them,
`VDU 23,11` restores the defaults) for any fill, and a simple pattern
mode `VDU 23,6` for dotted lines. On the C64 bitmaps a pattern is 8x8
pixels (hires) or 4x8 (multicolour), drawn per byte, so a pattern fill
costs no more than a solid one.

### 9.5 Memory modes under program control

The memory layout choices (section 2: graphics kernel in the REU overlay
or below HIMEM; Upic canvas in the REU; text screen kept in the REU) are
settable from a program, not only automatic:

- `*MEMORY` shows the layout; `*MEMORY GRAPHICS REU|HIMEM|AUTO` chooses
  where the graphics kernel goes, `*MEMORY UPIC ON|OFF` reserves the Upic
  areas, `*MEMORY REU <size>` sets how much REU the system keeps (the rest
  is the RAM disk).
- The same through OSBYTE (`A%=&A0..`, read and write), so a program can
  check and set it with `USR`/`CALL` and then rely on HIMEM, as BBC
  programs do after `MODE`.
- `MODE` follows the BBC rule: it may move HIMEM, but only with no
  program variables in the way ("Bad MODE" otherwise, as on the BBC).
