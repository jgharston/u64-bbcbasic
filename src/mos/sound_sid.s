; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- sound engine, SID image (*SOUND SID, the default):
; voices 0-23 = voice v MOD 3 of SID v DIV 3, each playing an instrument
; (records in the REU, DESIGN_SOUND.md section 9)
;
; Included by sound.s with SIDIMG = 1. Modulation (s_mod, every
; interrupt for each voice that uses it): pulse width and cutoff sweeps,
; vibrato, portamento, wave and arpeggio tables, hard restart, finetune.
; Pitch is kept in 1/64 semitones (c_pit: (P + 235) * 16, as s_q2f's Q
; times 16); s_pitch adds arpeggio and vibrato and writes the frequency,
; interpolated between the quarter-semitone table entries. Units:
; DESIGN_SOUND.md section 11.
;
; ----------------------------------------------------------------------------

; c_mod bits: what s_mod has to do for a voice
CM_PW       = $01               ; pulse width sweep
CM_VIB      = $02               ; vibrato
CM_PORTA    = $04               ; portamento running
CM_CUT      = $08               ; cutoff sweep
CM_TAB      = $10               ; wave / arpeggio table running
CM_HR       = $20               ; hard restart: gate on at the next interrupt
CM_RAW      = $80               ; raw frequency (P >= 1024): no pitch changes

; s_imginit: nothing beyond the common mapping
s_imginit:
    rts

; s_noteend: voice X's duration is over: the gate goes off, the SID's own
; release plays, the voice is free for the next note
s_noteend:
    lda #ST_REL
    sta c_state,x
    jmp s_gateoff

; ----------------------------------------------------------------------------
; s_note
;   Summary: start the note in s_amp/s_plo/s_phi on voice X.
;   Function: A = 1-64: the voice takes instrument A (from the REU);
;            A = -15..-1: the voice's instrument at sustain level -A;
;            A = 0: a rest (gate off for the duration). The tie flag
;            changes the pitch of a sounding note without a new attack
;            (with the instrument's portamento: a slide). Otherwise:
;            modulation restarted, pulse width, ADSR, filter, pitch, and
;            the gate retriggered (with hard restart: one interrupt later).
;   Uses:    A, X (kept), Y.
s_note:
    lda c_state,x               ; (tie and portamento: was one sounding?)
    sta s_tgt
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
    jsr s_ldinst                ; show at the next note)
    ldx s_ch
    lda s_lvl                   ; with a level L: sustain S * L / 15
    beq sn_go                   ; (S = 0, percussion, stays 0)
    sta s_t
    lda c_srbase,x
    lsr
    lsr
    lsr
    lsr
    beq sn_go
    tay                         ; S * L
    lda #0
    clc
sn_mul:
    adc s_t
    dey
    bne sn_mul
    ldy #0                      ; / 15, rounded
sn_div:
    cmp #15
    bcc sn_rnd
    sbc #15
    iny
    bne sn_div
sn_rnd:
    cmp #8
    bcc sn_scaled
    iny
sn_scaled:
    tya
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
    jsr s_target                ; c_tgt (or raw)
    lda s_ctl                   ; tie: pitch only
    and #QF_TIE
    beq sn_attack
    lda s_tgt
    cmp #ST_PLAY
    bne sn_attack
    jsr s_glide
    jmp s_pitch
sn_attack:
    jsr s_glide                 ; portamento from the last pitch, or none
    lda c_mod,x                 ; modulation from the start
    and #CM_RAW|CM_PORTA
    sta c_mod,x
    lda c_pwrate,x
    beq sn_nopw
    lda #CM_PW
    jsr sn_set
sn_nopw:
    lda c_vwid,x
    beq sn_novib
    lda c_vrate,x
    beq sn_novib
    lda #CM_VIB
    jsr sn_set
sn_novib:
    lda c_vdel,x
    sta c_vcnt,x
    lda #0
    sta c_vph,x
    sta c_arp,x
    lda c_ctrate,x
    beq sn_nocut
    lda c_filt,x
    lsr
    bcc sn_nocut
    lda #CM_CUT
    jsr sn_set
