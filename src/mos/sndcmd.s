; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- sound: everything outside the interrupt (bank 2)
;
; SID probing, OSWORD 7 (SOUND) and 8 (ENVELOPE), ADVAL, *SOUND and
; *INSTRUMENT; the interrupt engine is sound.s in RAM (label prefix snd.).
; Design: docs/DESIGN_SOUND.md.
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; snd_setup
;   Summary: at start-up (interrupts off): find the SIDs, then reset the
;            engine in SID mode.
;   Uses:    A, X, Y, mosPTR2.
snd_setup:
    jsr snd_probe
    lda #0
    sta snd.s_mode
    jmp SOUNDRAM+0

; snd_instinit: after the REU is known: the 16 default instruments to the
; REU, 17-64 as copies of instrument 1 (no REU: the engine's built-in one)
snd_instinit:
    jsr has_reu
    beq sii_rts
    lda #1
    sta fsSX
sii_loop:
    lda fsSX                    ; source: snd_definst + (n-1) * 64, or 1
    cmp #17
    bcc sii_own
    lda #1
sii_own:
    jsr si_srcptr
    jsr si_put                  ; 64 bytes (fsBLK) -> instrument fsSX
    inc fsSX
    lda fsSX
    cmp #65
    bne sii_loop
sii_rts:
    rts

; si_srcptr: fsBLK = snd_definst + (A - 1) * 64
si_srcptr:
    sec
    sbc #1
    sta fsBLK+1                 ; (n-1) * 64 = (n-1) * 256 / 4
    lda #0
    lsr fsBLK+1
    ror
    lsr fsBLK+1
    ror
    clc
    adc #<snd_definst
    sta fsBLK
    lda fsBLK+1
    adc #>snd_definst
    sta fsBLK+1
    rts

; si_reu: REU registers for instrument fsSX (64 bytes) <-> (fsBLK)
si_reu:
    lda fsSX
    sec
    sbc #1
    and #63
    sta fsCNT
    lda #0
    lsr fsCNT
    ror
    lsr fsCNT
    ror
    sta REU_ADDR
    lda fsCNT
    clc
    adc #>snd.REU_INST
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda fsBLK
    sta REU_C64
    lda fsBLK+1
    sta REU_C64+1
    lda #64
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    rts
si_put:
    jsr si_reu
    lda #REU_TO_REU
    sta REU_CMD
    rts
si_get:
    jsr si_reu
    lda #REU_TO_C64
    sta REU_CMD
    rts

; ----------------------------------------------------------------------------
; snd_probe
;   Summary: find the SIDs (up to 8) at $D400-$D7E0, the 8SID layout's
;            addresses first.
;   Function: a SID is at B if voice 3's oscillator (saw, highest
;            frequency) holds still at OSC3 ($1B) with the TEST bit (0 on
;            a SID or UltiSID, 255 on an ARMSID), changes without it and
;            stops again with it; it is a new one if running it does not
;            run a SID found before (mirrors). The display is off
;            meanwhile, so open-bus reads hold still too and never pass.
;            $DE00-$DFFF is not probed (cartridge, REU, UCI, Ultimate
;            Audio live there).
;   Output:  snd.s_nsid, snd.s_sidlo/hi.  Uses: A, X, Y, mosPTR2.
snd_probe:
    php
    sei
    lda $D011
    pha
    and #$EF
    sta $D011
    lda #0
    sta snd.s_nsid
    sta fsSX                    ; candidate index
spb_cand:
    ldx fsSX
    lda sp_cands,x
    sta mosPTR2+1
    lda sp_candl,x
    sta mosPTR2
    jsr sp_test
    bcc spb_next
    ldx snd.s_nsid              ; a new SID
    lda mosPTR2
    sta snd.s_sidlo,x
    lda mosPTR2+1
    sta snd.s_sidhi,x
    inc snd.s_nsid
    lda snd.s_nsid
    cmp #8
    bcs spb_end
spb_next:
    inc fsSX
    lda fsSX
    cmp #SP_NCAND
    bcc spb_cand
spb_end:
    ldx snd.s_nsid              ; voice 3 of every SID found: off
