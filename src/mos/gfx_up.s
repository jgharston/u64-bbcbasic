; Drawing engine, Upic full variant (gfx.s with GXUL = 1, GXUP = 1),
; stored in bank 8 and copied to ENGINE when MODE 110 or 111 starts.
    .local gxup
GXUL = 1
GXUP = 1
    icl 'gfx.s'
    .endl
