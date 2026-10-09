; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- sound engine, assembled for SOUNDRAM ($0800)
;
; Copied to RAM at start-up by snd_install (ulbank.s, bank 4); the parts
; that do not run in the interrupt (OSWORD 7/8 parsing, SID probing, the
; * commands, the instruments) are in bank 2 (sndcmd.s). Design:
; docs/DESIGN_SOUND.md.
;
; Two modes (s_mode):
; - SID mode (0, the default): voices 0-23 = voice v MOD 3 of SID v DIV 3;
;   a note plays an instrument (waveform, ADSR, pulse width, filter;
;   instrument records in the REU, section 9 of the design).
; - BBC mode (1, *SOUND BBC): channels 0 (noise) and 1-3 (tone) as on a
;   BBC Micro in slots 0-3, with ENVELOPE in software.
;
; Both: queues of 3 notes per voice, flush, sync, hold; the BBC mode
; follows the BBC MOS 1.20 sound code (Toby Lobster's annotated
; disassembly, tobylobster.github.io/mos, chapter 16): durations in 1/20
; s counted in 5-centisecond units, 255 = for ever; envelope steps every
; T centiseconds, pitch in three sections (repeated unless T bit 7),
; amplitude phases attack, decay, sustain, release; at the end of a note
; the next queued note starts at once, otherwise the release phase plays.
; Adapted: written anew for the SID (software amplitude through the
; sustain level, see s_hwvol).
;
; The interrupt part uses no zero page: absolute addressing, the SID
; writes through a patched address (s_w). It runs in RAM, so the
; self-modifying code is allowed.
;
; ----------------------------------------------------------------------------

    .local snd

NV          = 24                ; voices (8 SIDs x 3)
QLEN        = 3                 ; queued notes per voice (MOS 1.20: 15 bytes)
IHDR        = 20                ; instrument header bytes copied at note-on
REU_INST    = $2000             ; 64 instruments x 64 bytes (REU bank 0)

; voice states
ST_IDLE     = 0
ST_PLAY     = 1                 ; note sounding, duration running
ST_REL      = 2                 ; duration over, releasing
ST_HOLD     = 3                 ; a hold note: duration runs, release goes on

; queue flags (q_ctl)
QF_SYNC     = $0F               ; start together with S other voices
QF_HOLD     = $10
QF_TIE      = $20               ; SID mode: change the playing note

; ----------------------------------------------------------------------------
; Entry points (SOUNDRAM + n)

    jmp s_init                  ; +0  reset the voices for s_mode
    jmp s_irq                   ; +3  from the interrupt
    jmp s_put                   ; +6  queue s_qbuf on voice X (C = 1: full)
    jmp s_adval                 ; +9  X = voice: X = free queue bytes
    jmp s_stopall               ; +12 silence, empty the queues
    jmp s_bell                  ; +15 VDU 7
    jmp s_flush                 ; +18 voice X: queue emptied, sound off

; ----------------------------------------------------------------------------
; s_init
;   Summary: all voices idle, queues empty, every SID silent at volume 15,
;            voices mapped to SID voices for the mode.
;   Function: SID mode: voice v = SID v DIV 3, voice v MOD 3 (voices
;            beyond the SIDs found write to a dummy). BBC mode: slots 1-3
;            = SID 0 voices 0-2; slot 0 (noise) = SID 1 voice 0 with 2+
;            SIDs, else SID 0 voice 2, shared with slot 3 while it plays.
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
    sta c_vol,x
    sta c_env,x
    lda #1                      ; instrument 1
    sta c_inst,x
    txa                         ; SID mode map
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
    stx s_ch
    jsr s_ldinst                ; the default instrument's header
    ldx s_ch
    dex
    bpl si_clr
    lda #0
    sta s_share
    lda s_mode
    beq si_vol
    lda #0                      ; BBC mode: slots 1-3 = SID 0 voices 0-2
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
;            empty queues cost a few cycles each.
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
sq_skip:
    dex
    bpl sq_ch
    jsr s_sync
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
    lda c_state,x               ; envelope steps every T cs (BBC mode)
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
    and #QF_SYNC
    beq sc_go
    sta c_wait,x                ; waits for s_sync
    rts
