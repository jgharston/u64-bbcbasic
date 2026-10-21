; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- REU data storage for programs (bank 2)
;
; As the BBC Master's sideways RAM commands (*SRWRITE, *SRREAD, OSWORD
; &42), with the REU in the place of sideways RAM: a program keeps its
; code in BASIC's memory and megabytes of data (tables, levels, text,
; pictures) in the REU, copied by DMA.
;
; REU addresses are 24 bits. Banks 0-3 ($000000-$03FFFF) are the MOS's
; (fonts, palettes, instruments, songs); programs use $040000 up to the
; REU's size. C64 memory: OSHWM (PAGE) to $7FFF, BASIC's memory.
;
; ----------------------------------------------------------------------------

SR_LOW      = $04               ; first REU bank programs may use

; ----------------------------------------------------------------------------
; cmd_srwrite / cmd_srread
;   Summary: *SRWRITE <start> <end>|+<length> <REU address>: C64 memory
;            to the REU; *SRREAD <start> <end>|+<length> <REU address>:
;            the REU to C64 memory at start.
;   Function: numbers decimal or &hex; the REU address up to 24 bits.
;   Input:   mosPTR/Y.  Output: raises on errors.
;   Uses:    A, X, Y, fs*, mosNUM.
cmd_srwrite:
    lda #REU_TO_REU
    bne sr_cmd
cmd_srread:
    lda #REU_TO_C64
sr_cmd:
    sta fsMODE
    jsr arg_need                ; start
    lda mosNUM
    sta fsADDR
    lda mosNUM+1
    sta fsADDR+1
    jsr ci_skipsp               ; +length or end
    cmp #'+'
    bne sr_end
    iny
    jsr arg_need
    lda mosNUM
    sta fsLEN
    lda mosNUM+1
    sta fsLEN+1
    jmp sr_reu
sr_end:
    jsr arg_need
    lda mosNUM                  ; length = end - start
    sec
    sbc fsADDR
    sta fsLEN
    lda mosNUM+1
    sbc fsADDR+1
    sta fsLEN+1
    bcs sr_reu
    jmp sr_bad
sr_reu:
    jsr sr_num24                ; REU address -> fsTMP (3 bytes)
    bcc sr_line
    jmp an_syntax
sr_line:
    jsr ff_end                  ; nothing may follow
    jmp sr_copy

