# U64 BBC BASIC -- user manual

BBC BASIC 3.10 for the Ultimate 64 and the C64 Ultimate, as a cartridge.
One file per chapter. The reference sections (the syntax of every
keyword and command) are the machine's own `*HELP` texts, put in by
`tools/genmanual.py` (`make manual`): edit the chapters in `src/` and
`src/help/help.txt`, not the generated files here.

The whole manual as one PDF: [U64_BBC_BASIC_MANUAL.pdf](U64_BBC_BASIC_MANUAL.pdf)
(`make docs`).

| Chapter | Contents |
|---|---|
| [1. Introduction](01_INTRODUCTION.md) | what it is; compared with a BBC Micro; credits |
| [2. Installation](02_INSTALLATION.md) | what you need, the cartridges, `make deploy`, starting |
| [3. Building from source](03_BUILDING.md) | tools, `make`, where things are |
| [4. Starting](04_STARTING.md) | a first program, saving and loading, the keyboard, `*HELP` |
| [5. Typing and editing lines](05_SCREEN_EDITOR.md) | the line editor, history, copy editing, `*EDIT` |
| [6. BASIC](06_BASIC.md) | every keyword, grouped: variables, programs, flow, procedures, errors, numbers, strings, data, text, time, machine code |
| [7. Files](07_FILES.md) | the filing system, `/REU`, directories, channels, REU data |
| [8. Graphics](08_GRAPHICS.md) | screen modes, drawing, VDU codes, colours, palettes, fonts |
| [9. Sound](09_SOUND.md) | SOUND, ENVELOPE, the sound engine, instruments, songs |
| [10. Network](10_NETWORK.md) | `*NET`, `*JSON`, network channels |
| [11. Ultimate commands](11_ULTIMATE.md) | drives, disk images, partitions, clock, speed |
| [12. Memory](12_MEMORY.md) | the memory map, PAGE and HIMEM, the REU map |
| [13. MOS calls](13_MOS_CALLS.md) | entry points, OSBYTE, OSWORD, `*FX` |
| [14. Developing from a PC](14_REMOTE.md) | VS Code, `u64remote.py`, the MCP server, the debugger |
| [15. Limits](15_ERRORS.md) | what this BASIC can and cannot do |

