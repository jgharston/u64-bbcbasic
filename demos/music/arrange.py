#!/usr/bin/env python3
"""Write the music demo's note files (demos/music/*.mml).

Arrangements for this project (GPL-3.0) of public-domain music
(docs/DESIGN_MUSICDEMO.md). Five pieces start from Mutopia Project
editions (MIDI files, https://www.mutopiaproject.org; public domain:
The Entertainer, Maple Leaf Rag, Toccata BWV 565, Greensleeves,
Eine kleine Nachtmusik KV 525), read with tools/mid2mml.py; Scarborough
Fair, Pachelbel's Canon and Ode to Joy are written out here.

Every block (bar) is checked: all voices must last as long as the bar.

    demos/music/arrange.py --mutopia DIR      (the downloaded .mid files)
    demos/music/arrange.py --instruments      (only the instrument choice)

The MIDI files, from https://www.mutopiaproject.org/ftp/ (DIR as named):
    green.mid        Traditional/greensleeves/greensleeves.mid
    entertainer.mid  JoplinS/entertainer/entertainer.mid
    maple.mid        JoplinS/maple/maple.mid
    toccata.mid      BachJS/BWV565/ToccataFugue/ToccataFugue.mid
    kv525/           MozartWA/KV525/MozartWA-KV525/MozartWA-KV525-mids.zip
                     (unzipped)

Voices: voice v is voice v MOD 3 of SID v DIV 3; SIDs 0, 2, 4, 6 play
left, 1, 3, 5, 7 right (DESIGN_SOUND.md section 8).
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))
import mid2mml as M  # noqa: E402

# instruments (DESIGN_SOUND.md section 9)
SQUARE, PIANO, ORGAN, STRINGS, BRASS, LEAD, BASS, FLUTE = range(1, 9)
PLUCK, BELL, KICK, SNARE, HIHAT, PAD, ARP, SYNC = range(9, 17)

# balance: melodies at full level on both UltiSIDs (left and right, so
# they sound in the middle), the rest clearly below them
MEL, SECOND, CHORD, ARPV, BASSV = 15, 9, 5, 6, 11

# the demo's own instruments (17-30), made with the engine's modulation
# (*INSTRUMENT, DESIGN_SOUND.md sections 9 and 11); each starts as a copy
# of 1, so a definition is complete; a piece's file defines the ones it uses
CUSTOM = {
    17: ["COPY 1 SAW ADSR 3 4 12 6", "VIB 18 2 6 FILTER LOW RES 2 CUT 150 NAME VIOLIN"],
    18: ["COPY 1 SAW ADSR 4 6 11 7", "VIB 20 2 5 FILTER LOW RES 4 CUT 90 NAME CELLO"],
    19: ["COPY 1 PULSE PW 500 10 12 2 ADSR 0 9 0 9 NAME HARPSI"],
    20: ["COPY 1 PULSE PW 2048 30 14 2 ADSR 9 6 11 8", "VIB 30 1 4 NAME CHOIR"],
    21: ["COPY 1 PULSE PW 1000 6 12 4 ADSR 0 10 3 8 FINE 6 NAME RAGPIANO"],
    22: ["COPY 1 PULSE PW 300 ADSR 0 7 0 6 NAME BANJO"],
    23: ["COPY 1 PULSE PW 1900 ADSR 2 4 12 5", "FILTER LOW RES 3 CUT 110 NAME CLARINET"],
    24: ["COPY 1 SAW ADSR 2 7 10 6 VIB 25 2 6", "FILTER LOW RES 5 CUT 50 6 170 50 STOP NAME TRUMPET"],
    25: ["COPY 3 ADSR 0 2 14 4 PW 1600 3 12 6", "VIB 40 1 3 NAME CHURCH"],
    26: ["COPY 1 TRI ADSR 0 9 0 9 WAVES 17 17 0", "ARP 12 0 SPEED 1 NAME GLOCK"],
    27: ["COPY 1 SAW ADSR 1 6 10 6 PORTA 20", "VIB 20 2 6 FILTER LOW CUT 140 NAME SLIDE"],
    28: ["COPY 1 PULSE PW 1024 ADSR 2 6 12 5", "FILTER LOW RES 6 CUT 40 NAME TUBA"],
    29: ["COPY 1 TRI ADSR 0 8 0 8 NAME STRBASS"],
    30: ["COPY 1 SAW ADSR 8 8 12 9 VIB 30 1 4", "FILTER LOW RES 4 CUT 60 1 140 60 NAME STRINGS2"],
}

# per piece: instruments 1-16 replaced (old: new), and voices that get
# their own (voice: new) whatever the plan gave them
PIECE_INSTR = {
    "greenslv": ({9: 19, 4: 20, 7: 18}, {3: 23}),
    "scarboro": ({10: 26, 14: 20, 7: 18}, {}),
    "entertnr": ({2: 21, 9: 22, 6: 27}, {}),
    "nachtmus": ({4: 17, 7: 18, 9: 19}, {}),
    "canon": ({4: 17, 7: 29, 14: 30, 3: 25}, {3: 18}),
    "toccata": ({3: 25, 5: 24}, {}),
    "odetojoy": ({3: 25, 5: 24, 4: 17, 15: 26}, {}),
    "maplelf": ({2: 21, 9: 22, 7: 28}, {}),
}


def apply_instruments(name, lines):
    """The piece's instrument choice on .mml lines: I<n> (n <= 16) of a
    voice replaced; #INSTRUMENT lines for the instruments 17+ it uses (after
    #VOICES; old ones dropped)"""
    remap, voices = PIECE_INSTR.get(name, ({}, {}))
    out, used = [], set()
    for line in lines:
        if line.startswith("#INSTRUMENT"):
            continue
        m = re.match(r"(\d+):(.*)", line)
        if m:
            v = int(m.group(1))

            def sub(mm):
                n = int(mm.group(1))
                if n <= 16:
                    n = voices.get(v, remap.get(n, n))
                if n >= 17:
                    used.add(n)
                return "I%d" % n
            line = "%d:%s" % (v, re.sub(r"I(\d+)", sub, m.group(2)))
        out.append(line)
    defs = ["#INSTRUMENT %d %s" % (n, part) for n in sorted(used) for part in CUSTOM[n]]
    k = next(i for i, l in enumerate(out) if l.startswith("#VOICES")) + 1
    return out[:k] + defs + out[k:]


