; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- Upic Lite palette through the Ultimate (bank 2)
;
; Control target commands (firmware 3.15+), as ultimate-uci-oscar64's
; uii_setpalette / uii_resetpalette: $04 $52 + 48 bytes RGB, $04 $54.
;
; ----------------------------------------------------------------------------

CTRL_SETPAL   = $52
CTRL_RESETPAL = $54

; ul_setpal
;   Summary: send the Upic Lite palette: entry i shows the BBC colour
;            pal[i AND cmask] (cmask 1 or 3): the renderer writes shifted
;            picture bytes to $D020, and the palette decodes the low bits.
;   Input:   pal[], vmode_cmask.  Output: C = 1 if the Ultimate refused.
;   Uses:    A, X, Y, fs*, errbuf.
ul_setpal:
    ldx #0                      ; palette index
    ldy #0                      ; byte in errbuf+1
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
    sta errbuf+1,y
    lda bbcrgb+1,x
    sta errbuf+2,y
    lda bbcrgb+2,x
    sta errbuf+3,y
    iny
    iny
    iny
    ldx fsCNT
    inx
    cpx #16
    bne usp_loop
    lda #<[errbuf+1]
    sta fsPTR
    lda #>[errbuf+1]
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

; ul_palreset: the Ultimate's default palette. Output: C = 1 if refused
; (no UCI, or firmware without palette commands); used at start-up to
; decide whether Upic Lite is possible.
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

; BBC colours 0-15 as RGB; the flashing colours 8-15 show their first
; colour (no flashing yet)
bbcrgb:
    dta $00,$00,$00, $FF,$00,$00, $00,$FF,$00, $FF,$FF,$00
    dta $00,$00,$FF, $FF,$00,$FF, $00,$FF,$FF, $FF,$FF,$FF
    dta $00,$00,$00, $FF,$00,$00, $00,$FF,$00, $FF,$FF,$00
    dta $00,$00,$FF, $FF,$00,$FF, $00,$FF,$FF, $FF,$FF,$FF
