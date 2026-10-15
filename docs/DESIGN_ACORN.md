# Acorn compatibility (design notes)

The owner's decisions (2026-10-14) are in `docs/PLAN.md` ("Acorn
compatibility decisions"). This file describes how they are built.

## 1. Keys, analogue channels, *FX (`src/mos/acorn.s`, bank 7)

### State

The state takes the KERNAL's RS-232 variables at `$0293-$029E`. The MOS
never opens device 2, and the KERNAL uses these bytes only while that
device is open. RAMTAS clears them at the cold start, so every default
is 0. Page 2 (`$02A7-$02FF`) and the cassette-buffer variables (up to
`$03FC`) are full.

| Address | Name | Contents |
|---|---|---|
| `$0293` | `ac_ports` | port modes: bits 0-1 port 1, 2-3 port 2 (0 joystick, 1 paddles, 2 mouse) |
| `$0294` | `ac_fx4` | *FX 4 (kept) |
| `$0295` | `ac_fx200` | *FX 200 |
| `$0296` | `ac_fx220` | the escape character EOR 27 (0 = 27) |
| `$0297-$029A` | `ac_mpot` | mouse: the last POT x, y per port |
| `$029B-$029E` | `ac_mpos` | mouse: position x, y 0-255 per port |

### INKEY(-n)

- OSBYTE &81 with Y = &FF sends key scans to `ac_scan`.
- X = 0 (INKEY(-256)) returns X = &FF, Y = 0, which BASIC reads as 255
  (BBC B with OS 1.2).
- Otherwise X EOR &FF is the BBC's internal key number. `ac_keytab`
  turns it into a C64 matrix position (column * 8 + row). Bit 6 of the
  entry means Shift must be held, bit 7 means it must not be: the C64
  shares one key between two BBC codes for the cursor keys and f2, f4,
  f6, f8. &FF means the C64 has no such key.
- The matrix is read with interrupts off, because the KERNAL scans it in
  its interrupt. SHIFT (key 0) is either Shift key.
- A held key returns X = Y = &FF, so BASIC gives TRUE.

### ADVAL

- OSBYTE &80 sends X = 0-4 and &FF to `ac_adval`.
- BBC joystick 1 is control port 2 (channels 1 and 2), the usual C64
  game port. Joystick 2 is port 1 (channels 3 and 4).
- Values run from 0 to &FFF0; high is left or up.
- **Joystick**: &FFF0, &8000 or 0 per axis.
- **Paddles**: the port is chosen with CIA 1 PA6/PA7. The SID needs 512
  cycles at 1 MHz to sample, so the code waits nine raster lines with
  interrupts off; the KERNAL's scan would otherwise change PA6/PA7. The
  channel gives 255 - POT in its high byte.
- **1351 mouse**: proportional mode. The POT lines count the position
  modulo 64 in bits 1-6. Each read adds the signed change to a 0-255
  position, which starts in the middle when `*ADVAL MOUSE` selects the
  port. More than 31 counts between two reads come out the wrong way.
  This mode is untested with a real mouse; the E2E test only checks that
  an empty port stays in the middle.