LEN = {"1": 32, "2": 16, "4": 8, "8": 4, "16": 2, "32": 1}
HERE = os.path.dirname(os.path.abspath(__file__))


# ----------------------------------------------------------------------------
# Checking

def duration(text, state):
    """32nds of a voice's text in a block; state = {"L": default length}"""
    total, i = 0, 0
    while i < len(text):
        c = text[i].upper()
        i += 1
        if c in "OIV":
            while i < len(text) and text[i].isdigit():
                i += 1
            continue
        if c == "L":
            j = i
            while i < len(text) and text[i].isdigit():
                i += 1
            state["L"] = text[j:i]
            continue
        if c in "CDEFGABR":
            if i < len(text) and text[i] in "#+-":
                i += 1
            j = i
            while i < len(text) and text[i].isdigit():
                i += 1
            n = LEN[text[j:i] or state["L"]]
            if i < len(text) and text[i] == ".":
                n = n * 3 // 2
                i += 1
            if i < len(text) and text[i] == "&":
                i += 1
            total += n
    return total


class Piece:
    def __init__(self, name, title, composer, tempo, bar, hold_end=False):
        self.name, self.title, self.composer = name, title, composer
        self.hold_end = hold_end                    # last bar: its downbeat held
        self.tempo, self.bar = tempo, bar           # bar: 32nds per bar
        self.blocks = []                            # [{voice: text}]
        self.instr = {}

    def add(self, voice, texts, instrument=None, volume=None, start=None):
        """Bars of text for a voice, from block `start` (default: after
        the voice's last bar). The first bar sets the instrument."""
        if start is None:
            start = sum(1 for b in self.blocks if voice in b)
        for k, t in enumerate(texts):
            while len(self.blocks) <= start + k:
                self.blocks.append({})
            pre = ""
            if voice not in self.instr or (instrument and self.instr[voice] != instrument):
                if instrument:
                    pre += "I%d " % instrument
                    self.instr[voice] = instrument
            if volume is not None and k == 0:
                pre += "V%d " % volume
            self.blocks[start + k][voice] = (pre + t).strip()

    def rests(self, count):
        return ["R%s" % self.rest_len()] * count

    def rest_len(self):
        for v, s in M.LENGTHS:
            if v == self.bar:
                return s
        raise ValueError("bar length")

    def write(self):
        voices = sorted({v for b in self.blocks for v in b})
        # every voice gets every bar, a rest where it is silent: a voice
        # whose rests the player made up itself would start them late
        for b in self.blocks:
            for v in voices:
                if v not in b:
                    b[v] = "R" + self.rest_len()
        if self.hold_end:               # end on the cadence's chord
            last = self.blocks[-1]
            for v in voices:
                last[v] = hold_first(last[v], self.rest_len())
        state = {v: {"L": "4"} for v in voices}
        out = ["#TITLE " + self.title, "#COMPOSER " + self.composer,
               "#TEMPO %d" % self.tempo, "#VOICES %d" % (max(voices) + 1),
               "; arrangement: u64-bbcbasic (GPL-3.0); the music is public domain",
               ""]
        for n, b in enumerate(self.blocks):
            for v in sorted(b):
                d = duration(b[v], state[v])
                if d != self.bar:
                    raise SystemExit("%s: bar %d voice %d lasts %d/32, not %d: %s"
                                     % (self.name, n + 1, v, d, self.bar, b[v]))
                if len(b[v]) > 230:
                    raise SystemExit("%s: bar %d voice %d: line too long" % (self.name, n + 1, v))
                out.append("%d: %s" % (v, b[v]))
            out.append("")
        out = apply_instruments(self.name, out)
        with open(os.path.join(HERE, self.name + ".mml"), "w") as f:
            f.write("\n".join(out))
        print("%s: %d bars, voices %s" % (self.name, len(self.blocks), voices))


