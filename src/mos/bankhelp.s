; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- helpers for the banks above bank 2 (sound, network)
;
; Code in a cartridge bank cannot call bank 2's helpers directly when they
; read text from their caller's bank (keywords, inline messages): copies
; here. Those that only take registers go through farcall. Included at the
; top level by sndbank.s (labels s6_*) and inside .local net by netbank.s
; (net.s6_*).
;
; ----------------------------------------------------------------------------

; s6_word: as arg_word (batcha.s): C = 1 if the word at A/X (here) is next
; on the line (case does not matter, no letter may follow); Y past it
s6_word:
    sta mosPTR2
    stx mosPTR2+1
s6w_skip:
    lda (mosPTR),y
    cmp #' '
    bne s6w_start
    iny
    bne s6w_skip
s6w_start:
    sty aw_start_y
    lda #0
    sta aw_i
s6w_cmp:
    ldy aw_i
    lda (mosPTR2),y
    beq s6w_end
    sta aw_c
    tya
    clc
    adc aw_start_y
    tay
    lda (mosPTR),y
    jsr s6_up
    cmp aw_c
    bne s6w_no
    inc aw_i
    bne s6w_cmp
s6w_end:
    lda aw_i
    clc
    adc aw_start_y
    tay
    lda (mosPTR),y
    jsr s6_up
    cmp #'A'
    bcc s6w_yes
    cmp #'Z'+1
    bcc s6w_no
s6w_yes:
    sec
    rts
s6w_no:
    ldy aw_start_y
    clc
    rts

; s6_up: A in upper case (a-z only)
s6_up:
    cmp #'a'
    bcc s6u_rts
    cmp #'z'+1
    bcs s6u_rts
    and #$DF
s6u_rts:
    rts

; s6_num: as arg_number: the next number at mosPTR/Y into mosNUM (C = 1:
; none)
s6_num:
    farcall cli_number, BANK_MOS
    rts

; s6_need: s6_num, raising "Syntax" if there is none
s6_need:
    jsr s6_num
    bcs s6_syntax
    rts
s6_syntax:
    brk
    dta 220, 'Syntax', 0

; s6_skipsp: A = the next non-space character at mosPTR/Y
s6_skipsp:
    lda (mosPTR),y
    cmp #' '
    bne s6s_rts
    iny
    bne s6_skipsp
s6s_rts:
    rts

; s6_end: nothing else may follow on the line ("Syntax")
s6_end:
    jsr s6_skipsp
    cmp #13
    bne s6_syntax
    rts

; s6_signed: as sm_signed: [-]n, mosNUM = 0-255, mosNUM+1 = 1 if negative
; (C = 1: none, or over 255)
s6_signed:
    jsr s6_skipsp
    ldx #0
    cmp #'-'
    bne s6g_num
    iny
    inx
s6g_num:
    stx fsTMP
    jsr s6_num
    bcs s6g_rts
    lda mosNUM+1
    beq s6g_ok
    sec
    rts
s6g_ok:
    lda fsTMP
    sta mosNUM+1
    clc
s6g_rts:
    rts

; s6_name: as arg_name: the file name at mosPTR/Y -> fsPTR/fsLEN, Y past it
s6_name:
    farcall arg_name, BANK_FS
    rts

; s6_dec8 / s6_dec16: A / mosTMP in decimal
s6_dec8:
    farcall st_dec8, BANK_FS
    rts
s6_dec16:
    farcall st_dec16, BANK_FS
    rts

; s6_text: print the 0-terminated text after the JSR (as st_text)
s6_text:
    pla
    sta mosPTR2
    pla
    sta mosPTR2+1
    ldy #1
s6t_loop:
    lda (mosPTR2),y
    beq s6t_end
    jsr OSASCI
    iny
    bne s6t_loop
s6t_end:
    tya
    clc
    adc mosPTR2
    tax
    lda mosPTR2+1
    adc #0
    pha
    txa
    pha
    rts

; s6_hasreu: Z = 0 if there is an REU
s6_hasreu:
    lda reu_banks
    ora reu_banks+1
    rts

s6w_bbc     dta 'BBC', 0
s6w_off     dta 'OFF', 0
s6w_on      dta 'ON', 0
s6w_none    dta 'NONE', 0
s6w_default dta 'DEFAULT', 0
s6w_save    dta 'SAVE', 0
s6w_load    dta 'LOAD', 0

