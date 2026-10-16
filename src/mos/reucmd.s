; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- REU files and the REU preload image (batch B, bank 6):
; *REULOAD, *REUSAVE, *REU SAVE|LOAD
;
; Owner's decisions of 2026-10-16 (PLAN.md 27 item 4): *REULOAD/*REUSAVE
; in the program area only (&40000-&8FFFF, as *SRWRITE/*SRREAD; *REULOAD
; at &40000 when no address is given); the Ultimate's REU preload image
; (control &08/&09) as *REU SAVE / *REU LOAD, for keeping the /REU RAM
; disk and REU data over a power-off, LOAD asking first. The file work is
; bank 2's (fs_reuopen0, fs_reurest3, rx_create, ru_saveop, rx_close,
; ctl_cmd), called through the trampoline.
;
; ----------------------------------------------------------------------------

RU_A        = MOSBUF+$E8        ; 3: the REU address
RU_L        = MOSBUF+$EB        ; 2: the length or room (FR_LENH: its top)

; ----------------------------------------------------------------------------
; cmd_reuload
;   Summary: *REULOAD file [addr]: a file into the REU at addr (&40000 if
;            left out), at most up to &8FFFF (more is not loaded); one
;            LOAD_REU command, the bytes never pass C64 memory.
;   Input:   mosPTR/Y.  Output: the REU; raises on errors.
;   Uses:    A, X, Y, fs*, MOSBUF+$E0-$EF.
cmd_reuload:
    jsr s6_name
    jsr ru_notreu
    lda #0                      ; &40000 unless given
    sta fsTMP
    sta fsTMP+1
    lda #SR_LOW
    sta fsTMP+2
    jsr s6_skipsp
    cmp #13
    beq rul_addr
    farcall sr_num24, BANK_FS
    bcs ru_syn
    jsr s6_end
rul_addr:
    jsr ru_save                 ; RU_A; room = &90000 - addr
    lda #0
    sec
    sbc RU_A
    sta RU_L
    lda #0
    sbc RU_A+1
    sta RU_L+1
    lda #UPIC_BANK
    sbc RU_A+2
    sta FR_LENH
    farcall fs_reuopen0, BANK_FS
    jsr ru_load                 ; fsTMP = RU_A, fsCNT = room
    farcall fs_reurest3, BANK_FS
    rts
ru_syn:
    jmp s6_syntax

; ----------------------------------------------------------------------------
; cmd_reusave
;   Summary: *REUSAVE file addr len: len bytes (24 bits) of the REU from
;            addr to a file (created or replaced); addr to addr+len within
;            &40000-&8FFFF; one SAVE_REU command.
;   Input:   mosPTR/Y.  Output: the file; raises on errors.
;   Uses:    A, X, Y, fs*, MOSBUF+$E0-$EF.
cmd_reusave:
    jsr s6_name
    jsr ru_notreu
    farcall sr_num24, BANK_FS   ; addr
    bcs ru_syn
    jsr ru_save
    farcall sr_num24, BANK_FS   ; len
    bcs ru_syn
    jsr s6_end
    lda fsTMP
    sta RU_L
    lda fsTMP+1
    sta RU_L+1
    lda fsTMP+2
    sta FR_LENH
    ora fsTMP+1                 ; at least 1
    ora fsTMP
    bne rus_len
    jmp ru_bad
rus_len:
    lda RU_A                    ; the end within &90000
    clc
    adc RU_L
    sta fsCNT
    lda RU_A+1
    adc RU_L+1
    sta fsCNT+1
    lda RU_A+2
    adc FR_LENH
    bcs ru_bad
    cmp #UPIC_BANK
    bcc rus_ok
    bne ru_bad
    lda fsCNT                   ; (exactly &90000: fine)
    ora fsCNT+1
    bne ru_bad
rus_ok:
    farcall rx_create, BANK_FS
    ldx #2                      ; SAVE_REU's address and length
rus_a:
    lda RU_A,x
    sta MOSBUF+$E0,x
    dex
    bpl rus_a
    lda RU_L
    sta MOSBUF+$E4
    lda RU_L+1
    sta MOSBUF+$E5
    lda FR_LENH
    sta MOSBUF+$E6
    farcall ru_saveop, BANK_FS
    farcall rx_close, BANK_FS
    rts
ru_bad:
    brk
    dta 212, 'Bad address (&40000-&8FFFF)', 0

; ru_save: RU_A = fsTMP (bank SR_LOW up to below UPIC_BANK, else "Bad
; address"); ru_load: fsTMP = RU_A, fsCNT = RU_L
ru_save:
    lda fsTMP+2
    cmp #SR_LOW
    bcc ru_bad
    cmp #UPIC_BANK
    bcs ru_bad
    ldx #2
rsv_c:
    lda fsTMP,x
    sta RU_A,x
    dex
    bpl rsv_c
    rts
ru_load:
    ldx #2
rld_c:
    lda RU_A,x
    sta fsTMP,x
    dex
    bpl rld_c
    lda RU_L
    sta fsCNT
    lda RU_L+1
    sta fsCNT+1
    rts

; ru_notreu: "Not on /REU" for the name at fsPTR (the RAM disk's code uses
; MOSBUF's top too; the REU to itself is *SRWRITE/*SRREAD's)
ru_notreu:
    tya                         ; (Y: the place on the line)
    pha
    farcall rd_route, BANK_FS
    pla
    tay
    bcc rnr_rts
    brk
    dta 214, 'Not on /REU', 0
rnr_rts:
    rts

; ----------------------------------------------------------------------------
; cmd_reu
;   Summary: *REU SAVE: the whole REU to the Ultimate's REU preload image
;            (the file set in its menu, control &09): keeps the /REU RAM
;            disk and REU data over a power-off; *REU LOAD [Y]: back
;            (control &08; asks first unless Y, as everything in the REU
;            is replaced), then the RAM disk read again.
;   Input:   mosPTR/Y.  Uses: A, X, Y, fs*.
cmd_reu:
    lda #<rw_save
    ldx #>rw_save
    jsr s6_word
    bcc cr_load
    jsr s6_end
    lda #$09
    farcall ctl_cmd, BANK_FS
    rts
cr_load:
    lda #<rw_load
    ldx #>rw_load
    jsr s6_word
    bcs crl_ask
    jmp s6_syntax
crl_ask:
    lda #<rw_y
    ldx #>rw_y
    jsr s6_word
    php
    jsr s6_end
    plp
    bcs crl_go
    jsr s6_text
    dta 'Replace all of the REU, RAM disk too? (Y/N) ', 0
    jsr OSRDCH
    bcs crl_no
    and #$DF
    cmp #'Y'
    bne crl_no
    jsr OSWRCH
    jsr OSNEWL
crl_go:
    lda #$08
    farcall ctl_cmd, BANK_FS
    farcall rd_boot, BANK_RD    ; the RAM disk as it was saved
    rts
crl_no:
    jsr s6_text
    dta 'N', 13, 0
    lda #$7E
    jmp OSBYTE
rw_save     dta 'SAVE', 0
rw_load     dta 'LOAD', 0
rw_y        dta 'Y', 0
