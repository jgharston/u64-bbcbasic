; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *FONT: whole character sets (bank 2)
;
; Fonts live in the REU (DESIGN_GRAPHICS.md 6 and 9.3): REU_FONT (ASCII
; order, the glyphs of the graphics modes), REU_VICFONT (screen-code order,
; the text screen's font, restored on MODE changes) and REU_DEFFONT (the
; start-up font, for *FONT DEFAULT). On the text screen the live font at
; FONT is written too; in graphics modes that RAM is bitmap. Without an
; REU only the text screen can change a font.
;
; Every source goes glyph by glyph through the 8-byte buffer `glyph`:
; files 8 bytes per read or write, the BBC font from this bank, the C64
; character ROM through the core's glyph_scr.
;
; File formats (the format word after the name; C64 when omitted):
;   C64    2048 bytes, 256 glyphs in screen-code order (a C64 charset;
;          2050 bytes with a load address are read too)
;   BBC    768 bytes, characters 32-127 in ASCII order (as in a BBC MOS
;          ROM at &C000)
;   ASCII  2048 bytes, characters 0-255 in ASCII order (the REU font)
;
; ----------------------------------------------------------------------------

FMT_C64     = 0
FMT_BBC     = 1
FMT_ASCII   = 2

; fsMODE = format, fsSX = glyph index, fsBLK = BBC font pointer: the OSFILE
; variables, free outside OSFILE.

; ----------------------------------------------------------------------------
; cmd_font
;   Summary: *FONT LOAD <file> [C64|BBC|ASCII], *FONT SAVE <file>
;            [C64|BBC|ASCII], *FONT BBC, *FONT C64, *FONT DEFAULT.
;   Function: dispatches on the first word.
;   Input:   mosPTR/Y = the rest of the command line.
;   Output:  the new font; raises on errors.
;   Uses:    A, X, Y, fs*, glyph, REU registers.
cmd_font:
    lda #<fw_load
    ldx #>fw_load
    jsr arg_word
    bcc cf_save
    jmp fo_load
cf_save:
    lda #<fw_save
    ldx #>fw_save
    jsr arg_word
    bcc cf_bbc
    jmp fo_save
cf_bbc:
    lda #<fw_bbc
    ldx #>fw_bbc
    jsr arg_word
    bcc cf_c64
    jmp fo_bbc
cf_c64:
    lda #<fw_c64
    ldx #>fw_c64
    jsr arg_word
    bcc cf_def
    jmp fo_c64
cf_def:
    lda #<fw_default
    ldx #>fw_default
    jsr arg_word
    bcc cf_syntax
    jmp fo_default
cf_syntax:
    jmp an_syntax

fw_load     dta 'LOAD', 0
fw_save     dta 'SAVE', 0
fw_bbc      dta 'BBC', 0
fw_c64      dta 'C64', 0
fw_ascii    dta 'ASCII', 0
fw_default  dta 'DEFAULT', 0

; fo_fmt: optional format word -> fsMODE (C64 when there is none); the
; line must end there
fo_fmt:
    lda #FMT_C64
    sta fsMODE
    lda #<fw_c64
    ldx #>fw_c64
    jsr arg_word
    bcs ff_end
    lda #<fw_bbc
    ldx #>fw_bbc
    jsr arg_word
    bcc ff_ascii
    lda #FMT_BBC
    sta fsMODE
    bcs ff_end
ff_ascii:
    lda #<fw_ascii
    ldx #>fw_ascii
    jsr arg_word
    bcc ff_end
    lda #FMT_ASCII
    sta fsMODE
ff_end:
    lda (mosPTR),y              ; nothing else may follow
    cmp #' '
    bne ff_cr
    iny
    bne ff_end
ff_cr:
    cmp #13
    bne cf_syntax
    rts

; fo_need: raise "Font needs an REU" in graphics modes without an REU
fo_need:
    jsr has_reu
    bne fn_ok
    lda vtype
    beq fn_ok
    brk
    dta 189, 'Font needs an REU', 0
fn_ok:
    rts

; has_reu: Z = 0 if there is an REU.  Uses: A.
has_reu:
    lda reu_banks
    ora reu_banks+1
    rts

; ----------------------------------------------------------------------------
; fo_load
;   Summary: *FONT LOAD <file> [C64|BBC|ASCII].
;   Function: checks the size against the format, reads 8 bytes at a time
;            and installs each glyph (fo_put); a C64 font also rebuilds
;            the ASCII-order font from the new text font.
;   Input:   mosPTR/Y after LOAD.  Output: the font; raises on errors.
;   Uses:    A, X, Y, fs*, glyph.
fo_load:
    jsr uci_need
    jsr arg_name
    jsr fo_fmt
    jsr fo_need
    jsr fs_free_target
    lda #FA_READ
    jsr fs_open
    bcc fl_isopen
    jmp uci_error
fl_isopen:
    jsr fs_size
    lda fsTMP+2
    ora fsTMP+3
    bne fl_badsize
    ldx fsMODE
    lda fsTMP+1
    cmp fo_size,x
    bne fl_badsize
    lda fsTMP
    beq fl_sizeok
    cmp #2                      ; C64 with a load address: skip it
    bne fl_badsize
    cpx #FMT_C64
    bne fl_badsize
    lda #2
    jsr fo_read
