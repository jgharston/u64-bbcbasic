# Design: music demo (24 voices, instruments)

Status: decided 2026-10-09 (section 6). The BASIC player (sections 3, 7)
is replaced by the song tracker (DESIGN_TRACKER.md): the demo builds
each piece from BASIC with SOUND in record mode, then plays it. Roadmap: PLAN.md
section 24. Depends on sound step (b2) (sweeps, vibrato, tables: the
instruments only sound full with it).

## 1. Goal

Show off U64 BBC BASIC's sound: all 24 voices of the 8 UltiSIDs, the 16
default instruments, stereo (UltiSID 1 left, 2 right), in music people
know; and show that it is plain, readable BBC BASIC (structured, no
POKE/PEEK), the way BBC Micro music programs were written.

All music is public domain; the arrangements are written for this
project and licensed with it (GPL-3.0, as the rest of `demos/` that is
ours).

## 2. Programme

A menu program (`MUSIC`) and one program per piece, `CHAIN`ed (each
piece has the full 26.75K for its notes; the menu comes back after each,
or plays them all in order). Running order builds up, from a few voices
to all 24:

| # | Piece | Style | Voices | Instruments | Shows |
|---|---|---|---|---|---|
| 1 | *Greensleeves* (trad., 16th c.) | folk | 4 | FLUTE melody, PLUCK broken chords, BASS | a quiet start, vibrato, BBC-like simplicity |
| 2 | *Scarborough Fair* (trad.) | folk | 6 | BELL (ring modulation) melody, ARP, PAD | wave/arpeggio tables, filter sweep |
| 3 | *The Entertainer* (Joplin, 1902) | ragtime ("pop") | 8 | PIANO right hand, PLUCK + BASS left hand, then a modern beat (KICK, SNARE, HIHAT) | drums from tables, swing, stereo split of the hands |
| 4 | *Eine kleine Nachtmusik*, 1st theme (Mozart, 1787) | classical | 10 | STRINGS in four parts, PLUCK bass | string section, sync of chords |
| 5 | *Canon in D* (Pachelbel) | classical | 3 -> 24 | BASS ostinato, then a new voice every two bars: STRINGS, FLUTE, BELL, PAD, ORGAN... until all 24 play | the big build-up: every voice, left and right |
| 6 | *Toccata in D minor*, opening (Bach) | classical | 18 | ORGAN in full chords over 6 SIDs, BRASS doubling | the wall of sound, filter |
| 7 | *Ode to Joy* (Beethoven) - finale | classical | 24 | melody passed through LEAD, BRASS, FLUTE, SYNC; full orchestra on the last verse | everything at once |
| (8) | *Maple Leaf Rag* (Joplin, 1899) | ragtime | 8 | as 3 | an encore |

## 3. How the notes are played

Option A (proposed): **plain BASIC with SOUND**, as BBC music programs
did. Each piece is DATA in a compact note text, one line per bar per
voice group, read by a small player PROC:

```
1000 DATA "V0 I8 O5 L8 E G A2 B8 C B A F#4 D8 E F# G4 E E D# E F# D# B"
```

- The player reads a line, turns each note into `SOUND &v,i,p,d`
  (instrument, BBC pitch, duration in 1/20 s), and waits only when a
  voice's queue is full (`ADVAL(-5-v)`), so 24 voices stay in time. Chord
  starts use the sync digit (`SOUND &2xx`).
- Shows that the machine needs no special music commands: a BBC
  programmer recognises every line. Works today (after b2 for the full
  instrument sound).

Option B: **a MOS sequencer `*PLAY`**: note strings handed to the MOS,
played from the interrupt in the background, so a program can draw at
the same time. More capable, but a new feature (notation, a sequencer in
the sound engine, RAM it does not have yet).

The note text for A follows the usual MML conventions, so B can take the
same text later: `C D E F G A B` (`#`/`+` sharp, `-` flat), `R` rest,
`O4` octave (`<` `>` down/up), `L8` default length (1, 2, 4, 8, 16, 32;
`.` dotted), `T120` tempo, `I5` instrument, `V12` loudness, `&` tie,
`V0`-`V23` the voice the next notes go to.

## 4. Screen

BBC look, MODE 7 teletext (it does not lower HIMEM below &7C00 and
draws fast): the title in double height, the piece and composer, and a
**voice meter**: 24 coloured bars (one per voice, grouped by SID, left
half UltiSID 1, right half UltiSID 2), driven by the player itself (it
knows which voice it gave a note and how long), no PEEK. A line of the
note text scrolls along the bottom while it plays.

## 5. Files

`demos/music/MUSIC.bas`, the player and menu (indented, structured; the
formatter strips the indentation on upload, PLAN.md section 20), the
pieces as `demos/music/*.mml` note files (section 7), a README with the
pieces,
their sources (public-domain editions used for reference) and the
licence. `*FX` and `*SOUND SID` set at the start; `*SID` shows the SIDs
before the menu.

## 6. Decisions (owner, 2026-10-09)

1. Both: option A now (BASIC with SOUND), in the MML-like notation of
   section 3, so a later `*PLAY` (option B) plays the same text.
2. The programme of section 2 as proposed.
3. The screen: graphics, Upic Lite MODE 2 (160 x 256, 16 colours);
   changed to MODE 5 (section 7).

## 7. Consequence of MODE 2: notes from files

Upic Lite MODE 2 keeps its picture below HIMEM (`&3000`), so a program
has `&1900-&2FFF`, about 5.9K. That holds the player and the screen code,
not the notes of a 24-voice piece. So the notes are **text files**
(`demos/music/*.mml`, one per piece), read line by line while the piece
plays (`OPENIN`, `BGET#`), not DATA: a piece can be as long as it needs,
the pieces need no `CHAIN` of their own (one program plays them all),
and `*PLAY` can later take the same files.

Even so the player itself (about 4-6K, plus 2-3K of arrays, strings and
BASIC's stack) does not fit MODE 2's 5.9K, the same squeeze as on a disc
BBC. Decided (owner): **MODE 5** on Upic Lite: the same 160 x 256
picture with 4 colours and HIMEM &5800 (16K). The 24 voice bars are
grouped by SID, UltiSID 1's SIDs left in cyan, UltiSID 2's right in
magenta (as heard in stereo), the title in white.