# ----------------------------------------------------------------------------
# From MIDI

def hold_first(text, length):
    """A bar's text reduced to its first note (or rest) held for the whole
    bar (length: e.g. "2" for 2/4): the commands before it are kept"""
    m = re.match(r"((?:\s*(?:[IVOL]\d+|[<>]))*)\s*([A-GR][#+-]?)", text)
    if not m:
        return text
    return ("%s %s%s" % (m.group(1).strip(), m.group(2), length)).strip()


def midi_lines(path, track, count, first, bars, transpose=0):
    m = M.Midi(path)
    unit = m.division // 8
    bar = 32 * m.timesig[0] // m.timesig[1]
    notes = [n for n in m.notes if n.track == track]
    return [M.bars(line, unit, bar, first, bars, transpose)
            for line in M.lines_of(notes, count)]


def shift(texts, octaves):
    """The same bars an octave or more higher/lower (O numbers changed)."""
    out = []
    for t in texts:
        toks = []
        for tok in t.split():
            if tok[0] == "O":
                tok = "O%d" % max(0, min(8, int(tok[1:]) + octaves))
            toks.append(tok)
        out.append(" ".join(toks))
    return out


def first_octave(texts, octave):
    """Make sure the first bar starts with an octave (bars taken from the
    middle of a line may not)."""
    if texts and not texts[0].startswith("O"):
        texts = ["O%d %s" % (octave, texts[0])] + texts[1:]
    return texts


def drums(piece, start, count, kick, snare, hat):
    """A beat: kick on the beats, snare on the off-beats, hi-hat eighths
    (2/4 or 4/4 bars)."""
    beats = piece.bar // 8
    k, s, h = [], [], []
    for _ in range(count):
        k.append(" ".join(["O2 C8 R8"] * beats))
        s.append(" ".join(["R4" if b % 2 == 0 else "O3 C8 R8" for b in range(beats)]))
        h.append(" ".join(["O6 C8"] * (beats * 2)))
    piece.add(kick, k, KICK, 10, start=start)
    piece.add(snare, s, SNARE, 8, start=start)
    piece.add(hat, h, HIHAT, 4, start=start)


