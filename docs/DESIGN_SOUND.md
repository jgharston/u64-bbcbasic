# Design: sound (SID, up to 8 SIDs, Ultimate Audio)

The sound of U64 BBC BASIC: all 8 SIDs the Ultimate can have (24
voices), commands for everything the SIDs can do (not only what the BBC
Micro had), usable from BASIC without POKE or PEEK, a BBC mode that
sounds like a BBC Micro, a song tracker (DESIGN_TRACKER.md), and
Ultimate Audio's sample channels with a MOD player.

The interpreter stays bit-exact, so there are no new keywords. BASIC
reaches the MOS through `SOUND` (OSWORD 7), `ENVELOPE` (OSWORD 8),
`ADVAL` (OSBYTE &80) and `*` commands, which a program can build with
`OSCLI` (`OSCLI "INSTRUMENT "+STR$I%+" SAW"`).

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
(mirrors). `*SID` lists the result. The order: `$D400` first, then by
address.
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
| Queue (3 waiting notes per channel, as MOS 1.20), flush, sync (S), hold (H), ADVAL(-5..-8) | As the BBC |

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
| `*INSTRUMENT SAVE <file>` / `LOAD <file>` | All 64 instruments as a file. |
| `*SID` | List the SIDs found. |
| `*SOUND SID` / `BBC` / `OFF` / `ON` / `STOP` / `NONE` | Mode; all sound off (SOUND ignored, as `*FX210,1`) and on; stop every voice and flush the queues; the engine out of RAM (section 4). |
| `*SID SETUP`, `*SID PAN`, `*SID VOL` | The 8SID layout and the mixer (sections 7, 8). |
| `*SONG ...` | The song tracker (DESIGN_TRACKER.md). |
| `*SAMPLE`, `*MODPLAY`, `*MODSTOP` | Ultimate Audio (section 5). |

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
- Queues: 3 waiting notes per voice (as MOS 1.20: `ADVAL(-5..-8)` = 15
  - 4 x waiting, so the `ADVAL(-6)=15` idiom of BBC programs works),
  each note 5 bytes (C flags, A, P as 16 bits, D).
- Centiseconds per call come from TIME (60 Hz system interrupt, 50 Hz
  Upic Lite frames), at most 10 per call.
- A Upic full show (`*UPIC SHOW`) runs with interrupts off and the
  engine's RAM swapped out: the SIDs' volume goes to 0 meanwhile and back
  afterwards (`upmute.s`), so the music pauses cleanly.

## 4. Memory (PAGE)

| RAM | |
|---|---|
| `&0800-&08FF` | MOSBUF, the `*` commands' 256-byte scratch (under `*SOUND NONE` a program may start at `&900`) |
| `&0900-&1C5F` | the engine image in use: code and its variables |
| `&1C60-&1CF5` | data the images share (`defs.s` SNDSHR): mode, on/off, the SIDs found, filter registers, the note being queued, pitch tables, recording |
| `&1D00` | PAGE (OSHWM) |

- Three images: BBC mode, SID mode (with modulation and the tracker,
  filling its space to `&1C3F`), and the MOD engine (section 5). They are
  assembled into cartridge bank 6 with the sound commands (`sndbank.s`,
  `sndcmd.s`, `songcmd.s`; the MOD engine in bank 10); `*SOUND BBC` /
  `SID` copies one into RAM (same entry points). BBC envelopes are kept
  in the REU (`$3000`), so they survive a switch.
- `*SOUND NONE` takes the engine out (`snd_on` 0: the interrupt and VDU 7
  leave it alone, SOUND is ignored, OSBYTE &83 says `&900`, LOAD /
  `*SRREAD` may go down to `&900`); `*SOUND SID|BBC` refuses while PAGE
  is below `&1D00` and then finds the SIDs again.
- Instruments: 64 records of 64 bytes in the REU at `$2000` (bank 0); a
  note copies the header (20 bytes) into the voice. Without an REU every
  voice plays the built-in SQUARE and `*INSTRUMENT` reports that it needs
  one.
