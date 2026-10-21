# Design: the music demo (24 voices, instruments)

`demos/music/MUSIC.bas` shows off U64 BBC BASIC's sound: all 24 voices
of the 8 UltiSIDs, the instruments, stereo (UltiSID 1 left, 2 right), in
music people know; and it shows that this is plain, readable BBC BASIC
(structured, no POKE/PEEK), the way BBC Micro music programs were
written. It builds each piece from BASIC with `SOUND` on the song
tracker (DESIGN_TRACKER.md), then plays it in the background.

All music is public domain; the arrangements are written for this
project and licensed with it (GPL-3.0, as the rest of `demos/` that is
ours).

## 1. Programme

A menu with eight pieces, one at a time or all in order. They build up
from a few voices to all 24:

| # | Piece | Style | Voices |
|---|---|---|---|
| 1 | *Greensleeves* (trad., 16th c.) | folk | 4 |
| 2 | *Scarborough Fair* (trad.) | folk | 6 |
| 3 | *The Entertainer* (Joplin, 1902) | ragtime | 8 |
| 4 | *Eine kleine Nachtmusik*, 1st theme (Mozart, 1787) | classical | 10 |
| 5 | *Canon in D* (Pachelbel) | classical | 3 -> 24: a new voice every two bars until all 24 play |
| 6 | *Toccata in D minor*, opening (Bach) | classical | 18 |
| 7 | *Ode to Joy* (Beethoven) | classical | 24 |
| 8 | *Maple Leaf Rag* (Joplin, 1899) | ragtime | 8 |

## 2. Note files

The pieces are text files, `demos/music/*.mml`, one per piece, written by
`arrange.py` (from public-domain MIDI editions; the Mutopia download
addresses are in its docstring, the files go to `build/mutopia`). A file
has header lines, then blocks (one per bar, a blank line between
blocks) with a line `v: notes` per voice.

- Header: `#TITLE`, `#COMPOSER`, `#TEMPO bpm`, `#VOICES n`,
  `#INSTRUMENT n parts` (as `*INSTRUMENT`: each piece defines its own
  instruments).
- Notes in the usual MML conventions: `C D E F G A B` (`#`/`+` sharp,
  `-` flat), `R` rest, a length after the note (1, 2, 4, 8, 16, 32; `.`
  dotted), `&` tie to the next note, `O4` octave (`<` `>` down/up), `L8`
  default length, `I5` instrument, `V12` loudness.

## 3. Building and playing

For each piece MUSIC reads the note file and builds a song from BASIC:
`#TEMPO` gives `*SONG NEW tempo 8` (8 rows per beat: a 32nd note is one
row) and `*SONG RECORD`; each note is a `SOUND` (duration in rows) that
goes into the song at its voice's place; `#INSTRUMENT` lines define the
piece's instruments with `*INSTRUMENT`. Then `*SONG PLAY`. The screen
shows the commands as they go by. Building takes 10-30 seconds (the
Canon, 24 voices: about 28 s); playback runs in the interrupt, without
gaps, in every screen mode.

The screen is MODE 100 (the C64 text screen; MODE is set at the top of
the program, as BASIC refuses it inside a PROC). While a piece plays, a
bar chart shows one bar per voice, as high as the note it plays
(`ADVAL(-29-v)`, 49 = middle C), in eighths of a row (characters made
with VDU 23, as PETSCII's partial blocks). UltiSID 1's SIDs (0, 2, 4, 6)
are on the left in cyan (the left speaker), UltiSID 2's on the right.

## 4. Instruments and arrangement

Instruments 17-30 (`arrange.py` CUSTOM: violin, cello, harpsichord,
choir, ragtime piano, banjo, clarinet, trumpet, organ, glockenspiel,
slide lead, tuba, string bass, swelling strings) use the engine's
modulation; each piece maps some of its parts onto them (`PIECE_INSTR`;
`arrange.py --instruments` applies that to the `.mml` files without the
MIDI sources). Loudness `V` goes with the instrument (SOUND amplitude
instrument + 256 * level).

- Endings: each piece ends on a cadence, its last bar the downbeat's
  chord held (`Piece(hold_end=True)`): The Entertainer at bar 36 (the A
  strain's C), Nachtmusik at bar 18 (back in G), the Toccata at bar 30
  (its D minor end before the fugue; first bar 12); Maple Leaf Rag gets
  a bar of its A-flat chord after bar 32.
- Voices that depend on their neighbour (ring modulation, sync) sound off
  key in full chords: the pieces use GLOCK and LEAD instead. The organ
  has a slow pulse sweep and slight vibrato.
- Drums: KICK2, SNARE2, HAT2 (decays 7, 6, 3; a SID envelope always
  peaks at full volume, so a drum's loudness is its decay) in a rag's
  boom-chick: kick on 1 and 3, snare on 2 and 4, hi-hat on the off-beat
  eighths.
