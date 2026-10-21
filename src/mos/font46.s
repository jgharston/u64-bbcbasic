; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- MODE 1 on the VIC-II: the 4x6 font, bank 6
;
; Called by bank 3's MODE code (bk_mode0) at every mode change.
;
; ----------------------------------------------------------------------------
; fnt46
;   Summary: modes with 4-pixel cells get the 4x6 font, any other mode
;            the glyphs it had: MODE 1 on the VIC-II (40 readable
;            columns in its 160 double-wide pixels), MODE 0 and 3 (80
;            columns).
;   Function: with an REU: on entering, characters 32-126 of the REU font
;            (REU_FONT + 32 * 8, 760 bytes) go to REU_FONTSAVE and the 4x6
;            glyphs (font4x6, this bank) take their place; on leaving they
;            come back. FONT46 says which is in. Characters defined (VDU
;            23) while such a mode is on are lost when it ends.
;   Input:   vmode, vmode_ul.  Output: FONT46.  Uses: A, X, Y, fs*, MOSBUF.
fnt46:
    ldx #0                      ; wanted with 4-pixel cells: VIC-II MODE 1,
    lda vmode_cw                ; MODE 0 and 3 (VIC-II and Upic Lite)
    cmp #4
    bne f46_want
    inx
f46_want:
    cpx FONT46
    beq f46_rts
    lda reu_banks
    ora reu_banks+1
    beq f46_rts
    stx FONT46
    txa
    beq f46_back
    lda #REU_TO_C64             ; in: the glyphs aside, through MOSBUF
    sta f46_c1
    lda #REU_TO_REU
    sta f46_c2
    lda #<[REU_FONT+$100]
    sta f46_a1
    lda #<REU_FONTSAVE
    sta f46_a2
    lda #>[REU_FONT+$100]
    sta f46_h1
    lda #>REU_FONTSAVE
    sta f46_h2
    jsr f46_move
    lda #<font4x6               ; and the 4x6 font from this bank (8)
    sta fsADDR
    lda #>font4x6
    sta fsADDR+1
    ldy #<760
    sty fsLEN
    ldy #>760
    sty fsLEN+1
    lda #<[REU_FONT+$100]
    sta fsTMP
    lda #>[REU_FONT+$100]
    sta fsTMP+1
    lda #REU_TO_REU
    jmp f46_dma
f46_back:
    lda #REU_TO_C64             ; out: the glyphs back
    sta f46_c1
    lda #REU_TO_REU
    sta f46_c2
    lda #<REU_FONTSAVE
    sta f46_a1
    lda #<[REU_FONT+$100]
    sta f46_a2
    lda #>REU_FONTSAVE
    sta f46_h1
    lda #>[REU_FONT+$100]
    sta f46_h2
    jsr f46_move
f46_rts:
    rts
; f46_move: 760 bytes from REU f46_h1:a1 to f46_h2:a2, 128 at a time
; through MOSBUF+0-$7F (the REU cannot copy within itself; the move's
; variables and the line editor's state lie beyond)
f46_move:
    lda #0
    sta f46_n
f46_chunk:
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #128                    ; the last chunk: 760 - 5 * 128 = 120
    ldx f46_n
    cpx #5
    bne f46_len
    lda #120
f46_len:
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda f46_a1
    ldx f46_h1
    jsr f46_addr
    lda f46_c1
    jsr f46_dma
    lda f46_a2
    ldx f46_h2
    jsr f46_addr
    lda f46_c2
    jsr f46_dma
    inc f46_n
    lda f46_n
    cmp #6
    bcc f46_chunk
    rts
; f46_addr: fsTMP = A (low) / X (high) + f46_n * 128
f46_addr:
    stx fsTMP+1
    sta fsTMP
    lda f46_n
    lsr
    pha
    lda #0
    ror                         ; (n AND 1) * 128
    clc
    adc fsTMP
    sta fsTMP
    pla
    adc fsTMP+1
    sta fsTMP+1
    rts
; f46_dma: fsADDR (C64) <-> REU_FONT_BANK:fsTMP, fsLEN bytes, command A
; (interrupts off while it is set up: the sound interrupt uses the REU)
f46_dma:
    php
    sei
    pha
    lda fsADDR
    sta REU_C64
    lda fsADDR+1
    sta REU_C64+1
    lda fsTMP
    sta REU_ADDR
    lda fsTMP+1
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda fsLEN
    sta REU_LEN
    lda fsLEN+1
    sta REU_LEN+1
    lda #0
    sta REU_CTRL
    pla
    sta REU_CMD
    plp
    rts

    icl 'font4x6.s'

