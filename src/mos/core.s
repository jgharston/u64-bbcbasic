; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- VDU core, runs from RAM at CORE ($C800-$CFFF)
;
; The VDU driver (OSWRCH) and what it needs. Copied from bank 0 at cold
; start (core_init), so it runs at turbo speed: from cartridge ROM the
; Ultimate 64 reads at 1 MHz. WRCHV points here directly. Code here may
; switch I/O and the KERNAL; the drawing engine at $D000 (under I/O)
; follows with the graphics modes (docs/DESIGN_GRAPHICS.md section 10).
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; putpet
;   Summary: print one PETSCII code through the KERNAL.
;   Function: switches quote and insert mode off first, so control codes
;            always act and are never shown as reverse characters.
;   Input:   A = PETSCII code.
;   Output:  screen. A, X, Y preserved (KERNAL CHROUT to the screen).
;   Uses:    QTSW, INSRT.

putpet:
    pha
    lda vtype
    bne pp_bitmap
    lda #0
    sta QTSW
    sta INSRT
    pla
    jmp K_CHROUT
pp_bitmap:                      ; bitmap modes: the engine's cursor codes,
    stx pp_x                    ; registers kept as with the KERNAL
    sty pp_y
    pla
    pha
    ldx #GX_PET
    jsr gx_call
    ldx pp_x
    ldy pp_y
    pla
    rts
pp_x:
    dta 0
pp_y:
    dta 0

; ----------------------------------------------------------------------------
; mos_wrch (OSWRCH)
;   Summary: BBC VDU driver, text part.
;   Function: printable ASCII goes to the screen through asc2pet; codes
;            0-31 are VDU commands, which first collect their parameter
;            bytes (vdu_nparam) in vdubuf, then run from vdu_table.
;            Codes 128-255 are ignored for now.
;   Input:   A = character or VDU byte.
;   Output:  screen. A, X, Y preserved.
;   Uses:    wr_a, wr_x, wr_y, vduq, vducmd, vduidx, vdubuf.

mos_wrch:
    sta wr_a
    stx wr_x
    sty wr_y
    ldx MB_DEBUG                ; remote debugger: TRACE "[n] " filter
    beq wr_nodbg
    ldx vduq
    bne wr_nodbg
    farcall dbg_filter, BANK_MOS ; (bank 0: debug mode only)
    bcc wr_nodbg
    jmp wr_done                 ; part of a trace: swallowed
wr_nodbg:
    lda wr_a
    ldx MB_CAPTURE              ; remote output capture
    beq wr_notee
    jsr wr_tee
    lda wr_a
wr_notee:
    ldx vduq
    bne wr_param
    cmp #32
    bcc wr_ctrl
    cmp #127
    beq wr_del
    bcs wr_done                 ; 128-255: no glyphs yet
    jsr out_char
wr_done:
    lda wr_a
    ldx wr_x
    ldy wr_y
    rts

wr_del:                         ; VDU 127: delete the character to the left
    lda #$9D
    jsr putpet
    lda #' '
    jsr out_char
    lda #$9D
    jsr putpet
    jmp wr_done

wr_ctrl:                        ; VDU 0-31: run now or wait for parameters
    tax
    lda vdu_nparam,x
    beq wr_exec
    sta vduq
    stx vducmd
    lda #0
    sta vduidx
    beq wr_done

wr_param:                       ; collect a parameter byte
    ldx vduidx
    cpx #VDUBUFLEN              ; bounded: OSBYTE &DA can set any count
    bcs wr_pskip
    sta vdubuf,x
    inc vduidx
wr_pskip:
    dec vduq
    bne wr_done
    ldx vducmd
wr_exec:                        ; X = VDU code 0-31
    stx gx_code
    txa
    asl
    tax
    lda vdu_table+1,x
    pha
    lda vdu_table,x
    pha
    rts

; wr_raw
;   Summary: print one printable ASCII character from inside mos_wrch:
;            to the output capture (if on) and the screen.
;   Input:   A = character (32-126).
;   Output:  A, X and Y preserved.
wr_raw:
    pha
    txa
    pha
    tsx
    lda $0102,x                 ; the character
    ldx MB_CAPTURE
    beq wrr_screen
    jsr wr_tee
    tsx
    lda $0102,x
wrr_screen:
    jsr out_char
wrr_done:
    pla
    tax
    pla
    rts

