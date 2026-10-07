; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- shapes for PLOT (bank 3)
;
; Triangles, parallelograms, circles and ellipses, filled and outline, and
; the U64 outline codes for rectangles, triangles and parallelograms
; (docs/DESIGN_GRAPHICS.md section 9.4). This code works out edges and
; spans; the pixels are drawn by the engine in RAM (GX_RECT for spans,
; GX_PSET for points, GX_LINE for lines), so the slow part here (bank code
; runs at 1 MHz) is per row or per step, not per pixel.
;
; Assembled twice (SHRAM, set by the wrapper): in bank 3 for the VIC-II
; modes (gxs_bank.s, through the trampoline), and for $F300 in RAM for
; Upic Lite (gxs_ram.s, copied by ul_enter): there cartridge code would
; only get the renderer's spare time at 1 MHz. The RAM copy runs with the
; KERNAL out and interrupts off, and lets interrupts in now and then
; (sh_yield, core).
;
; Entered from the core (vdu_eng) after the engine has moved the graphics
; cursors (gc = new point, gp = previous, gq = the one before) and set
; ecol/eact for the plot code.
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; bk_shape
;   Summary: PLOT groups the engine leaves to this bank.
;   Input:   vdubuf = plot code k (k AND 3 <> 0); cursors gq, gp, gc.
;   Output:  the shape drawn.  Uses: A, X, Y, shape variables (core).
bk_shape:
    .if SHRAM
    jmp bks_go                  ; first byte: the core jumps to $F300
bks_go:
    .endif
    lda vdubuf
    lsr
    lsr
    lsr
    cmp #10
    beq bs_tri
    cmp #14
    beq bs_par
    cmp #18
    beq bs_circle
    cmp #19
    beq bs_circfill
    cmp #24
    beq bs_ellipse
    cmp #25
    beq bs_ellfill
    cmp #27
    beq bs_rectout
    cmp #28
    beq bs_triout
    cmp #30
    beq bs_parout
    rts                         ; arcs, flood fill, block copy: not yet
bs_tri:
    jsr sh_points
    jmp sh_trifill
bs_par:
    jsr sh_points
    jsr sh_corner4
    jsr sh_trifill              ; gq, gp, gc (sorts the slots)
    jsr sh_points               ; again: gq, p4, gc
    jsr sh_corner4
    jsr sh_swap4
    jmp sh_trifill
bs_circle:
    lda #0
    beq bs_circ
bs_circfill:
    lda #1
bs_circ:
    sta sh_fill
    jsr sh_circle_axes
    jmp sh_ellipse
bs_ellipse:
    lda #0
    beq bs_ell
bs_ellfill:
    lda #1
bs_ell:
    sta sh_fill
    jsr sh_ellipse_axes
    jmp sh_ellipse
bs_rectout:
    jsr sh_points               ; corners gp (0) and gc (2)
    lda sh_x+4                  ; point 1 = (x2, y0), point 3 = (x0, y2)
    sta sh_x+2
    lda sh_x+5
    sta sh_x+3
    lda sh_y
    sta sh_y+2
    lda sh_y+1
    sta sh_y+3
    lda sh_x
    sta sh_x+6
    lda sh_x+1
    sta sh_x+7
    lda sh_y+4
    sta sh_y+6
    lda sh_y+5
    sta sh_y+7
    lda #4
    jmp sh_polyline
bs_triout:
    jsr sh_points
    lda #3
    jmp sh_polyline
bs_parout:
    jsr sh_points
    jsr sh_corner4              ; 0 gq, 1 gp, 2 gc, 3 = gq - gp + gc
    lda #4
    jmp sh_polyline

; ----------------------------------------------------------------------------
; sh_points: device coordinates of gq, gp and gc into sh_x/sh_y 0, 1, 2
; (for a rectangle only 0 = gp and 2 = gc matter: gq is copied there too)
sh_points:
    ldx #0
    lda gqx
    ldy gqx+1
    jsr shp_x
    lda gqy
    ldy gqy+1
    jsr shp_y
    jsr shp_conv
    ldx #2
    lda gpx
    ldy gpx+1
    jsr shp_x
    lda gpy
    ldy gpy+1
    jsr shp_y
    jsr shp_conv
    ldx #4
    lda gcx
    ldy gcx+1
    jsr shp_x
    lda gcy
    ldy gcy+1
    jsr shp_y
    jsr shp_conv
    lda vdubuf                  ; rectangle outline: corners gp and gc
    lsr
    lsr
    lsr
    cmp #27
    bne shp_done
    lda sh_x+2
    sta sh_x
    lda sh_x+3
    sta sh_x+1
    lda sh_y+2
    sta sh_y
    lda sh_y+3
    sta sh_y+1
