; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- sound: everything outside the interrupt (bank 6)
;
; SID probing, OSWORD 7 (SOUND) and 8 (ENVELOPE), ADVAL, *SOUND and
; *INSTRUMENT; the interrupt engine is sound.s in RAM (images snds., sndb.
; in sndbank.s).
; Design: docs/DESIGN_SOUND.md.
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; snd_setup
;   Summary: at start-up (interrupts off), and when *SOUND brings an
;            engine back: pitch tables, find the SIDs, then engine image
;            A (0 SID, 1 BBC) into RAM.
;   Uses:    A, X, Y, mosPTR, mosPTR2, fs*.
snd_setup:
    pha
    ldx #0                      ; the shared data from scratch (mode, on,
    txa                         ; not recording, filter registers; more
sst_clr:                        ; than 128 bytes: counted up)
    sta SNDSHR,x
    inx
    cpx #SNDSHR_END-SNDSHR
    bne sst_clr
    jsr snd_tables
    jsr snd_probe
    lda s_nsid                  ; the probe found the 8SID layout itself
    cmp #8                      ; (it can, at start-up): remembered too
    bne sst_known
    ldx #7
sst_cmp:
    lda s_sidlo,x
    cmp sst_lo,x
    bne sst_known
    lda s_sidhi,x
    cmp sst_hi,x
    bne sst_known
    dex
    bpl sst_cmp
    lda #1
    sta snd_8sid
sst_known:
    lda snd_8sid                ; the 8SID layout: its addresses (a later
    beq sst_load                ; probe may see only one per UltiSID)
    ldx #7
sst_list:
    lda sst_lo,x
    sta s_sidlo,x
    lda sst_hi,x
    sta s_sidhi,x
    dex
    bpl sst_list
    lda #8
    sta s_nsid
sst_load:
    pla
    jmp snd_load
; the 8SID layout's addresses (*SID SETUP), in the probe's order
; (UltiSID 1, 2, 1, 2, ...: even SIDs left, odd right)
sst_lo      dta $00, $20, $80, $A0, $00, $20, $80, $A0
sst_hi      dta $D4, $D4, $D4, $D4, $D5, $D5, $D5, $D5

