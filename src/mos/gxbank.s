; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 3: graphics (screen modes, palettes, Upic Lite)
;
; Not speed critical: MODE changes and palette changes run here, through
; the trampoline (the core's vdu_mode/vdu_pal/vdu_defcol). Bank code runs
; with I/O and the KERNAL in ($01 = $37).
;
; ----------------------------------------------------------------------------

; Mode table: type, mc, cols, rows, ncol, xsh, ysc, cw, ch, palette
MT_LEN = 10
mode_nums:
    dta 0, 1, 2, 3, 4, 5, 6, 7, 100, 103, 104, $FF
mode_tab:
    dta 1, 0, 80, 32,  2, 2, 0, 4, 6, pal_bbc2-pal_sets   ; 0
    dta 1, 1, 40, 32,  4, 3, 0, 4, 6, pal_bbc4-pal_sets   ; 1
    dta 1, 1, 20, 32, 16, 3, 0, 8, 6, pal_bbc16-pal_sets  ; 2
    dta 0, 0, 40, 25, 16, 0, 0, 8, 8, pal_bbc16-pal_sets  ; 3 (40 cols yet)
    dta 1, 0, 40, 32,  2, 2, 0, 8, 6, pal_bbc2-pal_sets   ; 4
    dta 1, 1, 20, 32,  4, 3, 0, 8, 6, pal_bbc4-pal_sets   ; 5
    dta 0, 0, 40, 25, 16, 0, 0, 8, 8, pal_bbc16-pal_sets  ; 6
    dta 0, 0, 40, 25, 16, 0, 0, 8, 8, pal_bbc16-pal_sets  ; 7
    dta 0, 0, 40, 25, 16, 0, 1, 8, 8, pal_c64-pal_sets    ; 100 text
    dta 1, 0, 40, 25, 16, 2, 1, 8, 8, pal_c64-pal_sets    ; 103 hires
    dta 1, 1, 20, 25, 16, 3, 1, 8, 8, pal_c64-pal_sets    ; 104 multicolour
pal_sets:
pal_bbc2:
    dta 0, 1
pal_bbc4:
    dta 0, 2, 7, 1
pal_bbc16:                      ; BBC colours 0-15 on the C64
    dta 0, 2, 5, 7, 6, 4, 3, 1, 8, 9, 10, 11, 12, 13, 14, 15
pal_c64:
    dta 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
pal_ulb2:                       ; Upic Lite: BBC colour numbers (RGB via
    dta 0, 7                    ; the Ultimate's palette)
pal_ulb4:
    dta 0, 1, 3, 7

; ----------------------------------------------------------------------------
; bk_mode (VDU 22, from the core's vdu_mode)
;   Summary: VDU 22,n (MODE n).
;   Function: looks n up in mode_nums (an unknown number uses n AND 7,
;            as the BBC Model B does), sets the vmode_* variables and the
;            default palette, then the VIC-II and the screen: text modes
;            get the text screen and font back; bitmap modes switch the
;            KERNAL cursor off, and the engine clears the bitmap and
;            resets windows, cursors and colours.
bk_mode:
    lda vdubuf
    ldx #0
vm_find:
    ldy mode_nums,x
    cpy #$FF
    beq vm_unknown
    cmp mode_nums,x
    beq vm_found
    inx
    bne vm_find
vm_unknown:
    and #7
    sta vdubuf
    jmp bk_mode
vm_found:
    sta vmode
    txa                         ; entry = X * 10
    asl
    sta vm_t
    asl
    asl
    adc vm_t
    tax
    lda mode_tab,x
    sta vtype
    lda mode_tab+1,x
    sta vmode_mc
    lda mode_tab+2,x
    sta vmode_cols
    lda mode_tab+3,x
    sta vmode_rows
    lda mode_tab+4,x
    sta vmode_ncol
    sec
    sbc #1
    sta vmode_cmask
    lda mode_tab+5,x
    sta vmode_xsh
    lda mode_tab+6,x
    sta vmode_ysc
    eor #1                      ; BBC palette numbers unless a C64 mode
    sta vmode_bbc
    lda mode_tab+7,x
    sta vmode_cw
    lda mode_tab+8,x
    sta vmode_ch
    lda mode_tab+9,x
    sta vmode_pal
    lda #<319
    ldy #>319
    ldx vmode_mc
    beq vm_xmax
    lda #<159
    ldy #>159
vm_xmax:
    sta vmode_xmax
    sty vmode_xmax+1
    lda #7
    ldx vmode_mc
    beq vm_ppb
    lda #3
vm_ppb:
    sta vmode_ppbm
    lda #199
    sta vmode_ymax
    lda #$80
    sta vmode_himem
    jsr ul_choose               ; MODE 0/1/4: Upic Lite when possible
    jsr pal_default
    lda ul_active               ; leaving Upic Lite?
    beq vm_noleave
    lda vmode_ul
    bne vm_noleave
    jsr ul_leave
vm_noleave:
    lda vtype
    bne vm_bitmap
    ; text mode: VIC text, font back, KERNAL cursor on, clear
    lda #$1B
    sta $D011
    lda #$C8
    sta $D016
    lda #$0C
    sta $D018
    jsr font_restore
    lda #0
    sta $D021
    sta BLNSW
    lda #1
    sta COLOR
    lda #$93
    jsr putpet
    rts
vm_bitmap:
    sei                         ; KERNAL cursor: stop blinking, hide it
    lda #1                      ; (as wk_hide)
    sta BLNSW
    lda BLNON
    beq vm_noblink
    lda GDBLN
    ldx GDCOL
    ldy #0
    sty BLNON
    jsr K_SETCURSOR
vm_noblink:
    cli
    lda vmode_ul
    beq vm_vic
    farcall ul_enter, BANK_UL
    rts
vm_vic:
    lda #$0B                    ; display off while clearing
    sta $D011
    ldx #GX_MODE
    jsr gx_call
    jsr io_palette
    lda #$C8
    ldx vmode_mc
    beq vm_d016
    lda #$D8
vm_d016:
    sta $D016
    lda #$08                    ; matrix $C000, bitmap $E000
    sta $D018
    lda #$3B
    sta $D011
    rts

; pal_default: pal[] from the mode's palette set (vmode_pal = offset)
pal_default:
    ldx vmode_pal
    ldy #0
pd_loop:
    lda pal_sets,x
    sta pal,y
    inx
    iny
    cpy vmode_ncol
    bne pd_loop
    rts

; ----------------------------------------------------------------------------
; io_palette
;   Summary: show the palette of a bitmap mode: $D021 (and border) and,
;            in multicolour modes, the colour RAM (logical colour 3).
;   Function: called with I/O in (from the core) or from the engine
;            ($01 = $34: I/O is switched in here and back).
io_palette:
    lda $01
    pha
    cmp #$34                    ; from the engine: I/O in
    bne iop_io
    lda #$35
    sta $01
iop_io:
    lda pal
    sta $D021
    lda vmode_mc
    beq iop_done
    lda pal+3
    ldx #0
iop_col:
    sta $D800,x
    sta $D900,x
    sta $DA00,x
    sta $DAE8,x
    inx
    bne iop_col
iop_done:
    pla
    sta $01
    rts

; ----------------------------------------------------------------------------
; bk_pal (VDU 19,l,p,r,g,b)
;   Summary: logical colour l shows physical colour p: a BBC colour 0-15
;            in BBC modes, a C64 colour in the C64 modes. Bitmap modes
;            with 2 or 4 colours show the change at once (cells and
;            colour RAM); 16-colour modes use it for new drawing.
bk_pal:
    lda vtype
    beq vp_done
    lda vmode_ul
    beq vp_vic
    lda vdubuf                  ; Upic Lite: pal[] holds BBC colours
    and vmode_cmask
    tax
    lda vdubuf+1
    and #15
    sta pal,x
    farcall ul_setpal, BANK_FS
    rts
vp_vic:
    lda vdubuf+1
    and #15
    ldx vmode_bbc
    beq vp_c64
    tax
    lda bbc2c64,x
vp_c64:
    pha
    lda vdubuf
    and vmode_cmask
    tax
    pla
    sta pal,x
vp_show:
    lda vmode_ul
    beq vp_vicshow
    farcall ul_setpal, BANK_FS
    rts
vp_vicshow:
    lda vmode_ncol
    cmp #16
    beq vp_done
    ldx #GX_MATRIX
    jsr gx_call
    jsr io_palette
vp_done:
    rts

; bk_defcol (VDU 20): default palette and colours
bk_defcol:
    lda vtype
    beq vp_done
    jsr pal_default
    lda #0
    sta tbg
    sta gbg
    sta gact_fg
    sta gact_bg
    ldx vmode_cmask
    cpx #15
    bne vdc_fg
    ldx #7
vdc_fg:
    stx tfg
    stx gfg
    jmp vp_show


; ----------------------------------------------------------------------------
; Upic Lite (docs/DESIGN_GRAPHICS.md section 10.8): live 320 x 256 pictures
; with 1-dot pixels, 1 or 2 bits per pixel, drawn by a raster interrupt.
; The buffer lies below HIMEM, where the BBC has its screen (MODE 0/4:
; &5800, MODE 1: &3000). The renderer (tools/upiclite_gen.py) and its
; frame loop run at $E000, the shift tables at $F000, the Upic Lite engine
; at $D000.

; ul_choose
;   Summary: MODE 0, 1 or 4 on a machine that can show Upic Lite (ul_ok:
;            64 MHz and palette commands): override the VIC-II mode with
;            the Upic Lite one.
;   Input:   vmode and the mode table's fields.  Output: vmode_ul and the
;            vmode_* fields.  Uses: A, X, Y.
ul_choose:
    lda #0
    sta vmode_ul
    lda ul_ok
    bne uc_ok
    rts
uc_ok:
    ldx vmode
    cpx #2                      ; MODE 2 and 5: 160 wide, 2 dots per pixel
    bne uc_n2
    jmp uc_160
uc_n2:
    cpx #5
    bne uc_n5
    jmp uc_160
uc_n5:
    lda #0                      ; bits per pixel - 1
    ldy #4                      ; cell width (MODE 0, 3: 80 columns)
    cpx #0
    beq uc_go
    cpx #3
    beq uc_go
    ldy #8
    cpx #4
    beq uc_go
    cpx #6
    beq uc_go
    cpx #1
    beq uc_m1
    rts
uc_m1:
    lda #1                      ; MODE 1: 2 bits per pixel
uc_go:
    sta vmode_mc
    clc                         ; renderer 1 (1 bit) or 2 (2 bits)
    adc #1
    sta vmode_rend
    lda vmode_mc
    sty vmode_cw
    lda #80
    cpy #4
    beq uc_cols
    lda #40
uc_cols:
    sta vmode_cols
    lda #1
    sta vtype                   ; (MODE 3 and 6 are text modes otherwise)
    sta vmode_ul
    sta vmode_bbc
    sta vmode_ysc               ; y >> 2
    lda #32                     ; 32 rows of 8 lines; MODE 3 and 6: 25
    ldy #8                      ; rows of 10 (250 lines, as the BBC)
    ldx vmode
    cpx #3
    beq uc_25
    cpx #6
    bne uc_rows
uc_25:
    lda #25
    ldy #10
uc_rows:
    sta vmode_rows
    sty vmode_ch
    lda #2
    sta vmode_xsh
    lda #255
    sta vmode_ymax
    lda #<319
    sta vmode_xmax
    lda #>319
    sta vmode_xmax+1
    lda vmode_mc
    bne uc_2bpp
    lda #7
    ldx #$58
    ldy #pal_ulb2-pal_sets
    lda #2
    sta vmode_ncol
    lda #7
    bne uc_set
uc_2bpp:
    lda #4
    sta vmode_ncol
    lda #3
    ldx #$30
    ldy #pal_ulb4-pal_sets
uc_set:
    sta vmode_ppbm
    stx vmode_bufhi
    stx vmode_himem
    sty vmode_pal
    ldx vmode_ncol
    dex
    stx vmode_cmask
uc_done:
    rts

; uc_160: MODE 2 (4 bits per pixel, 16 colours) and MODE 5 (2 bits, 4
; colours): 160 x 256, 20 x 32 text, as the BBC
uc_160:
    lda #1
    sta vtype
    sta vmode_ul
    sta vmode_bbc
    sta vmode_ysc
    lda #20
    sta vmode_cols
    lda #32
    sta vmode_rows
    lda #8
    sta vmode_cw
    sta vmode_ch
    lda #3                      ; 1280 / 160 = 8 OS units per pixel
    sta vmode_xsh
    lda #255
    sta vmode_ymax
    lda #<159
    sta vmode_xmax
    lda #>159
    sta vmode_xmax+1
    cpx #2
    bne u160_5
    lda #2                      ; MODE 2: 4 bits per pixel
    sta vmode_mc
    lda #16
    sta vmode_ncol
    lda #1                      ; 2 pixels per byte
    ldx #$30
    ldy #pal_c64-pal_sets       ; (identity: BBC colours 0-15)
    lda #4
    sta vmode_rend
    lda #1
    jmp uc_set
u160_5:
    lda #1                      ; MODE 5: 2 bits per pixel
    sta vmode_mc
    lda #4
    sta vmode_ncol
    lda #3
    sta vmode_rend
    lda #3                      ; 4 pixels per byte
    ldx #$58
    ldy #pal_ulb4-pal_sets
    jmp uc_set

; ul_leave: raster interrupt off, CIA timer interrupt and the standard
; IRQ back, the Ultimate's default palette, the VIC-II engine back
ul_leave:
    sei
    lda #0
    sta $D01A
    sta ul_active
    lda #$0F
    sta $D019
    lda #<irq_main
    sta $0314
    lda #>irq_main
    sta $0315
    lda #$81
    sta $DC0D
    cli
    farcall ul_palreset, BANK_FS
    farcall engine_init, BANK_MOS
    rts

; bk_himem (OSBYTE &85): HIMEM page for mode X in Y
bk_himem:
    ldy #$80
    lda ul_ok
    beq bh_done
    txa
    and #$7F
    beq bh_58
    cmp #3
    beq bh_58
    cmp #4
    beq bh_58
    cmp #6
    beq bh_58
    cmp #5
    beq bh_58
    cmp #1
    beq bh_30
    cmp #2
    bne bh_done
bh_30:
    ldy #$30
    rts
bh_58:
    ldy #$58
bh_done:
    rts


    icl 'gxs_bank.s'


bank3_end:
    .if bank3_end > $C000
    .error "Bank 3 overflows 16K"
    .endif
    :[$C000-*] dta $FF
