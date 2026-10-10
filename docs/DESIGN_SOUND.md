# Design: sound (SID, up to 8 SIDs)

Status: decided 2026-10-09 (section 6). Step (a), BBC mode with SID
probing, is implemented (section 7); SID mode follows.

Owner requests (2026-10-09):

- Support all 8 SIDs the Ultimate can have.
- Design the sound commands for everything UltiSID's 8 SIDs can do, not
  only what the BBC Micro had; usable from BASIC without POKE or PEEK.
- A BBC Micro compatibility option, which should sound like a BBC.
- The sound engine in RAM, with PAGE raised as on a BBC (decided: PAGE
  &1900, a disc BBC's value; see 4 and 6).

The interpreter stays bit-exact (PLAN.md section 14), so there are no new
keywords. BASIC reaches the MOS through `SOUND` (OSWORD 7), `ENVELOPE`
(OSWORD 8), `ADVAL` (OSBYTE &80) and `*` commands, which a program can
build with `OSCLI` (`OSCLI "VOICE "+STR$V%+" SAW"`). The design uses all
of them.

## 1. The hardware

| | |
|---|---|
| SIDs | Up to 8: two UltiSIDs, each split into 1, 2 or 4 instances over address lines (8SID: `$D400 $D440 $D480 $D580` and `$D420 $D4A0 $D520 $D5A0` in the manual's example), plus the two sockets (a dual-SID board in a socket counts as two). Addresses are set in the Ultimate's menu (`$D400-$D7E0`, `$DE00-$DFE0`). |
| Per SID | 3 voices (frequency, pulse width, waveform triangle/saw/pulse/noise and their combinations, ring modulation, hard sync, ADSR envelope), one filter (cutoff 11 bits, resonance, low/band/high pass, which voices go through it), master volume. |
| Total | 24 voices, 8 filters. |
| Not per voice | Volume (only via the ADSR sustain level), stereo position (the Ultimate's mixer, set in its menu). |

Finding the SIDs: the firmware's "get hardware info" (UCI `$28`, device 1)
lists the UltiSIDs and sockets with their base address, but not the split
instances. So at start-up the MOS probes every possible SID address
(`$D400-$D7E0`, `$DE00-$DFE0` in steps of `$20`; `$DE00/$DF00` only where
no cartridge I/O is there) with voice 3's oscillator (readable at `$1B`):
a SID is there if its oscillator runs when started and stops on the TEST
bit, and it is a new SID if starting it does not start one found before
(mirrors). `*SID` lists the result; `*SID <addr> ...` sets the list by
hand (VICE, unusual setups). The order: `$D400` first, then by address.
Voice v is voice `v MOD 3` of SID `v DIV 3`.

## 2. Two modes

`*SOUND SID` (the default) and `*SOUND BBC` choose how `SOUND` and
`ENVELOPE` are understood; a program switches with
`OSCLI "SOUND BBC"`.

### 2.1 BBC mode: sounds like a BBC Micro

The BBC's SN76489 has three square-wave tone channels and one noise
channel, 16 volume steps of 2 dB, and the MOS adds 4-note queues, sync,
hold and software envelopes (pitch and amplitude, steps in centiseconds).
In BBC mode:

| BBC | On the SID |
|---|---|
| Channels 1-3 (square) | SID 0 voices 0-2, pulse wave at 50% duty |
| Channel 0 (noise) | Its own voice when there are 2+ SIDs (SID 1 voice 0), else it takes SID 0 voice 2 while it plays (as channel 3's frequency drives noise types 3 and 7 anyway) |
| Noise P = 0-2 (periodic) | Pulse wave at 1/16 duty, frequency = shift rate / 15 (7812.5, 3906, 1953 Hz shift rates, as the BBC's 4 MHz / 512, 1024, 2048) |
| Noise P = 4-6 (white) | Noise waveform at a frequency giving the same shift rate |
| Noise P = 3, 7 | As 0/4, at channel 1's frequency |
| Pitch P (quarter semitones, 53 = middle C, 89 = A 440 Hz) | SID frequency from a table (PAL and NTSC clocks) |
| Amplitude -15..0 | Sustain level through a table matching the BBC's 2 dB steps on the SID's linear scale; attack and release fast (2 ms, 6 ms) so notes start and stop like the BBC's |
| ENVELOPE (14 parameters) | Pitch sections in software, as the BBC MOS does. Amplitude in software too: the level steps move the voice's sustain level (falling: written directly; rising: sustain set and the gate retriggered with attack 2 ms) |
| Duration (1/20 s), -1 | As the BBC |
| Queue (4 notes per channel), flush, sync (S), hold (H), ADVAL(-5..-8) | As the BBC |

Timing: the interrupt runs at 50 Hz (PAL) or 60 Hz (NTSC); envelope steps
of T centiseconds are counted in centiseconds (2 or 1.67 per interrupt),
so envelopes run at the BBC's speed.

### 2.2 SID mode (default): all voices, all SID features

`SOUND` addresses all 24 voices; each voice plays an *instrument*. The
instrument model follows Heartbeat Soundtracker's (the player in
ultimate-uci-oscar64, `HEARTBEATPLAYER_MANUAL.md` section 4), which was
made for exactly this hardware: up to 8 SIDs driven from one interrupt.

**SOUND C,A,P,D**

| | |
|---|---|
| C | `&FSVV` in hex: VV = voice `&00`-`&17` (0-23); S = sync: start together with S other voices (0-15, as BBC's S but more); F = flags: 1 flush (as BBC's F), 2 hold (as BBC's H), 4 tie (change pitch/instrument of the playing note without a new attack: legato and slides). Examples: `SOUND 5,...` voice 5; `SOUND &1005,...` flush voice 5 first; `SOUND &0200,...`, `&0201`, `&0202`: a chord on voices 0-2 that starts together. |
| A | 1-64: instrument number (its envelope, waveforms, modulation); -15..-1: the voice's current instrument at that loudness (sustain level 15..1); 0: rest (a silent note, for timing). |
| P | Pitch in quarter semitones as on the BBC (53 = middle C, 89 = A 440 Hz) over the SID's whole range, 0-511. P >= 1024: P-1024 is a raw SID frequency / 16 (effects). |
| D | Duration in 1/20 s (1-255) as on the BBC; -1 = until the next note on the voice or a flush; 0 = a hit (gate on, off at the next interrupt: attack/decay then release). The release phase sounds after the duration. |

**ENVELOPE N,T,...** (14 parameters): as on the BBC, N 1-16, pitch in
software; in SID mode the amplitude part becomes the hardware ADSR (AA ->
attack, AD/ALD -> decay to sustain ALD/8, AR -> release). Envelope n and
instrument n are the same slot for n <= 16: ENVELOPE n is a quick way to
define a simple instrument.

**Instruments** (64, kept in the REU, copied into the voice at note-on;
the Heartbeat fields):

| Part | Fields |
|---|---|
| Sound | waveform(s) (triangle, saw, pulse, noise; combined), ring modulation, hard sync, ADSR, finetune, hard restart (clean retrigger) |
| Pulse | width at the start, sweep rate, top and bottom (bounces) |
| Vibrato | delay, width, rate |
| Portamento | speed (slides from the previous note to the new one) |
| Filter | through the filter or not; type, resonance, cutoff start, sweep rate, top and bottom (bounce or stop) |
| Tables | wave table and arpeggio table, 16 steps each, with loop: chords (arpeggios), drum sounds (noise attack then pulse), wave sequences |

**Commands** (abbreviable, usable from programs through `OSCLI`):

| Command | |
|---|---|
| `*INSTRUMENT n [TRI] [SAW] [PULSE] [NOISE] [RING] [SYNC] [ADSR a d s r] [PW w [rate top bottom]] [VIB delay width rate] [PORTA speed] [FILTER type res cut [rate top bottom]] [ARP n n ...] [WAVES w w ...] [FINE f]` | Define instrument n (1-64); only the parts given change. `*INSTRUMENT n` lists it. |
| `*INSTRUMENT SAVE <file>` / `LOAD <file>` | All 64 instruments as a file (also: Heartbeat `.reu` songs' instruments, later). |
| `*VOICE v [n] [OFF]` | Voice v (0-23, or `ALL`) plays instrument n by default; OFF silences it. `*VOICE` lists the voices. |
| `*FILTER s [LOW] [BAND] [HIGH] [CUT n] [RES n] [VOL n] [3OFF]` | Filter and volume of SID s (0-7, or `ALL`) by hand. |
| `*SID` / `*SID <addr> ...` / `*SID AUTO` | List the SIDs found; set the list by hand; probe again. |
| `*SOUND SID` / `BBC` / `OFF` / `ON` / `STOP` | Mode; all sound off (SOUND ignored, as `*FX210,1`) and on; stop every voice and flush the queues. |
| `*PLAY v <notes>` (later) | A note string (`*PLAY 0 T120 O4 C D E F G`), for tunes without DATA tables. |
| `*HBPLAY <file>` / `*HBSTOP` (later, PLAN.md Phase 6) | Play a Heartbeat Soundtracker song (8 SIDs + Ultimate Audio) in the background. |

Defaults: instrument 1 a 50% pulse with ADSR 0,9,10,0; every voice plays
instrument 1; SID volume 15.

`ADVAL(-5-v)`: free places in voice v's queue (v = 0-23: `ADVAL(-5)` to
`ADVAL(-28)`; BBC's -5..-8 are the same for voices 0-3).

## 3. Interrupt and queues

- 50/60 Hz interrupt (the existing one; most C64 music players also
  run at 50 Hz): per active voice: duration countdown, envelope and
  modulation steps (pitch envelope, vibrato, pulse and filter sweeps,
  wave/arpeggio tables, portamento), queue pop with sync; then the
  register images are written to the SIDs (Heartbeat's flush pattern).
  Only active voices cost time. Heartbeat measured that 24 channels do
  not fit a tick at 1 MHz; at 64 MHz they take a few % of a frame.
- Upic Lite: the sound update runs after the frame is drawn (the 18%
  spare time), as the keyboard does now.
- Queues: 4 notes per voice (BBC), each note 5 bytes (C flags, A, P as
  16 bits, D).

## 4. Memory (PAGE)

| Part | Bytes |
|---|---|
| Engine (interrupt, OSWORD 7/8, pitch tables) | ~1.6K |
| Voice state (24 x 16) | 384 |
| Queues (24 x 4 x 5) | 480 |
| Envelopes (16 x 13) | 208 |
| Voice copies of the instrument in use (24 x ~24) | ~580 |
| Filters (8 x 8), SID list (8 x 2) | ~80 |
| Instrument definitions (64 x 64) | in the REU (4K), DMA at note-on |
| Total RAM | ~3.3K |

PAGE &0E00 (1.5K, the BBC tape value) holds this only for 4 voices
without instruments. Decided (owner): **PAGE &1900**, a disc BBC's value:
4.25K for the engine (`&0800-&18FF`), room for `*PLAY` and Ultimate
Audio state later; 26.75K for programs. Without an REU: 16 instruments in
RAM instead of 64.

## 5. Ultimate Audio

Ultimate Audio (7 DMA sample channels; the MOD and Heartbeat players in
ultimate-uci-oscar64) is a separate phase: `*HBPLAY`/`*MODPLAY` and
samples as voices 24-30. The Heartbeat player is C (Oscar64) ported from
Aleksi Eeben's 6502 original, published with his permission; using it
here means a 6502 version again, to be agreed with him. This design keeps
the voice numbering open for it (24-30 = Ultimate Audio channels, as
Heartbeat's own numbering puts them next to the SID channels).

## 6. Decisions (owner, 2026-10-09)

1. SID mode's `SOUND` layout `&FSVV`, A = instrument number: yes.
2. Native commands for everything the SIDs can do, BBC compatibility as
   an option that sounds like a BBC: the Heartbeat instrument model and
   `*INSTRUMENT`, `*VOICE`, `*FILTER`, `*SID`, `*SOUND`.
3. PAGE &1900.
4. Order of work: (a) SID list and probing, engine, BBC mode, (b) SID
   mode with instruments, (c) `*PLAY`, (d) Ultimate Audio / Heartbeat.
5. Still to do: a BBC sound check by the owner's ears.

## 7. Implementation notes, step (a) (2026-10-09)

- `src/mos/sound.s`, assembled for `&0800` and copied by `snd_install`
  (bank 4) right after the resident code at start-up: `font_init` lets
  interrupts in early, and the interrupt calls the engine (`irq_keys`,
  so the system, Upic Lite and teletext interrupts all reach it).
  Entry points `&0800+n`: 0 init, 3 interrupt, 6 OSWORD 7, 9 OSWORD 8,
  12 ADVAL, 15 stop all, 18 probe, 21 bell. Engine about 1.9K, variables
  and tables to about `&1300`.
- Centiseconds per call come from TIME (60 Hz system interrupt, 50 Hz
  Upic Lite frames), at most 10 per call.
- Queues: 3 waiting notes per channel, `ADVAL(-5..-8)` = 15 - 4 x
  waiting (MOS 1.20: 16-byte buffers, full when the next write would meet
  the read position; the `ADVAL(-6)=15` idiom of BBC programs works).
- SID probing: voice 3's oscillator must hold still under TEST (0 on a
  SID or UltiSID, **255 on an ARMSID**: measured on the U64-II's
  sockets), run without it and stop again; the display is off meanwhile
  so open-bus reads never pass. The 8SID addresses come first, then
  `$D400-$D7E0`; at most 8.
- The shipped `.cfg` sets Heartbeat's SID addressing (UltiSID 1 `$D400`,
  UltiSID 2 `$D420`, Range Split 1/4 on A7/A8, no mirroring); the
  sockets stay as they are and play along where they share an address
  (owner). With it the probe finds exactly the 8 UltiSIDs. The `.cfg` is
  applied when the cartridge is started from the Ultimate's file
  browser, not by REST `run_crt`.
- Amplitude in software through the sustain level: a rising level
  retriggers the gate (2 ms attack to full, 6 ms decay to the level), so
  slow attacks in BBC envelopes come out as small steps. VICE's ENV3
  read-back does not follow the envelope; the U64's does (255 at -15).
- Not yet: noise checked by ear, the owner's BBC sound check, SID mode,
  `*SOUND`/`*SID` commands.

## 8. Stereo and volume (owner, 2026-10-09)

The Ultimate's audio mixer has a volume and a stereo position for each
UltiSID (all four split instances of an UltiSID share them) and for each
SID socket; there is no setting per split instance.

- The shipped `.cfg` switches the UltiSIDs on (`Vol UltiSid 1/2 = -6 dB`;
  the owner's U64-II had them OFF, so only the ARMSID sockets sounded)
  and pans them as Heartbeat's does: UltiSID 1 `Left 3`, UltiSID 2
  `Right 3`. In the SID list (8SID order) SIDs 0, 2, 4, 6 are UltiSID 1's
  (left) and 1, 3, 5, 7 UltiSID 2's (right). The sockets keep the user's
  settings.
- From BASIC: `*SID PAN <unit> <-5..5>` and `*SID VOL <unit> <dB>|OFF`,
  unit `1`, `2` (UltiSIDs) or `S1`, `S2` (sockets). The MOS writes a
  two-line configuration file (`[Audio Mixer]`, `<item>=<value>`) to
  `/Temp/bbcmix.cfg` and sends the firmware's "load config" control
  command (`$04 $50` + path, firmware 3.15a, 2026-08-11), which applies it
  at once (not saved to flash) and answers with an error status for a
  line it cannot apply. There is no command to read mixer settings back.
- `*SID` lists the SIDs found.

## 9. Instruments and their defaults (owner, 2026-10-09)

Owner request: commands to program SID instruments, with default ones.
Part of step (b), SID mode.

Record (64 bytes, in the REU, 64 instruments; the fields follow
Heartbeat's instrument record, laid out for this engine):

| Offset | Field |
|---|---|
| 0 | waveform: control register bits ($10 triangle, $20 saw, $40 pulse, $80 noise, $04 ring, $02 sync) |
| 1, 2 | ADSR: attack/decay, sustain/release |
| 3, 4 | pulse width at the start (12 bits) |
| 5, 6, 7 | pulse sweep: rate (signed), top, bottom (high bytes; bounces) |
| 8, 9, 10 | vibrato: delay (interrupts), width, rate |
| 11 | portamento speed (0 = none) |
| 12 | filter: bit 0 on; bits 4-6 low/band/high pass |
| 13 | resonance (0-15) |
| 14, 15, 16, 17 | cutoff: start (high 8 bits), sweep rate (signed), top, bottom |
| 18 | finetune (signed, 1/64 semitone) |
| 19 | flags: bit 0 hard restart (gate off one interrupt before the note), bit 1 cutoff sweep stops at the end instead of bouncing |
| 20-35 | wave table: 16 steps of waveform bytes ($FF n = loop to step n, 0 = end) |
| 36-51 | arpeggio table: 16 steps of semitone offsets, alongside the wave table |
| 52 | table speed (interrupts per step) |
| 53-63 | name (up to 10 characters, padded with spaces) |

Defaults 1-16 (in the cartridge, copied to the REU at start-up and by
`*INSTRUMENT DEFAULT`); 17-64 start as copies of 1:

| # | Name | Sound |
|---|---|---|
| 1 | SQUARE | 50% pulse, quick decay: the BBC-like default |
| 2 | PIANO | pulse, short attack, long decay |
| 3 | ORGAN | triangle and pulse, full sustain |
| 4 | STRINGS | saw, slow attack, slow pulse sweep |
| 5 | BRASS | saw, low pass opening |
| 6 | LEAD | pulse, width sweep, delayed vibrato |
| 7 | BASS | saw, low pass, short decay |
| 8 | FLUTE | triangle, vibrato |
| 9 | PLUCK | pulse, fast decay |
| 10 | BELL | triangle, ring modulation |
| 11 | KICK | noise click, then triangle falling in pitch (tables) |
| 12 | SNARE | noise and triangle (tables) |
| 13 | HIHAT | short noise |
| 14 | PAD | saw, slow cutoff sweep |
| 15 | ARP | major chord arpeggio (tables) |
| 16 | SYNC | hard-sync lead |

Commands: `*INSTRUMENT n <fields>` (as section 2.2), `*INSTRUMENT n` lists
it with its name, `*INSTRUMENT n NAME <text>`, `*INSTRUMENT n COPY m`,
`*INSTRUMENT DEFAULT`, `*INSTRUMENT SAVE/LOAD <file>` (64 x 64 bytes).

## 10. Implementation notes, step (b1) (2026-10-09)

- SID mode is the start-up mode; `*SOUND BBC`/`SID` switch (all voices
  reset), `OFF`/`ON`/`STOP`. 24 voices; the interrupt only spends time on
  voices that play or have queued notes.
- Split: the interrupt engine stays in RAM (`sound.s`, about 2.3K code,
  variables to about `&162C`); probing, OSWORD 7/8 parsing, ADVAL,
  `*SOUND` and `*INSTRUMENT` moved to bank 2 (`sndcmd.s`).
- Pitch: one octave of 48 quarter-semitone frequencies (middle C's,
  PAL or NTSC) shifted per octave instead of a 256-entry table; SID-mode
  P is signed (Q = P + 235 >= 0, so down to P = -235), P >= 1024 a raw
  frequency x 16.
- Instruments: 64 records of 64 bytes at REU `$2000` (bank 0); 1-16 the
  defaults from `tools/gensound.py` (data in bank 2, since the REU DMA
  reads the bus with that bank mapped), 17-64 copies of 1. A note copies
  the header (20 bytes) into the voice: waveform, ADSR, pulse width,
  filter routing, resonance and cutoff (set on the SID when the note
  starts). Without an REU every voice plays the built-in SQUARE and
  `*INSTRUMENT` reports that it needs one.
- Not yet (step b2): pulse and cutoff sweeps, vibrato, portamento, the
  wave/arpeggio tables (KICK, SNARE, ARP sound plain until then), hard
  restart, finetune. ENVELOPE only acts in BBC mode.
- Read-back: on the split UltiSIDs the voice-3 read-back registers
  appear to be shared by an UltiSID's four instances, so they cannot
  tell the instances apart; tests read back only SID 0.

## 11. Two engine images, modulation (step b2) (2026-10-09)

Memory (owner: the REU first, PAGE &1D00, options to switch functions
off for more RAM):

| RAM | |
|---|---|
| `&0800-&08FF` | MOSBUF, the `*` commands' 256-byte scratch (moved from `&1800`: under `*SOUND NONE` a program may start at `&900`) |
| `&0900-&1C5F` | the engine image in use: code and its variables |
| `&1C60-&1CF5` | data both images share (`defs.s` SNDSHR): mode, on/off, the SIDs found, filter registers, the note being queued, pitch tables, recording |
| `&1D00` | PAGE (OSHWM) |

- Two images assembled from `sound.s` with `SIDIMG` 0 or 1 (`sound_bbc.s`
  and `sound_sid.s` are their own parts), both in cartridge bank 6 with
  the sound commands (`sndbank.s`, `sndcmd.s`, `songcmd.s`; the help
  moved to banks 7+). `*SOUND BBC` / `SID` copies one into RAM (same
  entry points); BBC envelopes are kept in the REU (`$3000`), so they
  survive a switch. `*SOUND NONE` takes the engine out (`snd_on` 0: the
  interrupt and VDU 7 leave it alone, SOUND is ignored, OSBYTE &83 says
  `&900`, LOAD / `*SRREAD` may go down to `&900`); `*SOUND SID|BBC`
  refuses while PAGE is below `&1D00` and then finds the SIDs again.
  The SID image with modulation and the tracker fills its space to
  `&1C3F`.
- Bank 6 cannot call bank 2's helpers directly (they read keywords and
  texts from their caller's bank): copies (`s6_word`, `s6_text`, ...) or
  `farcall` (numbers, file names, `rx_` REU-file transfers in
  `reufile.s`).

Modulation (SID image, `s_mod` every interrupt for voices that use it;
`c_mod` bits say which), with the units of the instrument record:

| Part | Unit |
|---|---|
| pitch | 1/64 semitone internally (`(P + 235) * 16`), interpolated between the quarter-semitone table entries |
| FINE f | 1/64 semitone, signed |
| PW w rate top bottom | rate: width units per interrupt, signed; top, bottom: the width's high nybble; bounces |
| CUT c rate top bottom | rate: cutoff (high 8 bits) units per interrupt; bounces, or stops (flag bit 1, `STOP`) |
| VIB delay width rate | delay in interrupts; width in 1/8 semitone (a triangle); phase step rate * 4 per interrupt (rate 5: about 4 Hz at 50 Hz) |
| PORTA speed | speed/64 semitone per interrupt, from the previous note (also on a tie) |
| WAVES / ARP / SPEED | step every SPEED interrupts, fetched from the REU record by DMA (1 byte each); wave 0 ends, `$FF n` goes on at step n; arpeggio in semitones, signed |
| RESTART | hard restart: TEST bit, envelope 0, the gate one interrupt later |

SOUND's amplitude in SID mode may also be `instrument + 256 * level`
(`&0A08`: instrument 8 at 10/15): the level scales the instrument's own
sustain level (sustain * level / 15, rounded), so a percussive
instrument (sustain 0) stays percussive; a queue carries the level
(`q_lvl`), the recorder writes it as the effect `&1v`, which a song
plays the same way. (A first version set the sustain level itself:
KICK and SNARE then held a tone for the whole note.) Amplitude -15..-1
still sets the voice's sustain level directly, as before. Before this, a
note with a level (amplitude -15..-1) could only use the voice's
previous instrument, so programs that gave every note a level (the
music demo) played the default instrument on every voice.

## 12. Making sure there are 8 SIDs (owner, 2026-10-09)

The U64 applies the cartridge's `.cfg` (8SID layout, stereo mixer) only
when the cartridge is started from its file browser; after a power cycle
and a start over the network the layout is the default one and the probe
found 3 SIDs: voices 9-23 were silent (the demo's drums, the Toccata's
pedal). Decided (owner: both): `*SID SETUP` loads the layout (the `.cfg`'s
`[SID Addressing]` and `[Audio Mixer]` lines through "load config", as
`*SID PAN`), and start-up does the same when it finds fewer than 8 SIDs
and the command interface is there (errors ignored then). After a
successful load the list is set to the 8 known addresses (`$D400 $D420
$D480 $D4A0 $D500 $D520 $D580 $D5A0`) instead of probed: a split
UltiSID's four parts all read back the first part's oscillator, so the
probe cannot see the other three. Lasts until the Ultimate is reset.

The probe does find all eight at start-up (before the engine has run),
but not later: after `*SOUND NONE`, `*SOUND SID` found 3. So `snd_8sid`
($03FD, cleared by the KERNAL's RAMTAS at a cold start) remembers the
layout, set by `*SID SETUP` or by a probe that finds exactly its eight
addresses; every later setup then uses the eight addresses.

Ring modulation and hard sync (BELL, SYNC) take part of their sound from
the neighbouring voice of the same SID; with every voice busy that is an
unrelated part and they sound off key, so the demo does not use them.

## 13. The REU from the interrupt (2026-10-10)

SID mode reads instrument tables (`s_tget`) and song rows (`t_rowplay`)
from the REU in the interrupt. Every other REU user (the line editor's
history, fonts, palettes, the RAM disk, `*SRWRITE`/`*SRREAD`, OSWORD
&42, the network buffers) sets the REU's registers from the foreground
in several steps; an interrupt in between left its own address, length
and target behind, and the foreground transfer then went elsewhere:
314 of 483 test transfers came back wrong with eight ARP voices
sounding, and pressing UP in the line editor crashed the machine.
A first fix had `s_irq` push `$DF02-$DF0A` and restore them; but the
Ultimate's REU bank register reads back only its low 3 bits ($F8 + bank),
so the restore moved interrupted transfers to bank $F8+: damaged glyphs
and "Song full" in the music demo. Now every foreground transfer (39
places in 14 files) sets the REU up with interrupts off (`php`/`sei` ...
the command, `plp`); `s_irq` uses the REU freely. The SID image's ten
work bytes `s_dirty`..`s_tmpx` stay in SNDSHR. Test: `reu_irq`.
