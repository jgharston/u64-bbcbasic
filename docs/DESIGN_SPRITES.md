# Sprites (design, 2026-10-14)

Decided (owner, 2026-10-14): `*SPRITE` commands plus an OSWORD for fast
movement; positions in BBC graphics coordinates; up to 32 sprites,
multiplexed by raster interrupt. Next on the roadmap after snapshots
(PLAN.md section 26).

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

## 3. Where the shapes can be (the open point)

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
  2 blocks, at most 2 different shapes per band; more needs room taken
  from somewhere (options below).
- **Upic Lite (MODE 1, 2, 4, 5, 6 on 64 MHz machines):** tested on the
  U64 (2026-10-14): VIC-II sprites do **not** show; the Upic picture
  replaces the VIC-II's whole output. The same sprite in MODE 132 (MODE 4
  on the VIC-II, `*SHADOW`) shows, from the free block at $FF40. So on a
  64 MHz machine a program with sprites uses MODE 128+n (or `*SHADOW`),
  as BBC Master programs choose shadow modes; `*SPRITE` in a Upic Lite
  mode gives an error that says so.

Options for the bitmap modes, to decide:

1. Text screen first (all features), bitmap modes with the REU copying
   and at most 2 shapes per band (enough for a player and bullets);
2. take 1K from the bitmap's last text rows for 16 shapes (the screen
   then shows 24 rows of graphics instead of 25 in the VIC-II modes);
3. text screen only, until Upic full (MODE 110/111), whose picture is in
   the REU and leaves the VIC-II's bank free.

## 4. Implemented (step 1, 2026-10-14)

- `*SPRITE ON` / `OFF` switches the multiplexer, as `*SOUND` the sound
  engine (owner's request): ON copies the image (`spritemux.s`, 5 pages)
  below the mode's HIMEM (&7B00, or &7700 under MODE 7's &7C00) and
  lowers HIMEM; OFF stops the interrupt and gives the pages back. At the
  prompt BASIC's HIMEM moves at once; in a program from the next MODE.
  OSBYTE &84/&85 report the lowered HIMEM while sprites are on.
- After every MODE `bk_mode` calls `spr_modehook` (bank 5): the image is
  reinstalled below the new HIMEM with all sprites hidden; in Upic Lite
  and (for now) the graphics modes it stays out.
- The interrupt (`mx_irq` on $0314) handles only the VIC-II raster
  interrupt and passes everything else to the vector before it: at line
  251 an insertion sort by Y and the first 8; then each next virtual
  sprite once the one 8 before it has finished (Y + 22 lines, +21 more
  double high). Collision registers are read at every raster interrupt
  and credited to the virtual sprites on the hardware ones.
- Robustness (fixed after the first demo flickered): Y is frozen per
  frame (the sort's copy, `skey`), and each hardware sprite keeps the
  line its virtual sprite ends (`hwend`): BASIC moving a sprite during
  the frame no longer makes a reuse cut the one still drawn. A raster
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

## 5. Graphics modes, MODE 7, LOAD, multicolour (step 3, 2026-10-14)

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
- **Multicolour** (owner's choice, 2026-10-14): `*SPRITE n MULTI ON|OFF`
  per sprite; `*SPRITE COLOURS a,b` sets the pair the VIC-II shares
  between all sprites ($D025, $D026). `COLOUR` only ever sets a
  sprite's own colour.
- Not yet: `*SPRITE LOAD` does not take SPD's colours; SPD versions 2+
  (SpritePad 2) give an error.
