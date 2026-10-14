; Drawing engine, VIC-II bitmap variant (gfx.s with GXUL = 0), stored in
; bank 0 and copied to ENGINE at start-up and when a VIC-II mode returns.
    .local gxvic
GXUL = 0
GXUP = 0
    icl 'gfx.s'
    .endl
