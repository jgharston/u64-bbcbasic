; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the PETSCII mode: *PETSCII, *ASCII, *SEQ (bank 6)
;
; Owner's decisions of 2026-10-16 (PLAN.md): in the full PETSCII mode
; OSWRCH sends bytes to the KERNAL as on a C64 (core.s wr_pet): colour,
; reverse, cursor and case codes act, PETSCII wins over BBC's VDU codes;
; CR starts a new line, LF does nothing, VDU 22 (MODE) and 23 stay BBC's,
; and typed lines are echoed the BBC way (the line editor). GET and
; INKEY give PETSCII codes (mos.s). The ASCII modes are unchanged.
;
; The font: the C64's character ROM, its upper case/graphics set at FONT
; ($F000) and its lower/upper case set at $F800, so that the KERNAL's own
; case switch (codes 14 and 142: $D018 bit 1) works unchanged; the six
; bytes at $FFFA stay (RAM vectors). The mode ends with *ASCII, MODE or
; an error (core.s pet_brkv on BRKV), each restoring the ASCII font from
; its REU copy (so the mode needs an REU).
;
; ----------------------------------------------------------------------------

    .local pet

; ----------------------------------------------------------------------------
; cmd_petscii
;   Summary: *PETSCII: the full PETSCII mode on (text modes).
;   Input:   mosPTR/Y.  Output: pet_on, the font, BRKV.
;   Uses:    A, X, Y, glyph, mosTMP, mosPTR2.
cmd_petscii:
    jsr s6_end
pt_enter:
    lda pet_on
    beq pt_off
    rts
pt_off:
    lda vtype                   ; the text screen only
    beq pt_text
    brk
    dta 254, 'PETSCII: text modes only (MODE 100)', 0
pt_text:
    jsr s6_hasreu
    bne pt_reu
    brk
    dta 254, 'PETSCII needs an REU', 0
pt_reu:
    lda #>$D000                 ; the ROM's upper case/graphics set
    ldx #>FONT
    jsr pt_copy
    lda #>$D800                 ; its lower/upper case set
    ldx #>[FONT+$800]
    jsr pt_copy
    php
    sei
    lda $D018                   ; upper case/graphics, as a C64 starts
    and #$FD
    sta $D018
    lda BRKV+1                  ; errors end the mode (pet_brkv); not
    cmp #>pet_brkv              ; when it is already there
    bne pt_hook
    lda BRKV
    cmp #<pet_brkv
    beq pt_hooked
pt_hook:
    lda BRKV
    sta pet_obrk
    lda BRKV+1
    sta pet_obrk+1
    lda #<pet_brkv
    sta BRKV
    lda #>pet_brkv
    sta BRKV+1
pt_hooked:
    lda #1
    sta pet_on
    plp
    farcall wk_hide, BANK_MOS   ; no cursor blink while a program runs, as
pt_rts:                         ; on a C64 (MODE 100 starts it, BBC-style:
    rts                         ; a blink as the cursor moves on stays as a
                                ; reverse cell; GET shows it while waiting)

; pt_copy: the 256 glyphs of the character ROM page A ($D0 or $D8) to the
; RAM page X ($F0 or $F8; under the KERNAL, where writes go to RAM),
; through glyph_scr (core.s: reads the ROM with $01 = $33). Not the six
; bytes from $FFFA (RAM vectors).  Uses: A, X, Y, mosTMP, mosPTR2.
pt_copy:
    sta mosTMP+1                ; ROM page
    stx mosPTR2+1
    lda #0
    sta mosPTR2
    sta mosTMP                  ; screen code
ptc_l:
    lda mosTMP
    ldx mosTMP+1
    ldy #$33
    jsr glyph_scr
    ldy #7
ptc_b:
    lda mosPTR2+1               ; (not $FFFA-$FFFF)
    cmp #$FF
    bne ptc_w
    cpy #2
    bcc ptc_w
    lda mosPTR2
    cmp #$F8
    beq ptc_n
ptc_w:
    lda glyph,y
    sta (mosPTR2),y
ptc_n:
    dey
    bpl ptc_b
    lda mosPTR2
    clc
    adc #8
    sta mosPTR2
    bcc ptc_nx
    inc mosPTR2+1
ptc_nx:
    inc mosTMP
    bne ptc_l
    rts

; ----------------------------------------------------------------------------
; cmd_ascii
;   Summary: *ASCII: back from the PETSCII mode (nothing if it is off).
;   Uses:    A (pet_brk, core.s).
cmd_ascii:
    jsr s6_end
    jmp pet_brk

; ----------------------------------------------------------------------------
; cmd_seq
;   Summary: *SEQ file [LOWER|UPPER]: a PETSCII .seq file on the text
;            screen.
;   Function: opens the file (OSFIND, any filing system), switches the
;            PETSCII mode on unless it is on, clears the screen (2026-10-
;            16: .seq screens from Petmate or the VDC Screen Editor start
;            without a clear and rely on the 40-column wrap), sets the
;            character set when a word asks for one (lower case screens
;            carry no CHR$14 either), sends each byte to the KERNAL as it
;            is (OSBGET), stops at the end or on ESCAPE, then waits for a
;            key; a mode it switched on ends again, with a clear screen.
;   Input:   mosPTR/Y: the file name.  Output: the screen.
;   Uses:    A, X, Y, mosTMP, mosPTR2, mosARGS, glyph.
cmd_seq:
    jsr s6_name                 ; fsPTR: the name (ended by CR or space)
    lda #0                      ; the character set: 0 as it is, else the
    sta mosARGS+2               ; code (14 lower case, 142 upper case)
    lda #<cw_lower
    ldx #>cw_lower
    jsr s6_word
    bcc cq_nlow
    lda #14
    sta mosARGS+2
cq_nlow:
    lda #<cw_upper
    ldx #>cw_upper
    jsr s6_word
    bcc cq_nup
    lda #142
    sta mosARGS+2
cq_nup:
    jsr s6_end
    ldx fsPTR                   ; OSFIND (fs_name measures it again)
    ldy fsPTR+1
    lda #$40
    jsr OSFIND
    cmp #0
    bne cq_open
    brk
    dta 214, 'File not found', 0
cq_open:
    sta mosARGS                 ; the handle
    lda pet_on                  ; was the mode on?
    sta mosARGS+1
    jsr pt_enter
    lda #147                    ; a clear screen, the set asked for
    jsr K_CHROUT
    lda mosARGS+2
    beq cq_loop
    jsr K_CHROUT
cq_loop:
    bit ESCFLG
    bmi cq_esc
    ldy mosARGS
    jsr OSBGET
    bcs cq_end
    jsr K_CHROUT
    jmp cq_loop
cq_esc:
    lda #$7E                    ; acknowledge ESCAPE
    jsr OSBYTE
cq_end:
    lda #0
    ldy mosARGS
    jsr OSFIND
    jsr OSRDCH                  ; a key (ESCAPE too) ends the view
    bcc cq_key
    lda #$7E
    jsr OSBYTE
cq_key:
    lda mosARGS+1
    bne cq_rts
    jsr pet_brk                 ; the mode was off: off again, cleared
    lda #12
    jmp OSWRCH
cq_rts:
    rts

cw_lower    dta 'LOWER', 0
cw_upper    dta 'UPPER', 0

    .endl
