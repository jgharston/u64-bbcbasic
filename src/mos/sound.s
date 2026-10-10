; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- sound engine core, assembled for SOUNDRAM ($0900)
;
; Two images with the same entry points, in the sound bank (sndbank.s):
; the BBC image (SIDIMG = 0, sound_bbc.s) and the SID image (SIDIMG = 1,
; sound_sid.s); *SOUND BBC / SID copies one into RAM ($0900-$1BFF, code
; and its variables), *SOUND NONE takes it out. What both share (mode,
; the SIDs found, filter registers, pitch tables) is at SNDSHR ($1C00,
; defs.s). The parts that do not run in the interrupt (OSWORD 7/8, SID
; probing, the * commands) are sndcmd.s in the sound bank. Design:
; docs/DESIGN_SOUND.md.
;
; Both images: queues of 3 notes per voice, flush, sync, hold.
;
; The interrupt part uses no zero page: absolute addressing, the SID
; writes through a patched address (s_w). It runs in RAM, so the
; self-modifying code is allowed.
;
; ----------------------------------------------------------------------------

; voice states
ST_IDLE     = 0
ST_PLAY     = 1                 ; note sounding, duration running
ST_REL      = 2                 ; duration over, releasing
ST_HOLD     = 3                 ; a hold note: duration runs, release goes on

; ----------------------------------------------------------------------------
; Entry points (SOUNDRAM + n, defs.s SND_*)

    jmp s_init                  ; +0  reset the voices
    jmp s_irq                   ; +3  from the interrupt
    jmp s_put                   ; +6  queue s_qbuf on voice X (C = 1: full)
    jmp s_adval                 ; +9  X = voice: X = free queue bytes
    jmp s_stopall               ; +12 silence, empty the queues
    jmp s_bell                  ; +15 VDU 7
    jmp s_flush                 ; +18 voice X: queue emptied, sound off
    dta SIDIMG                  ; +21 which image (0 BBC, 1 SID)

; ----------------------------------------------------------------------------
; s_init
;   Summary: all voices idle, queues empty, every SID silent at volume 15,
;            voices mapped to SID voices.
;   Function: voice v = SID v DIV 3, voice v MOD 3 (voices beyond the SIDs
;            found write to a dummy); then the image's own mapping
;            (s_imginit).
;   Uses:    A, X, Y.
s_init:
    php
    sei
    ldx #NV-1
si_clr:
    lda #0
    sta c_state,x
    sta c_qn,x
    sta c_qr,x
    sta c_wait,x
    .if SIDIMG = 0
    sta c_vol,x
    sta c_env,x
    .else
    lda #1                      ; instrument 1
    sta c_inst,x
    .endif
    txa
    ldy #0
si_div:
    cmp #3
    bcc si_mod
    sbc #3
    iny
    bne si_div
si_mod:
    sta s_t
    asl
    asl
    asl
    sec
    sbc s_t                     ; voice in SID * 7
    sta c_voff,x
    tya
    cmp s_nsid
    bcc si_ok
    lda #$FF                    ; no such SID
si_ok:
    sta c_sid,x
    .if SIDIMG = 1
    stx s_ch
    jsr s_ldinst                ; the default instrument's header
    ldx s_ch
    .endif
    dex
    bpl si_clr
    jsr s_imginit
    ldx s_nsid                  ; every SID: voices off, volume 15
    beq si_done
si_sid:
    dex
    stx s_tmp
    lda #0
    sta s_f17,x
    lda #$0F
    sta s_f18,x
    txa
    jsr s_sidbase
    ldy #$17
si_regs:
    lda #0
    jsr s_w
    dey
    bpl si_regs
    ldy #$18
    lda #$0F
    jsr s_w
    ldx s_tmp
    bne si_sid
si_done:
    lda mostime
    sta s_lastt
    plp
    rts

