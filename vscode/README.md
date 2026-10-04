# U64 BBC BASIC for VS Code

Write BBC BASIC on your PC and run it on an Ultimate 64 / C64 Ultimate
running the [U64 BBC BASIC](https://github.com/xahmol/u64-bbcbasic)
cartridge, over the network.

## Features

- **Run on U64** (Ctrl+F5, or the play button): sends the program and runs
  it; output appears in the "U64 BBC BASIC" output panel while it runs.
- **Run-time errors** are marked on the source line (Problems panel), with
  the BBC error number and message.
- **INPUT**: when the program asks, VS Code asks you.
- **Stop** (Shift+F5) sends ESCAPE.
- **Type a Line** (Ctrl+Alt+Enter): immediate commands such as
  `PRINT A%`, `LIST`, `*CAT`.
- **Get Program from the Machine**, **Show the Screen**, **Check Program**
  (offline: line numbers, line lengths).
- **Syntax highlighting**, keyword **completion** and **hover help**: the
  same reference as `*HELP` on the machine.

## Setup

1. Start the U64 BBC BASIC cartridge on the Ultimate (the `>` prompt must
   be visible).
2. Command palette: **U64 BBC BASIC: Select Machine** and enter the
   Ultimate's IP address (setting `u64bbc.host`; `u64bbc.password` if the
   Ultimate has a network password).
3. Open a `.bas` file and press Ctrl+F5.

Programs are plain text with line numbers, as typed on a BBC Micro:

```
10 FOR I%=1 TO 10
20   PRINT I%, I%*I%
30 NEXT
```

## How it works

The cartridge's MOS keeps a small mailbox in C64 memory; the extension
reads and writes it through the Ultimate's REST API. It tokenises the
program on the PC (byte-for-byte what BBC BASIC itself stores), writes it
to memory and lets BASIC's own LOAD check it. Protocol:
[docs/REMOTE_DEV.md](https://github.com/xahmol/u64-bbcbasic/blob/main/docs/REMOTE_DEV.md).

## Development

```
npm install
npm test                                   # tokeniser vs. the Python reference
U64_HOST=192.168.1.148 npm run test:device # protocol against a machine
U64_HOST=192.168.1.148 npm run test:vscode # inside VS Code, against a machine
npm run package                            # ../build/u64-bbcbasic.vsix
```
