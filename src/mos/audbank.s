; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 10: Ultimate Audio: samples (*SAMPLE, SOUND
; voices 24-30) and the MOD engine (*MODPLAY)
;
; Everything inside .local aud, with its own copy of the bank helpers
; (bankhelp.s). The REU area: docs/ARCHITECTURE.md 7.
;
; ----------------------------------------------------------------------------

    .local aud
    icl 'bankhelp.s'
    icl 'sample.s'
    icl 'modplay.s'
    .endl

bank10_end:
    .if bank10_end > $C000
    .error "Bank 10 overflows 16K"
    .endif
    :[$C000-*] dta $FF