; ----------------------------------------------------------------------------
; s_irq
;   Summary: per interrupt: durations, envelope steps, next notes.
;   Function: the centiseconds since the last call come from TIME (so
;            the 60 Hz system interrupt and Upic Lite's 50 Hz frame
;            interrupt both work); at most 10 per call. Idle voices with
;            empty queues cost a few cycles each. SID mode reads its
;            tables and the song from the REU here: every transfer from
;            the foreground sets the REU up with interrupts off (the REU
;            registers cannot be saved and restored here: the Ultimate's
;            bank register reads back only its low 3 bits).
;   Uses:    A, X, Y (the interrupt saved them), s_* variables.
s_irq:
    lda mostime
    sec
    sbc s_lastt
    beq sq_rts
    cmp #11
    bcc sq_cs
    lda #10
sq_cs:
    sta s_cs
    lda mostime
    sta s_lastt
    ldx #NV-1
sq_ch:
    lda c_state,x
    ora c_qn,x
    beq sq_skip
    stx s_ch
    jsr s_chan
    ldx s_ch
    .if SIDIMG = 1
    lda c_mod,x                 ; modulation (sound_sid.s)
    beq sq_skip
    jsr s_mod
    ldx s_ch
    .endif
sq_skip:
    dex
    bpl sq_ch
    jsr s_sync
    .if SIDIMG = 1
    lda t_on                    ; the song (sound_sid.s)
    beq sq_rts
    jsr s_song
    .endif
sq_rts:
    rts

; s_chan: one voice (X): duration, envelope, next note
s_chan:
    lda c_state,x
    beq sc_next
    cmp #ST_REL
    beq sc_env
    lda c_dur,x                 ; ST_PLAY / ST_HOLD: duration
    cmp #$FF
    beq sc_env                  ; for ever
    lda c_d20,x
    clc
    adc s_cs
    sta c_d20,x
sc_d20:
    lda c_d20,x
    cmp #5
    bcc sc_env
    sbc #5
    sta c_d20,x
    lda c_dur,x
    beq sc_end
    dec c_dur,x
    bne sc_d20
sc_end:
    jsr s_noteend
    ldx s_ch
sc_env:
    .if SIDIMG = 0
    lda c_state,x
    beq sc_next
    jsr s_chanenv
    ldx s_ch
    .endif
sc_next:
    lda c_state,x               ; free (idle or releasing): next note
    cmp #ST_PLAY
    beq sc_rts
    cmp #ST_HOLD
    beq sc_rts
    lda c_qn,x
    beq sc_rts
    jsr s_qhead                 ; Y = head of the queue
    lda q_ctl,y                 ; sync count
    and #QF_SYNC
    beq sc_go
    sta c_wait,x                ; waits for s_sync
    rts
sc_go:
    jmp s_start
sc_rts:
    rts

; s_sync: notes waiting for sync start when S+1 voices wait with S
s_sync:
    ldx #NV-1
ss_ch:
    lda c_wait,x
    beq ss_next
    sta s_sv                    ; count the voices waiting with this S
    ldy #NV-1
    lda #0
    sta s_tmp
ss_cnt:
    lda c_wait,y
    cmp s_sv
    bne ss_cn
    inc s_tmp
ss_cn:
    dey
    bpl ss_cnt
    lda s_tmp
    cmp s_sv
    beq ss_next                 ; not yet: S+1 needed
    bcc ss_next
    ldy #NV-1                   ; start them all
ss_go:
    lda c_wait,y
    cmp s_sv
    bne ss_gn
    lda #0
    sta c_wait,y
    stx s_ch2
    tya
    tax
    stx s_ch
    jsr s_start
    ldx s_ch2
    ldy s_ch
ss_gn:
    dey
    bpl ss_go
ss_next:
    dex
    bpl ss_ch
    rts

; ----------------------------------------------------------------------------
; s_start
;   Summary: take the head note of voice X's queue and start it.
;   Function: hold notes keep the sound and let the release run for their
;            duration; other notes: s_note of the image.
;   Uses:    A, X (kept), Y.
s_start:
    jsr s_qhead
    lda q_ctl,y
    sta s_ctl
    lda q_amp,y
    sta s_amp
    lda q_plo,y
    sta s_plo
    lda q_phi,y
    sta s_phi
    lda q_dur,y
    sta c_dur,x
    .if SIDIMG = 1
    lda q_lvl,y
    sta s_lvl
    .endif
    lda c_qr,x                  ; pop
    clc
    adc #1
    cmp #QLEN
    bcc sst_qr
    lda #0
