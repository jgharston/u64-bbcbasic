# u64-bbcbasic

BBC BASIC 3.10 for the Ultimate 64 and C64 Ultimate, as a cartridge, with a
BBC-style MOS (machine operating system) on top of the C64 KERNAL, and
`*` commands for the Ultimate's features.

**Status: in development (0.1.0).** BBC BASIC programs run at the
device's maximum turbo speed: the BBC's screen modes and graphics (Upic
Lite pictures with square pixels on 64 MHz machines, teletext MODE 7),
sound on up to 8 SIDs with instruments and a song player, Ultimate Audio
sample effects and ProTracker MOD music in the background, files on the
Ultimate's drives and an REU RAM disk, network channels, HTTP requests
(GET, POST, PUT, DELETE, headers, status codes) and JSON, a line editor
with history and BBC copy editing, and a built-in help system (`*HELP`). The **user manual** is [docs/manual](docs/manual/README.md);
[docs/PLAN.md](docs/PLAN.md) has the plan and roadmap.

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
turbo registers, and sets up 8 UltiSIDs for sound (as Heartbeat
Soundtracker does: UltiSID 1 at `$D400`, UltiSID 2 at `$D420`, each split
four ways; SIDs in the sockets keep their addresses and play along). The
settings are loaded into memory only, not saved to flash.

## Using it

- Letters type in capitals (BBC CAPS LOCK on); Shift gives lower case;
  Shift+C= switches CAPS LOCK.
- The ASCII characters the C64 keyboard lacks: `\` = £, `^` = ↑, `_` = ←,
  `|` = Shift+£, `~` = Shift+↑, `{` = Shift++, `}` = Shift+-,
  `` ` `` = Shift+@.
- RUN/STOP is ESCAPE.
- Input lines can be up to 238 characters, edited in place, with the
  last 127 lines on the cursor keys and BBC copy editing (`*EDIT C64`
  gives the C64 screen editor back).
- `PAGE` = &1D00 (as a BBC Micro with ADFS), `HIMEM` = &8000: 25.75K for
  programs; &0800-&1CFF holds the sound engine (`*SOUND NONE` frees it).
- MOS entry points: `OSWRCH` = &C7EE, `OSBYTE` = &C7F4, `OSWORD` = &C7F1,
  `OSCLI` = &C7F7, … (BBC low bytes, page &C7). The RAM vectors are at
  &0200, as on the BBC.
- Files on the Ultimate (see `*HELP FILES`): `LOAD`, `SAVE`, `CHAIN`, two
  open channels (`OPENIN`, `OPENOUT`, `OPENUP`, `BGET#`, `BPUT#`, `PRINT#`,
  `INPUT#`, `PTR#`, `EXT#`, `EOF#`).
- Commands: `*CAT` (`*.`), `*DIR` (`*CD`), `*PWD`, `*DELETE`, `*MKDIR`,
  `*RENAME`, `*LOAD`, `*SAVE`, `*TYPE`, `*UVER`, `*TIME`, `*TURBO`,
  `*STATUS` (memory, REU, drives, network, clock), `*FX`, `*HELP`.
- A file browser: `*BROWSE`, or <kbd>F1</kbd> on an empty line at the
  prompt. Folders and drives, RETURN opens by type (CHAINs a program,
  shows a PETSCII or Upic file, plays a MOD or WAV, mounts a disk image),
  T types, D deletes, R renames.
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
make deploy         # install on the Ultimate (below)
```

Put the Ultimates' IP addresses in `.env` (`ULTIP1 = ...`, `ULTIP2 = ...`)
for `make deploy` and the tests, and the drive to install on (`ULTDRV1 =
SD`, `ULTDRV2 = ...`; default `USB0`). `make deploy` puts the cartridges
and their `.cfg` files in `/<drive>/idi8b/u64bbcbasic/`, and the demos,
tokenised as BBC BASIC programs, in its `demos/` folder (`music`, `net`,
`sound`, `classics`): `*DIR /SD/idi8b/u64bbcbasic/demos/music` and
`CHAIN "MUSIC"`, or <kbd>F1</kbd> and pick it in the browser. A second Ultimate is skipped when it does not answer.

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
- The MOD player is ModPlayer_16k by Freshness (6510nl),
  [CSDb release 131522](https://csdb.dk/release/?id=131522), ported to MADS
  (`src/mos/modengine.s`; its tables in `src/mos/modtables/`).
- Upic: Aleksi Eeben's renderer, the 48 MHz path by Christian Gleissner
  (through ultimate-uci-oscar64's Upic module).
- Demos: Eric Schraf's graphics programs (`demos/archbas`); music and
  sound effects in `demos/audio` and the showcase: see
  [demos/audio/CREDITS.md](demos/audio/CREDITS.md).
- MOS, tools and tests: Xander Mol, GPL-3.0 (see `LICENSE`). The BBC BASIC
  interpreter itself is not covered by this licence: see
  [NOTICE.md](NOTICE.md).
