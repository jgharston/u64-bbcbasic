; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- sound engine, assembled for SOUNDRAM ($0800)
;
; Copied to RAM at start-up by snd_install (ulbank.s, bank 4). Design:
; docs/DESIGN_SOUND.md. This first part is the BBC mode (section 2.1):
; channels 0 (noise) and 1-3 (tone) as on a BBC Micro, with its 3-note
; queues, flush, sync, hold and ENVELOPE, on the SID voices.
;
; Behaviour follows the BBC MOS 1.20 sound code (Toby Lobster's
; annotated disassembly, tobylobster.github.io/mos, chapter 16):
; durations in 1/20 s counted in 5-centisecond units, 255 = for ever;
; envelope steps every T centiseconds, pitch in three sections (repeated
; unless T bit 7), amplitude phases attack, decay, sustain, release; at
; the end of a note the next queued note starts at once, otherwise the
; release phase plays. Adapted: written anew for the SID (software
; amplitude through the sustain level, see s_hwvol).
;
; The interrupt part (s_irq) uses no zero page: absolute addressing,
; the SID writes through a patched address (s_w). It runs in RAM, so the
; self-modifying code is allowed.
;
; ----------------------------------------------------------------------------

    .local snd

NCH         = 4                 ; channels (BBC mode)
QLEN        = 3                 ; queued notes per channel (MOS 1.20: 15 bytes)

; channel states
ST_IDLE     = 0
ST_PLAY     = 1                 ; note sounding, duration running
ST_REL      = 2                 ; duration over, envelope releasing
ST_HOLD     = 3                 ; a hold note: duration runs, release goes on

; ----------------------------------------------------------------------------
; Entry points (SOUNDRAM + n)

    jmp s_init                  ; +0  reset all channels, SID volumes
    jmp s_irq                   ; +3  from the interrupt
    jmp s_sound                 ; +6  OSWORD 7 (block at mosPTR)
    jmp s_env                   ; +9  OSWORD 8 (block at mosPTR)
    jmp s_adval                 ; +12 X = channel: X = free queue bytes
    jmp s_stopall               ; +15 silence, empty the queues
    jmp s_probe                 ; +18 find the SIDs
    jmp s_bell                  ; +21 VDU 7

; ----------------------------------------------------------------------------
; s_init
;   Summary: all channels idle, queues empty, the SIDs' volume at 15,
;            channels mapped to SID voices.
;   Function: channels 1-3 = SID 0 voices 0-2; channel 0 (noise) = SID 1
;            voice 0 when there are 2+ SIDs, else SID 0 voice 2 (shared
;            with channel 3: channel 0 has it while it plays).
;   Uses:    A, X, Y.
s_init:
    php
    sei
    ldx #NCH-1
si_clr:
    lda #0
    sta c_state,x
    sta c_qn,x
    sta c_qr,x
    sta c_wait,x
    sta c_vol,x
    sta c_env,x
    dex
    bpl si_clr
    lda #0                      ; channel -> SID, voice offset
    sta c_sid+1
    sta c_sid+2
    sta c_sid+3
    sta c_voff+1
    lda #7
    sta c_voff+2
    lda #14
    sta c_voff+3
    lda #0
    sta s_share
    ldx s_nsid
    cpx #2
    bcc si_one
    lda #1                      ; noise on SID 1 voice 0
    sta c_sid
    lda #0
    sta c_voff
    beq si_vol
si_one:
    lda #0                      ; noise shares SID 0 voice 2
    sta c_sid
    lda #14
    sta c_voff
    inc s_share
si_vol:
    ldx s_nsid                  ; every SID: voices off, volume 15
    beq si_done
si_sid:
    dex
    stx s_tmp
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
;            interrupt both work); at most 10 per call.
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
    ldx #NCH-1
sq_ch:
    stx s_ch
    jsr s_chan
    ldx s_ch
    dex
    bpl sq_ch
    jsr s_sync
sq_rts:
    rts

