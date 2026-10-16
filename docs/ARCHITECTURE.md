# U64 BBC BASIC -- architecture and memory maps

How the cartridge is put together: the layers, what lives in which
cartridge bank, the C64 RAM map, zero page and pages 2-3, HIMEM per mode,
and the REU map. Figures are those of 2026-10-16 (after the 1.0.0 items
1-6 and the move of the tools to bank 9). The history of decisions is in
`PLAN.md`; graphics details in `DESIGN_GRAPHICS.md`, sound in
`DESIGN_SOUND.md`, network in `DESIGN_NETWORK.md`.

Keep this file up to date when a bank, a RAM area or an REU area changes:
`src/mos/defs.s` points here.

## 1. Layers

| Layer | Where | What |
|---|---|---|
| BBC BASIC 3.10 | RAM `$8000-$BFFF` (copied from bank 1 at start-up, cartridge off while it runs) | Ivo van Poorten's C64 target, unchanged (`make compare-core`) |
| Resident MOS | RAM `$C400-$C7FF` | BBC entry points (`OSWRCH` &C7EE ... `OSCLI` &C7F7), the bank trampoline, IRQ/BRK/NMI handlers, the remote mailbox (`$C6E0`) |
| VDU core | RAM `$C800-$CFFF` (`core.s`) | the hot VDU path, text output, PETSCII mode, 48-bit maths slots |
| Drawing engine | RAM `$D000-$DFFF`, under I/O (`gfx.s`; teletext and Upic Lite engines swap in) | PLOT, shapes, text in the bitmap modes |
| MOS banks | cartridge `$8000-$BFFF` while a MOS call runs | everything else, in banks 0 and 2-9 (section 2) |
| Help texts | cartridge banks 10+ | `*HELP` (`tools/genhelp.py`) |

A MOS call from BASIC goes to the RAM entry point, which maps the
cartridge and the bank it needs; `farcall target, bank` (defs.s) calls
across banks through `tramp` (resident.s), which saves the current bank
on the stack and restores it, with A, X, Y and the flags passed both ways.

Rules that follow from this design:

