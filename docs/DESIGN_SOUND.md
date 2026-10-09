# Design: sound (SID, up to 8 SIDs)

Status: decided 2026-10-09 (section 6); BBC mode is built first.

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
