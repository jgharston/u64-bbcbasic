; Shapes, bank copy (gxshape.s with SHRAM = 0): VIC-II modes, through the
; trampoline.
    .local gxsb
SHRAM = 0
    icl 'gxshape.s'
    .endl
bk_shape = gxsb.bk_shape
