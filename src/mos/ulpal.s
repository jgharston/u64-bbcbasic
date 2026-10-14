; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- palettes through the Ultimate (bank 2)
;
; Control target commands (firmware 3.15a+, 1541ultimate #791): $04 $51
; get the palette (48 bytes RGB), $52 + 48 bytes set it, $53 + index, R,
; G, B set one colour, $54 back to the firmware's default colours.
;
; Two palettes, kept in the REU (bank REU_FONT_BANK):
; - REU_PAL64: the RGB of the 16 C64 colours, shown whenever a VIC-II
;   screen is up (text, C64 modes, BBC modes on the VIC-II). Read from the
;   Ultimate at start-up (so a palette chosen in its menu stays), copied
;   to REU_PALBOOT for *PALETTE RESET; *PALETTE LOAD/SAVE/BBC/C64 and
;   VDU 19,l,16,r,g,b change it.
; - REU_LRGB: the RGB of each logical colour in Upic Lite and teletext,
;   where the Ultimate's palette decodes the picture: entry i shows
;   logical colour i AND cmask (ul_setpal).
; Without an REU: Upic Lite and teletext compose from pal[] directly, the
; VIC-II screens get the firmware's default colours, and *PALETTE only
; does C64.
;
; ----------------------------------------------------------------------------

CTRL_GETPAL   = $51
CTRL_SETPAL   = $52
CTRL_SETCOL   = $53
CTRL_RESETPAL = $54

REU_PAL64   = $1800             ; 48: C64 colours, current
REU_PALBOOT = $1830             ; 48: C64 colours at start-up
REU_LRGB    = $1860             ; 48: logical colours (Upic Lite, teletext)
REU_PALTMP  = $1890             ; 48: a .vpl file while it is read
REU_FONTSAVE = $1900            ; 760: characters 32-126 of REU_FONT while
                                ; MODE 1 on the VIC-II has the 4x6 font

PALBUF      = errbuf+1          ; 48 bytes composed / read here

; ----------------------------------------------------------------------------
; pal_boot
;   Summary: at start-up: are the palette commands there? Reads the
;            Ultimate's current palette into REU_PAL64 and REU_PALBOOT.
;   Function: get palette ($51); the 48 bytes land in PALBUF, the status
;            after them (uci_finish_x).
;   Output:  C = 0 if the Ultimate answered with 48 bytes.
;   Uses:    A, X, Y, fs*, errbuf, REU registers.
pal_boot:
    jsr pb_read
    bcs pb_done
    jsr has_reu
    beq pb_ok
    ldx #>REU_PAL64             ; PALBUF to both copies
    lda #<REU_PAL64
    jsr pal_toreu
    ldx #>REU_PALBOOT
    lda #<REU_PALBOOT
    jsr pal_toreu
pb_ok:
    clc
pb_done:
    rts

; pb_read: the Ultimate's palette into PALBUF. Output: C = 0 if 48 bytes
; came
pb_read:
    lda uci_ok
    bne pb_go
    sec
    rts
pb_go:
    lda #TARGET_CTRL
    sta fsTGT
    lda #CTRL_GETPAL
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    lda #<PALBUF
    sta fsADDR
    lda #>PALBUF
    sta fsADDR+1
    lda #48
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_read_to
    lda fsCNT                   ; bytes received
    pha
    ldx #48
    jsr uci_finish_x
    pla
    bcs pb_fail
    cmp #48
    bne pb_fail
    clc
    rts
pb_fail:
    sec
    rts

; pal_toreu / pal_fromreu: PALBUF (48 bytes) to / from the REU at X/A
; (high/low). Uses: A, REU registers.
pal_toreu:
    php                         ; (interrupts off while the REU is set up:
    sei                         ; the sound interrupt uses it too)
    jsr pr_set
    lda #REU_TO_REU
    sta REU_CMD
    plp
    rts
pal_fromreu:
    php
    sei
    jsr pr_set
    lda #REU_TO_C64
    sta REU_CMD
    plp
    rts
pr_set:
    sta REU_ADDR
    stx REU_ADDR+1
    lda #<PALBUF
    sta REU_C64
    lda #>PALBUF
    sta REU_C64+1
    lda #48
    bne pr_len

; pr_dma3: 3 bytes between C64 address X/A (high/low) and REU_LRGB +
; 3 * Y (the RGB of logical colour Y), direction REU command in pr_cmd
pr_dma3:
    sta REU_C64
    stx REU_C64+1
    tya
    sta fsCNT
    asl
    adc fsCNT                   ; Y * 3 (Y < 16: no carry)
    adc #<REU_LRGB
    sta REU_ADDR
    lda #>REU_LRGB
    adc #0
    sta REU_ADDR+1
    lda #3
pr_len:
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_FONT_BANK
    sta REU_BANK
    rts

; ----------------------------------------------------------------------------
; pal_apply
;   Summary: show the C64 palette (REU_PAL64) on the Ultimate: after
;            leaving Upic Lite or teletext, and after *PALETTE.
;   Function: without an REU the firmware's default colours ($54).
;   Output:  C = 1 if refused.  Uses: A, X, Y, fs*, errbuf.
pal_apply:
    lda pal_ok
    beq pa_none
    jsr has_reu
    beq ul_palreset
    ldx #>REU_PAL64
    lda #<REU_PAL64
    jsr pal_fromreu
    jmp pal_send
pa_none:
    sec
    rts

; pal_send: send PALBUF (48 bytes) as the palette ($52)
pal_send:
    lda #<PALBUF
    sta fsPTR
    lda #>PALBUF
    sta fsPTR+1
    lda #48
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #TARGET_CTRL
    sta fsTGT
    lda #CTRL_SETPAL
    jsr fs_hdr2
    jsr uci_send
    jmp uci_finish

; ul_palreset: the firmware's default colours ($54). Output: C = 1 if
; refused (no UCI, or firmware without palette commands).
ul_palreset:
    lda uci_ok
    bne upr_go
    sec
    rts
upr_go:
    lda #0
    sta fsLEN
    sta fsLEN+1
    lda #TARGET_CTRL
    sta fsTGT
    lda #CTRL_RESETPAL
    jsr fs_hdr2
    jsr uci_send
    jmp uci_finish

; ----------------------------------------------------------------------------
; ul_setpal
;   Summary: Upic Lite / teletext palette from pal[]: logical colour l
;            shows BBC colour pal[l]; entry i of the Ultimate's palette
;            shows logical colour i AND cmask (the renderer writes shifted
;            picture bytes to $D020, the palette decodes the low bits).
;   Function: with an REU: REU_LRGB[l] = bbcrgb[pal[l]] for every logical
;            colour, then ul_sendlrgb. Without: composed straight from
;            pal[].
;   Input:   pal[], vmode_cmask.  Output: C = 1 if the Ultimate refused.
;   Uses:    A, X, Y, fs*, errbuf.
ul_setpal:
    jsr has_reu
    beq usp_direct
    ldy #0
usp_log:
    sty fsSX
    jsr usp_one                 ; REU_LRGB[Y] = bbcrgb[pal[Y]]
    ldy fsSX
    iny
    tya
    and vmode_cmask
    bne usp_log
    jmp ul_sendlrgb
usp_direct:
    ldx #0                      ; palette index
    ldy #0                      ; byte in PALBUF
usp_loop:
    txa
    and vmode_cmask
    stx fsCNT
    tax
    lda pal,x                   ; BBC colour 0-15 -> RGB offset (x 3)
    and #15
    sta fsCNT+1
    asl
    adc fsCNT+1
    tax
    lda bbcrgb,x
    sta PALBUF,y
    lda bbcrgb+1,x
    sta PALBUF+1,y
    lda bbcrgb+2,x
    sta PALBUF+2,y
    iny
    iny
    iny
    ldx fsCNT
    inx
    cpx #16
    bne usp_loop
    jmp pal_send

; usp_one: REU_LRGB[Y] = bbcrgb[pal[Y]] (through glyph)
usp_one:
    lda pal,y
    and #15
    sta fsCNT
    asl
    adc fsCNT
    tax
    lda bbcrgb,x
    sta glyph
    lda bbcrgb+1,x
    sta glyph+1
    lda bbcrgb+2,x
    sta glyph+2
    lda #<glyph
    ldx #>glyph
    php
    sei
    jsr pr_dma3
    lda #REU_TO_REU
    sta REU_CMD
    plp
    rts

; ul_setlog: logical colour A changed (VDU 19,l,p in Upic Lite): only its
; entry, so RGB colours of the others stay
ul_setlog:
    tay
    jsr has_reu
    beq usp_direct
    jsr usp_one
    jmp ul_sendlrgb

; ul_setrgb: VDU 19,l,16,r,g,b in Upic Lite: logical colour l (vdubuf)
; gets the RGB in vdubuf+2..4 (needs an REU)
ul_setrgb:
    jsr has_reu
    beq usr_done
    lda vdubuf
    and vmode_cmask
    tay
    lda #<[vdubuf+2]
    ldx #>[vdubuf+2]
    php
    sei
    jsr pr_dma3
    lda #REU_TO_REU
    sta REU_CMD
    plp
    jmp ul_sendlrgb
usr_done:
    rts

; ul_sendlrgb: PALBUF entry i = REU_LRGB[i AND cmask], sent (PALBUF
; does not cross a page)
ul_sendlrgb:
    ldy #0
usl_loop:
    sty fsSX
    tya                         ; PALBUF + 3 * i
    sta fsCNT
    asl
    adc fsCNT
    adc #<PALBUF
    pha
    tya
    and vmode_cmask
    tay
    pla
    ldx #>PALBUF
    php
    sei
    jsr pr_dma3
    lda #REU_TO_C64
    sta REU_CMD
    plp
    ldy fsSX
    iny
    cpy #16
    bne usl_loop
    jmp pal_send

; ----------------------------------------------------------------------------
; pal_vdu19rgb
;   Summary: VDU 19,l,16,r,g,b on a VIC-II screen: the C64 colour that
;            logical colour l shows gets the RGB colour.
;   Function: C64 colour = bbc2c64[l] on the text screen, pal[l AND cmask]
;            in bitmap modes; REU_PAL64 is updated (with an REU) and the
;            colour set at once ($53).
;   Input:   vdubuf = l, 16, r, g, b.  Uses: A, X, Y, fs*, errbuf.
pal_vdu19rgb:
    lda pal_ok
    beq pv_done
    lda vdubuf
    and #15
    tax
    lda vtype
    bne pv_bitmap
    lda bbc2c64,x
    jmp pv_col
pv_bitmap:
    txa
    and vmode_cmask
    tax
    lda pal,x
pv_col:
    and #15
    sta PALBUF                  ; index, R, G, B: the $53 payload
    tay
    lda vdubuf+2
    sta PALBUF+1
    lda vdubuf+3
    sta PALBUF+2
    lda vdubuf+4
    sta PALBUF+3
    jsr has_reu
    beq pv_send
    php
    sei
    tya                         ; REU_PAL64 + 3 * colour
    sta fsCNT
    asl
    adc fsCNT
    adc #<REU_PAL64
    sta REU_ADDR
    lda #>REU_PAL64
    adc #0
    sta REU_ADDR+1
    lda #<[PALBUF+1]
    sta REU_C64
    lda #>[PALBUF+1]
    sta REU_C64+1
    lda #3
    jsr pr_len
    lda #REU_TO_REU
    sta REU_CMD
    plp
pv_send:
    lda #<PALBUF
    sta fsPTR
    lda #>PALBUF
    sta fsPTR+1
    lda #4
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #TARGET_CTRL
    sta fsTGT
    lda #CTRL_SETCOL
    jsr fs_hdr2
    jsr uci_send
    jmp uci_finish
pv_done:
    rts

; ----------------------------------------------------------------------------
; cmd_palette
;   Summary: *PALETTE LOAD <file> [VPL], *PALETTE SAVE <file>, *PALETTE
;            BBC, *PALETTE C64, *PALETTE RESET: the 16 C64 colours.
;   Function: files: 48 bytes (R, G, B per colour, C64 colour order), or
;            with VPL a VICE palette file (text: per colour a line "RR GG
;            BB [dither]" in hex, # starts a comment). BBC: the 8 colours
;            BBC colours map to get the BBC's pure RGB. C64: the
;            firmware's default colours. RESET: the palette at start-up.
;            Shown at once on a VIC-II screen; Upic Lite and teletext
;            keep theirs until the next MODE change.
;   Input:   mosPTR/Y.  Output: the palette; raises on errors.
;   Uses:    A, X, Y, fs*, errbuf, glyph, REU registers.
cmd_palette:
    jsr uci_need
    lda pal_ok
    bne cp_ok
    brk
    dta 187, 'No palette commands', 0
cp_ok:
    lda #<fw_c64
    ldx #>fw_c64
    jsr arg_word
    bcc cp_reu
    jsr ul_palreset             ; the firmware's colours ...
    jsr has_reu
    beq cp_show
    jsr pb_read                 ; ... read back into REU_PAL64
    bcs cp_show
    ldx #>REU_PAL64
    lda #<REU_PAL64
    jmp pal_toreu
cp_show:
    rts                         ; ($54 already shows them)
cp_reu:
    jsr has_reu
    bne cp_words
    brk
    dta 189, 'Palette needs an REU', 0
cp_words:
    lda #<fw_load
    ldx #>fw_load
    jsr arg_word
    bcc cp_save
    jmp pl_load
cp_save:
    lda #<fw_save
    ldx #>fw_save
    jsr arg_word
    bcc cp_bbc
    jmp pl_save
cp_bbc:
    lda #<fw_bbc
    ldx #>fw_bbc
    jsr arg_word
    bcc cp_reset
    jmp pl_bbc
cp_reset:
    lda #<pw_reset
    ldx #>pw_reset
    jsr arg_word
    bcs pl_reset
    jmp an_syntax

pw_reset    dta 'RESET', 0
pw_vpl      dta 'VPL', 0

; *PALETTE RESET: REU_PALBOOT -> REU_PAL64
pl_reset:
    ldx #>REU_PALBOOT
    lda #<REU_PALBOOT
    jsr pal_fromreu
    jmp pl_set
; pl_set: PALBUF -> REU_PAL64, shown if a VIC-II screen is up
pl_set:
    ldx #>REU_PAL64
    lda #<REU_PAL64
    jsr pal_toreu
pl_show:
    lda vtype
    beq pl_apply
    cmp #1
    bne pl_noshow
    lda vmode_ul
    bne pl_noshow
pl_apply:
    jmp pal_apply
pl_noshow:
    rts

; *PALETTE BBC: C64 colour bbc2c64[b] = BBC colour b (0-7)
pl_bbc:
    ldx #>REU_PAL64
    lda #<REU_PAL64
    jsr pal_fromreu
    ldx #7
pbb_loop:
    stx fsSX
    lda bbc2c64,x               ; PALBUF + 3 * C64 colour
    sta fsCNT
    asl
    adc fsCNT
    tay
    txa                         ; bbcrgb + 3 * b
    sta fsCNT
    asl
    adc fsCNT
    tax
    lda bbcrgb,x
    sta PALBUF,y
    lda bbcrgb+1,x
    sta PALBUF+1,y
    lda bbcrgb+2,x
    sta PALBUF+2,y
    ldx fsSX
    dex
    bpl pbb_loop
    jmp pl_set

; *PALETTE SAVE <file>: REU_PAL64, 8 bytes per write
pl_save:
    jsr arg_name
    jsr ff_end                  ; nothing may follow
    jsr fs_free_target
    lda #FA_CREATE
    jsr fs_open
    bcc ps_open
    jmp uci_error
ps_open:
    lda #0
    sta fsSX
ps_loop:
    lda fsSX
    ldx #>REU_PAL64
    jsr reu_get                 ; (page $18 + A * 8)
    jsr fo_write8
    inc fsSX
    lda fsSX
    cmp #6
    bne ps_loop
    jmp fs_close_tgt

; *PALETTE LOAD <file> [VPL]
pl_load:
    jsr arg_name
    lda #<pw_vpl
    ldx #>pw_vpl
    jsr arg_word
    lda #0
    rol                         ; C: VPL
    sta fsMODE
    jsr ff_end
    jsr fs_free_target
    lda #FA_READ
    jsr fs_open
    bcc pld_open
    jmp uci_error
pld_open:
    jsr fs_size
    lda fsTMP+2
    ora fsTMP+3
    bne pld_bad
    lda fsMODE
    bne pld_vpl
    lda fsTMP+1                 ; binary: 48 bytes
    bne pld_bad
    lda fsTMP
    cmp #48
    bne pld_bad
    lda #0
    sta fsSX
pld_loop:
    lda #8
    jsr fo_read
    lda fsSX
    ldx #>REU_PAL64
    jsr reu_put
    inc fsSX
    lda fsSX
    cmp #6
    bne pld_loop
    jsr fs_close_tgt
    jmp pl_show
pld_bad:
    jsr fs_close_tgt
    brk
    dta 186, 'Bad palette file', 0

; VPL: parsed into REU_PALTMP, copied to REU_PAL64 when 16 colours came.
; Variables: arg_word's, free after the command line is read.
vp_val      = aw_c              ; value of the hex number being read
vp_i        = aw_i              ; index in the chunk
vp_len      = aw_start_y        ; chunk length
vp_flags    = fsMODE            ; 1: in a comment, 2: digits in vp_val
pld_vpl:
    lda fsTMP                   ; fsBLK = bytes still to read
    sta fsBLK
    lda fsTMP+1
    sta fsBLK+1
    lda #0
    sta fsSX                    ; colour
    sta fsSY                    ; field in the line
    sta vp_val
    sta vp_flags
vp_chunk:
    lda fsBLK
    ora fsBLK+1
    beq vp_eof
    lda fsBLK+1                 ; next chunk: up to 8 bytes
    bne vp_8
    lda fsBLK
    cmp #8
    bcc vp_setn
vp_8:
    lda #8
vp_setn:
    sta vp_len
    jsr fo_read
    lda fsBLK
    sec
    sbc vp_len
    sta fsBLK
    bcs vp_nb
    dec fsBLK+1
vp_nb:
    lda #0
    sta vp_i
vp_char:
    ldx vp_i
    lda glyph,x
    jsr vp_parse
    inc vp_i
    lda vp_i
    cmp vp_len
    bne vp_char
    jmp vp_chunk
vp_eof:
    jsr fs_close_tgt
    lda #10                     ; a last line without a newline
    jsr vp_parse
    lda fsSX
    cmp #16
    bcc vp_bad
    ldx #>REU_PALTMP
    lda #<REU_PALTMP
    jsr pal_fromreu
    jmp pl_set
vp_bad:
    brk
    dta 186, 'Bad palette file', 0

; vp_parse: one character A of a .vpl file
vp_parse:
    cmp #13
    beq vp_eol
    cmp #10
    beq vp_eol
    tax
    lda vp_flags
    lsr
    bcs vp_rts                  ; in a comment
    txa
    cmp #'#'
    bne vp_hex
    jsr vp_token
    lda #1
    sta vp_flags
    rts
vp_hex:
    jsr toupper2
    cmp #'0'
    bcc vp_sep
    cmp #'9'+1
    bcc vp_digit
    cmp #'A'
    bcc vp_sep
    cmp #'F'+1
    bcs vp_sep
    sbc #'A'-10-1               ; (C = 0 here)
    bne vp_add
vp_digit:
    sbc #'0'-1                  ; (C = 0)
vp_add:
    asl vp_val
    asl vp_val
    asl vp_val
    asl vp_val
    ora vp_val
    sta vp_val
    lda #2
    sta vp_flags
    rts
vp_sep:
    jmp vp_token
vp_eol:
    jsr vp_token
    lda #0
    sta vp_flags
    lda fsSY                    ; a line with R, G, B: next colour
    cmp #3
    bcc vp_noline
    inc fsSX
vp_noline:
    lda #0
    sta fsSY
vp_rts:
    rts

; vp_token: end of a token: field fsSY of colour fsSX = vp_val (fields
; 0-2 of colours 0-15; the dither field and anything after are ignored)
vp_token:
    lda vp_flags
    and #2
    beq vt_none
    lda fsSX
    cmp #16
    bcs vt_skip
    lda fsSY
    cmp #3
    bcs vt_skip
    php
    sei
    lda fsSX                    ; REU_PALTMP + 3 * colour + field
    sta fsCNT
    asl
    adc fsCNT
    adc fsSY
    adc #<REU_PALTMP
    sta REU_ADDR
    lda #>REU_PALTMP
    adc #0
    sta REU_ADDR+1
    lda #<vp_val
    sta REU_C64
    lda #>vp_val
    sta REU_C64+1
    lda #1
    jsr pr_len
    lda #REU_TO_REU
    sta REU_CMD
    plp
vt_skip:
    inc fsSY
vt_none:
    lda #0
    sta vp_val
    lda vp_flags
    and #1
    sta vp_flags
    rts

; toupper2: a-z to A-Z
toupper2:
    cmp #'a'
    bcc tu2_done
    cmp #'z'+1
    bcs tu2_done
    and #$DF
tu2_done:
    rts

; BBC colours 0-15 as RGB; the flashing colours 8-15 show their first
; colour (no flashing yet)
bbcrgb:
    dta $00,$00,$00, $FF,$00,$00, $00,$FF,$00, $FF,$FF,$00
    dta $00,$00,$FF, $FF,$00,$FF, $00,$FF,$FF, $FF,$FF,$FF
    dta $00,$00,$00, $FF,$00,$00, $00,$FF,$00, $FF,$FF,$00
    dta $00,$00,$FF, $FF,$00,$FF, $00,$FF,$FF, $FF,$FF,$FF
