; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- Upic full: the engine's REU and console stub (RAM image)
;
; Assembled for UP_STUB ($E000), stored in bank 8, copied there when MODE
; 110 or 111 starts (the console is a text screen: $E000-$EFFF is free).
; The drawing engine lives under I/O ($D000) and runs with $01 = $34; it
; calls these entries to reach the REU (the picture, UPIC_BANK) and the
; colour RAM, which need I/O: each switches $01 to $35 (I/O in, KERNAL
; out: this code stays visible) and back to $34. Interrupts are off (the
; engine's caller); every transfer sets all REU registers and leaves the
; address control at 0 (the sound interrupt's assumption).
;
; ----------------------------------------------------------------------------

    jmp us_rd                   ; +0  A = picture byte at page gzp+1, gzp
    jmp us_wr                   ; +3  picture byte = A
    jmp us_fill                 ; +6  US_N bytes (0 = 256) from gzp+1:gzp = A
    jmp us_get                  ; +9  US_N bytes -> UP_BUF + gzp
    jmp us_put                  ; +12 UP_BUF + gzp -> US_N bytes
    jmp us_scroll               ; +15 console: the text window up a row
    jmp us_clrow                ; +18 console: row A of the window cleared
    jmp us_fillall              ; +21 the whole picture = A

; ----------------------------------------------------------------------------
; us_rd / us_wr
;   Summary: read or write one picture byte (REU UPIC_BANK, page gzp+1,
;            offset gzp).
;   Input:   gzp; us_wr: A.  Output: us_rd: A.  Uses: A.
us_rd:
    lda #$35
    sta $01
    jsr us_one
    lda #$91                    ; REU -> C64
    sta $DF01
    lda #$34
    sta $01
    lda US_BYTE
    rts
us_wr:
    sta US_BYTE
    lda #$35
    sta $01
    jsr us_dirty
    jsr us_one
    lda #$90                    ; C64 -> REU
    sta $DF01
    lda #$34
    sta $01
    rts
; us_one: C64 = US_BYTE, REU = the picture byte, 1 byte
us_one:
    lda #<US_BYTE
    sta $DF02
    lda #>US_BYTE
    sta $DF03
    jsr us_reu
    lda #1
    sta $DF07
    lda #0
    sta $DF08
    sta $DF0A
    rts
; us_reu: the REU address: UPIC_BANK, page gzp+1, offset gzp
us_reu:
    lda gzp
    sta $DF04
    lda gzp+1
    sta $DF05
    lda #UPIC_BANK
    sta $DF06
    rts
; us_len: length US_N (0 = 256)
us_len:
    lda US_N
    sta $DF07
    cmp #1                      ; C = 1 unless 0
    lda #0
    bcs usl_hi
    lda #1
usl_hi:
    sta $DF08
    rts

; ----------------------------------------------------------------------------
; us_fill: US_N bytes of the column from gzp+1:gzp set to A (DMA from one
; byte: the C64 address fixed)
us_fill:
    sta US_BYTE
    lda #$35
    sta $01
    jsr us_dirty
    lda #<US_BYTE
    sta $DF02
    lda #>US_BYTE
    sta $DF03
    jsr us_reu
    jsr us_len
    lda #$80
    sta $DF0A
    lda #$90
    sta $DF01
    lda #0
    sta $DF0A
    lda #$34
    sta $01
    rts

; us_fillall: the whole bitmap (UPIC_BANK:0100, 48K) set to A
us_fillall:
    sta US_BYTE
    lda #$35
    sta $01
    jsr us_dirty
    lda #<US_BYTE
    sta $DF02
    lda #>US_BYTE
    sta $DF03
    lda #0
    sta $DF04
    sta $DF07
    lda #1
    sta $DF05
    lda #UPIC_BANK
    sta $DF06
    lda #$C0
    sta $DF08
    lda #$80
    sta $DF0A
    lda #$90
    sta $DF01
    lda #0
    sta $DF0A
    lda #$34
    sta $01
    rts

; us_get / us_put: US_N bytes between the column (gzp+1:gzp) and UP_BUF
; + gzp (the same rows in the buffer)
us_get:
    lda #$91
    bne usg_go
us_put:
    jsr us_dirty
    lda #$90
usg_go:
    pha
    lda #$35
    sta $01
    lda gzp
    sta $DF02
    lda #>UP_BUF
    sta $DF03
    jsr us_reu
    jsr us_len
    lda #0
    sta $DF0A
    pla
    sta $DF01
    lda #$34
    sta $01
    rts

; us_dirty: the picture has changed (auto-show, upic.s). Uses: nothing
us_dirty:
    pha
    lda UP_DIRTY
    ora #1
    sta UP_DIRTY
    pla
    rts

; ----------------------------------------------------------------------------
; us_scroll
;   Summary: the console's text window (twl..twr, twt..twb) up one row:
;            characters and colours, then the bottom row cleared.
;   Uses:    A, X, Y.
us_scroll:
    lda #$35
    sta $01
    ldx twt
uss_row:
    cpx twb
    bcs uss_last
    lda rowlo,x                 ; destination row X, source row X + 1
    sta uss_d1+1
    sta uss_d2+1
    lda rowhi,x
    sta uss_d1+2
    clc
    adc #>[$D800-SCREEN]
    sta uss_d2+2
    lda rowlo+1,x
    sta uss_s1+1
    sta uss_s2+1
    lda rowhi+1,x
    sta uss_s1+2
    clc
    adc #>[$D800-SCREEN]
    sta uss_s2+2
    ldy twl
uss_col:
uss_s1:
    lda $FFFF,y
uss_d1:
    sta $FFFF,y
uss_s2:
    lda $FFFF,y
uss_d2:
    sta $FFFF,y
    cpy twr
    beq uss_next
    iny
    bne uss_col
uss_next:
    inx
    bne uss_row
uss_last:
    txa                         ; the bottom row (I/O is in already)
    jmp usc_go

; us_clrow: row A of the text window: spaces in the text colour
us_clrow:
    pha
    lda #$35
    sta $01
    pla
usc_go:
    tax
    lda rowlo,x
    sta usc_s+1
    sta usc_c+1
    lda rowhi,x
    sta usc_s+2
    clc
    adc #>[$D800-SCREEN]
    sta usc_c+2
    ldx tfg
    lda bbc2c64,x
    tax
    ldy twl
usc_loop:
    lda #' '
usc_s:
    sta $FFFF,y
    txa
usc_c:
    sta $FFFF,y
    cpy twr
    beq usc_done
    iny
    bne usc_loop
usc_done:
    lda #$34
    sta $01
    rts

rowlo:
    :25 dta l(SCREEN+#*40)
rowhi:
    :25 dta h(SCREEN+#*40)
