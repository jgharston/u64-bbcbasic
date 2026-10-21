; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 9: tools (the *SEDIT sprite editor, the Acorn
; compatibility commands, the DFS commands, the BASIC toolkit)
;
; Moved here from bank 7 (2026-10-16) to give the network room for HTTP
; (PLAN.md 27 item 7). Each module is a .local with its own copy of the
; bank helpers (bankhelp.s).
;
; ----------------------------------------------------------------------------

    icl 'sedit.s'
    icl 'acorn.s'
    icl 'dfs.s'
    icl 'toolkit.s'

    .local brw
    icl 'bankhelp.s'
    icl 'browse.s'
    .endl

bank9_end:
    .if bank9_end > $C000
    .error "Bank 9 overflows 16K"
    .endif
    :[$C000-*] dta $FF
