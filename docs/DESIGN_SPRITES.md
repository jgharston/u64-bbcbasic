# Sprites (design)

Two kinds: the VIC-II's hardware sprites through `*SPRITE` commands and
an OSWORD for fast movement (positions in BBC graphics coordinates; up
to 32 sprites, multiplexed by raster interrupt), and the GXR's software
sprites drawn into the picture (section 6), with the sprite editor
`*SEDIT` (section 7).

## 1. Commands

| Command | Does |
|---|---|
| `*SPRITE n ON x,y` | show sprite n (0-31) at BBC coordinates x,y (0-1279, 0-1023; 0,0 bottom left, the sprite's bottom left corner) |
| `*SPRITE n OFF` | hide it |
| `*SPRITE n SHAPE s` | its shape (0-63) |
| `*SPRITE n COLOUR c [c1 c2]` | its colour (logical colour, as GCOL); multicolour shapes: the two shared colours |
| `*SPRITE n SIZE w h` | double width / height (1 or 2) |
| `*SPRITE n BEHIND` / `FRONT` | behind or in front of the picture |
| `*SPRITE DEFINE s b0,b1,...,b62` | shape s from 63 bytes (24 x 21, 3 bytes a row; as VDU 23 for characters) |
| `*SPRITE LOAD s file` | shapes from a SpritePad (.spd) or raw 64-byte file, from shape s on |
| `*SPRITE` | the sprites shown: number, position, shape |

OSWORD &71 (the network's JSON is &70): block +0 sprite, +1 action (0
off, 1 on/move, 2 shape, 3 colour), +2/+3 x, +4/+5 y, +6 shape, +7
colour: one call moves a sprite without command parsing, for loops.
`ADVAL(-40-n)` or OSBYTE: the collision bits of sprite n since the last
read (sprite-sprite and sprite-picture), from the VIC-II registers per
band.

## 2. Multiplexing

Up to 32 virtual sprites on the 8 hardware sprites: each frame the
shown sprites are sorted by Y (an insertion sort, as most stay in
order), then a raster interrupt chain gives each hardware sprite to the
next virtual one once the previous has been drawn (Y + 21 lines, or 42
when doubled), as Oscar64's virtual sprites do. At most 8 sprites on
one raster line; more are skipped in that band (as on every C64
multiplexer). The interrupt joins the existing ones: irq_main (CIA,
VIC-II modes) and Upic Lite's frame interrupt; MODE 7's refresh runs
from the same frame.

Coordinates: BBC x 0-1279 -> VIC x = x / 4 + 24 (320 wide), BBC y
0-1023 -> VIC y = 50 + (1023 - y) * 200 / 1024 (the 200-line VIC-II
modes); with Upic Lite's 256 lines the scale follows the mode. The MOS
keeps the BBC values and converts when a sprite is set.

## 3. Where the shapes are

The VIC-II reads sprite shapes only from its bank, here bank 3
($C000-$FFFF), and that bank is nearly full:

| Range | In use |
|---|---|
| $C000-$C3FF | screen matrix; sprite pointers $C3F8-$C3FF |
| $C400-$CFFF | resident MOS, RAM core: full |
| $D000-$DFFF | the drawing engine (under the I/O area): full |
| $E000-$FF3F | the bitmap (graphics modes, MODE 7); in the text screen only the font at $F000-$F7FF |
| $FF40-$FFBF | free: 2 shapes |

- **Text screen (MODE 100, MODE 3/6 on the VIC-II):** $E000-$EFFF and
  $F800-$FF3F are free: 92 shapes held in place, the simple case.
- **Bitmap modes and MODE 7:** 2 blocks. The 64 shapes are kept in the
  REU; the multiplexer copies a band's shapes into the free blocks just
  before the band (64 bytes a sprite by DMA, about 64 cycles each). With
  2 blocks, at most 2 different shapes per band (enough for a player
  and bullets; section 5).
- **Upic Lite (MODE 1, 2, 4, 5, 6 on 64 MHz machines):** VIC-II sprites
  do **not** show (tested on the U64); the Upic picture
  replaces the VIC-II's whole output. The same sprite in MODE 132 (MODE 4
  on the VIC-II, `*SHADOW`) shows, from the free block at $FF40. So on a
  64 MHz machine a program with sprites uses MODE 128+n (or `*SHADOW`),
  as BBC Master programs choose shadow modes; `*SPRITE` in a Upic Lite
  mode gives an error that says so.

## 4. The multiplexer

- `*SPRITE ON` / `OFF` switches the multiplexer, as `*SOUND` the sound
  engine: ON copies the image (`spritemux.s`, 5 pages)
  below the mode's HIMEM (&7B00, or &7700 under MODE 7's &7C00) and
  lowers HIMEM; OFF stops the interrupt and gives the pages back. At the
  prompt BASIC's HIMEM moves at once; in a program from the next MODE.
  OSBYTE &84/&85 report the lowered HIMEM while sprites are on.