sst_qr:
    sta c_qr,x
    dec c_qn,x
    lda #0
    sta c_d20,x
    sta c_wait,x
    lda s_ctl                   ; hold: the release goes on
    and #QF_HOLD
    beq sst_new
    lda c_state,x
    beq sst_held                ; (nothing sounding: a silent wait)
    .if SIDIMG = 0
    lda #3                      ; (the previous note's release)
    sta c_phase,x
    .endif
    lda #ST_HOLD
    sta c_state,x
    rts
sst_held:
    lda #ST_HOLD
    sta c_state,x
    .if SIDIMG = 0
    lda #0
    sta c_env,x
    .endif
    rts
sst_new:
    jmp s_note

; ----------------------------------------------------------------------------
; The image's own part

    .if SIDIMG = 0
    icl 'sound_bbc.s'
    .else
    icl 'sound_sid.s'
    .endif

; ----------------------------------------------------------------------------
; Common hardware helpers

; s_q2f: s_flo/hi = Q (quarter semitones, 288 = middle C) -> SID frequency
; from ftab (the octave of middle C), shifted per octave (clamped)
s_q2f:
    ldy #0                      ; octave = Q DIV 48
sq2_div:
    lda s_flo
    sec
    sbc #48
    pha
    lda s_fhi
    sbc #0
    bcc sq2_done
    sta s_fhi
    pla
    sta s_flo
    iny
    bne sq2_div
sq2_done:
    pla
    sty s_t                     ; octave 0-..
    ldy s_flo                   ; 0-47
    lda ftab_lo,y
    sta s_flo
    lda ftab_hi,y
    sta s_fhi
    lda s_t
    cmp #6
    beq sq2_rts
    bcc sq2_down
sq2_up:
    asl s_flo                   ; octaves above: double, clamped
    rol s_fhi
    bcs sq2_max
    dec s_t
    lda s_t
    cmp #6
    bne sq2_up
sq2_rts:
    rts
sq2_max:
    lda #$FF
    sta s_flo
    sta s_fhi
    rts
sq2_down:
    lsr s_fhi                   ; octaves below: halve
    ror s_flo
    inc s_t
    lda s_t
    cmp #6
    bne sq2_down
    rts

; s_vmap: point s_w at voice X's SID voice (s_vdummy: at a dummy, for
; voices beyond the SIDs found)
s_vmap:
    lda c_sid,x
    bmi s_vdummy
    jsr s_sidbase
    lda c_voff,x
    clc
    adc sw_op+1
    sta sw_op+1
    bcc sv_rts
    inc sw_op+2
sv_rts:
    rts
s_vdummy:
    lda #<s_dummy
    sta sw_op+1
    lda #>s_dummy
    sta sw_op+2
    rts

; s_sidbase: s_w at SID A's base
s_sidbase:
    tay
    lda s_sidlo,y
    sta sw_op+1
    lda s_sidhi,y
    sta sw_op+2
    rts

; s_w: SID register Y (of the voice / SID chosen) = A
s_w:
sw_op:
    sta $D400,y
    rts

; ----------------------------------------------------------------------------
; Queue helpers

; s_qhead: Y = voice X's head entry (X * QLEN + read index)
s_qhead:
    txa
    sta s_tmp
    asl
    adc s_tmp                   ; X * 3 (QLEN)
    adc c_qr,x
    tay
    rts

; s_put
;   Summary: queue the note in s_qbuf (ctl, amp, plo, phi, dur) on
;            voice X.
;   Output:  C = 1 if the queue is full (nothing queued).
;   Uses:    A, X (kept), Y.
s_put:
    php
    sei
    lda c_qn,x
    cmp #QLEN
    bcs sp_full
    lda c_qr,x                  ; Y = X * 3 + (read + count) MOD 3
    clc
    adc c_qn,x
    cmp #QLEN
    bcc sp_i
    sbc #QLEN
