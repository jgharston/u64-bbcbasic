# u64-bbcbasic

BBC BASIC 3.10 for the Ultimate 64 and C64 Ultimate, as a cartridge, with a
BBC-style MOS (machine operating system) on top of the C64 KERNAL. Commands
for the Ultimate's features (UCI file system, drives, clock, turbo,
network, Ultimate Audio, Upic) are planned as `*` commands.

**Status: early development (0.1.0).** It boots to the BBC BASIC `>` prompt
and runs BASIC programs in text mode, at the device's maximum turbo speed,
with files on the Ultimate's USB/SD/RAM disk and a built-in help system
(`*HELP`). There are no graphics or sound yet. See
[docs/PLAN.md](docs/PLAN.md) for the plan and roadmap, and
[docs/HELP_REFERENCE.md](docs/HELP_REFERENCE.md) for the full reference.

**Compatibility.** The aim is that BBC BASIC *programs* run: the
language, and the behaviour of the VDU, graphics, sound and file
statements. It is not a BBC Micro emulator: the memory map, the BBC
hardware, the MOS internals and BBC machine code are not reproduced, so
programs that poke the machine or call BBC machine code will not work.

## Cartridges

| File | Type | For |
|---|---|---|
| `u64bbc-tmb.crt` | Protovision TwoMegabyter (CRT type 87) | Ultimate 64 / C64 Ultimate: UCI, REU, Ultimate Audio and turbo all usable |
| `u64bbc-ef.crt` | EasyFlash, subtype 1 | VICE, and as a fallback (no Ultimate Audio; the firmware moves UCI to `$DE1C`) |

Copy the `.cfg` with the same name next to the `.crt`. When the cartridge
is started from the Ultimate's file browser (firmware 3.15+), it switches
on the Command Interface, the REU, the Ultimate Audio mapping and the U64
turbo registers. The settings are loaded into memory only, not saved to
flash.

## Using it

- Letters type in capitals (BBC CAPS LOCK on); Shift gives lower case.
- The ASCII characters the C64 keyboard lacks: `\` = £, `^` = ↑, `_` = ←,
  `|` = Shift+£, `~` = Shift+↑, `{` = Shift++, `}` = Shift+-,
  `` ` `` = Shift+@.
- RUN/STOP is ESCAPE.
- Input lines can be up to 78 characters (the C64 screen editor's limit).
- `PAGE` = &0800, `HIMEM` = &8000: 30K for programs.
- MOS entry points: `OSWRCH` = &C7EE, `OSBYTE` = &C7F4, `OSWORD` = &C7F1,
  `OSCLI` = &C7F7, … (BBC low bytes, page &C7). The RAM vectors are at
  &0200, as on the BBC.
- Files on the Ultimate (see `*HELP FILES`): `LOAD`, `SAVE`, `CHAIN`, two
  open channels (`OPENIN`, `OPENOUT`, `OPENUP`, `BGET#`, `BPUT#`, `PRINT#`,
  `INPUT#`, `PTR#`, `EXT#`, `EOF#`).
- Commands: `*CAT` (`*.`), `*DIR` (`*CD`), `*PWD`, `*DELETE`, `*MKDIR`,
  `*RENAME`, `*LOAD`, `*SAVE`, `*TYPE`, `*UVER`, `*TIME`, `*TURBO`,
  `*STATUS` (memory, REU, drives, network, clock), `*FX`, `*HELP`.
- `*HELP` covers every BASIC keyword, command and topic: `*HELP KEYWORDS`,
  `*HELP COMMANDS`, `*HELP TOPICS`.

## Programming from a PC or an AI agent

- **VS Code:** the extension in `vscode/` (`make vscode` builds
  `build/u64-bbcbasic.vsix`) runs `.bas` files on the machine with
  Ctrl+F5, shows output and puts run-time errors on the source line.
- **Command line:** `tools/u64remote.py run prog.bas` (JSON with `--json`).
- **AI coding agents:** the MCP server `tools/u64mcp.py` (registered in
  `.mcp.json`); see [docs/AI_AGENTS.md](docs/AI_AGENTS.md).

## Building from source

Requirements: [MADS](https://github.com/tebe6502/Mad-Assembler) 2.1.x
(build with FreePascal: `fpc -Mdelphi -vh -O3 mads.pas`), Python 3, GNU
make, `patch`. VICE (`x64sc`) and Node.js (`npx`) for the tests.

```
git clone --recurse-submodules https://github.com/xahmol/u64-bbcbasic
cd u64-bbcbasic
make                # build/u64bbc-tmb.crt, build/u64bbc-ef.crt and .cfg
make compare-core   # BBC BASIC 3.10 still identical to the reference ROM
make vice           # run in VICE
make e2e            # end-to-end tests (tests/e2e/README.md)
```

Put the Ultimates' IP addresses in `.env` (`ULTIP1 = ...`, `ULTIP2 = ...`)
for `make deploy` and the tests.

## Credits and licences

- BBC BASIC © 1982/1983 Acorn Computers and Sophie Wilson.
- Annotated MADS source: Ivo van Poorten,
  [ivop/bbc-basic](https://github.com/ivop/bbc-basic), based on
  J.G. Harston's source reconstruction
  ([mdfs.net](https://mdfs.net/Software/BBCBasic/)). Used as a submodule;
  this project only adds a build target (`src/basic/u64-target.patch`).
- The MOS design follows Ivo van Poorten's
  [Atari port](https://github.com/ivop/atari-bbc-basic).
- Ultimate knowledge: [ultimate-uci-oscar64](https://github.com/xahmol/ultimate-uci-oscar64).
- MOS, tools and tests: Xander Mol, GPL-3.0 (see `LICENSE`). The BBC BASIC
  interpreter itself is not covered by this licence: see
  [NOTICE.md](NOTICE.md).
