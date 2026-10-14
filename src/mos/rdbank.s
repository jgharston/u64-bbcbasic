; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 5: the REU RAM disk (reudisk.s), snapshots
; (snapshot.s, inside .local snap with its own helpers)
;
; ----------------------------------------------------------------------------

    icl 'reudisk.s'
    icl 'snapshot.s'

bank5_end:
    .if bank5_end > $C000
    .error "Bank 5 overflows 16K"
    .endif
    :[$C000-*] dta $FF
