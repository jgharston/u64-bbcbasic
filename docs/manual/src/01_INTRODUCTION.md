# 1. Introduction

U64 BBC BASIC is BBC BASIC 3.10, the BASIC of the Acorn BBC Micro, as a
cartridge for the Ultimate 64 and the C64 Ultimate. The interpreter is
the original, unchanged (built from Ivo van Poorten's annotated source,
checked byte for byte against the reference ROM). Around it sits a
BBC-style MOS (machine operating system), written for the C64 and the
Ultimate: the screen and its modes, the keyboard, sound on the SIDs,
files on the Ultimate's drives, the network, the REU.

The aim is that BBC BASIC *programs* run: the language, and what the
VDU, graphics, sound and file statements do. It is not a BBC Micro
emulator: the memory map, the BBC's hardware and machine code are not
reproduced.

What it adds for this machine: the Ultimate's turbo (BASIC runs many
times faster than on a BBC Micro), up to 24 SID voices with instruments
and a song player, the REU as storage and as a RAM disk, network
connections, and `*` commands for the Ultimate's drives, clock and
settings.

## 1.1 Help on the machine

Everything in this manual's reference sections is also on the machine:
`*HELP` and a keyword, a command or a topic.

```
*HELP PRINT
*HELP *CAT
*HELP KEYWORDS
```

## 1.2 Compared with a BBC Micro

@@help BBC

## 1.3 Credits

@@help CREDITS
