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
- **Upic Lite (MODE 1, 2, 4, 5, 6 on 64 MHz machines):** whether VIC-II
  sprites show over the Upic picture is to be tested on the U64.

Options for the bitmap modes, to decide:

1. Text screen first (all features), bitmap modes with the REU copying
   and at most 2 shapes per band (enough for a player and bullets);
2. take 1K from the bitmap's last text rows for 16 shapes (the screen
   then shows 24 rows of graphics instead of 25 in the VIC-II modes);
3. text screen only, until Upic full (MODE 110/111), whose picture is in
   the REU and leaves the VIC-II's bank free.