; s_chan: one channel (X): duration, envelope, next note
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
    lda c_state,x               ; envelope steps every T cs
    beq sc_next
    lda c_env,x
    beq sc_next
    jsr s_envptr                ; Y = envelope offset
    lda env+0,y                 ; T (bits 0-6), at least 1
    and #$7F
    bne sc_t
    lda #1
sc_t:
    sta s_per
    lda c_tcnt,x
    clc
    adc s_cs
    sta c_tcnt,x
sc_step:
    lda c_tcnt,x
    cmp s_per
    bcc sc_next
    sbc s_per
    sta c_tcnt,x
    jsr s_estep
    ldx s_ch
    lda c_state,x
    bne sc_step
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
    and #3
    beq sc_go
    sta c_wait,x                ; waits for s_sync
    rts
sc_go:
    jmp s_start
sc_rts:
    rts

; s_noteend: channel X's duration is over. A queued note follows at once
; (s_chan's next step); else the release phase (envelope), or off.
s_noteend:
    lda c_env,x
    beq sne_off
    lda #3                      ; envelope: the release phase (cut short
    sta c_phase,x               ; when the next note starts)
    lda #ST_REL
    sta c_state,x
    rts
sne_off:
    lda #ST_IDLE
    sta c_state,x
    jmp s_gateoff

; s_sync: notes waiting for sync start when S+1 channels wait with S
s_sync:
    ldx #NCH-1
ss_ch:
    lda c_wait,x
    beq ss_next
    sta s_sv                    ; count the channels waiting with this S
    ldy #NCH-1
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
    ldy #NCH-1                  ; start them all
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
;   Summary: take the head note of channel X's queue and start it.
;   Function: hold notes (H) keep the sound and run the release for their
;            duration; envelope notes (A = 1-16) start their envelope
;            from the current level when they interrupt a release (BBC
;            amplitude continuity), else from 0; A = -15..0 sets the
;            level (-A * 8, BBC volume -A).
;   Uses:    A, X (kept), Y.
s_start:
    jsr s_qhead
    lda q_ctl,y
    sta s_t
    lda q_amp,y
    sta s_amp
    lda q_pit,y
    sta s_pit
    lda q_dur,y
    sta c_dur,x
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
    lda s_t                     ; hold: the release goes on
    and #4
    beq sst_new
    lda c_state,x
    beq sst_held                ; (nothing sounding: a silent wait)
    lda #3                      ; the previous note's release goes on
    sta c_phase,x
    lda #ST_HOLD
    sta c_state,x
    rts
sst_held:
    lda #ST_HOLD
    sta c_state,x
    lda #0
    sta c_env,x
    rts
sst_new:
    lda s_pit
    sta c_pitch,x
    lda s_amp
    beq sst_fixed
    bmi sst_fixed
    cmp #17                     ; envelope 1-16
    bcs sst_fixed
    ldy c_state,x               ; level: kept if a release is cut short
    cpy #ST_REL
    beq sst_keep
    pha
    lda #0
    sta c_lvl,x
    pla
sst_keep:
    sta c_env,x
    lda #0
    sta c_phase,x
    sta c_psec,x
    sta c_tcnt,x
    jsr s_envptr
    lda env+4,y                 ; PN1
    sta c_pcnt,x
    jmp sst_sound
sst_fixed:
    lda #0                      ; level = -A * 8
    sta c_env,x
    sec
    sbc s_amp
    and #15
    asl
    asl
    asl
    sta c_lvl,x
sst_sound:
    lda #ST_PLAY
    sta c_state,x
    lda #0                      ; a new note: attack from the start
    sta c_vol,x
    jsr s_hwstart
    ldx s_ch
    rts

; ----------------------------------------------------------------------------
; s_estep
;   Summary: one envelope step of channel X: pitch, then amplitude.
;   Function: pitch: + PI of the section, PN steps per section, after
;            section 3 back to 1 unless T bit 7. Amplitude: attack (AA to
;            ALA), decay (AD to ALD), sustain (AS, to 0 at most), release
;            (AR to 0, then the channel is free and silent).
;   Uses:    A, X (kept), Y.
s_estep:
    jsr s_envptr
    sty s_eo
    lda #0
    sta s_tmp                   ; empty pitch sections passed
    lda c_psec,x                ; pitch
    cmp #3
    bcs se_amp
