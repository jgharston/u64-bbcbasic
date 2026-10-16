; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- MOS cartridge banks, one assembly
;
; Bank 0 (mos.s) and bank 2 (bank2.s) are assembled together so that
; symbols are shared across banks. The raw output holds bank 0 at offset
; $0000 and bank 2 at offset $4000; tools/mkcrt.py splits it into 16K
; banks; bank 3 (gxbank.s) follows at $8000. Bank 1 is BBC BASIC
; (build/basic.rom), banks 10+ the help texts (tools/genhelp.py).
;
; ----------------------------------------------------------------------------

    opt h-                      ; raw binary, no Atari header

    icl 'defs.s'

    org $8000                   ; bank 0, runs at $8000, stored at $0000
    icl 'mos.s'

    org $8000, $C000            ; bank 2, runs at $8000, stored at $4000
    icl 'bank2.s'

    org $8000, $8000            ; bank 3 (graphics), stored at $8000
    icl 'gxbank.s'

    org $8000, $C000            ; bank 4 (Upic Lite images)
    icl 'ulbank.s'

    org $8000, $C000            ; bank 5 (the REU RAM disk)
    icl 'rdbank.s'

    org $8000, $C000            ; bank 6 (sound)
    icl 'sndbank.s'

    org $8000, $C000            ; bank 7 (network)
    icl 'netbank.s'

    org $8000, $C000            ; bank 8 (Upic full)
    icl 'upbank.s'

    org $8000, $C000            ; bank 9 (tools: *EDIT, Acorn, DFS, toolkit)
    icl 'toolbank.s'
