# CLAUDE.md -- u64-bbcbasic

BBC BASIC 3.10 for the Ultimate 64 / C64 Ultimate as a cartridge, with a
BBC-style MOS in 6502 assembler (MADS). Plan, findings, decisions and
roadmap: `docs/PLAN.md`.

## Build and test

- `make` builds `build/u64bbc-tmb.crt` and `build/u64bbc-ef.crt` (+ `.cfg`).
- `make deploy` installs them with the demos (tokenised) on the Ultimate:
  `/<ULTDRV1>/idi8b/u64bbcbasic/` (`tools/deploy.py`; `.148`: `SD`).
- `make compare-core`: the interpreter must stay identical to Ivo van
  Poorten's reference ROM. Never patch `lib/bbc-basic`; the only change is
  `src/basic/u64-target.patch` (build target).
- `make e2e` (VICE + the Ultimates in `.env`) through c64bridge, group by
  group (`GROUP=graphics` for one; groups in `tests/e2e/README.md`);
  `tests/e2e/run_e2e.py --device IP --kind tmb --only NAME ...` for a
  subset. Run the affected tests after every MOS change; the full suite
  before a commit. Don't run `make` while an E2E run is uploading
  cartridges.

## Running BASIC on the machine

Use the MCP server `u64bbc` (`.mcp.json`, `tools/u64mcp.py`) or
`tools/u64remote.py`: see `docs/AI_AGENTS.md`. `bbc_help LIMITS` lists
what this BASIC can and cannot do.

## Code rules (from the project owner)

- Every assembler routine has a header: Summary, Function, Input, Output,
  Uses. Match the style in `src/mos/mos.s`.
- Bound every buffer; interrupt handlers never use the MOS zero page
  (`$52-$6F`); `$70-$8F` stays free for users; no dynamic allocation.
- The sound interrupt uses the REU: every foreground REU transfer sets
  the registers up with interrupts off (`php`/`sei` ... command, `plp`).
  Saving them in the interrupt does not work: the Ultimate's bank
  register reads back only its low 3 bits (memory wipes of 2026-10-10).
- MADS labels are case-insensitive: don't name a routine like a KERNAL
  equate (`keylog`/`KEYLOG`). `#>label+2` is `(>label)+2`: bracket the
  sum, `#>[label+2]` (an REU transfer once went to $0258, not $0058).
- Code in cartridge banks runs at bus speed (1 MHz) and cannot modify
  itself; put hot paths and anything self-modifying in RAM.
- New `*` commands need a `*HELP` entry in `src/help/help.txt` (the build
  fails otherwise) and an E2E test.
- Ask open design decisions with the question tool, explained, with a
  recommendation.
- Example/demo BASIC programs are structured: no GOTO, DEF PROC/FN
  instead of GOSUB. Source files are indented (2 spaces per level, after
  the line number; no `10 :` colons), kept consistent by the VS Code
  extension's formatter; the extension strips the indentation on upload,
  and on the machine `LISTO 7` indents loops (PLAN.md section 20).
- Commit per tested step on a branch; don't push without being asked.

## Layout

| Path | Contents |
|---|---|
| `src/mos/cart.s` | banks 0 and 2 in one assembly |
| `src/mos/mos.s` | bank 0: boot, VDU, keyboard, OSBYTE/OSWORD, OSCLI, *HELP reader |
| `src/mos/lineed.s` | bank 0: the line editor (OSWORD 0, history, copy cursor, `*EDIT`) |
| `src/mos/resident.s` | RAM $C400-$C7FF: entry points, trampoline, IRQ/BRK/NMI, mailbox |
| `src/mos/uci.s`, `fs.s`, `ucmds.s` | bank 2: UCI driver, filing system, Ultimate commands |
| `src/mos/reudisk.s`, `rdglue.s` | bank 5: the /REU RAM disk; its routing (bank 2) |
| `src/mos/sndbank.s`, `sound*.s`, `sndcmd.s`, `songcmd.s` | bank 6: the sound engine images (RAM &0900), sound and song commands |
| `src/mos/netbank.s`, `netcmd.s`, `netchan.s` | bank 7: network (*NET, *JSON, network channels); helpers `bankhelp.s` |
| `src/help/help.txt` | *HELP source (banks 8+, docs/HELP_REFERENCE.md) |
| `tools/` | mkcrt, gentables, genhelp, checkcfg, bbctok (tokeniser), u64remote, u64mcp |
| `tests/e2e/` | end-to-end suite |