; wr_tee
;   Summary: copy an output byte into the remote output ring.
;   Function: when the ring is full, waits for the host to read it, for
;            2.56 to 5.12 seconds (TIME); then capture is switched off so
;            a host that went away cannot hang the machine. ESCAPE also
;            leaves the wait.
;   Input:   A = byte.  Output: MB_RING, MB_RINGW.
;   Uses:    A, X, mosTMP+2/+3.
wr_tee:
    ldx MB_RINGW
    sta MB_RING,x
    inx
    txa
    and #MB_RINGMASK
    cmp MB_RINGR
    bne wt_store                ; room left
    sta mosTMP+3
    lda mostime+1               ; full: wait for the host, 2.56-5.12 s
    sta mosTMP+2                ; (TIME high byte at the start)
wt_wait:
    bit ESCFLG
    bmi wt_off
    lda mosTMP+3
    cmp MB_RINGR
    bne wt_go
    lda mostime+1
    sec
    sbc mosTMP+2
    cmp #2
    bcc wt_wait
wt_off:
    lda #0                      ; host gone: capture off
    sta MB_CAPTURE
    rts
wt_go:
    lda mosTMP+3
wt_store:
    sta MB_RINGW
    rts

vdu_nparam:
    dta 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dta 0, 1, 2, 5, 0, 0, 1, 9, 8, 5, 0, 0, 4, 4, 0, 2

vdu_table:
    dta a(wr_done-1)            ;  0 null
    dta a(wr_done-1)            ;  1 next char to printer
    dta a(wr_done-1)            ;  2 printer on
    dta a(wr_done-1)            ;  3 printer off
    dta a(wr_done-1)            ;  4 text at text cursor
    dta a(wr_done-1)            ;  5 text at graphics cursor
    dta a(wr_done-1)            ;  6 VDU on
    dta a(wr_done-1)            ;  7 bell
    dta a(vdu_bs-1)             ;  8 cursor left
    dta a(vdu_ht-1)             ;  9 cursor right
    dta a(vdu_lf-1)             ; 10 cursor down
    dta a(vdu_vt-1)             ; 11 cursor up
    dta a(vdu_eng-1)            ; 12 CLS
    dta a(vdu_cr-1)             ; 13 carriage return
    dta a(wr_done-1)            ; 14 paged mode on
    dta a(wr_done-1)            ; 15 paged mode off
    dta a(vdu_eng-1)            ; 16 CLG
    dta a(vdu_eng-1)            ; 17 COLOUR
    dta a(vdu_eng-1)            ; 18 GCOL
    dta a(vdu_pal-1)            ; 19 palette
    dta a(vdu_defcol-1)         ; 20 default colours
    dta a(wr_done-1)            ; 21 VDU off
    dta a(vdu_mode-1)           ; 22 MODE
    dta a(vdu_23-1)             ; 23 cursor / character definition
    dta a(vdu_eng-1)            ; 24 graphics window
    dta a(vdu_eng-1)            ; 25 PLOT
    dta a(vdu_eng-1)            ; 26 default windows
    dta a(wr_done-1)            ; 27 escape
    dta a(vdu_eng-1)            ; 28 text window
    dta a(vdu_eng-1)            ; 29 graphics origin
    dta a(vdu_home-1)           ; 30 home
    dta a(vdu_tab-1)            ; 31 TAB(x,y)

; VDU command handlers. Entered from wr_exec with the parameters in
; vdubuf; all end at wr_done, which restores the caller's registers.

vdu_bs:                         ; VDU 8: cursor left
    lda #$9D
    bne vdu_out
vdu_ht:                         ; VDU 9: cursor right
    lda #$1D
    bne vdu_out
vdu_lf:                         ; VDU 10: cursor down, scrolls at the bottom
    lda #$11
    bne vdu_out
vdu_vt:                         ; VDU 11: cursor up
    lda #$91
    bne vdu_out
vdu_cls:                        ; VDU 12 CLS, VDU 22 MODE (text only yet)
    lda #$93
    bne vdu_out
vdu_home:                       ; VDU 30: home
    lda #$13
vdu_out:
    jsr putpet
    jmp wr_done

vdu_cr:                         ; VDU 13: column 0 of the current line
    lda vtype
    beq vcr_text
    lda twl
    sta tcx
    jmp wr_done
vcr_text:
    sec
    jsr K_PLOT
    ldy #0
    clc
    jsr K_PLOT
    jmp wr_done

vdu_colour:                     ; VDU 17,n: COLOUR n (128+n: background)
    lda vdubuf
    bmi vdu_bg
    and #15
    tax
    lda bbc2c64,x
    sta COLOR
    jmp wr_done
