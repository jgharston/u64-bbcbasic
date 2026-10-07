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
    lda sh_op
    beq bs_plot
    cmp #1
    bne bs_v5move
    jmp sh_vdu5char
bs_v5move:
    jmp sh_vdu5move
bs_plot:
    lda vdubuf                  ; group = k DIV 8, looked up in bs_groups
    lsr
    lsr
    lsr
    ldx #bs_groups_end-bs_groups-1
bsp_find:
    cmp bs_groups,x
    beq bsp_go
    dex
    bpl bsp_find
    rts                         ; arcs, segments, sectors, block copy: not yet
bsp_go:
    txa
    asl
    tax
    lda bs_jumps+1,x
    pha
    lda bs_jumps,x
    pha
    rts
bs_groups:
    dta 10, 14, 18, 19, 24, 25, 27, 28, 30, 16, 17, 20, 21, 22
bs_groups_end:
bs_jumps:
    dta a(bs_tri-1), a(bs_par-1), a(bs_circle-1), a(bs_circfill-1)
    dta a(bs_ellipse-1), a(bs_ellfill-1), a(bs_rectout-1), a(bs_triout-1)
    dta a(bs_parout-1), a(bs_flood-1), a(bs_flood-1), a(sh_arc-1)
    dta a(sh_arc-1), a(sh_arc-1)
bs_flood:
    jmp sh_flood
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

; ----------------------------------------------------------------------------
; VDU 5: text at the graphics cursor

; sh_vdu5char
;   Summary: draw glyph[] with its top left corner at the graphics cursor,
;            in the graphics colour and action (GCOL), set pixels only
;            (transparent, as the BBC), then move the cursor one
;            character right.
;   Input:   glyph[], gcx/gcy, gfg, gact_fg.  Uses: A, X, Y.
sh_vdu5char:
    lda gcx
    ldy gcx+1
    jsr shp_x
    lda gcy
    ldy gcy+1
    jsr shp_y
    ldx #GX_TODEV
    jsr gx_call
    lda ex
    sta sh_cx
    lda ex+1
    sta sh_cx+1
    lda ey
    sta sh_cy
    lda ey+1
    sta sh_cy+1
    lda gfg
    sta ecol
    lda gact_fg                 ; action and pattern (as e_actsplit)
    pha
    and #15
    sta eact
    pla
    lsr
    lsr
    lsr
    lsr
    sta epat
    lda #0
    sta sh_i                    ; glyph row
sv5_row:
    ldx sh_i
    lda vmode_ch                ; 6-line cells: rows 3 and 7 left out
    cmp #8
    beq sv5_8
    cpx #3
    bcc sv5_8
    inx
sv5_8:
    lda glyph,x
    ldx vmode_cw
    cpx #4
    bne sv5_bits
    jsr sh_squeeze
sv5_bits:
    sta sh_e
    lda #0
    sta sh_j                    ; column
sv5_pix:
    asl sh_e
    bcc sv5_next
    lda sh_cx                   ; ex = x + column, ey = y + row
    clc
    adc sh_j
    sta ex
    lda sh_cx+1
    adc #0
    sta ex+1
    lda sh_cy
    clc
    adc sh_i
    sta ey
    lda sh_cy+1
    adc #0
    sta ey+1
    ldx #GX_PSET
    jsr gx_call
sv5_next:
    inc sh_j
    lda sh_j
    cmp vmode_cw
    bne sv5_pix
    inc sh_i
    lda sh_i
    cmp vmode_ch
    bne sv5_row
    lda #9                      ; cursor right
    sta sh_arg

; sh_vdu5move
;   Summary: VDU 5 cursor codes (PETSCII from the VDU driver in sh_arg):
;            right/left one character width (cell width in pixels << xsh
;            OS units), down/up 32 OS units (one BBC text row), return to
;            the graphics window's left edge, home to its top left.
sh_vdu5move:
    lda vmode_cw                ; w = cw << xsh (OS units)
    sta sh_rx
    lda #0
    sta sh_rx+1
    ldx vmode_xsh
    beq sv5m_w
