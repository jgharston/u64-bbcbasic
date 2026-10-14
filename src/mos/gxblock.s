; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- GXR horizontal line fills and block copy/move
;
; Bank 5 (bank 3 is full): PLOT 72-79 and 88-95 (groups 9 and 11) and
; PLOT 184-191 (group 23), as in the Graphics Extension ROM and the
; Master's MOS (docs/DESIGN_GRAPHICS.md 10.14). The shapes' bank copy
; (gxshape.s, bs_gxr) calls gxb_shape; Upic Lite's engine sends these
; groups there too. Both read the screen with GX_POINTDEV and draw
; through the engine (gx_call, in the resident core), so they work in
; every engine.
;
; ----------------------------------------------------------------------------

    .local gxb

; gxb_shape: vdubuf = the plot code: group 23 the block, else a line fill
gxb_shape:
    lda vdubuf
    cmp #184
    bcs gbs_blk
    jmp bs_hfill
gbs_blk:
    jmp bs_block

; gb_cpoint: the graphics cursor gc in device pixels ex/ey
gb_cpoint:
    lda gcx
    sta pk_x
    lda gcx+1
    sta pk_x+1
    lda gcy
    sta pk_y
    lda gcy+1
    sta pk_y+1
    ldx #GX_TODEV
    jmp gx_call

; gb_test: C = 1 if ex/ey is inside the graphics window and its colour is
; area: sh_fill 0: = gbg (PLOT 72-79), 1: <> gbg (88-95)
gb_test:
    ldx #GX_POINTDEV
    jsr gx_call
    lda gx_res
    cmp #$FF                    ; outside the window
    beq gbt_no
    cmp gbg
    beq gbt_bg
    lda sh_fill                 ; not background: area for 88-95
    beq gbt_no
    sec
    rts
gbt_bg:
    lda sh_fill
    bne gbt_no
    sec
    rts
gbt_no:
    clc
    rts

; gb_points: gq, gp, gc in device pixels into sh_x/sh_y slots 0, 1, 2
gb_points:
    lda gqx
    sta pk_x
    lda gqx+1
    sta pk_x+1
    lda gqy
    sta pk_y
    lda gqy+1
    sta pk_y+1
    ldy #0
    jsr gbp_conv
    lda gpx
    sta pk_x
    lda gpx+1
    sta pk_x+1
    lda gpy
    sta pk_y
    lda gpy+1
    sta pk_y+1
    ldy #2
    jsr gbp_conv
    jsr gb_cpoint
    ldy #4
    bne gbp_put
gbp_conv:                       ; pk -> device, into slot Y / 2
    tya
    pha
    ldx #GX_TODEV
    jsr gx_call
    pla
    tay
gbp_put:
    lda ex
    sta sh_x,y
    lda ex+1
    sta sh_x+1,y
    lda ey
    sta sh_y,y
    lda ey+1
    sta sh_y+1,y
    rts

; ----------------------------------------------------------------------------
; bs_hfill
;   Summary: PLOT 72-79: from the point left and right over the pixels
;            of the background colour; PLOT 88-95: from the point right
;            over the pixels that are not the background colour.
;   Function: the point to device pixels; nothing when it is outside the
;            window or not such a pixel; the run's ends found with gb_test
;            (window and colour), the run filled with GX_RECT in the plot
;            colour and action (no ECF pattern, as the flood fill).
;   Input:   gc, ecol/eact, vdubuf (bit 4: 88-95).  Output: the run.
;   Uses:    A, X, Y, ex, ey, pk_x, pk_y, sh_fill, sh_cx, sh_cy, erx*/ery*.
bs_hfill:
    lda #0
    sta epat
    lda vdubuf                  ; 0: area = gbg (72-79), 1: area <> gbg
    and #16
    beq bh_mode
    lda #1
bh_mode:
    sta sh_fill
    jsr gb_cpoint               ; the point in device pixels
    jsr gb_test
    bcs bh_go
    rts
bh_go:
    lda ex                      ; left end = right end = the point
    sta sh_cx
    sta sh_cy
    lda ex+1
    sta sh_cx+1
    sta sh_cy+1
    lda sh_fill
    bne bh_right                ; 88-95: to the right only
bh_left:
    lda ex
    ora ex+1
    beq bh_right                ; x = 0
    lda ex
    bne bhl_lo
    dec ex+1
bhl_lo:
    dec ex
    jsr gb_test
    bcc bh_right
    lda ex
    sta sh_cx
    lda ex+1
    sta sh_cx+1
    jmp bh_left
bh_right:
    lda sh_cy
    sta ex
    lda sh_cy+1
    sta ex+1
bhr_next:
    inc ex
    bne bhr_t
    inc ex+1