sn_nocut:
    lda c_tabw,x                ; a wave table: its first step now
    beq sn_notab
    lda reu_banks
    ora reu_banks+1
    beq sn_notab
    lda #CM_TAB
    jsr sn_set
    lda #0
    sta c_tidx,x
    jsr s_tstep
    ldx s_ch
sn_notab:
    jsr s_voice
    lda c_flags,x               ; hard restart: TEST, envelope 0, the gate
    lsr                         ; at the next interrupt
    bcc sn_gate0
    lda #$08
    ldy #4
    jsr s_w
    lda #0
    ldy #5
    jsr s_w
    iny
    jsr s_w
    lda #CM_HR
    jsr sn_set
    jmp sn_regs
sn_gate0:
    lda c_wave,x                ; gate off first (a new attack)
    ldy #4
    jsr s_w
    lda c_ad,x
    ldy #5
    jsr s_w
    lda c_sr,x
    iny
    jsr s_w
sn_regs:
    lda c_pwlo,x
    ldy #2
    jsr s_w
    lda c_pwhi,x
    iny
    jsr s_w
    jsr s_filter
    ldx s_ch
    jsr s_pitch
    lda c_mod,x
    and #CM_HR
    bne sn_rts
s_gateon:
    jsr s_voice                 ; voice X: AD, SR, waveform with the gate
    lda c_ad,x
    ldy #5
    jsr s_w
    lda c_sr,x
    iny
    jsr s_w
    lda c_wave,x
    ora #1
    ldy #4
    jmp s_w
sn_rts:
    rts
; sn_set: c_mod,x |= A
sn_set:
    ora c_mod,x
    sta c_mod,x
    rts

; ----------------------------------------------------------------------------
; s_target
;   Summary: voice X's target pitch from s_plo/s_phi: c_tgt = (P + 235)
;            * 16 + finetune, at least 0; P >= 1024: a raw frequency
;            (P - 1024) * 16 in c_tgt and CM_RAW set.
;   Uses:    A, Y.
s_target:
    lda c_mod,x
    and #$FF-CM_RAW
    sta c_mod,x
    lda s_phi
    bmi stg_q
    cmp #4
    bcc stg_q
    sbc #4                      ; raw: (P - 1024) * 16
    sta s_fhi
    lda s_plo
    ldy #4
stg_raw:
    asl
    rol s_fhi
    dey
    bne stg_raw
    sta c_tgtlo,x
    lda s_fhi
    sta c_tgthi,x
    lda #CM_RAW
    jmp sn_set
stg_q:
    lda s_plo                   ; Q = P + 235
    clc
    adc #235
    sta s_flo
    lda s_phi
    adc #0
    bpl stg_pos
    lda #0                      ; below the lowest: 0
    sta s_flo
stg_pos:
    ldy #4                      ; * 16
stg_16:
    asl s_flo
    rol
    dey
    bne stg_16
    sta s_fhi
    lda c_fine,x                ; + finetune (signed)
    bpl stg_fpos
    dec s_fhi
stg_fpos:
    clc
    adc s_flo
    sta c_tgtlo,x
    lda s_fhi
    adc #0
    bpl stg_set
    lda #0
    sta c_tgtlo,x
stg_set:
    sta c_tgthi,x
    rts

; s_glide: portamento: with a speed and a pitch sounding before, slide to
; the target from there; else the pitch is the target at once
s_glide:
    lda c_mod,x
    and #$FF-CM_PORTA
    sta c_mod,x
    bmi sgl_set                 ; (raw)
    lda c_porta,x
    beq sgl_set
    lda s_tgt                   ; nothing before (idle): no slide
    beq sgl_set
    lda #CM_PORTA
    jmp sn_set
sgl_set:
    lda c_tgtlo,x
    sta c_pitlo,x
    lda c_tgthi,x
    sta c_pithi,x
    rts

; ----------------------------------------------------------------------------
; s_mod
;   Summary: one interrupt's modulation of voice X (c_mod <> 0).
;   Function: hard restart's gate; pulse width sweep (bounces between the
;            top and bottom high nybbles); cutoff sweep (bounces, or stops
;            with flag bit 1); table step every c_tspd interrupts;
;            portamento towards c_tgt; vibrato after its delay; then the
;            frequency again if the pitch moved.
;   Uses:    A, X (kept), Y.
s_mod:
    lda #0
    sta s_dirty
    lda c_mod,x
    and #CM_HR
    beq smd_pw
    lda c_mod,x                 ; hard restart: the gate now
    and #$FF-CM_HR
    sta c_mod,x
    lda c_state,x
    cmp #ST_PLAY
    bne smd_pw
    jsr s_gateon
    ldx s_ch