se_pitch:
    lda c_pcnt,x
    bne se_padd
    inc c_psec,x                ; next section (PN = 0: skipped)
    lda c_psec,x
    cmp #3
    bcc se_pload
    lda env+0,y                 ; repeat unless T bit 7
    bmi se_amp
    lda #0
    sta c_psec,x
se_pload:
    lda c_psec,x
    clc
    adc s_eo
    tay
    lda env+4,y                 ; PN of the section
    sta c_pcnt,x
    ldy s_eo
    inc s_tmp                   ; (at most 3 empty sections in a row)
    lda s_tmp
    cmp #4
    bcc se_pitch
    bcs se_amp
se_padd:
    dec c_pcnt,x
    lda c_psec,x
    clc
    adc s_eo
    tay
    lda env+1,y                 ; PI of the section
    clc
    adc c_pitch,x
    sta c_pitch,x
    jsr s_hwfreq
    ldx s_ch
se_amp:
    lda #0
    sta s_tmp
    ldy s_eo
    lda c_phase,x
    cmp #4
    bcs se_done
    cmp #3
    beq se_rel
    cmp #2
    beq se_sus
    cmp #1
    beq se_dec
    lda env+7,y                 ; attack: AA towards ALA
    sta s_t
    lda env+11,y
    jmp se_move
se_dec:
    lda env+8,y                 ; decay: AD towards ALD
    sta s_t
    lda env+12,y
    jmp se_move
se_sus:
    lda env+9,y                 ; sustain: AS, no phase change
    sta s_t
    lda #0
    jsr se_mv
    jmp se_vol
se_rel:
    lda env+10,y                ; release: AR towards 0
    sta s_t
    lda #0
se_move:
    jsr se_mv
    bcc se_vol
    inc c_phase,x               ; target reached: next phase
    lda c_phase,x
    cmp #4
    bcc se_vol
    lda #ST_IDLE                ; release over
    sta c_state,x
    jmp s_gateoff
se_vol:
    jsr s_hwvol
    ldx s_ch
se_done:
    rts

; se_mv: level += step (s_t, signed) towards target A, limits 0..126.
; C = 1 if the target was reached (level = target).
se_mv:
    sta s_tgt
    lda s_t
    beq sm_no
    bmi sm_down
    lda c_lvl,x                 ; up
    clc
    adc s_t
    cmp s_tgt
    bcs sm_hit
    cmp #127
    bcs sm_top
    sta c_lvl,x
sm_no:
    clc
    rts
sm_top:
    lda #126
    sta c_lvl,x
    clc
    rts
sm_down:
    lda c_lvl,x
    clc
    adc s_t                     ; (adding a negative step)
    bcc sm_hit                  ; below 0
    cmp s_tgt
    bcc sm_hit
    beq sm_hit
    sta c_lvl,x
    clc
    rts
sm_hit:
    lda s_tgt
    sta c_lvl,x
    sec
    rts

; ----------------------------------------------------------------------------
; Hardware: channel X's SID voice

; s_hwstart: waveform, pulse width, ADSR, frequency, level of a new note
s_hwstart:
    jsr s_voice
    lda #$41                    ; pulse (tone channels; BBC square wave)
    sta s_wave
    lda #$08                    ; 50%
    ldy #3
    jsr s_w
    lda #0
    ldy #2
    jsr s_w
    cpx #0
    bne sh_tone
    lda c_pitch,x               ; noise channel: P AND 7
    and #4
    beq sh_per
    lda #$81                    ; white noise
    sta s_wave
    bne sh_tone
sh_per:
    lda #$01                    ; periodic: 1/16 duty pulse
    ldy #3
    jsr s_w
sh_tone:
    lda s_wave
    and #$FE
    sta c_wave,x
    lda #$00                    ; attack 2 ms, decay 6 ms
    ldy #5
    jsr s_w
    jsr s_hwfreq
    ldx s_ch
    jmp s_hwvol