shp_done:
    rts
shp_x:
    sta pk_x
    sty pk_x+1
    rts
shp_y:
    sta pk_y
    sty pk_y+1
    rts
shp_conv:                       ; pk -> device, into slot X
    stx sh_i
    ldx #GX_TODEV
    jsr gx_call
    ldx sh_i
    lda ex
    sta sh_x,x
    lda ex+1
    sta sh_x+1,x
    lda ey
    sta sh_y,x
    lda ey+1
    sta sh_y+1,x
    rts

; sh_corner4: slot 3 = slot 0 - slot 1 + slot 2 (the BBC's fourth corner)
sh_corner4:
    ldx #0
    jsr sc4_one
    ldx #sh_y-sh_x
sc4_one:
    lda sh_x,x
    sec
    sbc sh_x+2,x
    sta sh_x+6,x
    lda sh_x+1,x
    sbc sh_x+3,x
    sta sh_x+7,x
    lda sh_x+6,x
    clc
    adc sh_x+4,x
    sta sh_x+6,x
    lda sh_x+7,x
    adc sh_x+5,x
    sta sh_x+7,x
    rts

; sh_swap4: slot 1 <-> slot 3 (second triangle of a parallelogram)
sh_swap4:
    ldx #1
ss4_loop:
    lda sh_x+2,x
    ldy sh_x+6,x
    sta sh_x+6,x
    tya
    sta sh_x+2,x
    lda sh_y+2,x
    ldy sh_y+6,x
    sta sh_y+6,x
    tya
    sta sh_y+2,x
    dex
    bpl ss4_loop
    rts

; sh_polyline: lines through slots 0 .. A-1 and back to 0, each without
; its last point, so EOR plotting touches every corner once
sh_polyline:
    sta sh_n
    lda #0
    sta sh_i
spl_loop:
    lda sh_i
    asl
    tax                         ; from slot i
    lda sh_x,x
    sta eline_x0
    lda sh_x+1,x
    sta eline_x0+1
    lda sh_y,x
    sta eline_y0
    lda sh_y+1,x
    sta eline_y0+1
    inx                         ; to slot i + 1 (or 0)
    inx
    txa
    lsr
    cmp sh_n
    bcc spl_to
    ldx #0
spl_to:
    lda sh_x,x
    sta eline_x1
    lda sh_x+1,x
    sta eline_x1+1
    lda sh_y,x
    sta eline_y1
    lda sh_y+1,x
    sta eline_y1+1
    lda #4                      ; omit the last point
    sta eflags
    ldx #GX_LINE
    jsr gx_call
    inc sh_i
    lda sh_i
    cmp sh_n
    bcc spl_loop
    rts

; ----------------------------------------------------------------------------
; sh_trifill
;   Summary: filled triangle through slots 0, 1, 2 (device pixels).
;   Function: sorts the corners by y, then walks the long edge (top to
;            bottom) and the two short ones in 16.16 fixed point, one span
;            per row (GX_RECT clips to the graphics window).
;   Uses:    A, X, Y, shape variables.
sh_trifill:
    ldx #0                      ; sort by y: slots 0 <= 1 <= 2
    ldy #2
    jsr st_order
    ldx #2
    ldy #4
    jsr st_order
    ldx #0
    ldy #2
    jsr st_order
    ; long edge: 0 -> 2 (edge A); short: 0 -> 1, then 1 -> 2 (edge B)
    ldx #0
    ldy #4
    lda #0
    jsr st_edge                 ; edge A from slot 0 to slot 2
    ldx #0
    ldy #2
    lda #8
    jsr st_edge                 ; edge B from slot 0 to slot 1
    lda sh_y                    ; y = y0
    sta sh_cy
    lda sh_y+1
    sta sh_cy+1
st_row:
    lda sh_cy                   ; at y1: edge B becomes 1 -> 2
    cmp sh_y+2
    bne st_nob
    lda sh_cy+1
    cmp sh_y+3
    bne st_nob
    ldx #2
    ldy #4
    lda #8
    jsr st_edge
st_nob:
    jsr st_span
    lda sh_cy                   ; last row: y2
    cmp sh_y+4
    bne st_next
    lda sh_cy+1
    cmp sh_y+5
    beq st_done
st_next:
    inc sh_cy
    bne st_step
    inc sh_cy+1
st_step:
    .if SHRAM
    jsr sh_yield
    .endif
    ldx #0                      ; x += slope, both edges
    jsr st_add
    ldx #8
    jsr st_add
    jmp st_row
st_done:
    rts

; st_add: edge X (0 = A, 8 = B): 32-bit x += 32-bit slope
st_add:
    clc
    lda sh_ex,x
    adc sh_ex+4,x
    sta sh_ex,x
    lda sh_ex+1,x
    adc sh_ex+5,x
    sta sh_ex+1,x
    lda sh_ex+2,x
    adc sh_ex+6,x
    sta sh_ex+2,x
    lda sh_ex+3,x
    adc sh_ex+7,x
    sta sh_ex+3,x
    rts

; st_span: row sh_cy from the integer parts of both edges' x
st_span:
    lda sh_ex+2                 ; edge A x (16.16: bytes 2-3)
    sta erx0
    lda sh_ex+3
    sta erx0+1
    lda sh_ex+10                ; edge B x
    sta erx1
    lda sh_ex+11
    sta erx1+1
    lda sh_cy
    sta ery0
    sta ery1
    lda sh_cy+1
    sta ery0+1
    sta ery1+1
    ldx #GX_RECT                ; orders and clips the corners itself
    jmp gx_call

; st_order: make slot X's y <= slot Y's y (swapping both coordinates)
st_order:
    lda sh_y,y                  ; y(Y) - y(X), signed: negative -> swap
    cmp sh_y,x
    lda sh_y+1,y
    sbc sh_y+1,x
    bvc sto_v
    eor #$80
sto_v:
    bpl sto_ok
    lda sh_x,x
    pha
    lda sh_x,y
    sta sh_x,x
    pla
    sta sh_x,y
    lda sh_x+1,x
    pha
    lda sh_x+1,y
    sta sh_x+1,x
    pla
    sta sh_x+1,y
    lda sh_y,x
    pha
    lda sh_y,y
    sta sh_y,x
    pla
    sta sh_y,y
    lda sh_y+1,x
    pha
    lda sh_y+1,y
    sta sh_y+1,x
    pla
    sta sh_y+1,y
sto_ok:
    rts

; st_edge
;   Summary: set up edge A (A = 0) or B (A = 8) from slot X to slot Y:
;            x = x(X) in 16.16 (+ 0.5 for rounding), slope = dx * 65536 / dy
;            (0 if dy = 0).
st_edge:
    sta sh_e
    stx sh_i
    sty sh_j
    ldy sh_e                    ; x = x(X) . $8000
    lda #0
    sta sh_ex,y
    lda #$80
    sta sh_ex+1,y
    lda sh_x,x
    sta sh_ex+2,y
    lda sh_x+1,x
    sta sh_ex+3,y
    ldy sh_j                    ; dy = y(Y) - y(X) (>= 0: sorted)
    lda sh_y,y
    sec
    sbc sh_y,x
    sta sh_dv
    lda sh_y+1,y
    sbc sh_y+1,x
    sta sh_dv+1
    lda sh_x,y                  ; dx = x(Y) - x(X)
    sec
    sbc sh_x,x
    sta sh_nm+2
    lda sh_x+1,y
    sbc sh_x+1,x
    sta sh_nm+3
    lda #0
    sta sh_nm
    sta sh_nm+1
    lda sh_dv
    ora sh_dv+1
    bne ste_div
    ldy sh_e                    ; dy = 0: slope 0
    lda #0
    sta sh_ex+4,y
    sta sh_ex+5,y
    sta sh_ex+6,y
    sta sh_ex+7,y
    rts
ste_div:
    lda sh_nm+3                 ; sign of dx
    sta sh_sg
    bpl ste_pos
    jsr sh_neg32
ste_pos:
    jsr sh_div32                ; sh_nm = |dx| * 65536 / dy
    lda sh_sg
    bpl ste_store
    jsr sh_neg32
ste_store:
    ldy sh_e
    lda sh_nm
    sta sh_ex+4,y
    lda sh_nm+1
    sta sh_ex+5,y
    lda sh_nm+2
    sta sh_ex+6,y
    lda sh_nm+3
    sta sh_ex+7,y
    rts

; sh_neg32: sh_nm = -sh_nm
sh_neg32:
    ldx #0
    ldy #4
    sec
sn_loop:
    lda #0
    sbc sh_nm,x
    sta sh_nm,x
    inx
    dey
    bne sn_loop
    rts

; sh_div32: sh_nm (32 bits, unsigned) / sh_dv (16 bits) -> sh_nm
sh_div32:
    lda #0
    sta sh_rm
    sta sh_rm+1
    ldx #32
shd_loop:
    asl sh_nm
    rol sh_nm+1
    rol sh_nm+2
    rol sh_nm+3
    rol sh_rm
    rol sh_rm+1
    lda sh_rm
    sec
    sbc sh_dv
    tay
    lda sh_rm+1
    sbc sh_dv+1
    bcc shd_next
    sta sh_rm+1
    sty sh_rm
    inc sh_nm
shd_next:
    dex
    bne shd_loop
    rts

; ----------------------------------------------------------------------------
; Circles and ellipses: centre (sh_cx, sh_cy) and semi-axes (sh_rx, sh_ry)
; in device pixels, then sh_ellipse.

; sh_circle_axes: centre gp, radius |gc - gp| in OS units; the radius in
; pixels per axis follows the mode (VIC-II BBC modes: x / 4, y * 25 / 128,
; so the circle stays round on screen)
sh_circle_axes:
    lda gcx                     ; dx, dy (OS units)
    sec
    sbc gpx
    sta sh_nm
    lda gcx+1
    sbc gpx+1
    sta sh_nm+1
    lda gcy
    sec
    sbc gpy
    sta sh_nm+2
    lda gcy+1
    sbc gpy+1
    sta sh_nm+3
    jsr sh_hypot                ; sh_r = sqrt(dx^2 + dy^2)
    lda gpx                     ; centre
    ldy gpx+1
    jsr shp_x
    lda gpy
    ldy gpy+1
    jsr shp_y
    ldx #GX_TODEV
    jsr gx_call
    jsr sh_centre
    lda sh_r                    ; radius in OS units -> pixels: as a point
    sta pk_x                    ; offset from the origin, both axes
    lda sh_r+1
    sta pk_x+1
    lda sh_r
    sta pk_y
    lda sh_r+1
    sta pk_y+1
    jmp sh_axes

; sh_ellipse_axes: centre gq; semi-axes |gp.x - gq.x| and |gc.y - gq.y|
; (the BBC Master's ellipse; the shear of gc.x is not applied yet)
sh_ellipse_axes:
    lda gqx
    ldy gqx+1
    jsr shp_x
    lda gqy
    ldy gqy+1
    jsr shp_y
    ldx #GX_TODEV
    jsr gx_call
    jsr sh_centre
    lda gpx
    sec
    sbc gqx
    sta pk_x
    lda gpx+1
    sbc gqx+1
    sta pk_x+1
    bpl sea_xpos
    jsr sh_negpkx
sea_xpos:
    lda gcy
    sec
    sbc gqy
    sta pk_y
    lda gcy+1
    sbc gqy+1
    sta pk_y+1
    bpl sh_axes
    lda #0
    sec
    sbc pk_y
    sta pk_y
    lda #0
    sbc pk_y+1
    sta pk_y+1

; sh_axes: semi-axes (pk_x, pk_y, OS units >= 0) -> sh_rx, sh_ry pixels:
; the device position of (pk_x, pk_y) relative to that of (0, 0), with
; the graphics origin taken out
sh_axes:
    lda pk_x
    pha
    lda pk_x+1
    pha
    lda pk_y
    pha
    lda pk_y+1
    pha
    lda #0
    sta pk_x
    sta pk_x+1
    sta pk_y
    sta pk_y+1
    ldx #GX_TODEV
    jsr gx_call
    lda ex
    sta sh_rx
    lda ex+1
    sta sh_rx+1
    lda ey
    sta sh_ry
    lda ey+1
    sta sh_ry+1
    pla
    sta pk_y+1
    pla
    sta pk_y
    pla
    sta pk_x+1
    pla
    sta pk_x
    ldx #GX_TODEV
    jsr gx_call
    lda ex                      ; rx = x(r) - x(0)
    sec
    sbc sh_rx
    sta sh_rx
    lda ex+1
    sbc sh_rx+1
    sta sh_rx+1
    lda sh_ry                   ; ry = y(0) - y(r) (device y is down)
    sec
    sbc ey
    sta sh_ry
    lda sh_ry+1
    sbc ey+1
    sta sh_ry+1
    ldx #sh_rx-sh_rx            ; clamp both to 0 .. 2047
    jsr sa_clamp
    ldx #sh_ry-sh_rx
sa_clamp:
    lda sh_rx+1,x
    bpl sac_pos
    lda #0
    sta sh_rx,x
    sta sh_rx+1,x
    rts
sac_pos:
    cmp #8
    bcc sac_ok
    lda #<2047
    sta sh_rx,x
    lda #>2047
    sta sh_rx+1,x
sac_ok:
    rts

sh_centre:
    lda ex
    sta sh_cx
    lda ex+1
    sta sh_cx+1
    lda ey
    sta sh_cy
    lda ey+1
    sta sh_cy+1
    rts

sh_negpkx:
    lda #0
    sec
    sbc pk_x
    sta pk_x
    lda #0
    sbc pk_x+1
    sta pk_x+1
    rts

; sh_hypot: sh_r = sqrt(dx^2 + dy^2), dx = sh_nm/+1, dy = sh_nm+2/+3
; (signed 16 bits each); squares and sum in 32 bits, then a bitwise root
sh_hypot:
    ldx #0
    jsr shh_abs
    ldx #2
    jsr shh_abs
    lda sh_nm                   ; m48 slots: A = dx^2, B = dy^2
    ldy sh_nm+1
    jsr m_sq16
    ldx #MR_A
    jsr m_store_t
    lda sh_nm+2
    ldy sh_nm+3
    jsr m_sq16
    ldx #MR_B
    jsr m_store_t
    ldx #MR_A
    ldy #MR_B
    jsr m_add                   ; A = dx^2 + dy^2 (< 2^31)
    jmp m_sqrt                  ; sh_r = sqrt(A)
shh_abs:
    lda sh_nm+1,x
    bpl shh_ok
    lda #0
    sec
    sbc sh_nm,x
    sta sh_nm,x
    lda #0
    sbc sh_nm+1,x
    sta sh_nm+1,x
shh_ok:
    rts

; ----------------------------------------------------------------------------
; sh_ellipse
;   Summary: midpoint ellipse, outline (sh_fill = 0: four points per step)
;            or filled (one span per row, each row once, so EOR works).
;   Function: the usual two regions (where the slope is above / below 1),
;            decision values in 48-bit integers (semi-axes up to 2047).
;            Region 2 starts with p = ry^2 (x^2 + x) + rx^2 (y - 1)^2 -
;            rx^2 ry^2 (the integer form of the half-pixel start).
;   Input:   sh_cx/cy, sh_rx/ry (pixels), sh_fill, ecol/eact.
;   Uses:    A, X, Y, m48 slots.
sh_ellipse:
    lda sh_rx                   ; rx2 = rx^2, ry2 = ry^2
    ldy sh_rx+1
    jsr m_sq16
    ldx #MR_RX2
    jsr m_store_t
    lda sh_ry
    ldy sh_ry+1
    jsr m_sq16
    ldx #MR_RY2
    jsr m_store_t
    ldx #MR_TRX2                ; 2 rx2, 2 ry2
    ldy #MR_RX2
    jsr m_mov
    ldx #MR_TRX2
    jsr m_shl
    ldx #MR_TRY2
    ldy #MR_RY2
    jsr m_mov
    ldx #MR_TRY2
    jsr m_shl
    lda #0                      ; x = 0, y = ry
    sta sh_ex2
    sta sh_ex2+1
    lda sh_ry
    sta sh_ey2
    lda sh_ry+1
    sta sh_ey2+1
    ldx #MR_PX                  ; px = 0
    jsr m_clr
    ldx #MR_PY                  ; py = 2 rx2 * y
    ldy #MR_TRX2
    lda sh_ey2
    sta m_t24
    lda sh_ey2+1
    sta m_t24+1
    lda #0
    sta m_t24+2
    jsr m_mul24
    ; p = ry2 - rx2 * ry + rx2 / 4 = ry2 - py / 2 + rx2 / 4
    ldx #MR_P
    ldy #MR_RY2
    jsr m_mov
    ldx #MR_T
    ldy #MR_PY
    jsr m_mov
    ldx #MR_T
    jsr m_shr
    ldx #MR_P
    ldy #MR_T
    jsr m_sub
    ldx #MR_T
    ldy #MR_RX2
    jsr m_mov
    ldx #MR_T
    jsr m_shr
    ldx #MR_T
    jsr m_shr
    ldx #MR_P
    ldy #MR_T
    jsr m_add
se_r1:                          ; region 1: while px < py
    .if SHRAM
    jsr sh_yield
    .endif
    ldx #MR_PX
    ldy #MR_PY
    jsr m_cmp                   ; C = 0 if px < py
    bcs se_r2init
    lda sh_fill
    bne se_r1f
    jsr se_plot4
se_r1f:
    inc sh_ex2                  ; x + 1; px += 2 ry2
    bne se_r1x
    inc sh_ex2+1
se_r1x:
    ldx #MR_PX
    ldy #MR_TRY2
    jsr m_add
    ldx #MR_P                   ; p < 0?
    jsr m_neg
    bcs se_r1neg
    lda sh_fill                 ; y goes down: rows +-y done (width x - 1)
    beq se_r1y
    jsr se_rowsprev
se_r1y:
    jsr se_ydec
    ldx #MR_PY                  ; py -= 2 rx2; p += ry2 + px - py
    ldy #MR_TRX2
    jsr m_sub
    ldx #MR_P
    ldy #MR_PY
    jsr m_sub
se_r1neg:
    ldx #MR_P                   ; p += ry2 + px
    ldy #MR_RY2
    jsr m_add
    ldx #MR_P
    ldy #MR_PX
    jsr m_add
    jmp se_r1
se_r2init:
    ; p = ry2 (x^2 + x) + rx2 (y - 1)^2 - rx2 ry2
    lda sh_ex2                  ; T = x^2 + x (24 bits)
    ldy sh_ex2+1
    jsr m_sq16
    lda sh_ex2
    clc
    adc m_sq
    sta m_t24
    lda sh_ex2+1
    adc m_sq+1
    sta m_t24+1
    lda #0
    adc m_sq+2
    sta m_t24+2
    ldx #MR_P                   ; p = ry2 * T
    ldy #MR_RY2
    jsr m_mul24
    lda sh_ey2                  ; T = (y - 1)^2
    sec
    sbc #1
    tax
    lda sh_ey2+1
    sbc #0
    bpl se_r2y
    lda #0                      ; y = 0: (y - 1)^2 = 1
    ldx #1
se_r2y:
    tay
    txa
    jsr m_sq16
    lda m_sq
    sta m_t24
    lda m_sq+1
    sta m_t24+1
    lda m_sq+2
    sta m_t24+2
    ldx #MR_T                   ; p += rx2 * T
    ldy #MR_RX2
    jsr m_mul24
    ldx #MR_P
    ldy #MR_T
    jsr m_add
    lda sh_ry                   ; p -= rx2 * ry2: T = rx2 * ry
    sta m_t24
    lda sh_ry+1
    sta m_t24+1
    lda #0
    sta m_t24+2
    ldx #MR_T
    ldy #MR_RX2
    jsr m_mul24
    lda sh_ry                   ; ... * ry again
    sta m_t24
    lda sh_ry+1
    sta m_t24+1
    ldx #MR_T2
    ldy #MR_T
    jsr m_mul24
    ldx #MR_P
    ldy #MR_T2
    jsr m_sub
se_r2:                          ; region 2: while y >= 0
    .if SHRAM
    jsr sh_yield
    .endif
    lda sh_ey2+1
    bmi se_done
    lda sh_fill
    bne se_r2f
    jsr se_plot4
    jmp se_r2y2
se_r2f:
    jsr se_rows                 ; rows +-y, width x
se_r2y2:
    jsr se_ydec
    ldx #MR_PY                  ; py -= 2 rx2
    ldy #MR_TRX2
    jsr m_sub
    ldx #MR_P                   ; p > 0?
    jsr m_pos
    bcc se_r2x
    ldx #MR_P                   ; p += rx2 - py
    ldy #MR_RX2
    jsr m_add
    ldx #MR_P
    ldy #MR_PY
    jsr m_sub
    jmp se_r2
se_r2x:
    inc sh_ex2                  ; x + 1; px += 2 ry2; p += rx2 - py + px
    bne se_r2x2
    inc sh_ex2+1
se_r2x2:
    ldx #MR_PX
    ldy #MR_TRY2
    jsr m_add
    ldx #MR_P
    ldy #MR_RX2
    jsr m_add
    ldx #MR_P
    ldy #MR_PY
    jsr m_sub
    ldx #MR_P
    ldy #MR_PX
    jsr m_add
    jmp se_r2
se_done:
    rts

se_ydec:
    lda sh_ey2
    bne sey_lo
    dec sh_ey2+1
sey_lo:
    dec sh_ey2
    rts

; se_plot4: (cx +- x, cy +- y), each distinct point once
se_plot4:
    lda #0
    sta sh_i                    ; bit 0: -x, bit 1: -y
sp4_loop:
    lda sh_i                    ; skip -x when x = 0, -y when y = 0
    and #1
    beq sp4_x
    lda sh_ex2
    ora sh_ex2+1
    beq sp4_next
sp4_x:
    lda sh_i
    and #2
    beq sp4_y
    lda sh_ey2
    ora sh_ey2+1
    beq sp4_next
sp4_y:
    lda sh_i
    and #1
    jsr sh_cxpm                 ; ex = cx +- x
    lda sh_i
    and #2
    jsr sh_cypm                 ; ey = cy +- y
    ldx #GX_PSET
    jsr gx_call
sp4_next:
    inc sh_i
    lda sh_i
    cmp #4
    bne sp4_loop
    rts

; sh_cxpm: ex = cx + x (A = 0) or cx - x (A <> 0); sh_cypm likewise ey
sh_cxpm:
    tax
    beq scx_add
    lda sh_cx
    sec
    sbc sh_ex2
    sta ex
    lda sh_cx+1
    sbc sh_ex2+1
    sta ex+1
    rts
scx_add:
    lda sh_cx
    clc
    adc sh_ex2
    sta ex
    lda sh_cx+1
    adc sh_ex2+1
    sta ex+1
    rts
sh_cypm:
    tax
    beq scy_add
    lda sh_cy
    sec
    sbc sh_ey2
    sta ey
    lda sh_cy+1
    sbc sh_ey2+1
    sta ey+1
    rts
scy_add:
    lda sh_cy
    clc
    adc sh_ey2
    sta ey
    lda sh_cy+1
    adc sh_ey2+1
    sta ey+1
    rts

; se_rows: spans cy - y and cy + y (once if y = 0), from cx - x to cx + x;
; se_rowsprev: the same with x - 1 (region 1: x has already moved on)
se_rowsprev:
    lda sh_ex2
    bne serp_lo
    dec sh_ex2+1
serp_lo:
    dec sh_ex2
    jsr se_rows
    inc sh_ex2
    bne serp_done
    inc sh_ex2+1
serp_done:
    rts
se_rows:
    lda #1
    jsr sh_cxpm
    lda ex
    sta erx0
    lda ex+1
    sta erx0+1
    lda #0
    jsr sh_cxpm
    lda ex
    sta erx1
    lda ex+1
    sta erx1+1
    lda #1
    jsr sh_cypm
    jsr ser_span
    lda sh_ey2
    ora sh_ey2+1
    beq ser_done
    lda #0
    jsr sh_cypm
ser_span:
    lda ey
    sta ery0
    sta ery1
    lda ey+1
    sta ery0+1
    sta ery1+1
    lda erx0                    ; GX_RECT may reorder the corners: keep
    pha                         ; them for the second row
    lda erx0+1
    pha
    lda erx1
    pha
    lda erx1+1
    pha
    ldx #GX_RECT
    jsr gx_call
    pla
    sta erx1+1
    pla
    sta erx1
    pla
    sta erx0+1
    pla
    sta erx0
ser_done:
    rts

; ----------------------------------------------------------------------------
; 48-bit arithmetic on slots of m48 (core), 6 bytes each, little endian,
; two's complement. X, Y = slot offsets (MR_*).

m_clr:
    lda #0
    ldy #6
mc_loop:
    sta m48,x
    inx
    dey
    bne mc_loop
    rts

m_mov:                          ; X = Y
    lda #6
    sta m_n
mm_loop:
    lda m48,y
    sta m48,x
    inx
    iny
    dec m_n
    bne mm_loop
    rts

m_add:                          ; X += Y
    lda #6
    sta m_n
    clc
ma_loop:
    lda m48,x
    adc m48,y
    sta m48,x
    inx
    iny
    dec m_n
    bne ma_loop
    rts

m_sub:                          ; X -= Y
    lda #6
    sta m_n
    sec
ms_loop:
    lda m48,x
    sbc m48,y
    sta m48,x
    inx
    iny
    dec m_n
    bne ms_loop
    rts

m_cmp:                          ; C = 0 if X < Y (signed)
    lda #6
    sta m_n
    sec
mcp_loop:
    lda m48,x
    sbc m48,y
    inx
    iny
    dec m_n
    bne mcp_loop
    bvc mcp_v
    eor #$80
mcp_v:
    asl                         ; C = sign of X - Y: 1 if negative
    bcs mcp_lt
    sec
    rts
mcp_lt:
    clc
    rts

m_neg:                          ; C = 1 if slot X < 0
    lda m48+5,x
    asl
    rts

m_pos:                          ; C = 1 if slot X > 0
    lda m48+5,x
    bmi mp_no
    ora m48+4,x
    ora m48+3,x
    ora m48+2,x
    ora m48+1,x
    ora m48,x
    beq mp_no
    sec
    rts
mp_no:
    clc
    rts

m_shl:                          ; X <<= 1
    asl m48,x
    rol m48+1,x
    rol m48+2,x
    rol m48+3,x
    rol m48+4,x
    rol m48+5,x
    rts

m_shr:                          ; X >>= 1 (arithmetic)
    lda m48+5,x
    cmp #$80
    ror m48+5,x
    ror m48+4,x
    ror m48+3,x
    ror m48+2,x
    ror m48+1,x
    ror m48,x
    rts

; m_sq16: m_sq (32 bits) = A/Y (unsigned 16 bits) squared
m_sq16:
    sta m_a
    sty m_a+1
    sta m_b
    sty m_b+1
    lda #0
    sta m_sq
    sta m_sq+1
    sta m_sq+2
    sta m_sq+3
    ldx #16
msq_loop:
    asl m_sq
    rol m_sq+1
    rol m_sq+2
    rol m_sq+3
    asl m_b
    rol m_b+1
    bcc msq_next
    lda m_sq
    clc
    adc m_a
    sta m_sq
    lda m_sq+1
    adc m_a+1
    sta m_sq+1
    bcc msq_next
    inc m_sq+2
    bne msq_next
    inc m_sq+3
msq_next:
    dex
    bne msq_loop
    rts

; m_store_t: slot X = m_sq (32 bits, unsigned)
m_store_t:
    lda m_sq
    sta m48,x
    lda m_sq+1
    sta m48+1,x
    lda m_sq+2
    sta m48+2,x
    lda m_sq+3
    sta m48+3,x
    lda #0
    sta m48+4,x
    sta m48+5,x
    rts

; m_mul24: slot X = slot Y (>= 0) * m_t24 (24 bits, unsigned)
m_mul24:
    stx m_dst
    sty m_src
    jsr m_clr                   ; X = 0
    ldx #24
mm24_loop:
    stx m_n2
    ldx m_dst                   ; result <<= 1
    jsr m_shl
    asl m_t24                   ; next multiplier bit, high first
    rol m_t24+1
    rol m_t24+2
    bcc mm24_next
    ldx m_dst
    ldy m_src
    jsr m_add
mm24_next:
    ldx m_n2
    dex
    bne mm24_loop
    rts

; m_sqrt: sh_r (16 bits) = floor(sqrt(slot MR_A)), MR_A < 2^31
m_sqrt:
    lda #0
    sta sh_r
    sta sh_r+1
    lda #$80                    ; bit to try, from 2^15 down
    sta m_bit
    lda #0
    sta m_bit+1
    ldx #16
msr_loop:
    stx m_n2
    lda sh_r                    ; trial = r + bit
    ora m_bit+1
    sta m_a
    lda sh_r+1
    ora m_bit
    sta m_a+1
    lda m_a                     ; trial^2 <= A?
    ldy m_a+1
    jsr m_sq16
    ldx #MR_B
    jsr m_store_t
    ldx #MR_A
    ldy #MR_B
    jsr m_cmp                   ; C = 0 if A < trial^2
    bcc msr_next
    lda m_a
    sta sh_r
    lda m_a+1
    sta sh_r+1
msr_next:
    lsr m_bit                   ; next bit (m_bit high, m_bit+1 low)
    ror m_bit+1
    ldx m_n2
    dex
    bne msr_loop
    rts