smd_pw:
    lda c_mod,x
    and #CM_PW
    beq smd_cut
    jsr s_pwstep
    ldx s_ch
smd_cut:
    lda c_mod,x
    and #CM_CUT
    beq smd_tab
    jsr s_cutstep
    ldx s_ch
smd_tab:
    lda c_mod,x
    and #CM_TAB
    beq smd_porta
    dec c_tcnt,x
    bne smd_porta
    jsr s_tstep
    ldx s_ch
smd_porta:
    lda c_mod,x
    and #CM_PORTA
    beq smd_vib
    jsr s_portstep
smd_vib:
    lda c_mod,x
    and #CM_VIB
    beq smd_freq
    lda c_vcnt,x                ; delay first
    beq smd_vph
    dec c_vcnt,x
    jmp smd_freq
smd_vph:
    lda c_vrate,x               ; phase += rate * 4
    asl
    asl
    clc
    adc c_vph,x
    sta c_vph,x
    inc s_dirty
smd_freq:
    lda s_dirty
    beq smd_rts
    jmp s_pitch
smd_rts:
    rts

; s_pwstep: pulse width += rate; past the top or bottom (high nybble)
; the direction turns
s_pwstep:
    lda c_pwrate,x
    clc
    adc c_pwlo,x
    sta c_pwlo,x
    lda c_pwrate,x
    bmi spw_down
    lda c_pwhi,x
    adc #0
    sta c_pwhi,x
    cmp c_pwtop,x
    bcc spw_w
    lda c_pwtop,x               ; at the top: back down
    sta c_pwhi,x
    jmp spw_turn
spw_down:
    lda c_pwhi,x
    adc #$FF
    sta c_pwhi,x
    bmi spw_bot                 ; (below 0)
    cmp c_pwbot,x
    bcs spw_w
spw_bot:
    lda c_pwbot,x
    sta c_pwhi,x
spw_turn:
    lda #0
    sec
    sbc c_pwrate,x
    sta c_pwrate,x
spw_w:
    jsr s_voice
    lda c_pwlo,x
    ldy #2
    jsr s_w
    lda c_pwhi,x
    and #$0F
    iny
    jmp s_w

; s_cutstep: cutoff (high 8 bits) += rate; at the top or bottom it turns
; (flag bit 1: stops there); written to the voice's SID
s_cutstep:
    lda c_ctrate,x
    bmi sct_down
    clc
    adc c_fcut,x
    bcs sct_top
    cmp c_cttop,x
    bcc sct_set
sct_top:
    lda c_cttop,x
    jmp sct_end
sct_down:
    clc
    adc c_fcut,x
    bcc sct_bot                 ; below 0
    cmp c_ctbot,x
    bcs sct_set
    beq sct_set
sct_bot:
    lda c_ctbot,x
sct_end:
    sta c_fcut,x
    lda c_flags,x
    and #2
    beq sct_turn
    lda c_mod,x                 ; stop
    and #$FF-CM_CUT
    sta c_mod,x
    jmp sct_w
sct_turn:
    lda #0
    sec
    sbc c_ctrate,x
    sta c_ctrate,x
    jmp sct_w
sct_set:
    sta c_fcut,x
sct_w:
    lda c_sid,x
    bmi sct_rts
    jsr s_sidbase
    ldx s_ch
    lda c_fcut,x
    ldy #$16
    jmp s_w
sct_rts:
    rts

; s_portstep: c_pit moves towards c_tgt by c_porta; there: done
s_portstep:
    inc s_dirty
    lda c_pitlo,x               ; below or above?
    cmp c_tgtlo,x
    lda c_pithi,x
    sbc c_tgthi,x
    bcs spt_down
    lda c_pitlo,x               ; up
    clc
    adc c_porta,x
    sta c_pitlo,x
    lda c_pithi,x
    adc #0
    sta c_pithi,x
    lda c_pitlo,x               ; past the target?
    cmp c_tgtlo,x
    lda c_pithi,x
    sbc c_tgthi,x
    bcs spt_there
    rts
