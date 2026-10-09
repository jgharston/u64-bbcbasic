# Design: the song tracker

Status: decided 2026-10-09 (owner); built 2026-10-09 (section 7).

## 1. Why, and why our own

The BASIC music player of DESIGN_MUSICDEMO.md fed 24 voices from BASIC
in real time: reading a bar of 24 voices from a file was slow enough that
queues ran dry (audible pauses between the Canon's sections) and the
player then had no time to draw (bars missing). Music moves into the
interrupt: a tracker that plays songs kept in the REU.

Heartbeat Soundtracker's own player (Aleksi Eeben; source supplied by the
owner) was considered and dropped (owner, 2026-10-09). It needs 16K of
RAM while a song is loaded:

| Heartbeat part | Size | Our need |
|---|---|---|
| song header in RAM: 64 instruments, 64 sample records, sequencer | 8K | instruments stay in the REU (as now); no samples |
| frequency and BPM tables (SID with finetune, Ultimate Audio rates) | 3.75K | none: the engine computes SID frequencies from one octave (96 bytes) |
| live parameters of 31 channels | 1.25K | the 24 SID voices' state the engine has |
| code (7 sample channels, modulations, 11 commands, visualiser, NTSC) | 4K | the modulations are sound step (b2) |

and its own 195 Hz CIA interrupt, which Upic Lite's frame interrupt
switches off. Decided instead: **our own simpler tracker inside the SID
sound engine**: patterns and instruments in the REU, one row fetched per
step by DMA, about 1K of code, no extra RAM, played from the engine's
interrupt path, so in **every screen mode** (also Upic Lite). Songs are
**built from BASIC** (section 5); the music demo records its pieces that
way and plays them (owner: the demo should show the song being built
from BASIC commands, not just play a finished song). Heartbeat songs do
not play.

## 2. Song in the REU

| REU | Contents |
|---|---|
| `$010000` | header (256 bytes): magic `U64SONG`, version, title (32), composer (32), tempo (BPM), rows per beat, voices used, song length (patterns), loop point |
| `$010100` | order list: 256 pattern numbers |
| `$010200` | per-pattern row count (1-64), 256 bytes |
| `$010300` | instruments 1-64 are the global ones (REU `$2000`); a saved song carries a copy |
| `$020000` + n x `$1200` | pattern n (0-255): 64 rows x 24 voices x 3 bytes |

