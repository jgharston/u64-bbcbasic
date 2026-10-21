; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the music paused during a Upic full show (bank 7,
; inside .local upm; called by upic.s's up_show, bank 8, which is full)
;
; ----------------------------------------------------------------------------
; ups_mute / ups_unmute
;   Summary: the music paused cleanly while a picture shows.
;   Function: the viewer runs with interrupts off and the sound engines'
;            RAM swapped out, so the music stands still and its notes
;            would hang: a clean pause instead.
;            ups_mute: every SID's volume 0 (its filter mode kept), and
;            when the MOD plays (SNDV_IMG 2) Ultimate Audio's 7 channels
;            stopped. ups_unmute: the SIDs' volume back from the shadow
;            (s_f18); the MOD carries on where it stood, its channels
;            starting again with their next notes.
;   Input:   interrupts off; s_nsid, s_sidlo/hi, s_f18 (SNDSHR).
;   Output:  the SID volume registers; Ultimate Audio's control registers.
;   Uses:    A, X, Y, mosTMP.
; ups_run: the music muted, the viewer run (upv.run, in RAM), the music
; back: one call from bank 8 (full).
ups_run:
    jsr ups_mute
    jsr upv.run
ups_unmute:
    lda #$FF
    bne um_sids
ups_mute:
    lda #$F0
    jsr um_sids
    lda SNDV_IMG
    cmp #2
    bne um_rts
    ldx #6*32                   ; channel 6 down to 0: control 0 (stop)
um_ua:
    lda #0
    sta $DF20,x                 ; (UA_BASE + 32 c + UA_CTRL, sample.s)
    txa
    sec
    sbc #32
    tax
    bcs um_ua
um_rts:
    rts
um_sids:                        ; each SID: register $18 = s_f18 AND A
    sta mosTMP+2
    ldx s_nsid
    beq um_rts
um_sid:
    dex
    lda s_sidlo,x
    sta mosTMP
    lda s_sidhi,x
    sta mosTMP+1
    ldy #$18
    lda s_f18,x
    and mosTMP+2
    sta (mosTMP),y
    txa
    bne um_sid
    rts


; ups_pal: the mode's palette back after a show: Upic Lite and teletext
; their own, the VIC-II modes and Upic full's console the C64's (moved
; here from upic.s's up_show: bank 8 is full).  Uses: A, X, Y.
ups_pal:
    lda eng_kind
    cmp #1
    beq upp_ul
    cmp #2
    bne upp_c64
upp_ul:
    farcall ul_setpal, BANK_FS
    rts
upp_c64:
    farcall pal_apply, BANK_FS
    rts
