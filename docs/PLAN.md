# U64 BBC BASIC — Project Plan

BBC BASIC for the Ultimate 64 and C64 Ultimate, with star commands for the
Ultimate's features (UCI file system, drives, RTC, network, turbo, Ultimate
Audio, Upic, REU).

Status: plan, 2026-10-03. Nothing built yet.

---

## 1. Summary of recommendations

| Question | Recommendation |
|---|---|
| Interpreter source | Ivo van Poorten's annotated disassembly (github.com/ivop/bbc-basic), **BASIC 3.10**, as a submodule of a fork carrying a new `BUILD_U64_BASIC310` target |
| Assembler | **MADS (Mad-Assembler)**, the upstream source's own assembler. Not Kick Assembler, not ca65 |
| Oscar64 | **Not for the interpreter, the MOS layer or the command layer.** Only optionally, later, for the large Ultimate modules (MOD player, Heartbeat player, Upic) as separate cartridge banks behind a trampoline |
| Delivery format | **TwoMegabyter `.crt`** for the U64/C64U (everything works: UCI, REU, Ultimate Audio, turbo) plus an **EasyFlash subtype 1 `.crt`** from the same source for VICE and as a fallback. Both run in 16K mode with the KERNAL kept. A replacement BASIC ROM alone cannot work: see §3 |
| New commands | **`*` commands (OSCLI)** plus OSBYTE/OSWORD calls for returning values. The token table is full: all 128 tokens `$80–$FF` are in use |
| UCI access | A small native-assembler port of the protocol parts of `ultimate-uci-oscar64` (common, DOS, control, time, turbo, network), credited to the library |

---

## 2. What the sources give us

**ivop/bbc-basic** (mads source, `basic.s` 15.3k lines + `vars.s`):

- It builds BBC BASIC 2.00, 3.00 and 3.10 for the BBC, Acorn System and Atom,
  plus a **C64 target** (`BUILD_C64_BASIC2`, BASIC 2 at `$B800`). It is
  bit-exact against reference ROMs (`make compare`).
- The C64 target already handles the 6510 port: `zpLOMEM` moves to `$50`,
  `BRKV=$0316` (the KERNAL BRK vector), and `USER`/`ADVAL` have C64 tweaks.
  The matching C64 MOS is **not** in the repo: only the 16K BASIC image is.
- The image is exactly 16K and full. There is a `.error` on code overrun at
  `romstart+$4000`, so **adding code to the interpreter itself is not an
  option**. Extensions have to go through the MOS interface.
- All OS access goes through the BBC MOS entry points (`OSWRCH`, `OSRDCH`,
  `OSBYTE`, `OSWORD`, `OSFILE`, `OSFIND`, `OSBGET`, `OSBPUT`, `OSARGS`,
  `OSCLI`, …). Their addresses are symbols, so a new target can point them
  at our own jump table. The C64 KERNAL jump table occupies `$FF81–$FFF3`,
  so the BBC `$FFxx` addresses can't be used.
- Errors use the 6502 `BRK` instruction. The README warns about the NMOS
  NMI/BRK race: our NMI handler (RESTORE key, CIA2) **must** check the B
  flag on the stack.

