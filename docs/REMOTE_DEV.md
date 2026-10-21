# Remote development: VS Code ↔ U64 BBC BASIC

Write BBC BASIC on a PC and run, test and debug it on the Ultimate 64 /
C64 Ultimate: send a program, run it, see its output, stop it, set
breakpoints, step, and inspect variables. Three clients share one
protocol: the VS Code extension (`vscode/`), the command-line tool
`tools/u64remote.py` (with the tokeniser `tools/bbctok.py`) and the MCP
server `tools/u64mcp.py` for AI agents (docs/AI_AGENTS.md).

## 1. Principles

- **No change to the interpreter.** BBC BASIC stays bit-exact
  (`make compare-core`). Every hook is in the MOS, at points the BBC MOS
  design already provides.
- **Host-driven over the Ultimate's REST API.** The PC reads and writes
  C64 memory (DMA) and presses keys; the MOS only needs a small mailbox.
  No cable and no network code on the C64.

## 2. What the Ultimate's DMA can reach (measured)

REST memory access uses the standard C64 map, not the CPU's current one.
It sees plain RAM `$0000-$7FFF` and `$C000-$CFFF`. At `$8000-$BFFF` it
sees neither BASIC's RAM copy nor the cartridge, and at `$E000` it sees
the KERNAL ROM. So:

- program, variables and BASIC's stacks (`&1D00-&7FFF`, PAGE to HIMEM) and the resident
  MOS page (`$C400-$C7FF`) are reachable;
- the mailbox lives in the resident page;
- while a UCI file transfer runs, an Ultimate 64-II can refuse a REST
  access: the host retries (as the E2E client does).
- every REST access is a DMA that stops the C64's CPU while it runs.
  During serial-bus transfers (`*STATUS`'s drive scan, `*CP`,
  `*PARTITIONS`) the KERNAL's IEC timing breaks: measured, `*CP` took
  0-4 cs without polling and 11 s or more (or hung the test)
  with 238-byte mailbox and 1000-byte screen reads during it. Hosts
  therefore poll only the mailbox header (20 bytes) and read the output
  ring only when it holds new bytes, and only those (`u64remote.py`,
  the VS Code extension). Tests of serial-bus commands use the remote
  interface, not screen polling.

## 3. The two hook points

**The prompt (OSWORD 0).** BASIC reads every immediate-mode line with
OSWORD 0, which the MOS implements. While it waits for keys, the MOS also
polls the mailbox. A line waiting there is returned as if it had been
typed, and echoed on the screen. BASIC is guaranteed to be idle at the
prompt then, so loading a program or running one is always safe.

**TRACE output (OSWRCH).** With `TRACE ON`, BASIC prints `[line]` through
OSWRCH before each line it runs. In debug mode the MOS recognises these
sequences, swallows them, records the current line in the mailbox, and
checks it against a breakpoint table. On a hit (or when single-stepping)
OSWRCH does not return: the MOS waits in a loop for the host's "continue",
"step" or "stop". Meanwhile the host reads variables by DMA. The cost is
one TRACE sequence per line, and only while debugging.

**ESCAPE** stops a running program at any time (the host sets ESCFLG).

