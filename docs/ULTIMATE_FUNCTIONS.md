# Ultimate firmware 3.15a functions in U64 BBC BASIC

What firmware 3.15a offers through the command interface (UCI), and how
BBC BASIC reaches it. The list of commands is the one in
ultimate-uci-oscar64's manual, section 17 (checked against the v3.15a
sources). Interface rule: BBC style. Files and streams go through the
filing system (OPENIN/BGET#/...), actions are `*` commands, data for
programs uses OSWORD or `*` commands with addresses.

Status: **yes**, or **not in 1.0.0** (the niche functions: tape capture,
the GEOS RAM disk, track decoding, the SoftIEC filing system).

## DOS target (files, drives, REU, clock)

| Command | Function | BASIC | Status |
|---|---|---|---|
| `0x01` | identify | `*UVER` | yes |
| `0x02`-`0x05` | open/close/read/write | OPENIN/OPENOUT/OPENUP, BGET#, BPUT#, PRINT#, INPUT#, CLOSE#, LOAD, SAVE, `*LOAD`, `*SAVE`, `*TYPE` | yes |
| `0x06`-`0x08` | seek, info, stat | PTR#= , EXT#, OSFILE 5 | yes |
| `0x09`, `0x0A` | delete, rename | `*DELETE`, `*RENAME` | yes |
| `0x0B` | copy (into a directory, same name, no overwrite) | `*COPY <file> <directory>` | yes |
| `0x11`, `0x12` | change dir, get path | `*DIR`/`*CD`, `*PWD` | yes |
| `0x13`/`0x14` | directory | `*CAT` / `*.` | yes |
| `0x16` | create dir | `*MKDIR`/`*CDIR` | yes |
| `0x17` | home dir | `*DIR ~` | yes |
| `0x21`/`0x22` | REU load/save (at address) | `*REULOAD <file> [<reu address>]`, `*REUSAVE <file> <reu address> <length>` (program area &40000-&8FFFF) | yes |
| `0x23`-`0x25` | mount, unmount, swap (next disk of a drive's disk set) | `*MOUNT <image> [A|B]`, `*UNMOUNT [A|B]`, `*SWAP [A|B]` | yes |
| `0x26`/`0x27` | get/set time | `*TIME`, `*SETTIME yyyy/mm/dd hh:mm:ss`; OSWORD 14 (BBC "read clock string") | yes |
| `0x41`/`0x42` | GEOS RAM disk load/save | `*RAMDISK LOAD/SAVE <file> <id>` | not in 1.0.0 |
| `0xF0` | echo | used by `*UTEST` (diagnostics) | not in 1.0.0 |

## Control target (machine)

| Command | Function | BASIC | Status |
|---|---|---|---|
| `0x01` | identify | `*UVER` | yes |
| `0x03` | finish capture (tape) | `*CAPTURE END` | not in 1.0.0 |
| `0x05` | freeze (Ultimate menu) | `*MENU` | yes (not in the E2E suite: it stops the machine) |
| `0x06` | reboot | `*REBOOT [Y]` (asks for confirmation) | yes (the "N" answer tested) |
| `0x08`/`0x09` | REU preload image load/save | `*REU SAVE`, `*REU LOAD [Y]` (keeping the RAM disk over a power-off; LOAD asks) | yes |
| `0x0F` | save C64 memory (U64) | `*SAVEMEM <file>` | yes (an existing file is deleted first: the firmware answers "file exists") |
| `0x11` | decode track | OSWORD for disk tools | not in 1.0.0 |
| `0x20` | EasyFlash erase | not offered (it would erase this cartridge's own flash image in EasyFlash mode) | - |
| `0x28` | hardware info | `*STATUS` (product); SID configuration in `*STATUS SID` | yes |
| `0x29` | drive info | `*STATUS`, `*DRIVES` | yes (with the 3.15a workaround) |
| `0x30`-`0x35` | drive A/B on/off, power state | `*DRIVE A|B ON|OFF` | yes |
| `0x40` | RAM disk info | `*RAMDISK` | not in 1.0.0 |
| `0x50` | load config | `*CONFIG <file>`, `*SETUP` and the start-up check (built-in settings via /Temp/uci_config.cfg) | yes (the first command right after the cartridge starts can go unanswered: the start-up tries twice) |
| `0x51`-`0x54` | palette get/set/colour/reset | `VDU 19,l,16,r,g,b` (BBC RGB palette call), `*PALETTE RESET/SAVE/LOAD` | yes |

## SoftIEC target (firmware 3.15+)

| Command | Function | BASIC | Status |
|---|---|---|---|
| `0x01` | identify | `*STATUS` (presence) | yes |
| `0x20` | add partition | `*PARTITION <n> <path>`: needed to reach anything outside `/Temp` from the SoftIEC drive  | yes |
| `0x21` | delete partition | `*PARTITION <n> OFF` (ineffective on 3.15a hardware: documented) | yes |
| `0x10`-`0x16` | load/save/open/close/read/write through SoftIEC | an IEC-compatible filing system on the SoftIEC drive: `*FS IEC` | not in 1.0.0 |
| `0x22`/`0x23` | FAT name <-> IEC name | used by `*FS IEC` and `*CAT` of SoftIEC partitions | not in 1.0.0 |
| (DOS `CP`, `$=P`) | select / list partitions | `*PARTITIONS`, `*CP <n>` over the serial bus | yes |

## Network target

| Command | Function | BASIC | Status |
|---|---|---|---|
| `0x01`, `0x02` | identify, interface count | `*NET` | identify: yes (IP in `*STATUS`); interface count: not in 1.0.0 |
| `0x04`-`0x06` | MAC, IP (get/set) | `*NET` shows IP, netmask, gateway | IP get and MAC: yes (`*NET`); IP set: not in 1.0.0 |
| `0x07`/`0x08` | TCP/UDP connect | `c=OPENUP "TCP:host:port"` / `"UDP:host:port"`: a channel | yes |
| `0x09`-`0x11` | close/read/write | CLOSE#, BGET#, BPUT#, EOF#, PRINT#, INPUT# on such a channel | yes |

## HTTP target (22 commands, firmware 3.15+)

| Commands | Function | BASIC | Status |
|---|---|---|---|
| `0x01`, `0x10`-`0x15`, `0x21`-`0x2E`, `0x31`, `0x32` | requests (GET/POST/...), headers, body, status, streaming | `*JSON GET`, queries (OSWORD &70), `*JSON NEW/SET/POST` through the HTTP target; `*NET GET/POST/PUT/DELETE`, `*NET HEADER` and `OPENIN "http://..."` through the MOS's own HTTP/1.0 client over TCP (the raw exchange gives no status: DESIGN_NETWORK.md 10); status codes as error 223 and OSBYTE &65 | yes |

## U64 hardware (not UCI)

| Function | BASIC | Status |
|---|---|---|
| turbo registers | `*TURBO`, start at maximum | yes |
| REU (DMA) | REU detection, `*SRWRITE`/`*SRREAD`/OSWORD `&42` block moves, RAM disk, `*REULOAD`/`*REUSAVE`, preload image | yes |
| Ultimate Audio (sampler) | SOUND voices 24-30, `*SAMPLE LOAD`/`CLEAR`, `*MODPLAY`/`*MODSTOP` (ModPlayer_16k ported) | yes (control bit 2 is the channel's interrupt, measured) |
| Upic display | MODE / `*UPIC` (docs/DESIGN_GRAPHICS.md section 5) | yes |

## Adding a command

Every new command gets a `*HELP` entry (the build checks this), an E2E
test, and, if it uses a library function marked `[UNTESTED]`, a report back
to ultimate-uci-oscar64's manual section 20.