fl_sizeok:
    lda fo_first,x
    sta fsSX
fl_loop:
    lda #8
    jsr fo_read
    jsr fo_put
    inc fsSX
    ldx fsMODE
    lda fsSX
    cmp fo_last,x
    bne fl_loop
    jsr fs_close_tgt
    lda fsMODE                  ; C64: the ASCII font from the text font
    bne fl_done
    jmp fo_mkascii
fl_done:
    rts
fl_badsize:
    jsr fs_close_tgt
    brk
    dta 188, 'Bad font file', 0

fo_size     dta 8, 3, 8         ; size high bytes per format
fo_first    dta 0, 32, 0        ; first glyph index
fo_last     dta 0, 128, 0       ; index after the last (0: 256 glyphs)

; fo_read: read A bytes (1-8) of the open file into glyph; raises on errors
fo_read:
    pha
    lda #DOS_READ
    jsr fs_hdr2
    pla
    sta uciHDR+2
    sta fsLEN
    lda #0
    sta uciHDR+3
    sta fsLEN+1
    lda #4
    sta uciHLEN
    jsr fl_send_nopay
    lda #<glyph
    sta fsADDR
    lda #>glyph
    sta fsADDR+1
    jsr uci_read_to
    jsr uci_finish
    bcs fr_err
    rts
fr_err:
    jsr fs_saveerr              ; closes the file, raises the status
    jmp uci_error

; ----------------------------------------------------------------------------
; fo_save
;   Summary: *FONT SAVE <file> [C64|BBC|ASCII]: the current font.
;   Function: C64: the text font (REU copy, or FONT on the text screen
;            without an REU); BBC and ASCII: the ASCII-order font (REU,
;            or the text font's glyphs without one). 8 bytes per write.
;   Input:   mosPTR/Y after SAVE.  Output: the file; raises on errors.
;   Uses:    A, X, Y, fs*, glyph.
fo_save:
    jsr uci_need
    jsr arg_name
    jsr fo_fmt
    jsr fo_need
    jsr fs_free_target
    lda #FA_CREATE
    jsr fs_open
    bcc fs_isopen
    jmp uci_error
fs_isopen:
    ldx fsMODE
    lda fo_first,x
    sta fsSX
fsv_loop:
    jsr fo_get
    jsr fo_write8
    inc fsSX
    ldx fsMODE
    lda fsSX
    cmp fo_last,x
    bne fsv_loop
    jmp fs_close_tgt

; fo_write8: write glyph (8 bytes) to the open file; raises on errors
fo_write8:
    lda #<glyph
    sta fsPTR
    lda #>glyph
    sta fsPTR+1
    lda #8
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #DOS_WRITE
    jsr fs_hdr2
    lda #0
    sta uciHDR+2
    sta uciHDR+3
    lda #4
    sta uciHLEN
    jsr uci_send
    jsr uci_finish
    bcs fw_err
    rts
fw_err:
    jsr fs_saveerr
    jmp uci_error

; fo_get: glyph = glyph fsSX of the current font, in format fsMODE
fo_get:
    lda fsMODE
    bne fg_asc
    jsr has_reu                 ; C64: by screen code
    beq fg_font
    lda fsSX
    ldx #>REU_VICFONT
    jmp reu_get
fg_font:
    lda fsSX
    ldx #>FONT
    ldy #$35
    jmp glyph_scr
fg_asc:
    jsr has_reu                 ; BBC, ASCII: by ASCII code
    beq fg_text
    lda fsSX
    ldx #>REU_FONT
    jmp reu_get
fg_text:
    lda fsSX
    and #$7F
    jmp glyph_font

; ----------------------------------------------------------------------------
; fo_bbc / fo_c64 / fo_default
;   Summary: *FONT BBC: the BBC Micro's characters 32-127 (MOS 1.20, see
;            NOTICE.md); *FONT C64: the C64 character ROM (lower/upper
;            case set); *FONT DEFAULT: the start-up font.
;   Function: as *FONT LOAD, from this bank, the character ROM or the
;            REU copy kept at start-up. DEFAULT without an REU rebuilds the
;            start-up font (text screen only).
;   Output:  the font.  Uses: A, X, Y, fs*, glyph.
fo_bbc:
    jsr fo_need
    lda #FMT_BBC
    sta fsMODE
    lda #<bbcfont
    sta fsBLK
    lda #>bbcfont
    sta fsBLK+1
    lda #32
    sta fsSX
fb_loop:
    ldy #7
fb_copy:
    lda (fsBLK),y
    sta glyph,y
    dey
    bpl fb_copy
    jsr fo_put
    lda fsBLK
    clc
    adc #8
    sta fsBLK
    bcc fb_next
    inc fsBLK+1
fb_next:
    inc fsSX
    lda fsSX
    cmp #128
    bne fb_loop
    rts

fo_c64:
    jsr fo_need
    lda #0
    sta fsSX
