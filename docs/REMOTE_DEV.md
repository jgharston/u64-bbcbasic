# Remote development: VS Code ↔ U64 BBC BASIC

Design, 2026-10-04; phases 1 and 2 implemented and tested the same day
(MOS mailbox, `tools/u64remote.py`, `tools/bbctok.py`, plus the MCP
server `tools/u64mcp.py` for AI agents, see docs/AI_AGENTS.md). Decisions (2026-10-04): the extension lives in this
repository (`vscode/`); build order MOS hook + CLI tool first, then the
extension, then debugging; programs go to PAGE by DMA followed by a MOS
"set TOP" request.

Goal: write BBC BASIC in VS Code on a PC and run, test and debug it on the
Ultimate 64 / C64 Ultimate: send a program, run it, see its output, stop
it, set breakpoints, step, and inspect variables.

## 1. Principles

- **No change to the interpreter.** BBC BASIC stays bit-exact
  (`make compare-core`). Every hook is in the MOS, at points the BBC MOS
  design already provides.
- **Host-driven over the Ultimate's REST API.** The PC reads and writes
  C64 memory (DMA) and presses keys; the MOS only needs a small mailbox.
  No cable, no network code on the C64 for the first transport.
- **Same protocol for every transport**, so a TCP transport (Ultimate II+,
  later the C128) can be added without changing the extension's logic.

## 2. What the Ultimate's DMA can reach (measured 2026-10-04)

REST memory access uses the standard C64 map, not the CPU's current one.
It sees plain RAM `$0000-$7FFF` and `$C000-$CFFF`. At `$8000-$BFFF` it
sees neither BASIC's RAM copy nor the cartridge, and at `$E000` it sees
the KERNAL ROM. So:

- program, variables and BASIC's stacks (`&0800-&7FFF`) and the resident
  MOS page (`$C400-$C7FF`) are reachable;
- the mailbox lives in the resident page;
- while a UCI file transfer runs, an Ultimate 64-II can refuse a REST
  access: the host retries (as the E2E client does).
- every REST access is a DMA that stops the C64's CPU while it runs.
  During serial-bus transfers (`*STATUS`'s drive scan, `*CP`,
  `*PARTITIONS`) the KERNAL's IEC timing breaks: measured 2026-10-07,
  `*CP` took 0-4 cs without polling and 11 s or more (or hung the test)
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

**ESCAPE** stops a running program at any time (the host sets ESCFLG, as
the E2E suite already does).

## 4. Mailbox (resident page, `$C6E0-$C7CD`, 238 bytes)

Implemented (protocol version 1); the layout is in `src/mos/defs.s`:

| Offset | Size | Meaning |
|---|---|---|
| 0 | 4 | magic "BBCR" |
| 4 | 1 | protocol version (1) |
| 5 | 1 | host → C64 request sequence number (host increments to post) |
| 6 | 1 | C64 → host: last request handled |
| 7 | 1 | request: 1 line, 3 output capture on/off, 4 program at PAGE |
| 8 | 1 | status: 0 idle, 1 waiting for a line, 2 running |
| 9 | 2 | current line number (debug, phase 4) |
| 11 | 1 | debug flags (phase 4) |
| 12 | 1 | output ring write index (C64) |
| 13 | 1 | output ring read index (host) |
| 14 | 1 | output capture on |
| 15 | 1 | line length |
| 16 | 1 | program request pending (`$REMOTE`) |
| 17 | 1 | buffer page while waiting: &07 prompt/AUTO, &06 INPUT |
| 18 | 1 | number of the last error |
| 19 | 1 | error counter (the host compares before/after) |
| 20 | 74 | line text / request data |
| 94 | 16 | breakpoints (phase 4) |
| 110 | 128 | output ring |

Requests are posted by writing the data first and the sequence number
last; the MOS sets status "running" and then copies the sequence number
to offset 6. A program request makes the MOS answer the prompt with
`LOAD "$REMOTE"` (or `CHAIN`): BASIC's own LOAD then checks the program,
sets TOP and clears the variables, and the filing system answers that one
name without reading a file.

**Output capture.** When on, OSWRCH also copies each character into the
ring. If the ring is full, OSWRCH waits until the host has read it
(bounded, and ESCAPE leaves the wait), so no output is lost. Off by
default; costs nothing then. The screen (`$C000`) can be read as well.

## 5. Operations (extension side)

