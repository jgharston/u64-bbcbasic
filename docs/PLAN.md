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
| `$0800–$7FFF` | **PAGE=&0800 … HIMEM=&8000: 30K for programs** (a BBC Model B in MODE 7 has about 25K) |
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
