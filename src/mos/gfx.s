; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- drawing engine, runs from RAM at ENGINE ($D000-$DFFF)
;
; The RAM under the I/O area: code here runs with $01 = $34 (all RAM),
; entered only through gx_call in the VDU core (core.s), with interrupts
; off. It never touches I/O itself: colour RAM and VIC registers go
; through core routines (io_*), which switch I/O in and out around the
; access. Long operations call gx_yield (core) now and then, so the
; keyboard and TIME interrupts are not lost.
;
; Screen: VIC-II bitmap at BITMAP ($E000-$FF3F), screen matrix (cell
; colours) at SCREEN ($C000), colour RAM for the multicolour modes. BBC
; graphics coordinates (OS units, y up) are converted to device pixels
; (y down) per mode; see docs/DESIGN_GRAPHICS.md section 10.
;
; ----------------------------------------------------------------------------

; Assembled twice (GXUL, set by the wrapper): GXUL = 0 for the VIC-II
; bitmap modes (gfx_vic.s, bank 0), GXUL = 1 for Upic Lite (gfx_ul.s,
; bank 3): a column-major buffer below HIMEM (byte column c at
; vmode_bufhi + c pages, row y = offset y), leftmost pixel in the lowest
; bit(s), 256 lines (docs/DESIGN_GRAPHICS.md section 10.8).

; Entry points (jump table, offsets used by core.s: GX_*)
    jmp e_mode                  ; +0  set up the current mode, clear
    jmp e_vdu                   ; +3  graphics VDU code X (vdubuf)
    jmp e_char                  ; +6  draw glyph[] at the text cursor
    jmp e_pet                   ; +9  PETSCII cursor/control code A
    jmp e_cursor                ; +12 toggle the text cursor
    jmp e_point                 ; +15 POINT: pk_x/pk_y -> gx_res
    jmp e_matrix                ; +18 cell colours from pal[]

; ----------------------------------------------------------------------------
; Engine variables (RAM, zero at cold start: the engine is copied)

ex          dta a(0)            ; device x (signed 16)
ey          dta a(0)            ; device y (signed 16)
emask       dta 0               ; pixel mask in the byte
evrep       dta 0               ; colour value repeated over the byte
eact        dta 0               ; GCOL action 0-4
ecol        dta 0               ; logical colour of the current operation
eline_x0    dta a(0)
eline_y0    dta a(0)
eline_x1    dta a(0)
eline_y1    dta a(0)
edx         dta a(0)
edy         dta a(0)
esx         dta 0               ; x step +1/-1 ($01/$FF)
esy         dta 0
eerr        dta a(0)
eflags      dta 0               ; line: bit 0 dotted, 1 omit first, 2 omit last
edot        dta 0
efirst      dta 0
ecount      dta a(0)
et24        dta 0, 0, 0
eyield      dta 0
erx0        dta a(0)            ; rectangle in device pixels
erx1        dta a(0)
ery0        dta a(0)
ery1        dta a(0)
etmp        dta 0, 0
enoclip     dta 0               ; 1: e_rect ignores the graphics window
egrow       dta 0               ; glyph row being drawn
erows       :6 dta 0            ; rows drawn in 6-line cells (e_rows6)
er6a        dta 0
er6b        dta 0
egbits      dta 0               ; its bits
ecrow       dta 0               ; text row (clear/cls)
esqt        dta 0, 0            ; e_squeeze
ewb_first   dta a(0)            ; window: offset of its first byte in a row
ewb_count   dta 0               ; window: width in bytes

; ----------------------------------------------------------------------------
; Tables (the small ones are in the core, gx_tables in core.s)