sv5m_shift:
    asl sh_rx
    rol sh_rx+1
    dex
    bne sv5m_shift
sv5m_w:
    lda sh_arg
    cmp #9                      ; (from sh_vdu5char)
    beq sv5m_right
    cmp #$1D
    beq sv5m_right
    cmp #$9D
    beq sv5m_left
    cmp #$11
    beq sv5m_down
    cmp #$91
    beq sv5m_up
    cmp #$0D
    beq sv5m_cr
    cmp #$13
    beq sv5m_home
    rts
sv5m_right:
    lda gcx
    clc
    adc sh_rx
    sta gcx
    lda gcx+1
    adc sh_rx+1
    sta gcx+1
    rts
sv5m_left:
    lda gcx
    sec
    sbc sh_rx
    sta gcx
    lda gcx+1
    sbc sh_rx+1
    sta gcx+1
    rts
sv5m_down:
    lda gcy
    sec
    sbc #32
    sta gcy
    bcs sv5m_ok
    dec gcy+1
sv5m_ok:
    rts
sv5m_up:
    lda gcy
    clc
    adc #32
    sta gcy
    bcc sv5m_ok
    inc gcy+1
    rts
sv5m_cr:                        ; x = the window's left edge (OS units)
    jsr sv5m_left0
    rts