# ----------------------------------------------------------------------------
# The pieces

def greensleeves(src):
    p = Piece("greenslv", "Greensleeves", "trad., 16th century", 96, 24)
    up = midi_lines(os.path.join(src, "green.mid"), 1, 2, 0, 17)
    lo = midi_lines(os.path.join(src, "green.mid"), 2, 2, 0, 17)
    for _ in range(2):
        p.add(0, up[0], FLUTE, MEL)              # melody, left and right
        p.add(3, up[0], FLUTE, MEL)
        p.add(1, lo[0], PLUCK, SECOND)           # lower part
        p.add(4, shift(lo[1], -1), BASS, BASSV)
        p.add(2, up[1], STRINGS, CHORD)
    # second time: the melody an octave up as well
    p.add(9, shift(up[0], 1), LEAD, SECOND, start=17)
    p.write()


def scarborough(_src):
    # D dorian, 3/4; melody by hand (traditional)
    p = Piece("scarboro", "Scarborough Fair", "traditional", 112, 24)
    mel = ["O4 D2 D4", "A2 A4", "E4. F8 E4", "D2.",
           "R4 A4 O5 C4", "D2 C4", "O4 A4 B4 G4", "A2.",
           "R4 O5 D2", "D2 C4", "O4 A4 A4 G4", "F4 E4 C4",
           "D4 A2", "G4 F4 E4", "D4 C4 E4", "D2."]
    chords = ["D", "D", "C", "D", "D", "D", "G", "A",
              "D", "C", "A", "C", "D", "G", "C", "D"]
    tones = {"D": ("D", "F", "A"), "C": ("C", "E", "G"), "G": ("G", "B", "D"),
             "A": ("A", "C", "E")}
    bass = ["O2 %s2." % c for c in chords]
    pad = ["O3 %s2." % tones[c][1] for c in chords]
    pad2 = ["O3 %s2." % tones[c][2] for c in chords]
    arp = ["O4 %s8 %s8 %s8 %s8 %s8 %s8" % (tones[c][0], tones[c][1], tones[c][2],
                                          tones[c][1], tones[c][0], tones[c][2])
           for c in chords]
    for rep in range(2):
        p.add(0, mel, FLUTE, MEL)
        p.add(3, mel, FLUTE, MEL)
        p.add(1, bass, BASS, BASSV)
        p.add(2, pad, PAD, CHORD)
        p.add(5, pad2, PAD, CHORD)
        p.add(6, shift(mel, 1) if rep else ["R2."] * 16, BELL, SECOND)
        p.add(4, arp, ARP, ARPV)
    p.write()


def entertainer(src):
    f = os.path.join(src, "entertainer.mid")
    p = Piece("entertnr", "The Entertainer", "Scott Joplin, 1902", 84, 16,
              hold_end=True)              # bar 36: the A strain's last C
    up = midi_lines(f, 1, 2, 0, 36)
    lo = midi_lines(f, 2, 2, 0, 36)
    again = midi_lines(f, 1, 1, 20, 16)[0]         # the repeat, converted fresh
    p.add(0, up[0], PIANO, MEL)                  # the tune, both sides
    p.add(3, up[0], PIANO, MEL)
    p.add(1, up[1], PIANO, SECOND)
    p.add(4, lo[0], PLUCK, SECOND)               # left hand
    p.add(2, lo[1], BASS, BASSV)
    # the repeat (bars 21-36) with a modern beat and the tune doubled
    drums(p, 20, 16, 9, 10, 11)
    p.add(6, ["R2"] * 20, LEAD, SECOND, start=0)
    p.add(6, shift(again, -1), start=20)
    p.write()