; s_hwfreq: frequency from c_pitch (tone: the BBC pitch table; noise:
; P AND 7 as the BBC's noise types)
s_hwfreq:
    jsr s_voice
    cpx #0
    beq shf_noise
    ldy c_pitch,x
    lda ptab_lo,y
    sta s_flo
    lda ptab_hi,y
    sta s_fhi
    jmp shf_set
shf_noise:
    lda c_pitch,x
    and #3
    cmp #3
    beq shf_ch1
    tay
    lda c_pitch,x
    and #4
    beq shf_p
    iny                         ; white: entries 3-5
    iny
    iny
shf_p:
    lda ntab_lo,y
    sta s_flo
    lda ntab_hi,y
    sta s_fhi
    jmp shf_set
shf_ch1:
    ldy c_pitch+1               ; P = 3, 7: channel 1's frequency / 16
    lda ptab_hi,y
    sta s_fhi
    lda ptab_lo,y
    lsr s_fhi
    ror
    lsr s_fhi
    ror
    lsr s_fhi
    ror
    lsr s_fhi
    ror
    sta s_flo
shf_set:
    lda s_flo
    ldy #0
    jsr s_w
    lda s_fhi
    ldy #1
    jmp s_w

; s_hwvol
;   Summary: show channel X's level (c_lvl 0-126) on the SID.
;   Function: BBC volume = level / 8 (0-15), through vtab to a SID
;            sustain level (the BBC's 2 dB steps on the SID's linear
;            scale). Lower: the new sustain level (the SID decays to it);
;            higher: sustain set and the gate retriggered (attack 2 ms
;            to full, decay 6 ms to it); 0: gate off.
;   Uses:    A, Y.
s_hwvol:
    lda c_lvl,x
    lsr
    lsr
    lsr
    tay
    lda vtab,y
    cmp c_vol,x
    beq shv_rts
    sta s_t
    jsr s_voice
    lda s_t
    beq shv_off
    asl                         ; sustain in the high nybble, release 0
    asl
    asl
    asl
    ldy #6
    jsr s_w
    lda s_t
    cmp c_vol,x
    sta c_vol,x
    bcc shv_rts                 ; lower: the SID decays to it
    lda c_wave,x                ; higher: retrigger
    ldy #4
    jsr s_w
    ora #1
    jmp s_w
shv_off:
    sta c_vol,x
s_gateoff:
    jsr s_voice
    lda c_wave,x
    ldy #4
    jmp s_w
shv_rts:
    rts

; s_voice: point s_w at channel X's voice (or at a dummy while channel 0
; has the voice it shares with channel 3)
s_voice:
    cpx #3
    bne sv_map
    lda s_share
    beq sv_map
    lda c_state                 ; channel 0 playing: channel 3 is mute
    beq sv_map
    lda #<s_dummy
    sta sw_op+1
    lda #>s_dummy
    sta sw_op+2
    rts
sv_map:
    lda c_sid,x
    jsr s_sidbase
    lda c_voff,x
    clc
    adc sw_op+1
    sta sw_op+1
    bcc sv_rts
    inc sw_op+2
sv_rts:
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
; Queue and envelope helpers

; s_qhead: Y = channel X's head entry (X * QLEN + read index)
s_qhead:
    txa
    sta s_tmp
    asl
    adc s_tmp                   ; X * 3 (QLEN)
    adc c_qr,x
    tay
    rts

; s_envptr: Y = offset of channel X's envelope (c_env 1-16) in env
s_envptr:
    ldy c_env,x
    lda env_ofs-1,y
    tay
    rts

