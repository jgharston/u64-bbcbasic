; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 5: the REU RAM disk (reudisk.s)
;
; ----------------------------------------------------------------------------

    icl 'reudisk.s'

bank5_end:
    .if bank5_end > $C000
    .error "Bank 5 overflows 16K"
    .endif
    :[$C000-*] dta $FF