spt_down:
    lda c_pitlo,x
    sec
    sbc c_porta,x
    sta c_pitlo,x
    lda c_pithi,x
    sbc #0
    sta c_pithi,x
    bcc spt_there               ; below 0
    lda c_pitlo,x               ; past the target?
    cmp c_tgtlo,x
    lda c_pithi,x
    sbc c_tgthi,x
    bcc spt_there
    rts
spt_there:
    lda c_tgtlo,x
    sta c_pitlo,x
    lda c_tgthi,x
    sta c_pithi,x
    lda c_mod,x
    and #$FF-CM_PORTA
    sta c_mod,x
    rts

; ----------------------------------------------------------------------------
; s_tstep
;   Summary: the next step of voice X's wave and arpeggio tables.
;   Function: the step's wave byte and arpeggio byte come from the
;            instrument record in the REU (offsets 20 and 36 + step):
;            0 = the end (the last step stays), $FF n = go on at step n;
;            else the waveform (the gate bit is the engine's) and the
;            arpeggio offset in semitones (signed). Then c_tspd
;            interrupts to the next step.
;   Uses:    A, X (kept), Y.
s_tstep:
    lda c_tspd,x
    sta c_tcnt,x
    lda #2                      ; (at most one loop per step)
    sta s_t
sts_get:
    lda c_tidx,x
    cmp #16
    bcs sts_end
    jsr s_tget                  ; s_flo = wave, s_fhi = arpeggio
    lda s_flo
    beq sts_end
    cmp #$FF
    bne sts_use
    lda c_tidx,x                ; $FF n: n is the next wave byte
    clc
    adc #1
    sta c_tidx,x
    jsr s_tget
    lda s_flo
    sta c_tidx,x
    dec s_t
    bne sts_get
sts_end:
    lda c_mod,x                 ; the end
    and #$FF-CM_TAB
    sta c_mod,x
    rts
sts_use:
    and #$FE
    sta c_wave,x
    lda s_fhi
    sta c_arp,x
    inc c_tidx,x
    inc s_dirty
    jsr s_voice                 ; the waveform, gated while the note plays
    lda c_state,x
    cmp #ST_PLAY
    bne sts_nogate
    lda c_mod,x                 ; (not before a hard restart's gate)
    and #CM_HR
    bne sts_nogate
    lda c_wave,x
    ora #1
    bne sts_w
sts_nogate:
    lda c_wave,x
sts_w:
    ldy #4
    jmp s_w

; s_tget: s_flo = wave table byte c_tidx, s_fhi = arpeggio byte (REU)
s_tget:
    lda c_inst,x                ; REU_INST + (n-1) * 64 + 20 + step
    sec
    sbc #1
    and #63
    sta s_tmp
    lda #0
    lsr s_tmp
    ror
    lsr s_tmp
    ror
    clc
    adc #20
    adc c_tidx,x
    sta REU_ADDR
    lda s_tmp
    adc #>REU_INST
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<s_flo
    sta REU_C64
    lda #>s_flo
    sta REU_C64+1
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    lda REU_ADDR                ; the arpeggio byte: 16 further
    clc                         ; (the REU address registers moved on by 1)
    adc #15
    sta REU_ADDR
    lda #<s_fhi
    sta REU_C64
    lda #>s_fhi
    sta REU_C64+1
    lda #1
    sta REU_LEN
    lda #REU_TO_C64
    sta REU_CMD
    rts

; ----------------------------------------------------------------------------
; s_pitch
;   Summary: write voice X's frequency: c_pit + arpeggio * 64 + vibrato,
;            in 1/64 semitones, interpolated between the table's quarter
;            semitones; raw frequencies (CM_RAW) as they are.
;   Uses:    A, X (kept), Y.
s_pitch:
    lda c_mod,x
    bpl sp_q
    lda c_tgtlo,x               ; raw
    sta s_flo
    lda c_tgthi,x
    sta s_fhi
    jmp shf_set
sp_q:
    lda c_arp,x                 ; arpeggio: semitones * 64 (signed)
    sta s_tmp2
    lda #0
    ldy s_tmp2
    bpl sp_apos
    lda #$FF
sp_apos:
    sta s_tmp
    ldy #6
sp_a64:
    asl s_tmp2
    rol s_tmp
    dey
    bne sp_a64
    lda c_pitlo,x
    clc
    adc s_tmp2
    sta s_vlo
    lda c_pithi,x
    adc s_tmp
    sta s_vhi
    lda c_mod,x                 ; vibrato (after its delay)
    and #CM_VIB
    beq sp_clamp
    lda c_vcnt,x
    bne sp_clamp
    jsr s_vibofs                ; A/Y = offset (signed 16)
    clc
    adc s_vlo
    sta s_vlo
    tya
    adc s_vhi
    sta s_vhi
sp_clamp:
    lda s_vhi                   ; below 0: 0
    bpl sp_split
    lda #0
    sta s_vlo
    sta s_vhi
sp_split:
    lda s_vlo                   ; Q = v / 16, fraction v AND 15
    and #15
    sta s_frac
    lda s_vhi
    sta s_fhi
    lda s_vlo
    ldy #4
sp_d16:
    lsr s_fhi
    ror
    dey
    bne sp_d16
    sta s_flo
    sta s_qlo                   ; (Q kept for Q + 1)
    lda s_fhi
    sta s_qhi
    jsr s_q2f                   ; f(Q)
    lda s_frac
    bne sp_interp
    jmp shf_set
sp_interp:
    lda s_flo                   ; f(Q) aside, then f(Q + 1)
    sta s_f0lo
    lda s_fhi
    sta s_f0hi
    lda s_qlo
    clc
    adc #1
    sta s_flo
    lda s_qhi
    adc #0
    sta s_fhi
    jsr s_q2f
    lda s_flo                   ; d = f(Q+1) - f(Q)
    sec
    sbc s_f0lo
    sta s_tmp2
    lda s_fhi
    sbc s_f0hi
    sta s_tmp
    lda #0                      ; f = f(Q) + d * frac / 16
    sta s_flo
    sta s_fhi
    ldy #4
sp_mul:
    lsr s_frac                  ; (frac: 4 bits)
    bcc sp_mn
    lda s_flo
    clc
    adc s_tmp2
    sta s_flo
    lda s_fhi
    adc s_tmp
    sta s_fhi
sp_mn:
    asl s_tmp2
    rol s_tmp
    dey
    bne sp_mul
    ldy #4                      ; / 16
sp_m16:
    lsr s_fhi
    ror s_flo
    dey
    bne sp_m16
    lda s_flo
    clc
    adc s_f0lo
    sta s_flo
    lda s_fhi
    adc s_f0hi
    sta s_fhi
    bcc sp_set
    lda #$FF                    ; (top of the range)
    sta s_flo
    sta s_fhi
sp_set:
    jmp shf_set

; s_vibofs: A (low), Y (high) = vibrato offset of voice X: a triangle of
; the phase (-64..63) * width / 8, in 1/64 semitones
s_vibofs:
    lda c_vph,x                 ; triangle: rising 0-127, falling 128-255
    bmi svo_fall
    sec
    sbc #64                     ; -64..63
    jmp svo_t
svo_fall:
    eor #$FF                    ; 255 - phase: 127..0
    sec
    sbc #64                     ; 63..-64
svo_t:
    sta s_vsign
    bpl svo_abs
    eor #$FF
    clc
    adc #1
svo_abs:
    sta s_tmp2                  ; product (s_flo/s_tmp) = |t| (0-64) *
    lda #0                      ; width, shift and add: |t| doubles in
    sta s_tmpx                  ; s_tmp2/s_tmpx, the width shifts out
    sta s_tmp
    sta s_flo
    lda c_vwid,x
    sta s_fhi
    ldy #8
svo_mul:
    lsr s_fhi
    bcc svo_mn
    lda s_flo
    clc
    adc s_tmp2
    sta s_flo
    lda s_tmp
    adc s_tmpx
    sta s_tmp
svo_mn:
    asl s_tmp2
    rol s_tmpx
    dey
    bne svo_mul
    ldy #3                      ; / 8
svo_d8:
    lsr s_tmp
    ror s_flo
    dey
    bne svo_d8
    lda s_vsign
    bpl svo_pos
    lda #0                      ; negative
    sec
    sbc s_flo
    pha
    lda #0
    sbc s_tmp
    tay
    pla
    rts
svo_pos:
    lda s_flo
    ldy s_tmp
    rts

; ----------------------------------------------------------------------------
; Song playback (the tracker, docs/DESIGN_TRACKER.md): rows of the song in
; the REU (pattern p at REU_PAT + p * $1200, 64 rows of 24 cells: note,
; instrument, effect) come one per row time by DMA into t_buf and start
; notes through s_note, as SOUND's queue does. *SONG PLAY (sndcmd.s) sets
; t_ord, t_len, t_loop, t_rlen and t_on; t_ord's pattern loads here.

; s_song: from s_irq: the row clock; a row when it is due (at most two
; per interrupt)
s_song:
    lda t_acc+1                 ; centiseconds * 256 towards the next row
    clc
    adc s_cs
    sta t_acc+1
    lda #2
    sta t_n
ssg_due:
    lda t_acc                   ; acc >= row length?
    cmp t_rlen
    lda t_acc+1
    sbc t_rlen+1
    bcc ssg_rts
    sta t_acc+1
    lda t_acc
    sbc t_rlen
    sta t_acc
    jsr t_rowplay
    lda t_on
    beq ssg_rts
    dec t_n
    bne ssg_due
ssg_rts:
    rts

; t_rowplay: the row t_row of the pattern at t_ptr, then the next row
; (the next pattern of the order list, the loop point, or the end)
t_rowplay:
    lda t_row                   ; a new pattern first?
    bne trp_get
    jsr t_patload
    lda t_on
    bne trp_get
    rts
trp_get:
    lda t_ptr                   ; the row: 72 bytes into t_buf
    sta REU_ADDR
    lda t_ptr+1
    sta REU_ADDR+1
    lda t_ptr+2
    sta REU_BANK
    lda #<t_buf
    sta REU_C64
    lda #>t_buf
    sta REU_C64+1
    lda #72
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    lda t_ptr                   ; next row: + 72
    clc
    adc #72
    sta t_ptr
    bcc trp_cells
    inc t_ptr+1
    bne trp_cells
    inc t_ptr+2
trp_cells:
    ldx #0                      ; the cells: voice X at t_buf + 3 * X
    ldy #0
trp_cell:
    stx s_ch
    sty t_y
    lda t_buf,y
    beq trp_next                ; nothing
    cmp #255
    beq trp_off
    cmp #97
    bcs trp_next                ; (254 and others: the note goes on)
    asl                         ; P = note * 4 - 143 (note 49 = middle C)
    asl
    sta s_plo
    lda #0
    rol
    sta s_phi
    lda s_plo
    sec
    sbc #143
    sta s_plo
    lda s_phi
    sbc #0
    sta s_phi
    lda t_buf+1,y               ; instrument, or the voice's
    bne trp_inst
    lda c_inst,x
trp_inst:
    sta s_amp
    lda t_buf+2,y               ; effect 1v: level v (scales the sustain)
    and #$F0
    cmp #$10
    bne trp_nolvl
    lda t_buf+2,y
    and #$0F
    .byte $2C                   ; (BIT abs: skips the LDA #0)
trp_nolvl:
    lda #0
    sta s_lvl
trp_play:
    lda #0
    sta s_ctl
    sta c_d20,x
    lda #$FF                    ; until the next note or key off
    sta c_dur,x
    jsr s_note
    jmp trp_next
trp_off:
    lda c_state,x
    cmp #ST_PLAY
    bne trp_next
    jsr s_noteend
trp_next:
    ldx s_ch
    ldy t_y
    iny
    iny
    iny
    inx
    cpx #NV
    beq trp_rowend
    jmp trp_cell
trp_rowend:
    inc t_row                   ; next row
    lda t_row
    cmp t_rows
    bcc trp_rts
    lda #0                      ; end of the pattern: the next one
    sta t_row
    inc t_ord
trp_rts:
    rts

; t_patload: pattern t_ord of the order list (order list and row counts
; from the REU): t_pat, t_rows, t_ptr; past the end: the loop point, or
; the song stops
t_patload:
    lda t_ord
    cmp t_len
    bcc tpl_go
    lda t_loop
    cmp t_len
    bcc tpl_loop
    lda #0                      ; the end: stop; the song's notes (those
    sta t_on                    ; without an end) released
    ldx #NV-1
tpl_off:
    stx s_ch
    lda c_state,x
    cmp #ST_PLAY
    bne tpl_on
    lda c_dur,x
    cmp #$FF
    bne tpl_on
    jsr s_noteend
tpl_on:
    ldx s_ch
    dex
    bpl tpl_off
    rts
tpl_loop:
    sta t_ord
tpl_go:
    lda t_ord                   ; t_pat = order[t_ord]
    sta REU_ADDR
    lda #>REU_ORDER
    sta REU_ADDR+1
    lda #<t_pat
    ldx #>t_pat
    jsr t_get1
    lda t_pat                   ; t_rows = rows[t_pat]
    sta REU_ADDR
    lda #>REU_ROWS
    sta REU_ADDR+1
    lda #<t_rows
    ldx #>t_rows
    jsr t_get1
    lda t_rows
    beq tpl_64
    cmp #65
    bcc tpl_ptr
tpl_64:
    lda #64
    sta t_rows
tpl_ptr:
    lda #0                      ; t_ptr = REU_PAT + t_pat * $1200: the
    sta t_ptr                   ; page part t_pat * 18 in t_ptr+1/+2
    sta t_ptr+2
    lda t_pat
    asl                         ; * 2
    rol t_ptr+2
    sta t_ptr+1
    sta t_y                     ; (t_pat * 2 kept: t_y, s_tmp)
    lda t_ptr+2
    sta s_tmp
    lda t_ptr+1
    ldy #3                      ; * 16
tpl_16:
    asl
    rol t_ptr+2
    dey
    bne tpl_16
    clc                         ; * 16 + * 2
    adc t_y
    sta t_ptr+1
    lda t_ptr+2
    adc s_tmp
    adc #REU_PATBANK
    sta t_ptr+2
    rts

; t_get1: one byte from the song's bank (REU_SONGBANK, page and low byte
; already in REU_ADDR) to A/X
t_get1:
    sta REU_C64
    stx REU_C64+1
    lda #REU_SONGBANK
    sta REU_BANK
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    rts

; ----------------------------------------------------------------------------
; shf_set: voice X's frequency registers = s_flo/s_fhi
shf_set:
    jsr s_voice
    lda s_flo
    ldy #0
    jsr s_w
    lda s_fhi
    ldy #1
    jmp s_w

; s_gateoff: voice X's gate off (its release plays)
s_gateoff:
    jsr s_voice
    lda c_wave,x
    ldy #4
    jmp s_w

; s_voice: point s_w at voice X's SID voice (a dummy beyond the SIDs found)
s_voice = s_vmap

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
    ldy #IHDR-1                 ; SQUARE's first 5 bytes, the rest 0
sl_dloop:
    lda #0
    cpy #5
    bcs sl_dz
    lda s_defhdr,y
sl_dz:
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
    ldy #0                      ; modulation fields: record offset -> array
sl_mods:
    lda sl_tab,y
    beq sl_done
    sty s_t
    tay
    lda s_ihdr,y
    pha
    ldy s_t
    lda sl_tab+1,y              ; (self-modified store into the array)
    sta sl_st+1
    lda sl_tab+2,y
    sta sl_st+2
    pla
sl_st:
    sta $FFFF,x
    iny
    iny
    iny
    bne sl_mods
sl_done:
    lda c_tspd,x                ; table speed at least 1
    bne sl_rts
    inc c_tspd,x
sl_rts:
    rts
sl_tab:
    dta 5, a(c_pwrate), 6, a(c_pwtop), 7, a(c_pwbot)
    dta 8, a(c_vdel), 9, a(c_vwid), 10, a(c_vrate), 11, a(c_porta)
    dta 15, a(c_ctrate), 16, a(c_cttop), 17, a(c_ctbot)
    dta 18, a(c_fine), 19, a(c_flags), 20, a(c_tabw), 52, a(c_tspd)
    dta 0

; instrument 1 (SQUARE) without an REU
s_defhdr:
    dta $40, $09, $A8, $00, $08