- After every MODE `bk_mode` calls `spr_modehook` (bank 5): the image is
  reinstalled below the new HIMEM with all sprites hidden; in Upic Lite
  it stays out.
- The interrupt (`mx_irq` on $0314) handles only the VIC-II raster
  interrupt and passes everything else to the vector before it: at line
  251 an insertion sort by Y and the first 8; then each next virtual
  sprite once the one 8 before it has finished (Y + 22 lines, +21 more
  double high). Collision registers are read at every raster interrupt
  and credited to the virtual sprites on the hardware ones.
- Robustness: Y is frozen per frame (the sort's copy, `skey`), and each
  hardware sprite keeps the line its virtual sprite ends (`hwend`): BASIC
  moving a sprite during the frame cannot make a reuse cut the one still
  drawn. A raster
  line passed while setting `$D012` places at once (not from the frame
  interrupt, whose target is the next frame); the frame interrupt only
  acts at its own line.
- The limit stays the VIC-II's: at most 8 sprites on a raster line; a
  9th on the same lines drops out for that frame (seen as flicker).
  `demos/sprites/BALLS.bas` keeps 32 balls in four bands of 8, so never
  more than 8 share a line: no flicker (tested on the U64).
- Shapes: 64 in REU bank 1 at $1000, copied to $E000 (pointers $80-$BF)
  in the text screen. `*SPRITE DEFINE s` takes 126 hex digits (the
  remote's 74-byte line limit: from programs).
- OSWORD &71 as in section 1, plus action 4: the collision bits (cleared
  when read).

## 5. Graphics modes, MODE 7, LOAD, multicolour

- **Shape blocks.** In the VIC-II graphics modes and MODE 7 the shapes
  go into two blocks, $FF40 and $FF80 (pointers $FD, $FE). Per block
  the multiplexer keeps the shape in it and the line until which a
  sprite still draws from it. A sprite whose shape is in a block uses
  it; otherwise the block that comes free first gets the shape by REU
  DMA (64 bytes, in the raster interrupt: foreground REU transfers have
  interrupts off, so the registers are free), and the sprite waits for
  that line if it must. So sprites on the same lines can have at most 2
  different shapes; a 3rd is placed once a block is free (too late: it
  drops out where they meet). Shapes stay in their block from frame to
  frame; DEFINE and LOAD empty the blocks.
- **The frame** resets every hardware sprite's and block's end line and
  places what is free at once (`mx_atframe`: compared with line 0 of
  the coming frame, not the raster line), the rest by raster interrupt.
- **MODE 7**'s refresh runs from the CIA interrupt, which the
  multiplexer passes on; the drawing engine has interrupts off between
  its yields: both can delay a raster interrupt (a sprite may then drop
  out for a frame while much is drawn).
- **`*SPRITE LOAD s file`**: the file (up to 17
  pages) into REU bank 1 at $2000 (scratch), then the shapes from s on
  into $1000: SpritePad 'SPD' version 1 (9-byte header, the count in
  byte 4), a 3-byte header (length 64n + 3), or plain 64-byte shapes.
- **Multicolour**: `*SPRITE n MULTI ON|OFF`
  per sprite; `*SPRITE COLOURS a,b` sets the pair the VIC-II shares
  between all sprites ($D025, $D026). `COLOUR` only ever sets a
  sprite's own colour.
- SPD versions 1-5 (layouts from SpritePad Pro 3.20's help,
  "File Format - SPD (V1)" to "(V5)"): the header is 9 bytes (V1), 16
  (V2, V3) or 20 (V4, V5), and the sprites follow it in every version.
  The count is byte 4 + 1 (V1) or the 16-bit value at bytes 5-6 (V2-V5).
  The count matters because tiles and animations can come after the
  sprites. The multicolours are at bytes 7/8 (V1) or &0E/&0F (V2-V5).
  Each shape's 64th byte is SpritePad's attribute (`MYXVCCCC`: multicolour,
  Y/X expand from V5, overlay, colour) and stays in the REU with the shape.
- SPD colours: `*SPRITE n SHAPE s` also sets the
  sprite's colour (CCCC, a C64 colour) and multicolour flag (M) from a
  shape that came from an SPD file; a later `*SPRITE n COLOUR` overrides.
  A marker per shape at REU bank 1 &3100 (64 bytes, cleared at
  start-up) says which shapes have one: `*SPRITE LOAD` sets it for SPD
  files and clears it for raw ones, `*SPRITE DEFINE` clears it. The
  expand and overlay bits and the file's multicolour pair are not used.

## 6. GXR software sprites

The BBC Master's / GXR's sprites: drawn into the picture by the engine,
so they work in every graphics mode, Upic Lite and Upic full included
(where the VIC-II's sprites cannot show).

GXR, as found in its ROM (tobylobster's annotated reassembly) and on its
sprite disc (ZornsLemma/GXR, discs/..._Sprites.orig.ssd):

- `*SGET n` / `VDU 23,27,1,n,0,0,0,0,0,0`: the rectangle between the
  last two graphics points becomes sprite n, selected. `*SCHOOSE n` /
  `VDU 23,27,0,n,...`: select. `PLOT 232-239` (&E8-&EF, group 29):
  the selected sprite with its bottom-left corner at x,y, every pixel
  through the GCOL action (no transparency), clipped to the window.
- `*SDELETE n`, `*SNEW`, `*SRENUMBER n,m` (m replaced), `*SLOAD f`
  (replace all), `*SMERGE f` (add), `*SSAVE f`, `*SSPACE n` (pages of
  sprite memory), `*SEDIT n` (editor).
- File: 2 bytes length, 1 byte count, then per sprite 6 bytes (width in
  bytes - 1, height - 1, data size low/high, mode, number) and the data:
  rows top to bottom, each row's bytes right to left, the mode's screen
  bytes (MODE 0/4 1 bit, 1/5 2 bits interleaved b7/b3..., 2 4 bits
  b7/b5/b3/b1). Checked by decoding the disc's S.ROCKETS, S.CHOPPER etc.

Here: every pixel as its logical colour (one byte),
so a sprite plots in any mode, sized in the device pixels it was taken
in; `*SMASK n c` (new) leaves colour c out when plotting; *SLOAD/*SMERGE
read real GXR files (decoded by their mode) and our own format;
`*SSAVE` writes ours; `*SEDIT` edits them (section 7).

- Store: REU bank 1, &4000 the selected sprite's descriptor (data
  address, width, height, mask, valid), &4006 its number, &4008 the data
  end; &4100 a directory of 256 entries (address, width, height, mask,
  used); data &4800-&FFFF (46K). Delete and replace close the gap.
- Plot (bank 3, group 29): the descriptor, then a small loop copied to
  MOSBUF (turbo speed: bank code runs at 1 MHz) reads the pixels from
  the REU one by one (fixed C64 address, the REU's address counting on;
  interrupts off for the whole sprite, so the sound interrupt cannot
  move the REU registers) and plots each through the engine's PSET with
  the GCOL action (k AND 3 as for shapes), skipping the mask colour.
  Upic Lite: its engine sends group 29 to bank 3 as well (its RAM copy
  of the shapes has no room).
- **Measured** (U64-II): `*SGET`/PLOT 237/EOR/mask
  in MODE 132, 2 and 110; the GXR sprite disc's S.CHOPPER (MODE 2,
  26 x 16) and S.DOG (MODE 1, 44 x 24) load pixel-exact; 100 plots of a
  32 x 32 sprite take 1.65 s (MODE 132), 1.74 s (MODE 2, Upic Lite),
  1.85 s (MODE 110): about 50 sprites a second. E2E test `gxr` (with GXR
  files made from the format, as the disc's own files are Acornsoft's).
- Replacing a sprite keeps *SGET's box and the sprite number being
  written apart from the variables `gx_delete` uses when it moves data.
- Code: the store and commands in bank 5 (gxr.s; bank 8 is full), the
  plot in the shapes' bank 3 copy (bs_sprite) with its loop run from
  MOSBUF; Upic Lite's engine routes group 29 there.

## 7. The sprite editor *SEDIT

`src/mos/sedit.s`, bank 9 (`.local sed`). `*SEDIT n` edits GXR sprite n,
`*SEDIT VIC s` the VIC-II shape s.

- **Buffer**: REU bank `GXR_SCR` (the GXR file scratch), one byte per
  pixel, a row every 256 bytes (pixel x,y at y*256+x). GXR sprites go in
  and out through `gxr_edload` / `gxr_edstore` in bank 5 (farcall);
  `edstore` keeps the sprite's mask colour. A VIC shape (REU bank 1,
  `$1000 + s*64`) is unpacked to 24 x 21 bytes of 0/1 and packed again.
- **Multicolour view** (VIC, `M`): pixel pairs as one logical pixel with
  value 0-3 (01 `$D025`, 10 the sprite colour, 11 `$D026`); the buffer
  stays in bits, so switching the view loses nothing.
- **Screen**: MODE 100. The grid takes columns 0-23 and rows 1-23, with one
  cell per pixel (a reversed space in the pixel's colour, colour 0 a grey
  dot, the cursor `+`). It scrolls to keep the cursor in view (GXR sprites
  up to 192 x 255). The panel is from column 25. A VIC shape is also shown as
  hardware sprite 0 (its shape at `$FF00`), so the multiplexer is
  removed first. The mode before is set again on leaving.
- **Fill**: a scan-line fill with its stack of (x, y) pairs in REU bank
  `$0B` (up to 16K pairs; when the stack is full, pairs are dropped).
- **Variables**: `MOSBUF+$80-$9F`; gxr's helpers use `MOSBUF+$00-$3F`
  meanwhile.
- **Cold start**: the VIC shapes in the REU are cleared (`gxr_cold`),
  as the REU holds random data at power-on. `*SNEW` clears only the GXR
  store.