def nachtmusik(src):
    f = os.path.join(src, "kv525", "MozartWA-KV525-mov-01.mid")
    p = Piece("nachtmus", "Eine kleine Nachtmusik", "W. A. Mozart, 1787", 132, 32,
              hold_end=True)              # bar 18: back in G
    parts = [midi_lines(f, t, 1, 0, 18)[0] for t in (1, 2, 3, 4)]
    # violins I and II, viola, cello: strings left and right
    p.add(0, parts[0], STRINGS, MEL)
    p.add(3, parts[0], STRINGS, MEL)
    p.add(1, parts[1], STRINGS, SECOND)
    p.add(4, parts[1], STRINGS, SECOND)
    p.add(2, parts[2], STRINGS, 7)
    p.add(5, parts[2], STRINGS, 7)
    p.add(6, parts[3], STRINGS, SECOND)
    p.add(9, parts[3], STRINGS, SECOND)
    p.add(7, shift(parts[3], -1), BASS, BASSV)
    p.add(10, parts[3], PLUCK, CHORD)
    p.write()


def canon(_src):
    # Pachelbel's Canon in D: ground bass (8 quarter notes, 2 bars), three
    # violins in canon, two bars apart; then more and more voices to 24
    p = Piece("canon", "Canon in D", "Johann Pachelbel", 60, 32)
    ground = ["O2 D4 O1 A4 B4 F#4", "G4 D4 G4 A4"]
    chords = [("D", "F#", "A"), ("A", "C#", "E"), ("B", "D", "F#"), ("F#", "A", "C#"),
              ("G", "B", "D"), ("D", "F#", "A"), ("G", "B", "D"), ("A", "C#", "E")]
    lines = [
        ["O5 F#4 E4 D4 C#4", "O4 B4 A4 B4 O5 C#4"],
        ["O5 D4 C#4 O4 B4 A4", "G4 F#4 G4 E4"],
        ["O4 D8 F#8 A8 G8 F#8 D8 F#8 E8", "D8 O3 B8 O4 D8 A8 G8 B8 A8 G8"],
        ["O5 D16 C#16 D16 O4 D16 C#16 A16 E16 F#16 D16 O5 D16 C#16 O4 B16 O5 C#16 F#16 A16 B16",
         "G16 F#16 E16 G16 F#16 E16 D16 C#16 O4 B16 A16 G16 F#16 E16 G16 F#16 E16"],
    ]
    cycles = 12
    rest2 = ["R1", "R1"]

    def cyc(voice, texts, instr, vol, c):
        p.add(voice, texts, instr, vol, start=2 * c)

    # voice plan: (voice, from cycle, kind, instrument, volume)
    for c in range(cycles):
        cyc(0, ground, BASS, BASSV, c)                        # 1 the bass
        cyc(3, shift(ground, 1), STRINGS, SECOND, c)           # 2 cello
        cyc(6, shift(ground, 1), PLUCK, CHORD, c)              # 3
        for k, (voice, delay) in enumerate(((1, 1), (4, 2), (7, 3))):
            n = c - delay                                      # violins
            cyc(voice, lines[n % 4] if n >= 0 else rest2, STRINGS, MEL - k, c)
        def qs(octave, k):              # chord tone k, one per quarter
            return ["O%d " % octave + " ".join("%s4" % ch[k] for ch in chords[0:4]),
                    "O%d " % octave + " ".join("%s4" % ch[k] for ch in chords[4:8])]

        def eighths(octave, a, b):      # two chord tones per quarter
            return ["O%d " % octave + " ".join("%s8 %s8" % (ch[a], ch[b]) for ch in chords[0:4]),
                    "O%d " % octave + " ".join("%s8 %s8" % (ch[a], ch[b]) for ch in chords[4:8])]
        extra = [  # (voice, first cycle, texts, instrument, volume)
            (9, 4, shift(lines[c % 4], 1), FLUTE, 9),
            (2, 5, qs(4, 1), PAD, CHORD),
            (5, 5, qs(4, 2), PAD, CHORD),
            (10, 6, eighths(5, 0, 2), BELL, ARPV),
            (8, 6, shift(lines[(c + 1) % 4], 0), STRINGS, 9),
            (11, 7, ground, BASS, 9),
            (12, 7, qs(3, 0), ORGAN, CHORD),
            (13, 7, qs(4, 1), ORGAN, CHORD),
            (14, 8, shift(lines[(c + 2) % 4], 1), FLUTE, 8),
            (15, 8, shift(lines[c % 4], -1), STRINGS, 9),
            (16, 8, eighths(4, 2, 1), PLUCK, ARPV),
            (17, 9, shift(ground, 2), BRASS, 8),
            (18, 9, shift(lines[(c + 3) % 4], 0), LEAD, 8),
            (19, 9, qs(5, 0), STRINGS, 7),
            (20, 10, shift(lines[(c + 1) % 4], 1), SYNC, 7),
            (21, 10, qs(3, 2), PAD, CHORD),
            (22, 10, shift(lines[c % 4], 1), BELL, ARPV),
            (23, 11, shift(ground, 1), ORGAN, 8),
        ]
        for voice, first, texts, instr, vol in extra:
            cyc(voice, texts if c >= first else rest2, instr, vol, c)
    # the end: a D major chord on every voice
    tones = ["D", "F#", "A"]
    for v in range(24):
        p.add(v, ["O%d %s1" % (2 + (v % 4), tones[v % 3])], start=2 * cycles)
    p.write()