- Code in a cartridge bank runs at bus speed (1 MHz on the U64) and
  cannot modify itself: hot paths run from RAM (the core, the engine, the
  fast path below HIMEM, RAM images in MOSBUF such as `*TABLE SQR`'s).
- An error raised in a bank is copied to `errbuf` (`$02A7`) before BASIC
  sees it: BASIC reads it through `FAULT` with the cartridge off.
- IRQ and NMI handlers live in RAM, never in a cartridge bank, and never
  use the MOS zero page.
- The sound interrupt drives the REU: every foreground REU transfer sets
  the registers up with interrupts off (`php`/`sei` ... command, `plp`).
- A bank that reads text or payloads "from the caller" needs its own copy
  of the helpers (`bankhelp.s`, one per `.local` module) and, for UCI
  payloads in its own ROM, of the UCI driver (bank 7 has one).

## 2. Cartridge banks

TwoMegabyter (CRT type 87, the normal build) and EasyFlash (VICE,
fallback) share the layout. Banks are 16K at `$8000`; free space as built
on 2026-10-16.

| Bank | Source | Contents | Ends at (free) |
|---|---|---|---|
| 0 | `mos.s` (+ `lineed.s`, ...) | boot, VDU dispatch, keyboard, OSBYTE/OSWORD, OSCLI and the command table, `*HELP` reader, line editor | `$BDEF` (about 0.5K) |
| 1 | `build/basic.rom` | BBC BASIC 3.10, copied to RAM at start-up | (full) |
| 2 | `bank2.s` | UCI driver, filing system, Ultimate commands (`ucmds.s`), REU, status, batch A, palettes, fonts, SID, REU files, `*LIST`, `*SRWRITE`/`*SRREAD`, RAM disk routing | `$BF6E` (146 bytes) |
| 3 | `gxbank.s` | graphics: MODE, palettes, Upic Lite setup, teletext engine image, shapes, RND seeding (`rndseed.s`) | `$BFB8` (72 bytes) |
| 4 | `ulbank.s` | Upic Lite RAM images | `$AFF2` (about 4K) |
| 5 | `rdbank.s` | the `/REU` RAM disk, snapshots, sprites, GXR, block graphics, the `*` command fast path, `*TABLE` (SQR, RECIP; SIN/COS passed on to bank 8) | `$BF76` (138 bytes) |
| 6 | `sndbank.s` | sound engine images (copied to `$0900`), SOUND/ENVELOPE, song tracker, speech, the 4x6 font, PETSCII mode, `*SETUP`'s settings text, `*REULOAD`/`*REUSAVE`/`*REU` | `$BFA0` (96 bytes) |
| 7 | `netbank.s` | network: `*NET`, `*JSON`, network channels, Ultimate machine commands (`ultctl.s`); own UCI driver copy | `$9439` (about 11K, for HTTP) |
| 8 | `upbank.s` | Upic full (`*UPIC`, MODE 110/111), BASIC V graphics commands (`bvcmd.s`), `*MAP` (`cmap.s`), `*TABLE SIN/COS` (`mathtab.s`) | `$BFF1` (14 bytes) |
| 9 | `toolbank.s` | tools: sprite editor (`sedit.s`), Acorn compatibility (`acorn.s`), DFS commands (`dfs.s`), BASIC toolkit (`toolkit.s`) | `$ABC0` (about 5K) |
| 10-14 | `build/help.bin` | `*HELP`: index and texts (5 banks, 70K) | |

Planned: Ultimate Audio (sample sounds, `*MODPLAY`) in a bank of its own
(1.0.0 item 8a).

## 3. C64 RAM while BASIC runs

| Range | Use |
|---|---|
| `$0000-$0001` | 6510 port |
| `$0002-$0051` | BBC BASIC zero page (`zpSEED`, the RND seed, at `$0D-$11`) |
| `$0052-$006F` | MOS zero page (section 4) |
| `$0070-$008F` | free for users' machine code, as &70-&8F on a BBC Micro |
| `$0090-$00FA` | KERNAL (keyboard, cursor) |
| `$00FB-$00FC` | `gzp`: the drawing engine's pointer |
| `$00FD-$00FE`, `$00FF` | `FAULT` (last error block), `ESCFLG` |
| `$0100-$01FF` | 6502 stack |
| `$0200-$03FF` | BBC vectors and MOS variables (section 5) |
| `$0400-$07FF` | BBC BASIC workspace (variables A%-Z% at `$0400`, stacks, string buffer `$0600`, input buffer `$0700`) |
| `$0800-$08FF` | `MOSBUF`: scratch for `*` commands (UCI replies, RAM images such as `*TABLE`'s; top bytes `$E0+` per command) |
| `$0900-$1CFF` | sound engine image (`SOUNDRAM`; shared part `$1C60`); with `*SOUND NONE` PAGE can drop to `$0900` |
| `$1D00` | PAGE (`OSHWM`) |
| PAGE-HIMEM | the program; below HIMEM, in the graphics modes, the `*` command fast path (3 pages) and with `*SPRITE ON` the sprite multiplexer (5 pages); Upic Lite pictures and MODE 7's buffer (`$7C00`) also come off the top (section 6) |
| `$8000-$BFFF` | BBC BASIC (RAM copy); the cartridge window during MOS calls |
| `$C000-$C3FF` | text screen / colour matrix (VIC bank 3) |
| `$C400-$C7FF` | resident MOS; `$C6E0` remote mailbox; entry points `$C7CE-$C7FF` |
| `$C800-$CFFF` | VDU core (`core.s`) |
| `$D000-$DFFF` | I/O; under it the drawing engine (RAM) |
| `$DE00`/`$DE02` | cartridge bank / mode register |
| `$DF00-$DF0A` | REU registers |
| `$DF1C-$DF1F` | UCI (`$DE1C` in the EasyFlash build) |
| `$E000-$FFFF` | KERNAL ROM; under it the 8K bitmap (`$E000`), the font (`$F000`, 2K) and, in Upic Lite, the shapes copy (`$EC00`) |

## 4. MOS zero page `$52-$6F`

Foreground only: interrupt handlers never touch it.

| Address | Name | Use |
|---|---|---|
| `$52` | `mosPTR` | general pointer (the command line in `*` commands) |
| `$54` | `mosPTR2` | second pointer |
| `$56-$59` | `mosTMP` | scratch |
| `$5A-$5D` | `mosCNT`, `mosMAX`, `mosMIN`, `mosHIGH` | line input |
| `$5E` | `mosNUM` | number parsing (2) |
| `$60` | `mosARGS` | `*FX` arguments (3) |
| `$63` | `fsPTR` | file name / data pointer (2) |
| `$65` | `fsLEN` | length (2) |
| `$67` | `fsCNT` | byte counter (2) |
| `$69` | `fsADDR` | transfer address (2) |
| `$6B` | `fsTGT` | UCI target of the current file operation |
| `$6C` | `fsCH` | channel index |
| `$6D` | `uciHLEN` | UCI command header length |
| `$6E` | `fsBLK` | OSFILE block pointer (2) |

## 5. Pages 2 and 3

| Range | Use |
|---|---|
| `$0200-$021F` | BBC RAM vectors (USERV ... FSCV), as on the BBC |
| `$0220-$0258` | DFS: `*EXEC`/`*SPOOL` state, the `*SPOOL` WRCHV stub (`DF_STUB` `$0228`) |
| `$0248-$0252` | speech scratch while speaking (`SVV`, `SV_RA`) |
| `$0259-$0276` | KERNAL file tables |
| `$0277-$0280` | keyboard buffer |
| `$0281-$02A6` | KERNAL (colour, shift state, `KEYLOG` vector `$028F`, MODE flag `$0291`) |
| `$02A7-$02DE` | `errbuf`: error block copied from a bank (56 bytes) |
| `$02DF-$02FF` | MOS variables: `osfblk` (18), `ch_ptr` (8), REU byte transfer, IEC devices, `caps_ofs`, `rd_ok` (full) |
| `$0300-$0333` | KERNAL vectors (`$0314` IRQ, `$0316` BRK, `$0318` NMI) |
| `$0334-$033B` | Upic full show state, `FONT46` |
| `$033C-$03FB` | keyboard table with CAPS LOCK (65), MOS variables up to `ramvars_end` (full) |
| `$03FC-$03FF` | `snd_8sid`, the kept JSON handles (`json_body`, `json_rhdr`) |

Pages 2 and 3, the resident page and the core are all full: new state goes
into the REU (section 7) or into `MOSBUF` for the length of one command.

## 6. HIMEM per mode

From OSBYTE &85 (2026-10-16); with `*SPRITE ON` in parentheses. The
graphics modes keep 768 bytes for the fast path.

| Mode(s) | HIMEM |
|---|---|
| 100, 134 | &8000 (&7B00) |
| 7, 135 | &7C00 (&7700) |
| 0, 3, 103, 104, 128-133 | &7D00 (&7800) |
| 110, 111 (Upic full) | &7D00 |
| 6 | &5800 |
| 4, 5 (Upic Lite) | &5500 |
| 1, 2 (Upic Lite) | &2D00 |

## 7. REU map (16 MB expected; the start-up check sets it)

| Range | Use |
|---|---|
| `$000000-$0007FF` | font in ASCII order (bitmap modes) |
| `$000800-$000FFF` | the text-mode font, for MODE changes |
| `$001000-$0017FF` | the start-up font (`*FONT DEFAULT`) |
| `$001830-$0018BF` | palettes: start-up colours, logical colours, a `.vpl` being read |
| `$001900-$001BF7` | characters 32-126 saved while the 4x6 font is in |
| `$002000-$002FFF` | 64 instruments x 64 bytes |
| `$003000-$0030CF` | the 16 envelopes |
| `$003100-$0034FF` | network channels: receive and send buffers (2 x 256 each) |
| `$003500-$0035FF` | line editor: history head and count |
| `$003600-$00387F` | `*KEY` texts, keys 0-9 (64 each) |
| `$003880-$003C7F` | speech: zero page and `&7D00-&7FFF` saved while SAM speaks |
| `$003C80-$003FFF` | free (896 bytes; planned for HTTP request headers and the last status) |
| `$004000-$007FFF` | HTTP reply buffer (16K); also the toolkit's line-target bitmap (transient) |
| `$008000-$00FFFF` | line editor history (128 lines of 256) |
| `$010000-$0102FF` | song header, order list, rows per pattern |
| `$011000-$01xxxx` | sprite shapes |
| `$012000-$0130FF` | `*SPRITE LOAD` scratch; `$013100` SpritePad marks (64) |
| `$014000-$01xxxx` | GXR sprites: descriptor, directory (`$014100`), data (`$014800`) |
| `$020000-$03F7FF` | song patterns (28 x `$1200`) |
| `$040000-$08FFFF` | **programs** (320K): `*SRWRITE`/`*SRREAD`, OSWORD &42, `*REULOAD`/`*REUSAVE` |
| `$090000-$09FFFF` | Upic full: the picture |
| `$0A0000-$0AFFFF` | Upic: BASIC's RAM while it shows; also the file scratch bank (`*MAP`, GXR, sprite files: transient) |
| `$0B0000-$0FFFFF` | `*SNAPSHOT` slots (two per bank); the sprite editor's fill stack uses slot 0 |
| `$100000-...` | the `/REU` RAM disk (header, data from `$101000`), up to the map bank |
| last bank - 1 | `*MAP`: the map (header, colours, characters `$1000`, colours `$8800`) |
| last bank | `*SPOOL` output (`$0000-$BCEF`); speech's image of `&7D00-&BFFF` and its header (`$BCF0-$FFFF`) |

The `*REU SAVE` preload image holds all of this, so a power-off keeps the
RAM disk and the program area.
