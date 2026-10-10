# 3. Building from source

## 3.1 Requirements

[MADS](https://github.com/tebe6502/Mad-Assembler) 2.1.x (built with
FreePascal: `fpc -Mdelphi -vh -O3 mads.pas`), Python 3, GNU make,
`patch`. For the tests: VICE (`x64sc`) and Node.js (`npx`, for
c64bridge).

## 3.2 Building

```
git clone --recurse-submodules https://github.com/xahmol/u64-bbcbasic
cd u64-bbcbasic
make                # build/u64bbc-tmb.crt, build/u64bbc-ef.crt and .cfg
make compare-core   # BBC BASIC 3.10 still identical to the reference ROM
make vice           # run in VICE
make e2e            # end-to-end tests (tests/e2e/README.md)
make deploy         # install on the Ultimate (chapter 2)
make manual         # this manual, from docs/manual/src and the help texts
```

The interpreter is never changed: `lib/bbc-basic` is Ivo van Poorten's
source as a submodule, and the only difference is the build target
(`src/basic/u64-target.patch`); `make compare-core` checks it.

## 3.3 Where things are

| Path | Contents |
|---|---|
| `src/mos/` | the MOS in 6502 assembler (MADS): boot, VDU, keyboard, filing system, sound, network, line editor |
| `src/help/help.txt` | the `*HELP` texts (also this manual's reference sections) |
| `tools/` | the cartridge builder, tokeniser, help packer, remote tools |
| `demos/` | the demo programs |
| `tests/e2e/` | the end-to-end tests (VICE and the Ultimates) |
| `docs/` | design documents, the plan, this manual |