; ----------------------------------------------------------------------------
; s_sound (OSWORD 7)
;   Summary: SOUND C,A,P,D: queue a note (BBC mode).
;   Function: C = &HSFN: N AND 3 = channel, F <> 0 flush (queue emptied,
;            the sound stopped), S = sync (0-3), H = hold. Waits while
;            the queue is full (ESCAPE ends the wait).
;   Input:   mosPTR = block: C, A, P, D (16 bits each).
;   Uses:    A, X, Y.
s_sound:
    lda s_off
    bne ssd_rts
    ldy #0
    lda (mosPTR),y
    and #3
    tax
    lda (mosPTR),y              ; F: flush
    and #$F0
    beq ssd_wait
    php
    sei
    lda #0
    sta c_qn,x
    sta c_qr,x
    sta c_wait,x
    lda c_state,x
    beq ssd_fl
    lda #ST_IDLE
    sta c_state,x
    stx s_ch
    jsr s_gateoff
    ldx s_ch
ssd_fl:
    plp
ssd_wait:
    lda c_qn,x                  ; room? (the interrupt frees it)
    cmp #QLEN
    bcc ssd_put
    bit ESCFLG
    bpl ssd_wait
ssd_rts:
    rts
ssd_put:
    php
    sei
    stx s_ch2
    lda c_qr,x                  ; Y = X * 3 + (read + count) MOD 3
    clc
    adc c_qn,x
    cmp #QLEN
    bcc ssd_i
    sbc #QLEN
ssd_i:
    sta s_tmp2
    txa
    sta s_tmp
    asl
    adc s_tmp
    adc s_tmp2
    tax
    ldy #1                      ; ctl = S (bits 0-1) + H (bit 2)
    lda (mosPTR),y
    and #3
    sta q_ctl,x
    lda (mosPTR),y
    and #$F0
    beq ssd_nh
    lda q_ctl,x
    ora #4
    sta q_ctl,x
ssd_nh:
    ldy #2
    lda (mosPTR),y
    sta q_amp,x
    ldy #4
    lda (mosPTR),y
    sta q_pit,x
    ldy #6
    lda (mosPTR),y
    sta q_dur,x
    ldx s_ch2
    inc c_qn,x
    plp
    rts

; s_env (OSWORD 8): ENVELOPE N,13 parameters (N 1-16)
s_env:
    ldy #0
    lda (mosPTR),y
    beq sen_rts
    cmp #17
    bcs sen_rts
    tax
    lda env_ofs-1,x
    tax
    php
    sei
    ldy #1
sen_copy:
    lda (mosPTR),y
    sta env,x
    inx
    iny
    cpy #14
    bne sen_copy
    plp
sen_rts:
    rts

; s_adval: X = channel 0-3 (BBC): X = free queue bytes (15 empty, as
; MOS 1.20's 16-byte buffers; 4 per note)
s_adval:
    txa
    and #3
    tax
    lda c_qn,x
    asl
    asl
    eor #$FF
    sec
    adc #15
    tax
    rts

; s_stopall: every channel silent, queues empty
s_stopall:
    php
    sei
    ldx #NCH-1
sa_ch:
    stx s_ch
    lda #0
    sta c_qn,x
    sta c_qr,x
    sta c_wait,x
    sta c_state,x
    jsr s_gateoff
    ldx s_ch
    dex
    bpl sa_ch
    plp
    rts

; s_bell: VDU 7 as the BBC's default bell: SOUND &13,-15,101,6 (channel 3)
s_bell:
    lda mosPTR
    pha
    lda mosPTR+1
    pha
    lda #<bell_blk
    sta mosPTR
    lda #>bell_blk
    sta mosPTR+1
    jsr s_sound
    pla
    sta mosPTR+1
    pla
    sta mosPTR
    rts
bell_blk:
    dta a($0003), a(-15), a(101), a(6)

; ----------------------------------------------------------------------------
; s_probe
;   Summary: find the SIDs (up to 8) at $D400-$D7E0, the 8SID layout's
;            addresses first.
;   Function: a SID is at B if voice 3's oscillator (saw, highest
;            frequency) holds still at OSC3 ($1B) with the TEST bit (0 on
;            a SID or UltiSID, 255 on an ARMSID), changes without it and
;            stops again with it; it is a new one if running it does not
;            run a SID found before (mirrors). The display is off
;            meanwhile, so open-bus reads hold still too and never pass. $D400 is always first.
;            $DE00-$DFFF is not probed (cartridge, REU, UCI, Ultimate
;            Audio live there); *SID adds SIDs there by hand.
;   Output:  s_nsid, s_sidlo/hi.  Uses: A, X, Y.
s_probe:
    php
    sei
    lda $D011                   ; display off: the VIC-II's fetches would
    pha                         ; make open-bus reads look like a SID
    and #$EF
    sta $D011
    lda #0
    sta s_nsid
    sta s_pi
