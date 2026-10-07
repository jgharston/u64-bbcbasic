; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- teletext engine (MODE 7), runs from RAM at ENGINE
;
; Copied to $D000 by bank 3 when MODE 7 is selected (bk_mode); the VIC-II
; engine comes back for other modes. Same jump table as gfx.s; runs with
; $01 = $34 through gx_call.
;
; Screen: the BBC's MODE 7 screen memory at TTXBUF (&7C00, 40 x 25
; character codes; HIMEM &7C00 as on the BBC), shown on the VIC-II hires
; bitmap: a teletext cell is an 8 x 8 cell with one foreground and one
; background colour, which is exactly the VIC-II's rule. A row is drawn
; again after every change, because a control code acts on the rest of
; its row.
;
; Teletext rules (SAA5050, as the BBC): codes 128-159 are control codes,
; shown as spaces (or the held mosaic); "set-after" codes (colours,
; double height, release) act from the next cell, "set-at" codes
; (contiguous, separated, black/new background, hold, normal height) at
; once. Mosaics: 2 x 3 blocks from bits 0-4 and 6; codes 64-95 stay
; letters in graphics mode. Double height: a row with code 141 shows the
; top halves, the row below the bottom halves of its own characters
; (programs print the line twice). Flashing (136) shows steady for now.
;
; ----------------------------------------------------------------------------


    jmp t_mode                  ; +0
    jmp t_vdu                   ; +3
    jmp t_char                  ; +6  A = character code (32-255)
    jmp t_pet                   ; +9  A = PETSCII cursor/control code
    jmp t_cursor                ; +12
    jmp t_refresh               ; +15 from the interrupt (core's tt_irq)
    jmp t_rts                   ; +18
    jmp t_rts                   ; +21 todev, line, rect, pset, pointdev:
    jmp t_rts                   ; +24 no graphics in MODE 7
    jmp t_rts                   ; +27
    jmp t_rts                   ; +30
    jmp t_rts                   ; +33
t_rts:
    rts

; ----------------------------------------------------------------------------
; Variables

tr_row      dta 0               ; row being drawn
tr_col      dta 0
tr_fg       dta 0               ; teletext colours 0-7
tr_bg       dta 0
tr_gfx      dta 0               ; 1: graphics mode
tr_sep      dta 0               ; 1: separated mosaics
tr_hold     dta 0
tr_held     dta 0               ; held mosaic (code), 0: none
tr_dh       dta 0               ; double height in this cell
tr_lower    dta 0               ; 1: this row shows bottom halves
tr_nfg      dta 0               ; set-after values for the next cell
tr_ngfx     dta 0
tr_ndh      dta 0
tr_nrel     dta 0
tr_code     dta 0               ; the cell's character (display code)
tr_pat      :8 dta 0            ; the cell's 8 bitmap bytes
tr_t        dta 0, 0
dhrows      :25 dta 0           ; 1: row has double height (top halves)
flrows      :25 dta 0           ; 1: row has flashing cells
tr_flash    dta 0               ; flashing in this cell
tr_nflash   dta 0
tf_phase    dta 0               ; flashing: 0 shown, 1 hidden
tf_count    dta 0               ; interrupts until the next flash change
tf_row      dta 0               ; next row to compare
tf_n        dta 0
; shadow copy of the screen memory: rows that differ were written to
; directly (?&7C00=...) and are drawn again
tshadow     :1000 dta 0

; Row addresses: buffer (40 per row), bitmap (320), screen matrix (40)
tbuflo:
    :25 dta l(TTXBUF+#*40)
tbufhi:
    :25 dta h(TTXBUF+#*40)
tbmplo:
    :25 dta l(BITMAP+#*320)
tbmphi:
    :25 dta h(BITMAP+#*320)
tmatlo:
    :25 dta l(SCREEN+#*40)
tmathi:
    :25 dta h(SCREEN+#*40)
; teletext colours -> C64 colours
tcol:
    dta 0, 2, 5, 7, 6, 4, 3, 1

; ASCII glyphs 32-127 (8 bytes each), copied in by bank 3 at MODE 7
ttxfont:
    :768 dta 0

; ----------------------------------------------------------------------------
; t_mode: empty screen (spaces), windows full, cursor home, all drawn
t_mode:
    lda #0
    sta tcx
    sta tcy
    sta twl
    sta twt
    lda #39
    sta twr
    lda #24
    sta twb
    ldx #0                      ; buffer: spaces
    lda #' '
tm_buf:
    sta TTXBUF,x
    sta TTXBUF+$100,x
    sta TTXBUF+$200,x
    sta TTXBUF+$2E8,x
    inx
    bne tm_buf
    ldx #24
    lda #0
tm_dh:
    sta dhrows,x
    dex
    bpl tm_dh
    jmp t_drawall

; t_drawall: draw every row
t_drawall:
    lda #0
tda_loop:
    pha
    jsr t_row
    pla
    clc
    adc #1
    cmp #25
    bne tda_loop
    rts

; ----------------------------------------------------------------------------
; t_vdu: 12 CLS (the text window), 26 default windows, 28 text window;
; COLOUR, GCOL and the graphics codes do nothing in MODE 7
t_vdu:
    lda gx_code
    cmp #12
    bne tv_n12
    jmp t_cls
tv_n12:
    cmp #26
    bne tv_n26
    lda #0
    sta twl
    sta twt
    sta tcx
    sta tcy
    lda #39
    sta twr
    lda #24
    sta twb
    rts
tv_n26:
    cmp #28
    bne tv_done
    lda vdubuf+2                ; VDU 28,l,b,r,t (ignored if wrong)
    cmp #40
    bcs tv_done
    cmp vdubuf
    bcc tv_done
    lda vdubuf+1
    cmp #25
    bcs tv_done
    cmp vdubuf+3
    bcc tv_done
    lda vdubuf
    sta twl
    sta tcx
    lda vdubuf+1
    sta twb
    lda vdubuf+2
    sta twr
    lda vdubuf+3
    sta twt
    sta tcy
tv_done:
    rts

; t_cls: the text window full of spaces, cursor home
t_cls:
    lda twt
tc_row:
    pha
    tax
    jsr t_rowaddr
    ldy twl
    lda #' '
tc_col:
    sta (gzp),y
    cpy twr
    iny
    bcc tc_col
    pla
    pha
    jsr t_row
    pla
    cmp twb
    bcs tc_done
    adc #1
    bne tc_row
tc_done:
    lda twl
    sta tcx
    lda twt
    sta tcy
    rts

; t_rowaddr: gzp = buffer address of row X
t_rowaddr:
    lda tbuflo,x
    sta gzp
    lda tbufhi,x
    sta gzp+1
    rts

; ----------------------------------------------------------------------------
; t_char: A = character code: into the buffer at the cursor, the row drawn
; again, the cursor moved on
t_char:
    pha
    ldx tcy
    jsr t_rowaddr
    ldy tcx
    pla
    sta (gzp),y
    lda tcy
    jsr t_rowdh                 ; draw the row (and the next one if its
    jmp t_advance               ; double height changed)

; t_rowdh: draw row A; if its double-height flag changed, also the row
; below (whose bottom halves depend on it)
t_rowdh:
    tax
    lda dhrows,x
    pha
    txa
    pha
    jsr t_row
    pla
    tax
    pla
    cmp dhrows,x
    beq trd_done
    inx
    cpx #25
    bcs trd_done
    txa
    jmp t_row
trd_done:
    rts

t_advance:
    lda tcx
    cmp twr
    bcs tad_wrap
    inc tcx
    rts
tad_wrap:
    lda twl
    sta tcx
t_down:
    lda tcy
    cmp twb
    bcs t_scroll
    inc tcy
    rts

; t_scroll: the text window up one row; the bottom row blank
t_scroll:
    lda twt
    sta tr_t
tsc_row:
    lda tr_t
    cmp twb
    bcs tsc_last
    ldx tr_t                    ; row t <- row t + 1 (window columns)
    inx
    jsr t_rowaddr
    lda gzp
    sta tsc_src+1
    lda gzp+1
    sta tsc_src+2
    ldx tr_t
    jsr t_rowaddr
    ldy twl
tsc_col:
tsc_src:
    lda $FFFF,y
    sta (gzp),y
    cpy twr
    iny
    bcc tsc_col
    inc tr_t
    jmp tsc_row
tsc_last:
    ldx twb
    jsr t_rowaddr
    ldy twl
    lda #' '
tsc_blank:
    sta (gzp),y
    cpy twr
    iny
    bcc tsc_blank
    lda twt                     ; draw the window's rows (and the one
tsc_draw:                       ; below, for double height)
    pha
    jsr t_row
    pla
    cmp twb
    beq tsc_done
    clc
    adc #1
    bne tsc_draw
tsc_done:
    cmp #24
    bcs tsc_end
    adc #1
    jmp t_row
tsc_end:
    rts

; ----------------------------------------------------------------------------
; t_pet: the MOS's cursor codes (as the bitmap engine's e_pet)
t_pet:
    cmp #$0D
    bne tp_n0d
    lda twl
    sta tcx
    jmp t_down
tp_n0d:
    cmp #$9D
    bne tp_n9d
    lda tcx                     ; left; at the left edge: end of the line
    cmp twl                     ; above
    beq tp_lwrap
    bcc tp_lwrap
    dec tcx
    rts
tp_lwrap:
    lda twr
    sta tcx
    lda tcy
    cmp twt
    beq tp_ok
    dec tcy
tp_ok:
    rts
tp_n9d:
    cmp #$1D
    bne tp_n1d
    jmp t_advance
tp_n1d:
    cmp #$11
    bne tp_n11
    jmp t_down
tp_n11:
    cmp #$91
    bne tp_n91
    lda tcy
    cmp twt
    beq tp_ok
    dec tcy
    rts
tp_n91:
    cmp #$93
    bne tp_n93
    jmp t_cls
tp_n93:
    cmp #$13
    bne tp_ok
    lda twl
    sta tcx
    lda twt
    sta tcy
    rts

; t_cursor: invert the bottom line of the cursor's cell
t_cursor:
    ldx tcy
    lda tcx
    asl
    asl
    asl
    php
    clc
    adc tbmplo,x
    sta gzp
    lda tbmphi,x
    adc #0
    plp                         ; columns 32-39: +256
    adc #0
    sta gzp+1
    ldy #7
    lda (gzp),y
    eor #$FF
    sta (gzp),y
    rts

; ----------------------------------------------------------------------------
; t_row
;   Summary: draw text row A from the buffer into the bitmap and the
;            screen matrix, following the teletext attributes; the row's
;            codes go to the shadow copy.
;   Uses:    A, X, Y, gzp, tr_* variables.
t_row:
    sta tr_row
    tax
    jsr t_rowaddr               ; shadow row = buffer row
    lda gzp                     ; shadow = buffer - TTXBUF + tshadow
    clc                         ; (TTXBUF's low byte is 0)
    adc #<tshadow
    sta trs_dst+1
    lda gzp+1
    adc #[>tshadow-[>TTXBUF]]&$FF
    sta trs_dst+2
    ldy #39
trs_copy:
    lda (gzp),y
trs_dst:
    sta $FFFF,y
    dey
    bpl trs_copy
    ldx tr_row
    lda #0                      ; bottom halves if the row above has
    sta tr_lower                ; double height
    cpx #0
    beq trw_top
    lda dhrows-1,x
    sta tr_lower
trw_top:
    lda #0
    sta dhrows,x
    sta tr_bg
    sta tr_gfx
    sta tr_sep
    sta tr_hold
    sta tr_held
    sta tr_dh
    sta tr_nrel
    lda #7
    sta tr_fg
    sta tr_nfg
    lda #0
    sta tr_ngfx
    sta tr_ndh
    sta tr_col
    sta tr_flash
    sta tr_nflash
    sta flrows,x
trw_cell:
    ldx tr_row                  ; the cell's code
    jsr t_rowaddr
    ldy tr_col
    lda (gzp),y
    sta tr_code
    and #$7F
    cmp #$20
    bcs trw_print
    jsr t_control               ; control code: attributes, then a space
    lda #' '                    ; or the held mosaic
    ldx tr_hold
    beq trw_space
    ldx tr_gfx
    beq trw_space
    lda tr_held
    beq trw_space2
    sta tr_code
    jmp trw_show
trw_space2:
    lda #' '
trw_space:
    sta tr_code
    jmp trw_show
trw_print:
    sta tr_code
trw_show:
    jsr t_cellpat               ; tr_pat from tr_code and the attributes
    jsr t_cellput               ; into the bitmap, colours into the matrix
    jsr t_after                 ; set-after attributes take effect
    inc tr_col
    lda tr_col
    cmp #40
    bne trw_cell
    lda tr_lower                ; a bottom-half row never starts a new
    beq trw_done                ; pair: the row below it is a top row
    ldx tr_row
    lda #0
    sta dhrows,x
trw_done:
    rts

; t_control: a control code (A = 0-31): set-at now, set-after later
t_control:
    cmp #$01                    ; 1-7: alphanumeric colour (after)
    bcs tct_go
tct_rts:
    rts
tct_go:
    cmp #$08
    bcs tct_n17
    sta tr_nfg
    lda #0
    sta tr_ngfx
    lda #1
    sta tr_nrel                 ; (alpha: hold released afterwards)
    rts
tct_n17:
    cmp #$0C                    ; normal height (at)
    bne tct_n0c
    lda #0
    sta tr_dh
    sta tr_ndh
    sta tr_held
    rts
tct_n0c:
    cmp #$08                    ; flash (after)
    bne tct_n08
    lda #1
    sta tr_nflash
    ldx tr_row
    sta flrows,x
    rts
tct_n08:
    cmp #$09                    ; steady (at)
    bne tct_n09
    lda #0
    sta tr_flash
    sta tr_nflash
    rts
tct_n09:
    cmp #$0D                    ; double height (after)
    bne tct_n0d
    lda #1
    sta tr_ndh
    ldx tr_row
    sta dhrows,x
    lda #0
    sta tr_held
    rts
tct_n0d:
    cmp #$11                    ; 17-23: graphics colour (after)
    bcc tct_rts
    cmp #$18
    bcs tct_n18
    and #7
    sta tr_nfg
    lda #1
    sta tr_ngfx
    rts
tct_n18:
    cmp #$19                    ; contiguous (at)
    bne tct_n19
    lda #0
    sta tr_sep
    rts
tct_n19:
    cmp #$1A                    ; separated (at)
    bne tct_n1a
    lda #1
    sta tr_sep
    rts
tct_n1a:
    cmp #$1C                    ; black background (at)
    bne tct_n1c
    lda #0
    sta tr_bg
    rts
tct_n1c:
    cmp #$1D                    ; new background = foreground (at)
    bne tct_n1d
    lda tr_fg
    sta tr_bg
    rts
tct_n1d:
    cmp #$1E                    ; hold graphics (at)
    bne tct_n1e
    lda #1
    sta tr_hold
    rts
tct_n1e:
    cmp #$1F                    ; release graphics (after)
    bne tct_done
    lda #1
    sta tr_nrel
tct_done:
    rts

; t_after: apply the set-after attributes after the current cell
t_after:
    lda tr_nflash
    sta tr_flash
    lda tr_nfg
    sta tr_fg
    lda tr_ngfx
    sta tr_gfx
    lda tr_ndh
    sta tr_dh
    lda tr_nrel
    beq taf_done
    lda #0
    sta tr_hold
    sta tr_nrel
taf_done:
    rts

; t_cellpat
;   Summary: the cell's 8 bitmap bytes in tr_pat: a glyph (letters, and
;            codes 64-95 also in graphics mode) or a mosaic; double
;            height stretches the top or bottom half; in the row below a
;            double-height row, cells without double height are blank.
t_cellpat:
    lda tr_lower                ; bottom-half row, normal cell: blank
    beq tcp_go
    lda tr_dh
    bne tcp_go
    ldx #7
    lda #0
tcp_blank:
    sta tr_pat,x
    dex
    bpl tcp_blank
    rts
tcp_go:
    lda tr_gfx
    beq tcp_glyph
    lda tr_code
    cmp #$40
    bcc tcp_mosaic
    cmp #$60
    bcs tcp_mosaic
tcp_glyph:
    lda tr_code                 ; glyph: ttxfont + (code - 32) * 8
    sec
    sbc #$20
    sta tr_t
    lda #0
    asl tr_t
    rol
    asl tr_t
    rol
    asl tr_t
    rol
    sta tr_t+1
    lda tr_t
    clc
    adc #<ttxfont
    sta tcp_rd+1
    lda tr_t+1
    adc #>ttxfont
    sta tcp_rd+2
    ldx #7
tcp_rd:
    lda $FFFF,x
    sta tr_pat,x
    dex
    bpl tcp_rd
    jmp tcp_height
tcp_mosaic:                     ; 2 x 3 blocks: bits 0,1 / 2,3 / 4,6
    lda tr_code
    sta tr_held                 ; (the last mosaic, for hold)
    lsr                         ; top: rows 0-2
    jsr tcp_pair
    ldx #0
    jsr tcp_band3
    lda tr_code
    lsr
    lsr
    lsr                         ; middle: rows 3-4 (bits 2, 3)
    jsr tcp_pair
    sta tr_pat+3
    ldy tr_sep
    beq tcp_m4
    lda #0                      ; separated: the band's last row empty
tcp_m4:
    sta tr_pat+4
    lda tr_code                 ; bottom: rows 5-7 (bits 4, 6)
    and #$50
    lsr
    lsr
    lsr
    lsr                         ; bit 4 -> 0, bit 6 -> 2
    sta tr_t
    and #1
    beq tcp_bl
    lda #$F0
tcp_bl:
    sta tr_t+1
    lda tr_t
    and #4
    beq tcp_br
    lda #$0F
    ora tr_t+1
    sta tr_t+1
tcp_br:
    lda tr_t+1
    jsr tcp_sepmask
    ldx #5
    jsr tcp_band3
    jmp tcp_height
; tcp_pair: C = left bit (bit 0 shifted out), A bit 0 = right bit ->
; A = $F0 / $0F / $FF / $00 (separated: $E0 / $0E)
tcp_pair:
    php
    and #1
    beq tpp_r0
    lda #$0F
tpp_r0:
    plp
    bcc tpp_l0
    ora #$F0
tpp_l0:
tcp_sepmask:
    ldy tr_sep
    beq tsm_done
    and #$EE                    ; separated: a gap column in each block
tsm_done:
    rts
; tcp_band3: A (from tcp_pair) in rows X .. X+2 (separated: X+2 empty)
tcp_band3:
    sta tr_pat,x
    sta tr_pat+1,x
    ldy tr_sep
    beq tb3_full
    lda #0
tb3_full:
    sta tr_pat+2,x
    rts
; double height: rows 0-3 (top) or 4-7 (bottom) stretched to 8. Top:
; from the bottom up (rows 7,6 <- 3 ...); bottom: from the top down
; (rows 0,1 <- 4 ...), so no source row is overwritten before it is read
tcp_height:
    lda tr_dh
    beq tch_done
    lda tr_lower
    bne tch_bottom
    ldx #3
    ldy #7
tch_up:
    lda tr_pat,x
    sta tr_pat,y
    dey
    sta tr_pat,y
    dex
    dey
    bpl tch_up
tch_done:
    rts
tch_bottom:
    ldx #4
    ldy #0
tch_down:
    lda tr_pat,x
    sta tr_pat,y
    iny
    sta tr_pat,y
    inx
    iny
    cpy #8
    bne tch_down
    rts

; t_cellput: tr_pat into the bitmap cell, the colours into the matrix
t_cellput:
    ldx tr_row
    lda tr_col
    asl
    asl
    asl
    php
    clc
    adc tbmplo,x
    sta gzp
    lda tbmphi,x
    adc #0
    plp
    adc #0
    sta gzp+1
    ldy #7
    lda tr_flash                ; flashing and in the hidden phase:
    and tf_phase                ; foreground = background
    beq tcput_loop
    lda #0
tcput_hide:
    sta (gzp),y
    dey
    bpl tcput_hide
    bmi tcput_col
tcput_loop:
    lda tr_pat,y
    sta (gzp),y
    dey
    bpl tcput_loop
tcput_col:
    lda tmatlo,x                ; matrix: foreground high, background low
    sta gzp
    lda tmathi,x
    sta gzp+1
    ldx tr_fg
    lda tcol,x
    asl
    asl
    asl
    asl
    ldx tr_bg
    ora tcol,x
    ldy tr_col
    sta (gzp),y
    rts

; ----------------------------------------------------------------------------
; t_refresh (from the 60 Hz interrupt, core's tt_irq)
;   Summary: rows whose codes differ from the shadow copy (written to
;            directly) are drawn again, 5 rows per interrupt in rotation;
;            every 30 interrupts the flash phase changes and rows with
;            flashing cells are drawn again.
t_refresh:
    lda #5                      ; 5 rows per interrupt, in rotation (all
    sta tf_n                    ; 25 at 1 MHz would take longer than the
trf_row:                        ; time between interrupts)
    ldx tf_row                  ; compare row with its shadow
    jsr t_rowaddr
    lda gzp
    clc
    adc #<tshadow
    sta trf_cmp+1
    lda gzp+1
    adc #[>tshadow-[>TTXBUF]]&$FF
    sta trf_cmp+2
    ldy #39
trf_byte:
    lda (gzp),y
trf_cmp:
    cmp $FFFF,y
    bne trf_draw
    dey
    bpl trf_byte
    bmi trf_next
trf_draw:
    lda tf_row
    jsr t_rowdh
trf_next:
    inc tf_row
    lda tf_row
    cmp #25
    bcc trf_more
    lda #0
    sta tf_row
trf_more:
    dec tf_n
    bne trf_row
    dec tf_count                ; flashing: phase change every 30
    bpl trf_done
    lda #29
    sta tf_count
    lda tf_phase
    eor #1
    sta tf_phase
    ldx #24
trf_fl:
    lda flrows,x
    beq trf_flnext
    txa
    pha
    jsr t_row
    pla
    tax
trf_flnext:
    dex
    bpl trf_fl
trf_done:
    rts

ttx_end:
    .if ttx_end > ENGINE+$1000
    .error "Teletext engine overflows its 4K"
    .endif