def toccata(src):
    f = os.path.join(src, "toccata.mid")
    p = Piece("toccata", "Toccata in D minor", "J. S. Bach, BWV 565", 66, 32,
              hold_end=True)              # bar 12: the D minor arrival
    rh = midi_lines(f, 1, 2, 0, 12)
    lh = midi_lines(f, 2, 2, 0, 12)
    ped = midi_lines(f, 3, 1, 0, 12)[0]
    plan = [(0, rh[0], 0, ORGAN, MEL), (3, rh[0], 0, ORGAN, MEL),
            (6, rh[0], 1, ORGAN, 10), (9, rh[0], -1, ORGAN, 10),
            (1, rh[1], 0, ORGAN, 10), (4, rh[1], 0, ORGAN, 10),
            (2, lh[0], 0, ORGAN, None), (5, lh[0], 0, ORGAN, None),
            (7, lh[0], -1, ORGAN, 10), (10, lh[0], 1, ORGAN, 9),
            (8, lh[1], 0, ORGAN, 10), (11, lh[1], 0, ORGAN, 10),
            (12, ped, 0, BASS, None), (15, ped, 0, BASS, None),
            (13, ped, 1, ORGAN, 10), (16, ped, 1, ORGAN, 10),
            (14, rh[0], 1, BRASS, 8), (17, rh[0], 1, BRASS, 8)]
    for voice, line, octs, instr, vol in plan:
        p.add(voice, shift(line, octs), instr, vol)
    p.write()