- **ADVAL(0)**: the fire buttons (bit 0 joystick 1, bit 1 joystick 2;
  for paddles, either paddle's button). Y = 4.
- **ADVAL(-1)**: the keys in the keyboard buffer.

### OSBYTEs

| Call | Effect |
|---|---|
| &04 | The value is kept. GET and INKEY always return 136-139, as *FX 4,1 would; the line editor keeps the cursor keys. |
| &0B / &0C | The KERNAL's repeat flag `$028A`: 0 for &0B turns repeat off (`$40`); 0 for &0C restores the default (0: cursor keys, space and DEL repeat); other values make every key repeat (`$80`). The KERNAL's delay and speed are constants in ROM, so they can't be changed. |
| &13 | Waits until the raster reaches the bottom border (line 256 on), first leaving it if already there. |
| &A3 | Accepted (the GXR's 242 calls). |
| &C8 | Bit 0 turns ESCAPE off: bit 1 of `escdis`, which the interrupt checks. *FX 229 now uses bit 0 of the same byte. |
| &DC | `key_get` (keys.s) checks every typed key: if its ASCII equals the escape character (other than 27), ESCAPE is set and the key is dropped. |

### Entry points

BBC programs that `CALL &FFF4` (or other `&FFxx` entries) don't work.
The C64's KERNAL ROM sits there; the MOS entries are at `&C7xx` (see
*HELP MOS).

## 2. DFS commands (`src/mos/dfs.s`, bank 7; `*ACCESS` in bank 2)

### State

The C64 BASIC input buffer after the BBC vectors, `$0220-$0258`, is free
RAM: neither the KERNAL nor BBC BASIC uses it.

| Address | Contents |
|---|---|
| `$0220` | `DF_EXEC`: the `*EXEC` channel |
| `$0221` | `DF_EXCR`: the last byte was CR |
| `$0222` | `DF_SPCH`: the `*SPOOL` channel |
| `$0223` | `DF_SPLEN`: bytes spooled (2) |
| `$0225` | `DF_SPBANK`: the REU bank spooled into |
| `$0226` | `DF_BYTE`: a byte for REU transfers |
| `$0228-$023C` | `DF_STUB`: `*SPOOL`'s WRCHV stub |
| `$0240-$0258` | scratch, shared with the toolkit |

The MOS clears `DF_EXEC` and `DF_SPCH` at every start (WRCHV is set
again then).

### Commands

- **\*SPOOL** never writes the file from inside OSWRCH. MOS commands
  print while a UCI transfer or the filing system's variables are in
  use, and a nested `BPUT#` would break them.
  - A 21-byte stub on WRCHV (`farcall sp_put`, then `mos_wrch`) puts
    each byte into the REU's last bank, up to 65535 bytes.
  - `*SPOOL` alone, another `*SPOOL` or `CLOSE#0` (`fs.s` calls
    `dfs_closeall` first) writes the bytes with `OSBPUT` and closes the
    file.
  - The file is opened when the spool starts, so a bad name fails at
    once.
  - The RAM disk now ends below the REU's last 64K (`rd_lastbank`).
    `*SPOOL` refuses if the RAM disk already has data in that bank
    (`rd_spoolok`).
- **\*EXEC**: `key_avail` reports a key while `DF_EXEC` is set, and
  `key_get` reads the file through `ex_get`. LF counts as CR, except
  right after a CR. At the end the file is closed. ESCAPE
  (`by_ackesc` → `bae_exec`) closes it too, as on the BBC.
- **\*BUILD** reads lines with OSWORD 0 into &0700 (the command was read
  from there already, and each line ends in CR) and writes them with
  `OSBPUT`. Its OSWORD block is not in `DF_T`: `DF_T+4` holds the
  channel.
- **\*DUMP** shows 8 bytes a line with the offset; ESCAPE stops.
- **\*INFO** uses OSFILE 5. Attribute bit 3 (locked) is at +14, set by
  `rf_info` for /REU.
- **\*ACCESS** works only on /REU, as bit 1 of an entry's "used" byte.
  `rd_delent` (delete, replace on save, OPENOUT) and `rd_rename` raise
  error 195 "Locked". The Ultimate's DOS can read attributes (FILE_STAT)
  but cannot set them, so files on its drives raise an error.
- **\*RUN**: a file with a load address (OSFILE 5: `*SAVE` on /REU now
  records load = start and exec = start, or the address given after the
  end) is loaded there and called at its exec address. Any other file is
  a C64 program file: its first two bytes are the load address. Both
  load only into &0400-&7FFF.

## 3. The BASIC toolkit (`src/mos/toolkit.s`, bank 7)

The commands follow Beebug's Toolkit Plus manual (scanned at 8bs.com,
"Beebug Toolkit Plus").

- **\*SEARCH**, **\*FIND**, **\*REPLACE**
  - The line is scanned with its state: quotes, REM, DATA, `*`.
  - Line-number constants (`&8D` and 3 bytes) are skipped.
  - K turns a string that spells a keyword into its token; the
    keywords come from `list_tokens.s`.
  - Matching lines are printed by `*LIST`'s printer (`ls_one`, bank 2).
    It spells keywords out through `fsPTR`, so `tk_show` saves the line
    pointer around it.
  - A replacement moves the rest of the program (`tk_shift`) and TOP
    with it; at the end `SETFSA` clears the variables.
