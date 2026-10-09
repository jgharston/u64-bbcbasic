; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *SID: the SIDs found, and the Ultimate's audio mixer
; (bank 2)
;
; Mixer settings go through the firmware's "load config" control command
; (UCI $04 $50, firmware 3.15a+, 1541ultimate 2026-08-11): the MOS writes
; a two-line configuration file to the RAM disk and has the firmware
; load it; settings take effect at once and are not saved to flash. The
; firmware answers with an error status when it cannot apply a line.
;
; ----------------------------------------------------------------------------

CTRL_LOADCFG = $50

; ----------------------------------------------------------------------------
; cmd_sid
;   Summary: *SID: list the SIDs; *SID PAN <unit> <p>: stereo position;
;            *SID VOL <unit> <dB>|OFF: volume.
;   Function: unit 1 or 2 = UltiSID 1 or 2 (with the shipped .cfg the
;            SIDs at even positions in the list are UltiSID 1's, the odd
;            ones UltiSID 2's), S1 or S2 = the SID sockets. p = -5 (left)
;            to 5 (right), 0 = centre. dB = -42 to 6 in the firmware's
;            steps (-42 -36 -30 -27 -24 -18 then every dB), or OFF.
;   Input:   mosPTR/Y.  Output: text or the setting; raises on errors.
;   Uses:    A, X, Y, fs*, errbuf, MOSBUF, mosNUM.
cmd_sid:
    lda #<sw_pan
    ldx #>sw_pan
    jsr arg_word
    bcc cs_vol
    lda #0
    beq cs_set
cs_vol:
    lda #<sw_vol
    ldx #>sw_vol
    jsr arg_word
    bcc cs_list
    lda #1
cs_set:
    sta fsMODE                  ; 0 PAN, 1 VOL
    jmp sid_mixer

; *SID: "8 SIDs: &D400 &D420 ..."
cs_list:
    lda s_nsid
    jsr st_dec8
    jsr st_text
    dta ' SID', 0
    lda s_nsid
    cmp #2
    bcc cs_one
    lda #'s'
    jsr OSWRCH
cs_one:
    lda #':'
    jsr OSWRCH
    ldx #0
cs_addr:
    cpx s_nsid
    beq sl_end
    stx fsSX
    jsr st_text
    dta ' &', 0
    ldx fsSX
    lda s_sidhi,x
    pha
    lda s_sidlo,x
    tax
    pla
    jsr st_hex16
    ldx fsSX
    inx
    bne cs_addr
sl_end:
    jmp OSNEWL

sw_pan      dta 'PAN', 0
sw_vol      dta 'VOL', 0
sw_s1       dta 'S1', 0
sw_s2       dta 'S2', 0

; ----------------------------------------------------------------------------
; sid_mixer
;   Summary: *SID PAN/VOL: build "[Audio Mixer]", "<item>=<value>" in
;            MOSBUF, save it as /Temp/bbcmix.cfg, have the firmware load it.
;   Input:   fsMODE = 0 PAN, 1 VOL; mosPTR/Y at the unit.
;   Uses:    A, X, Y, fs*, errbuf, MOSBUF, mosNUM, osfblk.
sid_mixer:
    jsr uci_need
    lda #<sw_s1                 ; unit: S1, S2, 1 or 2 -> fsSY 0-3
    ldx #>sw_s1
    jsr arg_word
    bcc sm_s2
    lda #2
    bne sm_unit
sm_s2:
    lda #<sw_s2
    ldx #>sw_s2
    jsr arg_word
    bcc sm_num
    lda #3
    bne sm_unit
sm_num:
    jsr arg_number
    bcs sm_syn1
    lda mosNUM+1
    bne sm_syn1
    lda mosNUM
    sec
    sbc #1
    cmp #2
    bcc sm_unit
sm_syn1:
    jmp an_syntax
sm_unit:
    sta fsSY
    sty fsCNT                   ; line position (the text builder uses Y)
    ldx #0                      ; text in MOSBUF, X = length
    lda #<sm_head
    ldy #>sm_head
    jsr sm_str
    lda fsMODE                  ; item name: (Pan|Vol) (UltiSID|Socket) n
    bne sm_ivol
    lda #<sm_pan
    ldy #>sm_pan
    jsr sm_str
    lda fsSY
    and #2
    bne sm_isock
    lda #<sm_ulti
    ldy #>sm_ulti
    bne sm_iname
sm_ivol:
    lda #<sm_vol
    ldy #>sm_vol
    jsr sm_str
    lda fsSY
    and #2
    bne sm_isock
    lda #<sm_ultv               ; (the firmware spells it UltiSid here)
    ldy #>sm_ultv
    bne sm_iname
sm_isock:
    lda #<sm_sock
    ldy #>sm_sock
sm_iname:
    jsr sm_str
    lda fsSY
    and #1
    clc
    adc #'1'
    jsr sm_chr
    lda #'='
    jsr sm_chr
    stx fsSX                    ; (the value parsers use X)
    ldy fsCNT
    lda fsMODE
    bne sm_vval
    jsr sm_signed               ; pan: -5..5
    bcs sm_syntax
    ldx fsSX
    lda mosNUM
    bne sm_lr
    lda #<sm_ctr
    ldy #>sm_ctr
    jsr sm_str
    jmp sm_save
sm_lr:
    lda mosNUM+1                ; sign
    bne sm_left
    lda #<sm_right
    ldy #>sm_right
    bne sm_lr2
sm_left:
    lda #<sm_leftw
    ldy #>sm_leftw
sm_lr2:
    jsr sm_str
    lda mosNUM
    cmp #6
    bcs sm_syntax
    ora #'0'
    jsr sm_chr
    jmp sm_save
sm_syntax:
    jmp an_syntax
sm_vval:
    lda #<w_off                 ; volume: OFF or -42..6 dB
    ldx #>w_off
    jsr arg_word
    bcc sm_vnum
    ldx fsSX
    lda #<sm_offw
    ldy #>sm_offw
    jsr sm_str
    jmp sm_save
sm_vnum:
    jsr sm_signed
    bcs sm_syntax
    jsr sm_vstep                ; to the firmware's nearest step
    ldx fsSX
    lda mosNUM
    bne sm_vsign
    lda #' '                    ; " 0 dB"
    bne sm_vdig
sm_vsign:
    lda mosNUM+1
    beq sm_vplus
    lda #'-'
    bne sm_vdig
sm_vplus:
    lda #'+'
sm_vdig:
    jsr sm_chr
    lda mosNUM                  ; up to two digits
    ldy #0
sm_tens:
    cmp #10
    bcc sm_units
    sbc #10
    iny
    bne sm_tens
sm_units:
    pha
    tya
    beq sm_one
    ora #'0'
    jsr sm_chr
sm_one:
    pla
    ora #'0'
    jsr sm_chr
    lda #<sm_db
    ldy #>sm_db
    jsr sm_str

; save MOSBUF .. +X as the file, then load it
sm_save:
    lda #13                     ; CR LF: *TYPE shows the lines too
    jsr sm_chr
    lda #10
    jsr sm_chr
    txa                         ; OSFILE 0: start, end
    clc
    adc #<[MOSBUF]
    sta osfblk+14
    lda #>[MOSBUF]
    adc #0
    sta osfblk+15
    lda #<[MOSBUF]
    sta osfblk+10
    lda #>[MOSBUF]
    sta osfblk+11
    lda #<sm_fname
    sta osfblk
    lda #>sm_fname
    sta osfblk+1
    lda #0
    jsr osf_call
    lda #<[sm_file]             ; load config: path, 0 as the payload
    sta fsPTR
    lda #>[sm_file]
    sta fsPTR+1
    lda #sm_fend-sm_file
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #TARGET_CTRL
    sta fsTGT
    lda #CTRL_LOADCFG
    jsr fs_hdr2
    jsr uci_send
    jsr uci_finish
    bcc sm_done
    jmp uci_error
sm_done:
    rts

; sm_vstep: mosNUM (dB, sign in mosNUM+1) to the nearest volume the
; firmware has: -42 -36 -30 -27 -24 -18 .. +6 (above +6: +6)
sm_vstep:
    lda mosNUM+1
    bne smv_neg
    lda mosNUM
    cmp #7
    bcc smv_rts
    lda #6
    sta mosNUM
smv_rts:
    rts
smv_neg:
    lda mosNUM                  ; -1..-18: every dB
    cmp #19
    bcc smv_rts
    ldx #0
smv_find:
    lda mosNUM
    cmp smv_upto,x              ; magnitude <= the step's upper limit?
    bcc smv_set
    beq smv_set
    inx
    cpx #5
    bne smv_find
smv_set:
    lda smv_step,x
    sta mosNUM
    rts
smv_upto:
    dta 21, 25, 28, 33, 39
smv_step:
    dta 18, 24, 27, 30, 36, 42

; sm_chr: MOSBUF+X = A, X + 1 (bounded: 255; the firmware's status
; lands in errbuf, so the text cannot be built there)
sm_chr:
    cpx #255
    bcs smc_full
    sta MOSBUF,x
    inx
smc_full:
    rts

; sm_str: the 0-terminated string at A/Y (low/high) to MOSBUF+X
sm_str:
    sta fsBLK
    sty fsBLK+1
    ldy #0
sms_loop:
    lda (fsBLK),y
    beq sms_rts
    jsr sm_chr
    iny
    bne sms_loop
sms_rts:
    rts

; sm_signed: [-]number at mosPTR/Y: mosNUM = magnitude (< 256), mosNUM+1
; = 1 if negative. C = 1 if none or too big.
sm_signed:
    lda (mosPTR),y
    cmp #' '
    bne sgn_start
    iny
    bne sm_signed
sgn_start:
    ldx #0
    cmp #'-'
    bne sgn_num
    iny
    inx
sgn_num:
    stx fsTMP
    jsr arg_number
    bcs sgn_rts
    lda mosNUM+1
    beq sgn_ok
    sec
    rts
sgn_ok:
    lda fsTMP
    sta mosNUM+1
    clc
sgn_rts:
    rts

sm_head     dta '[Audio Mixer]', 13, 10, 0
sm_pan      dta 'Pan ', 0
sm_vol      dta 'Vol ', 0
sm_ulti     dta 'UltiSID ', 0
sm_ultv     dta 'UltiSid ', 0
sm_sock     dta 'Socket ', 0
sm_ctr      dta 'Center', 0
sm_leftw    dta 'Left ', 0
sm_right    dta 'Right ', 0
sm_offw     dta 'OFF', 0
sm_db       dta ' dB', 0
sm_file     dta '/Temp/bbcmix.cfg', 0
sm_fend
sm_fname    dta '/Temp/bbcmix.cfg', 13