; snd_instinit: after the REU is known: the 16 default instruments to the
; REU, 17-64 as copies of instrument 1 (no REU: the engine's built-in one)
snd_instinit:
    jsr s6_hasreu
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
    adc #>REU_INST
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
    php                         ; (interrupts off while the REU is set up:
    sei                         ; the sound interrupt uses it too)
    jsr si_reu
    lda #REU_TO_REU
    sta REU_CMD
    plp
    rts
si_get:
    php
    sei
    jsr si_reu
    lda #REU_TO_C64
    sta REU_CMD
    plp
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
;   Output:  s_nsid, s_sidlo/hi.  Uses: A, X, Y, mosPTR2.
snd_probe:
    php
    sei
    lda $D011
    pha
    and #$EF
    sta $D011
    lda #0
    sta s_nsid
    sta fsSX                    ; candidate index
spb_cand:
    ldx fsSX
    lda sp_cands,x
    sta mosPTR2+1
    lda sp_candl,x
    sta mosPTR2
    jsr sp_test
    bcc spb_next
    ldx s_nsid              ; a new SID
    lda mosPTR2
    sta s_sidlo,x
    lda mosPTR2+1
    sta s_sidhi,x
    inc s_nsid
    lda s_nsid
    cmp #8
    bcs spb_end
spb_next:
    inc fsSX
    lda fsSX
    cmp #SP_NCAND
    bcc spb_cand
spb_end:
    ldx s_nsid              ; voice 3 of every SID found: off
spb_off:
    dex
    bmi spb_done
    lda s_sidlo,x
    sta mosPTR2
    lda s_sidhi,x
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
    lda s_nsid              ; none (unusual): assume $D400
    bne spb_rts
    lda #<$D400
    sta s_sidlo
    lda #>$D400
    sta s_sidhi
    inc s_nsid
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
    ldx s_nsid              ; a mirror of a SID found before?
sp_mir:
    dex
    bmi sp_new
    lda s_sidlo,x
    sta mosPTR
    lda s_sidhi,x
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
    lda snd_on                  ; nothing under *SOUND NONE or OFF
    beq sw7_none
    lda s_off
    beq sw7_on
sw7_none:
    rts
sw7_on:
    lda #0                      ; SID mode: A = instrument + 256 * level
    sta s_qlvl                  ; (level 1-15) as well
    ldy #3
    lda (mosPTR),y
    beq sw7_amp
    cmp #16
    bcs sw7_amp                 ; (-15..-1: high byte &FF)
    sta s_qlvl
sw7_amp:
    ldy #2                      ; amplitude, pitch, duration
    lda (mosPTR),y
    sta s_qbuf+1
    ldy #4
    lda (mosPTR),y
    sta s_qbuf+2
    iny
    lda (mosPTR),y
    sta s_qbuf+3
    ldy #6
    lda (mosPTR),y
    sta s_qbuf+4
    ldy #1
    lda (mosPTR),y
    sta fsTMP                   ; C high byte
    dey
    lda (mosPTR),y              ; C low byte
    ldx s_mode
    beq sw7_sid
    cpx #2                      ; the MOD engine: only voices 24-30
    beq sw7_ua
    pha                         ; BBC mode
    and #$F0
    sta fsTMP+1                 ; flush
    pla
    and #3
    tax
    lda #0
    sta s_qbuf+3            ; (pitch 0-255)
    lda fsTMP
    and #3
    sta s_qbuf
    lda fsTMP
    and #$F0
    beq sw7_go
    lda s_qbuf
    ora #QF_HOLD
    sta s_qbuf
    jmp sw7_go
sw7_sid:
    cmp #NV                 ; voice
    bcc sw7_v
sw7_ua:
    cmp #NV                 ; 24-30: Ultimate Audio samples (sample.s)
    bcc sw7_rts
    cmp #NV+7
    bcs sw7_rts
    farcall aud.sa_sound, BANK_AUD
    rts
sw7_v:
    tax
    lda fsTMP                   ; F: 1 flush, 2 hold, 4 tie
    and #$10
    sta fsTMP+1
    lda fsTMP
    and #$0F
    sta s_qbuf              ; sync
    lda fsTMP
    and #$20
    beq sw7_nh
    lda s_qbuf
    ora #QF_HOLD
    sta s_qbuf
sw7_nh:
    lda fsTMP
    and #$40
    beq sw7_go
    lda s_qbuf
    ora #QF_TIE
    sta s_qbuf
sw7_go:
    lda t_rec                   ; *SONG RECORD (SID mode): into the song
    beq sw7_play                ; (songcmd.s)
    lda s_mode
    bne sw7_play
    jmp sg_record
sw7_play:
    lda fsTMP+1                 ; flush first
    beq sw7_wait
    jsr SNDV_FLUSH
sw7_wait:
    jsr SNDV_PUT               ; queue it (C = 1: full)
    bcc sw7_rts
    bit ESCFLG
    bpl sw7_wait
sw7_rts:
    rts

; snd_word8 (OSWORD 8): ENVELOPE N,13 parameters (N 1-16): into the
; REU copy (REU_ENV, kept while the BBC image is not in RAM) and, with the
; BBC image in RAM, into its envelopes
snd_word8:
    ldy #0
    lda (mosPTR),y
    beq sw8_rts
    cmp #17
    bcs sw8_rts
    tax
    lda sw8_ofs-1,x
    sta fsCNT                   ; offset of envelope N
    jsr s6_hasreu
    beq sw8_ram
    php
    sei
    lda fsCNT                   ; the REU copy: 13 bytes from block+1
    clc
    adc #<REU_ENV
    sta REU_ADDR
    lda #>REU_ENV
    adc #0
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda mosPTR
    clc
    adc #1
    sta REU_C64
    lda mosPTR+1
    adc #0
    sta REU_C64+1
    lda #13
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    plp
sw8_ram:
    lda snd_on                  ; the BBC image in RAM?
    beq sw8_rts
    lda SNDV_IMG
    bne sw8_rts
    ldx fsCNT
    php
    sei
    ldy #1
sw8_copy:
    lda (mosPTR),y
    sta sndb.env,x
    inx
    iny
    cpy #14
    bne sw8_copy
    plp
sw8_rts:
    rts
sw8_ofs:
    :16 dta #*13

; snd_adval: OSBYTE &80 with X = &E4-&FB (ADVAL(-5) to ADVAL(-28)):
; X = free queue bytes of voice &FB - X (BBC mode: channels 0-3 only)
snd_adval:
    cpx #$E4                    ; ADVAL(-29) and lower: the song's notes
    bcs sad_queue
    jmp sg_adval
sad_queue:
    lda snd_on                  ; *SOUND NONE: every queue empty
    bne sad_on
    ldx #15
    rts
sad_on:
    txa
    eor #$FF
    sec
    sbc #4                      ; &FB -> 0
    ldx s_mode
    beq sad_sid
    cmp #4
    bcs sad_zero
sad_sid:
    tax
    jmp SNDV_ADVAL
sad_zero:
    ldx #0
    rts

; ----------------------------------------------------------------------------
; cmd_sound
;   Summary: *SOUND: show the mode; *SOUND SID / BBC: that engine image
;            into RAM (voices reset); *SOUND NONE: no engine, &0900-&1CFF
;            free for programs (PAGE may go down to &900); *SOUND OFF / ON:
;            sound off (SOUND ignored, as *FX210,1) and on; *SOUND STOP:
;            every voice silent, queues emptied.
;   Function: SID and BBC refuse while PAGE is below &1D00 (a program
;            there would be overwritten); after NONE they find the SIDs
;            again (the shared data may have been overwritten).
;   Input:   mosPTR/Y.  Uses: A, X, Y, fs*.
cmd_sound:
    lda #<cw_sid
    ldx #>cw_sid
    jsr s6_word
    bcc csd_bbc
    lda #0
    beq csd_mode
csd_bbc:
    lda #<s6w_bbc
    ldx #>s6w_bbc
    jsr s6_word
    bcc csd_none
    lda #1
csd_mode:
    pha
    jsr s6_end
    lda zpTXTP                  ; PAGE below the engine?
    cmp #>OSHWM
    bcs csd_room
    brk
    dta 198, 'No room: PAGE is below &1D00', 0
csd_room:
    lda snd_on                  ; an engine there: only the image changes
    beq csd_setup
    jsr SNDV_STOP
    pla
    jmp snd_load
csd_setup:
    pla                         ; after NONE: tables and SIDs again
    php
    sei
    jsr snd_setup
    plp
    rts
csd_none:
    lda #<s6w_none
    ldx #>s6w_none
    jsr s6_word
    bcc csd_off
    jsr s6_end
    lda snd_on
    beq csd_rts
    jsr SNDV_STOP                ; silent first
    lda #0
    sta snd_on
csd_rts:
    rts
csd_off:
    lda #<s6w_off
    ldx #>s6w_off
    jsr s6_word
    bcc csd_on
    lda #1
    sta s_off
    lda snd_on
    beq csd_rts
    jmp SNDV_STOP
csd_on:
    lda #<s6w_on
    ldx #>s6w_on
    jsr s6_word
    bcc csd_stop
    lda #0
    sta s_off
    rts
csd_stop:
    lda #<cw_stop
    ldx #>cw_stop
    jsr s6_word
    bcc csd_show
    lda snd_on
    beq csd_rts
    jmp SNDV_STOP
csd_show:
    jsr s6_end
    lda snd_on
    bne csd_print
    jsr s6_text
    dta 'None: &0900-&1CFF free', 13, 0
    rts
csd_print:
    lda s_mode
    bne csd_pbbc
    jsr s6_text
    dta 'SID mode, ', 0
    jmp csd_onoff
csd_pbbc:
    jsr s6_text
    dta 'BBC mode, ', 0
csd_onoff:
    lda s_off
    bne csd_poff
    jsr s6_text
    dta 'on', 13, 0
    rts
csd_poff:
    jsr s6_text
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
    jsr s6_hasreu
    bne ci_reu
    brk
    dta 189, 'Instruments need an REU', 0
ci_reu:
    lda #<s6w_default
    ldx #>s6w_default
    jsr s6_word
    bcc ci_save
    jmp snd_instinit
ci_save:
    lda #<s6w_save
    ldx #>s6w_save
    jsr s6_word
    bcc ci_load
    jmp ci_dosave
ci_load:
    lda #<s6w_load
    ldx #>s6w_load
    jsr s6_word
    bcc ci_num
    jmp ci_doload
ci_num:
    jsr s6_num
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
    jsr s6_skipsp               ; nothing else: list it
    cmp #13
    bne ci_parts
    jmp ci_list
ci_syn:
    jmp s6_syntax

; the parts, until the end of the line
ci_parts:
    lda #0
    sta fsMODE                  ; bit 0: waveform replaced, bit 1: mode
ci_part:
    jsr s6_skipsp
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
    jsr s6_word
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
    dta a(cw_name), 16, a(cw_copy), 17, a(cw_vib), 18, a(cw_porta), 19
    dta a(cw_restart), 20, a(cw_norest), 21, a(cw_stop), 22
    dta a(cw_bounce), 23, a(cw_waves), 24, a(cw_arp), 25, a(cw_speed), 26
    dta 0, 0, 0
ci_jumps:
    dta a(cp_tri-1), a(cp_saw-1), a(cp_pulse-1), a(cp_noise-1)
    dta a(cp_ring-1), a(cp_sync-1), a(cp_adsr-1), a(cp_pw-1)
    dta a(cp_filter-1), a(cp_nofilt-1), a(cp_low-1), a(cp_band-1)
    dta a(cp_high-1), a(cp_res-1), a(cp_cut-1), a(cp_fine-1)
    dta a(cp_name-1), a(cp_copy-1), a(cp_vib-1), a(cp_porta-1)
    dta a(cp_restart-1), a(cp_norest-1), a(cp_stop-1), a(cp_bounce-1)
    dta a(cp_waves-1), a(cp_arp-1), a(cp_speed-1)

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
cw_vib      dta 'VIB', 0
cw_porta    dta 'PORTA', 0
cw_restart  dta 'RESTART', 0
cw_norest   dta 'NORESTART', 0
cw_bounce   dta 'BOUNCE', 0
cw_waves    dta 'WAVES', 0
cw_arp      dta 'ARP', 0
cw_speed    dta 'SPEED', 0

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
    jsr s6_num
    bcs cin_syn
    lda mosNUM+1
    bne cin_syn
    lda mosNUM
    cmp #16
    bcs cin_syn
    rts
cin_syn:
    jmp s6_syntax

; PW w (0-4095)
cp_pw:
    jsr s6_num
    bcs cin_syn
    lda mosNUM+1
    cmp #16
    bcs cin_syn
    sta MOSBUF+4
    lda mosNUM
    sta MOSBUF+3
    ldx #5                      ; [rate top bottom]: the sweep
    jmp ci_sweep

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
    jsr s6_num
    bcs cin_syn
    lda mosNUM+1
    bne cin_syn
    lda mosNUM
    sta MOSBUF+14
    ldx #15                     ; [rate top bottom]: the sweep
    jmp ci_sweep

; FINE f (-128..127)
cp_fine:
    jsr s6_signed
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
    jmp s6_syntax

; NAME text: the rest of the line, up to 10 characters
cp_name:
    jsr s6_skipsp
    ldx #0
cpn_loop:
    lda (mosPTR),y
    cmp #13
    beq cpn_pad
    jsr s6_up
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
    jsr s6_num
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
    jmp s6_syntax

; ci_sweep: optional "rate top bottom" after PW or CUT into MOSBUF+X..+2
; (rate signed -128..127, top and bottom 0-255); without them: no sweep
ci_sweep:
    stx fsCNT+1
    jsr s6_skipsp
    cmp #'-'
    beq csw_go
    cmp #'0'
    bcc csw_none
    cmp #'9'+1
    bcs csw_none
csw_go:
    jsr ci_sbyte                ; rate
    ldx fsCNT+1
    sta MOSBUF,x
    jsr ci_byte                 ; top
    ldx fsCNT+1
    sta MOSBUF+1,x
    jsr ci_byte                 ; bottom
    ldx fsCNT+1
    sta MOSBUF+2,x
    jmp ci_part
csw_none:
    ldx fsCNT+1
    lda #0
    sta MOSBUF,x
    jmp ci_part

; ci_byte: A = the next number, 0-255 ("Syntax" otherwise)
ci_byte:
    jsr s6_num
    bcs cib_syn
    lda mosNUM+1
    bne cib_syn
    lda mosNUM
    rts
cib_syn:
    jmp s6_syntax

; ci_sbyte: A = the next number, -128..127 (two's complement)
ci_sbyte:
    jsr s6_signed
    bcs cib_syn
    lda mosNUM
    ldx mosNUM+1
    beq csb_pos
    cmp #129
    bcs cib_syn
    eor #$FF
    clc
    adc #1
    rts
csb_pos:
    cmp #128
    bcs cib_syn
    rts

; VIB delay width rate (0-255 each)
cp_vib:
    jsr ci_byte
    sta MOSBUF+8
    jsr ci_byte
    sta MOSBUF+9
    jsr ci_byte
    sta MOSBUF+10
    jmp ci_part

; PORTA speed (0 = none)
cp_porta:
    jsr ci_byte
    sta MOSBUF+11
    jmp ci_part

; RESTART / NORESTART: hard restart (flag bit 0); STOP / BOUNCE: the
; cutoff sweep stops at its end or turns (flag bit 1)
cp_restart:
    lda #1
    bne cpf_set
cp_stop:
    lda #2
cpf_set:
    ora MOSBUF+19
    sta MOSBUF+19
    jmp ci_part
cp_norest:
    lda #$FE
    bne cpf_clr
cp_bounce:
    lda #$FD
cpf_clr:
    and MOSBUF+19
    sta MOSBUF+19
    jmp ci_part

; WAVES w ...: the wave table (up to 16 bytes: waveform, 255 n = loop to
; step n, 0 = end), the rest 0; ARP a ...: the arpeggio table (semitones,
; signed), the rest 0
cp_waves:
    ldx #20
    lda #0
    beq cpt_go
cp_arp:
    ldx #36
    lda #1
cpt_go:
    sta fsSY                    ; (0: unsigned bytes, 1: signed)
    stx fsCNT+1
    txa
    clc
    adc #16
    sta fsTMP+1                 ; end
    lda #0                      ; clear the table
cpt_clr:
    sta MOSBUF,x
    inx
    cpx fsTMP+1
    bne cpt_clr
cpt_next:
    jsr s6_skipsp               ; another number?
    cmp #'-'
    beq cpt_num
    cmp #'&'
    beq cpt_num
    cmp #'0'
    bcc cpt_done
    cmp #'9'+1
    bcs cpt_done
cpt_num:
    ldx fsCNT+1
    cpx fsTMP+1
    bcs cpt_syn                 ; more than 16
    lda fsSY
    beq cpt_u
    jsr ci_sbyte
    jmp cpt_put
cpt_u:
    jsr ci_byte
cpt_put:
    ldx fsCNT+1
    sta MOSBUF,x
    inc fsCNT+1
    jmp cpt_next
cpt_done:
    jmp ci_part
cpt_syn:
    jmp s6_syntax

; SPEED n: interrupts per table step (1-255)
cp_speed:
    jsr ci_byte
    sta MOSBUF+52
    jmp ci_part

; ----------------------------------------------------------------------------
; ci_list: "n NAME       PULSE ADSR 0 9 10 8 PW 2048 FILTER LOW RES 6 CUT 96"
ci_list:
    lda fsSX
    jsr s6_dec8
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
    jsr s6_text
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
    jsr s6_text
    dta ' PW ', 0
    lda MOSBUF+3
    sta mosTMP
    lda MOSBUF+4
    sta mosTMP+1
    jsr s6_dec16
    ldx #5
    jsr cl_sweep
cl_filt:
    lda MOSBUF+12
    lsr
    bcc cl_end
    jsr s6_text
    dta ' FILTER', 0
    lda MOSBUF+12
    and #$10
    beq cl_f2
    jsr s6_text
    dta ' LOW', 0
cl_f2:
    lda MOSBUF+12
    and #$20
    beq cl_f3
    jsr s6_text
    dta ' BAND', 0
cl_f3:
    lda MOSBUF+12
    and #$40
    beq cl_f4
    jsr s6_text
    dta ' HIGH', 0
cl_f4:
    jsr s6_text
    dta ' RES', 0
    lda MOSBUF+13
    jsr cl_num
    jsr s6_text
    dta ' CUT', 0
    lda MOSBUF+14
    jsr cl_num
    ldx #15
    jsr cl_sweep
    lda MOSBUF+19
    and #2
    beq cl_end
    jsr s6_text
    dta ' STOP', 0
cl_end:
    lda MOSBUF+9                ; vibrato
    beq cl_porta
    jsr s6_text
    dta ' VIB', 0
    lda MOSBUF+8
    jsr cl_num
    lda MOSBUF+9
    jsr cl_num
    lda MOSBUF+10
    jsr cl_num
cl_porta:
    lda MOSBUF+11
    beq cl_fine
    jsr s6_text
    dta ' PORTA', 0
    lda MOSBUF+11
    jsr cl_num
cl_fine:
    lda MOSBUF+18
    beq cl_hr
    jsr s6_text
    dta ' FINE', 0
    lda MOSBUF+18
    jsr cl_snum
cl_hr:
    lda MOSBUF+19
    lsr
    bcc cl_tabs
    jsr s6_text
    dta ' RESTART', 0
cl_tabs:
    lda MOSBUF+20               ; tables: up to the 0 that ends them
    beq cl_done
    jsr s6_text
    dta ' WAVES', 0
    ldx #20
    jsr cl_table
    jsr s6_text
    dta ' ARP', 0
    ldx #36
    jsr cl_table
    jsr s6_text
    dta ' SPEED', 0
    lda MOSBUF+52
    jsr cl_num
cl_done:
    jmp OSNEWL

; cl_sweep: " rate top bottom" of the sweep at MOSBUF+X, if its rate <> 0
cl_sweep:
    lda MOSBUF,x
    beq cls_rts
    stx fsCNT+1
    jsr cl_snum
    ldx fsCNT+1
    lda MOSBUF+1,x
    jsr cl_num
    ldx fsCNT+1
    lda MOSBUF+2,x
    jmp cl_num
cls_rts:
    rts

; cl_table: the table at MOSBUF+X (16 steps) up to its last non-zero step
; (signed for the arpeggio table at 36)
cl_table:
    stx fsCNT+1
    txa                         ; the last non-zero step
    clc
    adc #15
    tay
clt_last:
    lda MOSBUF,y
    bne clt_have
    dey
    cpy fsCNT+1
    bcs clt_last
    lda #0                      ; all 0: one 0
    jmp cl_num
clt_have:
    sty fsTMP+1
clt_loop:
    ldx fsCNT+1
    lda MOSBUF,x
    cpx #36
    bcc clt_u
    jsr cl_snum
    jmp clt_n
clt_u:
    jsr cl_num
clt_n:
    inc fsCNT+1
    lda fsTMP+1
    cmp fsCNT+1
    bcs clt_loop
    rts

; cl_snum: " " and a signed byte in decimal
cl_snum:
    pha
    lda #' '
    jsr OSWRCH
    pla
    bpl cls_pos
    pha
    lda #'-'
    jsr OSWRCH
    pla
    eor #$FF
    clc
    adc #1
cls_pos:
    jmp s6_dec8
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
    jmp s6_dec8
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
; *INSTRUMENT SAVE / LOAD <file>: all 64 instruments, 4096 bytes (16
; pages of the REU, through bank 2's rx_ routines, reufile.s)
ci_dosave:
    jsr s6_name
    jsr s6_end
    farcall rx_create, BANK_FS
    lda #REU_FONT_BANK
    ldy #>REU_INST
    ldx #16
    farcall rx_write, BANK_FS
    farcall rx_close, BANK_FS
    rts

ci_doload:
    jsr s6_name
    jsr s6_end
    farcall rx_openin, BANK_FS
    lda fsTMP                   ; exactly 4096 bytes
    ora fsTMP+2
    ora fsTMP+3
    bne cil_bad
    lda fsTMP+1
    cmp #$10
    bne cil_bad
    lda #REU_FONT_BANK
    ldy #>REU_INST
    ldx #16
    farcall rx_read, BANK_FS
    farcall rx_close, BANK_FS
    rts
cil_bad:
    farcall rx_close, BANK_FS
    brk
    dta 186, 'Bad instrument file', 0

; default instruments 1-16 (tools/gensound.py; in this bank: the REU DMA
; reads the bus with this bank mapped)
    icl 'sound_inst.s'