- Bank 6 cannot call bank 2's helpers directly (they read keywords and
  texts from their caller's bank): copies (`s6_word`, `s6_text`, ...) or
  `farcall` (numbers, file names, `rx_` REU-file transfers in
  `reufile.s`).

## 5. Ultimate Audio

Ultimate Audio (U64, 16 MB REU) has 7 DMA sample channels:

- **Samples:** `*SAMPLE LOAD n file [rate]` keeps up to 32 samples (8-bit
  mono WAV, or raw signed 8-bit data), 256K in all, in the REU
  (`$EE0B00` on; the directory at `$EE0000`). In SID mode voices 24-30
  are the sample channels 0-6: `SOUND 24+c,n,p,d` plays sample n (`n +
  256 * loudness` for its volume), p 53 the sample's own rate (4 steps a
  semitone), d in 1/20 s (`sample.s`, bank 10). A one-shot writes loop
  points 0: non-zero loop points loop a sample even without the loop bit
  (measured; reported to ultimate-uci-oscar64, 1.4.2).
- **MOD music:** `*MODPLAY file` plays a ProTracker MOD (4 channels, 15
  or 31 samples, up to 768K at `$F20000`) in the background; `*MODSTOP`
  ends it. The engine is ModPlayer_16k by Freshness (6510nl), ported to
  MADS (`modengine.s`, assembled for `&0900` as the third engine image,
  `SNDV_IMG` 2; its tables in `modtables/`, copied to the REU at
  start-up). It takes the SID engine's place: SOUND on the SID voices is
  silent until `*MODSTOP`, which brings the SID engine back; samples
  still play on channels 4-6 (SOUND 28-30). The CIA timer runs at the
  MOD's tick rate meanwhile; TIME stays right (`mi_time`).
- Control register bits: 1 start, 2 loop, 4 the channel's interrupt at
  the sample's end (it hangs the machine when not acknowledged, so the
  MOS never sets it). Registers are big-endian; loop points are offsets
  from the sample's start.
- During a Upic full show the MOD's channels are stopped; the MOD goes on
  where it stood afterwards, its channels starting again with their next
  notes.

## 6. SID probing

`src/mos/sound.s` is the interrupt engine, copied into RAM; its entry
points are `&0900+n` (init, interrupt, OSWORD 7, OSWORD 8, ADVAL, stop
all, probe, bell). The interrupt calls it from `irq_keys`, so the system,
Upic Lite and teletext interrupts all reach it.

- SID probing: voice 3's oscillator must hold still under TEST (0 on a
  SID or UltiSID, **255 on an ARMSID**: measured on the U64-II's
  sockets), run without it and stop again; the display is off meanwhile
  so open-bus reads never pass. The 8SID addresses come first, then
  `$D400-$D7E0`; at most 8.
- The shipped `.cfg` sets Heartbeat's SID addressing (UltiSID 1 `$D400`,
  UltiSID 2 `$D420`, Range Split 1/4 on A7/A8, no mirroring); the
  sockets stay as they are and play along where they share an address.
  With it the probe finds exactly the 8 UltiSIDs. The `.cfg` is applied
  when the cartridge is started from the Ultimate's file browser, not by
  REST `run_crt` (section 7).
- BBC mode's amplitude goes through the sustain level: a rising level
  retriggers the gate (2 ms attack to full, 6 ms decay to the level), so
  slow attacks in BBC envelopes come out as small steps. VICE's ENV3
  read-back does not follow the envelope; the U64's does (255 at -15).
- Read-back: on the split UltiSIDs the voice-3 read-back registers are
  shared by an UltiSID's four instances, so they cannot tell the
  instances apart; tests read back only SID 0.

## 7. Making sure there are 8 SIDs

