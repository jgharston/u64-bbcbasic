# ModPlayer_16k tables

`notelookupgls.bin` (1024 bytes: Amiga period -> note 1-36, bit 7 set
between notes) and `finetune.bin` (1152 bytes: 16 finetune rows of 36
periods, low bytes then high bytes) are the tables of ModPlayer_16k by
Freshness (6510nl), CSDb release 131522 (`Tools/`), unchanged. The MOS
puts them into the REU at &EE0200 at start-up (`src/mos/modplay.s`); the
MOD engine (`src/mos/modengine.s`) reads them there.