A cell (3 bytes): **note** (0 = nothing, 1-96 = C0..B7 in semitones, 254
= tie: the playing note continues (legato to a new pitch with an
instrument's portamento), 255 = key off), **instrument** (0 = keep, 1-64),
**effect** (high nybble command, low nybble value: volume (sustain
level), pitch slide up/down, vibrato depth, filter cutoff step, set
tempo; 0 = none).

## 3. Playback

From the engine's interrupt (system 60 Hz, Upic Lite's 50 Hz frame,
teletext): the centiseconds since the last call (from TIME, as SOUND
does) count towards the next row (row length = 6000 / (BPM x rows per
beat) cs, kept in 1/256 cs so tempos stay exact; rows land on interrupts,
so within 17-20 ms). A row: one DMA of 72 bytes into a RAM buffer, then
per voice: note -> the voice takes the instrument and starts it (as a
SID-mode SOUND note), key off -> gate off, tie -> new pitch without a new
attack; the instruments' modulation (step b2) runs every interrupt. The
order list advances at the end of a pattern; at the end of the song:
stop, or loop.

While a song plays, SOUND still plays on voices the song does not use.

## 4. Commands

| Command | |
|---|---|
| `*SONG NEW [bpm [rows per beat]]` | an empty song (default 120, 4) |
| `*SONG RECORD` / `*SONG RECORD OFF` | SOUND writes into the song (section 5) |
| `*SONG PLAY [pattern]` / `*SONG STOP` | play (from the order list's position), stop |
| `*SONG TEMPO bpm` | change the tempo |
| `*SONG TITLE text`, `*SONG COMPOSER text` | for the header and `*SONG` |
| `*SONG SAVE <file>` / `*SONG LOAD <file>` | header, order list, patterns used, the instruments |
| `*SONG` | title, tempo, position, length |

For programs, without PEEK: `ADVAL(-29-v)` = the note voice v of the song
plays now (0 = silent), for meters; OSBYTE (number to be chosen) = order
position and row, for synchronising pictures with the music.

## 5. Building songs from BASIC

After `*SONG RECORD`, `SOUND c,a,p,d` does not play: it writes into the
song. Each voice has a cursor (a row in the song):

- `c` = voice (SID mode `&FSVV`; S and F ignored except tie, F = 4);
- `a` = instrument 1-64 (or -15..-1: the voice's instrument at that
  loudness: a volume effect), 0 = a rest (key off);
- `p` = pitch as SOUND (BBC quarter semitones, 53 = middle C), rounded to
  a semitone;
- `d` = length **in rows** (not 1/20 s): the note goes into the cell at
  the cursor, the cursor moves on by d rows (a key off is written at the
  new cursor unless a note follows there).

Patterns fill up in order (a new pattern when a cursor passes row 64,
added to the order list). `ENVELOPE` writes nothing; instruments are
`*INSTRUMENT` (they belong to the song when it is saved).

The music demo: arrange.py writes the note files (as now, plus
`#INSTRUMENT` lines: each piece defines its own instruments, owner: more
variety); MUSIC reads a file, defines the instruments with OSCLI, records
every note with SOUND (no real-time pressure: a piece takes a second or
two to build, shown on screen), then `*SONG PLAY` and draws the voice
meters from `ADVAL(-29-v)` while it plays.

## 6. Order of work

1. Sound step (b2): instrument modulation (pulse and cutoff sweeps,
   vibrato, portamento, wave/arpeggio tables, hard restart) in the
   engine. RAM: `&0800-&17FF` cannot hold BBC mode, SID mode with
   modulation and the tracker at once, but they are never needed at the
   same time: the engine becomes **two images** with the same entry
   points, a BBC-mode one (software envelopes, noise channel) and a
   SID-mode one (instruments, modulation, the tracker), swapped in from
   the cartridge by `*SOUND BBC` / `*SOUND SID` (as the start-up copy
   does now); each has the full 4K.
2. The tracker: song format, playback, `*SONG` commands, SAVE/LOAD.
3. Recording (section 5), `ADVAL(-29-v)`.
4. The demo on it; arrange.py with per-piece instruments.

## 7. As built (2026-10-09)

- Patterns at `$020000` + n * `$1200` in REU banks 2 and 3: at most 28
  patterns (1792 rows), so the song stays clear of programs' data
  (`$040000` on) and the RAM disk. Header, order list and row counts in
  bank 1 (`$010000`-`$0102FF`); the header also keeps the 24 recording
  cursors.
- Playback (`s_song` in the SID image, about 400 bytes with its 72-byte
  row buffer): the row clock in centiseconds * 256 from TIME (row length
  1536000 / (tempo * rows per beat), worked out by `*SONG PLAY`); a row
  is one DMA, its notes start through `s_note` with duration "until the
  next note" (255); key off releases them. At the end the song's notes
  are released (or it goes on at the loop point).
- Cells: note 1-96 (49 = middle C), 254 = the note goes on (a tie), 255
  = key off; instrument 0 = the voice's own; effect `&1v` = sustain level
  v. Other effects are not used yet.
- Recording (`sg_record`, from OSWORD 7 while `*SONG RECORD` is on in SID
  mode): the cell at the voice's cursor, the cursor moves on by the
  duration in rows, a key off goes after the note; `*SONG RECORD OFF`
  sets the length from the furthest cursor. Durations up to 255 rows per
  SOUND.
- `ADVAL(-29-v)`: the voice's note from its target pitch while it plays
  (the image had no room for a note table).
- `*SONG SAVE/LOAD`: 3 pages of header, order list and row counts, then
  the patterns up to the highest one the order list uses.
- Not yet: other effects (slides, tempo changes), `*SONG PLAY` from a
  pattern number, an OSBYTE for the position.
