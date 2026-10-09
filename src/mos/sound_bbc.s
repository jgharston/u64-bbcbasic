; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- sound engine, BBC image (*SOUND BBC): channels 0 (noise)
; and 1-3 (tone) as on a BBC Micro, ENVELOPE in software
;
; Included by sound.s with SIDIMG = 0. The BBC mode follows the BBC MOS
; 1.20 sound code (Toby Lobster's annotated disassembly,
; tobylobster.github.io/mos, chapter 16): durations in 1/20 s counted in
; 5-centisecond units, 255 = for ever; envelope steps every T
; centiseconds, pitch in three sections (repeated unless T bit 7),
; amplitude phases attack, decay, sustain, release; at the end of a note
; the next queued note starts at once, otherwise the release phase plays.
; Adapted: written anew for the SID (software amplitude through the
; sustain level, see s_hwvol).
;
; ----------------------------------------------------------------------------

; s_imginit: BBC slots: 1-3 = SID 0 voices 0-2; slot 0 (noise) = SID 1
; voice 0 with 2+ SIDs, else SID 0 voice 2, shared with slot 3 while it
; plays. The envelopes come from the REU copy (ENVELOPE keeps one there,
; so they survive *SOUND SID and back).
s_imginit:
    lda #0
    sta s_share
    sta c_sid+1
    sta c_sid+2
    sta c_sid+3
    sta c_voff+1
    lda #7
    sta c_voff+2
    lda #14
    sta c_voff+3
    ldx s_nsid
    cpx #2
    bcc sii_one
    lda #1                      ; noise on SID 1 voice 0
    sta c_sid
    lda #0
    sta c_voff
    beq sii_env
sii_one:
    lda #0                      ; noise shares SID 0 voice 2
    sta c_sid
    lda #14
    sta c_voff
    inc s_share
sii_env:
    lda reu_banks
    ora reu_banks+1
    beq sii_rts
    lda #<REU_ENV
    sta REU_ADDR
    lda #>REU_ENV
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<env
    sta REU_C64
    lda #>env
    sta REU_C64+1
    lda #<[16*13]
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
sii_rts:
    rts

; s_chanenv: envelope steps every T cs (s_chan, voice X sounding)
s_chanenv:
    lda c_env,x
    beq sce_rts
    jsr s_envptr                ; Y = envelope offset
    lda env+0,y                 ; T (bits 0-6), at least 1
    and #$7F
    bne sce_t
    lda #1
sce_t:
    sta s_per
    lda c_tcnt,x
    clc
    adc s_cs
    sta c_tcnt,x
sce_step:
    lda c_tcnt,x
    cmp s_per
    bcc sce_rts
    sbc s_per
    sta c_tcnt,x
    jsr s_estep
    ldx s_ch
    lda c_state,x
    bne sce_step
sce_rts:
    rts

; s_noteend: voice X's duration is over: an envelope goes to its release
; phase (cut short when the next note starts), else the voice is free
s_noteend:
    lda c_env,x
    beq sne_off
    lda #3
    sta c_phase,x
    lda #ST_REL
    sta c_state,x
    rts
sne_off:
    lda #ST_IDLE
    sta c_state,x
    jmp s_gateoff

; s_note: start the note in s_amp/s_plo on voice X: envelope notes (A =
; 1-16) start their envelope from the current level when they cut a
; release short (BBC amplitude continuity), else from 0; A = -15..0 sets
; the level
s_note:
    lda s_plo
    sta c_plo,x
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
;   Summary: one envelope step of voice X (BBC mode): pitch, amplitude.
;   Function: pitch: + PI of the section, PN steps per section, after
;            section 3 back to 1 unless T bit 7. Amplitude: attack (AA to
;            ALA), decay (AD to ALD), sustain (AS, to 0 at most), release
;            (AR to 0, then the voice is free and silent).
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
    adc c_plo,x
    sta c_plo,x
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
; Hardware: voice X's SID voice (BBC mode helpers first)

; s_hwstart: BBC mode: waveform, pulse width, ADSR, frequency, level
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
    lda c_plo,x                 ; noise channel: P AND 7
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

; s_hwfreq: the frequency of voice X: c_plo as BBC pitch (the noise
; channel: P AND 7 as the BBC's noise types)
s_hwfreq:
    cpx #0
    beq shf_noise
    lda c_plo,x                 ; tone: Q = P + 235
    clc
    adc #235
    sta s_flo
    lda #0
    adc #0
    sta s_fhi
    jsr s_q2f
    jmp shf_set
shf_noise:
    lda c_plo,x
    and #3
    cmp #3
    beq shf_ch1
    tay
    lda c_plo,x
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
    lda c_plo+1                 ; P = 3, 7: channel 1's frequency / 16
    clc
    adc #235
    sta s_flo
    lda #0
    adc #0
    sta s_fhi
    jsr s_q2f
    lsr s_fhi
    ror s_flo
    lsr s_fhi
    ror s_flo
    lsr s_fhi
    ror s_flo
    lsr s_fhi
    ror s_flo
shf_set:
    jsr s_voice
    lda s_flo
    ldy #0
    jsr s_w
    lda s_fhi
    ldy #1
    jmp s_w

; s_hwvol
;   Summary: BBC mode: show voice X's level (c_lvl 0-126) on the SID.
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

; s_voice: point s_w at voice X's SID voice (a dummy for voices beyond the
; SIDs found, and for slot 3 while the noise channel has the voice it
; shares)
s_voice:
    cpx #3
    bne sv_map
    lda s_share
    beq sv_map
    lda c_state                 ; slot 0 playing: slot 3 is mute
    beq sv_map
    jmp s_vdummy
sv_map:
    jmp s_vmap

; s_envptr: Y = offset of voice X's envelope (c_env 1-16) in env
s_envptr:
    ldy c_env,x
    lda env_ofs-1,y
    tay
    rts

; BBC volume 0-15 -> SID sustain level (2 dB steps, linear SID scale)
vtab:
    dta 0, 1, 1, 1, 1, 2, 2, 2, 3, 4, 5, 6, 8, 9, 12, 15

; envelope N -> offset in env (13 bytes each)
env_ofs:
    :16 dta #*13