sp_i:
    sta s_tmp2
    txa
    sta s_tmp
    asl
    adc s_tmp
    adc s_tmp2
    tay
    lda s_qbuf+0
    sta q_ctl,y
    lda s_qbuf+1
    sta q_amp,y
    lda s_qbuf+2
    sta q_plo,y
    lda s_qbuf+3
    sta q_phi,y
    lda s_qbuf+4
    sta q_dur,y
    .if SIDIMG = 1
    lda s_qlvl
    sta q_lvl,y
    .endif
    inc c_qn,x
    plp
    clc
    rts
sp_full:
    plp
    sec
    rts

; s_flush: voice X's queue emptied and its sound stopped
s_flush:
    php
    sei
    stx s_ch
    lda #0
    sta c_qn,x
    sta c_qr,x
    sta c_wait,x
    lda c_state,x
    beq sfl_done
    lda #ST_IDLE
    sta c_state,x
    jsr s_gateoff
sfl_done:
    ldx s_ch
    plp
    rts

; s_adval: X = voice: X = free queue bytes (15 empty, as MOS 1.20's
; 16-byte buffers; 4 per note)
s_adval:
    lda c_qn,x
    asl
    asl
    eor #$FF
    sec
    adc #15
    tax
    rts

; s_stopall: every voice silent, queues empty
s_stopall:
    ldx #NV-1
sa_ch:
    jsr s_flush
    dex
    bpl sa_ch
    rts

; s_bell: VDU 7 as the BBC's default bell: SOUND &13,-15,101,6 (BBC mode:
; channel 3; SID mode: voice 2); dropped if that queue is full
s_bell:
    lda s_off
    bne sb_rts
    ldx #4
sb_copy:
    lda bell_q,x
    sta s_qbuf,x
    dex
    bpl sb_copy
    lda #0                      ; (no level of its own)
    sta s_qlvl
    ldx #2
    lda #SIDIMG
    bne sb_put
    ldx #3
sb_put:
    jmp s_put
sb_rts:
    rts
bell_q:
    dta 0, -15, 101, 0, 6


; ----------------------------------------------------------------------------
; Variables (not in the image: after it; cleared by snd_load)

s_vars      = *
s_ihdr      = s_vars            ; IHDR: instrument header being loaded
s_share     = s_ihdr+IHDR       ; BBC: slot 0 shares slot 3's voice
s_lastt     = s_share+1         ; TIME low byte at the last interrupt
s_cs        = s_lastt+1         ; centiseconds this interrupt
s_ch        = s_cs+1            ; voice being processed
s_ch2       = s_ch+1
s_t         = s_ch2+1           ; scratch (interrupt)
s_per       = s_t+1             ; envelope step period (cs)
s_sv        = s_per+1           ; sync value being started (s_sync)
s_tmp       = s_sv+1
s_tmp2      = s_tmp+1
s_tgt       = s_tmp2+1
s_eo        = s_tgt+1
s_ctl       = s_eo+1
s_amp       = s_ctl+1
s_plo       = s_amp+1
s_phi       = s_plo+1
s_wave      = s_phi+1
s_flo       = s_wave+1
s_fhi       = s_flo+1
s_dummy     = s_fhi+1           ; 7: writes of a muted voice
c_state     = s_dummy+7         ; per voice (NV each)
c_qn        = c_state+NV        ; notes queued
c_qr        = c_qn+NV           ; queue read index
c_wait      = c_qr+NV           ; waiting for sync (S)
c_dur       = c_wait+NV         ; duration left, 1/20 s (255: for ever)
c_d20       = c_dur+NV          ; centiseconds towards the next 1/20 s
c_plo       = c_d20+NV          ; pitch (BBC: 0-255; SID: signed 16 bits)
c_phi       = c_plo+NV
c_wave      = c_phi+NV          ; waveform (control register, gate 0)
c_sid       = c_wave+NV         ; SID of the voice ($FF: none)
c_voff      = c_sid+NV          ; voice offset 0, 7, 14
q_ctl       = c_voff+NV         ; queue: NV * QLEN each
q_amp       = q_ctl+NV*QLEN
q_plo       = q_amp+NV*QLEN
q_phi       = q_plo+NV*QLEN
q_dur       = q_phi+NV*QLEN
v_img       = q_dur+NV*QLEN     ; the image's own variables

    .if SIDIMG = 0
