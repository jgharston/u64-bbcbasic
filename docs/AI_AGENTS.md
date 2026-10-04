# U64 BBC BASIC for AI coding agents

An AI coding agent (Claude Code or any MCP client) can write BBC BASIC,
run it on a real Ultimate 64 / C64 Ultimate, read the output and errors,
answer INPUT, stop a runaway program, and look up the dialect, all
without a person at the keyboard. The same hook serves the planned VS
Code extension (docs/REMOTE_DEV.md).

## Setup

1. The cartridge runs on the Ultimate (`make deploy`, then start
   `u64bbc-tmb.crt`; the `>` prompt must be visible).
2. The machine's address: `U64_HOST=192.168.1.148`, or `ULTIP1` in
   `.env`. With a network password: `ULTIMATE_PASSWORD`.
3. MCP: this repository's `.mcp.json` registers the server
   `tools/u64mcp.py` (Python 3, standard library only). In Claude Code
   it is offered when the repository is opened.

## Tools (MCP server `u64bbc`)

| Tool | Does |
|---|---|
| `bbc_help` | the `*HELP` reference without a machine: keywords, `*` commands, topics (`LIMITS`, `MEMORY`, `FILES`, `ERRORS`, `KEYBOARD`, `MOS`, `VDUCODES`) |
| `bbc_check` | tokenise a program on the PC: line number problems, over-long lines; returns the program as BASIC would LIST it (shows which words became keywords) |
| `bbc_run` | send a program and RUN it |
| `bbc_load` | send a program without running it |
| `bbc_exec` | type lines at the prompt (`PRINT`, `LIST`, `*CAT`, numbered lines) |
| `bbc_input` | answer an `INPUT` |
| `bbc_stop` | ESCAPE |
| `bbc_status` | prompt / input / running, last error |
| `bbc_screen` | the 40x25 text screen |
| `bbc_list` | the program in memory |
| `bbc_debug` | run under the debugger with breakpoints (BASIC line numbers); pauses with `state: "paused"`, `line` |
| `bbc_step` / `bbc_continue` | while paused: one line / to the next breakpoint or the end |
| `bbc_vars` | variables (resident integers, reals, integers, strings; arrays by name) and the current line |

Results are JSON:

```json
{"ok": false, "state": "prompt",
 "output": "LINE 1\nLINE 2\nLINE 3\nDivision by zero at line 40\n",
 "error": {"number": 18, "message": "Division by zero", "line": 40},
 "elapsed_s": 0.15}
```

`state`: `prompt` (finished), `input` (waiting for `INPUT`: use
`bbc_input`), `timeout` (still running: `bbc_stop`, or call again).

## The same from a shell

```
tools/u64remote.py --json run prog.bas      # exit 0 ok, 1 BASIC error,
tools/u64remote.py --json exec "PRINT 6*7"  # 2 time-out, 3 no machine
tools/u64remote.py input "ANSWER"
tools/u64remote.py stop | screen | list | status
```

## Writing BBC BASIC for this machine

Read `bbc_help LIMITS` first. Short version:

- **BBC BASIC 3.10** (1983): no `WHILE`, `CASE`, multi-line `IF`/
  `ENDIF` or `LOCAL` arrays (those are BASIC V). Use `REPEAT`/`UNTIL`,
  single-line `IF ... THEN ... ELSE`, `PROC`/`FN`, `GOSUB`.
- Keywords must be **upper case**; lower case words are variables.
- Integer variables end in `%` and are fast; `A%`-`Z%` and `@%` survive
  `RUN`.
- Text screen only for now: 40 columns, 25 rows. No graphics or sound
  yet (`MODE`, `PLOT`, `SOUND` do nothing useful).
- Files live on the Ultimate's storage (`*DIR /Temp` is a RAM disk);
  two files can be open at once.
- `TIME` counts centiseconds in real time; the CPU runs at 48-64 MHz,
  25-30 times a BBC Micro.
- Lines sent with `bbc_run` may be up to 251 characters; lines typed with
  `bbc_exec` up to 74.

## Debugging approach

1. `bbc_check` the program: catches structure errors offline.
2. `bbc_run` with a `timeout` that fits the program.
3. On an error, the result has the number, message and line. Inspect
   with `bbc_exec` (`PRINT A%`, `LIST 100,120`) while BASIC is at the
   prompt: variables keep their values after an error.
4. `TRACE ON` before `RUN` prints line numbers as they run (in the
   output).
5. A program that never ends: `bbc_stop`, then `bbc_exec ["PRINT ERL"]`
   shows where it was.

6. Breakpoints: `bbc_debug` with `breakpoints: [120]`; at the pause
   `bbc_vars`, then `bbc_step` or `bbc_continue`. BBC BASIC traces the
   line after a FOR or REPEAT only on the first pass: for later loop
   passes put the breakpoint on the NEXT/UNTIL line.