spb_off:
    dex
    bmi spb_done
    lda snd.s_sidlo,x
    sta mosPTR2
    lda snd.s_sidhi,x
    sta mosPTR2+1
    lda #0
    ldy #$12
    sta (mosPTR2),y
    ldy #$0E
    sta (mosPTR2),y
    iny
    sta (mosPTR2),y
    jmp spb_off
spb_done:
    lda snd.s_nsid              ; none (unusual): assume $D400
    bne spb_rts
    lda #<$D400
    sta snd.s_sidlo
    lda #>$D400
    sta snd.s_sidhi
    inc snd.s_nsid
spb_rts:
    pla
    sta $D011
    plp
    rts

; Candidates: the 8SID layout of two split UltiSIDs first (the shipped
; .cfg, as Heartbeat's: $D400/$D420, Range Split 1/4 on A7, A8), then
; every $20 step of $D400-$D7E0 (those found already are mirrors then)
SP_NCAND    = 8+32
sp_cands:
    dta $D4, $D4, $D4, $D4, $D5, $D5, $D5, $D5
    :32 dta $D4+#/8
sp_candl:
    dta $00, $20, $80, $A0, $00, $20, $80, $A0
    :32 dta [#%8]*$20

; sp_test: C = 1 if a new SID is at (mosPTR2)
sp_test:
    lda #$FF                    ; voice 3: highest frequency, saw + TEST
    ldy #$0E
    sta (mosPTR2),y
    iny
    sta (mosPTR2),y
    lda #$28
    ldy #$12
    sta (mosPTR2),y
    jsr sp_still                ; TEST: OSC3 holds still
    bne sp_no
    lda #$20                    ; running: it must change
    ldy #$12
    sta (mosPTR2),y
    jsr sp_delay
    jsr sp_read
    sta fsCNT
    jsr sp_delay
    jsr sp_read
    cmp fsCNT
    bne sp_runs
    jsr sp_delay
    jsr sp_read
    cmp fsCNT
    beq sp_stop                 ; does not run
sp_runs:
    lda #$28                    ; TEST again: it must stop
    ldy #$12
    sta (mosPTR2),y
    jsr sp_still
    bne sp_no
    lda #$20
    ldy #$12
    sta (mosPTR2),y
    ldx snd.s_nsid              ; a mirror of a SID found before?
sp_mir:
    dex
    bmi sp_new
    lda snd.s_sidlo,x
    sta mosPTR
    lda snd.s_sidhi,x
    sta mosPTR+1
    ldy #$1B
    lda (mosPTR),y
    sta fsCNT
    jsr sp_delay
    ldy #$1B
    lda (mosPTR),y
    cmp fsCNT
    bne sp_mirror
    jmp sp_mir
sp_new:
    jsr sp_stop
    sec
    rts
sp_mirror:
    jsr sp_stop
sp_no:
    clc
    rts
sp_stop:
    lda #$28                    ; back to saw + TEST
    ldy #$12
    sta (mosPTR2),y
    clc
    rts

; sp_still: Z = 1 if OSC3 at (mosPTR2) reads the same three times
sp_still:
    jsr sp_delay
    jsr sp_read
    sta fsCNT
    jsr sp_delay
    jsr sp_read
    cmp fsCNT
    bne sps_rts
    jsr sp_delay
    jsr sp_read
    cmp fsCNT
sps_rts:
    rts

; sp_read: A = OSC3 at (mosPTR2) (X kept)
sp_read:
    ldy #$1B
    lda (mosPTR2),y
    rts

; sp_delay: some SID clock cycles, also at 64 MHz (X kept)
sp_delay:
    txa
    pha
    ldx #0
spd_loop:
    nop
    nop
    dex
    bne spd_loop
    pla
    tax
    rts

; ----------------------------------------------------------------------------
; snd_word7 (OSWORD 7)
;   Summary: SOUND C,A,P,D: queue a note.
;   Function: BBC mode: C = &HSFN (N AND 3 channel, F <> 0 flush, S sync
;            0-3, H hold); SID mode: C = &FSVV (VV voice 0-23, S sync
;            0-15, F: 1 flush, 2 hold, 4 tie). Waits while the queue is
;            full (ESCAPE ends the wait). Nothing under *SOUND OFF.
;   Input:   mosPTR = block: C, A, P, D (16 bits each).
;   Uses:    A, X, Y, fsTMP.
snd_word7:
    lda snd.s_off
    beq sw7_on
    rts
sw7_on:
    ldy #2                      ; amplitude, pitch, duration
    lda (mosPTR),y
    sta snd.s_qbuf+1
    ldy #4
    lda (mosPTR),y
    sta snd.s_qbuf+2
    iny
    lda (mosPTR),y
    sta snd.s_qbuf+3
    ldy #6
    lda (mosPTR),y
    sta snd.s_qbuf+4
    ldy #1
    lda (mosPTR),y
    sta fsTMP                   ; C high byte
    dey
    lda (mosPTR),y              ; C low byte
    ldx snd.s_mode
    beq sw7_sid
    pha                         ; BBC mode
    and #$F0
    sta fsTMP+1                 ; flush
    pla
    and #3
    tax
    lda #0
    sta snd.s_qbuf+3            ; (pitch 0-255)
    lda fsTMP
    and #3
    sta snd.s_qbuf
    lda fsTMP
    and #$F0
    beq sw7_go
    lda snd.s_qbuf
    ora #snd.QF_HOLD
    sta snd.s_qbuf
    jmp sw7_go
sw7_sid:
    cmp #snd.NV                 ; voice
    bcs sw7_rts
    tax
    lda fsTMP                   ; F: 1 flush, 2 hold, 4 tie
    and #$10
    sta fsTMP+1
    lda fsTMP
    and #$0F
    sta snd.s_qbuf              ; sync
    lda fsTMP
    and #$20
    beq sw7_nh
    lda snd.s_qbuf
    ora #snd.QF_HOLD
    sta snd.s_qbuf
sw7_nh:
    lda fsTMP
    and #$40
    beq sw7_go
    lda snd.s_qbuf
    ora #snd.QF_TIE
    sta snd.s_qbuf
sw7_go:
    lda fsTMP+1                 ; flush first
    beq sw7_wait
    jsr SOUNDRAM+18
sw7_wait:
    jsr SOUNDRAM+6              ; queue it (C = 1: full)
    bcc sw7_rts
    bit ESCFLG
    bpl sw7_wait
sw7_rts:
    rts

; snd_word8 (OSWORD 8): ENVELOPE N,13 parameters (N 1-16)
snd_word8:
    ldy #0
    lda (mosPTR),y
    beq sw8_rts
    cmp #17
    bcs sw8_rts
    tax
    lda snd.env_ofs-1,x
    tax
    php
    sei
    ldy #1
sw8_copy:
    lda (mosPTR),y
    sta snd.env,x
    inx
    iny
    cpy #14
    bne sw8_copy
    plp
sw8_rts:
    rts

; snd_adval: OSBYTE &80 with X = &E4-&FB (ADVAL(-5) to ADVAL(-28)):
; X = free queue bytes of voice &FB - X (BBC mode: channels 0-3 only)
snd_adval:
    txa
    eor #$FF
    sec
    sbc #4                      ; &FB -> 0
    ldx snd.s_mode
    beq sad_sid
    cmp #4
    bcs sad_zero
sad_sid:
    tax
    jmp SOUNDRAM+9
sad_zero:
    ldx #0
    rts

; ----------------------------------------------------------------------------
; cmd_sound
;   Summary: *SOUND: show the mode; *SOUND SID / BBC: the mode (voices
;            reset); *SOUND OFF / ON: sound off (SOUND ignored, as
;            *FX210,1) and on; *SOUND STOP: every voice silent, queues
;            emptied.
;   Input:   mosPTR/Y.  Uses: A, X, Y.
cmd_sound:
    lda #<cw_sid
    ldx #>cw_sid
    jsr arg_word
    bcc csd_bbc
    lda #0
    beq csd_mode
csd_bbc:
    lda #<fw_bbc
    ldx #>fw_bbc
    jsr arg_word
    bcc csd_off
    lda #1
csd_mode:
    sta snd.s_mode
    jmp SOUNDRAM+0
csd_off:
    lda #<w_off
    ldx #>w_off
    jsr arg_word
    bcc csd_on
    lda #1
    sta snd.s_off
    jmp SOUNDRAM+12
csd_on:
    lda #<w_on
    ldx #>w_on
    jsr arg_word
    bcc csd_stop
    lda #0
    sta snd.s_off
    rts
csd_stop:
    lda #<cw_stop
    ldx #>cw_stop
    jsr arg_word
    bcc csd_show
    jmp SOUNDRAM+12
csd_show:
    jsr ci_skipsp
    cmp #13
    beq csd_print
    jmp an_syntax
csd_print:
    lda snd.s_mode
    bne csd_pbbc
    jsr st_text
    dta 'SID mode, ', 0
    jmp csd_onoff
csd_pbbc:
    jsr st_text
    dta 'BBC mode, ', 0
csd_onoff:
    lda snd.s_off
    bne csd_poff
    jsr st_text
    dta 'on', 13, 0
    rts
csd_poff:
    jsr st_text
    dta 'off', 13, 0
    rts

cw_sid      dta 'SID', 0
cw_stop     dta 'STOP', 0

; ----------------------------------------------------------------------------
; cmd_instrument
;   Summary: *INSTRUMENT n [parts]: define instrument n (1-64);
;            *INSTRUMENT n: list it; *INSTRUMENT n NAME text / COPY m;
;            *INSTRUMENT DEFAULT; *INSTRUMENT SAVE / LOAD <file>.
;   Function: the record is read from the REU into MOSBUF, changed and
;            written back. Parts: TRI SAW PULSE NOISE RING SYNC (the
;            waveform: the first of these replaces the old one), ADSR a d
;            s r (0-15), PW w (0-4095), FILTER [LOW] [BAND] [HIGH] [RES r]
;            [CUT c], NOFILTER, FINE f (-128..127).
;   Input:   mosPTR/Y.  Output: raises on errors.
;   Uses:    A, X, Y, fs*, MOSBUF.
cmd_instrument:
    jsr has_reu
    bne ci_reu
    brk
    dta 189, 'Instruments need an REU', 0
ci_reu:
    lda #<fw_default
    ldx #>fw_default
    jsr arg_word
    bcc ci_save
    jmp snd_instinit
ci_save:
    lda #<fw_save
    ldx #>fw_save
    jsr arg_word
    bcc ci_load
    jmp ci_dosave
ci_load:
    lda #<fw_load
    ldx #>fw_load
    jsr arg_word
    bcc ci_num
    jmp ci_doload
ci_num:
    jsr arg_number
    bcs ci_syn
    lda mosNUM+1
    bne ci_syn
    lda mosNUM
    beq ci_syn
    cmp #65
    bcs ci_syn
    sta fsSX
    lda #<MOSBUF
    sta fsBLK
    lda #>MOSBUF
    sta fsBLK+1
    jsr si_get                  ; the record to MOSBUF
    jsr ci_skipsp               ; nothing else: list it
    cmp #13
    bne ci_parts
    jmp ci_list
ci_syn:
    jmp an_syntax

; ci_skipsp: A = the next non-space character at mosPTR/Y
ci_skipsp:
    lda (mosPTR),y
    cmp #' '
    bne cis_rts
    iny
    bne ci_skipsp
cis_rts:
    rts

; the parts, until the end of the line
ci_parts:
    lda #0
    sta fsMODE                  ; bit 0: waveform replaced, bit 1: mode
ci_part:
    jsr ci_skipsp
    cmp #13
    bne ci_word
    lda #<MOSBUF                ; done: write the record back
    sta fsBLK
    lda #>MOSBUF
    sta fsBLK+1
    jmp si_put
ci_word:
    ldx #0                      ; find the word in ci_words
ci_try:
    lda ci_wtab+1,x             ; (the high byte is never 0)
    beq ci_syn
    stx fsCNT+1
    pha
    lda ci_wtab,x
    sta fsCNT
    pla
    tax
    lda fsCNT
    jsr arg_word
    ldx fsCNT+1
    bcs ci_found
    inx
    inx
    inx
    bne ci_try
ci_found:
    lda ci_wtab+2,x             ; part number
    asl
    tax
    lda ci_jumps+1,x
    pha
    lda ci_jumps,x
    pha
    rts

; words (address, part number)
ci_wtab:
    dta a(cw_tri), 0, a(cw_saw), 1, a(cw_pulse), 2, a(cw_noise), 3
    dta a(cw_ring), 4, a(cw_sync), 5, a(cw_adsr), 6, a(cw_pw), 7
    dta a(cw_filter), 8, a(cw_nofilt), 9, a(cw_low), 10, a(cw_band), 11
    dta a(cw_high), 12, a(cw_res), 13, a(cw_cut), 14, a(cw_fine), 15
    dta a(cw_name), 16, a(cw_copy), 17
    dta 0, 0, 0
ci_jumps:
    dta a(cp_tri-1), a(cp_saw-1), a(cp_pulse-1), a(cp_noise-1)
    dta a(cp_ring-1), a(cp_sync-1), a(cp_adsr-1), a(cp_pw-1)
    dta a(cp_filter-1), a(cp_nofilt-1), a(cp_low-1), a(cp_band-1)
    dta a(cp_high-1), a(cp_res-1), a(cp_cut-1), a(cp_fine-1)
    dta a(cp_name-1), a(cp_copy-1)

cw_tri      dta 'TRI', 0
cw_saw      dta 'SAW', 0
cw_pulse    dta 'PULSE', 0
cw_noise    dta 'NOISE', 0
cw_ring     dta 'RING', 0
cw_sync     dta 'SYNC', 0
cw_adsr     dta 'ADSR', 0
cw_pw       dta 'PW', 0
cw_filter   dta 'FILTER', 0
cw_nofilt   dta 'NOFILTER', 0
cw_low      dta 'LOW', 0
cw_band     dta 'BAND', 0
cw_high     dta 'HIGH', 0
cw_res      dta 'RES', 0
cw_cut      dta 'CUT', 0
cw_fine     dta 'FINE', 0
cw_name     dta 'NAME', 0
cw_copy     dta 'COPY', 0

; waveform bits: the first waveform word replaces the old waveform
cp_tri:
    lda #$10
    bne cp_wave
cp_saw:
    lda #$20
    bne cp_wave
cp_pulse:
    lda #$40
    bne cp_wave
cp_noise:
    lda #$80
    bne cp_wave
cp_ring:
    lda #$04
    bne cp_wave
cp_sync:
    lda #$02
cp_wave:
    pha
    lda fsMODE
    lsr
    bcs cpw_or
    lda #0
    sta MOSBUF+0
    lda fsMODE
    ora #1
    sta fsMODE
cpw_or:
    pla
    ora MOSBUF+0
    sta MOSBUF+0
    jmp ci_part

; ADSR a d s r (0-15 each)
cp_adsr:
    jsr ci_nyb
    asl
    asl
    asl
    asl
    sta MOSBUF+1
    jsr ci_nyb
    ora MOSBUF+1
    sta MOSBUF+1
    jsr ci_nyb
    asl
    asl
    asl
    asl
    sta MOSBUF+2
    jsr ci_nyb
    ora MOSBUF+2
    sta MOSBUF+2
    jmp ci_part

; ci_nyb: A = the next number, 0-15
ci_nyb:
    jsr arg_number
    bcs cin_syn
    lda mosNUM+1
    bne cin_syn
    lda mosNUM
    cmp #16
    bcs cin_syn
    rts
cin_syn:
    jmp an_syntax

; PW w (0-4095)
cp_pw:
    jsr arg_number
    bcs cin_syn
    lda mosNUM+1
    cmp #16
    bcs cin_syn
    sta MOSBUF+4
    lda mosNUM
    sta MOSBUF+3
    jmp ci_part

; FILTER: on (low pass unless a mode follows); NOFILTER: off
cp_filter:
    lda MOSBUF+12
    and #$70
    bne cpf_mode
    lda #$10                    ; no mode yet: low pass
cpf_mode:
    ora MOSBUF+12
    ora #1
    sta MOSBUF+12
    jmp ci_part
cp_nofilt:
    lda MOSBUF+12
    and #$FE
    sta MOSBUF+12
    jmp ci_part

; LOW / BAND / HIGH: the filter mode (the first one replaces the old)
cp_low:
    lda #$10
    bne cp_fmode
cp_band:
    lda #$20
    bne cp_fmode
cp_high:
    lda #$40
cp_fmode:
    pha
    lda fsMODE
    and #2
    bne cpm_or
    lda MOSBUF+12
    and #$0F
    sta MOSBUF+12
    lda fsMODE
    ora #2
    sta fsMODE
cpm_or:
    pla
    ora MOSBUF+12
    ora #1                      ; (a mode switches the filter on)
    sta MOSBUF+12
    jmp ci_part

; RES r (0-15)
cp_res:
    jsr ci_nyb
    sta MOSBUF+13
    jmp ci_part

; CUT c (0-255: the high 8 bits of the cutoff)
cp_cut:
    jsr arg_number
    bcs cin_syn
    lda mosNUM+1
    bne cin_syn
    lda mosNUM
    sta MOSBUF+14
    jmp ci_part

; FINE f (-128..127)
cp_fine:
    jsr sm_signed
    bcs cpfi_syn
    lda mosNUM
    bmi cpfi_syn
    ldx mosNUM+1
    beq cpfi_pos
    eor #$FF
    clc
    adc #1
cpfi_pos:
    sta MOSBUF+18
    jmp ci_part
cpfi_syn:
    jmp an_syntax

; NAME text: the rest of the line, up to 10 characters
cp_name:
    jsr ci_skipsp
    ldx #0
cpn_loop:
    lda (mosPTR),y
    cmp #13
    beq cpn_pad
    jsr up2
    sta MOSBUF+53,x
    iny
    inx
    cpx #10
    bne cpn_loop
cpn_skip:
    lda (mosPTR),y              ; (the rest is dropped)
    cmp #13
    beq cpn_done
    iny
    bne cpn_skip
cpn_pad:
    lda #' '
    sta MOSBUF+53,x
    inx
    cpx #10
    bne cpn_pad
cpn_done:
    jmp ci_part

; COPY m: instrument m's record, then the other parts on the line
cp_copy:
    jsr arg_number
    bcs cpc_syn
    lda mosNUM+1
    bne cpc_syn
    lda mosNUM
    beq cpc_syn
    cmp #65
    bcs cpc_syn
    lda fsSX
    pha
    lda mosNUM
    sta fsSX
    lda #<MOSBUF
    sta fsBLK
    lda #>MOSBUF
    sta fsBLK+1
    sty fsCNT+1
    jsr si_get
    ldy fsCNT+1
    pla
    sta fsSX
    jmp ci_part
cpc_syn:
    jmp an_syntax

; ----------------------------------------------------------------------------
; ci_list: "n NAME       PULSE ADSR 0 9 10 8 PW 2048 FILTER LOW RES 6 CUT 96"
ci_list:
    lda fsSX
    jsr st_dec8
    lda #' '
    jsr OSWRCH
    ldx #0
cl_name:
    lda MOSBUF+53,x
    jsr OSWRCH
    inx
    cpx #10
    bne cl_name
    ldx #0                      ; waveform words
cl_wave:
    lda cl_bits,x
    and MOSBUF+0
    beq cl_wn
    stx fsCNT
    lda #' '
    jsr OSWRCH
    lda fsCNT
    asl
    asl
    asl
    tax                         ; (8 per word in cl_wnames)
cl_wc:
    lda cl_wnames,x
    beq cl_wd
    jsr OSWRCH
    inx
    bne cl_wc
cl_wd:
    ldx fsCNT
cl_wn:
    inx
    cpx #6
    bne cl_wave
    jsr st_text
    dta ' ADSR', 0
    lda MOSBUF+1
    jsr cl_hi
    lda MOSBUF+1
    jsr cl_lo
    lda MOSBUF+2
    jsr cl_hi
    lda MOSBUF+2
    jsr cl_lo
    lda MOSBUF+0                ; pulse width when pulse
    and #$40
    beq cl_filt
    jsr st_text
    dta ' PW ', 0
    lda MOSBUF+3
    sta mosTMP
    lda MOSBUF+4
    sta mosTMP+1
    jsr st_dec16
cl_filt:
    lda MOSBUF+12
    lsr
    bcc cl_end
    jsr st_text
    dta ' FILTER', 0
    lda MOSBUF+12
    and #$10
    beq cl_f2
    jsr st_text
    dta ' LOW', 0
cl_f2:
    lda MOSBUF+12
    and #$20
    beq cl_f3
    jsr st_text
    dta ' BAND', 0
cl_f3:
    lda MOSBUF+12
    and #$40
    beq cl_f4
    jsr st_text
    dta ' HIGH', 0
cl_f4:
    jsr st_text
    dta ' RES', 0
    lda MOSBUF+13
    jsr cl_num
    jsr st_text
    dta ' CUT', 0
    lda MOSBUF+14
    jsr cl_num
cl_end:
    jmp OSNEWL
; cl_hi / cl_lo / cl_num: " " and a nybble / byte in decimal
cl_hi:
    lsr
    lsr
    lsr
    lsr
cl_lo:
    and #15
cl_num:
    pha
    lda #' '
    jsr OSWRCH
    pla
    jmp st_dec8
cl_bits:
    dta $10, $20, $40, $80, $04, $02
cl_wnames:
    dta 'TRI', 0, 0, 0, 0, 0
    dta 'SAW', 0, 0, 0, 0, 0
    dta 'PULSE', 0, 0, 0
    dta 'NOISE', 0, 0, 0
    dta 'RING', 0, 0, 0, 0
    dta 'SYNC', 0, 0, 0, 0

; ----------------------------------------------------------------------------
; *INSTRUMENT SAVE / LOAD <file>: all 64 instruments, 4096 bytes, in 16
; pieces of 256 through MOSBUF
ci_dosave:
    jsr arg_name
    jsr ff_end
    jsr fs_free_target
    lda #FA_CREATE
    jsr fs_open
    bcc cis_open
    jmp uci_error
cis_open:
    lda #0
    sta fsSX
cis_piece:
    jsr ci_piece                ; REU -> MOSBUF
    lda #REU_TO_C64
    sta REU_CMD
    lda #<MOSBUF
    sta fsPTR
    lda #>MOSBUF
    sta fsPTR+1
    lda #0
    sta fsLEN
    lda #1
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
    bcc cis_next
    jsr fs_saveerr
    jmp uci_error
cis_next:
    inc fsSX
    lda fsSX
    cmp #16
    bne cis_piece
    jmp fs_close_tgt

ci_doload:
    jsr arg_name
    jsr ff_end
    jsr fs_free_target
    lda #FA_READ
    jsr fs_open
    bcc cil_open
    jmp uci_error
cil_open:
    jsr fs_size
    lda fsTMP
    ora fsTMP+2
    ora fsTMP+3
    bne cil_bad
    lda fsTMP+1
    cmp #$10
    bne cil_bad
    lda #0
    sta fsSX
cil_piece:
    lda #DOS_READ               ; 256 bytes to MOSBUF
    jsr fs_hdr2
    lda #0
    sta uciHDR+2
    sta fsLEN
    lda #1
    sta uciHDR+3
    lda #4
    sta uciHLEN
    lda #0
    sta fsLEN+1
    jsr fl_send_nopay
    lda #1
    sta fsLEN+1
    lda #0
    sta fsLEN
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    jsr uci_read_to
    jsr uci_finish
    bcs cil_err
    jsr ci_piece                ; MOSBUF -> REU
    lda #REU_TO_REU
    sta REU_CMD
    inc fsSX
    lda fsSX
    cmp #16
    bne cil_piece
    jmp fs_close_tgt
cil_err:
    jsr fs_saveerr
    jmp uci_error
cil_bad:
    jsr fs_close_tgt
    brk
    dta 186, 'Bad instrument file', 0

; ci_piece: REU registers for piece fsSX (256 bytes) <-> MOSBUF
ci_piece:
    lda #0
    sta REU_ADDR
    lda fsSX
    clc
    adc #>snd.REU_INST
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<MOSBUF
    sta REU_C64
    lda #>MOSBUF
    sta REU_C64+1
    lda #0
    sta REU_LEN
    lda #1
    sta REU_LEN+1
    lda #0
    sta REU_CTRL
    rts

; default instruments 1-16 (tools/gensound.py; in this bank: the REU DMA
; reads the bus with this bank mapped)
    icl 'sound_inst.s'
