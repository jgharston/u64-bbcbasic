# Ultimate firmware 3.15a functions in U64 BBC BASIC

Goal (owner, 2026-10-07): every function firmware 3.15a offers through the
command interface (UCI) is usable from BBC BASIC. The list of commands is
the one in ultimate-uci-oscar64's manual, section 17 (checked against the
v3.15a sources). Interface rule: BBC style. Files and streams go through
the filing system (OPENIN/BGET#/...), actions are `*` commands, data for
programs uses OSWORD (`&E0` upwards) or `*` commands with addresses.

Status: **done**, **next** (batch), or a later batch letter.

## DOS target (files, drives, REU, clock)

| Command | Function | BASIC | Status |
|---|---|---|---|
| `0x01` | identify | `*UVER` | done |
| `0x02`-`0x05` | open/close/read/write | OPENIN/OPENOUT/OPENUP, BGET#, BPUT#, PRINT#, INPUT#, CLOSE#, LOAD, SAVE, `*LOAD`, `*SAVE`, `*TYPE` | done |
| `0x06`-`0x08` | seek, info, stat | PTR#= , EXT#, OSFILE 5 | done |
| `0x09`, `0x0A` | delete, rename | `*DELETE`, `*RENAME` | done |
| `0x0B` | copy (into a directory, same name, no overwrite) | `*COPY <file> <directory>` | done |
| `0x11`, `0x12` | change dir, get path | `*DIR`/`*CD`, `*PWD` | done |
| `0x13`/`0x14` | directory | `*CAT` / `*.` | done |
| `0x16` | create dir | `*MKDIR`/`*CDIR` | done |
| `0x17` | home dir | `*DIR ~` | done |
| `0x21`/`0x22` | REU load/save (at address) | `*REULOAD <file> [<reu address>]`, `*REUSAVE <file> <reu address> <length>` | B |
| `0x23`-`0x25` | mount, unmount, swap (next disk of a drive's disk set) | `*MOUNT <image> [A|B]`, `*UNMOUNT [A|B]`, `*SWAP [A|B]` | done |
| `0x26`/`0x27` | get/set time | `*TIME`, `*SETTIME yyyy/mm/dd hh:mm:ss`; OSWORD 14 (BBC "read clock string") | done |
| `0x41`/`0x42` | GEOS RAM disk load/save | `*RAMDISK LOAD/SAVE <file> <id>` | E |
| `0xF0` | echo | used by `*UTEST` (diagnostics) | E |

## Control target (machine)

| Command | Function | BASIC | Status |
|---|---|---|---|
| `0x01` | identify | `*UVER` | done |
| `0x03` | finish capture (tape) | `*CAPTURE END` | E |
| `0x05` | freeze (Ultimate menu) | `*MENU` | C |
| `0x06` | reboot | `*REBOOT` (asks for confirmation) | C |
| `0x08`/`0x09` | REU preload image load/save | `*REUPRELOAD LOAD/SAVE` | B |
| `0x0F` | save C64 memory (U64) | `*SAVEMEM <file>` | C |
| `0x11` | decode track | OSWORD for disk tools | E |
| `0x20` | EasyFlash erase | not offered (it would erase this cartridge's own flash image in EasyFlash mode) | - |
| `0x28` | hardware info | `*STATUS` (product); SID configuration in `*STATUS SID` | product done, SID C |
| `0x29` | drive info | `*STATUS`, `*DRIVES` | done (with the 3.15a workaround) |
| `0x30`-`0x35` | drive A/B on/off, power state | `*DRIVE A|B ON|OFF` | done |
| `0x40` | RAM disk info | `*RAMDISK` | E |
| `0x50` | load config | `*CONFIG <file>` (and the start-up check in PLAN.md section 13) | C |
| `0x51`-`0x54` | palette get/set/colour/reset | `VDU 19,l,16,r,g,b` (BBC RGB palette call), `*PALETTE RESET/SAVE/LOAD` | with graphics (D) |

## SoftIEC target (firmware 3.15+)

| Command | Function | BASIC | Status |
|---|---|---|---|
| `0x01` | identify | `*STATUS` (presence) | done |
| `0x20` | add partition | `*PARTITION <n> <path>`: needed to reach anything outside `/Temp` from the SoftIEC drive (owner note 2026-10-07) | done |
| `0x21` | delete partition | `*PARTITION <n> OFF` (ineffective on 3.15a hardware: documented) | done |
| `0x10`-`0x16` | load/save/open/close/read/write through SoftIEC | an IEC-compatible filing system on the SoftIEC drive: `*FS IEC` | E |
| `0x22`/`0x23` | FAT name <-> IEC name | used by `*FS IEC` and `*CAT` of SoftIEC partitions | E |
| (DOS `CP`, `$=P`) | select / list partitions | `*PARTITIONS`, `*CP <n>` over the serial bus | done |

## Network target

| Command | Function | BASIC | Status |
|---|---|---|---|
| `0x01`, `0x02` | identify, interface count | `*NET` | done (IP in `*STATUS`), rest F |
| `0x04`-`0x06` | MAC, IP (get/set) | `*NET`, `*NET IP <a.b.c.d> <mask> <gateway>` | F |
| `0x07`/`0x08` | TCP/UDP connect | `c=OPENUP "TCP:host:port"` / `"UDP:host:port"`: a channel | F |
| `0x09`-`0x11` | close/read/write | CLOSE#, BGET#, BPUT#, EOF#, PRINT#, INPUT# on such a channel | F |

## HTTP target (22 commands, firmware 3.15+)

| Commands | Function | BASIC | Status |
|---|---|---|---|
| `0x01`, `0x10`-`0x15`, `0x21`-`0x2E`, `0x31`, `0x32` | requests (GET/POST/...), headers, body, status, streaming | `c=OPENIN "HTTP://host/path"` streams a GET; `*HTTPGET <url> <file>` saves to a file; OSWORD for methods, headers and status codes | G |

## U64 hardware (not UCI)

| Function | BASIC | Status |
|---|---|---|
| turbo registers | `*TURBO`, start at maximum | done |
| REU (DMA) | REU detection done; `*REU` block moves, OSWORD `&E0`, RAM disk | B |
| Ultimate Audio (sampler) | SOUND channels 4-10, `*SAMPLE`, `*MODPLAY` | with sound |
| Upic display | MODE / `*UPIC` (docs/DESIGN_GRAPHICS.md section 5) | with graphics |

## Batches

| Batch | Contents | Why |
|---|---|---|
| A (done 2026-10-07) | drives and storage: `*MOUNT`, `*UNMOUNT`, `*SWAP`, `*DRIVE A|B ON|OFF`, `*COPY`, home dir, `*SETTIME`, OSWORD 14, SoftIEC partitions | daily use; partitions unlock the SoftIEC drive beyond /Temp |
| B | REU: `*REULOAD`/`*REUSAVE`, preload, block moves, OSWORD `&E0` | needed by graphics and the RAM disk |
| C | machine: `*MENU`, `*REBOOT`, `*SAVEMEM`, `*CONFIG`, SID info | small |
| D | palette (with graphics) | |
| E | niche: tape capture, GEOS RAM disk, track decode, echo, SoftIEC filing system | completeness |
| F | network: `*NET`, TCP/UDP channels | |
| G | HTTP | |

Every new command gets a `*HELP` entry (the build checks this), an E2E
test, and, if it uses a library function marked `[UNTESTED]`, a report back
to ultimate-uci-oscar64's manual section 20.