def ode(_src):
    # Ode to Joy (Beethoven, 9th symphony), in D; verse once quietly, then
    # with all 24 voices
    p = Piece("odetojoy", "Ode to Joy", "L. van Beethoven, 1824", 120, 32)
    mel = ["O4 F#4 F#4 G4 A4", "A4 G4 F#4 E4", "D4 D4 E4 F#4", "F#4. E8 E2",
           "F#4 F#4 G4 A4", "A4 G4 F#4 E4", "D4 D4 E4 F#4", "E4. D8 D2",
           "E4 E4 F#4 D4", "E4 F#8 G8 F#4 D4", "E4 F#8 G8 F#4 E4", "D4 E4 O3 A2",
           "O4 F#4 F#4 G4 A4", "A4 G4 F#4 E4", "D4 D4 E4 F#4", "E4. D8 D2"]
    ch = ["D", "A", "D", "A", "D", "A", "D", "AD",
          "A", "D", "A", "DA", "D", "A", "D", "AD"]
    T = {"D": ("D", "F#", "A"), "A": ("A", "C#", "E")}

    def chord_bars(idx, octave, fig):
        out = []
        for c in ch:
            if len(c) == 2:
                a, b = T[c[0]], T[c[1]]
                out.append(fig(a, octave, 2) + " " + fig(b, octave, 2))
            else:
                out.append(fig(T[c], octave, 1))
        return out

    def held(i):
        return lambda t, o, half: "O%d %s%d" % (o, t[i], 1 if half == 1 else 2)

    def arp(t, o, half):
        n = 4 // half
        notes = [t[0], t[1], t[2], t[1]] * 2
        return "O%d " % o + " ".join("%s8" % x for x in notes[:4 * (2 // half)])

    bass = chord_bars(0, 2, held(0))
    # verse 1: melody, bass, two string voices, arpeggio
    p.add(0, mel, FLUTE, MEL)
    p.add(3, mel, FLUTE, MEL)
    p.add(1, bass, BASS, BASSV)
    p.add(2, chord_bars(0, 3, held(1)), STRINGS, CHORD)
    p.add(5, chord_bars(0, 3, held(2)), STRINGS, CHORD)
    p.add(4, chord_bars(0, 4, arp), PLUCK, ARPV)
    # verse 2: everything
    full = [
        (0, mel, LEAD, MEL), (3, mel, BRASS, MEL), (6, shift(mel, 1), FLUTE, SECOND),
        (9, shift(mel, 1), SYNC, SECOND), (12, shift(mel, 2), BELL, ARPV),
        (15, shift(mel, -1), STRINGS, SECOND),
        (1, bass, BASS, BASSV), (4, shift(bass, -1), BASS, 8),
        (2, chord_bars(0, 3, held(1)), STRINGS, CHORD), (5, chord_bars(0, 3, held(2)), STRINGS, CHORD),
        (7, chord_bars(0, 4, held(0)), PAD, 4), (8, chord_bars(0, 4, held(1)), PAD, 4),
        (10, chord_bars(0, 4, held(2)), PAD, 4), (11, chord_bars(0, 3, held(0)), ORGAN, 4),
        (13, chord_bars(0, 4, arp), PLUCK, ARPV), (14, chord_bars(0, 5, arp), ARP, 4),
        (16, chord_bars(0, 3, held(1)), ORGAN, 4), (17, chord_bars(0, 3, held(2)), ORGAN, 4),
        (18, shift(mel, 0), PIANO, SECOND), (19, chord_bars(0, 2, held(0)), PIANO, 6),
    ]
    for voice, texts, instr, vol in full:
        p.add(voice, texts, instr, vol, start=16)
    drums(p, 16, 16, 20, 21, 22)
    p.add(23, ["R1"] * 16, BELL, ARPV, start=0)
    p.add(23, shift(mel, 1), start=16)
    p.write()


def maple(src):
    f = os.path.join(src, "maple.mid")
    p = Piece("maplelf", "Maple Leaf Rag", "Scott Joplin, 1899", 88, 16)
    up = midi_lines(f, 1, 2, 0, 32)
    lo = midi_lines(f, 2, 2, 0, 32)
    again = midi_lines(f, 1, 1, 16, 16)[0]
    p.add(0, up[0], PIANO, MEL)
    p.add(3, up[0], PIANO, MEL)
    p.add(1, up[1], PIANO, SECOND)
    p.add(4, lo[0], PLUCK, SECOND)
    p.add(2, lo[1], BASS, BASSV)
    drums(p, 16, 16, 9, 10, 11)
    p.add(6, ["R2"] * 16, LEAD, SECOND, start=0)
    p.add(6, shift(again, -1), start=16)
    # the A strain ends on A-flat: a bar of its chord to end on
    for voice, text in ((0, "O5 G#2"), (3, "O5 G#2"), (1, "O5 C2"), (4, "O4 D#2"),
                        (2, "O2 G#2"), (6, "O4 G#2"), (9, "O2 C2"), (10, "R2"),
                        (11, "R2")):
        p.add(voice, [text], start=32)
    p.write()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mutopia", help="directory with the .mid files")
    ap.add_argument("--instruments", action="store_true",
                    help="only apply the instrument choice to the .mml files there are")
    a = ap.parse_args()
    if a.instruments:
        for name in PIECE_INSTR:
            path = os.path.join(HERE, name + ".mml")
            with open(path) as f:
                lines = f.read().split("\n")
            with open(path, "w") as f:
                f.write("\n".join(apply_instruments(name, lines)))
            print(name)
        return
    if not a.mutopia:
        ap.error("--mutopia is needed to arrange")
    for f in (greensleeves, scarborough, entertainer, nachtmusik, canon,
              toccata, ode, maple):
        f(a.mutopia)


if __name__ == "__main__":
    sys.exit(main())
