# 12. Memory

The C64's 64K hold BASIC, the MOS, the screens and your program; the
REU holds what does not fit. This chapter shows where everything is and
how to get more room for programs.

@@help MEMORY *MEMORY PAGE HIMEM LOMEM

## 12.1 The REU

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
| &40000 up | programs' data (`*SRWRITE`, OSWORD &42) |
| &100000 up | the RAM disk `/REU` |