sp_cand:
    ldx s_pi                    ; next candidate address
    lda sp_cands,x
    sta s_pa+1
    lda sp_candl,x
    sta s_pa
    jsr sp_test
    bcc sp_next
    ldx s_nsid                  ; a new SID
    lda s_pa
    sta s_sidlo,x
    lda s_pa+1
    sta s_sidhi,x
    inc s_nsid
    lda s_nsid
    cmp #8
    bcs sp_end
sp_next:
    inc s_pi
    lda s_pi
    cmp #SP_NCAND
    bcc sp_cand
sp_end:
    ldx s_nsid                  ; voice 3 of every SID found: off
sp_off:
    dex
    bmi sp_done
    txa
    jsr s_sidbase
    lda #0
    ldy #$12
    jsr s_w
    ldy #$0E
    jsr s_w
    ldy #$0F
    jsr s_w
    jmp sp_off
sp_done:
    lda s_nsid                  ; none (unusual): assume $D400
    bne sp_rts
    lda #<$D400
    sta s_sidlo
    lda #>$D400
    sta s_sidhi
    inc s_nsid
sp_rts:
    pla
    sta $D011
    plp
    rts

; sp_test: C = 1 if a new SID is at s_pa
sp_test:
    lda s_pa
    sta sw_op+1
    lda s_pa+1
    sta sw_op+2
    lda #$FF                    ; voice 3: highest frequency, saw + TEST
    ldy #$0E
    jsr s_w
    ldy #$0F
    jsr s_w
    lda #$28
    ldy #$12
    jsr s_w
    jsr sp_still                ; TEST: OSC3 holds still (0 on a SID
    bne sp_no                   ; or UltiSID, 255 on an ARMSID)
    lda #$20                    ; running: it must change
    ldy #$12
    jsr s_w
    jsr sp_delay
    jsr sp_read
    sta s_tmp
    jsr sp_delay
    jsr sp_read
    cmp s_tmp
    bne sp_runs
    jsr sp_delay
    jsr sp_read
    cmp s_tmp
    beq sp_stop                 ; does not run
sp_runs:
    lda #$28                    ; TEST again: it must stop
    ldy #$12
    jsr s_w
    jsr sp_still
    bne sp_no
    lda #$20
    ldy #$12
    jsr s_w
    ldx s_nsid                  ; a mirror of a SID found before?
sp_mir:
    dex
    bmi sp_new
    lda s_sidlo,x
    sta sp_rd+1
    lda s_sidhi,x
    sta sp_rd+2
    jsr sp_rd0
    sta s_tmp
    jsr sp_delay
    jsr sp_rd0
    cmp s_tmp
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
    lda s_pa                    ; back to saw + TEST
    sta sw_op+1
    lda s_pa+1
    sta sw_op+2
    lda #$28
    ldy #$12
    jsr s_w
    clc
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

; sp_still: Z = 1 if OSC3 at s_pa reads the same three times
sp_still:
    jsr sp_delay
    jsr sp_read
    sta s_tmp
    jsr sp_delay
    jsr sp_read
    cmp s_tmp
    bne sps_rts
    jsr sp_delay
    jsr sp_read
    cmp s_tmp
sps_rts:
    rts

; sp_read: A = OSC3 of the SID at s_pa; sp_rd0: of the address in sp_rd
sp_read:
    lda s_pa
    sta sp_rd+1
    lda s_pa+1
    sta sp_rd+2
sp_rd0:
    ldy #$1B
sp_rd:
    lda $D400,y
    rts

