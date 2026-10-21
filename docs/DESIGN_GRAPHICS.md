# Design: graphics

How U64 BBC BASIC draws: measurements, the RAM kernel, the screen modes
(the VIC-II's, Upic Lite, teletext, Upic full), charsets and palettes,
shapes and the GXR, maths tables, CharPad maps, the PETSCII mode and the
fast path for the `*` graphics commands. Sprites: DESIGN_SPRITES.md.

## 1. Measurements (Ultimate 64-II, 64 MHz)

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

Two consequences, which shaped the design:

1. **Code in cartridge ROM runs at bus speed.** The Ultimate 64 reads the
   cartridge at 1 MHz, so the VDU path from ROM cost 100 us a byte, 600
   us a PLOT (`VDU 25,k,x;y;`). The VDU driver and the drawing engine
   therefore run from RAM (section 3): a VDU byte costs about 15 us, a
   PLOT 69 about 0.06 ms. The `*` graphics commands have their own RAM
   fast path (section 11).
2. **Trigonometry dominates generative graphics.** A "Bubble Universe"
   with 62,500 points and 4 SIN/COS each spends 250,000 x 775 us = over
   3 minutes in SIN/COS alone: hence `*TABLE` (section 2).

## 2. Maths tables for programs

The interpreter stays bit-exact (`make compare-core`), so SIN/COS/SQR
are not patched. Instead `*TABLE` copies a ready integer table into the
program's memory (it must lie between PAGE and HIMEM):

- `*TABLE SIN|COS addr [steps]` (`mathtab.s`, bank 8): steps 1024
  (default), 512 or 256, 32-bit values x 65536, a full turn in that many
  steps. The cartridge holds a quarter wave (257 x 16 bits,
  `tools/genmath.py`); the command unfolds it by symmetry. 256 steps (1K)
  exist because MODE 2 on Upic Lite leaves under 5K. COS is the SIN
  table a quarter turn on. Measured at turbo: four SIN/COS 3.3 ms, the
  same four table reads (with INT and AND for the index) 0.7 ms.
  `S%!(4*(A% AND 1023))` costs about 30 us against 775 us for `SIN`.
- `*TABLE SQR addr [n]` and `*TABLE RECIP addr [n]` (`mathtab2.s`, bank
  5): square roots and 1/x as 32-bit values x 65536.

The Schraf demos, GFXSPR and the showcase use them.

## 3. Memory layout: one RAM kernel, no HIMEM loss

The RAM at `$D000-$DFFF` (under I/O) and `$E000-$FFFF` (under the
KERNAL) holds the kernel, and the VIC-II in bank 3 can read all of it.

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
  graphics; it is used for Upic, fonts, saved screens and tables.
- The KERNAL ROM can still be switched in over the bitmap for the serial
  bus routines: the VIC reads the RAM underneath.
- The C64 screen editor works only in text modes. In bitmap modes, line
  input (OSWORD 0) uses the MOS's own BBC-style line editor, with
  DELETE and the copy cursor.

## 4. What "BBC compatible" means

Compatibility is at the level of **BBC BASIC programs**, not of the BBC
Micro as a machine. This is not an emulator.

| Compatible | Not compatible |
|---|---|
| The BBC BASIC 3.10 language, unchanged | The BBC memory map (screen at `&3000`/`&7C00`, MODE 7 teletext memory, `&FE00` SHEILA hardware) |
| The VDU drivers' behaviour: text, windows, VDU 4/5, 17-29, `VDU 23` character definitions | `?`/`!` access to BBC hardware or OS workspace |
| PLOT, DRAW, MOVE, GCOL, CLG, POINT, MODE semantics, palette (VDU 19) | Machine code written for the BBC (`CALL`, `USR`, `*RUN` of BBC binaries) |
| SOUND, ENVELOPE (on SID) | The MOS beyond the calls BASIC uses: the MOS call entry points exist, with the OSBYTE/OSWORD/OSFILE/... functions listed in `*HELP OSBYTE` etc. |
| Filing system statements (LOAD, SAVE, OPENIN, ...) on the Ultimate's storage | Disc/tape formats, DFS/ADFS command details |

Programs that only use BASIC and the VDU/sound interface run; programs
that poke the machine do not. README and `*HELP BBC` say the same.

## 5. Screen modes

| MODE | Size, colours | Text | On a 64 MHz U64 |
|---|---|---|---|
| 0 | 320x200, 2 | 80x32 (4x6 font) | VIC-II hires |
| 1 | 320x256, 4 | 40x32 | Upic Lite |
| 2 | 160x256, 16 | 20x32 | Upic Lite |
| 3 | text, 2 | 80x25 (4x6 font in 8-line rows) | VIC-II hires |
| 4 | 320x256, 2 | 40x32 | Upic Lite |
| 5 | 160x256, 4 | 20x32 | Upic Lite |
| 6 | text | 40x25 | Upic Lite |
| 7 | teletext | 40x25 | VIC-II hires (section 5.5) |
| 100 | C64 text | 40x25 | VIC-II text |
| 103 | 320x200, 16 (2 per 8x8 cell) | 40x25 | VIC-II hires |
| 104 | 160x200, 16 (4 per 4x8 cell) | 20x25 | VIC-II multicolour |
| 110 | 384x256, 16 per pixel | 40x25 console | Upic full (section 6) |
| 111 | 288x256 logical, 16 | 40x25 console | Upic full, 48 MHz path |

- 48 MHz Ultimates use the VIC-II versions of MODE 0, 1 and 4 (a 1-dot
  pixel needs 64 MHz), and VICE those of every mode. `MODE 128+n` asks
  for the VIC-II version on any machine (section 5.4).
- Graphics coordinates stay BBC: 1280x1024, y up, through a 1024-entry
  row table on the VIC-II's 200 lines. MODE 103/104 use 1280x800 (RISC
  OS style: whole OS units per pixel). Upic full uses 1536x1024.