vdu_bg:
    and #15
    tax
    lda bbc2c64,x
    sta $D021
    jmp wr_done

vdu_23:                         ; VDU 23,1,n: cursor off (0) / on
    lda vdubuf
    cmp #1
    bne vdu_23done
    lda vdubuf+1
    sta curson
vdu_23done:
    jmp wr_done

vdu_tab:                        ; VDU 31,x,y: TAB(x,y), ignored off screen
    lda vtype
    beq vtb_text
    lda vdubuf                  ; bitmap: inside the text window
    clc
    adc twl
    bcs vdu_tabdone
    cmp twr
    beq vtb_x
    bcs vdu_tabdone
vtb_x:
    tax
    lda vdubuf+1
    clc
    adc twt
    bcs vdu_tabdone
    cmp twb
    beq vtb_y
    bcs vdu_tabdone
vtb_y:
    stx tcx
    sta tcy
    jmp wr_done
vtb_text:
    lda vdubuf
    cmp #40
    bcs vdu_tabdone
    tay
    ldx vdubuf+1
    cpx #25
    bcs vdu_tabdone
    clc
    jsr K_PLOT
vdu_tabdone:
    jmp wr_done


; ----------------------------------------------------------------------------
; Screen modes (docs/DESIGN_GRAPHICS.md section 10). Text modes use the
; C64 text screen and the KERNAL screen editor; bitmap modes use the
; drawing engine at ENGINE (gfx.s), which also draws their text.

; mode state, shared with the engine and with OSBYTE in bank 0
vmode       dta 7               ; current MODE number
vtype       dta 0               ; 0: text screen, 1: VIC-II bitmap
vmode_mc    dta 0               ; 1: multicolour bitmap
vmode_cols  dta 40              ; text columns, rows
vmode_rows  dta 25
vmode_ncol  dta 16              ; logical colours: 2, 4 or 16
vmode_cmask dta 15              ; ncol - 1
vmode_xsh   dta 2               ; OS units -> pixels: x >> xsh
vmode_ysc   dta 0               ; y: 0 = 1024 -> 200 lines, 1 = 800 -> 200
vmode_xmax  dta a(319)          ; last pixel column
vmode_ppbm  dta 7               ; pixels per byte - 1
vmode_cw    dta 8               ; text cell width, height in pixels
vmode_ch    dta 8
vmode_bbc   dta 1               ; 1: BBC palette numbers in VDU 19
tcx         dta 0               ; bitmap modes: text cursor
tcy         dta 0
twl         dta 0               ; text window (characters)
twb         dta 24
twr         dta 39
twt         dta 0
tfg         dta 7               ; text colours (logical)
tbg         dta 0
gfg         dta 7               ; graphics colours and GCOL actions
gbg         dta 0
gact_fg     dta 0
gact_bg     dta 0
gox         dta a(0)            ; graphics origin (OS units)
goy         dta a(0)
gcx         dta a(0)            ; graphics cursor and the point before
gcy         dta a(0)
gpx         dta a(0)
gpy         dta a(0)
gwl         dta a(0)            ; graphics window (device pixels)
gwr         dta a(319)
gwt         dta a(0)
gwb         dta a(199)
pk_x        dta a(0)            ; PLOT/POINT coordinates
pk_y        dta a(0)
vdu5        dta 0               ; VDU 5: text at the graphics cursor
ecell       dta a(0)            ; engine: cell index for io_colget/put
gx_res      dta 0               ; engine result (POINT)
gx_save01   dta 0
gx_a        dta 0
gx_code     dta 0               ; VDU code for the engine's e_vdu
vmode_pal   dta 0               ; offset of the mode's palette set
vm_t        dta 0               ; scratch (never the MOS zero page: the
                                ; VDU path runs inside MOS commands)
pal         :16 dta 0           ; logical colour -> C64 colour
glyph       :8 dta 0            ; glyph of the character being drawn

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
bbc2c64:
    dta 0, 2, 5, 7, 6, 4, 3, 1, 8, 9, 10, 11, 12, 13, 14, 15
pal_c64:
    dta 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

; ----------------------------------------------------------------------------
; vdu_mode
;   Summary: VDU 22,n (MODE n).
;   Function: looks n up in mode_nums (an unknown number uses n AND 7,
;            as the BBC Model B does), sets the vmode_* variables and the
;            default palette, then the VIC-II and the screen: text modes
;            get the text screen and font back; bitmap modes switch the
;            KERNAL cursor off, and the engine clears the bitmap and
;            resets windows, cursors and colours.
vdu_mode:
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
    jmp vdu_mode
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
    jsr pal_default
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
    jmp wr_done
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
    jmp wr_done

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