fc_loop:
    lda fsSX
    ldx #>$D800
    ldy #$33
    jsr glyph_scr
    lda fsSX
    jsr put_scr
    inc fsSX
    bne fc_loop
    jmp fo_mkascii

fo_default:
    jsr has_reu
    bne fd_reu
    lda vtype                   ; no REU: rebuild on the text screen
    beq fd_init
    jmp fo_need                 ; (raises)
fd_init:
    farcall font_init, BANK_MOS
    rts
fd_reu:
    lda #0
    sta fsSX
fd_loop:
    lda fsSX
    ldx #>REU_DEFFONT
    jsr reu_get
    lda fsSX
    jsr put_scr
    inc fsSX
    bne fd_loop
    jmp fo_mkascii

; ----------------------------------------------------------------------------
; font_keepdef
;   Summary: at start-up: the text font (REU_VICFONT) to REU_DEFFONT, for
;            *FONT DEFAULT.
;   Input:   reu_banks.  Uses: A, X, Y, fsSX, glyph.
font_keepdef:
    jsr has_reu
    beq fk_done
    lda #0
    sta fsSX
fk_loop:
    lda fsSX
    ldx #>REU_VICFONT
    jsr reu_get
    lda fsSX
    ldx #>REU_DEFFONT
    jsr reu_put
    inc fsSX
    bne fk_loop
fk_done:
    rts

; ----------------------------------------------------------------------------
; fo_put
;   Summary: install glyph as glyph fsSX of format fsMODE.
;   Function: C64: text font screen code fsSX. BBC: ASCII code fsSX in the
;            REU font (and fsSX + 128, as at start-up) and in the text
;            font (with its reverse copy). ASCII: REU font code fsSX, and
;            the text font for 32-127.
;   Uses:    A, X, Y, fsCNT, fsADDR.
fo_put:
    lda fsMODE
    bne fp_asc
    lda fsSX
    jmp put_scr
fp_asc:
    jsr has_reu
    beq fp_text
    lda fsSX
    ldx #>REU_FONT
    jsr reu_put
    lda fsMODE
    cmp #FMT_BBC
    bne fp_text
    lda fsSX
    ora #$80
    ldx #>REU_FONT
    jsr reu_put
fp_text:
    lda fsSX
    cmp #32
    bcc fp_done
    cmp #128
    bcs fp_done
    jmp put_ascscr
fp_done:
    rts

; put_ascscr: glyph as ASCII character A (32-127) in the text font: at its
; screen code, and inverted at screen code + 128 (the cursor)
put_ascscr:
    tax
    lda asc2pet,x
    beq pa_done
    jsr pet2scr
    pha
    jsr put_scr
    jsr ginv
    pla
    ora #$80
    jsr put_scr
    jmp ginv
pa_done:
    rts

; ginv: invert glyph
ginv:
    ldy #7
gi_loop:
    lda glyph,y
    eor #$FF
    sta glyph,y
    dey
    bpl gi_loop
    rts

; put_scr: glyph as screen code A of the text font: the REU copy, and on
; the text screen the live font at FONT (written under the KERNAL: writes
; reach the RAM)
put_scr:
    pha
    jsr has_reu
    beq ps_text
    pla
    pha
    ldx #>REU_VICFONT
    jsr reu_put
ps_text:
    pla
    ldx vtype
    bne ps_done
    sta fsCNT
    lda #0
    asl fsCNT
    rol
    asl fsCNT
    rol
    asl fsCNT
    rol
    clc
    adc #>FONT
    sta fsADDR+1
    lda fsCNT
    sta fsADDR
    ldy #7
ps_copy:
    lda glyph,y
    sta (fsADDR),y
    dey
    bpl ps_copy
ps_done:
    rts

; fo_mkascii: the REU font (ASCII order) from the REU text font, as
; font_to_reu does at start-up (128-255 get the glyph of code - 128)
fo_mkascii:
    jsr has_reu
    beq fm_done
    lda #0
    sta fsSX
fm_loop:
    lda fsSX
    and #$7F
    tax
    lda asc2pet,x
    jsr pet2scr
    ldx #>REU_VICFONT
    jsr reu_get
    lda fsSX
    ldx #>REU_FONT
    jsr reu_put
    inc fsSX
    bne fm_loop
fm_done:
    rts

; ----------------------------------------------------------------------------
; reu_get / reu_put
;   Summary: glyph from / to the REU at page X + A * 8 (REU bank
;            REU_FONT_BANK).
;   Uses:    A, fsCNT.
reu_get:
    jsr ra_set
    lda #REU_TO_C64
    sta REU_CMD
    rts
reu_put:
    jsr ra_set
    lda #REU_TO_REU
    sta REU_CMD
    rts
ra_set:
    stx fsCNT+1
    sta fsCNT
    lda #0
    asl fsCNT
    rol
    asl fsCNT
    rol
    asl fsCNT
    rol
    clc
    adc fsCNT+1
    sta REU_ADDR+1
    lda fsCNT
    sta REU_ADDR
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
    rts

; The BBC Micro's characters 32-127 (MOS 1.20 &C000-&C2FF, (C) Acorn;
; see NOTICE.md)
bbcfont:
    ins '../acorn/bbcfont.bin'
