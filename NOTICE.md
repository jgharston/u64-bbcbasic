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
faith for non-commercial hobby use (owner decision 2026-10-07). Rights
holders who object are asked to open an issue; `*FONT LOAD` works without
it.

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