; io_colget / io_colput: colour RAM byte of cell ecell (A in/out), from
; the engine ($01 = $34)
io_colget:
    jsr ioc_addr
    inc $01                     ; $34 -> $35: I/O in
ioc_rd:
    lda $D800
    dec $01
    rts
io_colput:
    pha
    jsr ioc_addr
    pla
    inc $01
ioc_wr:
    sta $D800
    dec $01
    rts
ioc_addr:
    lda ecell
    sta ioc_rd+1
    sta ioc_wr+1
    lda ecell+1
    clc
    adc #>$D800
    sta ioc_rd+2
    sta ioc_wr+2
    rts

; ----------------------------------------------------------------------------
; gx_call
;   Summary: call the drawing engine (under I/O) at entry X.
;   Function: interrupts off, $01 = $34 (all RAM) for the call, then the
;            caller's $01 and interrupt flag back.
;   Input:   X = GX_* entry offset, A = argument (if any); engine inputs
;            in core variables.
;   Output:  per entry.  Uses: A, X, Y.
gx_call:
    stx gxc_j+1
    sta gx_a                    ; A is an argument (e_pet)
    php
    sei
    lda $01
    sta gx_save01
    lda #$34
    sta $01
    lda gx_a
gxc_j:
    jsr ENGINE
    lda gx_save01
    sta $01
    plp
    rts

; nmi_rti: the RAM NMI/IRQ vectors at $FFFA point here (ROMs out)
nmi_rti:
    rti

; gx_yield: from the engine: let pending interrupts run, then go on
gx_yield:
    lda gx_save01
    sta $01
    cli
    nop
    nop
    sei
    lda #$34
    sta $01
    rts

; ----------------------------------------------------------------------------
; glyph_get
;   Summary: the 8x8 glyph of ASCII character A into glyph[].
;   Function: from the REU font (REU_FONT, ASCII order, built at start-up
;            by font_to_reu), or without an REU from the character ROM.
;   Uses:    A, X, Y.
glyph_get:
    tax
    lda reu_banks
    ora reu_banks+1
    beq gg_rom
    txa                         ; REU address = REU_FONT + code * 8
    asl
    sta REU_ADDR
    lda #0
    rol
    asl REU_ADDR
    rol
    asl REU_ADDR
    rol
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<glyph
    sta REU_C64
    lda #>glyph
    sta REU_C64+1
    lda #8
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    rts
gg_rom:                         ; character ROM, by screen code
    lda asc2pet,x
    jsr pet2scr
    sta vm_t
    lda #0
    asl vm_t
    rol
    asl vm_t
    rol
    asl vm_t
    rol
    adc #>$D000
    sta ggr_rd+2
    lda vm_t
    sta ggr_rd+1
    php
    sei
    lda $01
    pha
    lda #$33
    sta $01
    ldy #7
ggr_rd:
    lda $D000,y
    sta glyph,y
    dey
    bpl ggr_rd
    pla
    sta $01
    plp
    rts

; pet2scr: PETSCII A -> screen code (lower/upper case set)
pet2scr:
    cmp #$20
    bcc p2s_space
    cmp #$40
    bcc p2s_done
    cmp #$60
    bcc p2s_sub40
    cmp #$80
    bcc p2s_sub20
    cmp #$A0
    bcc p2s_space
    cmp #$C0
    bcc p2s_sub40
    sbc #$80
    rts
p2s_sub40:
    sec
    sbc #$40
    rts
p2s_sub20:
    sec
    sbc #$20
p2s_done:
    rts
p2s_space:
    lda #$20
    rts

; font_restore: the text font at FONT after a bitmap mode (from the REU
; copy made at start-up, or rebuilt from the character ROM)
font_restore:
    lda reu_banks
    ora reu_banks+1
    beq fr_rom
    lda #<FONT
    sta REU_C64
    lda #>FONT
    sta REU_C64+1
    lda #<REU_VICFONT
    sta REU_ADDR
    lda #>REU_VICFONT
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<$800
    sta REU_LEN
    lda #>$800
    sta REU_LEN+1
    lda #0
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    rts
fr_rom:
    farcall font_init, BANK_MOS
    rts