c_env       = v_img             ; BBC envelope 1-16, 0 none
c_lvl       = c_env+NV          ; BBC amplitude 0-126
c_phase     = c_lvl+NV          ; 0 attack, 1 decay, 2 sustain, 3 release, 4 done
c_psec      = c_phase+NV        ; pitch section 0-2 (3: done)
c_pcnt      = c_psec+NV         ; steps left in the section
c_tcnt      = c_pcnt+NV         ; centiseconds towards the next step
c_vol       = c_tcnt+NV         ; SID sustain level shown
env         = c_vol+NV          ; 16 envelopes x 13 bytes
s_end       = env+16*13
    .else
c_inst      = v_img             ; instrument 1-64
c_ad        = c_inst+NV         ; its attack/decay
c_srbase    = c_ad+NV           ; its sustain/release
c_sr        = c_srbase+NV       ; sustain/release of this note
c_pwlo      = c_sr+NV           ; pulse width
c_pwhi      = c_pwlo+NV
c_filt      = c_pwhi+NV         ; filter: bit 0 on, bits 4-6 mode
c_fres      = c_filt+NV         ; resonance
c_fcut      = c_fres+NV         ; cutoff (high 8 bits)
c_mod       = c_fcut+NV         ; modulation running (CM_ bits)
c_pwrate    = c_mod+NV          ; pulse sweep: rate (signed), top, bottom
c_pwtop     = c_pwrate+NV
c_pwbot     = c_pwtop+NV
c_vdel      = c_pwbot+NV        ; vibrato: delay, width, rate
c_vwid      = c_vdel+NV
c_vrate     = c_vwid+NV
c_vcnt      = c_vrate+NV        ; delay left
c_vph       = c_vcnt+NV         ; phase
c_porta     = c_vph+NV          ; portamento speed
c_ctrate    = c_porta+NV        ; cutoff sweep: rate (signed), top, bottom
c_cttop     = c_ctrate+NV
c_ctbot     = c_cttop+NV
c_fine      = c_ctbot+NV        ; finetune (signed, 1/64 semitone)
c_flags     = c_fine+NV         ; bit 0 hard restart, bit 1 cutoff stops
c_tabw      = c_flags+NV        ; first wave table byte (0: no tables)
c_tspd      = c_tabw+NV         ; table speed (interrupts per step)
c_tcnt      = c_tspd+NV         ; interrupts to the next step
c_tidx      = c_tcnt+NV         ; table step
c_arp       = c_tidx+NV         ; arpeggio offset (semitones, signed)
c_pitlo     = c_arp+NV          ; pitch now (1/64 semitones)
c_pithi     = c_pitlo+NV
c_tgtlo     = c_pithi+NV        ; pitch to reach (portamento), or raw
c_tgthi     = c_tgtlo+NV        ; frequency
                                ; (s_dirty .. s_tmpx: SNDSHR, defs.s)
t_on        = c_tgthi+NV        ; the song plays
t_acc       = t_on+1            ; 2: cs * 256 towards the next row
t_rlen      = t_acc+2           ; 2: row length, cs * 256
t_n         = t_rlen+2          ; rows left this interrupt
t_row       = t_n+1             ; row in the pattern (0: load the pattern)
t_rows      = t_row+1           ; rows in the pattern
t_ord       = t_rows+1          ; order list position
t_len       = t_ord+1           ; order list length
t_loop      = t_len+1           ; loop to this position (>= t_len: stop)
t_pat       = t_loop+1          ; the pattern playing
t_ptr       = t_pat+1           ; 3: REU address of the next row
t_y         = t_ptr+3
t_buf       = t_y+1             ; 72: the row
s_lvl       = t_buf+72          ; the note's level (s_note; 0: the
                                ; instrument's own)
q_lvl       = s_lvl+1           ; queue: levels, NV * QLEN
s_end       = q_lvl+NV*QLEN
    .endif

    .if s_end > SNDSHR
    .error "Sound engine image overflows into the shared sound data"
    .endif