sv5m_home:                      ; top left of the graphics window
    jsr sv5m_left0
    lda gwt                     ; y = top edge: from device row gwt
    sta sh_e                    ; (the top text row: 1023 - origin in BBC
    lda #<1023                  ; modes; approximate for others)
    sec
    sbc goy
    sta gcy
    lda #>1023
    sbc goy+1
    sta gcy+1
    rts
sv5m_left0:                     ; x = gwl << xsh - origin
    lda gwl
    sta sh_rx
    lda gwl+1
    sta sh_rx+1
    ldx vmode_xsh
    beq sv5m_l0
sv5m_lsh:
    asl sh_rx
    rol sh_rx+1
    dex
    bne sv5m_lsh
sv5m_l0:
    lda sh_rx
    sec
    sbc gox
    sta gcx
    lda sh_rx+1
    sbc gox+1
    sta gcx+1
    rts

; sh_squeeze: 8 glyph bits -> 4 in the top nybble (pairs ORed), as the
; engine's e_squeeze
sh_squeeze:
    sta sh_nm
    lda #0
    sta sh_nm+1
    ldx #4
shq_loop:
    lda sh_nm
    and #$C0
    cmp #1
    rol sh_nm+1
    asl sh_nm
    asl sh_nm
    dex
    bne shq_loop
    lda sh_nm+1
    asl
    asl
    asl
    asl
    rts

; ----------------------------------------------------------------------------
; sh_flood
;   Summary: flood fill (PLOT 128-135: the area of background colour
;            around the point; PLOT 136-143: up to the foreground colour).
;   Function: span fill: a seed's row is filled from where the area ends
;            on the left to where it ends on the right (GX_RECT), and the
;            first pixel of every run of area in the rows above and below
;            becomes a seed. The seed stack lies in BASIC's free memory
;            between VARTOP (&02) and BASIC's stack (&04): unused during a
;            PLOT statement. A fill colour that is itself area (would
;            never end) does nothing; patterns are not used here.
;   Input:   gc (the point), ecol (fill colour), gfg/gbg, vdubuf.
;   Uses:    A, X, Y, shape variables.
sh_flood:
    lda #0                      ; plain colour
    sta epat
    lda vdubuf                  ; area colour test: 128-135 = bg, else fg
    and #8
    sta sh_fill                 ; 0: area = colour gbg; 8: area = not gfg
    lda ecol                    ; a fill colour inside the area: nothing
    jsr sf_isarea
    bcc sf_ok
    rts
sf_ok:
    lda $02                     ; stack bottom = VARTOP, limit = BASIC's
    sta sh_rx                   ; stack - 3
    lda $03
    sta sh_rx+1
    lda $04
    sec
    sbc #3
    sta sh_ry
    lda $05
    sbc #0
    sta sh_ry+1
    lda sh_rx                   ; sp = bottom
    sta sh_r
    lda sh_rx+1
    sta sh_r+1
    lda gcx                     ; the seed: device position of gc
    ldy gcx+1
    jsr shp_x
    lda gcy
    ldy gcy+1
    jsr shp_y
    ldx #GX_TODEV
    jsr gx_call
    jsr sf_pushxy               ; push ex/ey
sf_loop:
    lda sh_r                    ; stack empty?
    cmp sh_rx
    bne sf_pop
    lda sh_r+1
    cmp sh_rx+1
    bne sf_pop
    rts
sf_pop:
    jsr sf_popxy
    jsr sf_test                 ; still area (and in the window)?
    bcc sf_loop
    lda ex                      ; scan left
    sta sh_cx
    lda ex+1
    sta sh_cx+1
sf_left:
    lda ex
    bne sfl_dec
    lda ex+1
    beq sf_lend                 ; x = 0
sfl_dec:
    lda ex
    bne sfl_lo
    dec ex+1
sfl_lo:
    dec ex
    jsr sf_test
    bcs sfl_go
    inc ex                      ; one too far: back
    bne sf_lend
    inc ex+1
    bne sf_lend
sfl_go:
    lda ex
    sta sh_cx
    lda ex+1
    sta sh_cx+1
    jmp sf_left
sf_lend:
    lda sh_cx                   ; xl = sh_cx; scan right from the seed
    sta ex
    lda sh_cx+1
    sta ex+1
sf_right:
    lda ex
    sta sh_cy                   ; xr so far
    lda ex+1
    sta sh_cy+1
    inc ex
    bne sfr_t
    inc ex+1
sfr_t:
    jsr sf_test
    bcs sf_right
    lda sh_cx                   ; fill xl .. xr on this row
    sta erx0
    lda sh_cx+1
    sta erx0+1
    lda sh_cy
    sta erx1
    lda sh_cy+1
    sta erx1+1
    lda ey
    sta ery0
    sta ery1
    sta sh_e                    ; (the row)
    lda ey+1
    sta ery0+1
    sta ery1+1
    ldx #GX_RECT
    jsr gx_call
    .if SHRAM
    jsr sh_yield
    .endif
    lda sh_e                    ; seeds in the row above and below
    sec
    sbc #1
    bcc sf_below
    jsr sf_seeds
sf_below:
    lda sh_e
    clc
    adc #1
    beq sf_next                 ; (row 255)
    jsr sf_seeds
sf_next:
    jmp sf_loop

; sf_seeds: row A, columns sh_cx .. sh_cy: push the first pixel of every
; run of area
sf_seeds:
    sta ey
    lda #0
    sta ey+1
    sta sh_i                    ; 1 while inside a run
    lda sh_cx
    sta ex
    lda sh_cx+1
    sta ex+1
sfs_loop:
    jsr sf_test
    bcc sfs_out
    lda sh_i
    bne sfs_next
    inc sh_i
    jsr sf_pushxy
    jmp sfs_next
sfs_out:
    lda #0
    sta sh_i
sfs_next:
    lda ex                      ; up to xr
    cmp sh_cy
    lda ex+1
    sbc sh_cy+1
    bcs sfs_done
    inc ex
    bne sfs_loop
    inc ex+1
    bne sfs_loop
sfs_done:
    rts

; sf_test: C = 1 if ex/ey is inside the graphics window and area
sf_test:
    ldx #GX_POINTDEV
    jsr gx_call
    lda gx_res
    cmp #$FF                    ; outside the window
    bne sf_isarea
    clc
    rts
; sf_isarea: C = 1 if colour A is area: = gbg (PLOT 128) or <> gfg (136)
sf_isarea:
    ldx sh_fill
    bne sfa_fg
    cmp gbg
    beq sfa_yes
    clc
    rts
sfa_fg:
    cmp gfg
    bne sfa_yes
    clc
    rts
sfa_yes:
    sec
    rts

; sf_pushxy / sf_popxy: ex (2 bytes) and ey (1) on the seed stack at
; (sh_r); a full stack drops the seed (the area may stay partly unfilled)
sf_pushxy:
    lda sh_r
    cmp sh_ry
    lda sh_r+1
    sbc sh_ry+1
    bcs sfp_full
    lda sh_r
    sta gzp
    lda sh_r+1
    sta gzp+1
    ldy #0
    lda ex
    sta (gzp),y
    iny
    lda ex+1
    sta (gzp),y
    iny
    lda ey
    sta (gzp),y
    lda sh_r
    clc
    adc #3
    sta sh_r
    bcc sfp_full
    inc sh_r+1
sfp_full:
    rts
sf_popxy:
    lda sh_r
    sec
    sbc #3
    sta sh_r
    bcs sfo_hi
    dec sh_r+1
sfo_hi:
    lda sh_r
    sta gzp
    lda sh_r+1
    sta gzp+1
    ldy #0
    lda (gzp),y
    sta ex
    iny
    lda (gzp),y
    sta ex+1
    iny
    lda (gzp),y
    sta ey
    lda #0
    sta ey+1
    rts

; ----------------------------------------------------------------------------
; sh_arc
;   Summary: PLOT 160-167 arc, 168-175 segment, 176-183 sector (the BBC
;            GXR/Master's definition): centre = the point two plots back
;            (gq), the previous point (gp) gives the radius and the start
;            angle, the new point (gc) the end angle; anticlockwise.
;   Function: in OS units (the same scale on both axes): start and end
;            angles from a 256-step sine table (the step whose direction
;            fits best), arc points P(i) = centre + r (cos, sin) at each
;            step, converted to device pixels. Arc: lines between them;
;            sector: triangles from the centre; segment: triangles from
;            the start point (the area between chord and arc).
;   Uses:    A, X, Y, shape variables, m48 slots.
sh_arc:
    lda vdubuf                  ; 0 arc, 1 segment, 2 sector
    lsr
    lsr
    lsr
    sec
    sbc #20
    sta sh_fill
    lda gpx                     ; S = gp - gq (OS units); r = |S|
    sec
    sbc gqx
    sta sha_sx
    sta sh_nm
    lda gpx+1
    sbc gqx+1
    sta sha_sx+1
    sta sh_nm+1
    lda gpy
    sec
    sbc gqy
    sta sha_sy
    sta sh_nm+2
    lda gpy+1
    sbc gqy+1
    sta sha_sy+1
    sta sh_nm+3
    jsr sh_hypot                ; sh_r = radius
    lda sha_sx                  ; start angle: best step for S
    ldx sha_sx+1
    ldy sha_sy
    lda sha_sy+1
    sta sha_vy+1
    sty sha_vy
    lda sha_sx
    sta sha_vx
    stx sha_vx+1
    jsr sha_angle
    sta sha_a0
    lda gcx                     ; end angle: best step for gc - gq
    sec
    sbc gqx
    sta sha_vx
    lda gcx+1
    sbc gqx+1
    sta sha_vx+1
    lda gcy
    sec
    sbc gqy
    sta sha_vy
    lda gcy+1
    sbc gqy+1
    sta sha_vy+1
    jsr sha_angle
    sta sha_a1
    lda gqx                     ; the start point exactly: gp (device)
    ldy gqx+1
    jsr shp_x
    lda gqy
    ldy gqy+1
    jsr shp_y
    ldx #4                      ; slot 2 = centre (device)
    jsr shp_conv
    lda gpx
    ldy gpx+1
    jsr shp_x
    lda gpy
    ldy gpy+1
    jsr shp_y
    ldx #0                      ; slot 0 = previous arc point = start
    jsr shp_conv
    lda sh_x                    ; slot 3 (fan origin for segments) = start
    sta sh_x+6
    lda sh_x+1
    sta sh_x+7
    lda sh_y
    sta sh_y+6
    lda sh_y+1
    sta sh_y+7
    lda sha_a0
    sta sha_i
sha_step:
    inc sha_i                   ; next step (anticlockwise)
    lda sha_i
    jsr sha_point               ; slot 1 = P(i) (device)
    jsr sha_draw                ; line / triangle from slot 0 to slot 1
    lda sh_x+2                  ; slot 0 = slot 1
    sta sh_x
    lda sh_x+3
    sta sh_x+1
    lda sh_y+2
    sta sh_y
    lda sh_y+3
    sta sh_y+1
    .if SHRAM
    jsr sh_yield
    .endif
    lda sha_i
    cmp sha_a1
    bne sha_step
    rts

; sha_draw: arc: line slot 0 -> 1 (without its last point); sector:
; triangle centre (slot 2), slot 0, slot 1; segment: start (slot 3),
; slot 0, slot 1
sha_draw:
    lda sh_fill
    bne shd_fill
    lda sh_x
    sta eline_x0
    lda sh_x+1
    sta eline_x0+1
    lda sh_y
    sta eline_y0
    lda sh_y+1
    sta eline_y0+1
    lda sh_x+2
    sta eline_x1
    lda sh_x+3
    sta eline_x1+1
    lda sh_y+2
    sta eline_y1
    lda sh_y+3
    sta eline_y1+1
    lda #4
    sta eflags
    ldx #GX_LINE
    jmp gx_call
shd_fill:                       ; the triangle in slots 0, 1, 2 (trifill
    ldx #7                      ; sorts them: work on a copy)
shd_save:
    lda sh_x,x
    sta sha_save,x
    lda sh_y,x
    sta sha_save+8,x
    dex
    bpl shd_save
    lda sh_fill
    cmp #2
    beq shd_tri                 ; sector: slot 2 is the centre already
    lda sh_x+6                  ; segment: slot 2 = start
    sta sh_x+4
    lda sh_x+7
    sta sh_x+5
    lda sh_y+6
    sta sh_y+4
    lda sh_y+7
    sta sh_y+5
shd_tri:
    jsr sh_trifill
    ldx #7
shd_rest:
    lda sha_save,x
    sta sh_x,x
    lda sha_save+8,x
    sta sh_y,x
    dex
    bpl shd_rest
    rts

; sha_point: slot 1 = device position of centre + r (cos A, sin A), A =
; step (256 per turn)
sha_point:
    pha
    clc
    adc #64                     ; cos = sin(a + 64)
    jsr sha_rsin                ; r * cos -> sh_dv
    lda sh_dv
    clc
    adc gqx
    sta pk_x
    lda sh_dv+1
    adc gqx+1
    sta pk_x+1
    pla
    jsr sha_rsin                ; r * sin
    lda sh_dv
    clc
    adc gqy
    sta pk_y
    lda sh_dv+1
    adc gqy+1
    sta pk_y+1
    ldx #2
    jmp shp_conv

; sha_rsin: sh_dv = r * sin(step A) / 32768 (signed 16 bits)
sha_rsin:
    asl
    tax
    lda sha_sin,x
    sta m_a
    lda sha_sin+1,x
    sta m_a+1
    sta sha_sg                  ; sign of sin
    bpl shr_pos
    lda #0
    sec
    sbc m_a
    sta m_a
    lda #0
    sbc m_a+1
    sta m_a+1
shr_pos:
    lda sh_r
    sta m_b
    lda sh_r+1
    sta m_b+1
    jsr sha_mul                 ; m_sq = |sin| * r (32 bits)
    lda m_sq+1                  ; / 32768: bits 15-30
    asl
    lda m_sq+2
    rol
    sta sh_dv
    lda m_sq+3
    rol
    sta sh_dv+1
    lda sha_sg
    bpl shr_done
    lda #0
    sec
    sbc sh_dv
    sta sh_dv
    lda #0
    sbc sh_dv+1
    sta sh_dv+1
shr_done:
    rts

; sha_mul: m_sq (32 bits) = m_a * m_b (unsigned 16 bits each)
sha_mul:
    lda #0
    sta m_sq
    sta m_sq+1
    sta m_sq+2
    sta m_sq+3
    ldx #16
smu_loop:
    asl m_sq
    rol m_sq+1
    rol m_sq+2
    rol m_sq+3
    asl m_b
    rol m_b+1
    bcc smu_next
    lda m_sq
    clc
    adc m_a
    sta m_sq
    lda m_sq+1
    adc m_a+1
    sta m_sq+1
    bcc smu_next
    inc m_sq+2
    bne smu_next
    inc m_sq+3
smu_next:
    dex
    bne smu_loop
    rts

; sha_angle: A = the step (0-255) whose direction (cos, sin) fits the
; vector sha_vx, sha_vy best: the largest dot product, scaled down to
; 8 bits per component first (only the direction matters)
sha_angle:
    jsr sha_scale               ; sha_vx/vy -> signed 8-bit sha_bx/by
    lda #0
    sta sha_best
    lda #$80                    ; best dot so far: very small
    sta sha_bd+1
    lda #0
    sta sha_bd
    sta sha_i
sag_loop:
    lda sha_i                   ; dot = bx * cos + by * sin (16 bits,
    clc                         ; using the high byte of the table)
    adc #64
    asl
    tax
    lda sha_sin+1,x
    ldy sha_bx
    jsr sha_smul8
    sta sha_dot
    stx sha_dot+1
    lda sha_i
    asl
    tax
    lda sha_sin+1,x
    ldy sha_by
    jsr sha_smul8
    clc
    adc sha_dot
    sta sha_dot
    txa
    adc sha_dot+1
    sta sha_dot+1
    lda sha_dot                 ; better (signed)?
    cmp sha_bd
    lda sha_dot+1
    sbc sha_bd+1
    bvc sag_v
    eor #$80
sag_v:
    bmi sag_next
    lda sha_dot
    sta sha_bd
    lda sha_dot+1
    sta sha_bd+1
    lda sha_i
    sta sha_best
sag_next:
    inc sha_i
    bne sag_loop
    lda sha_best
    rts

; sha_scale: shift sha_vx/vy right (arithmetically) until both are in
; -64 .. 63; their low bytes are then sha_bx/by
sha_scale:
    ldx #0
    jsr sas_ok
    bcc sas_shift
    ldx #2
    jsr sas_ok
    bcc sas_shift
    lda sha_vx
    sta sha_bx
    lda sha_vy
    sta sha_by
    rts
sas_shift:
    lda sha_vx+1
    cmp #$80
    ror sha_vx+1
    ror sha_vx
    lda sha_vy+1
    cmp #$80
    ror sha_vy+1
    ror sha_vy
    jmp sha_scale
; sas_ok: C = 1 if the word at sha_vx + X is in -64 .. 63
sas_ok:
    lda sha_vx+1,x
    beq sok_pos
    cmp #$FF
    bne sok_no
    lda sha_vx,x
    cmp #$C0
    rts                         ; C = 1 if >= $C0
sok_pos:
    lda sha_vx,x
    cmp #$40                    ; C = 0 if < $40: ok -> invert
    bcs sok_no
    sec
    rts
sok_no:
    clc
    rts

; sha_smul8: A (signed) * Y (signed) -> A/X (low/high, signed 16 bits)
sha_smul8:
    sta sha_ma
    sty sha_mb
    lda #0
    sta sha_mr
    sta sha_mr+1
    lda sha_ma                  ; sign of the result, and magnitudes
    eor sha_mb
    sta sha_ms
    lda sha_ma
    bpl ssm_a
    eor #$FF
    clc
    adc #1
    sta sha_ma
ssm_a:
    lda sha_mb
    bpl ssm_b
    eor #$FF
    clc
    adc #1
    sta sha_mb
ssm_b:
    ldy #8
ssm_loop:
    asl sha_mr
    rol sha_mr+1
    asl sha_mb
    bcc ssm_next
    lda sha_mr
    clc
    adc sha_ma
    sta sha_mr
    bcc ssm_next
    inc sha_mr+1
ssm_next:
    dey
    bne ssm_loop
    lda sha_ms
    bpl ssm_done
    lda #0
    sec
    sbc sha_mr
    sta sha_mr
    lda #0
    sbc sha_mr+1
    sta sha_mr+1
ssm_done:
    lda sha_mr
    ldx sha_mr+1
    rts

; 256-step sine, signed 16 bits (32767 * sin(2 pi i / 256))
sha_sin:
    dta a($0000), a($0324), a($0648), a($096A), a($0C8C), a($0FAB), a($12C8), a($15E2)
    dta a($18F9), a($1C0B), a($1F1A), a($2223), a($2528), a($2826), a($2B1F), a($2E11)
    dta a($30FB), a($33DF), a($36BA), a($398C), a($3C56), a($3F17), a($41CE), a($447A)
    dta a($471C), a($49B4), a($4C3F), a($4EBF), a($5133), a($539B), a($55F5), a($5842)
    dta a($5A82), a($5CB3), a($5ED7), a($60EB), a($62F1), a($64E8), a($66CF), a($68A6)
    dta a($6A6D), a($6C23), a($6DC9), a($6F5E), a($70E2), a($7254), a($73B5), a($7504)
    dta a($7641), a($776B), a($7884), a($7989), a($7A7C), a($7B5C), a($7C29), a($7CE3)
    dta a($7D89), a($7E1D), a($7E9C), a($7F09), a($7F61), a($7FA6), a($7FD8), a($7FF5)
    dta a($7FFF), a($7FF5), a($7FD8), a($7FA6), a($7F61), a($7F09), a($7E9C), a($7E1D)
    dta a($7D89), a($7CE3), a($7C29), a($7B5C), a($7A7C), a($7989), a($7884), a($776B)
    dta a($7641), a($7504), a($73B5), a($7254), a($70E2), a($6F5E), a($6DC9), a($6C23)
    dta a($6A6D), a($68A6), a($66CF), a($64E8), a($62F1), a($60EB), a($5ED7), a($5CB3)
    dta a($5A82), a($5842), a($55F5), a($539B), a($5133), a($4EBF), a($4C3F), a($49B4)
    dta a($471C), a($447A), a($41CE), a($3F17), a($3C56), a($398C), a($36BA), a($33DF)
    dta a($30FB), a($2E11), a($2B1F), a($2826), a($2528), a($2223), a($1F1A), a($1C0B)
    dta a($18F9), a($15E2), a($12C8), a($0FAB), a($0C8C), a($096A), a($0648), a($0324)
    dta a($0000), a($FCDC), a($F9B8), a($F696), a($F374), a($F055), a($ED38), a($EA1E)
    dta a($E707), a($E3F5), a($E0E6), a($DDDD), a($DAD8), a($D7DA), a($D4E1), a($D1EF)
    dta a($CF05), a($CC21), a($C946), a($C674), a($C3AA), a($C0E9), a($BE32), a($BB86)
    dta a($B8E4), a($B64C), a($B3C1), a($B141), a($AECD), a($AC65), a($AA0B), a($A7BE)
    dta a($A57E), a($A34D), a($A129), a($9F15), a($9D0F), a($9B18), a($9931), a($975A)
    dta a($9593), a($93DD), a($9237), a($90A2), a($8F1E), a($8DAC), a($8C4B), a($8AFC)
    dta a($89BF), a($8895), a($877C), a($8677), a($8584), a($84A4), a($83D7), a($831D)
    dta a($8277), a($81E3), a($8164), a($80F7), a($809F), a($805A), a($8028), a($800B)
    dta a($8001), a($800B), a($8028), a($805A), a($809F), a($80F7), a($8164), a($81E3)
    dta a($8277), a($831D), a($83D7), a($84A4), a($8584), a($8677), a($877C), a($8895)
    dta a($89BF), a($8AFC), a($8C4B), a($8DAC), a($8F1E), a($90A2), a($9237), a($93DD)
    dta a($9593), a($975A), a($9931), a($9B18), a($9D0F), a($9F15), a($A129), a($A34D)
    dta a($A57E), a($A7BE), a($AA0B), a($AC65), a($AECD), a($B141), a($B3C1), a($B64C)
    dta a($B8E4), a($BB86), a($BE32), a($C0E9), a($C3AA), a($C674), a($C946), a($CC21)
    dta a($CF05), a($D1EF), a($D4E1), a($D7DA), a($DAD8), a($DDDD), a($E0E6), a($E3F5)
    dta a($E707), a($EA1E), a($ED38), a($F055), a($F374), a($F696), a($F9B8), a($FCDC)