; ----------------------------------------------------------------------------
; sr_word (OSWORD &42, as the BBC Master's sideways RAM transfer)
;   Summary: copy between C64 memory and the REU for a program.
;   Function: block +0 bit 7: 1 = C64 memory to the REU, 0 = the REU to
;            C64 memory (bit 6, absolute/pseudo addressing on the Master,
;            is ignored: always absolute); +1..+2 C64 address (+3..+4,
;            the high word, ignored); +5..+6 length; +7 the REU's 64K bank
;            (the Master's ROM number); +8..+9 the address in that bank.
;   Input:   mosPTR = block.  Output: raises on errors.
;   Uses:    A, X, Y, fs*.
sr_word:
    ldy #0
    lda (mosPTR),y
    and #$80
    beq sw_read
    lda #REU_TO_REU
    bne sw_dir
sw_read:
    lda #REU_TO_C64
sw_dir:
    sta fsMODE
    ldy #1
    lda (mosPTR),y
    sta fsADDR
    iny
    lda (mosPTR),y
    sta fsADDR+1
    ldy #5
    lda (mosPTR),y
    sta fsLEN
    iny
    lda (mosPTR),y
    sta fsLEN+1
    ldy #8
    lda (mosPTR),y
    sta fsTMP
    iny
    lda (mosPTR),y
    sta fsTMP+1
    ldy #7
    lda (mosPTR),y
    sta fsTMP+2
    ; (fall through)

; ----------------------------------------------------------------------------
; sr_copy
;   Summary: check and do the transfer: fsMODE = REU command (REU_TO_REU
;            C64 -> REU, REU_TO_C64 REU -> C64), fsADDR = C64 address,
;            fsLEN = length (1-32K), fsTMP = REU address (24 bits).
;   Function: the C64 range must lie in OSHWM-$7FFF, the REU range in
;            bank SR_LOW up to the REU's size; one DMA.
;   Uses:    A, X, Y.
sr_copy:
    jsr has_reu
    bne src_reu
    brk
    dta 189, 'No REU', 0
src_reu:
    lda fsLEN                   ; length 1 or more
    ora fsLEN+1
    bne src_len
    jmp sr_bad
src_len:
    jsr lo_page                 ; C64: the lowest PAGE <= start, start +
    sta fsCNT                   ; length <= $8000
    lda fsADDR+1
    cmp fsCNT
    bcs src_low
    jmp sr_bad
src_low:
    lda fsADDR
    clc
    adc fsLEN
    lda fsADDR+1
    adc fsLEN+1
    bcs sr_bad
    cmp #$80
    bcc src_c64ok
    bne sr_bad
    lda fsADDR                  ; exactly $8000 is the end: fine
    clc
    adc fsLEN
    bne sr_bad
src_c64ok:
    lda fsTMP+2                 ; REU: bank >= SR_LOW, end within the REU
    cmp #SR_LOW
    bcc sr_bad
    lda fsTMP                   ; end = address + length (24 bits)
    clc
    adc fsLEN
    sta fsCNT
    lda fsTMP+1
    adc fsLEN+1
    sta fsCNT+1
    lda fsTMP+2
    adc #0                      ; end bank (with carry); compare with the
    tax                         ; REU's banks (reu_banks, 16 bits)
    lda fsCNT                   ; an end exactly on a bank boundary
    ora fsCNT+1                 ; belongs to the bank before
    bne src_cmp
    dex
src_cmp:
    cpx #UPIC_BANK-1+1          ; not into Upic (&90000-&AFFFF, upic.s) or
    bcs sr_bad                  ; the snapshot slots (&B0000-&FFFFF)
    lda reu_banks+1             ; 256 banks or more (16M): every bank
    bne src_go
    cpx reu_banks
    bcs sr_bad
src_go:
    php                         ; (interrupts off while the REU is set up:
    sei                         ; the sound interrupt uses it too)
    lda fsADDR
    sta REU_C64
    lda fsADDR+1
    sta REU_C64+1
    lda fsTMP
    sta REU_ADDR
    lda fsTMP+1
    sta REU_ADDR+1
    lda fsTMP+2
    sta REU_BANK
    lda fsLEN
    sta REU_LEN
    lda fsLEN+1
    sta REU_LEN+1
    lda #0
    sta REU_CTRL
    lda fsMODE
    sta REU_CMD
    plp
    rts
sr_bad:
    brk
    dta 212, 'Bad address', 0

; ----------------------------------------------------------------------------
; sr_num24: a number of up to 24 bits at mosPTR/Y (decimal or &hex) into
; fsTMP (3 bytes). C = 1 if there is none.  Uses: A, X, Y.
sr_num24:
    jsr ci_skipsp
    lda #0
    sta fsTMP
    sta fsTMP+1
    sta fsTMP+2
    lda (mosPTR),y
    cmp #'&'
    beq r24_hex
    jsr r24_dec
    bcs r24_none
r24_decl:
    lda (mosPTR),y              ; fsTMP = fsTMP * 10 + digit
    jsr r24_dec
    bcs r24_done
    pha
    jsr r24_x2                   ; * 2
    lda fsTMP                   ; keep * 2
    sta fsCNT
    lda fsTMP+1
    sta fsCNT+1
    lda fsTMP+2
    sta fsTMP+3
    jsr r24_x2                   ; * 8
    jsr r24_x2
    lda fsTMP                   ; * 8 + * 2
    clc
    adc fsCNT
    sta fsTMP
    lda fsTMP+1
    adc fsCNT+1
    sta fsTMP+1
    lda fsTMP+2
    adc fsTMP+3
    sta fsTMP+2
    pla
    jsr r24_add
    iny
    bne r24_decl
r24_hex:
    iny
    lda (mosPTR),y
    jsr r24_hexd
    bcs r24_none
r24_hexl:
    lda (mosPTR),y
    jsr r24_hexd
    bcs r24_done
    pha
    jsr r24_x2
    jsr r24_x2
    jsr r24_x2
    jsr r24_x2
    pla
    jsr r24_add
    iny
    bne r24_hexl
r24_done:
    clc
    rts
r24_none:
    sec
    rts
; r24_x2: fsTMP * 2 (24 bits)
r24_x2:
    asl fsTMP
    rol fsTMP+1
    rol fsTMP+2
    rts
; r24_add: fsTMP + A
r24_add:
    clc
    adc fsTMP
    sta fsTMP
    bcc r24a_rts
    inc fsTMP+1
    bne r24a_rts
    inc fsTMP+2
r24a_rts:
    rts
; r24_dec: A = digit value of a decimal digit (C = 0), else C = 1
r24_dec:
    cmp #'0'
    bcc r24d_no
    cmp #'9'+1
    bcs r24d_no
    sbc #'0'-1
    clc
    rts
r24d_no:
    sec
    rts
; r24_hexd: A = value of a hex digit 0-9, A-F (also a-f) (C = 0)
r24_hexd:
    jsr r24_dec
    bcc r24h_rts
    jsr up2
    cmp #'A'
    bcc r24d_no
    cmp #'F'+1
    bcs r24d_no
    sbc #'A'-10-1
    clc
r24h_rts:
    rts

; ----------------------------------------------------------------------------
; ru_saveop (*REUSAVE, reucmd.s, bank 6): SAVE_REU (&22) on the file just
; opened (rx_create): REU address MOSBUF+$E0 (3 bytes), length +$E4 (3);
; raises the Ultimate's error (the file closed).  Uses: A, X, Y, fs*.
ru_saveop:
    lda #0
    sta MOSBUF+$E3
    sta MOSBUF+$E7
    lda #$22
    jsr fs_hdr2
    lda #<[MOSBUF+$E0]
    sta fsPTR
    lda #>[MOSBUF+$E0]
    sta fsPTR+1
    lda #8
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_send
    jsr uci_finish
    bcc rsop_rts
    jsr fs_saveerr              ; (closes the file, raises the status)
    jmp uci_error
rsop_rts:
    rts

; ctl_cmd (*REU SAVE / LOAD, reucmd.s): control command A, no payload;
; raises the Ultimate's error.  Uses: A, X, Y, fs*.
ctl_cmd:
    pha
    jsr uci_need
    lda #TARGET_CTRL
    sta fsTGT
    pla
    jsr fs_hdr2
    jmp uci_cmd

; ----------------------------------------------------------------------------
; rs_clock (rnd_seed, rndseed.s, bank 5)
;   Summary: the Ultimate clock's text ("YYYY/MM/DD HH:MM:SS") into MOSBUF.
;   Input:   none.  Output: fsCNT = its length (0 without the Ultimate).
;   Uses:    A, X, Y, fs*.
rs_clock:
    lda #0
    sta fsCNT
    lda uci_ok
    beq rsc_rts
    lda #TARGET_DOS1
    sta fsTGT
    lda #DOS_TIME
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #32
    sta fsLEN
    jsr uci_read_to
    jsr uci_finish
rsc_rts:
    rts

