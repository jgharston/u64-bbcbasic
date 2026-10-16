# PETSCII demo

`PETSCII.bas` shows U64 BBC BASIC's PETSCII mode (`*PETSCII`, `*ASCII`,
`*SEQ`; `*HELP *PETSCII`): the 16 colours by their PETSCII codes, a box
of PETSCII line graphics, the card suits, a drawing pad that echoes the
keys as PETSCII (GET gives PETSCII codes in this mode; the C= and SHIFT
graphics keys draw), and finally `IDI8B.seq` with `*SEQ IDI8B.SEQ LOWER`.

`IDI8B.seq`: the IDreamtIn8Bits logo by Xander Mol (made in Petmate,
lower case character set; from the idreamtin8bits.com site's assets).

Run it in its folder: `*DIR` to it, then `CHAIN "PETSCII"`.