; Bitmap address of each cell row (a pixel row adds its line 0-7)
crowlo:
    :25 dta l(BITMAP+#*320)
crowhi:
    :25 dta h(BITMAP+#*320)
; ----------------------------------------------------------------------------
; e_mode
;   Summary: set up the engine for the mode in vmode_*: clear the bitmap,
;            fill the screen matrix with the mode's cell colours, reset
;            windows, cursors, origin and colours.
;   Input:   vmode_* (core), pal[] already set by the core.
;   Output:  bitmap clear; state reset.  Uses: A, X, Y, gzp.
e_mode:
    .if GXUL
    lda vmode_bufhi             ; Upic Lite: buffer up to $7FFF, 0
    sta gzp+1
    lda #0
    sta gzp
    tay
eu_clr:
    sta (gzp),y
    iny
    bne eu_clr
    inc gzp+1
    ldx gzp+1
    cpx #$80
    bne eu_clr
    jmp e_defaults
    .else
    lda #<BITMAP                ; bitmap: 8000 bytes of 0
    sta gzp
    lda #>BITMAP
    sta gzp+1
    ldx #32                     ; 32 pages = $E000-$FFFF (ends before the
    ldy #0                      ; vectors: page $FF only to $FFF9)
    tya
em_clr:
    sta (gzp),y
    iny
    bne em_clr
    inc gzp+1
    dex
    cpx #1
    bne em_clr
em_last:
    sta (gzp),y                 ; page $FF: up to $FFF9
    iny
    cpy #$FA
    bne em_last
    jsr e_defaults
    jmp e_matrix
    .endif

; e_defaults: windows full screen, cursors home, origin 0, colours
e_defaults:
    lda #0
    ldx #11                     ; gox, goy, gcx, gcy, gpx, gpy (core)
ed_zero:
    sta gox,x
    dex
    bpl ed_zero
    sta vdu5
    ldx #5                      ; tfg, tbg, gfg, gbg, gact_fg, gact_bg
ed_col:
    sta tfg,x
    dex
    bpl ed_col
    lda vmode_ncol              ; foreground: the highest colour (BBC)
    sec                         ; (7 in 16-colour modes: white)
    sbc #1
    cmp #15
    bne ed_fg
    lda #7
ed_fg:
    sta tfg
    sta gfg
    jmp e_defwin

e_gwfull:                       ; graphics window: the whole screen
    lda #0
    sta gwl
    sta gwl+1
    sta gwt
    sta gwt+1
    sta gwb+1
    lda vmode_xmax
    sta gwr
    lda vmode_xmax+1
    sta gwr+1
    lda vmode_ymax
    sta gwb
    rts

; ----------------------------------------------------------------------------
; e_matrix
;   Summary: fill the screen matrix with the mode's cell colours (the
;            colour RAM and $D021 are set by the core, io_palette).
;   Function: hires: high nybble = colour of logical 1, low = logical 0.
;            Multicolour: high = logical 1, low = logical 2.
;            16-colour modes start with the same cells; drawing changes
;            them per cell.
e_matrix:
    .if GXUL
    rts
    .else
    lda vmode_mc
    bne emx_mc
    lda pal+1
    asl
    asl
    asl
    asl
    ora pal
    jmp emx_fill
emx_mc:
    lda pal+1
    asl
    asl
    asl
    asl
    ora pal+2
emx_fill:
    ldx #0
emx_loop:
    sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$2E8,x
    inx
    bne emx_loop
    rts
    .endif

; ----------------------------------------------------------------------------
; e_vdu
;   Summary: graphics VDU commands in bitmap modes.
;   Input:   gx_code = VDU code (12 CLS, 16 CLG, 17 COLOUR, 18 GCOL,
;            24, 25, 26, 28, 29), parameters in vdubuf.
;   Output:  per command.  Uses: A, X, Y, engine variables.
e_vdu:
    ldx gx_code
    cpx #25
    bne ev_n25
    jmp e_plot
ev_n25:
    cpx #16
    bne ev_n16
    jmp e_clg
ev_n16:
    cpx #18
    bne ev_n18
    lda vdubuf+1                ; GCOL a,c
    bmi ev_gbg
    and vmode_cmask
    sta gfg
    lda vdubuf
    and #7
    sta gact_fg
    rts
ev_gbg:
    and vmode_cmask
    sta gbg
    lda vdubuf
    and #7
    sta gact_bg
    rts
ev_n18:
    cpx #29
    bne ev_n29
    lda vdubuf                  ; VDU 29: origin
    sta gox
    lda vdubuf+1
    sta gox+1
    lda vdubuf+2
    sta goy
    lda vdubuf+3
    sta goy+1
    rts
ev_n29:
    cpx #24
    bne ev_n24
    jmp e_gwin
ev_n24:
    cpx #26
    bne ev_n26
    jmp e_defwin
ev_n26:
    cpx #28
    bne ev_n28
    jmp e_twin
ev_n28:
    cpx #12
    bne ev_n12
    jmp e_cls
ev_n12:
    cpx #17
    bne ev_n17
    lda vdubuf                  ; COLOUR n (128+n background)
    bmi ev_tbg
    and vmode_cmask
    sta tfg
    rts
ev_tbg:
    and vmode_cmask
    sta tbg
ev_n17:
    rts

; VDU 26: default windows (text and graphics), text cursor home
e_defwin:
    lda #0
    sta twl
    sta twt
    sta tcx
    sta tcy
    lda vmode_cols
    sec
    sbc #1
    sta twr
    lda vmode_rows
    sec
    sbc #1
    sta twb
    jmp e_gwfull

; VDU 28,l,b,r,t: text window; ignored if outside the screen or inverted
e_twin:
    lda vdubuf+2                ; r
    cmp vmode_cols
    bcs etw_bad
    cmp vdubuf                  ; r >= l
    bcc etw_bad
    lda vdubuf+1                ; b
    cmp vmode_rows
    bcs etw_bad
    cmp vdubuf+3                ; b >= t
    bcc etw_bad
    lda vdubuf
    sta twl
    lda vdubuf+1
    sta twb
    lda vdubuf+2
    sta twr
    lda vdubuf+3
    sta twt
    lda twl                     ; cursor to the window's top left
    sta tcx
    lda twt
    sta tcy
etw_bad:
    rts

; VDU 24,l;b;r;t;: graphics window, relative to the origin
e_gwin:
    lda vdubuf                  ; left/bottom corner
    sta pk_x
    lda vdubuf+1
    sta pk_x+1
    lda vdubuf+2
    sta pk_y
    lda vdubuf+3
    sta pk_y+1
    jsr e_todev
    lda ex
    sta erx0
    lda ex+1
    sta erx0+1
    lda ey
    sta ery1                    ; bottom (device y is larger)
    lda ey+1
    sta ery1+1
    lda vdubuf+4                ; right/top
    sta pk_x
    lda vdubuf+5
    sta pk_x+1
    lda vdubuf+6
    sta pk_y
    lda vdubuf+7
    sta pk_y+1
    jsr e_todev
    jsr e_clipscreen            ; ex/ey and erx0/ery1 into the screen
    lda ex                      ; right >= left and top <= bottom, else
    cmp erx0                    ; ignored (as the BBC does)
    lda ex+1
    sbc erx0+1
    bmi egw_bad
    lda ery1
    cmp ey
    lda ery1+1
    sbc ey+1
    bmi egw_bad
    lda erx0
    sta gwl
    lda erx0+1
    sta gwl+1
    lda ex
    sta gwr
    lda ex+1
    sta gwr+1
    lda ey
    sta gwt
    lda ey+1
    sta gwt+1
    lda ery1
    sta gwb
    lda ery1+1
    sta gwb+1
egw_bad:
    rts

; e_clipscreen: clamp ex, ey, erx0, ery1 to the screen (0..xmax, 0..ymax)
e_clipscreen:
    ldx #ex-ex
    jsr ecs_x
    ldx #erx0-ex
    jsr ecs_x
    ldx #ey-ex
    jsr ecs_y
    ldx #ery1-ex
ecs_y:
    lda ex+1,x
    bmi ecs_zero
    bne ecs_ymax
    lda vmode_ymax
    cmp ex,x
    bcs ecs_ok
ecs_ymax:
    lda vmode_ymax
    sta ex,x
    lda #0
    sta ex+1,x
    rts
ecs_x:
    lda ex+1,x
    bmi ecs_zero
    lda ex,x
    cmp vmode_xmax
    lda ex+1,x
    sbc vmode_xmax+1
    bcc ecs_ok
    lda vmode_xmax
    sta ex,x
    lda vmode_xmax+1
    sta ex+1,x
    rts
ecs_zero:
    lda #0
    sta ex,x
    sta ex+1,x
ecs_ok:
    rts

; ----------------------------------------------------------------------------
; e_todev
;   Summary: OS units (pk_x, pk_y, relative to the origin) to device
;            pixels (ex, ey; y down), signed 16 bits.
;   Function: x = (pk_x + origin) >> vmode_xsh (arithmetic).
;            y: BBC modes (vmode_ysc = 0): 199 - (Y * 25) >> 7, so
;            1024 OS units become 200 lines; C64 modes (1): 199 - Y >> 2.
;   Uses:    A, X, et24.
e_todev:
    lda pk_x
    clc
    adc gox
    sta ex
    lda pk_x+1
    adc gox+1
    sta ex+1
    ldx vmode_xsh
    beq etd_y
etd_xs:
    lda ex+1
    cmp #$80                    ; C = sign: arithmetic shift right
    ror ex+1
    ror ex
    dex
    bne etd_xs
etd_y:
    lda pk_y
    clc
    adc goy
    sta et24
    lda pk_y+1
    adc goy+1
    sta et24+1
    lda vmode_ysc
    beq etd_bbc
    jmp etd_c64
etd_bbc:
    lda #0                      ; sign extend to 24 bits
    bit et24+1
    bpl etd_pos
    lda #$FF
etd_pos:
    sta et24+2
    ; Y * 25 = Y * 16 + Y * 8 + Y
    lda et24
    sta etmp
    lda et24+1
    sta etmp+1
    ldx #3                      ; * 8
etd_m8:
    asl et24
    rol et24+1
    rol et24+2
    dex
    bne etd_m8
    lda et24                    ; Y*8 + Y*16 = Y*24: keep Y*8 in ex+..?
    pha
    lda et24+1
    pha
    lda et24+2
    pha
    asl et24                    ; * 16
    rol et24+1
    rol et24+2
    pla                         ; + Y * 8
    tax
    pla
    tay
    pla
    clc
    adc et24
    sta et24
    tya
    adc et24+1
    sta et24+1
    txa
    adc et24+2
    sta et24+2
    lda etmp                    ; + Y (sign extended)
    clc
    adc et24
    sta et24
    lda etmp+1
    adc et24+1
    sta et24+1
    lda #0
    bit etmp+1
    bpl etd_ypos
    lda #$FF
etd_ypos:
    adc et24+2
    sta et24+2
    asl et24                    ; >> 7 = << 1, then the top two bytes
    rol et24+1
    rol et24+2
    lda #199                    ; ey = 199 - t
    sec
    sbc et24+1
    sta ey
    lda #0
    sbc et24+2
    sta ey+1
    rts
etd_c64:                        ; Y >> 2 (C64 modes, Upic Lite)
    ldx #2
etd_c64s:
    lda et24+1
    cmp #$80
    ror et24+1
    ror et24
    dex
    bne etd_c64s
    lda vmode_ymax
    sec
    sbc et24
    sta ey
    lda #0
    sbc et24+1
    sta ey+1
    rts

; ----------------------------------------------------------------------------
; e_plot
;   Summary: VDU 25,k,x;y; (PLOT).
;   Function: works out the new point (relative to the graphics cursor
;            when k AND 4 = 0), moves the cursors (previous point kept for
;            triangles and rectangles) and draws per group k DIV 8:
;            0-7 lines (solid/dotted, end points omitted or not), 8 point,
;            12 rectangle fill. k AND 3 = 0 only moves. Other groups
;            follow (docs/DESIGN_GRAPHICS.md section 9.4).
;   Input:   vdubuf: k, x lo, x hi, y lo, y hi.
e_plot:
    lda vdubuf+1
    sta pk_x
    lda vdubuf+2
    sta pk_x+1
    lda vdubuf+3
    sta pk_y
    lda vdubuf+4
    sta pk_y+1
    lda vdubuf
    and #4
    bne ep_abs
    lda pk_x                    ; relative: add the graphics cursor
    clc
    adc gcx
    sta pk_x
    lda pk_x+1
    adc gcx+1
    sta pk_x+1
    lda pk_y
    clc
    adc gcy
    sta pk_y
    lda pk_y+1
    adc gcy+1
    sta pk_y+1
ep_abs:
    lda gcx                     ; previous point
    sta gpx
    lda gcx+1
    sta gpx+1
    lda gcy
    sta gpy
    lda gcy+1
    sta gpy+1
    lda pk_x                    ; new cursor
    sta gcx
    lda pk_x+1
    sta gcx+1
    lda pk_y
    sta gcy
    lda pk_y+1
    sta gcy+1
    lda vdubuf
    and #3
    bne ep_draw
    rts                         ; move only
ep_draw:
    jsr e_setcol
    lda vdubuf
    lsr
    lsr
    lsr                         ; group
    cmp #8
    bcc ep_line
    bne ep_n8
    jsr e_todev                 ; 8: point
    jmp e_pset
ep_n8:
    cmp #12
    bne ep_n12
    jmp e_rectplot
ep_n12:
    rts                         ; not yet: ignored

; e_setcol: colour and action from k AND 3 (1 fg, 2 inverse, 3 bg)
e_setcol:
    lda vdubuf
    and #3
    cmp #2
    beq esc_inv
    bcs esc_bg
    lda gfg
    sta ecol
    lda gact_fg
    sta eact
    rts
esc_bg:
    lda gbg
    sta ecol
    lda gact_bg
    sta eact
    rts
esc_inv:
    lda #4
    sta eact
    lda #0
    sta ecol
    rts

; ep_line: group 0-7, from the previous point to the new one
ep_line:
    tax
    lda lineflags,x
    sta eflags
    lda gcx                     ; end point
    sta pk_x
    lda gcx+1
    sta pk_x+1
    lda gcy
    sta pk_y
    lda gcy+1
    sta pk_y+1
    jsr e_todev
    lda ex
    sta eline_x1
    lda ex+1
    sta eline_x1+1
    lda ey
    sta eline_y1
    lda ey+1
    sta eline_y1+1
    lda gpx                     ; start point
    sta pk_x
    lda gpx+1
    sta pk_x+1
    lda gpy
    sta pk_y
    lda gpy+1
    sta pk_y+1
    jsr e_todev
    lda ex
    sta eline_x0
    lda ex+1
    sta eline_x0+1
    lda ey
    sta eline_y0
    lda ey+1
    sta eline_y0+1
    jmp e_line

; ----------------------------------------------------------------------------
; e_line
;   Summary: Bresenham line in device pixels, clipped per pixel.
;   Input:   eline_x0/y0 -> eline_x1/y1, eflags, ecol/eact.
;   Uses:    A, X, Y, ex, ey, edx, edy, eerr, ecount.
e_line:
    lda #0
    sta edot
    lda #1
    sta efirst
    lda eline_x0
    sta ex
    lda eline_x0+1
    sta ex+1
    lda eline_y0
    sta ey
    lda eline_y0+1
    sta ey+1
    ; dx = |x1 - x0|, sx
    lda #1
    sta esx
    lda eline_x1
    sec
    sbc eline_x0
    sta edx
    lda eline_x1+1
    sbc eline_x0+1
    sta edx+1
    bpl el_dxp
    lda #$FF
    sta esx
    lda #0
    sec
    sbc edx
    sta edx
    lda #0
    sbc edx+1
    sta edx+1
el_dxp:
    ; dy = |y1 - y0|, sy
    lda #1
    sta esy
    lda eline_y1
    sec
    sbc eline_y0
    sta edy
    lda eline_y1+1
    sbc eline_y0+1
    sta edy+1
    bpl el_dyp
    lda #$FF
    sta esy
    lda #0
    sec
    sbc edy
    sta edy
    lda #0
    sbc edy+1
    sta edy+1
el_dyp:
    ; count = max(dx, dy) + 1 pixels
    lda edx
    cmp edy
    lda edx+1
    sbc edy+1
    bcc el_ymajor
    lda edx
    sta ecount
    lda edx+1
    sta ecount+1
    lda edx+1                   ; err = dx / 2
    lsr
    sta eerr+1
    lda edx
    ror
    sta eerr
    jmp el_xloop
el_ymajor:
    lda edy
    sta ecount
    lda edy+1
    sta ecount+1
    lda edy+1
    lsr
    sta eerr+1
    lda edy
    ror
    sta eerr
    jmp el_yloop

; x major: x every step, y when err goes below 0 (err -= dy, += dx)
el_xloop:
    jsr el_pixel
    lda ecount
    ora ecount+1
    beq el_done
    jsr el_dec
    jsr el_stepx
    lda eerr
    sec
    sbc edy
    sta eerr
    lda eerr+1
    sbc edy+1
    sta eerr+1
    bpl el_xloop
    jsr el_stepy
    lda eerr
    clc
    adc edx
    sta eerr
    lda eerr+1
    adc edx+1
    sta eerr+1
    jmp el_xloop

el_yloop:
    jsr el_pixel
    lda ecount
    ora ecount+1
    beq el_done
    jsr el_dec
    jsr el_stepy
    lda eerr
    sec
    sbc edx
    sta eerr
    lda eerr+1
    sbc edx+1
    sta eerr+1
    bpl el_yloop
    jsr el_stepx
    lda eerr
    clc
    adc edy
    sta eerr
    lda eerr+1
    adc edy+1
    sta eerr+1
    jmp el_yloop
el_done:
    rts

el_dec:
    lda ecount
    bne eld_lo
    dec ecount+1
eld_lo:
    dec ecount
    inc eyield                  ; let interrupts in every 256 pixels
    bne eld_ok
    jsr gx_yield
eld_ok:
    rts
el_stepx:
    lda esx
    bmi elx_neg
    inc ex
    bne elx_ok
    inc ex+1
elx_ok:
    rts
elx_neg:
    lda ex
    bne elx_lo
    dec ex+1
elx_lo:
    dec ex
    rts
el_stepy:
    lda esy
    bmi ely_neg
    inc ey
    bne ely_ok
    inc ey+1
ely_ok:
    rts
ely_neg:
    lda ey
    bne ely_lo
    dec ey+1
ely_lo:
    dec ey
    rts

; el_pixel: one line pixel, unless omitted (first/last) or a dot gap
el_pixel:
    lda efirst
    beq elp_notfirst
    lda #0
    sta efirst
    lda eflags
    and #2
    bne elp_skip
elp_notfirst:
    lda ecount
    ora ecount+1
    bne elp_notlast
    lda eflags
    and #4
    bne elp_skip
elp_notlast:
    lda eflags
    and #1
    beq elp_draw
    lda edot                    ; dotted: every second pixel
    eor #1
    sta edot
    beq elp_skip
elp_draw:
    jmp e_pset
elp_skip:
    rts

; ----------------------------------------------------------------------------
; e_rectplot: group 12, filled rectangle between the previous point and
; the new one (both corners included)
e_rectplot:
    jsr e_todev                 ; new point (pk_x/pk_y)
    lda ex
    sta erx1
    lda ex+1
    sta erx1+1
    lda ey
    sta ery1
    lda ey+1
    sta ery1+1
    lda gpx
    sta pk_x
    lda gpx+1
    sta pk_x+1
    lda gpy
    sta pk_y
    lda gpy+1
    sta pk_y+1
    jsr e_todev
    lda ex
    sta erx0
    lda ex+1
    sta erx0+1
    lda ey
    sta ery0
    lda ey+1
    sta ery0+1
    jmp e_rect

; e_clg: VDU 16, the graphics window in the background colour (its action)
e_clg:
    lda gbg
    sta ecol
    lda gact_bg
    sta eact
    lda gwl
    sta erx0
    lda gwl+1
    sta erx0+1
    lda gwr
    sta erx1
    lda gwr+1
    sta erx1+1
    lda gwt
    sta ery0
    lda gwt+1
    sta ery0+1
    lda gwb
    sta ery1
    lda gwb+1
    sta ery1+1
    jmp e_rect

; ----------------------------------------------------------------------------
; e_rect
;   Summary: fill a rectangle of device pixels, clipped to the graphics
;            window, with ecol/eact.
;   Function: normalises the corners, clips, then per row: single pixels
;            up to a byte boundary, whole bytes (8 hires / 4 multicolour
;            pixels at once), single pixels after.
;   Input:   erx0/ery0, erx1/ery1 (any order).
;   Uses:    A, X, Y, ex, ey, emask.
e_rect:
    ldx #erx0-ex                ; order x
    ldy #erx1-ex
    jsr er_order
    ldx #ery0-ex
    ldy #ery1-ex
    jsr er_order
    lda enoclip
    beq er_clip
    jmp er_y1ok
er_clip:                        ; clip to the graphics window
    lda erx0                    ; x0 = max(x0, gwl)
    cmp gwl
    lda erx0+1
    sbc gwl+1
    bvc er_c1
    eor #$80
er_c1:
    bpl er_x0ok
    lda gwl
    sta erx0
    lda gwl+1
    sta erx0+1
er_x0ok:
    lda gwr                     ; x1 = min(x1, gwr)
    cmp erx1
    lda gwr+1
    sbc erx1+1
    bvc er_c2
    eor #$80
er_c2:
    bpl er_x1ok
    lda gwr
    sta erx1
    lda gwr+1
    sta erx1+1
er_x1ok:
    lda ery0
    cmp gwt
    lda ery0+1
    sbc gwt+1
    bvc er_c3
    eor #$80
er_c3:
    bpl er_y0ok
    lda gwt
    sta ery0
    lda gwt+1
    sta ery0+1
er_y0ok:
    lda gwb
    cmp ery1
    lda gwb+1
    sbc ery1+1
    bvc er_c4
    eor #$80
er_c4:
    bpl er_y1ok
    lda gwb
    sta ery1
    lda gwb+1
    sta ery1+1
er_y1ok:
    ; empty after clipping?
    lda erx1
    cmp erx0
    lda erx1+1
    sbc erx0+1
    bvc er_c5
    eor #$80
er_c5:
    bmi er_none
    lda ery1
    cmp ery0
    lda ery1+1
    sbc ery0+1
    bvc er_c6
    eor #$80
er_c6:
    bmi er_none
    lda ery0
    sta ey
    lda #0
    sta ey+1
er_row:
    jsr e_span
    jsr gx_yield
    lda ey
    cmp ery1
    beq er_none
    inc ey
    bne er_row
er_none:
    rts

; er_order: make variable X (offset from ex) <= variable Y, signed
er_order:
    lda ex,x
    cmp ex,y
    lda ex+1,x
    sbc ex+1,y
    bvc ero_v
    eor #$80
ero_v:
    bmi ero_ok
    lda ex,x
    pha
    lda ex,y
    sta ex,x
    pla
    sta ex,y
    lda ex+1,x
    pha
    lda ex+1,y
    sta ex+1,x
    pla
    sta ex+1,y
ero_ok:
    rts

; e_span: row ey from erx0 to erx1 (inside the screen)
e_span:
    lda erx0
    sta ex
    lda erx0+1
    sta ex+1
es_head:                        ; single pixels up to a byte boundary
    jsr es_atend
    bcc es_done
    lda ex
    and vmode_ppbm
    beq es_body
    jsr e_pixel
    jsr es_next
    jmp es_head
es_body:                        ; whole bytes while x + ppb - 1 <= x1
    lda ex
    clc
    adc vmode_ppbm
    sta etmp
    lda ex+1
    adc #0
    sta etmp+1
    lda erx1
    cmp etmp
    lda erx1+1
    sbc etmp+1
    bcc es_tail
    jsr e_bytepix
    lda ex
    sec                         ; + ppb (C = 1 adds the 1)
    adc vmode_ppbm
    sta ex
    bcc es_body
    inc ex+1
    bne es_body
es_tail:
    jsr es_atend
    bcc es_done
    jsr e_pixel
    jsr es_next
    jmp es_tail
es_done:
    rts
es_next:
    inc ex
    bne esn_ok
    inc ex+1
esn_ok:
    rts
; es_atend: C = 0 when ex > erx1 (past the end), C = 1 otherwise
es_atend:
    lda erx1
    cmp ex
    lda erx1+1
    sbc ex+1
    rts

; ----------------------------------------------------------------------------
; e_pset
;   Summary: plot the pixel ex/ey if it is inside the graphics window.
e_pset:
    jsr e_inwin
    bcs e_pixel
    rts

; e_inwin: C = 1 if ex/ey is inside the graphics window (signed)
e_inwin:
    lda ex                      ; ex >= gwl
    cmp gwl
    lda ex+1
    sbc gwl+1
    jsr eiw_sign
    bmi eiw_out
    lda gwr                     ; ex <= gwr
    cmp ex
    lda gwr+1
    sbc ex+1
    jsr eiw_sign
    bmi eiw_out
    lda ey
    cmp gwt
    lda ey+1
    sbc gwt+1
    jsr eiw_sign
    bmi eiw_out
    lda gwb
    cmp ey
    lda gwb+1
    sbc ey+1
    jsr eiw_sign
    bmi eiw_out
    sec
    rts
eiw_out:
    clc
    rts
; eiw_sign: N = sign of a signed subtraction's true result (after SBC)
eiw_sign:
    bvc eis_ok
    eor #$80
eis_ok:
    ora #0                      ; N from A (V may be set: harmless)
    rts

; ----------------------------------------------------------------------------
; e_pixel / e_bytepix
;   Summary: apply colour ecol with action eact to one pixel (e_pixel) or
;            to the whole byte holding ex (e_bytepix), on screen.
;   Function: gzp = byte address, emask = the pixel's bits; evrep = the
;            colour value repeated over the byte (hires: $00/$FF, the
;            logical colour's bit; multicolour: the 2-bit value x $55).
;            16-colour modes first choose the cell's colour slot (e_cell).
;            Actions: 0 store, 1 OR, 2 AND, 3 EOR, 4 invert, as GCOL.
;   Input:   ex (0..xmax), ey (0..199).
;   Uses:    A, X, Y, gzp.
e_bytepix:
    lda #$FF
    sta emask
    jmp ep_addr
e_pixel:
    lda vmode_mc
    bne epx_mc
    lda ex
    and #7
    tax
    .if GXUL
    lda ul1mask,x
    .else
    lda hmask,x
    .endif
    sta emask
    jmp ep_addr
epx_mc:
    lda ex
    and #3
    tax
    .if GXUL
    lda ul2mask,x
    .else
    lda mcmask,x
    .endif
    sta emask
ep_addr:
    jsr ep_addr_only
ep_value:
    lda eact                    ; invert needs no colour value
    cmp #4
    bcs ep_apply
    .if GXUL = 0
    lda vmode_ncol
    cmp #16
    bne epv_direct
    jsr e_cell                  ; 16 colours: slot for ecol in this cell
    jmp ep_apply
    .endif
epv_direct:
    lda ecol
    ldx vmode_mc
    bne epv_mc
    and #1                      ; hires: logical colour's bit
    beq epv_set
    lda #$FF
    bne epv_set
epv_mc:
    and #3
    tax
    lda mcrep,x
epv_set:
    sta evrep
ep_apply:
    ldy #0
    ldx eact
    beq eap_store
    dex
    beq eap_or
    dex
    beq eap_and
    dex
    beq eap_eor
    lda (gzp),y                 ; 4 (and above): invert
    eor emask
    sta (gzp),y
    rts
eap_store:
    lda emask
    eor #$FF
    and (gzp),y
    sta etmp
    lda evrep
    and emask
    ora etmp
    sta (gzp),y
    rts
eap_or:
    lda evrep
    and emask
    ora (gzp),y
    sta (gzp),y
    rts
eap_and:
    lda emask
    eor #$FF
    ora evrep
    and (gzp),y
    sta (gzp),y
    rts
eap_eor:
    lda evrep
    and emask
    eor (gzp),y
    sta (gzp),y
    rts

    .if GXUL = 0
; ----------------------------------------------------------------------------
; e_cell
;   Summary: 16-colour modes: find (or make) a slot for colour ecol in the
;            pixel's cell and set evrep to that slot's value.
;   Function: physical colour p = pal[ecol]. Hires: low nybble of the
;            matrix byte = background (value 0), high = foreground (1);
;            p = background gives 0, else the foreground becomes p.
;            Multicolour: 0 = $D021 (pal[0]), 1 = matrix high, 2 = matrix
;            low, 3 = colour RAM; a colour not in the cell replaces slot 3
;            (colour clash, as on the C64).
;   Uses:    A, X, ecell, etmp+1, mosTMP is not used.
e_cell:
    jsr e_cellidx               ; ecell, matrix byte in etmp
    lda ecol
    and #15
    tax
    lda pal,x
    sta etmp+1                  ; p
    lda vmode_mc
    bne ecl_mcslots
    lda etmp                    ; hires
    and #15
    cmp etmp+1
    beq ecl_v0
    lda etmp
    and #15
    sta etmp
    lda etmp+1
    asl
    asl
    asl
    asl
    ora etmp
    jsr eci_wr
    lda #$FF
    sta evrep
    rts
ecl_v0:
    lda #0
    sta evrep
    rts
ecl_mcslots:
    lda etmp+1
    cmp pal
    beq ecl_v0
    lda etmp
    lsr
    lsr
    lsr
    lsr
    cmp etmp+1
    beq ecl_v1
    lda etmp
    and #15
    cmp etmp+1
    beq ecl_v2
    jsr io_colget               ; colour RAM of ecell
    and #15
    cmp etmp+1
    beq ecl_v3
    lda etmp+1                  ; not there: slot 3 becomes p
    jsr io_colput
ecl_v3:
    lda #$FF
    sta evrep
    rts
ecl_v1:
    lda #$55
    sta evrep
    rts
ecl_v2:
    lda #$AA
    sta evrep
    rts

    .endif

; ----------------------------------------------------------------------------
; e_point
;   Summary: POINT(x,y): logical colour at pk_x/pk_y (OS units) in
;            gx_res, or $FF outside the graphics window.
e_point:
    jsr e_todev
    lda #$FF
    sta gx_res
    jsr e_inwin
    bcc ept_out
    jsr ept_byte
    sta gx_res
ept_out:
    rts

    .if GXUL = 0
; ept_byte: A = logical colour of the pixel ex/ey (2/4-colour modes: the
; bits; 16-colour modes: the cell colour, mapped back through pal[])
ept_byte:
    lda vmode_mc
    bne eptb_mc
    lda ex
    and #7
    tax
    lda hmask,x
    sta emask
    jsr ep_addr_only
    ldy #0
    lda (gzp),y
    and emask
    beq eptb_zero
    lda #1
eptb_zero:
    ldx vmode_ncol
    cpx #16
    bne eptb_done
    jmp ept_map16
eptb_mc:
    lda ex
    and #3
    tax
    lda mcmask,x
    sta emask
    stx etmp                    ; pixel 0-3 in the byte
    jsr ep_addr_only
    ldy #0
    lda (gzp),y
    and emask
    ldx etmp                    ; shift down by 2 * (3 - pixel)
eptb_sh:
    cpx #3
    beq eptb_v
    lsr
    lsr
    inx
    bne eptb_sh
eptb_v:
    ldx vmode_ncol
    cpx #16
    bne eptb_done
    jmp ept_map16
eptb_done:
    rts

; ep_addr_only: gzp = byte address of ex/ey
ep_addr_only:
    lda ey
    jsr e_rowbase
    sta gzp
    stx gzp+1
    lda vmode_mc
    bne epo_mc
    lda ex                      ; hires: + (x AND $1F8)
    and #$F8
    clc
    adc gzp
    sta gzp
    lda ex+1
    adc gzp+1
    sta gzp+1
    rts
epo_mc:
    lda ex                      ; multicolour: + (x AND $FC) * 2
    and #$FC
    asl
    bcc epo_nc
    inc gzp+1
epo_nc:
    clc
    adc gzp
    sta gzp
    bcc epo_done
    inc gzp+1
epo_done:
    rts

; e_rowbase: A = pixel row (0-199) -> A/X = bitmap address of its first
; byte
e_rowbase:
    pha
    lsr
    lsr
    lsr
    tax
    pla
    and #7
    clc
    adc crowlo,x
    pha
    lda crowhi,x
    adc #0
    tax
    pla
    rts

; ept_map16: A = slot value -> physical colour of the cell -> logical
ept_map16:
    sta esqt                    ; slot value
    jsr e_cellidx               ; ecell, matrix byte in etmp
    lda vmode_mc
    bne epm_mc
    lda esqt
    beq epm_bg
    lda etmp
    lsr
    lsr
    lsr
    lsr
    jmp epm_find
epm_bg:
    lda etmp
    and #15
    jmp epm_find
epm_mc:
    lda esqt
    beq epm_d021
    cmp #1
    beq epm_hi
    cmp #2
    beq epm_lo
    jsr io_colget
    and #15
    jmp epm_find
epm_hi:
    lda etmp
    lsr
    lsr
    lsr
    lsr
    jmp epm_find
epm_lo:
    lda etmp
    and #15
    jmp epm_find
epm_d021:
    lda pal
epm_find:                       ; the first logical colour showing it
    ldx #0
epf_loop:
    cmp pal,x
    beq epf_got
    inx
    cpx #16
    bne epf_loop
    ldx #0
epf_got:
    txa
    rts

; e_cellidx: ecell for ex/ey, matrix byte into etmp; eci_wr writes A
; back to that cell
e_cellidx:
    lda ey
    lsr
    lsr
    lsr
    tay
    lda vmode_mc
    bne eci_mc
    lda ex+1
    lsr
    lda ex
    ror
    lsr
    lsr
    jmp eci_idx
eci_mc:
    lda ex
    lsr
    lsr
eci_idx:
    clc
    adc cofflo,y
    sta ecell
    lda coffhi,y
    adc #0
    sta ecell+1
    lda ecell
    clc
    adc #<SCREEN
    sta eci_rd+1
    sta eci_wr+1
    lda ecell+1
    adc #>SCREEN
    sta eci_rd+2
    sta eci_wr+2
eci_rd:
    lda SCREEN
    sta etmp
    rts
eci_wr:
    sta SCREEN
    rts

    .else
; ept_byte (Upic Lite): A = logical colour of the pixel ex/ey
ept_byte:
    jsr ep_addr_only
    ldy #0
    lda (gzp),y
    sta etmp
    lda vmode_mc
    bne eub_2
    lda ex                      ; 1 bit: shift by x AND 7
    and #7
    tax
    lda etmp
eub_1:
    dex
    bmi eub_1d
    lsr
    jmp eub_1
eub_1d:
    and #1
    rts
eub_2:
    lda ex                      ; 2 bits: shift by 2 * (x AND 3)
    and #3
    tax
    lda etmp
eub_2l:
    dex
    bmi eub_2d
    lsr
    lsr
    jmp eub_2l
eub_2d:
    and #3
    rts

; ep_addr_only (Upic Lite): gzp = vmode_bufhi + byte column pages, + ey
ep_addr_only:
    lda ex+1                    ; byte column = x >> 3 (1 bit) or >> 2
    lsr
    lda ex
    ror
    lsr
    ldx vmode_mc
    bne eua_2
    lsr
eua_2:
    clc
    adc vmode_bufhi
    sta gzp+1
    lda ey
    sta gzp
    rts

ul1mask:
    dta $01, $02, $04, $08, $10, $20, $40, $80
ul2mask:
    dta $03, $0C, $30, $C0

    .endif

; ----------------------------------------------------------------------------
; Text in bitmap modes

; e_txy: top-left pixel of the text cursor's cell into ex/ey
e_txy:
    lda tcx                     ; x = column * cell width
    ldx vmode_cw
    jsr e_mul8
    sta ex
    stx ex+1
    lda vmode_ch
    cmp #8
    bne etx_6
    lda tcy
    asl
    asl
    asl
    sta ey
    lda #0
    sta ey+1
    rts
etx_6:
    ldx tcy
    lda row6,x
    sta ey
    lda #0
    sta ey+1
    rts

; e_mul8: A * X -> A (low) / X (high)
e_mul8:
    sta etmp
    stx etmp+1
    lda #0
    ldx #0
    ldy #8
em8_loop:
    asl
    pha
    txa
    rol
    tax
    pla
    asl etmp
    bcc em8_next
    clc
    adc etmp+1
    bcc em8_next
    inx
em8_next:
    dey
    bne em8_loop
    rts

; ----------------------------------------------------------------------------
; e_char
;   Summary: draw the glyph in glyph[] at the text cursor, in the text
;            colours (COLOUR), and move the cursor on (wrapping and
;            scrolling in the text window).
;   Function: per glyph row (all 8, or 6 of them for 6-line fonts), per
;            pixel of the cell: the glyph bit chooses tfg or tbg. 4-pixel
;            wide cells OR adjacent glyph bit pairs.
e_char:
    jsr e_txy
    jsr e_glyphcell
    jmp e_advance

; e_glyphcell: the glyph at ex/ey (cell origin)
e_glyphcell:
    .if GXUL = 0
    lda vmode_ch
    cmp #8
    beq egc_go
    jsr e_rows6
egc_go:
    .endif
    lda #0
    sta eact                    ; text is drawn with "store"
    sta egrow
    lda ex
    sta erx0
    lda ex+1
    sta erx0+1
egc_row:
    ldx egrow
    lda vmode_ch
    cmp #8
    beq egc_8
    lda erows,x
    tax
egc_8:
    lda glyph,x
    ldx vmode_cw
    cpx #4
    bne egc_bits
    jsr e_squeeze               ; 8 bits -> 4 in the top nybble
egc_bits:
    sta egbits
    lda erx0
    sta ex
    lda erx0+1
    sta ex+1
    lda vmode_cw
    sta ecount
egc_pix:
    asl egbits
    lda tbg
    bcc egc_col
    lda tfg
egc_col:
    sta ecol
    jsr e_pixel
    inc ex
    bne egc_x
    inc ex+1
egc_x:
    dec ecount
    bne egc_pix
    inc ey
    inc egrow
    lda egrow
    cmp vmode_ch
    bne egc_row
    rts

    .if GXUL = 0
; e_rows6
;   Summary: the 6 glyph rows to draw in a 6-line cell, per glyph.
;   Function: drops row 7 if it is blank (capitals, most signs), else row
;            0 (descenders), then the first row equal to the next kept
;            one (C64 glyphs repeat their stems), else row 2 (keeps the
;            tip of > and <, the strokes of Z).
;   Input:   glyph[].  Output: erows[0..5] = row numbers.  Uses: A, X, Y.
e_rows6:
    lda #7
    ldx glyph+7
    beq er6_a
    lda #0
er6_a:
    sta er6a
    ldy #0
er6_dup:
    cpy er6a
    beq er6_next
    tya                         ; the next kept row
    tax
    inx
    cpx er6a
    bne er6_cmp
    inx
er6_cmp:
    cpx #8
    bcs er6_none
    lda glyph,y
    cmp glyph,x
    beq er6_got
er6_next:
    iny
    cpy #7
    bne er6_dup
er6_none:
    ldy #2
er6_got:
    sty er6b
    ldx #0
    ldy #0
er6_list:
    cpy er6a
    beq er6_skip
    cpy er6b
    beq er6_skip
    tya
    sta erows,x
    inx
er6_skip:
    iny
    cpy #8
    bne er6_list
    rts

    .endif

; e_squeeze: A = 8 glyph bits -> 4 bits in the top nybble, each the OR
; of a pair (for 4-pixel wide cells)
e_squeeze:
    sta esqt
    lda #0
    sta esqt+1
    ldx #4
esq_loop:
    lda esqt
    and #$C0
    cmp #1                      ; C = 1 if either bit of the pair is set
    rol esqt+1
    asl esqt
    asl esqt
    dex
    bne esq_loop
    lda esqt+1                  ; 4 bits, first pair highest: to the top
    asl
    asl
    asl
    asl
    rts

; e_advance: cursor right; past the window's right edge: next line
e_advance:
    lda tcx
    cmp twr
    bcs ead_wrap
    inc tcx
    rts
ead_wrap:
    lda twl
    sta tcx
    jmp e_down

; e_down: cursor down; at the window's bottom: scroll the window up
e_down:
    lda tcy
    cmp twb
    bcs edn_scroll
    inc tcy
    rts
edn_scroll:
    jmp e_scroll

; ----------------------------------------------------------------------------
    .if GXUL = 0
; e_scroll
;   Summary: scroll the text window up one text row and clear the bottom
;            row in the text background.
;   Function: per text row: its pixel lines take those of the row below
;            (whole bytes of the window's columns), then the last row is
;            filled. Works for 8- and 6-line rows.
e_scroll:
    jsr e_winbytes
    lda twt
    sta ecount                  ; destination text row
esc_rowloop:
    lda ecount
    cmp twb
    bcs esc_last
    ldx #0                      ; line in the row
esc_line:
    stx ecount+1
    lda ecount                  ; destination line address + window offset
    jsr e_rowline_x
    clc
    adc ewb_first
    sta esc_dst+1
    txa
    adc ewb_first+1
    sta esc_dst+2
    lda ecount                  ; source: the same line one text row down
    clc
    adc #1
    ldx ecount+1
    jsr e_rowline_x
    clc
    adc ewb_first
    sta esc_src+1
    txa
    adc ewb_first+1
    sta esc_src+2
    ldy #0
    ldx ewb_count
esc_byte:
esc_src:
    lda $FFFF,y
esc_dst:
    sta $FFFF,y
    tya                         ; next byte of the window: +8
    clc
    adc #8
    tay
    bcc esc_nc
    inc esc_src+2
    inc esc_dst+2
esc_nc:
    dex
    bne esc_byte
    ldx ecount+1
    inx
    cpx vmode_ch
    bne esc_line
    lda ecount                  ; 6-line rows: clear a gap line below
    jsr e_gapclear
    jsr gx_yield
    inc ecount
    jmp esc_rowloop
esc_last:
    lda twb                     ; clear the bottom row
    jmp e_clearrow

; e_rowline_x: A = text row, X = line in it -> A/X = bitmap address of
; that pixel line's first byte (column 0)
e_rowline_x:
    stx etmp
    tay
    lda vmode_ch
    cmp #8
    bne erl_6
    tya
    asl
    asl
    asl
    jmp erl_add
erl_6:
    lda row6,y
erl_add:
    clc
    adc etmp
    jmp e_rowbase

; e_winbytes: offset of the window's left byte in a pixel row
; (ewb_first, 16 bits: byte column * 8) and its width in bytes
; (ewb_count). 4-pixel hires cells round outward to whole bytes.
e_winbytes:
    lda twl                     ; left pixel = twl * cw
    ldx vmode_cw
    jsr e_mul8
    sta etmp
    stx etmp+1
    lda vmode_mc                ; pixel -> byte column
    bne ewb_mc
    lsr etmp+1
    ror etmp
    lsr etmp
    lsr etmp                    ; / 8 (hires)
    jmp ewb_f
ewb_mc:
    lsr etmp
    lsr etmp                    ; / 4 (multicolour, < 160)
ewb_f:
    lda etmp                    ; first byte column
    pha
    sta ewb_first
    lda #0
    sta ewb_first+1
    asl ewb_first               ; * 8
    rol ewb_first+1
    asl ewb_first
    rol ewb_first+1
    asl ewb_first
    rol ewb_first+1
    lda twr                     ; end pixel = (twr + 1) * cw
    clc
    adc #1
    ldx vmode_cw
    jsr e_mul8
    sta etmp
    stx etmp+1
    lda vmode_mc
    bne ewb_mc2
    lda etmp                    ; round up to a whole byte
    clc
    adc #7
    sta etmp
    bcc ewb_h
    inc etmp+1
ewb_h:
    lsr etmp+1
    ror etmp
    lsr etmp
    lsr etmp
    jmp ewb_c
ewb_mc2:
    lda etmp
    clc
    adc #3
    lsr
    lsr
    sta etmp
ewb_c:
    pla                         ; width = end column - first column
    sta etmp+1
    lda etmp
    sec
    sbc etmp+1
    sta ewb_count
    rts

; e_gapclear: 6-line rows are spread over 200 lines (row6): a row with
; 7 lines to the next one has a gap line, kept in the text background
e_gapclear:
    ldx vmode_ch
    cpx #6
    bne egp_none
    tay
    lda row6+1,y                ; next row's top (row 31: line 199 + 1)
    cpy #31
    bne egp_next
    lda #200
egp_next:
    sec
    sbc row6,y
    cmp #7
    bcc egp_none
    lda row6,y                  ; the gap line: top + 6
    clc
    adc #6
    sta ery0
    sta ery1
    lda #0
    sta ery0+1
    sta ery1+1
    jsr ecr_x                   ; window columns, background, then fill
egp_none:
    rts

    .else
; e_scroll (Upic Lite)
;   Summary: scroll the text window up one text row (8 lines) and clear
;            the bottom row: per byte column of the window, the bytes of
;            its lines move up 8 (column-major buffer).
e_scroll:
    jsr eus_cols
    lda twt                     ; first line, and the last row's first
    asl
    asl
    asl
    sta eus_y0
    lda twb
    asl
    asl
    asl
    sta eus_y1
    ldx eus_c0
eus_col:
    txa
    clc
    adc vmode_bufhi
    sta eus_src+2
    sta eus_dst+2
    ldy eus_y0
eus_y:
    cpy eus_y1
    bcs eus_next
eus_src:
    lda $FF08,y                 ; line y + 8 (y + 8 < 256: same column)
eus_dst:
    sta $FF00,y
    iny
    bne eus_y
eus_next:
    stx eus_x
    jsr gx_yield
    ldx eus_x
    cpx eus_c1
    inx
    bcc eus_col
    lda twb
    jmp e_clearrow

; eus_cols: byte columns of the text window: eus_c0 .. eus_c1
eus_cols:
    lda twl
    ldx vmode_cw
    jsr e_mul8
    jsr eus_tocol
    sta eus_c0
    lda twr
    clc
    adc #1
    ldx vmode_cw
    jsr e_mul8
    sec                         ; last pixel = end - 1
    sbc #1
    bcs eus_nb
    dex
eus_nb:
    jsr eus_tocol
    sta eus_c1
    rts
; eus_tocol: pixel A (low) / X (high) -> byte column in A
eus_tocol:
    stx etmp
    lsr etmp
    ror
    lsr
    ldx vmode_mc
    bne eut_2
    lsr
eut_2:
    rts

eus_y0  dta 0
eus_y1  dta 0
eus_c0  dta 0
eus_c1  dta 0
eus_x   dta 0

    .endif

; e_clearrow: text row A, window columns, in the text background (and its
; gap line, if any)
e_clearrow:
    .if GXUL = 0
    pha
    jsr e_gapclear
    pla
    .endif
    sta ecrow
    ldy ecrow
    lda vmode_ch
    cmp #8
    bne ecr_6
    tya
    asl
    asl
    asl
    jmp ecr_y
ecr_6:
    lda row6,y
ecr_y:
    sta ery0
    clc
    adc vmode_ch
    sec
    sbc #1
    sta ery1
    lda #0
    sta ery0+1
    sta ery1+1
ecr_x:                          ; columns of the window, then fill
    lda tbg
    sta ecol
    lda #0
    sta eact
    lda twl
    ldx vmode_cw
    jsr e_mul8
    sta erx0
    stx erx0+1
    lda twr
    clc
    adc #1
    ldx vmode_cw
    jsr e_mul8
    sec
    sbc #1
    sta erx1
    txa
    sbc #0
    sta erx1+1
    jmp e_rectscreen

; e_rectscreen: e_rect without the graphics window (text uses the text
; window, already in erx/ery)
e_rectscreen:
    lda #1
    sta enoclip
    jsr e_rect
    lda #0
    sta enoclip
    rts

; e_cls: VDU 12, the text window in the text background; cursor home
e_cls:
    lda twt
ecls_row:
    pha
    jsr e_clearrow
    pla
    cmp twb
    bcs ecls_done
    adc #1                      ; C = 0 here
    bne ecls_row
ecls_done:
    lda twl
    sta tcx
    lda twt
    sta tcy
    rts

; ----------------------------------------------------------------------------
; e_pet
;   Summary: the PETSCII cursor and control codes the MOS sends in bitmap
;            modes (the text-mode screen editor's codes).
;   Input:   A = $0D return, $9D left, $1D right, $11 down, $91 up,
;            $93 clear, $13 home, $14 delete (left, blank, left).
e_pet:
    cmp #$0D
    bne ept_n0d
    lda twl                     ; newline: column 0 of the window, down
    sta tcx
    jmp e_down
ept_n0d:
    cmp #$9D
    bne ept_n9d
    lda tcx                     ; left; at the left edge: end of the line
    cmp twl                     ; above (as the BBC)
    beq ept_lwrap
    bcc ept_lwrap
    dec tcx
    rts
ept_lwrap:
    lda twr
    sta tcx
    lda tcy
    cmp twt
    beq ept_ok
    dec tcy
ept_ok:
    rts
ept_n9d:
    cmp #$1D
    bne ept_n1d
    jmp e_advance
ept_n1d:
    cmp #$11
    bne ept_n11
    jmp e_down
ept_n11:
    cmp #$91
    bne ept_n91
    lda tcy
    cmp twt
    beq ept_ok
    dec tcy
    rts
ept_n91:
    cmp #$93
    bne ept_n93
    jmp e_cls
ept_n93:
    cmp #$13
    bne ept_n13
    lda twl
    sta tcx
    lda twt
    sta tcy
    rts
ept_n13:
    rts

; e_cursor: invert the bottom line of the cursor's cell (shown/hidden)
e_cursor:
    jsr e_txy
    lda ey
    clc
    adc vmode_ch
    sec
    sbc #1
    sta ey
    lda #4
    sta eact
    lda vmode_cw
    sta ecount
ecu_loop:
    jsr e_pixel
    inc ex
    bne ecu_x
    inc ex+1
ecu_x:
    dec ecount
    bne ecu_loop
    rts

engine_end:
    .if engine_end > ENGINE+$1000
    .error "Drawing engine overflows its 4K"
    .endif
    :[ENGINE+$1000-*] dta 0