- On the VIC-II the 32 text rows of modes 0, 1, 2, 4 and 5 are kept with
  a 6-pixel-high font, so `TAB(x,31)` still works. The 80-column modes
  (0, 3) use the 4x6 font (`font46.s`, `fnt46` swaps it in for any mode
  with 4-pixel cells); they stay on the VIC-II, as Upic Lite's 320-wide
  picture puts colour fringes on 1-pixel strokes, which 4-pixel glyphs do
  not survive. *CAT uses as many 20-character columns as the width
  allows.
- The C64 screen editor works only on the text screen. In the bitmap
  modes, line input (OSWORD 0) uses the MOS's own BBC-style line editor.

### 5.1 Upic Lite: live 320 x 256 with even pixels

Instead of squeezing BBC text into 8x6 cells on the VIC-II's 200 lines:
live Upic-style renderers at 1 or 2 bits per pixel. Every pixel is one
dot wide, so the 320 pixels are centred with a 32-dot border on each side.

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
  160-wide modes (2 dots per pixel) and MODE 6 use Upic Lite there too.
- **Memory**: column-major buffer below HIMEM where the BBC has its
  screen: MODE 4/0 10K (HIMEM &5800), MODE 1 20K (&3000), MODE 5 10K,
  MODE 2 20K. Frame loop `$E000`, renderer `$E100` (up to `$E8FF`), shift tables
  `$E900`, shapes' RAM copy `$EC00-$FFF9`, all in, which these modes leave free. The engine for these modes
  is a separate 4K image copied to `$D000` on MODE.
- **CPU left for BASIC**: a rendered line takes ~3400 of 4032 cycles;
  with the 56 lines outside the picture about 18% of the CPU, ~11 MHz.
- **Text**: 32 rows of full 8x8 characters, as on the BBC.

### 5.2 Upic Lite in the MOS

