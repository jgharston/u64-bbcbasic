# 12. Memory

The C64's 64K hold BASIC, the MOS, the screens and your program; the
REU holds what does not fit. This chapter shows where everything is and
how to get more room for programs.

@@help MEMORY *MEMORY PAGE HIMEM LOMEM

## 12.1 Snapshots

@@help *SNAPSHOT

## 12.2 Strings and memory

BBC BASIC never gives string space back while a program runs (there is
no garbage collection, on a BBC Micro neither). A string that grows
beyond the space it had gets new space, and the old space stays used
until the program ends (or `CLEAR`, `RUN`). Long-running programs that
build strings can therefore end with "No room". What helps:

- Give a string its largest length once, at the start: `A$=STRING$(200,"
  "):A$=""`. Later values up to 200 characters reuse that space.
- Avoid growing a string a character at a time in a loop
  (`A$=A$+CHR$C%`) when other strings are made in between; build it in
  memory with `?` and `$` instead (`DIM B% 255`, then `B%?I%=C%` and
  `$B%`).
- Keep large data out of BASIC's memory: in the REU (`*SRWRITE`,
  `*SRREAD`: chapter 7), read back when needed. The demo `U64TEXT` keeps
  its news and blog texts there.
- `PRINT ~(?2+256*?3), ~(?4+256*?5)` shows the end of the variables and
  BASIC's stack: the room between them is what is left.

## 12.3 The REU

| REU address | Used for |
|---|---|
| bank 0, $0000-$17FF | fonts (bitmap modes, text screen, start-up font) |
| bank 0, $1830-$18BF | palettes |
| bank 0, $2000-$30CF | instruments, envelopes |
| bank 0, $3100-$34FF | network channels' buffers |
| bank 0, $3500-$3501 | the line editor's history: head, count |
| bank 0, $4000-$7FFF | HTTP replies (`*NET GET`, `*JSON GET`, http:// channels) |
| bank 0, $8000-$FFFF | the line editor's history (127 lines) |
| banks 1-3 | the song (`*SONG`) |
| &40000-&AFFFF | programs' data (`*SRWRITE`, OSWORD &42) |
| &B0000-&FFFFF | snapshots: working slot 0, slots 1-9 (`*SNAPSHOT`) |
| &100000 up | the RAM disk `/REU` |