sc_go:
    jmp s_start
sc_rts:
    rts

; s_noteend: voice X's duration is over. A queued note follows at once
; (s_chan's next step); else the release phase (BBC envelope; SID mode:
; the gate goes off and the SID's own release plays).
s_noteend:
    lda s_mode
    bne sne_bbc
    lda #ST_REL                 ; SID mode: release, the voice is free
    sta c_state,x
    jmp s_gateoff
sne_bbc:
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
;            duration. BBC mode: envelope notes (A = 1-16) start their
;            envelope from the current level when they cut a release
;            short (BBC amplitude continuity), else from 0; A = -15..0
;            sets the level. SID mode: see s_sidnote.
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
    lda #3                      ; (BBC: the previous note's release)
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
    lda s_mode
    bne sst_bbc
    jmp s_sidnote
sst_bbc:
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
; s_sidnote
;   Summary: SID mode: start the note in s_amp/s_plo/s_phi on voice X.
;   Function: A = 1-64: the voice takes instrument A (header from the
;            REU); A = -15..-1: the voice's instrument at sustain level
;            -A; A = 0: a rest (gate off for the duration). The tie flag
;            changes the pitch of a playing note without a new attack.
;            Otherwise: pulse width, ADSR, filter routing, frequency, then
;            the gate is retriggered.
;   Uses:    A, X (kept), Y.
s_sidnote:
    lda c_state,x               ; (tie: only if a note was sounding)
    sta s_tgt
    lda s_plo
    sta c_plo,x
    lda s_phi
    sta c_phi,x
    lda #ST_PLAY
    sta c_state,x
    lda s_amp
    bne sn_amp
    jmp s_gateoff               ; a rest
sn_amp:
    bmi sn_level
    cmp #65
    bcs sn_go
    sta c_inst,x                ; (loaded every time: *INSTRUMENT changes
                                ; show at the next note)
    jsr s_ldinst
    ldx s_ch
    jmp sn_go
sn_level:
    lda #0                      ; sustain level -A
    sec
    sbc s_amp
    asl
    asl
    asl
    asl
    sta s_t
    lda c_srbase,x
    and #$0F
    ora s_t
    sta c_sr,x
    jmp sn_go2
sn_go:
    lda c_srbase,x
    sta c_sr,x
sn_go2:
    lda s_ctl                   ; tie: pitch only
    and #QF_TIE
    beq sn_attack
    lda s_tgt
    cmp #ST_PLAY
    bne sn_attack
    jmp s_hwfreq
sn_attack:
    jsr s_voice
    lda c_wave,x                ; gate off first (a new attack)
    ldy #4
    jsr s_w
    lda c_pwlo,x
    ldy #2
    jsr s_w
    lda c_pwhi,x
    iny
    jsr s_w
    lda c_ad,x
    ldy #5
    jsr s_w
    lda c_sr,x
    iny
    jsr s_w
    jsr s_filter
    ldx s_ch
    jsr s_hwfreq
    ldx s_ch
    jsr s_voice
    lda c_wave,x
    ora #1
    ldy #4
    jmp s_w

; s_filter: voice X's filter routing and, if it uses the filter, the
; filter settings of its instrument (s_ihdr, or the voice's copy)
s_filter:
    ldy c_sid,x
    bpl sf_go
    rts
sf_go:
    lda c_voff,x                ; route bit: 1, 2, 4
    ldy #0
sf_bit:
    beq sf_have
    iny
    sec
    sbc #7
    jmp sf_bit
sf_have:
    lda sf_bits,y
    sta s_t
    ldy c_sid,x
    lda c_filt,x
    lsr
    bcs sf_on
    lda s_t                     ; not filtered
    eor #$FF
    and s_f17,y
    sta s_f17,y
    jmp sf_w17
sf_on:
    lda s_f17,y                 ; routed, resonance from the voice
    ora s_t
    and #$0F
    sta s_f17,y
    lda c_fres,x
    asl
    asl
    asl
    asl
    ora s_f17,y
    sta s_f17,y
    lda c_filt,x                ; mode bits 4-6 + volume 15
    and #$70
    ora #$0F
    sta s_f18,y
    tya
    pha
    jsr s_sidbase
    lda #0                      ; cutoff: high 8 bits
    ldy #$15
    jsr s_w
    ldx s_ch
    lda c_fcut,x
    iny
    jsr s_w
    pla
    tay
    lda s_f18,y
    ldy #$18
    jsr s_w2
    ldx s_ch
    ldy c_sid,x
sf_w17:
    tya
    pha
    jsr s_sidbase
    pla
    tay
    lda s_f17,y
    ldy #$17
    jmp s_w
sf_rts:
    rts
sf_bits:
    dta 1, 2, 4
; s_w2: as s_w, Y kept by the caller (A = value, Y = register)
s_w2:
    jmp s_w

; s_ldinst: voice X takes the header of instrument c_inst,x (from the
; REU; without one, the built-in default)
s_ldinst:
    lda reu_banks
    ora reu_banks+1
    beq sl_def
    lda c_inst,x                ; REU_INST + (n - 1) * 64
    sec
    sbc #1
    and #63
    sta s_t
    lda #0
    lsr s_t
    ror
    lsr s_t
    ror
    sta REU_ADDR                ; low byte: ((n-1) AND 3) * 64
    lda s_t
    clc
    adc #>REU_INST
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<s_ihdr
    sta REU_C64
    lda #>s_ihdr
    sta REU_C64+1
    lda #IHDR
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    jmp sl_copy
sl_def:
    ldy #IHDR-1
sl_dloop:
    lda s_defhdr,y
    sta s_ihdr,y
    dey
    bpl sl_dloop
sl_copy:
    lda s_ihdr+0                ; waveform (gate bit off)
    and #$FE
    sta c_wave,x
    lda s_ihdr+1
    sta c_ad,x
    lda s_ihdr+2
    sta c_srbase,x
    sta c_sr,x
    lda s_ihdr+3
    sta c_pwlo,x
    lda s_ihdr+4
    sta c_pwhi,x
    lda s_ihdr+12
    sta c_filt,x
    lda s_ihdr+13
    sta c_fres,x
    lda s_ihdr+14
    sta c_fcut,x
    rts

; instrument 1 (SQUARE) without an REU
s_defhdr:
    dta $40, $09, $A8, $00, $08, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

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

; s_hwfreq: the frequency of voice X: BBC mode: c_plo as BBC pitch (the
; noise channel: P AND 7 as the BBC's noise types); SID mode: c_plo/c_phi
; signed, P >= 1024: raw frequency (P - 1024) * 16
s_hwfreq:
    lda s_mode
    beq shf_sid
    cpx #0
    beq shf_noise
    lda c_plo,x                 ; BBC tone: Q = P + 235
    clc
    adc #235
    sta s_flo
    lda #0
    adc #0
    sta s_fhi
    jmp shf_q
shf_sid:
    lda c_phi,x
    bmi shf_low
    cmp #4
    bcc shf_qs
    sec                         ; raw: (P - 1024) * 16
    sbc #4
    sta s_fhi
    lda c_plo,x
    asl
    rol s_fhi
    asl
    rol s_fhi
    asl
    rol s_fhi
    asl
    rol s_fhi
    sta s_flo
    jmp shf_set
shf_qs:
    lda c_plo,x                 ; Q = P + 235
    clc
    adc #235
    sta s_flo
    lda c_phi,x
    adc #0
    sta s_fhi
    jmp shf_q
shf_low:
    lda c_plo,x                 ; P < 0: Q = P + 235 if still >= 0
    clc
    adc #235
    sta s_flo
    lda c_phi,x
    adc #0
    sta s_fhi
    bpl shf_q
    lda #0
    sta s_flo
    sta s_fhi
    jmp shf_set
shf_q:
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
; SIDs found, and in BBC mode for slot 3 while the noise channel has the
; voice it shares)
s_voice:
    lda s_mode
    beq sv_map
    cpx #3
    bne sv_map
    lda s_share
    beq sv_map
    lda c_state                 ; slot 0 playing: slot 3 is mute
    beq sv_map
sv_dummy:
    lda #<s_dummy
    sta sw_op+1
    lda #>s_dummy
    sta sw_op+2
    rts
sv_map:
    lda c_sid,x
    bmi sv_dummy
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

; s_qhead: Y = voice X's head entry (X * QLEN + read index)
s_qhead:
    txa
    sta s_tmp
    asl
    adc s_tmp                   ; X * 3 (QLEN)
    adc c_qr,x
    tay
    rts

; s_envptr: Y = offset of voice X's envelope (c_env 1-16) in env
s_envptr:
    ldy c_env,x
    lda env_ofs-1,y
    tay
    rts

; ----------------------------------------------------------------------------
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
    ldx #2
    lda s_mode
    beq sb_put
    ldx #3
sb_put:
    jmp s_put
sb_rts:
    rts
bell_q:
    dta 0, -15, 101, 0, 6

; ----------------------------------------------------------------------------
; Tables

; BBC volume 0-15 -> SID sustain level (2 dB steps, linear SID scale)
vtab:
    dta 0, 1, 1, 1, 1, 2, 2, 2, 3, 4, 5, 6, 8, 9, 12, 15

; envelope N -> offset in env (13 bytes each)
env_ofs:
    :16 dta #*13

; filled by snd_install for PAL or NTSC: the octave of middle C in
; quarter semitones (48), and the noise frequencies: periodic (shift rate
; / 15) and white (shift rate) for the BBC's 7812.5, 3906.25, 1953.125 Hz
ftab_lo     :48 dta 0
ftab_hi     :48 dta 0
ntab_lo     :6 dta 0
ntab_hi     :6 dta 0

; ----------------------------------------------------------------------------
; Variables (not in the image: after it; cleared by snd_install)

s_vars      = *
s_mode      = s_vars            ; 0 SID mode, 1 BBC mode
s_off       = s_mode+1          ; *SOUND OFF
s_nsid      = s_off+1           ; SIDs found
s_sidlo     = s_nsid+1          ; 8: SID base addresses
s_sidhi     = s_sidlo+8         ; 8
s_f17       = s_sidhi+8         ; 8: filter routing / resonance per SID
s_f18       = s_f17+8           ; 8: filter mode / volume per SID
s_qbuf      = s_f18+8           ; 5: the note to queue (s_put)
s_ihdr      = s_qbuf+5          ; IHDR: instrument header being loaded
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
c_env       = c_d20+NV          ; BBC envelope 1-16, 0 none
c_lvl       = c_env+NV          ; BBC amplitude 0-126
c_phase     = c_lvl+NV          ; 0 attack, 1 decay, 2 sustain, 3 release, 4 done
c_plo       = c_phase+NV        ; pitch (BBC: 0-255; SID: signed 16 bits)
c_phi       = c_plo+NV
c_psec      = c_phi+NV          ; pitch section 0-2 (3: done)
c_pcnt      = c_psec+NV         ; steps left in the section
c_tcnt      = c_pcnt+NV         ; centiseconds towards the next step
c_vol       = c_tcnt+NV         ; BBC: SID sustain level shown
c_wave      = c_vol+NV          ; waveform (control register, gate 0)
c_sid       = c_wave+NV         ; SID of the voice ($FF: none)
c_voff      = c_sid+NV          ; voice offset 0, 7, 14
c_inst      = c_voff+NV         ; SID mode: instrument 1-64
c_ad        = c_inst+NV         ; its attack/decay
c_srbase    = c_ad+NV           ; its sustain/release
c_sr        = c_srbase+NV       ; sustain/release of this note
c_pwlo      = c_sr+NV           ; pulse width
c_pwhi      = c_pwlo+NV
c_filt      = c_pwhi+NV         ; filter: bit 0 on, bits 4-6 mode
c_fres      = c_filt+NV         ; resonance
c_fcut      = c_fres+NV         ; cutoff (high 8 bits)
q_ctl       = c_fcut+NV         ; queue: NV * QLEN each
q_amp       = q_ctl+NV*QLEN
q_plo       = q_amp+NV*QLEN
q_phi       = q_plo+NV*QLEN
q_dur       = q_phi+NV*QLEN
env         = q_dur+NV*QLEN     ; 16 BBC envelopes x 13 bytes
s_end       = env+16*13

    .if s_end > MOSBUF
    .error "Sound engine overflows into MOSBUF"
    .endif

    .endl
