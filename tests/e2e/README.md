# End-to-end tests

`make e2e` runs the cartridge on every target and checks real BBC BASIC
behaviour on screen, all through
[c64bridge](https://github.com/chrisgleissner/c64bridge) (MCP over stdio,
started with `npx -y c64bridge@latest`). Python 3 standard library only.

| Target | Cartridge | How |
|---|---|---|
| `vice` | EasyFlash (`u64bbc-ef.crt`) | x64sc started here with `-binarymonitor` on port 6510; c64bridge (`C64_MODE=vice`) attaches to it |
| `<ULTIP1>-tmb`, `-ef` | both | uploaded to `/Temp` over FTP, started with c64bridge `run_crt` (`C64_MODE=c64u`, `C64U_HOST`) |
| `<ULTIP2>-tmb`, `-ef` | both | same |

The devices come from `.env` (`ULTIP1`, `ULTIP2`). With a network password,
set `ULTIMATE_PASSWORD`.

```
make e2e                 # all targets (also checks the .cfg on both devices)
make e2e-vice            # VICE only
make e2e-u64             # Ultimates only
tests/e2e/run_e2e.py --device 192.168.1.148 --kind tmb --only time speed
```

## How a test works

Each test clears the screen (`CLS`), types a line and waits for the
expected text. Keys go into the KERNAL keyboard buffer (`$0277`, `$C6`),
at most 10 at a time, encoded the way the MOS decodes them (`screen.py`).
The screen is read from `$C000` and decoded with the MOS's character set.
On a failure the screen is saved as `build/e2e/<target>/<test>.txt`.

RUN/STOP is a real key tap (c64bridge `keyboard`, Ultimate firmware 3.15+).
VICE has no keyboard-matrix input through c64bridge, so there the test sets
ESCFLG directly and notes it.

## Tests

| Test | Checks |
|---|---|
| boot | banner, prompt, CPU speed line (`CPU 1 MHz` in VICE) |
| basic_ram | BASIC's RAM copy at `&8000-&BFFF` matches `basic.rom` (checksum computed by BASIC itself; the Ultimate's DMA read does not see the CPU's memory map) |
| arith, hex | `PRINT 1+1`, `PRINT ~255` |
| ascii | the eight ASCII characters the C64 lacks, typed and printed |
| program | entering, RUN and LIST of a program line |
| error | an error raised by BASIC (`Division by zero`) |
| mos_error | an error raised in the MOS bank (`Bad command`): the copy to RAM |
| help | `*HELP` |
| bad_number | `*FX 300` gives `Bad number` |
| vdu_overflow | `*FX 218,200` (VDU queue count 200) cannot overrun the 9-byte parameter buffer |
| fx_escape | `*FX 125` sets ESCAPE inside a program; BASIC reports it and recovers |
| stop_key | RUN/STOP stops `10 GOTO 10` |
| time | TIME advances 80-115 per second of wall-clock time (real time at turbo speed) |
| inkey | `INKEY(50)` times out with -1 |
| get | `GET` returns the ASCII code of a typed key |
| long_line | a 77-character input line (wrapped logical line) |
| speed | 5000 empty FOR loops, reported as a note (VICE 1 MHz ~183 cs, U64 turbo 3-4 cs) |
