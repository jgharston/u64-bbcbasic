; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- RND seeded from real entropy (bank 3; PLAN.md section 21,
; 1.0.0 item 5)
;
; BBC BASIC's RND is a 33-bit shift register with its seed at &0D-&11; at
; its start BASIC sets the fixed seed "ARW" only when the seed is zero. The
; MOS seeds it at the cold start, so every start gives another sequence,
; and on *RANDOMIZE. RND(-n) keeps giving a reproducible sequence.
;
; No entropy pool (no RAM left in the resident area or pages 2-3): the
; entropy is gathered when the seed is made. The sources: the old seed,
; BBC TIME in centiseconds (when a person did something: *RANDOMIZE after
; a key press), CIA 1's timer A at 1 MHz and the raster line, read before
; and after a request to the Ultimate's clock (its answer time varies at
; turbo speed), and the clock's date and time text.
;
; ----------------------------------------------------------------------------

RS_SEED     = $0D               ; BASIC's zpSEED (5 bytes, 33 bits used)

; ----------------------------------------------------------------------------
; rnd_seed / cmd_randomize
;   Summary: mix entropy into BASIC's RND seed (rnd_seed: the cold start;
;            cmd_randomize: *RANDOMIZE / *RANDOMISE, nothing may follow).
;   Function: each source byte is XORed into the seed (byte by byte in
;            turn) and the 40 bits are rotated left by one; then the seed
;            is cut to 33 bits and made non-zero.
;   Input:   none.  Output: &0D-&11.
;   Uses:    A, X, Y, mosTMP, fs*, MOSBUF (the clock's text).
cmd_randomize:
    farcall ff_end, BANK_FS
rnd_seed:
    lda #0
    sta mosTMP                  ; the seed byte to XOR into next
    ldx #4                      ; BBC TIME
rs_time:
    lda mostime,x
    jsr rs_mix
    dex
    bpl rs_time
    jsr rs_hw
    lda #0
    sta fsCNT
    farcall rs_clock, BANK_FS   ; the clock's text -> MOSBUF, fsCNT bytes
    jsr rs_hw                   ; (after the Ultimate's answer)
    ldx #0
rs_text:
    cpx fsCNT
    bcs rs_cut
    lda MOSBUF,x
    jsr rs_mix
    inx
    bne rs_text
rs_cut:
    lda RS_SEED+4               ; 33 bits, not all zero
    and #1
    sta RS_SEED+4
    ora RS_SEED
    ora RS_SEED+1
    ora RS_SEED+2
    ora RS_SEED+3
    bne rs_rts
    inc RS_SEED
rs_rts:
    rts

; rs_hw: CIA 1 timer A (low, high), the raster line, CIA 1's TOD tenths
rs_hw:
    lda $DC04
    jsr rs_mix
    lda $DC05
    jsr rs_mix
    lda $D012
    jsr rs_mix
    lda $DC08
    ; (fall through)

; rs_mix: A XORed into seed byte mosTMP (0-4, in turn), then the seed
; rotated left by one (40 bits). Keeps X and Y.
rs_mix:
    sty mosTMP+1
    ldy mosTMP
    eor RS_SEED,y
    sta RS_SEED,y
    iny
    cpy #5
    bcc rsm_i
    ldy #0
rsm_i:
    sty mosTMP
    lda RS_SEED+4
    asl
    rol RS_SEED
    rol RS_SEED+1
    rol RS_SEED+2
    rol RS_SEED+3
    rol RS_SEED+4
    ldy mosTMP+1
    rts