| Action | How |
|---|---|
| Send program | Tokenise on the PC (BBC BASIC tokeniser in TypeScript, checked against the interpreter's token table), write it to PAGE (`&0800`) by DMA, then post the line `END`. END runs at the prompt and recomputes TOP, as in Ivo van Poorten's Atari port. Alternatively: upload to `/Temp` by FTP and post `CHAIN "/Temp/prog"`. |
| Run | post `RUN` (with output capture on) |
| Stop | set ESCFLG (`$FF` = `$80`) |
| Immediate line / REPL | post the line; output via the ring |
| Breakpoints | write the table; post `TRACE ON` and debug flags; RUN |
| Step / continue | debug control request |
| Variables | read `&0400-&047F` (resident integers @%, A%-Z%) and the variable chains from VARPTR (`&0480`) through the heap; decode BBC 5-byte floats, integers and strings on the PC |
| Call stack | BASIC's own stack below HIMEM (PROC/FN frames, GOSUB and FOR stacks at `&0500-&05FF`) |
| Screen | read `$C000` (as tests/e2e/screen.py does) |
| Files | FTP to the Ultimate, or `*` commands as posted lines |

## 6. The VS Code extension

- **Language:** syntax highlighting, keyword completion and hover help
  from `src/help/help.txt` (the same text as `*HELP`), line numbering,
  RENUMBER and tokenise as commands.
- **Devices:** the Ultimates from settings (IP addresses, password);
  status bar shows the connected machine and its firmware.
- **Run:** "Run on U64" (F5 without debugging): send, RUN, output panel
  (ring buffer) and an optional screen mirror.
- **Debug:** a Debug Adapter (DAP): line breakpoints, continue, step,
  pause (the host sets the single-step flag; the MOS stops at the next
  traced line), variables view, watches of variables and array elements
  (read from memory: BASIC cannot evaluate expressions while it is paused
  inside OSWRCH), call stack from BASIC's stacks. Stop = ESCAPE.
- **Test:** run a program and compare its captured output with a
  golden file: the same approach as tests/e2e, usable for the user's own
  programs.
- **Implementation:** TypeScript, talking to the Ultimate's REST API
  directly (no Python, no MCP needed at run time). c64bridge stays the
  tool for the project's own E2E tests and for Claude.

## 6a. AI coding agents

Everything the extension does is also offered to AI coding agents:
`tools/u64remote.py` prints one JSON object per command (`--json`) with
fixed exit codes, and `tools/u64mcp.py` is an MCP server (stdio) with the
tools `bbc_run`, `bbc_load`, `bbc_exec`, `bbc_input`, `bbc_stop`,
`bbc_status`, `bbc_screen`, `bbc_list`, plus `bbc_check` (tokenise
offline) and `bbc_help` (the *HELP reference offline). Errors come back
structured (number, message, line), so an agent can fix and retry
without reading the screen. Registered for Claude Code in `.mcp.json`.
The debugger phase adds `bbc_break`, `bbc_step`, `bbc_vars` with the
same results as the Debug Adapter.

## 7. Transport B (later): TCP through the UCI network target

For machines without a REST API at hand (Ultimate II+ in a C64 or C128),
the MOS connects as a TCP client to the extension (`*REMOTE host:port`,
UCI network target, firmware 3.15+) and exchanges the same mailbox
records over the socket. The released firmware has no TCP listener for
the C64 side, so the C64 connects out.

## 8. Phases

1. MOS: mailbox, prompt hook (posted lines), output ring. E2E tests via
   c64bridge (post a line, read the ring). **Done.**
2. PC side: tokeniser plus "send and run" as a Python tool
   (`tools/u64remote.py`), proving the protocol from the command line;
   MCP server for AI agents. **Done.**
3. VS Code extension: language features, run, output panel. **Done**
   (`vscode/`, `make vscode`): highlighting, completion and hover help
   from `*HELP`, run/send/stop/type line/INPUT/get program/screen,
   run-time errors in the Problems panel. Tested offline (TypeScript
   tokeniser = Python tokeniser), against the machine (protocol) and
   inside VS Code with @vscode/test-electron (`make vscode-test`).
4. MOS: TRACE hook with breakpoints and stepping; extension: Debug
   Adapter with variables and call stack. **Done** (without call stack):
   `dbg_filter`/`dbg_line` in `src/mos/mos.s`, `debug`/`continue`/`step`/
   `vars` in `tools/u64remote.py`, `bbc_debug`/`bbc_continue`/
   `bbc_step`/`bbc_vars` for agents, F5 debugging in VS Code
   (`vscode/src/debugAdapter.ts`). Tested in E2E (`remote_debug`) and
   inside VS Code.

   **Limitation (BBC BASIC's TRACE):** the line after a FOR or REPEAT
   is traced only on the first pass, because NEXT and UNTIL jump back
   into the middle of the loop line. Breakpoints on later loop passes go
   on the NEXT/UNTIL line or after it. Lines reached in sequence or by
   GOTO/GOSUB are always traced.
5. TCP transport.

## 9. Open questions

- Where the extension lives: this repository (`vscode/`) or its own.
- Tokeniser for the extension: port `tools/bbctok.py` (itself a port of
  the interpreter's MATCH routine, verified byte-for-byte by the E2E test
  `remote_tokeniser`) to TypeScript, or run the Python one.