**Limitation (BBC BASIC's TRACE):** the line after a FOR or REPEAT is
traced only on the first pass, because NEXT and UNTIL jump back into the
middle of the loop line. Breakpoints on later loop passes go on the
NEXT/UNTIL line or after it. Lines reached in sequence or by GOTO/GOSUB
are always traced.

## 4. Mailbox (resident page, `$C6E0-$C7CD`, 238 bytes)

Protocol version 1; the layout is in `src/mos/defs.s`:

| Offset | Size | Meaning |
|---|---|---|
| 0 | 4 | magic "BBCR" |
| 4 | 1 | protocol version (1) |
| 5 | 1 | host → C64 request sequence number (host increments to post) |
| 6 | 1 | C64 → host: last request handled |
| 7 | 1 | request: 1 line, 3 output capture on/off, 4 program at PAGE |
| 8 | 1 | status: 0 idle, 1 waiting for a line, 2 running |
| 9 | 2 | current line number (debugging) |
| 11 | 1 | debug flags |
| 12 | 1 | output ring write index (C64) |
| 13 | 1 | output ring read index (host) |
| 14 | 1 | output capture on |
| 15 | 1 | line length |
| 16 | 1 | program request pending (`$REMOTE`) |
| 17 | 1 | buffer page while waiting: &07 prompt/AUTO, &06 INPUT |
| 18 | 1 | number of the last error |
| 19 | 1 | error counter (the host compares before/after) |
| 20 | 74 | line text / request data |
| 94 | 16 | breakpoints |
| 110 | 128 | output ring |

Requests are posted by writing the data first and the sequence number
last; the MOS sets status "running" and then copies the sequence number
to offset 6. A program request makes the MOS answer the prompt with
`LOAD "$REMOTE"` (or `CHAIN`): BASIC's own LOAD then checks the program,
sets TOP and clears the variables, and the filing system answers that one
name without reading a file.

**Output capture.** When on, OSWRCH also copies each character into the
ring. If the ring is full, OSWRCH waits until the host has read it
(at most a second, and ESCAPE leaves the wait), so no output is lost;
a host that does not read for a second is taken as gone and capture
goes off. Off by default; costs nothing then. The screen (`$C000`) can
be read as well.

A host switches capture off whenever it stops reading: `u64remote.py`
on every exit (also Ctrl+C and termination), the MCP server after every
call, by writing byte 14 directly (the MOS takes `REQ_CAPTURE` only at
the prompt; the byte works while a program runs too). Otherwise output
on the machine halts for that second the next time the ring fills. The
capture's REST reads also show as lines on screen in
the Upic modes: none while recording a video.

## 5. Operations (extension side)

| Action | How |
|---|---|
| Send program | Tokenise on the PC (the BBC BASIC tokeniser in TypeScript and Python, byte for byte what the interpreter stores), write it to PAGE by DMA, then post the program request: the MOS answers the prompt with `LOAD "$REMOTE"` (or `CHAIN`), so BASIC's own LOAD checks it and sets TOP. |
| Run | post `RUN` (with output capture on) |
| Stop | set ESCFLG (`$FF` = `$80`) |
| Immediate line / REPL | post the line; output via the ring |
| Breakpoints | write the table; post `TRACE ON` and debug flags; RUN |
| Step / continue | debug control request |
| Variables | read `&0400-&047F` (resident integers @%, A%-Z%) and the variable chains from VARPTR (`&0480`) through the heap; decode BBC 5-byte floats, integers and strings on the PC |
| Screen | read `$C000` (as tests/e2e/screen.py does) |
| Files | FTP to the Ultimate, or `*` commands as posted lines |

## 6. The VS Code extension

- **Language:** syntax highlighting, keyword completion and hover help
  from `src/help/help.txt` (the same text as `*HELP`); "Check Program"
  tokenises offline (line numbers, line lengths); "Format Document"
  indents by block nesting (`vscode/src/formatter.ts`), and sending a
  program drops the indentation again unless `u64bbc.keepIndentation`
  (the same rule as `tools/bbctok.py`).
- **Machine:** the Ultimate from the settings (`u64bbc.host`,
  `u64bbc.password`); "Select Machine", "Refresh Machine Status".
- **Run:** "Run on U64" (Ctrl+F5): send, RUN, output panel (the ring);
  run-time errors on the source line (Problems panel); INPUT answered
  from VS Code; "Send Program", "Stop", "Type a Line", "Get Program from
  the Machine", "Show the Screen".
- **Debug (F5):** a Debug Adapter (DAP): line breakpoints, continue,
  step, pause (the host sets the single-step flag; the MOS stops at the
  next traced line), a Variables view (resident integers and the
  program's variables, read from memory: BASIC cannot evaluate
  expressions while it is paused inside OSWRCH), the current line as the
  one stack frame. Stop = ESCAPE.
- **Implementation:** TypeScript, talking to the Ultimate's REST API
  directly (no Python, no MCP needed at run time). c64bridge is the
  tool for the project's own E2E tests.

## 6a. AI coding agents

Everything the extension does is also offered to AI coding agents:
`tools/u64remote.py` prints one JSON object per command (`--json`) with
fixed exit codes, and `tools/u64mcp.py` is an MCP server (stdio) with the
tools `bbc_run`, `bbc_load`, `bbc_exec`, `bbc_input`, `bbc_stop`,
`bbc_status`, `bbc_screen`, `bbc_list`, plus `bbc_check` (tokenise
offline) and `bbc_help` (the *HELP reference offline), and for
debugging `bbc_debug`, `bbc_step`, `bbc_continue`, `bbc_vars` (the same
results as the Debug Adapter) and `bbc_endshow`. Errors come back
structured (number, message, line), so an agent can fix and retry
without reading the screen. Registered for Claude Code in `.mcp.json`.

## 7. Upic shows

While `*UPIC SHOW` shows a picture, BASIC's RAM &0400-&CFFF, the mailbox
included, is in the REU. The MOS sets `$0334` = `$55` meanwhile (before
the swap, cleared after it); `u64remote` then reports the state
`showing` instead of a missing mailbox, and its poll loops wait (once a
second: every memory read stops the CPU for a moment, which in Upic
shows as a disturbed line). `endshow` (MCP: `bbc_endshow`) writes `$AA`
there: the show ends as with a key press and the program goes on;
`stop` ends it with ESCAPE.

The same holds for Upic Lite (MODE 0-2, 4-6 on 64 MHz machines): its
picture is drawn by the CPU too, so every memory read of a host (status
polls, `run` waiting at GET) shows as a disturbed raster line in the
frame. A stray line seen in a frame grab of a Upic Lite screen is that,
not drawing (none in frames taken without polling).