- **\*XREF**, **\*VARLIST**
  - The variables come from BASIC's catalogue: &0400 + 2 × the first
    character (the rest of the name, 0, then the value), &04F6 for
    procedures, &04F8 for functions.
  - Values are printed by BASIC itself in its RAM copy through
    `farcall ..., BANK_RAM`: `FLDA` (&A3CB) and `FCON` (&9EF5), with
    `@%`. H sets the hex flag `&15`.
  - The routine addresses come from `build/basic.lst`; the interpreter
    is pinned (`make compare-core`).
- **\*CRUNCH**, **\*PACK**
  - Pass 1 marks the target of every line-number constant in a 4K
    bitmap at REU bank 0 `$4000` (the HTTP buffer, free meanwhile).
  - Pass 2 reads each line into MOSBUF, shortened, and builds the
    output line in &0600. It doesn't use &0700, because BASIC scans the
    command's line there for its CR after the command.
  - Finished lines are written back at a write position that never
    passes the read position.
  - Not joined: after IF, ON, ELSE, DATA, REM, `*` or in assembler; DEF
    and DATA lines are not joined onto the line before.
  - Named lines that are only a REM are kept whole.
  - At the end the variables are cleared (`SETFSA`).

## 4. Speech: *SPEECH, *SAY, *SPEAK (`src/mos/speech.s`, bank 6)

SAM (Software Automatic Mouth, Don't Ask Software, 1982) is not part of
the project (owner, 2026-10-14). `*SPEECH LOAD` reads the user's copy of
the C64 package into the REU. Tested with the package from CSDb (release
234771, "S.A.M."):

| File | Load range | Contents |
|---|---|---|
| `.sam 1` | &9500-&BFFF | SAM, its BASIC wedge at &9500 |
| `.sam 2` | &7D00-&947F | Reciter, English to phonemes |

The two files are told apart by their load address.

### SAM's interface

Found in the binary, with groepaz's disassembly of the C64 SAM (hitmen,
2007) for orientation:

- **Text**: at &9A15, ended by &9B.
- **Entries**: `JSR &9A03` speaks phonemes; `JSR &9A09` runs Reciter on
  the text first.
- **Settings**: speed at &BC18 (default &48), pitch at &BA3F (&40),
  throat at &97E0 and mouth at &97E1 (&80 each). `JSR &97E2` applies
  throat and mouth.

### REU layout

| Place | Contents |
|---|---|
| Last bank &BCF0-&FFEF | the image of &7D00-&BFFF |
| Last bank &FFF0 | header: "SAM", what is loaded, speed, pitch, throat, mouth |
| Bank 0 &3880 | the saved zero page (254 bytes) |
| Bank 0 &3980 | the saved &7D00-&7FFF |

`*SPOOL` now stops at &BCF0 (about 47K).

### Speaking (`sv`, copied to MOSBUF, called through `farcall`)

The routine runs with BANK_RAM mapped (cartridge off):

1. Save zero page &02-&FF and &7D00-&7FFF to the REU.
2. DMA the image in.
3. Put the text at &9A15 (prepared at &0600), set the four settings and
   `JSR &97E2`.
4. Go to 1 MHz, through the U64 turbo register or the enable bit. SAM's
   timing needs it, and it blanks the screen itself.
5. Call the entry.
6. Restore the turbo and &D011.
7. `copy_basic` puts BBC BASIC back from cartridge bank 1.
8. Restore &7D00-&7FFF and the zero page.

Bank 6 then clears SID registers &D400-&D417 and sets &D418 to &0F,
as the sound engine's reset does. SAM leaves its last sample and voice
settings there: a constant level under the next SOUND.

### Limits

- Loading takes about 2 seconds:
  - From the Ultimate's drives, `fs_reuopen` (bank 2) opens the file and
    reads its two address bytes; after the check, `fs_reurest` loads the
    rest with the DOS's LOAD_REU in one command. "02,REQUEST TRUNCATED"
    is expected: the room given is larger than the file.
  - From /REU, bank 5 copies the file within the REU in 128-byte pieces
    (`rd_xopen`, `rd_xrest`).
  - Byte by byte through OSBGET, as at first, took 15 seconds: each byte
    is a UCI command or a bank-5 call at 1 MHz.
- File names can't contain spaces, so copy the package's files under
  other names.
- Up to 230 characters of text; the header is at &06F0 (MOSBUF+$F0 is
  the RAM disk's register save).
- `*SAY` spells out words without a vowel ("BBC" -> "B B C"), which
  Reciter would skip.
- TIME stops while SAM speaks: interrupts are off.
