#!/usr/bin/env python3
"""Standard MIDI files to the music demo's note text (demos/music/*.mml).

A small reader for MIDI files (format 0 and 1: notes, tempo, time
signature) and the pieces needed to write the player's notation
(docs/DESIGN_MUSICDEMO.md section 3): note lines in bars, chords split
into single voices, note lengths as tied power-of-two lengths.

Used by demos/music/arrange.py; on its own it lists a file's tracks:

    tools/mid2mml.py file.mid
"""
import struct
import sys

NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
# lengths in 32nds -> notation (longest first)
LENGTHS = [(32, "1"), (24, "2."), (16, "2"), (12, "4."), (8, "4"),
           (6, "8."), (4, "8"), (3, "16."), (2, "16"), (1, "32")]


class Note:
    def __init__(self, start, end, pitch, track, channel):
        self.start, self.end, self.pitch = start, end, pitch
        self.track, self.channel = track, channel

    def __repr__(self):
        return "Note(%d-%d %s)" % (self.start, self.end, pitch_name(self.pitch))


class Midi:
    """notes (ticks), division (ticks per quarter), tempo (bpm of the
    first tempo event), time signature (first one), track names."""

    def __init__(self, path):
        data = open(path, "rb").read()
        if data[:4] != b"MThd":
            raise ValueError("not a MIDI file")
        hlen, self.format, ntrk, self.division = struct.unpack(">IHHH", data[4:14])
        pos = 8 + hlen
        self.notes, self.names = [], {}
        self.tempo, self.timesig = None, None
        for t in range(ntrk):
            if data[pos:pos + 4] != b"MTrk":
                raise ValueError("track %d: no MTrk" % t)
            tlen = struct.unpack(">I", data[pos + 4:pos + 8])[0]
            self._track(data[pos + 8:pos + 8 + tlen], t)
            pos += 8 + tlen
        self.notes.sort(key=lambda n: (n.start, -n.pitch))
        if self.tempo is None:
            self.tempo = 120.0
        if self.timesig is None:
            self.timesig = (4, 4)

    def _track(self, d, t):
        i, tick, status, on = 0, 0, 0, {}

        def varlen():
            nonlocal i
            v = 0
            while True:
                b = d[i]
                i += 1
                v = (v << 7) | (b & 0x7F)
                if b < 0x80:
                    return v
        while i < len(d):
            tick += varlen()
            b = d[i]
            if b >= 0x80:
                status = b
                i += 1
            if status == 0xFF:
                kind = d[i]
                i += 1
                n = varlen()
                body = d[i:i + n]
                i += n
                if kind == 0x51 and self.tempo is None:
                    self.tempo = 60e6 / int.from_bytes(body, "big")
                elif kind == 0x58 and self.timesig is None:
                    self.timesig = (body[0], 1 << body[1])
                elif kind == 0x03:
                    self.names[t] = body.decode("latin-1")
                continue
            if status in (0xF0, 0xF7):
                n = varlen()
                i += n
                continue
            kind, ch = status & 0xF0, status & 0x0F
            if kind in (0xC0, 0xD0):
                i += 1
                continue
            a, v = d[i], d[i + 1]
            i += 2
            if kind == 0x90 and v > 0:
                on.setdefault((ch, a), []).append(tick)
            elif kind in (0x80, 0x90):
                starts = on.get((ch, a))
                if starts:
                    s = starts.pop(0)
                    if tick > s:
                        self.notes.append(Note(s, tick, a, t, ch))


def pitch_name(p):
    return "%s%d" % (NAMES[p % 12], p // 12 - 1)


def lines_of(notes, count):
    """Split (possibly) chordal notes into `count` single-note lines: at
    each onset the highest note goes to line 0, the next to line 1...;
    a note still sounding when its line gets a new one is cut short."""
    lines = [[] for _ in range(count)]
    i = 0
    while i < len(notes):
        j = i
        while j < len(notes) and notes[j].start == notes[i].start:
            j += 1
        chord = sorted(notes[i:j], key=lambda n: -n.pitch)
        for k, n in enumerate(chord[:count]):
            line = lines[k]
            if line and line[-1].end > n.start:
                line[-1] = Note(line[-1].start, n.start, line[-1].pitch,
                                line[-1].track, line[-1].channel)
            line.append(n)
        i = j
    return lines


def split_len(n):
    """A length in 32nds as notation pieces (to be tied)."""
    out = []
    while n > 0:
        for v, s in LENGTHS:
            if v <= n:
                out.append((v, s))
                n -= v
                break
    return out


def bars(line, unit, bar, first, count, transpose=0):
    """The line (Notes in ticks) as `count` bars of note text, starting at
    bar `first` (0-based); unit = ticks per 32nd, bar = 32nds per bar.
    Notes crossing a bar line continue in the next bar, tied (&)."""
    t0 = first * bar
    end = t0 + count * bar
    events = []                                  # (start, len, pitch|None)
    pos = t0
    for n in line:
        s = round(n.start / unit)
        e = round(n.end / unit)
        if e <= t0 or s >= end:
            continue
        s, e = max(s, t0), min(e, end)
        if s < pos:
            s = pos
        if e <= s:
            continue
        if s > pos:
            events.append((pos, s - pos, None))
        events.append((s, e - s, n.pitch + transpose))
        pos = e
    if pos < end:
        events.append((pos, end - pos, None))
    out = [[] for _ in range(count)]
    octave = [None]

    def emit(b, length, pitch, tied):
        for k, (v, s) in enumerate(split_len(length)):
            if pitch is None:
                out[b].append("R" + s)
                continue
            o = pitch // 12 - 1
            tok = ""
            if octave[0] != o:
                tok = "O%d " % o
                octave[0] = o
            tok += NAMES[pitch % 12] + s
            if tied or k > 0:
                tok += "&"
            out[b].append(tok)
    for s, length, pitch in events:
        tied = False
        while length > 0:
            b = (s - t0) // bar
            room = (b + 1) * bar + t0 - s
            part = min(room, length)
            emit(b, part, pitch, tied)
            s += part
            length -= part
            tied = True
    return [" ".join(x) for x in out]


def main():
    m = Midi(sys.argv[1])
    print("format %d, division %d, tempo %.1f, time %d/%d" %
          (m.format, m.division, m.tempo, *m.timesig))
    tracks = sorted(set(n.track for n in m.notes))
    for t in tracks:
        ns = [n for n in m.notes if n.track == t]
        lo, hi = min(n.pitch for n in ns), max(n.pitch for n in ns)
        bar = m.division * 4 * m.timesig[0] // m.timesig[1]
        print("track %d %-20s %4d notes, %s-%s, bars %d-%d" % (
            t, m.names.get(t, ""), len(ns), pitch_name(lo), pitch_name(hi),
            ns[0].start // bar + 1, ns[-1].end // bar + 1))


if __name__ == "__main__":
    sys.exit(main())