bhr_t:
    jsr gb_test                 ; (the window's right edge stops it)
    bcc bh_fill
    lda ex
    sta sh_cy
    lda ex+1
    sta sh_cy+1
    jmp bhr_next
bh_fill:
    lda sh_cx
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
    lda ey+1
    sta ery0+1
    sta ery1+1
    ldx #GX_RECT
    jmp gx_call

; ----------------------------------------------------------------------------
; bs_block
;   Summary: PLOT 185/189 (move) and 186-187/190-191 (copy): the
;            rectangle between the two points before (gq, gp) to the new
;            point (gc: its bottom left corner); a move leaves the
;            background colour where the rectangle was.
;   Function: pixel by pixel, read with GX_POINTDEV (outside the window:
;            left out) and set with GX_PSET (action 0, no pattern; clipped
;            to the window). Rows and columns run in the direction that
;            reads every pixel before it is overwritten, so overlapping
;            rectangles copy right; a move clears each source pixel right
;            after reading it (a later write in the destination wins).
;   Input:   gq, gp, gc; vdubuf (k AND 3 = 1: move).
;   Output:  the rectangle copied or moved.
;   Uses:    A, X, Y, ex, ey, ecol, sh_x/sh_y (all 4 slots), sh_cx,
;            sh_cy, sh_rx, sh_ry, sh_r, sh_e, sh_i, sh_fill.
; Slots: sh_x/y+0 the source's start column / row, +2 the destination's,
; +4 the current source pixel, +6 the current destination pixel;
; sh_cx/sh_cy width and height - 1, sh_r columns to go, sh_ry rows to go;
; sh_e/sh_i 0 = forwards, 1 = backwards (x / y).
bs_block:
    jsr gb_points               ; device: 0 = gq, 1 = gp, 2 = gc
    lda vdubuf
    and #3
    cmp #1
    beq bb_mv
    lda #0
bb_mv:
    sta sh_fill                 ; 1: move
    lda sh_x+4                  ; the destination's corner, kept in slot 3
    sta sh_x+6
    lda sh_x+5
    sta sh_x+7
    lda sh_y+4
    sta sh_y+6
    lda sh_y+5
    sta sh_y+7
    ldx #0                      ; source left = min x, width - 1 = |dx|
    jsr bb_minmax
    sta sh_cx
    sty sh_cx+1
    ldx #8                      ; (sh_y = sh_x + 8) top = min y, height - 1
    jsr bb_minmax
    sta sh_cy
    sty sh_cy+1
    lda sh_x+6                  ; destination left = gc's x
    sta sh_x+2
    lda sh_x+7
    sta sh_x+3
    lda sh_y+6                  ; destination top = gc's y - (height - 1)
    sec
    sbc sh_cy
    sta sh_y+2
    lda sh_y+7
    sbc sh_cy+1
    sta sh_y+3
    ldx #0                      ; directions: backwards when the
    jsr bb_dir                  ; destination is further right / down,
    sta sh_e                    ; starting at the far edge then
    ldx #8
    jsr bb_dir
    sta sh_i
    lda eact                    ; plain colours for the copy
    pha
    lda epat
    pha
    lda #0
    sta eact
    sta epat
    lda sh_y                    ; current rows: the start rows
    sta sh_y+4
    lda sh_y+1
    sta sh_y+5
    lda sh_y+2
    sta sh_y+6
    lda sh_y+3
    sta sh_y+7
    lda sh_cy                   ; rows to go = height
    clc
    adc #1
    sta sh_ry
    lda sh_cy+1
    adc #0
    sta sh_ry+1
bb_row:
    lda sh_x                    ; current pixels to the rows' start
    sta sh_x+4
    lda sh_x+1
    sta sh_x+5
    lda sh_x+2
    sta sh_x+6
    lda sh_x+3
    sta sh_x+7
    lda sh_cx                   ; columns to go = width
    clc
    adc #1
    sta sh_r
    lda sh_cx+1
    adc #0
    sta sh_r+1
bb_col:
    lda sh_x+4                  ; read the source pixel
    sta ex
    lda sh_x+5
    sta ex+1
    lda sh_y+4
    sta ey
    lda sh_y+5
    sta ey+1
    ldx #GX_POINTDEV
    jsr gx_call
    lda gx_res
    cmp #$FF
    beq bb_skip                 ; outside the window
    pha
    lda sh_fill                 ; a move: the background there
    beq bb_put
    lda gbg
    sta ecol
    ldx #GX_PSET
    jsr gx_call
bb_put:
    pla
    sta ecol
    lda sh_x+6
    sta ex
    lda sh_x+7
    sta ex+1
    lda sh_y+6
    sta ey
    lda sh_y+7
    sta ey+1
    ldx #GX_PSET
    jsr gx_call
bb_skip:
    ldx #4                      ; next column (both)
    lda sh_e
    jsr bb_step
    ldx #6
    lda sh_e
    jsr bb_step
    lda sh_r
    bne bbc_lo
    dec sh_r+1
bbc_lo:
    dec sh_r
    lda sh_r
    ora sh_r+1
    bne bb_col
    ldx #8+4                    ; next row (both)
    lda sh_i
    jsr bb_step
    ldx #8+6
    lda sh_i
    jsr bb_step
    lda sh_ry
    bne bbr_lo
    dec sh_ry+1
bbr_lo:
    dec sh_ry
    lda sh_ry
    ora sh_ry+1
    beq bb_done
    jmp bb_row
bb_done:
    pla
    sta epat
    pla
    sta eact
    rts

; bb_minmax: X = 0 (x) or 8 (y): slot 0 := min(slot 0, slot 1) of sh_x+X;
; A/Y = |slot 1 - slot 0| (low/high)
bb_minmax:
    lda sh_x+2,x
    sec
    sbc sh_x,x
    sta sh_rx
    lda sh_x+3,x
    sbc sh_x+1,x
    sta sh_rx+1
    bpl bbm_pos                 ; slot 1 >= slot 0: as it is
    lda sh_x+2,x                ; else slot 0 = slot 1, the difference
    sta sh_x,x                  ; negated
    lda sh_x+3,x
    sta sh_x+1,x
    lda #0
    sec
    sbc sh_rx
    sta sh_rx
    lda #0
    sbc sh_rx+1
    sta sh_rx+1
bbm_pos:
    lda sh_rx
    ldy sh_rx+1
    rts

; bb_dir: X = 0 (x) or 8 (y): A = 1 when the destination (slot 1) is
; beyond the source (slot 0): both slots then moved to their far edge
; (+ sh_cx / sh_cy, the size - 1)
bb_dir:
    lda sh_x,x                  ; source - destination < 0: backwards
    cmp sh_x+2,x
    lda sh_x+1,x
    sbc sh_x+3,x
    bvc bbd_s
    eor #$80
bbd_s:
    bmi bbd_back
    lda #0
    rts
bbd_back:
    txa                         ; the size - 1: sh_cx (x) or sh_cy (y)
    beq bbd_x
    lda sh_cy
    ldy sh_cy+1
    jmp bbd_add
bbd_x:
    lda sh_cx
    ldy sh_cx+1
bbd_add:
    sta sh_rx
    sty sh_rx+1
    lda sh_x,x
    clc
    adc sh_rx
    sta sh_x,x
    lda sh_x+1,x
    adc sh_rx+1
    sta sh_x+1,x
    lda sh_x+2,x
    clc
    adc sh_rx
    sta sh_x+2,x
    lda sh_x+3,x
    adc sh_rx+1
    sta sh_x+3,x
    lda #1
    rts

; bb_step: the 16-bit value at sh_x+X one on (A = 0) or back (A = 1)
bb_step:
    cmp #0
    bne bbs_back
    inc sh_x,x
    bne bbs_rts
    inc sh_x+1,x
    rts
bbs_back:
    lda sh_x,x
    bne bbs_lo
    dec sh_x+1,x
bbs_lo:
    dec sh_x,x
bbs_rts:
    rts

; ----------------------------------------------------------------------------
; gxb_vdu23
;   Summary: VDU 23,2-5,b1..b8: ECF pattern 1-4 from screen bytes in the
;            BBC layout of the mode's colours (as the GXR and the Master:
;            2 colours bit 7 = the left pixel; 4: pixel i = bits 7-i and
;            3-i; 16: bits 7-i, 5-i, 3-i, 1-i). VDU 23,6 (the dot-dash
;            line pattern): accepted, dotted lines keep every second pixel.
;   Function: the engine's patterns are 2 x 4 logical colours (pats, as
;            VDU 23,12-15): the first two pixels of the first four bytes.
;   Input:   vdubuf = 2-6, vdubuf+1..+8.  Output: pats.
;   Uses:    A, X, Y, sh_i, sh_e, sh_r (2).
gxb_vdu23:
    lda vdubuf
    sec
    sbc #2
    cmp #4
    bcs g23_rts                 ; (6: ignored)
    asl                         ; pats index = (n - 2) * 8
    asl
    asl
    sta sh_r
    lda #0                      ; bits per pixel: 1, 2 or 4; the step
    sta sh_r+1                  ; between a pixel's bits 8 / bpp
    ldy #0                      ; row 0-3
