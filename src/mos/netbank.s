; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 7: network (docs/DESIGN_NETWORK.md)
;
; Everything here is inside .local net: its own copies of the helpers
; (bankhelp.s) and of the UCI driver (uci.s), because bank 2's read
; command payloads and texts from the bank that is mapped.
;
; ----------------------------------------------------------------------------

    .local net
    icl 'bankhelp.s'
    icl 'uci.s'
    icl 'netcmd.s'
    icl 'netchan.s'
    .endl

bank7_end:
    .if bank7_end > $C000
    .error "Bank 7 overflows 16K"
    .endif
    :[$C000-*] dta $FF
