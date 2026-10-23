# Notice: what is covered by which licence

The cartridge images (`u64bbc-tmb.crt`, `u64bbc-ef.crt`) contain three kinds
of material.

## BBC BASIC 3.10 (cartridge bank 1)

BBC BASIC © 1982/1983 Acorn Computers and Sophie Wilson. The annotated MADS
source it is built from is Ivo van Poorten's
[ivop/bbc-basic](https://github.com/ivop/bbc-basic), based on J.G. Harston's
source reconstruction ([mdfs.net](https://mdfs.net/Software/BBCBasic/)). It
is used unchanged apart from a build target (`src/basic/u64-target.patch`);
`make compare-core` checks that the interpreter itself is identical to the
reference ROM.

This interpreter is **not** covered by this repository's GPL-3.0 licence.
Its current rights holder is unknown, and there is no formal open licence.
6502 BBC BASIC has been freely redistributed for decades (mdfs.net, the
Atari, Commander X16 and Ben Eater ports); this project does the same, in
good faith, for non-commercial hobby use. Rights holders who object are
asked to open an issue.

## BBC Micro character set (`src/acorn/bbcfont.bin`, bank 2)

The 8x8 glyphs of characters 32-127 behind `*FONT BBC`: 768 bytes from the
BBC Micro MOS 1.20 ROM (`&C000-&C2FF`), © 1981/1982 Acorn Computers. Taken
from the ROM image in Matt Godbolt's
[jsbeeb](https://github.com/mattgodbolt/jsbeeb) (`public/roms/os.rom`),
unchanged. Same status as the interpreter: not covered by this
repository's GPL-3.0 licence, no formal open licence, included in good
faith for non-commercial hobby use. Rights
holders who object are asked to open an issue; `*FONT LOAD` works without
it.

## The MOD player and the MODs (bank 10, `demos/audio`)

The MOD player (`src/mos/modengine.s`, its tables in `src/mos/modtables/`)
is a port to MADS of ModPlayer_16k by Freshness (6510nl),
[CSDb release 131522](https://csdb.dk/release/?id=131522). The two
ProTracker modules in `demos/audio` are "Forever Young" (`4ev.mod`),
remixed by Slice in 1995, and "Wild Perspective" (`wildpersp.mod`) by
Greg Tuby, 1996 (Amiga Music Workshop, Amiga Format). None of these has a
formal licence; like the interpreter they are not covered by this
repository's GPL-3.0 and are included in good faith, credited, for
non-commercial hobby use. Rights holders who object are asked to open an
issue.

## Graphics programs by others (`demos/archbas`, `demos/showcase/SHOW2`)

Eric Schraf's graphical BASIC programs (originals in QB64, shared on
[youtube.com/@Schraf](https://youtube.com/@Schraf)) and Aurel Wizzard's
Christmas tree, as converted for the Acorn Archimedes in
[ArchBAS](https://github.com/xahmol/ArchBAS) and then to BBC BASIC 3.10.
Each file names its original author. No formal licence; included in good
faith, credited, for non-commercial hobby use. Rights holders who object
are asked to open an issue.

## Free material

- The 4x6 font for modes with 4-pixel character cells (`src/fonts/4x6.bdf`): from the
  misc-fixed fonts, contributed by Janne V. Kujala, public domain.
- The sound effects (`demos/audio/*.WAV`): Juhani Junkala, CC0
  (`demos/audio/CREDITS.md`).
- The music demo's pieces (`demos/music`): public-domain music; five of
  them start from Mutopia Project editions placed in the public domain by
  their typesetters (`demos/music/arrange.py` lists them).
- The classic programs (`demos/classics`): zlib licence, see
  `demos/classics/LICENCE`.

## Everything else

The MOS (`src/mos/`), help texts (`src/help/`), tools, tests and
documentation: © 2026 Xander Mol, GPL-3.0 (see `LICENSE`).

The Ultimate command interface code (`src/mos/uci.s`, `src/mos/fs.s`) is a
6502 port of the protocol layer of
[ultimate-uci-oscar64](https://github.com/xahmol/ultimate-uci-oscar64)
(GPL-3.0), which is based on the Ultimate II DOS library by Scott Hutter and
Francesco Sblendorio, with fixes by Christian Gleissner.

The MOS design follows Ivo van Poorten's
[Atari port](https://github.com/ivop/atari-bbc-basic) (BSD-2).