g23_row:
    ldx #0                      ; pixel 0, 1
g23_pix:
    lda vdubuf+1,y              ; the byte shifted by the pixel number
    cpx #0
    beq g23_dec
    asl
g23_dec:
    sta sh_e
    lda #0
    sta sh_i                    ; the colour
    lda vmode_ncol
    cmp #4
    beq g23_4
    bcs g23_16
    asl sh_e                    ; 2 colours: bit 7
    rol sh_i
    jmp g23_put
g23_4:
    asl sh_e                    ; bit 7, then bit 3
    rol sh_i
    asl sh_e
    asl sh_e
    asl sh_e
    asl sh_e
    rol sh_i
    jmp g23_put
g23_16:
    lda #4                      ; bits 7, 5, 3, 1
    sta sh_r+1
g23_b16:
    asl sh_e
    rol sh_i
    asl sh_e
    dec sh_r+1
    bne g23_b16
g23_put:
    tya                         ; pats[n * 8 + row * 2 + pixel]
    asl
    sta sh_r+1
    txa
    ora sh_r+1
    ora sh_r
    stx sh_r+1
    tax
    lda sh_i
    sta pats,x
    ldx sh_r+1
    inx
    cpx #2
    bcc g23_pix
    iny
    cpy #4
    bcc g23_row
g23_rts:
    rts

    .endl