; sp_delay: some SID clock cycles, also at 64 MHz
sp_delay:
    ldx #0
spd_loop:
    nop
    nop
    dex
    bne spd_loop
    rts

; ----------------------------------------------------------------------------
; Tables

; BBC volume 0-15 -> SID sustain level (2 dB steps, linear SID scale)
vtab:
    dta 0, 1, 1, 1, 1, 2, 2, 2, 3, 4, 5, 6, 8, 9, 12, 15

; envelope N -> offset in env (13 bytes each)
env_ofs:
    :16 dta #*13

; noise frequencies: periodic (shift rate / 15) and white (shift rate),
; for the BBC's 7812.5, 3906.25 and 1953.125 Hz; filled by snd_install
; for PAL or NTSC along with the pitch table
ntab_lo     :6 dta 0
ntab_hi     :6 dta 0

; ----------------------------------------------------------------------------
; Variables (not in the image: after it)

s_vars      = *
s_nsid      = s_vars            ; SIDs found
s_sidlo     = s_nsid+1          ; 8: SID base addresses
s_sidhi     = s_sidlo+8         ; 8
s_off       = s_sidhi+8         ; *SOUND OFF
s_share     = s_off+1           ; channel 0 shares channel 3's voice
s_lastt     = s_share+1         ; TIME low byte at the last interrupt
s_cs        = s_lastt+1         ; centiseconds this interrupt
s_ch        = s_cs+1            ; channel being processed
s_ch2       = s_ch+1
s_t         = s_ch2+1           ; scratch (interrupt)
s_per       = s_t+1             ; envelope step period (cs)
s_sv        = s_per+1           ; sync value being started (s_sync)
s_tmp       = s_sv+1
s_tmp2      = s_tmp+1
s_tgt       = s_tmp2+1
s_eo        = s_tgt+1
s_amp       = s_eo+1
s_pit       = s_amp+1
s_wave      = s_pit+1
s_flo       = s_wave+1
s_fhi       = s_flo+1
s_pa        = s_fhi+1           ; 2: probe address
s_pi        = s_pa+2            ; probe candidate index
s_dummy     = s_pi+1            ; 7: writes of a muted voice
c_state     = s_dummy+7         ; per channel (NCH each)
c_qn        = c_state+NCH       ; notes queued
c_qr        = c_qn+NCH          ; queue read index
c_wait      = c_qr+NCH          ; waiting for sync (S)
c_dur       = c_wait+NCH        ; duration left, 1/20 s (255: for ever)
c_d20       = c_dur+NCH         ; centiseconds towards the next 1/20 s
c_env       = c_d20+NCH         ; envelope 1-16, 0 none
c_lvl       = c_env+NCH         ; amplitude 0-126
c_phase     = c_lvl+NCH         ; 0 attack, 1 decay, 2 sustain, 3 release, 4 done
c_pitch     = c_phase+NCH       ; pitch 0-255
c_psec      = c_pitch+NCH       ; pitch section 0-2 (3: done)
c_pcnt      = c_psec+NCH        ; steps left in the section
c_tcnt      = c_pcnt+NCH        ; centiseconds towards the next step
c_vol       = c_tcnt+NCH        ; SID sustain level shown
c_wave      = c_vol+NCH         ; waveform (control register, gate 0)
c_sid       = c_wave+NCH        ; SID of the channel's voice
c_voff      = c_sid+NCH         ; voice offset 0, 7, 14
q_ctl       = c_voff+NCH        ; queue: NCH * QLEN each
q_amp       = q_ctl+NCH*QLEN
q_pit       = q_amp+NCH*QLEN
q_dur       = q_pit+NCH*QLEN
env         = q_dur+NCH*QLEN    ; 16 envelopes x 13 bytes
ptab_lo     = env+16*13         ; BBC pitch -> SID frequency (snd_install)
ptab_hi     = ptab_lo+256
s_end       = ptab_hi+256

    .if s_end > MOSBUF
    .error "Sound engine overflows into MOSBUF"
    .endif

    .endl