**ivop/atari-bbc-basic** (BSD-2) is the model for this port: BASIC 3.10, a
MOS translation layer (`main.s`, ~1850 lines) in RAM, MOS vectors relocated
to a RAM page with the same low bytes (`&2FCE…&2FF7`), the host OS's own
screen editor for input, and `*` commands for DOS. Its documented
compromises (VDU, MODE, SOUND, no OPENUP/PTR#) are the list to improve on.

**ultimate-uci-oscar64 v1.4.0** is Oscar64 C (GPL-3). The UCI protocol is
small: 4 registers at `$DF1C–$DF1F`, push command, poll status, read data
and status FIFOs, plus the 3.15+ unlock (`$D038`/`$D036`). Two DOS targets
give **two simultaneously open files**, and DOS has seek and file info, so
`OPENUP`, `PTR#` and `EXT#` can work properly, unlike on the Atari.

**Licensing.** This repo is GPL-3, and so is the UCI library.

- **The interpreter has no clear licence anywhere.** It says © 1982/83
  Acorn and Sophie Wilson. Nobody seems to know who holds those rights now:
  a RISC OS Open forum thread names MSDW, which bought the Acorn group.
  Being published without a licence (ivop/bbc-basic, mdfs.net) legally
  means "all rights reserved", not "reusable". In practice the community
  freely redistributes 6502 BBC BASIC, and nobody has objected in decades.
- **Every port with a clear licence licenses only its own OS layer,**
  never Acorn's interpreter:

| Port | Licence | Interpreter | Relevance |
|---|---|---|---|
| mdfs.net `BBCBASIC.prg` (J.G. Harston) | none stated | BASIC II + a host interface to the C64 KERNAL | **The direct precedent for a C64 port**, and the source of ivop's C64 build (zero page `&00–&5F`, `&FD–&FF`, workspace `&400–&7FF`). Study its MOS layer |
| ivop/atari-bbc-basic | BSD-2 (Ivo's code) | 3.10, built from source | Model for this port (§2) |
| chelsea6502/BeebEater (Ben Eater 6502) | MIT | Ships Acorn's **BASIC 4r32 binary** (65C02) next to an MIT MOS | Shows the "own MOS + Acorn ROM" pattern. 65C02-only, so not usable on the 6510 |
| bobbimanners/Applecorn (Apple //e) | **GPL-3** | Runs unmodified Acorn language ROMs | **The same licence as ours, so its MOS code can be reused with credit** (VDU, OSWORD, OSFILE/OSFIND on a foreign DOS). Written for the enhanced //e, so expect 65C02 instructions to convert |
| adiee5/cx16-bbc-mos (Commander X16) | none | **Doesn't distribute BASIC**: the user builds it in | The cautious model |
| ivanizag/bbz | MIT | Runs MOS programs on a PC | A host tool for tokenising and testing (§11) |

**Options:** (A) ship the complete `.crt` with a `NOTICE.md` that separates
our GPL-3 code from the Acorn interpreter, as mdfs, Ivo and BeebEater do;
(B) like cx16-bbc-mos, release only our code plus a build that pulls Ivo's
source. B costs little here, because we assemble from source anyway.
Recommendation: A, with a courtesy message to Ivo (and J.G. Harston, whose
reconstruction underlies everything). It's your call.

**Other BBC BASIC versions** (stardot repositories checked 2026-10-04; the
RISC OS and Richard Russell entries are from memory and should be verified
before relying on their licences):

| Source | What it is | Usable here? |
|---|---|---|
| github.com/stardot/AcornCmosBasic | Original Acorn source of **BASIC 4** (Master 128), Acorn MASM format, released by Paul Fellows. No licence file | **65C02 only** (BRA, PHX/PLY, STZ, `(zp)` addressing, …). The U64's 6510 core is NMOS, so these opcodes would crash. Porting means rewriting every 65C02 instruction, which pushes it past 16K. Use it to learn from, not to build |
| github.com/stardot/AcornDmosBasic | BASIC "4++", the same family | Same as above |
| github.com/stardot/AcornBasic128 | BAS128 (B+128/Master, bank-switched program memory) | Its banking design is relevant if we ever put programs in REU/banked RAM |
| RISC OS Open BASIC module (gitlab.riscosopen.org, Apache-2.0) | **BASIC V/VI**, ARM assembler | No code reuse (ARM). It is the reference for the language: WHILE/ENDWHILE, CASE/OF/WHEN, multi-line IF/ENDIF, LOCAL arrays, LIBRARY/INSTALL, `ERROR n,"msg"`. Legally the cleanest source |
| Richard Russell's BBC BASIC (BBCZ80, BBCSDL; zlib licence) | Modern BASIC V-compatible implementations; the Z80 one is also the base of Agon BBC BASIC | Reference for semantics and test programs, not code |

Conclusion: stay on 3.10, the last NMOS version, for the interpreter. Treat
BASIC 4/V as a feature catalogue. Most of what they add (TIME$, structured
IF/WHILE/CASE, LIBRARY) needs room in the interpreter that the full 16K bank
doesn't have. TIME$-style things can be done as `*` commands/OSWORD. A
proper "BASIC V on a 6502" would mean extending the interpreter across
cartridge banks: possible later, but a separate project.

---

## 3. Why a cartridge, and which one

**A replacement BASIC ROM is too small.** The U64/C64U custom BASIC ROM slot
is 8K at `$A000`. BBC BASIC alone is 16K, before any MOS. Replacing BASIC
and KERNAL together gives 16K, but in two non-contiguous 8K pieces around
the I/O area, with no room for a MOS. So it has to be a cartridge. A
cartridge also leaves the user's ROM settings alone: they just run the
`.crt`. It also means BASIC itself takes no RAM, and the RAM under the
cartridge window can hold part of a Upic picture (§11).

**Compatibility, from the firmware's own source.** These come from the
`prohibit`/`require` masks in `configure_cart()` in
`GideonZ/1541ultimate/software/io/c64/c64_crt.cc`, re-checked against
master on 2026-10-04. The full research is now global:
`~/.claude/ultimate_cartridge_types.md`. BBC BASIC needs one contiguous 16K
window, which rules out every 8K-bank type (GMod2, Megabyter, Ocean, Magic
Desk).

| Type | 16K banks | REU | UCI | Ultimate Audio | Turbo | VICE 3.8 |
|---|---|---|---|---|---|---|
| **TwoMegabyter (87)** | 128 (2 MiB) | ✓ | ✓ at `$DF1C` | ✓ | ✓ | ✗ |
| EasyFlash **subtype 1** (32/1) | 64 (1 MiB) | ✓ | ✓ but **moved to `$DE1C`** | **✗** | ✓ | ✓ |
| EasyFlash subtype 0 | 64 | ✗ | ✗ | ✗ | ✓ | ✓ |
| COMAL 80 (21) | 4 (64K; more as the Ultimate's "Pakma" variant) | ✓ | ✓ at `$DF1C` | ✓ | ✓ | ✓ |
| FC-III subtype 1 | 4–16 | ✓ | ✓ at `$DF1C` | ✗ | ✓ | ✓ |

Turbo (`$D030/$D031`) is never affected by the cartridge type.

**Recommendation: build two cartridge types from one source.** Their
registers are nearly the same: bank at `$DE00`, control at `$DE02`.

- **TwoMegabyter: the main U64/C64U release.** It is the only 16K-bank type
  that allows everything (UCI at its normal address, REU, Ultimate Audio
  for SOUND/MOD playback, turbo). It powers up in 16K mode with bank 0
  mapped and the KERNAL visible, so bank 0 autostarts through the `CBM80`
  signature. Protovision also sells it as real hardware, so the same image
  would run on a stock C64 (without the Ultimate commands). Risks: the type
  was only added to the firmware on 2026-08-11, almost no software uses it
  yet, and VICE 3.8 doesn't support it. Phase 0 smoke-tests it on both
  Ultimates.
- **EasyFlash subtype 1: the development and fallback build.** It runs in
  VICE (which has no UCI anyway), has the best tooling, and on an Ultimate
  gives REU, UCI and turbo, but **no Ultimate Audio**. Its boot code sits in
  bank 0 (Ultimax start), and the UCI base moves to `$DE1C`.
- **The UCI base address is a build-time symbol** in the assembler UCI
  layer: one line. The C library hardcodes `$DF1C`. A configurable
  `UII_BASE` would be a worthwhile library improvement for any EasyFlash
  project (issue to file there).
- Never use EasyFlash subtype 0 (`PROHIBIT_IO`).
- COMAL 80 is a 64K VICE-compatible fallback if TwoMegabyter turns out to
  be unreliable.

Bank layout (the same for both types):

| Bank | Contents |
|---|---|
| 0 | Boot (`CBM80` for TwoMegabyter; Ultimax reset vector for EasyFlash). Cold start: copy the resident MOS and font to RAM, set up the IRQ/NMI/BRK vectors, detect and unlock UCI, select bank 1, enter BASIC |
| 1 | **BBC BASIC 3.10**, unmodified apart from the target block, `romstart=$8000` (the BBC Micro language-ROM address) |
| 2 | Non-resident MOS: OSFILE/OSFIND filing systems, VDU graphics (MODE/PLOT/DRAW/GCOL/CLG/POINT), SOUND/ENVELOPE |
| 3 | `*` command parser and UCI driver: file system, drives, time, turbo, network, REU, palette |
| 4+ | Upic driver, MOD/Heartbeat player, `*HELP` texts, a ROM filing system with demo programs (§11) |

**Optional second deliverable:** a RAM-loaded `.prg` build, with BASIC in
RAM at `$8000–$BFFF` and BASIC ROM banked out. It has the same memory map,
fewer extensions, and is useful for VICE and for quick turnaround.

---

## 4. Memory map (running)

(The original plan; the current maps are in `ARCHITECTURE.md`.)

| Range | Use |
|---|---|
| `$0000–$0001` | 6510 port |
| `$0002–$0050` | BBC BASIC zero page (`vars.s`, `zpLOMEM` at `$50`) |
| `$0051–$008F` | MOS zero page (the former C64 BASIC area) |
| `$0090–$00FA` | KERNAL |
| `$00FD/$00FF` | BBC `FAULT` pointer and `ESCFLG`, as in the existing C64 target (check `$FE` against `FAULT+1`) |
| `$0100–$01FF` | 6502 stack |
| `$0200–$03FF` | KERNAL variables and vectors (`$0316` BRK → MOS) |
| `$0400–$07FF` | **BBC BASIC workspace**, as on the BBC (variable heads, stacks, string buffer, input buffer `$0700`) |
| `$0800–$18FF` | Sound engine (from 2026-10-09, DESIGN_SOUND.md 4) |
| `$1900–$7FFF` | **PAGE=&1900 … HIMEM=&8000: 26.75K for programs**, PAGE as on a BBC with discs (a BBC Model B with discs in MODE 7 has about 25K); 30K with PAGE &0800 until 2026-10-09 |
| `$8000–$BFFF` | Cartridge window: bank 1 (BASIC) normally, other banks during MOS calls |
| `$C000–$C3FF` | Text screen (VIC bank 3) / bitmap colour matrix |
| `$C400–$C7FF` | Resident MOS: jump table at `$C7CE–$C7F7` (BBC low bytes kept), bank trampolines, OSWRCH/OSRDCH fast path, IRQ/NMI/BRK handlers |
| `$C800–$CBFF` | 128-character font: the C64 lower/upper set with ASCII glyphs `\ ^ _ ` { | } ~` |
| `$CC00–$CFFF` | Resident MOS overflow, error-block buffer, `*` command buffer |
| `$D000–$DFFF` | I/O: `$DE00`/`$DE02` cartridge bank/control, `$DF1C` UCI (`$DE1C` in the EasyFlash build), `$DF20–$DFFF` Ultimate Audio (TwoMegabyter build) |
| `$E000–$FFFF` | KERNAL ROM. The RAM underneath holds the 8K hires/multicolour bitmap, which the VIC can see |

To validate in Phase 1: whether the resident MOS fits in 2K. If it doesn't,
move the font to a 1K-aligned spot higher up, or take `$7C00–$7FFF` (HIMEM
`&7C00`, as on the BBC).

**Bank-switching rules** (the heart of the design):

1. BASIC (bank 1) calls `OSxxxx` at `$C7xx` (RAM). The trampoline saves the
   bank, selects bank N, `JSR`s the handler, restores bank 1 and returns
   with A/X/Y/flags intact.
2. **Errors from banked code:** BASIC reads the error text through `FAULT`,
   and that text sits in a bank that will no longer be mapped. The BRK
   handler therefore copies the error block (number + message) to the RAM
   buffer, points `FAULT` there, restores bank 1 and jumps to BASIC's error
   handler. (The BBC MOS does the same for sideways-ROM errors.)
3. IRQ and NMI handlers live in RAM or KERNAL, never in the cartridge
   window. They must not depend on which bank is selected.

---

## 5. Buildchain

**MADS** (Mad-Assembler, github.com/tebe6502/Mad-Assembler), version pinned:

- The interpreter is 15k lines of MADS syntax (`dta`, `icl`, `opt`, `.if
  .def`, `-d:` defines). Keeping that syntax means upstream fixes from Ivo
  can be merged in (he has already fixed FEXPCO and INSTR bugs) and `make
  compare` still proves the core is untouched.
- MADS is not installed. Build it from source with FreePascal (`fpc` 3.2.2
  is present): `fpc -Mdelphi -vh -O3 mads.pas` → `tools/` or `~/.local/bin`.
  The Makefile checks for it.
- The MOS and extension code are written in MADS too: one assembler, one
  symbol space, and shared `vars.s`/token definitions.

**Why not Kick Assembler:** we'd have to convert 15k lines of source,
losing upstream merges and the bit-exact comparison, and gain nothing that
a 16K ROM needs. Its scripting strength doesn't matter here, and Python can
do any table generation.

**Why not ca65:** the same conversion cost. Its linker would be nice for
banks, but a small Makefile/Python step handles banks fine.

**Why not Oscar64 for the core:**

- The core *is* an existing 6502 assembler program. There is nothing to write in C.
- The MOS and command layer must use BBC BASIC's zero page, its argument
  conventions (A/X/Y, parameter blocks, `CR`-terminated strings at
  `(X,Y)`), raise errors with `BRK`, and fit fixed entry addresses in a
  shared 2K RAM page. Oscar64's runtime (zero-page registers at
  `$80–$FF`, which collide with the KERNAL area, its own stack, startup
  code) does not fit inside that, and its code is larger than hand-written
  assembler in banks where every byte counts.
- The UCI protocol is a few hundred bytes of assembler. Porting it is
  cheaper than bridging C into an assembler program on every call.

**Where Oscar64 still makes sense (Phase 6, optional):** the MOD player
(1.2k lines), Heartbeat player (2.3k lines) and Upic module (0.6k lines) are
big, already tested C. Porting them to assembler is real work. **Upic is
the exception:** Aleksi Eeben's original v1.3 `display.s`/`drawing.s` are
6502 assembler and published (with his permission) through the library, so
the Upic driver should start from those, not from the C port. For the
players,
compile each with `-tf=bin` and a `#pragma region` at `$8000–$BFFF` into its
own cartridge bank, with a jump table at the bank start. Call it through a
trampoline that saves and restores Oscar64's zero-page area and points it
at its own stack. This only goes ahead after a spike shows that it works,
including when the player runs from the IRQ while BASIC keeps running.

**UCI assembler port — where it lives:** your rule is that Ultimate code
belongs in `ultimate-uci-oscar64`. My recommendation is to add an
`asm/mads/` folder to that library (`uci_common.s`, `uci_dos.s`, …, credited
to the C library and Scott Hutter/Francesco Sblendorio's original), released
with a version bump. This project then uses it through the submodule, the
same way as the C. **This is your decision.** The alternative is to start
it in `src/uci/` here and upstream it once it's stable.

**Other tools:** `cartconv` (VICE) or a small Python script to assemble the
`.crt` from the bank binaries; VICE `x64sc` for emulator tests (no UCI, so
the MOS must cope without an Ultimate: Ultimate commands fail with a clean
error and the IEC file system is used); real U64 / C64U through the
Ultimate REST API (run `.crt`) or the c64bridge MCP for hardware tests.

**Repository layout**

```
lib/bbc-basic/            submodule: fork of ivop/bbc-basic, branch u64 (target block only)
lib/ultimate-uci-oscar64/ submodule, pinned tag (asm port and, later, C modules)
src/boot.s                bank 0
src/mos/                  resident.s (RAM page), vdu.s, keyboard.s, fs_uci.s, fs_iec.s,
                          sound.s, graphics.s, oscli.s, errors.s
src/star/                 one file per command group (fs, drive, time, turbo, net, reu, audio)
src/font/                 ASCII-patched charset (+ generator script)
tools/mkcrt.py            bank binaries → .crt
tests/                    BBC BASIC test programs (.bas text + tokenised), expected output
docs/                     PLAN.md, ARCHITECTURE.md, USER_MANUAL.md, STAR_COMMANDS.md,
                          MOS_INTERFACE.md, UCILIB_MANUAL.md (copied in), OSCAR64_MANUAL.md (if phase 6)
```

Makefile per `~/.claude/makefile_conventions.md` (`.env` with the Ultimate
IP, `check-deploy`, `ALLSRCS`, `docs` target), plus a `make compare-core`
that builds the stock BBC BASIC 3.10 from the submodule and checks it
against Ivo's reference image.

---

## 6. Changes to the interpreter (fork of ivop/bbc-basic)

All of these go in a new `.elseif .def BUILD_U64_BASIC310` target block,
with no changes to interpreter logic:

- `romstart=$8000`, `VERSION=3`, `MINORVERSION=10`, `split=0`,
  `foldup=0`, `workspace=$0400`, `membot`/`memtop` taken from OSBYTE
  `&83`/`&84` (the MOS answers `&08`/`&80`, which shrinks with the graphics MODE).
- `zpLOMEM=$50`, `FAULT`/`ESCFLG` as in the C64 target, `BRKV=$0316`.
- `MOS_BBC` with the `OS*` symbols pointing at the resident jump table at
  `$C7CE…`, instead of `$FFCE…`.
- Reuse the existing `TARGET_C64` tweaks where they still fit (`USER`, `ADVAL`).

Offer the target block upstream to Ivo as a PR. Then the fork is only needed
until it is merged.

---

## 7. MOS layer: BBC behaviour on a C64

| BBC facility | Implementation |
|---|---|
| Line input (OSWORD 0) | KERNAL screen editor (`CHRIN`), as the Atari port does: full-screen editing for free. Translate PETSCII to ASCII on the way in |
| OSWRCH / VDU | ASCII to the patched lower/upper charset. VDU 7 (bell on SID), 8–13, 12 (CLS), 17/18 (COLOUR/GCOL), 19 (palette → `uii_setpalettecolor` on U64), 22 (MODE), 25 (PLOT), 26/28/29/31 (windows, origin, TAB). VDU queue with BBC parameter counts, so unknown codes are swallowed safely |
| Keyboard | `\ ^ _ { } | ~ `` ` on C= / Shift combinations (to define), RUN/STOP = ESCAPE (sets `ESCFLG` from the IRQ), RESTORE = BREAK (warm start, program kept), INKEY(-n) negative key numbers mapped to the C64 matrix |
| TIME | 100 Hz from a CIA1 timer. CIA timers keep 1 MHz timing at U64 turbo speeds (verify) |
| MODE | 7/0 = 40×25 text; 4 = 320×200 hires; 1/2/5 = 160×200 multicolour. BBC logical coordinates (1280×1024) scaled to the screen, so existing programs draw correctly. Later: an extra mode for Upic 384×256 in 16 colours on the U64 |
| SOUND / ENVELOPE | SID: channel 0 noise, 1–3 tone, BBC pitch (quarter semitones) through a table, ENVELOPE as a software envelope in the IRQ. Second SID and Ultimate Audio as extra channels later |
| OSFILE / OSFIND / OSBGET / OSBPUT / OSARGS | Two file systems, chosen with `*FS`: **UCI DOS** (default on an Ultimate: FAT paths on USB/SD, two open files, full `PTR#`/`EXT#`/`OPENUP`) and **IEC** through the KERNAL (any drive; also VICE). `SAVE` writes the standard BBC tokenised format, so programs from BBC archives load directly |
| OSBYTE / OSWORD | The common subset (`&00`, `&7E`, `&81`, `&82–&86`, `&87`, `&DA`, OSWORD `0/1/2/7/8/9/A/E`) plus a documented Ultimate range (§8) |
| Errors | `BRK` + number + message. UCI status strings become the message (`REPORT` shows them), Ultimate errors numbered in a reserved range |
| `CALL`/`USR` and the built-in assembler | Unchanged. The MOS entry points are documented at `&C7CE…`, as the Atari port documents `&2FCE…` |

---

## 8. Ultimate extensions

Because the token table is full, commands are `*` commands, usable directly
or with computed arguments through `OSCLI`:
`OSCLI "TURBO "+STR$(N%)`. Values come back through OSBYTE/OSWORD with A%,
X%, Y% and `USR`, or through parameter blocks (`DIM P% 32`).

| Group | Commands (initial set) | Library source |
|---|---|---|
| General | `*HELP [ULTIMATE]`, `*UVER` (firmware/hardware ID), `*FX`, `*RESET`, `*REBOOT`, `*POWEROFF`, `*MENU` (freeze) | common, control |
| File system (UCI DOS) | `*FS UCI|IEC`, `*CD`, `*PWD`, `*CAT`/`*.`, `*MKDIR`, `*DELETE`, `*RENAME`, `*COPY`, `*LOAD`/`*SAVE`/`*RUN` (binary), `*EXEC`/`*SPOOL` (text listings), `*INFO` | dos |
| Drives | `*MOUNT "x.d64" [8]`, `*UNMOUNT`, `*DRIVE n ON|OFF`, `*DRIVES`, `*NEWDISK` | dos (drives) |
| Clock | `*TIME`, `*DATE`, `*SETTIME`, OSWORD `&0E` (BBC "read clock string") from the Ultimate RTC | time |
| Speed | `*TURBO 1|2|…|48|OFF`, OSBYTE to read the current speed | turbo |
| REU | `*REU LOAD/SAVE`, OSWORD for DMA transfers between REU and C64 RAM | dos (REU) |
| Network | `*NET` (IP/status). Sockets as files: `OPENIN "TCP:host:port"` returns a channel for `BGET#`/`BPUT#`/`EOF#`. Later `HTTP:` the same way | network, http |
| Palette | `VDU 19,l,p,r,g,b` and `*PALETTE RESET` | common (palette) |
| Audio (Phase 6) | `*MODPLAY file`, `*MODSTOP`, `*HBPLAY`, SOUND on Ultimate Audio voices | audio, modplay, hbplay |
| Upic (Phase 6) | Upic `MODE`, `*UPIC LOAD/SAVE` | upic |

Every command using an `[UNTESTED]` library function gets a hardware test,
and the result goes back to the library's manual §20 (your library rule 3).

---

## 9. Phases

| # | Phase | Deliverable / acceptance |
|---|---|---|
| 0 | **Spikes** (S) | MADS built; stock 3.10 reproduced bit-exact from the submodule. A minimal **TwoMegabyter** `.crt` and **EasyFlash subtype 1** `.crt` on the U64 and C64U: CBM80/Ultimax boot from bank 0, switch banks from RAM, `uii_identify` (at `$DF1C` and `$DE1C` respectively), an REU transfer, an Ultimate Audio register (TwoMegabyter only), turbo on/off, power cycle and reset. CIA timer at turbo speed checked |
| 1 | **Minimal MOS, text only** (M) | `.crt` boots to `BBC BASIC` / `>` prompt in VICE and on the U64. OSWRCH/OSRDCH/OSWORD 0, ASCII font, ESCAPE, BRK errors from banks (rule §4.2), NMI B-flag check, TIME, OSBYTE subset. Test: CLOCKSP benchmark runs, `ON ERROR` loop from Ivo's README survives RESTORE presses |
| 2 | **Filing systems** (M) | UCI DOS and IEC: SAVE/LOAD/CHAIN, OPENIN/OPENOUT/OPENUP, BGET#/BPUT#/PTR#/EXT#/EOF#, `*CAT`, `*CD`, `*EXEC`/`*SPOOL`. Test: round-trip a BBC tokenised program from an archive; random-access file test |
| 3 | **Ultimate commands, protocol layer** (M) | UCI assembler port with tests; `*TURBO`, `*MOUNT`, `*TIME`/OSWORD 14, `*UVER`, `*REU`, `*RESET`, palette through VDU 19 |
| 4 | **Graphics and sound** (L) | MODE/PLOT/DRAW/MOVE/GCOL/CLG/POINT/VDU 24–29 with BBC coordinates; SOUND/ENVELOPE on SID. Test: classic BBC graphics demos run unchanged |
| 5 | **Network** (M) | TCP sockets as channels, `*NET`; later HTTP. Test: fetch a page with BGET# |
| 6 | **Large modules** (L, optional) | Oscar64 bank spike, then MOD/Heartbeat playback in the background, Upic mode |
| 7 | **Release** (S) | `docs/USER_MANUAL.md` (keyboard, MOS calls, memory map, star commands, differences from the BBC), example programs in a ROM filing system bank, a GitHub release with `.crt` (+ `.prg`), video per the YouTube workflow, Facebook post |

Phase 1 is where the shape is proven. Everything after it is incremental and
can be released in steps (v0.1 text + files, v0.2 Ultimate commands, …).

---

## 10. Risks and open questions

1. **TwoMegabyter is new** (firmware 2026-08-11, little real-world use, no
   VICE 3.8 support). Phase 0 smoke test; EasyFlash subtype 1 (no Ultimate
   Audio) and COMAL 80 are the fallbacks (§3).
2. **Resident MOS size (2K).** If it is too tight, HIMEM drops to `&7C00`.
3. **Licence** of the BBC BASIC image and Ivo's conversion (§2): ask before
   the first public release.
4. **Turbo:** check SID/CIA/IEC timing at high speeds. KERNAL IEC at turbo
   probably needs to drop to 1 MHz during IEC transfers. UCI DOS doesn't
   care.
5. **Decision for you:** where the UCI assembler port lives (library
   `asm/mads/` recommended, §5).
6. **Decision for you:** the PRG/RAM build as an official second
   deliverable, or just a development aid.
7. **Decision for you:** whether to support the Ultimate II+ on a stock C64
   (the same `.crt` works; turbo/audio/Upic commands would report "Not on
   this hardware"). Recommended, since it costs only detection code.

---

## 11. Demo programs: porting ArchBAS (Archimedes → U64)

`xahmol/ArchBAS` (GPL-3) has two BBC BASIC V programs for the Archimedes:
**Schraf Graphical Demos** (Bubble Universe, Field Lines, Mathematical Hat,
Event Horizon, Galaxy; after Eric Schraf's QB64 originals) and the
**Christmas Tree** (after Aurel). They are the showcase for palette control,
Upic and turbo, and the acceptance programs for Phases 4 and 6.

**What has to change.** They use BASIC V, and we have 3.10:

| BASIC V (Archimedes) | BASIC 3.10 on the U64 |
|---|---|
| `CASE key OF … WHEN … ENDCASE` | `IF key=49 PROCbubbleuniverse` lines |
| Multi-line `IF … THEN` / `ELSE` / `ENDIF` | Single-line IF, or move the body into a PROC |
| `WHILE … ENDWHILE` | `REPEAT … UNTIL` with a guard (WHILE tests first) |
| `<<` | `*4`, `*16` |
| `POINT x,y` (statement) | `PLOT 69,x,y` |
| `RECTANGLE FILL x,y,w` | `PLOT 4,x,y : PLOT 101,x+w,y+w` (Master/GXR PLOT code, implemented in our VDU driver) |
| `CIRCLE x,y,r` | `PLOT 4,x,y : PLOT 145,x+r,y` (GXR circle codes in our VDU driver), or a PROC |
| `COLOUR n,r,g,b` | `VDU 19,n,16,r,g,b` → `uii_setpalettecolor` (firmware palette control) |
| `GCOL c TINT t` (256 colours) | A 16-entry palette per demo, designed for the effect, then `GCOL c` |
| `OFF` | `VDU 23,1,0;0;0;0;` |
| `MODE 12/15` (640×256) | `MODE` for Upic (384×256, 16 colours per pixel) or multicolour (160×200, 4 colours) |

BBC logical coordinates stay 1280×1024. Upic scales them neatly: x × 3/10
and y ÷ 4, so the PLOT/DRAW coordinates in the programs don't change.
(`PROC_color` in XMas25 reads `r%`/`g%`/`b%` instead of its parameters
`r`/`g`/`b`; worth checking while porting.)

**Which demo fits which mode**

- **Event Horizon** (16 grey shades) and **Galaxy** (4 colours): an exact
  fit for Upic with a custom palette. Galaxy also works in multicolour
  bitmap.
- **Bubble Universe**, **Field Lines**, **Hat** and the **Christmas Tree**
  (256-colour GCOL/TINT): a 16-colour palette chosen per demo, so they show
  off palette control.

**What Upic means for the MOS (this needs designing before Phase 6)**

- **Memory.** A Upic picture is 48K (192 columns × 256 bytes), and the
  renderer needs I/O visible, so `$D000–$DFFF` can't hold columns. Because
  BASIC runs from the cartridge, the RAM *under* the cartridge window
  (`$8000–$BFFF`) can hold 16K of columns: CPU writes go to RAM, and the
  renderer runs with `$01=$35`, which unmaps the cartridge. A Upic MODE
  then behaves like BBC MODE 0–2: HIMEM drops to roughly `&3000`, leaving
  about 10K for programs. That is plenty for these demos (Schraf is 221
  lines). The resident MOS and the text screen/font at `$C000–$CFFF` must
  move or shrink in this mode; reading pixels back (`POINT()`) needs a RAM
  routine that unmaps the cartridge.
- **Fallback if 48K is too much: a compact 48 MHz Upic** (your
  suggestion). The 48 MHz path (Christian Gleissner) only *shows* 3 of
  every 4 pixels (288 of 384 per line), but still *stores* all 384, because
  pixel 4m+1 shares a byte with 4m. Storing just the 288 shown pixels takes
  144 columns = **36K, saving 12K** (programs get about 22K instead of 10K).
  The cost: a packed nybble layout, so the renderer's inner loop changes; a
  separate "compact" picture format, with `.upic` loading dropping pixel
  4m+1; and 64 MHz machines using the 48 MHz path in this mode (the Elite
  II supports it, at speed index 14). This is a renderer variant, so it
  belongs in the library's Upic module first. Decide after measuring the
  real memory budget of the full mode.
- **CPU.** The renderer changes the border colour once per pixel in a
  raster IRQ, so it uses most of the frame at 48/64 MHz. BASIC runs in what
  is left, which is still several times a 2 MHz BBC Micro. The IRQ viewer
  switches off the CIA1 interrupt, so keyboard scanning, ESCAPE and TIME
  move into its per-frame hook (`uii_upic_irq_hook`), with the ROMs out.
  A "draw now, show later" switch (display off while drawing, at the full
  turbo speed) makes the slow demos practical. Event Horizon has 98,304
  pixels with SQR and divisions each.
- **Files.** `*UPIC SAVE`/`*UPIC LOAD` in the v1.3 `.upic` format
  (palette included), so pictures drawn in BASIC open in Upic Paint and the
  other way round.

**Where they go:** `examples/` as text sources (`.bas`), tokenised at build
time on the host (with ivop's run-bbc-basic or bbz), placed in the ROM
filing system bank and on a release disk image. They also provide the
footage for the release video.

---

## 12. Findings from implementation (Phase 0/1, 2026-10-04)

Verified in VICE 3.8 and on both Ultimates (Ultimate 64-II and Ultimate 64
Elite, firmware 3.15a) by the E2E suite (`make e2e`, `tests/e2e/`).

- **TwoMegabyter works on firmware 3.15a**, and so does EasyFlash subtype 1.
  Both cartridges are built from one source (`make`).
- **The Ultimate 64 runs cartridge ROM fetches at 1 MHz.** At "maximum
  turbo", a loop in RAM ran 55× faster than at 1 MHz, but a BASIC loop
  running from cartridge ROM only 1.5× faster. So at cold start the MOS
  copies BASIC to the RAM underneath the cartridge and switches the
  cartridge off; the trampoline maps it in only for MOS calls. BASIC is now
  about 30× faster (5000 empty FOR loops: 117 → 4 cs). HIMEM stays &8000.
  Consequences:
  - MOS code in cartridge banks runs at bus speed. Hot paths (OSWRCH,
    OSRDCH) should move to RAM once space allows.
  - **Lookup tables in cartridge ROM cost about one bus cycle (~1 µs, or
    48–64 CPU cycles at turbo) per byte read.** They still pay off where
    the alternative costs thousands of cycles (transcendental functions,
    scaling, font rendering into bitmaps). Hot tables belong in RAM.
- **TIME stays real-time at turbo speed** (99–100 per second): the CIA
  timers are not CPU-clocked.
- **The KERNAL screen editor limits input lines to 80 columns** including
  the prompt (78 characters after `>`). A line that fills all 80 columns
  wraps onto an empty row and reads back as blank, as in C64 BASIC.
- The KERNAL editor reads the π screen code back as PETSCII `$FF`, not
  `$DE`. Both are mapped to `~`.
- **Default speed:** the cold start selects speed index 15 (the hardware
  maximum, 48 or 64 MHz) when the turbo registers are enabled. Ultimate II+
  and stock C64 stay at 1 MHz. In "Turbo Enable Bit" mode it sets the bit.
- **`.cfg` autoload:** since firmware 3.15 (commit 7a436e47, 2026-07-24)
  starting a `.crt` from the Ultimate's file browser also loads `<name>.cfg`
  from the same directory, in memory only, not saved to flash. REST
  `runners:run_crt` (used by c64bridge and the E2E suite) does not do this.
  The build ships `u64bbc-tmb.cfg`/`u64bbc-ef.cfg` (Command Interface,
  REU, Ultimate Audio mapping, U64 turbo registers), checked against both
  devices by `make checkcfg`. Firmware 3.15+ also has the UCI command
  "load config" (`0x50`), so later the MOS can apply settings itself.
- c64bridge's own VICE launch waits up to 20 s for a C64 BASIC prompt.
  The E2E suite starts VICE itself with the binary monitor, and c64bridge
  attaches to it.

## 13. Roadmap additions (requests 2026-10-04)

- **Full PETSCII mode, for PETSCII art.** `*PETSCII` / `*ASCII`, or
  `MODE` variants. Bytes go to the KERNAL unchanged, with the
  upper case/graphics set or the lower/upper set, and colour/reverse
  codes work. The open design point: BBC VDU codes 17–31 (COLOUR,
  TAB(x,y), …) collide with PETSCII colour and cursor codes. Proposal: in
  PETSCII mode only CR and LF keep their BBC meaning, and the BBC
  functions stay reachable through codes PETSCII leaves unused (VDU 22,
  23, 25). In ASCII mode, codes 128–255 should print the PETSCII graphics
  glyphs.
- **Own line editor**, replacing the KERNAL editor: BBC-length lines
  (238 characters) and BBC COPY-key editing.
- **Lookup tables in spare cartridge banks**, chosen with the bus-speed
  cost above in mind: SID frequency table for SOUND (BBC quarter-semitone
  pitch), bitmap row/column address and pixel-mask tables, coordinate
  scaling for BBC 1280×1024 → C64/Upic, an 8×8 font for text in graphics
  modes, quarter-square multiply tables for the graphics code, Upic column
  addresses. Faster SIN/COS/LN/EXP/SQR would mean patching BBC BASIC's
  float routines. That breaks the "unmodified interpreter" rule (`make
  compare-core`), so it is a separate decision. Precision must match the
  5-byte floats.
- **C128 cartridge** after the C64 one works, Ultimate II+ included:
  80-column VDC text and the screen modes of VDC Maniac, through the
  `vdc_core` library knowledge (`~/.claude/vdclib_c128.md`).
- **`.cfg` and the MOS:** make sure everything the implemented commands
  need is switched on: Command Interface, REU, Ultimate Audio, turbo
  registers, later SID settings for SOUND. The `.cfg` covers file-browser
  starts; for other starts the MOS can check at boot and offer `*SETUP`
  (UCI command `0x50`).
- **Quality rules** (now in force): every routine has a
  Summary/Function/Input/Output/Uses header; buffers are bounded (VDU
  parameters, error copy, line input); the MOS zero page is never used in
  interrupt handlers; the MOS allocates no memory dynamically, and BRK
  unwinds through BASIC's stack reset. BASIC's own string heap has no
  garbage collector (BBC BASIC reuses a string's space when the new value
  fits, and CLEAR/RUN reclaim the rest). That is interpreter behaviour,
  documented for users, not patched.

## 14. Decisions (2026-10-04)

Asked interactively, each with a recommendation; all recommendations taken:

| Decision | Choice |
|---|---|
| Version control | Branch `phase1-mos`, a commit per tested step |
| UCI assembler port | In this repo (`src/mos/uci.s`) first; moves to `ultimate-uci-oscar64/asm/mads/` with a library release once stable |
| Faster maths | Interpreter stays unmodified (`make compare-core`); cartridge tables only for MOS work (graphics, sound, fonts) |
| PETSCII | Switchable PETSCII mode (`*PETSCII` / `*ASCII`), with codes 128-255 printing PETSCII graphics in ASCII mode |
| Licence | Ship the full `.crt` with `NOTICE.md`; courtesy message to Ivo van Poorten and J.G. Harston before the first public release |
| Help | Full reference in cartridge banks: every keyword, command and topic (`*HELP`), single source `src/help/help.txt` also generating `docs/HELP_REFERENCE.md` |

## 15. Phase 2/3 status (2026-10-04)

Done and tested on both Ultimates (VICE: the "no Ultimate" path):

- **Bank layout:** 0 MOS core and help reader, 1 BASIC, 2 UCI driver,
  filing system and Ultimate commands, 3-4 help (157 entries). Banks 0 and
  2 come from one assembly (`src/mos/cart.s`); the trampoline takes a
  target bank.
- **UCI driver** (`src/mos/uci.s`): detect/unlock, send with streamed
  payload, packet reads straight to memory, status into the error buffer,
  every wait leaves on ESCAPE. Error numbers: 214 not found / doesn't
  exist, 189 access denied, 199 other.
- **Filing system** on the Ultimate's DOS targets: LOAD, SAVE, CHAIN,
  OPENIN/OPENOUT/OPENUP (two channels, &11 and &12), BGET#, BPUT#, PRINT#,
  INPUT#, PTR# (with seek), EXT#, EOF#, CLOSE#. LOAD/SAVE are single
  transfers between &0800 and &7FFF.
- **Commands:** `*CAT` / `*.`, `*DIR` / `*CD`, `*PWD`, `*DELETE`,
  `*MKDIR` / `*CDIR`, `*RENAME`, `*LOAD`, `*SAVE`, `*TYPE`, `*UVER`,
  `*TIME`, `*TURBO`, `*FX`, `*HELP`.
- **Help:** `*HELP [subject]`, exact match or prefix list, paged.
  `genhelp.py` fails the build when a MOS command has no help entry.
- **Guardrails:** MOS zero page reduced to `$52-$6F` (`&70-&8F` free for
  users, as on a BBC Micro); filing system state in the resident page.

Found on the way:
- The firmware's message for a missing file is "File doesn't exist".
- While a UCI file transfer runs, the Ultimate 64-II can refuse a REST
  memory access ("firmware reported failure"). The E2E client retries.

Next: IEC filing system fallback (Ultimate II+ without UCI, VICE), drives
and disk images (`*MOUNT`), the PETSCII mode, graphics (MODE/PLOT/DRAW/GCOL)
and SOUND.

## 16. Design note for graphics and sound (owner, 2026-10-04)

Aim for the highest compatibility with BBC Micro programs, including their
graphics and sound: MODE 0-7 semantics, VDU 4/5, 18-29 (GCOL, palette,
windows, origin), PLOT (lines, triangles, fills, circles), POINT, CLG,
SOUND with its four channels, and ENVELOPE. At the same time make full
use of the C64: VIC-II (hires/multicolour bitmaps, sprites, raster
effects, the 16 colours with palette control, Upic) and SID (three voices
with waveforms, ADSR, filter; second SID, Ultimate Audio).

If one model cannot serve both, add a switch between a **BBC Micro mode**
(BBC behaviour first: BBC screen modes mapped onto the C64, BBC sound
semantics on SID) and a **Commodore mode** (C64 behaviour first: direct
VIC/SID access, PETSCII, C64 colours, sprites), for example `*BBC` /
`*C64`, with the current mode remembered and shown at start-up. This
joins the decided PETSCII mode (section 14). To design in detail when
graphics and sound are started.

Scope (owner, 2026-10-07): compatibility means BBC BASIC *programs*
(language, VDU/PLOT/SOUND behaviour), not the BBC Micro machine (memory
map, hardware, MOS internals, machine code). This is not an emulator.
Details and the requirements of the same day (BBC charset and palette in
BBC mode, custom fonts and palettes, outline/solid/pattern fill for every
shape, memory modes under program control): docs/DESIGN_GRAPHICS.md
section 9.

## 17. Using the REU (16 MB) — proposals (2026-10-04)

Working assumption from the owner: an REU is always there (the `.cfg`
switches it on; the Ultimate II+ has one as well). The MOS detects it and
its size at start-up; without an REU these features report "No REU" and
everything else keeps working.

**Speed fact first.** REU DMA moves one byte per bus cycle, about 1 MB/s,
and stops the CPU meanwhile. At 48/64 MHz the CPU copies RAM to RAM faster
(roughly 5-10 MB/s). So the REU is not a faster RAM. It gives capacity,
and the Ultimate can fill it directly from files. It speeds things up
where the alternative is slower than 1 MB/s: the 1 MHz cartridge ROM, UCI
commands per byte, and the network.

Proposals, most useful first:

1. **REU as a fast filing system and file cache.**
   - `*FS REU` or a `:R.` drive: a RAM disk of up to 16 MB with a
     directory, used by LOAD, SAVE, OPENIN and BGET#. LOAD and SAVE
     become DMA transfers; BGET#/BPUT# become RAM speed instead of one
     UCI command per byte.
   - The Ultimate filing system can read whole files into the REU
     (DOS "load REU", one command for the whole file). OPENIN then only
     fetches the file once, and BGET# reads from the REU through a
     small RAM window.
   - This removes today's main bottleneck: per-byte file I/O.
2. **Program and session snapshots.**
   - `*SNAPSHOT n` and `*RESTORE n` save and restore all of PAGE..HIMEM
     plus the BASIC workspace (&0400-&07FF) and zero page: about 31K, so
     500 slots in 16 MB.
   - Uses: instant switching between programs including their
     variables; an automatic snapshot before every RUN, so `*UNDO` can
     recover from a crash or a NEW; and the remote debugger (rewind to
     the state before a run).
3. **Overlays for the MOS.**
   - The cartridge banks are copied to the REU at start-up. MOS code
     that should run fast (OSWRCH, the VDU and graphics driver, the
     filing system) is pulled into a RAM overlay area by DMA, instead of
     running at 1 MHz from cartridge ROM.
   - Better still, the most-used parts move to RAM permanently and the
     rest is paged in.
   - This needs a RAM overlay window, competing with program space and
     the graphics bitmap, so it is to be sized when graphics are
     designed.
4. **Graphics.**
   - Several full screens (bitmap and colour, 9-10K each) in the REU:
     double buffering, instant MODE switching back to the text screen
     with its content kept, and picture libraries.
   - Upic: 48K pictures are kept in the REU, so BASIC keeps its full
     memory while editing and swaps the picture in only for display.
   - Sprite and character-set sheets.
5. **Sound.**
   - Ultimate Audio plays samples straight from the REU (this is how the
     library's audio and MOD player work). SOUND and ENVELOPE can get
     sampled instruments, and `*MODPLAY` keeps the module in the REU.
6. **Big data for programs, without changing the interpreter.**
   - OSWORD calls and `*` commands for block moves between memory and
     the REU (`OSWORD &E0`: address, REU offset, length, direction), and
     `*REU LOAD/SAVE` of files straight into the REU.
   - Plus a small BASIC library (PROCs/FNs) giving programs megabytes
     of arrays and data in pages. BBC BASIC itself still has 30K for
     program and variables.
7. **Remote and debugging.**
   - A long output log and a TRACE history (the last thousands of lines
     executed, with chosen variables) in the REU. The debugger and AI
     agents can then ask "how did we get here".
   - The REST API cannot read the REU directly, so the MOS pages the log
     through the mailbox.
8. **Command-line history.** The last few hundred typed lines, recalled
   with the cursor keys once the MOS has its own line editor.

Not proposed: using the REU as transparent extra memory for BBC BASIC
variables. That would need the interpreter to be patched, which is ruled
out (section 14).

Suggested order: 1 (file speed), 2 (snapshots, also for the debugger),
6 (REU commands), then 4 and 5 together with graphics and sound, and 3
when the RAM map for graphics is fixed.

## 18. Owner notes (2026-10-04, later)

- **REU RAM disk as a drive**, like the Ultimate's /Temp: proposal 1 of
  section 17, as a drive the filing system can address
  (e.g. `*DIR :R` or `/REU`), with LOAD/SAVE/OPENIN on it at DMA speed.
- **BBC Micro character set as an option.** The 8x8 font is in the BBC
  MOS ROM, which is © Acorn, so it has the same status as the
  interpreter (see NOTICE.md): no open licence. Options: ship it under
  the same good-faith notice, behind `*FONT BBC`; or let the user load
  a font file (`*FONT LOAD file`) so the cartridge contains none. A
  look-alike drawn from scratch is a third option. To decide when the
  character set code is touched; the loadable-font route works in any
  case.
- **System information command**: show memory (PAGE, TOP, LOMEM,
  VARTOP, HIMEM, free), MOS version and cartridge type, CPU speed and
  turbo state, the Ultimate's hardware and firmware, REU size, drives
  (IEC, SoftIEC, types, power), current directory and open files, the
  network address, and the date and time. Proposed name `*STATUS`
  (the Master 128's command for showing settings), with `*SYS` as an
  alias. **Done** (`src/mos/status.s`), with REU size detection that
  leaves the REU's contents alone (`src/mos/reu.s`). Firmware 3.15a
  counts the SoftIEC drive and the printer in "get drive info" but does
  not send their bytes (upstream fix 2026-10-02, #941): `*STATUS` lists
  only entries that arrived. `uii_parse_deviceinfo` in
  ultimate-uci-oscar64 trusts the count and should get the same guard
  (library issue).

## 19. Decisions (2026-10-07)

| Decision | Choice |
|---|---|
| Graphics kernel + fast VDU path | REU overlay into the font area on MODE, with automatic fallback to a lower HIMEM when there is no REU (docs/DESIGN_GRAPHICS.md section 2) |
| Upic | Canvas in the REU, `*UPIC SHOW` swaps BASIC out; the compact 48 MHz variant (picture stays visible while BASIC runs slowly) later |
| Maths | Option 1: integer tables for programs (`*TABLE`), used by the MOS too; the interpreter stays bit-exact (decided after weighing a fast-maths build: 2-3x gain, precision, RAM and maintenance costs) |
| Firmware functions | Batch A first (drives, storage, SoftIEC partitions), then graphics (docs/ULTIMATE_FUNCTIONS.md) |
| BBC compatibility | BASIC programs only, not the machine; not an emulator (DESIGN_GRAPHICS.md section 9.1) |
| Graphics extras | BBC charset and palette in BBC mode; custom fonts/palettes; outline, solid and pattern fill (BBC Master ECF) for every shape; memory modes settable from programs (DESIGN_GRAPHICS.md section 9) |
| Screen modes | BBC 0-7, Archimedes modes that fit Upic, C64 modes 100-104, Upic 64/48 as 110/111 (DESIGN_GRAPHICS.md section 10) |
| Graphics kernel | Split: VDU/text core with I/O at `$C800-$CFFF`, drawing engine under I/O at `$D000-$DFFF`, font `$F000`, bitmap `$E000`, RAM vectors at `$FFFA`; HIMEM `&8000` in all VIC modes (replaces the REU overlay / HIMEM fallback of the morning) |
| BBC modes 0, 1, 2, 4, 5 | Upic by default on a U64 (exact 256 lines): live for MODE 2/5 if the double-pixel live renderer works on hardware, shown by swapping for 0/1/4; the VIC-II elsewhere and on request |
| BBC text grid on the VIC | 32 rows with an 8x6 font in modes 0/1/2/4/5 (fallback only, see Upic Lite); text modes 3/6/7 stay on the VIC-II |
| Upic Lite (owner, 2026-10-07) | Live Upic-style renderers, 320 x 256 with even 1-dot pixels (32-dot border), 1 or 2 bits per pixel through the programmable palette; proven on the U64-II (DESIGN_GRAPHICS.md section 10.8). Default for BBC MODE 0/1/4 on 64 MHz machines, 160-wide for MODE 2/5 everywhere; the VIC-II versions stay as fallback (48 MHz machines for 320-wide modes, VICE, Ultimate II+) |
| Teletext MODE 7 | VIC-II hires bitmap, 8x8 cells (per-cell foreground/background), double height, mosaics |
| BBC font (2026-10-07) | The MOS 1.20 glyphs in the cartridge behind `*FONT BBC`, good faith as for the interpreter (NOTICE.md) |
| Font files | Explicit format word: `*FONT LOAD/SAVE file [C64|BBC|ASCII]` |
| Palette files | Both: 48-byte RGB binary (C64 colour order) as the native format, plus VICE `.vpl` text files; `VDU 19,l,16,r,g,b` sets one RGB colour |
| Sound (2026-10-09) | SID mode (all 24 voices of up to 8 SIDs, Heartbeat-style instruments, `SOUND &FSVV`) as default, `*SOUND BBC` sounding like a BBC; engine in RAM with PAGE &1900; BBC mode first (DESIGN_SOUND.md) |
| Memory (2026-10-09, later) | The REU first, to leave BASIC as much RAM as possible: the sound engine keeps its large tables (note queues, BBC envelopes, part of the instrument data) in the REU; PAGE &1D00 (as a BBC with ADFS) for the sound engine with modulation and the tracker; REU data storage and the REU RAM disk (section 23) come before the tracker |
| Memory modes (2026-10-08) | Both: BBC Master shadow modes (`MODE 128+n`, `*SHADOW`, OSBYTE &72/&75) choose the VIC-II version of MODE 0-6 with HIMEM &8000; `*MEMORY UPIC ON|OFF|AUTO` as an alias; `*MEMORY` shows the map (DESIGN_GRAPHICS.md 9.5) |
| SoftIEC | Partition support (add partition, `CP`) is needed to reach anything outside `/Temp` from the SoftIEC drive (owner note) |

## 20. Structured programs and automatic indentation (owner, 2026-10-07)

Example and demo programs are structured: no GOTO, DEF PROC/FN instead of
GOSUB, indentation by block nesting. Measured on the U64: BBC BASIC 3.10
keeps spaces typed after the line number, and `LISTO` adds its own
indentation on top of them (FOR/NEXT and REPEAT/UNTIL only, not procedure
bodies). Hence:

- **Source files are indented** (2 spaces per level after the line number,
  no colons), readable on GitHub and in the editor.
- **Roadmap: VS Code formatter.** "Format Document" (optionally on save)
  indents by nesting: FOR/NEXT, REPEAT/UNTIL, DEF PROC/ENDPROC, DEF FN.
  The extension strips leading spaces when it sends a program to the
  machine (a setting keeps them), so the program in memory stays compact
  and `LISTO 7` gives the loop indentation there.
- **Roadmap: `*LIST`.** A MOS command that lists the program in memory
  with full indentation, procedure bodies included, without changing the
  interpreter (token table in a spare cartridge bank; options as LISTO,
  line ranges as LIST).

## 21. Random numbers as close to true randomness as possible (proposal, 2026-10-07)

BBC BASIC's RND is a 33-bit shift register (period 2^33 - 1) with its
seed in BASIC's zero page at `&0D-&11`. At language start BASIC sets its
fixed seed ("ARW") only when the seed is zero, so the MOS can seed it
without changing the interpreter. Proposals:

1. **Entropy pool** in the MOS interrupt: mix in, at every interrupt and
   above all at every key press, timing-dependent values: CIA timer low
   bytes, the raster position, SID voice 3's noise oscillator (running
   silently); also the Ultimate's clock and the timing of UCI, network and
   USB replies. Human key timing at 64 MHz resolution is true entropy.
2. **Seed at start-up** from the pool into `&0D-&11` before BASIC starts:
   a different sequence after every start. `RND(-n)` (reproducible) and
   `RND(0)` keep their BBC meaning.
3. **`*RANDOMIZE`**: reseed RND from the pool now (for example after a
   game's first key press).
4. **A better generator next to RND** (statistically weak, kept for
   compatibility): a MOS call or `*RND` returning bytes from a modern
   generator (xorshift128+ or similar), continuously reseeded from the
   pool.
5. **`*RANDOMIZE NET`** (optional): a seed from the internet (random.org,
   the drand beacon) through the Ultimate's network.

## 22. Demo package: classic BBC BASIC programs (owner, 2026-10-07)

Well-known BBC BASIC programs under permissive licences, to show
compatibility, next to our own demos (graphics, Upic Lite, Ultimate
features, ArchBAS ports). Found so far:

| Source | Licence | Candidates | Notes |
|---|---|---|---|
| BBC BASIC (Z80) examples by Richard Russell, in [agon-bbc-basic](https://github.com/breakintoprogram/agon-bbc-basic) `examples/` | zlib | ANIMAL (the learning guessing game), serial/random/indexed file demos (F-*), MERGE, SORT, SORTREAL | Plain BBC BASIC; the file demos exercise our filing system (OPENIN/OPENOUT/PTR#/EXT#) |
| [BBCSDL](https://github.com/rtrussell/BBCSDL) `examples/` (Richard Russell) | zlib (`licence.txt`) | Towers of Hanoi (R.T. Russell, 1982), SINE (John A. Coll, 1981, author of the BBC Micro User Guide), fractal fern, Conway's Life, Mandelbrot, Truchet, kaleidoscope, MODE 7 demo | Stored in BB4W's tokenised format; most have a BBCSDL-only first line (touch IDE) and some use BASIC V/BB4W features (CASE, MODE 8, *REFRESH) that need a small rewrite |

Rules: zlib requires altered versions to be plainly marked, so every
adapted program gets a header naming the original author, source and
licence and the changes (as the code attribution rule in CLAUDE.md), and
the package gets the zlib notices. "BBC PD" (1991 library) is not
permissive (non-commercial only) and is not used. Each program is
checked on the machine; ports follow the structured-programming rules
(section 20) only where the original is ours to restyle -- classics stay
as close to the original as possible, so they show compatibility.

To do: a converter for BB4W's tokenised .bbc format (tools/), then
porting and testing per program once triangles, circles and fills exist.

## 23. Bigger programs with the REU (owner, 2026-10-09)

Owner question: can BASIC code and variables live in a reserved part of
the REU, for much bigger programs? Not directly: the interpreter reads
program lines and variables from C64 RAM with its own pointers, and
patching it is ruled out (section 14, and section 17's note). Chosen
instead (owner, 2026-10-09), after the sound phase:

1. **REU data storage**, as the BBC Master's sideways RAM: `*SRWRITE`
   and `*SRREAD` (`*SRWRITE <start> <end>|+<length> <REU address>`) and
   OSWORD `&42` from programs copy a DIM'd block or an array to and from
   the REU at DMA speed. Megabytes of data for a program that keeps only
   its code in RAM. A REU area for programs is reserved next to the RAM
   disk (DESIGN_GRAPHICS.md 6).
2. **REU RAM disk and CHAIN** (section 17 proposal 1, section 18): a
   `/REU` drive with LOAD/SAVE/CHAIN/OPENIN at DMA speed, so a big
   program can be split into parts that CHAIN each other at once,
   passing values in A%-Z% and @% (which survive CHAIN).
3. **Procedure libraries** (to investigate first): a MOS command that
   puts a library of `DEF PROC`/`DEF FN` from the REU above the program
   (`*LIB <file>`), as BBC BASIC IV/V's `INSTALL` does, so the main
   program stays small. BASIC 3.10 finds procedures by searching from
   PAGE, so the library has to look like part of the program to it; how
   to do that without patching (e.g. the library placed in front of the
   program with PAGE moved, or appended after TOP) is the first question.

Not chosen: a patched interpreter with more memory (as HIBASIC).

Status (2026-10-09): item 1 built (`srcmd.s`: `*SRWRITE`, `*SRREAD`,
OSWORD `&42` with the Master's block layout, the REU bank in place of
the ROM number; C64 side PAGE-`&7FFF`, REU side from `$040000`; "No REU"
on a C64 without one). Item 2, step 1 (whole files) built: the
directory `/REU` (owner: a directory, not a drive letter), cartridge
bank 5 (`reudisk.s`; routing in `rdglue.s`, bank 2):

- an REU of 2 MB or more; header at `$100000` ("U64RDISK", version,
  data end), 127 entries of 32 bytes from `$100020` (name of up to 16
  characters, start, length, load and execution address), data from
  `$101000`, one file after another; a delete moves the files after it
  down (no gaps, no fragmentation). Kept over a reset (recognised by its
  header), lost when switched off.
- `*DIR /REU` makes it current (`*DIR ..` back to the Ultimate's
  directory, which is kept), or `/REU/NAME` from anywhere: OSFILE
  (LOAD, SAVE, CHAIN, `*LOAD`, `*SAVE`), `*CAT [/REU]`, `*DELETE`,
  `*RENAME`, `*TYPE`, `*COPY` between `/REU` and the drives (128-byte
  pieces).
- Step 2 (owner: everything, in two steps): open files on `/REU`
  (OPENIN/OPENOUT/OPENUP, BGET#, BPUT#, PTR#, EXT#, EOF#) on the same
  two channels as the Ultimate's files (`ch_open` bit 0 marks a RAM disk
  channel, `rd_chent` its entry). Writing past the end of a file that is
  not the last one first moves it to the end (`rd_tolast`: copy, then
  close the gap), so files stay contiguous; setting PTR# past EXT# and
  writing fills zeros. Deleting or replacing an open file: "Open".
  Bank 2 is nearly full after this (about 200 bytes left).

Order (owner, 2026-10-09): items 1 and 2 now, before the song tracker.
REU map for it: banks 0-3 (`$000000-$03FFFF`) stay the MOS's (fonts,
palettes, instruments, songs); programs' data from `$040000` up to the
RAM disk; the RAM disk at `$100000-` (the REU's size).

Switching functions off for more RAM (owner, 2026-10-09): `*SOUND NONE`
takes the sound engine out and frees `&0800-&1CFF`; a program may then
set `PAGE=&800` itself (as on a BBC, where PAGE could be lowered when a
filing system's workspace was not needed) and has 30K; `*SOUND SID|BBC`
brings the engine back and refuses while PAGE is below `&1D00`.
`*MEMORY` shows what is switched on. To be built with the sound
engine's split (DESIGN_TRACKER.md section 6).

Status (2026-10-09, later): the sound engine split is built (two images
in bank 6, PAGE &1D00, MOSBUF at &0800, `*SOUND NONE` with PAGE down to
&900; DESIGN_SOUND.md section 11), with modulation (step b2) and the
song tracker (`*SONG`, DESIGN_TRACKER.md section 7). Large tables in the
REU: the BBC envelopes, instruments, wave/arpeggio tables, the song;
the note queues stay in RAM (the interrupt reads them every time).

Phase 5 (network) status (2026-10-10): built, docs/DESIGN_NETWORK.md
section 9; the U64TEXT demo and the blog mirror on the BBS server are
next.

## 24. Music demo (owner, 2026-10-09)

A music demo that shows off the instruments and all 24 voices, with
public-domain music in our own arrangements (licensed with the project):
classical (Bach, Mozart, Beethoven's *Ode to Joy*, Pachelbel's *Canon*),
folk (*Greensleeves*, *Scarborough Fair*, the *Londonderry Air*), and as
"pop" the public-domain ragtime and early popular songs (Joplin's *The
Entertainer* and *Maple Leaf Rag*, *Take Me Out to the Ball Game*, 1908);
later pop songs are under copyright. After sound step (b2) and `*PLAY`
(DESIGN_SOUND.md), so the music is written as note strings.

## 25. The MOS line editor (owner, 2026-10-10)

Decisions (owner): the hybrid key layout, F1 as COPY, the new editor as
the default with `*EDIT C64` to switch back to the KERNAL's full-screen
editor (`*EDIT BBC` returns; `*EDIT` shows which).

Built in `src/mos/lineed.s` (bank 0, about 1.5 KB), entered from OSWORD 0
(`word0`) when `EDMODE` ($03FC) is 0:

- One editor for every screen mode: it only moves the text cursor
  (`K_PLOT` on the text screen, `tcx`/`tcy` elsewhere) and prints through
  OSWRCH without the remote capture. The line's start is kept as a screen
  position; after each redraw the cursor is read back, and a row less
  than expected means the screen scrolled.
- Lines up to the caller's maximum: 238 at BASIC's prompt (the KERNAL
  editor allowed 78 after the prompt).
- Keys: LEFT/RIGHT, CLR/HOME (start), SHIFT+CLR/HOME (end), DEL, INST,
  UP/DOWN (history), CTRL+cursor keys (copy cursor), F1 (COPY), RETURN
  from anywhere in the line. The C64 has two cursor keys with SHIFT for
  up/left, so SHIFT+cursor could not be the copy cursor as on a BBC;
  CTRL+cursor, which the KERNAL does not decode, is read while waiting
  for a key (`SHFLAG`, the held key in `$CB`), repeating like a key.
  A remote host types the copy cursor moves as `$80/$82/$84/$8F`.
- Copy reads the text screen (screen codes) and MODE 7 (&7C00); the
  bitmap modes keep no character codes, so COPY does nothing there
  (the BBC matched glyphs for OSBYTE &87; possible later).
- History: REU bank 0 `$8000-$FFFF`, 128 slots of 256 bytes; 127 lines
  typed at BASIC's prompt (not INPUT answers, not empty lines, not the
  same line twice in a row), slot 127 keeps the line being typed while
  older ones are shown. Head and count at REU `$3500`. Without an REU
  (VICE in the tests) there is no history.
- State in `MOSBUF+$C0` (no * command runs while a line is typed);
  RAM was full elsewhere (resident area, `$0200-$03FB`, the RAM core).

Not yet: COPY in bitmap modes.

`*KEY` (2026-10-10, owner's choice of the next roadmap item): `*KEY n
text` for F1-F8 (the C64's labels; keys 0 and 9 kept for BBC programs),
GSTRANS codes (`|M`, `|A`-`|Z`, `|?`, `||`, `|"`, `|!`), `*KEY n`
clears, `*KEY` lists. Texts in the REU (bank 0 $3600, 64 bytes a key),
the expansion in the RAM core (`kx_*`); every key the MOS reads goes
through `key_avail`/`key_get` (OSRDCH, INKEY, the line editor), so a
text types at the prompt and in programs. F1 is COPY until `*KEY 1` is
set. Not with `*EDIT C64` (the KERNAL reads the keys).

CAPS LOCK (2026-10-10): Shift+C= switches it (irq_keylog; off = the
KERNAL's own tables), OSBYTE &CA reads and sets it (bit 4).

## 26. Snapshots, then sprites, then Upic full (owner, 2026-10-14)

Snapshots (built): `*SNAPSHOT n` takes BASIC's world at the prompt into
REU slot n (1-9, &B8000-&FFFFF, 32K each; slot 0 at &B0000 is the
working slot for files): BASIC's zero page ($02-$51; the user's $70-$8F),
its workspace &0400-&07FF and PAGE..HIMEM, with the mode, PAGE, HIMEM
and the time in a header. `*SNAPSHOT LOAD n` sets the mode first, then
copies everything back: BASIC finishes the restored line and is at the
prompt with the program and variables as they were (taken at the prompt
only: the interpreter's 6502 stack is then the same). `*SNAPSHOT SAVE n
file` / `LOAD file` copy a slot to and from the Ultimate's drives (the
owner chose both). `*SRWRITE`/OSWORD &42 now stop at &AFFFF.

Next, in this order (owner): sprites with multiplexing (`*SPRITE`:
define, position in BBC coordinates, colour, collisions; up to ~32 by
raster interrupt; VIC-II modes, MODE 7, MODE 100; Upic Lite to be
tested), then Upic full (MODE 110/111, DESIGN_GRAPHICS section 10).

GXR sprites (owner, 2026-10-14; on the roadmap after Upic full): the
BBC has no hardware sprites; Acorn's Graphics Extension ROM (built into
the Master 128) adds software sprites, drawn into the picture: shapes
from the screen or defined (`*SGET`, `*SEDIT`, `*SLOAD`, `*SSAVE`, ...),
chosen with `VDU 23,27`, plotted with `PLOT &E8-&EF`. Here they are
drawn by the engine into every bitmap mode, not only the BBC modes
(0-6, Upic Lite and MODE 128+n) but also our own Upic modes (Upic full,
MODE 110/111, with its own colour depth and resolution; owner,
2026-10-14), so they show where VIC-II sprites cannot (DESIGN_SPRITES
section 3), and run Master programs that use them. No 8-per-line limit, but drawing costs
time. Separate from `*SPRITE` (the VIC-II's, C64 only).

Upic full (MODE 110/111), decisions of 2026-10-14 (owner): **split
output**: PRINT, INPUT, the prompt, errors and the line editor use a live
VIC-II text console (40x25, as MODE 100); graphics and VDU 5 text go into
the Upic picture (in the REU). **Showing**: automatic when a program ends
(until a key) and while it waits in GET or a long INKEY, plus `*UPIC
SHOW` at any time; `*UPIC AUTO OFF` leaves only the latter. Continuous
display while BASIC runs is impossible here: the 48K picture must be in
C64 RAM at $1000-$CFFF to be rendered (the library's IRQ viewer does
that, with 18% of the CPU left), which is BASIC's and the MOS's RAM; from
the REU one line takes three raster lines. 16 colours live remain MODE 2
(Upic Lite, 160x256).

Demos (owner, 2026-10-14): the ArchBAS demos (github.com/xahmol/ArchBAS:
Eric Schraf's graphical demos and Aurel's Christmas tree, converted by
the owner to Archimedes BASIC) converted to BBC BASIC 3.10, with a
choice per demo: live (MODE 2, Upic Lite 160x256, the picture grows as
it is drawn) or full (MODE 110, 384x256, time-lapse progress views with
`*UPIC SHOW n`, the finished picture at the end); 16-colour palettes per
demo through VDU 19 RGB. And a graphics demo: a menu (GFXDEMO) chaining
one part per area (BBC modes, C64 modes, MODE 7, Upic full, sprites).

BASIC V graphics as * commands (owner, 2026-10-14; not BASIC V itself:
the interpreter stays the reference ROM): *RECTANGLE [FILL] x,y,w,h,
*CIRCLE [FILL] x,y,r, *ELLIPSE [FILL] x,y,a,b, *LINE x1,y1,x2,y2,
*POINT x,y become the PLOT codes; *COLOUR n,r,g,b is VDU 19,n,16,r,g,b;
*OFF / *ON the cursor (VDU 23,1); *GCOL c TINT t picks the nearest of the
mode's current palette entries to the Archimedes 256-colour RGB.
Arguments: numbers (decimal, &hex, negative) or BASIC's resident integer
variables A%-Z% (read from &0400+), no expressions. A host-side BASIC V
translator (bbctok) stays an option for converting whole programs.

MODE 1 on the VIC-II (owner, 2026-10-14, after a mock-up of both): 40
columns with the 4x6 font (X11 misc-fixed, Janne V. Kujala, public
domain) in its 4-pixel cells, swapped into the REU font while the mode is
on; the 8x8 glyphs drawn there showed only their left halves. Upic Lite's
MODE 1 keeps its 40 sharp columns.

Sprite editor (owner, 2026-10-14): one editor for both kinds, built
into the MOS (bank 7): `*SEDIT n` (GXR sprite n) and `*SEDIT VIC s`
(hardware shape s); a text-screen grid (one character cell a pixel, 16
colours, scrolling for big GXR sprites) with the palette and keys at the
side and a VIC shape previewed at size as a real sprite; drawing (cursor
keys, colours 0-F, SPACE, C, RETURN keeps, ESCAPE cancels), transforms
(flip, shift), size and new sprites (GXR: width/height, another sprite
copied in), fill. The previous mode is set again afterwards (cleared). Done
2026-10-14 (DESIGN_SPRITES 7); colours are typed 0-9 or chosen with +/-
(letters are commands), and M switches the VIC multicolour view.

More GXR (owner, 2026-10-14, after the editor): PLOT 72-79 and 88-95
(horizontal line fills), PLOT 184-191 (move/copy a rectangle), VDU 23,6
and *FX 163,242 (the dot-dash pattern), VDU 23,2-5 (ECF patterns as
screen bytes), *FLOOD/*NOFLOOD/*GXR/*NOGXR accepted. Done 2026-10-14
(DESIGN_GRAPHICS 10.14), except the dot-dash pattern: accepted, but
dotted lines keep every second pixel (no shared RAM for its table).

Acorn compatibility (owner, 2026-10-14, after the editor and the GXR
remainder): INKEY(-n) key scanning (BBC key numbers on the C64 matrix)
and INKEY(-256); ADVAL(0-4) with the C64 joysticks/paddles and the 1351
mouse (Master style); *FX19, 4, 11, 12, 200, 220, 229; the DFS commands
*EXEC, *SPOOL, *BUILD, *DUMP, *INFO, *ACCESS, *RUN; a BASIC toolkit
(*FIND, *REPLACE, *VARLIST, *XREF, *PACK); speech (*SAY, SAM-style).

Garbage collection (owner): not in the interpreter (it stays the
reference ROM, `make compare-core`); instead a manual section on keeping
the string heap from filling (manual chapter 12).


Acorn compatibility decisions (owner, 2026-10-14):
- INKEY(-256) returns &FF (BBC B with OS 1.2): programs take their
  baseline path rather than Master-only code we only partly support.
- ADVAL(1-4): by default the C64 joysticks in ports 1/2, read as
  extremes (0 / 32768 / 65520, high = left/up); *ADVAL JOY|PADDLE|MOUSE
  [port] switches a port to paddles (SID POT lines) or a 1351 mouse
  (position accumulated, clamped). ADVAL(0): the fire buttons.
- *PACK: removes REMs (not jump targets) and spaces outside strings, and
  joins lines that are not jump targets (up to 255 bytes; care with DATA,
  IF and ON...GOTO). No variable renaming. It asks for confirmation first.
- *SAY: SAM is loaded from the user's own disk (not distributed with the
  project) into the REU and called.
- Toolkit (*FIND, *REPLACE, *VARLIST, *XREF): Beebug Toolkit style.
- *ACCESS name L: the FAT read-only attribute where the Ultimate allows
  it, and a lock flag on the /REU RAM disk; without L it is cleared;
  'Locked' errors as in DFS.
- Dot-dash pattern: stays accepted without effect (see DESIGN_GRAPHICS 10.14).
- While the owner is away: push line-editor and fast-forward main after
  each commit that passes the full regression.
- Built 2026-10-15 (DESIGN_ACORN.md): keys, ADVAL and *FX (commit
  412a316); the DFS commands; the toolkit. Speech (*SAY with the user's
  SAM) follows.

80 columns back (owner, 2026-10-15), now with the 4x6 font in 4-pixel
cells (the squeezed 8-pixel glyphs of before were what read badly):
MODE 0 (80 columns, 2-colour graphics: 80x32 on the VIC-II with 6-line
rows as MODE 4, 80x32 in Upic Lite) and MODE 3 (80x25 text); the
mapping to MODE 4 / 6 goes.

COPY key in the bitmap modes (2026-10-15, from the open items): the
character under the copy cursor, and OSBYTE &87, are recognised from
the pixels (DESIGN_GRAPHICS 11.1). The Hanoi classic (MODE 3) is back
in demos/classics now that the 80 columns are.

CharPad (owner, 2026-10-15): fonts and maps, not the multicolour/ECM
text modes. `*FONT LOAD` recognises CTM files (the charset); a new
`*MAP` command loads a CTM map into the REU (tiles expanded to
characters, the per-character colours) and draws any part of it on the
C64 text screen (`*MAP DRAW mx,my,w,h AT col,row`); `*MAP GET mx,my`
puts the cell's character in M% for game logic; `*MAP` alone shows the
sizes. Text screen only (fast enough to redraw a window each frame).

Decisions of 2026-10-16 (owner, asked interactively):
- SpritePad colours: `*SPRITE n SHAPE s` also takes the colour and the
  multicolour flag a shape got from an SPD file; a later `*SPRITE n
  COLOUR` overrides.
- `*MAP`: 16-bit map sizes (up to 65535 wide or high), still 30720
  cells in one REU bank (1659 of CharPad's 1814 examples fit, 976
  before); `*MAP DRAW` and `GET` take 16-bit coordinates.
- `*HELP` reflows its paragraphs to the screen width when shown (40 or
  80 columns); command lists and tables keep their lines.
- Order: these three first, then a PETSCII mode, then the uneven
  baselines of the 6-line glyphs (VIC MODE 2/5). The C128 cartridge
  waits until after the first release.
- *SONG's "Song full" has not been seen since the REU-register fix of
  2026-10-10 (DESIGN_SOUND): closed.

Schraf demos (owner, 2026-10-16): the menu in the music demo's style,
live/full as a choice shown in the menu; SIN/COS from `*TABLE`, built
now (DESIGN_GRAPHICS 4: steps 256/512/1024, 256 for MODE 2's under 5K),
in every non-original demo with many SIN/COS (BUBBLE, FIELD, HAT,
GALAXY, GFXSPR; INVADERS has one per frame). Measuring showed the
command lookup was the bigger cost: *POINT 42 ms against PLOT 6 ms,
*OFF alone 38 ms, as OSCLI compared the word with every table entry in
order at 1 MHz. The table is now grouped by first letter with an index
(cmd_index; genhelp.py checks the grouping): *POINT 13.9 ms, *OFF 10.5,
*FX 4,0 8.6 (15.5). Bubble Universe: 4.3 s a row of 250 points, about 12
before. What remains of a * graphics command is mostly its VDU bytes,
about 1 ms each through OSWRCH: the next speed-up (OSWRCH's VDU path in
RAM: "hot paths should move to RAM", the U64 findings above).


PETSCII (owner, 2026-10-16, asked interactively; PLAN 13's proposal):
- The normal (ASCII) text modes stay as they are: their font's 128
  normal glyphs are full (95 ASCII, 33 graphics) and the reverse half
  serves the cursor and COLOUR 128+n; all PETSCII graphics are in the
  full mode (asked twice, "only in *PETSCII").
- A full PETSCII mode, `*PETSCII` / `*ASCII`: bytes go to the screen as
  on a C64. PETSCII wins: all of 0-31 and 128-159 act as on a C64
  (colours, reverse, cursor, case), only CR stays BBC's new line; BBC's
  TAB(x,y) and COLOUR do not work there; `*ASCII` or MODE go back.
- Keyboard in PETSCII mode: typed lines stay ASCII; GET/INKEY return
  PETSCII codes (C= and SHIFT graphics keys as on a C64).
- `*SEQ file` shows a PETSCII .seq file (PETSCII mode for its duration,
  paging like *TYPE).

## 27. Release 1.0.0 (owner, 2026-10-16, asked interactively)

In 1.0.0, in this order (speed first):

1. Faster * graphics commands (was "faster VDU path": measuring without
   the remote's capture showed VDU bytes take 15 us, but *POINT 2 ms;
   owner's choice, 2026-10-16): a RAM fast path for *POINT, *LINE,
   *RECTANGLE, *CIRCLE, *ELLIPSE in the graphics modes, 768 bytes below
   HIMEM (DESIGN_GRAPHICS 14). Done: *POINT 25-34 times faster.
2. The uneven baselines of the 6-line glyphs (VIC-II MODE 2/5) and the
   ASCII-mode cursor (a blink as the cursor moves on, e.g. by TAB,
   stays as a reverse cell; fixed for *PETSCII already). Done: the owner chose
   a fixed baseline (row 7 last, two of rows 0-6 dropped: leading blank,
   repeated, then rows 1 and 3); O/o, V/v and X/x then look the same in
   those cells (COPY and OSBYTE &87 read the capital); MODE no longer
   starts the cursor blink in the text modes (only input does).
3. Ultimate batch C: *MENU, *REBOOT, *SAVEMEM, *CONFIG, and a start-up
   check offering *SETUP when the Ultimate's settings (REU size, turbo,
   command interface) do not suit the MOS. Done (ultctl.s, bank 7): the
   owner chose to apply the settings automatically at start-up, and
   *REBOOT asks first.
4. Ultimate batch B: *REULOAD / *REUSAVE, REU preload images, OSWORD &E0. Done
   (reucmd.s in bank 6, the file work in bank 2).
   Owner, 2026-10-16: *REULOAD/*REUSAVE in the program area only
   (&40000-&8FFFF, as *SRWRITE; *REULOAD defaults to &40000); the preload
   image as *REU SAVE / *REU LOAD, presented as keeping the RAM disk (and
   REU data) over a power-off, LOAD asking first; OSWORD &E0 dropped
   (OSWORD &42 covers it).
5. Random numbers (section 21): RND seeded from real entropy at start-up
   and *RANDOMIZE (the better generator and the internet seed later). Done
   (rndseed.s, bank 3): no entropy pool (no free resident RAM); the
   entropy is gathered when seeding: BBC TIME, CIA 1 timer A, the raster
   line and TOD before and after a request to the Ultimate's clock, and
   its date/time text, hashed into &0D-&11 (33 bits, never zero).
   *RANDOMISE is the same command.
6. *TABLE SQR and 1/x. Done (mathtab2.s, bank 5; owner, 2026-10-16: as
   SIN, 32-bit x 65536): *TABLE SQR / RECIP addr [n], n 256-4096; the
   bit-by-bit maths runs as a RAM image in MOSBUF at turbo speed.
7. Ultimate batch G: the rest of HTTP (*HTTPGET, methods, headers,
   status codes). Owner, 2026-10-16: *NET POST url file|"text" [outfile],
   *NET PUT (the same), *NET DELETE url [outfile]: the reply to outfile
   or the screen; *NET HEADER Name: value for all following requests
   (alone: cleared); a status of 400 or more raises a catchable error
   ("HTTP 404 Not Found"; error 223: 220 is the MOS's "Syntax"), an OSBYTE returns the last status; and the
   JSON body builder: *JSON NEW, *JSON SET key value, *JSON POST url.
   Also (owner, 2026-10-16, firmware coverage check): *NET shows the MAC
   address, and *STATUS SID lists the SID configuration (control &28).
   Measured 2026-10-17 (firmware 3.15a): the HTTP target's raw exchange
   (&32) gives no status at all (a 404 page arrives as a reply), the JSON
   exchange (&31) only for valid JSON replies ("200 OK"; otherwise "400
   NO VALID JSON"). Owner's choice: the MOS speaks HTTP/1.0 itself over
   the network target's TCP socket for *NET GET/POST/PUT/DELETE and
   OPENIN "http://" (real status codes, response headers, replies
   streamed to a file without the 16K limit); *JSON keeps the firmware's
   JSON parser. Done 2026-10-17 (nethttp.s, jsonbody.s; DESIGN_NETWORK.md 10):
   all of it, plus *NET's MAC line and *STATUS SID; HTTP errors are
   error 223 (220 is the MOS's "Syntax").
8. Upic's compact 48 MHz variant (the picture stays visible while BASIC
   runs slowly). Dropped (owner, 2026-10-17): the 36K picture leaves
   about 6K for programs, or BASIC from the cartridge at 1 MHz; Upic full
   (MODE 110/111, auto-show) and Upic Lite cover showing pictures.
8a. Ultimate Audio (owner, 2026-10-16): sample sound effects (SOUND on
   voices 24-30, *SAMPLE LOAD n file: samples in the REU) and *MODPLAY
   file / *MODSTOP (a ProTracker MOD in the background), the player
   ported to MADS from ultimate-uci-oscar64's (credited), in its own
   bank, under the sound engine's interrupt rules. *HBPLAY after 1.0.0.
   Decisions of 2026-10-17 (owner): the MOD engine is a third sound
   engine image in &0900-&1C5F (*MODPLAY swaps the SID engine out,
   *MODSTOP back; sample sounds keep working); timing as the sources:
   CIA1 timer A at the MOD's tick rate while it plays, the MOS interrupt
   follows it (keyboard, ESCAPE live) and the MOD engine keeps TIME right
   (250/BPM cs per tick); SOUND 24-30: A = sample (or -15..0 a volume),
   P the BBC pitch scale (53 = the sample's own rate), D in 1/20 s (0: to
   the end, 255: loop). The player is ported to MADS from ModPlayer_16k by
   Freshness (6510nl), CSDb release 131522 (KickAssembler source,
   2014; no licence statement): port and credit (owner), as the library's
   C port (ultimate_modplay_lib.c) used it as its reference. REU
   (owner): 1 MB below *MAP's bank for audio (16 MB REU: &EE0000-&F1FFFF
   samples with their directory, &F20000-&FDFFFF the MOD, up to 768K;
   the RAM disk ends below &EE0000). Formats (owner): 8-bit mono WAV
   (rate from the header, unsigned data made signed on load) and raw
   signed 8-bit (*SAMPLE LOAD n file [rate], default 8000 Hz). Built in
   two steps (samples, then the MOD engine) in cartridge bank 10 (the
   help moves to 11+). Built 2026-10-17 (sample.s, modplay.s, modengine.s; demos/audio
   with 4ev.mod, wild_perspective.mod and Juhani Junkala's CC0 effects):
   measured that control bit 2 enables a channel's CPU interrupt (the
   library's "restart"; unacknowledged it hangs the machine), so loops use
   control 3 with relative loop points; the registers are big-endian.
9. A showcase demo (owner, 2026-10-16): one program that shows off
   the BASIC with nice graphics and music, the last thing before the
   release and the videos. Owner, 2026-10-17: a timed scene show
   (2-3 minutes, any key skips a scene), music in turns: SID (8 SIDs,
   the song tracker) in the first half, a MOD on Ultimate Audio in the
   second ("and now: Ultimate Audio" as a scene).
10. The release: a GitHub release with a ZIP (both .crt and .cfg, all
   demos tokenised and as source, the manual as PDF, README, licences)
   and the VS Code extension (.vsix); an announcement (Facebook post and
   an idreamtin8bits blog post).
11. Videos, five, one per group: 1 introduction (start-up, the line
    editor, BASIC 3.10, *HELP, VS Code); 2 graphics (BBC modes, Upic Lite
    and full, GXR, sprites, *MAP, PETSCII); 3 sound and music (SOUND and
    ENVELOPE on 8 SIDs, the song tracker, speech); 4 files, Ultimate and
    network (drives, the /REU RAM disk, DFS commands, *NET, *JSON, HTTP);
    5 demos (classics, Schraf, Hanoi, the music demo).
    Recorded from the VIC video stream with scripted key presses, no
    REST probing during a take (it corrupts the picture); the stream has
    no palette, so each scene's palette is applied in post (from the
    demo's *COLOUR/VDU 19 values, or one read after the take).

After 1.0.0: *HBPLAY (Heartbeat songs), Ultimate batch E (tape capture, GEOS RAM disk, track
decoding, an IEC filing system on SoftIEC, RAM disk info, echo), *NET IP
(setting the address) and the interface count, bigger *MAP maps (over 30720
cells), the better random generator and the internet seed, and the C128
cartridge.
