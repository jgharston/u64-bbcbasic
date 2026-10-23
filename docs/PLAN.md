# U64 BBC BASIC: decisions and roadmap

BBC BASIC 3.10 for the Ultimate 64 and C64 Ultimate, as a cartridge, with
a BBC-style MOS in 6502 assembler and `*` commands for the Ultimate's
features. Version 1.0.0 is feature complete. This file keeps the
decisions that shape the project and what comes after 1.0.0; how things
are built is in ARCHITECTURE.md and the DESIGN_*.md documents, the
changes per version in CHANGELOG.md.

## 1. Principles

| Topic | Decision |
|---|---|
| Interpreter | BBC BASIC 3.10 from Ivo van Poorten's annotated MADS source (`lib/bbc-basic`, a submodule), unchanged: the only change is a build target (`src/basic/u64-target.patch`); `make compare-core` checks it byte for byte against the reference ROM. Faster maths through tables for programs (`*TABLE`), never by patching the float routines |
| Compatibility | BBC BASIC *programs*: the language and the behaviour of the VDU, graphics, sound and file statements. Not an emulator: no BBC memory map, BBC hardware or BBC machine code |
| Assembler | MADS, the interpreter source's own assembler |
| Cartridge | TwoMegabyter (CRT 87) for the Ultimates (UCI, REU, Ultimate Audio and turbo all usable) and EasyFlash subtype 1 for VICE and as a fallback, from one source; 16K mode with the KERNAL kept |
| New functions | `*` commands (OSCLI), OSBYTE/OSWORD for values: BBC BASIC's token table is full |
| Ultimate access | The command interface (UCI) in assembler in this repository (`src/mos/uci.s`), after ultimate-uci-oscar64; findings go back to that library |
| Machine | An REU is expected (16 MB for Ultimate Audio); turbo at the machine's highest speed |
| Code rules | CLAUDE.md: routine headers, bounded buffers, interrupt-safe zero page, foreground REU transfers with interrupts off, no dynamic allocation; every `*` command has a `*HELP` entry and an E2E test |
| Help | One source, `src/help/help.txt`: `*HELP` in cartridge banks, `docs/HELP_REFERENCE.md` and the manual's reference sections |
| Licences | The full cartridge ships with NOTICE.md (the interpreter and the MOS 1.20 font in good faith); the MOS, tools and tests are GPL-3.0; adapted code credits its source |

## 2. Decisions by area

**Screen and graphics** (DESIGN_GRAPHICS.md, DESIGN_SPRITES.md)

- The VDU driver and the drawing engine run from RAM under I/O and the
  KERNAL: HIMEM &8000 in the VIC-II modes, PAGE &1D00.
- BBC MODE 0-7 plus C64 modes 100, 103, 104 and Upic full 110/111. On 64
  MHz machines MODE 1, 2, 4, 5, 6 use Upic Lite (320 x 256, square
  pixels, the picture below HIMEM as on a BBC); `MODE 128+n` and
  `*SHADOW` choose the VIC-II version, as BBC Master shadow modes. MODE 0
  and 3 (80 columns, 4x6 font) and MODE 7 (teletext) stay on the VIC-II.
- Upic full: the picture in the REU, text on a live VIC-II console, the
  picture shown on request and automatically when a program waits or
  ends; music pauses cleanly while it shows.
- Fonts and palettes from files (C64, BBC, ASCII fonts; RGB and VICE
  `.vpl` palettes), the BBC look with `*FONT BBC` and `*PALETTE BBC`.
- Every shape outline, solid and pattern-filled (BBC Master ECF); the
  GXR's plot codes and software sprites; VIC-II sprites multiplexed (32);
  fast `*` graphics commands; CharPad maps; a PETSCII mode.

**Sound** (DESIGN_SOUND.md, DESIGN_TRACKER.md)

- SID mode by default: 24 voices on up to 8 SIDs, Heartbeat-style
  instruments, `SOUND &FSVV`; `*SOUND BBC` sounds like a BBC Micro. The
  engine in RAM, its tables in the REU.
- Songs built from BASIC on the MOS's own tracker; Ultimate Audio
  samples on SOUND voices 24-30 and ProTracker MODs through a port of
  ModPlayer_16k.

**Files** (DESIGN_ACORN.md)

- The Ultimate's drives through UCI, two channels; a 15 MB RAM disk
  `/REU`; DFS-style commands; `*BROWSE` with the keys of UBoot64-v2's
  browser, copying, moving and deleting recursively (/REU takes files,
  not folders; a name already there asks Y/N/All/Quit).

**Network** (DESIGN_NETWORK.md)

- Sockets as file channels (`OPENUP "TCP:host:port"`); HTTP requests by
  the MOS's own HTTP/1.0 client (the firmware's HTTP target gives no
  status and fails on long replies); JSON through the firmware's parser.

**Development** (REMOTE_DEV.md, AI_AGENTS.md)

- A mailbox in the MOS, driven over the Ultimate's REST API: the VS Code
  extension (`vscode/`: run, debug, format), `tools/u64remote.py` and an
  MCP server for AI agents.
- Example and demo programs are structured (no GOTO, PROC/FN instead of
  GOSUB) and indented, 2 spaces per level after the line number, as the
  extension's formatter writes them; the indentation is dropped when a
  program is sent or deployed, and `LISTO 7` indents loops on the
  machine. The classic programs stay as close to their originals as
  their licences allow.

## 3. Not in 1.0.0

Known limits: flashing colours 8-15 in the Upic Lite modes; teletext's
conceal and the SAA5050's own glyphs; the dot-dash line pattern (VDU
23,6) drawn as dotted lines; no call stack in the VS Code debugger;
names with spaces cannot be opened from `*BROWSE` (the `*` commands end a
name at a space).

Firmware functions left out (ULTIMATE_FUNCTIONS.md): tape capture, the
GEOS RAM disk, track decoding, a filing system on the SoftIEC drive, RAM
disk info, echo; setting the IP address and the interface count.

## 4. Roadmap

1. **Release 1.0.0:** a GitHub release with a ZIP (both `.crt` and
   `.cfg`, all demos tokenised and as source, the manual as PDF, README,
   licences) and the VS Code extension (`.vsix`); the repository, the
   videos and their playlist go public with it; an announcement (a
   Facebook post and an idreamtin8bits blog post).
2. **Videos (done):** five, one per group, in the
   [playlist](https://www.youtube.com/playlist?list=PLWExM0Ai4nOY):
   introduction, graphics, sound and music, files/Ultimate/network, the
   demos. Recorded from the Ultimate's video and audio streams with
   scripted key presses; how, in `docs/VIDEO_PLAN.md`.
3. **After 1.0.0:** Heartbeat Soundtracker songs (`*HBPLAY`); the
   firmware functions above; bigger `*MAP` maps (over 30720 cells); a
   better random generator next to RND; the UCI driver moved into
   ultimate-uci-oscar64 as an assembler module; the known limits above;
   a C128 cartridge (80-column VDC text).