; ----------------------------------------------------------------------------
; font_to_reu
;   Summary: at start-up: the text font to REU_VICFONT (for MODE changes)
;            and, in ASCII order, to REU_FONT (text in bitmap modes; codes
;            128-255 get the glyph of code - 128).
;   Function: runs here, in RAM, with $01 = $35: the font at FONT is RAM
;            under the KERNAL, and I/O is needed for the REU.
;   Input:   reu_banks.  Uses: A, X, Y, vm_t.
font_to_reu:
    lda reu_banks
    ora reu_banks+1
    beq ftr_done
    php
    sei
    lda $01
    pha
    lda #$35
    sta $01
    lda #<FONT
    sta REU_C64
    lda #>FONT
    sta REU_C64+1
    lda #<REU_VICFONT
    sta REU_ADDR
    lda #>REU_VICFONT
    sta REU_ADDR+1
    lda #0
    sta REU_LEN
    lda #8                      ; 2K
    sta REU_LEN+1
    jsr ftr_go
    ldx #0
ftr_loop:
    txa
    and #$7F
    tay
    lda asc2pet,y
    jsr pet2scr
    sta vm_t                    ; C64 address = FONT + screen code * 8
    lda #0
    asl vm_t
    rol
    asl vm_t
    rol
    asl vm_t
    rol
    adc #>FONT
    sta REU_C64+1
    lda vm_t
    sta REU_C64
    txa                         ; REU address = REU_FONT + code * 8
    asl
    sta REU_ADDR
    lda #0
    rol
    asl REU_ADDR
    rol
    asl REU_ADDR
    rol
    adc #>REU_FONT
    sta REU_ADDR+1
    lda #8
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    jsr ftr_go
    inx
    bne ftr_loop
    pla
    sta $01
    plp
ftr_done:
    rts
ftr_go:
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #0
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    rts

; ----------------------------------------------------------------------------
; out_char
;   Summary: show printable ASCII character A at the text cursor.
;   Uses:    A, X, Y.
out_char:
    ldx vtype
    bne oc_bitmap
    tax
    lda asc2pet,x
    beq oc_done
    jmp putpet
oc_bitmap:
    jsr glyph_get
    ldx #GX_CHAR
    jmp gx_call
oc_done:
    rts


; ----------------------------------------------------------------------------
; vdu_pal (VDU 19,l,p,r,g,b)
;   Summary: logical colour l shows physical colour p: a BBC colour 0-15
;            in BBC modes, a C64 colour in the C64 modes. Bitmap modes
;            with 2 or 4 colours show the change at once (cells and
;            colour RAM); 16-colour modes use it for new drawing.
vdu_pal:
    lda vtype
    beq vp_done
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
    lda vmode_ncol
    cmp #16
    beq vp_done
    ldx #GX_MATRIX
    jsr gx_call
    jsr io_palette
vp_done:
    jmp wr_done

; vdu_defcol (VDU 20): default palette and colours
vdu_defcol:
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

; vdu_eng: VDU codes the engine handles in bitmap modes (12 CLS, 16 CLG,
; 17 COLOUR, 18 GCOL, 24-26, 28, 29); in text modes only 12 and 17 act
vdu_eng:
    lda vtype
    bne ve_bitmap
    lda gx_code
    cmp #12
    bne ve_n12
    lda #$93
    jsr putpet
    jmp wr_done
ve_n12:
    cmp #17
    bne ve_none
    jmp vdu_colour
ve_bitmap:
    ldx #GX_VDU
    jsr gx_call
ve_none:
    jmp wr_done

; ----------------------------------------------------------------------------
; Engine tables kept here for space (the engine reads the core freely)

gx_tables:
; Colour RAM offset of each cell row (0-960)
cofflo:
    :25 dta l(#*40)
coffhi:
    :25 dta h(#*40)
hmask:
    dta $80, $40, $20, $10, $08, $04, $02, $01
mcmask:
    dta $C0, $30, $0C, $03
; 2-bit value repeated over a byte
mcrep:
    dta $00, $55, $AA, $FF
; Top pixel row of each text row: 32 rows of 6 lines in 200 (r*25/4)
row6:
    :32 dta [#*25]/4
; group -> bit 0 dotted, bit 1 omit first, bit 2 omit last
lineflags:
    dta 0, 4, 1, 5, 2, 6, 3, 7


; ----------------------------------------------------------------------------
; ASCII -> PETSCII (generated by tools/gentables.py)

    icl 'tables_core.s'

core_end:
    .if core_end > CORE+$800
    .error "VDU core overflows its 2K"
    .endif
    :[CORE+$800-*] dta 0        ; full 2K: the image layout relies on it
