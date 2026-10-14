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
