; Drawing engine, Upic Lite variant (gfx.s with GXUL = 1), stored in bank 3
; and copied to ENGINE when a Upic Lite mode starts.
    .local gxul
GXUL = 1
GXUP = 0
    icl 'gfx.s'
    .endl
