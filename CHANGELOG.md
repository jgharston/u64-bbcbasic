# Changelog

All notable changes to U64 BBC BASIC. Versions follow
[semantic versioning](https://semver.org/).

## [1.0.0] - 2026-10-21

The first release: BBC BASIC 3.10 for the Ultimate 64 and C64 Ultimate as
a cartridge, with a BBC-style MOS written for the C64 and the Ultimate.

### The language

- BBC BASIC 3.10, the BBC Micro's BASIC, unchanged: built from Ivo van
  Poorten's annotated source and checked byte for byte against the
  reference ROM. It runs at the Ultimate's turbo speed, 25 to 30 times a
  BBC Micro.
- The BBC's MOS calls (OSWRCH, OSBYTE, OSWORD, OSCLI, OSFILE, OSFIND,
  OSBGET, OSBPUT, OSARGS) and RAM vectors, `*FX`, `*KEY`, `*EXEC`,
  `*SPOOL`, `*BUILD`, OSWORD 14 for the clock; PAGE &1D00, HIMEM &8000.
- A line editor with 238-character lines, a history of 127 lines and the
  BBC's copy editing (F1 is COPY); `*EDIT C64` for the C64's screen
  editor.
- `*HELP` for every keyword, command and topic, built into the cartridge
  (also as `docs/HELP_REFERENCE.md` and in the user manual).
- A BASIC toolkit in the style of Beebug's Toolkit Plus (`*SEARCH`,
  `*REPLACE`, `*XREF`, `*VARLIST`, `*CRUNCH`, `*PACK`), `*LIST` with full
  indentation, `*SNAPSHOT` to keep BASIC's world in the REU, RND seeded
  from real entropy at every start and `*RANDOMIZE`.

### Screen and graphics

- The BBC's MODE 0-7 with BBC graphics coordinates: on 64 MHz machines
  the 320 x 256 modes as Upic Lite (square pixels, as on a BBC), on the
  VIC-II otherwise and on request (`MODE 128+n`, `*SHADOW`); teletext
  MODE 7 with mosaics, double height and screen memory at &7C00.
- The C64's own modes (MODE 100, 103, 104) and Upic full (MODE 110/111:
  384 x 256 pixels, each its own colour, kept in the REU and shown on
  request or when the program waits).
- PLOT with every BBC and BBC Master shape: lines, triangles, rectangles,
  parallelograms, circles, ellipses, arcs, segments, sectors and flood
  fill, outline, solid or pattern-filled (ECF); the GXR's software
  sprites (`*SGET`, `*SLOAD`, ...); fast `*` graphics commands (`*CIRCLE`,
  `*RECTANGLE`, ...).
- 32 multiplexed VIC-II sprites (`*SPRITE`, SpritePad files) and a sprite
  editor (`*SEDIT`).
- Fonts and palettes (`*FONT`, `*PALETTE`, `VDU 19` with RGB), the BBC
  look (`*FONT BBC`, `*PALETTE BBC`), CharPad maps (`*MAP`), a PETSCII
  mode (`*PETSCII`, `*SEQ`), and `*TABLE` for fast SIN, COS, SQR and 1/x
  tables.

### Sound and music

- `SOUND` and `ENVELOPE` on up to 8 SIDs (24 voices) with instruments
  (`*INSTRUMENT`: waveforms, envelope, pulse and filter sweeps, vibrato,
  portamento, wave and arpeggio tables), or sounding like a BBC Micro
  (`*SOUND BBC`); the stereo mixer (`*SID PAN`, `*SID VOL`).
- A song tracker: songs recorded from `SOUND` and played in the
  background (`*SONG`).
- Ultimate Audio: sample sound effects on SOUND voices 24-30
  (`*SAMPLE LOAD`, WAV or raw) and ProTracker MOD music in the background
  (`*MODPLAY`, a port of ModPlayer_16k by Freshness).
- Speech through the user's own copy of S.A.M. (`*SPEECH`, `*SAY`).

### Files

- LOAD, SAVE, CHAIN and two open channels on the Ultimate's drives;
  `*CAT`, `*DIR`, `*COPY`, `*RENAME`, `*DELETE`, `*MKDIR` and more;
  DFS-style commands; disk images (`*MOUNT`), the SoftIEC drive's
  partitions.
- A RAM disk in the REU (`/REU`, 15 MB) and REU storage for programs'
  data (`*SRWRITE`, `*SRREAD`, `*REULOAD`, `*REUSAVE`, `*REU SAVE`).
- A file browser (`*BROWSE`, or F1 at the prompt) with the keys of
  UBoot64-v2's: opening by type (CHAIN a program, show a PETSCII or Upic
  picture, play a MOD or a WAV, mount a disk image), marking, copying,
  moving and deleting files and folders recursively, renaming, new
  folders.

### Network and the Ultimate

- Network connections as file channels (`OPENUP "TCP:host:port"`, UDP),
  HTTP requests (`*NET GET`, `POST`, `PUT`, `DELETE`, headers, status
  codes as errors) and JSON (`*JSON`, OSWORD &70), the clock from a time
  server, RND seeded from the internet (`*NET RANDOM`).
- The Ultimate's clock, drives, turbo, settings and machine functions
  (`*TIME`, `*DRIVE`, `*TURBO`, `*CONFIG`, `*REBOOT`, `*SAVEMEM`,
  `*STATUS`, ...).

### Programming from a PC

- A VS Code extension: run programs on the machine, output and errors in
  the editor, answering INPUT, debugging with breakpoints, stepping and
  variables, hover help, and a formatter that indents by block nesting.
- `tools/u64remote.py` for the command line and an MCP server for AI
  coding agents.

### Demos

A showcase, a tour of the graphics modes, Eric Schraf's graphics
programs, sprites and a small Invaders game, a music demo on 24 voices,
Ultimate Audio, a Ceefax-style network service, PETSCII art and classic
BBC BASIC programs.