- **Choice**: MODE 1 and 4 use Upic Lite when `ul_ok`: the speed probe
  (Christian Gleissner's raster-timed loop, run from RAM) finds 64 MHz
  and the Ultimate accepts a palette reset. The probe is repeated until
  two results agree (right after the cartridge starts the Ultimate can
  run at reduced speed).
- **Layout**: Upic Lite engine (`gfx.s` with GXUL = 1) at `$D000`, frame
  loop at `$E000`, renderer at `$E100`, shift tables at `$F000`, all from
  bank 4; buffer at &5800 (MODE 4) or &3000 (MODE 1); OSBYTE &84/&85
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
- **MODE 2 and 5**: 160 x 256 with 2-dot pixels, 4 bits per pixel (low
  nybble straight to `$D020`, high one through the `>>4` table) or 2;
  15.75 cycles per pixel, no patching; HIMEM &3000 / &5800. Bank 4 holds
  the Upic Lite images (the renderers, tables, engine, shapes).
- **MODE 3 and 6**: 25 rows of 10 lines (250), as the BBC.
- **Not supported**: flashing colours 8-15 in the Upic Lite modes.

### 5.3 C64 modes

MODE 100 (the C64 text screen), 103 (hires, 2 colours per 8x8 cell) and
104 (multicolour, 4 colours per 4x8 cell), with the 16 C64 colours and
the VIC-II's per-cell rules; `VDU 19` changes the palette through the
Ultimate.

### 5.4 Upic Lite or the VIC-II: shadow modes

The RAM kernel costs no BASIC memory. One choice is left to programs:

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

### 5.5 Teletext MODE 7

- Teletext after an explicit MODE 7; start-up keeps the C64 text screen
  and its full-screen editor (MODE 100 returns to it).
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
- Not supported: conceal, the SAA5050's smoothed glyphs and its
  character set differences (# / pound / _).

## 6. Upic full (MODE 110/111)

A Upic picture (384 x 256, every pixel its own colour; Aleksi Eeben's
technique, Christian Gleissner's 48 MHz path, through
ultimate-uci-oscar64's Upic module) is 48K, and BASIC needs its RAM
besides it, so the picture lives in the REU. Text goes to a live VIC-II
console, graphics to the picture, which shows on request (`*UPIC SHOW`)
and by itself when a program waits or ends. A program cannot run while
the picture is shown: the renderer needs almost all of the CPU.

### 6.1 The picture in the REU

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
  About 0.1 s each way. The viewer maps its caller's bank back
  (`curbank`).
- **Music**: interrupts are off and the sound engines' RAM is swapped out
  during a show, so the music pauses: `upmute.s` (bank 7) sets the SIDs'
  volume to 0 and stops Ultimate Audio's channels while a MOD plays,
  and gives the SIDs their volume back afterwards; the MOD goes on where
  it stood.
- **Measured** on the U64-II (64 MHz): a picture of 16 bars of 24
  pixels shows every bar on its 24 dots on all 256 lines; the program
  goes on with its variables after the show; SAVE writes the loaded
  file's bytes; CLEAR 3 gives 98,304 cyan dots (E2E test `upic`). The
  48 MHz path is generated as the library's (tested there on a U64
  Elite).
- **Remote**: the mailbox is out during a show; `$0334` tells hosts
  (REMOTE_DEV.md). Each REST read stops the CPU: a disturbed Upic line.

### 6.2 MODE 110/111

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
  288 logical pixels (so circles stay round). A
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
- **Space**: the variant engine, the stub and the Upic renderers in
  cartridge bank 8.
- **Not**: VIC-II sprites (Upic shows none: an error, as in Upic Lite).
- **Measured** on the U64-II (E2E `upic_mode`): MODE 110 rectangle
  24,576 dots (192 x 128), a 192-dot line, POINT 1/0/2; MODE 111 144
  logical pixels = 192 dots a line; CLG in colour 1; mode changes in
  every direction; HIMEM &8000 (no sprite pages: sprites are refused).
- **Palette**: the picture's header palette follows the mode's logical
  colours (entry l = the C64 colour pal[l], as MODE 2); VDU 19,l,p and
  VDU 19,l,16,r,g,b change entry l, VDU 20 all (upbank.s).
- **Cursor**: the KERNAL's cursor blink is for the text screen only; in
  the graphics modes the prompt shows the engine's cursor.

### 6.3 Automatic showing

- The stub sets bit 0 of UP_DIRTY ($0335) on every picture write; a
  show, a MODE and the start clear it; bit 7 is *UPIC AUTO OFF.
- With the picture changed, MODE 110/111 shows it by itself: at the
  BASIC prompt (a program ended; until a key, not
  typed), in OSRDCH (GET: until a key, which a KERNAL SCNKEY then puts
  in the buffer for GET) and in OSBYTE &81 with 50 cs or more (INKEY:
  at most that long; TIME advances by the frames shown, so INKEY times
  out after it). `*UPIC SHOW n` shows for at most n centiseconds.
- The show's variables are in page 3 ($0334-$033A, unused by the
  KERNAL): bank code is ROM, and writes to it would land in BASIC's RAM
  copy under the cartridge.

## 7. Charsets and palettes

The BBC look on the C64: `*FONT BBC` (the MOS 1.20 glyphs) and
`*PALETTE BBC` (the colours the BBC's map to, as pure RGB through the
Ultimate's palette registers, control commands `$51`-`$54`).

- `VDU 23,c,b0..b7` redefines a character (BBC standard: all 224 printable
  characters, not only 224-255 as on a BBC with default `*FX20`).
  With an REU the definition goes into the REU font (graphics
  modes, codes 32-255) and, for 32-127, into the REU copy of the text font
  (restored on MODE changes) and, on the text screen, the live font at
  `$F000` (that RAM is bitmap in graphics modes, so it is only written on
  the text screen). Without an REU: the text screen only, until the next
  MODE change. MODE 7 keeps its teletext glyphs. OSWORD 10 reads a
  definition back.
- `*FONT LOAD <file> [C64|BBC|ASCII]` / `*FONT SAVE <file> [fmt]` /
  `*FONT DEFAULT` / `*FONT BBC` / `*FONT C64`: whole fonts
  (`src/mos/font.s`, bank 2). The format is an explicit word (C64 when
  omitted): C64 = 2048 bytes in screen-code
  order (2050 with a load address also loads), BBC = 768 bytes,
  characters 32-127 in ASCII order (a BBC MOS ROM's `&C000-&C2FF`),
  ASCII = 2048 bytes, 0-255 in ASCII order. Every source goes glyph by
  glyph into the REU fonts (REU_FONT, REU_VICFONT) and, on the text
  screen, the live font; the start-up font is kept at REU `$1000` for
  `*FONT DEFAULT`. `*FONT BBC` uses the MOS 1.20 glyphs, shipped in good
  faith (NOTICE.md). Without an REU only the text screen
  changes.
- `VDU 19,l,p,0,0,0` maps logical colour l to physical p (BBC);
  `VDU 19,l,16,r,g,b` sets an RGB colour (BBC Master/RISC OS extension),
  through the Ultimate's palette.
- `*PALETTE LOAD <file> [VPL]` / `SAVE <file>` / `RESET` / `BBC` / `C64`.
  (`src/mos/ulpal.s`, bank 2) with the firmware's palette
  commands (3.15a+, 1541ultimate #791: `$51` get, `$52` set, `$53` one
  colour, `$54` default). Two RGB tables in the REU (`$1800-$18BF`):
  the 16 C64 colours (read from the Ultimate at start-up, so a palette
  chosen in its menu stays; shown on every VIC-II screen, also after
  leaving Upic Lite and teletext), and the logical colours of Upic Lite and teletext
  (the palette decodes their picture). Files: 48 bytes RGB in C64 colour
  order, or VICE `.vpl` text with the `VPL` word.
  `*PALETTE BBC` gives the C64 colours the BBC colours map to the BBC's
  pure RGB; `C64` the firmware's colours; `RESET` the start-up palette.
  `VDU 19,l,16,r,g,b`: in Upic Lite that logical colour only; on VIC-II
  screens the C64 colour logical colour l shows (all logical colours
  showing it change); ignored in MODE 7. `VDU 19,l,24,...` (border) is
  not supported. Without an REU only `*PALETTE C64`.

## 8. Shapes: outline, solid and pattern fill

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

### 8.1 The rest of the GXR

`src/mos/gxblock.s`, bank 5 (`.local gxb`). The shapes' bank copy hands groups 9, 11
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
  shared RAM is free for it.
- **\*FLOOD, \*NOFLOOD, \*GXR, \*NOGXR**: accepted (`gxr.cmd_accept`).

## 9. Characters read back in the bitmap modes

OSBYTE &87 and the line editor's COPY read characters in every mode.
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

## 10. CharPad fonts and maps

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
  without gaps: up to 65535 wide or high and 30720 characters in all.
  Of CharPad's own examples (1814 files) 1659 fit.
- The load writes the cells as one run through 128-cell buffers
  (characters in MOSBUF, colours at &0600) and flushes them by DMA, so
  a row may be any width; its variables lie at &0680-&06FE (BASIC's
  string buffer page, free between statements).
- `*MAP DRAW mx,my,w,h AT col,row` clips to the map and the 40 x 25
  screen and copies each row twice by DMA (characters to the screen
  at `HIBASE`, colours to `$D800`): a full screen is 50 transfers, well
  within a frame, so a program can scroll by redrawing. Text modes only.
  It keeps ahead of the beam (finding the command and reading its
  arguments at 1 MHz would take the copy into the next frame): with the
  raster at lines 32-250 it
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
  in 5.2 s; the largest map takes about 10 s. Checked against a Python
  model of the format, and on 1814 example files for the parsing.

## 11. The fast path for the * graphics commands

Measured (without the remote's output capture, which throttles OSWRCH
while the PC drains its ring): a VDU byte costs about 15 us, PLOT 69
0.06 ms, but *POINT 2 ms without a fast path, as OSCLI's lookup and the argument parsing run in
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
  with *CIRCLE: the VIC-II engine's circle algorithm.
## 12. The PETSCII mode

`*PETSCII` / `*ASCII` / `*SEQ file` (petscii.s, bank 6). The ASCII text modes stay as they are: their font's 128 normal
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
- The ASCII-order REU font is built at start-up by bank 2's
  `fo_mkascii` (as after `*FONT LOAD`).
- `*SEQ file [LOWER|UPPER]`: OSFIND/OSBGET (any filing system), a
  clear screen first, then the character set asked for (screens from
  Petmate and the VDC Screen Editor start without a clear or case code
  and rely on the 40-column wrap), bytes straight to CHROUT, ESCAPE
  stops, a key ends; a mode it switched on ends again with CLS.