The U64 applies the cartridge's `.cfg` (8SID layout, stereo mixer) only
when the cartridge is started from its file browser; after a power cycle
and a start over the network the layout is the default one and a probe
finds 3 SIDs. So `*SID SETUP` loads the layout (the `.cfg`'s `[SID
Addressing]` and `[Audio Mixer]` lines through "load config", as `*SID
PAN`), and start-up does the same when it finds fewer than 8 SIDs and the
command interface is there (errors ignored then). After a successful
load the list is set to the 8 known addresses (`$D400 $D420 $D480 $D4A0
$D500 $D520 $D580 $D5A0`) instead of probed: a split UltiSID's four parts
all read back the first part's oscillator, so the probe cannot see the
other three. Lasts until the Ultimate is reset.

The probe finds all eight at start-up (before the engine has run), but
not later (after `*SOUND NONE`, `*SOUND SID` would find 3). So
`snd_8sid` (`$03FD`, cleared by the KERNAL's RAMTAS at a cold start)
remembers the layout, set by `*SID SETUP` or by a probe that finds
exactly its eight addresses; every later setup then uses the eight
addresses.

## 8. Stereo and volume

The Ultimate's audio mixer has a volume and a stereo position for each
UltiSID (all four split instances of an UltiSID share them) and for each
SID socket; there is no setting per split instance.

- The shipped `.cfg` switches the UltiSIDs on (`Vol UltiSid 1/2 = -6 dB`;
  a U64 may have them OFF, so that only the SID sockets sound) and pans
  them as Heartbeat's does: UltiSID 1 `Left 3`, UltiSID 2
  `Right 3`. In the SID list (8SID order) SIDs 0, 2, 4, 6 are UltiSID 1's
  (left) and 1, 3, 5, 7 UltiSID 2's (right). The sockets keep the user's
  settings.
- From BASIC: `*SID PAN <unit> <-5..5>` and `*SID VOL <unit> <dB>|OFF`,
  unit `1`, `2` (UltiSIDs) or `S1`, `S2` (sockets). The MOS writes a
  two-line configuration file (`[Audio Mixer]`, `<item>=<value>`) to
  `/Temp/bbcmix.cfg` and sends the firmware's "load config" control
  command (`$04 $50` + path, firmware 3.15a), which applies it
  at once (not saved to flash) and answers with an error status for a
  line it cannot apply. There is no command to read mixer settings back.
- `*SID` lists the SIDs found.

## 9. Instruments and their defaults

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

## 10. SID mode

- SID mode is the start-up mode; `*SOUND BBC`/`SID` switch (all voices
  reset). 24 voices; the interrupt only spends time on voices that play
  or have queued notes.
- Pitch: one octave of 48 quarter-semitone frequencies (middle C's,
  PAL or NTSC) shifted per octave instead of a 256-entry table; SID-mode
  P is signed (Q = P + 235 >= 0, so down to P = -235), P >= 1024 a raw
  frequency x 16.
- Instruments 1-16 are the defaults from `tools/gensound.py` (data in
  bank 6), 17-64 copies of 1. ENVELOPE acts in BBC mode.

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
plays the same way. Amplitude -15..-1 sets the voice's sustain level
directly, with the voice's current instrument.

## 11. Ring modulation and sync

Ring modulation and hard sync (BELL, SYNC) take part of their sound from
the neighbouring voice of the same SID; with every voice busy that is an
unrelated part and they sound off key, so the demo does not use them.

## 12. The REU from the interrupt

SID mode reads instrument tables (`s_tget`) and song rows (`t_rowplay`)
from the REU in the interrupt. Every other REU user (the line editor's
history, fonts, palettes, the RAM disk, `*SRWRITE`/`*SRREAD`, OSWORD
&42, the network buffers) sets the REU's registers from the foreground
in several steps; an interrupt in between would leave its own address,
length and target behind, and the foreground transfer would go
elsewhere. Saving and restoring `$DF02-$DF0A` in the interrupt does not
work: the Ultimate's REU bank register reads back only its low 3 bits
($F8 + bank). So every foreground transfer sets the REU up with
interrupts off (`php`/`sei` ... the command, `plp`); `s_irq` uses the
REU freely. The SID image's ten
work bytes `s_dirty`..`s_tmpx` stay in SNDSHR. Test: `reu_irq`.
