; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *TABLE SQR and *TABLE RECIP (bank 5)
;
; As *TABLE SIN (mathtab.s, bank 8): 32-bit
; values times 65536, read as T%!(4*I%):
;   *TABLE SQR addr [n]    entry i = SQR(i) * 65536, rounded
;   *TABLE RECIP addr [n]  entry i = 65536 / i, rounded (entry 0:
;                          &7FFFFFFF)
; for i = 0 to n-1, n = 256, 512, 1024 (when left out), 2048 or 4096
; (1K-16K). *TABLE comes here first; SIN and COS go on to bank 8.
;
; The values are computed bit by bit (square root: 24 steps of two bits
; of i * 2^32; reciprocal: 24 steps of a division), which would take
; seconds at the cartridge's bus speed: that loop is a RAM image run in
; MOSBUF at turbo speed (assembled for MOSBUF, copied there).
;
; ----------------------------------------------------------------------------

    .local mt5

BAS_HIMEM   = $06               ; BBC BASIC's HIMEM (2), PAGE (high byte)
BAS_PAGE    = $18

; ----------------------------------------------------------------------------
; cmd_tab5
;   Summary: *TABLE SQR|RECIP addr [n]; any other word: *TABLE SIN/COS
;            (mtab.cmd_tab, bank 8).
;   Function: checks addr .. addr + 4n - 1 lie between PAGE and HIMEM,
;            copies the image to MOSBUF and runs it.
;   Input:   mosPTR/Y.  Output: the table; raises on errors.
;   Uses:    A, X, Y, mosTMP, mosNUM, mosPTR2, MOSBUF.
cmd_tab5:
    lda (mosPTR),y              ; (spaces)
    cmp #' '
    bne m5_word
    iny
    bne cmd_tab5
m5_word:
    ldx #0                      ; SQR?
    jsr m5_is
    bcs m5_kind
    ldx #m5_wrec-m5_wsqr        ; RECIP?
    jsr m5_is
    bcs m5_kind
    farcall mtab.cmd_tab, BANK_UP
    rts
m5_kind:
    stx mosTMP+2                ; 0 SQR, else RECIP
    farcall bvc.bv_arg, BANK_UP ; addr
    lda mosNUM
    pha
    lda mosNUM+1
    pha
    lda #4                      ; n: 1024 (n DIV 256 = 4)
    sta mosTMP+3
    farcall bvc.s6_skipsp, BANK_UP
    cmp #13
    beq m5_n
    farcall bvc.bv_arg, BANK_UP
    lda mosNUM                  ; 256 * (1, 2, 4, 8 or 16)
    bne m5_badn
    lda mosNUM+1
    sta mosTMP+3
    beq m5_badn
    cmp #17
    bcs m5_badn
    sec                         ; (a power of two: n AND (n-1) = 0)
    sbc #1
    and mosTMP+3
    beq m5_n
m5_badn:
    brk
    dta 254, 'Entries: 256 to 4096', 0
m5_n:
    farcall bvc.s6_end, BANK_UP
    pla
    sta mosPTR2+1
    pla
    sta mosPTR2
    lda mosPTR2+1               ; addr >= PAGE
    cmp BAS_PAGE
    bcc m5_bad
    lda mosTMP+3                ; end = addr + 4n (pages: 4 * n DIV 256)
    asl
    asl
    clc
    adc mosPTR2+1
    bcs m5_bad
    sta mosTMP                  ; HIMEM - end >= 0
    lda BAS_HIMEM
    cmp mosPTR2
    lda BAS_HIMEM+1
    sbc mosTMP
    bcs m5_ok
m5_bad:
    brk
    dta 254, 'Bad address (between PAGE and HIMEM)', 0
m5_ok:
    ldx #0                      ; the image to MOSBUF (over 128 bytes:
m5_cp:                          ; counted up, not with bpl)
    lda m5_img,x
    sta MOSBUF,x
    inx
    cpx #M5_LEN
    bne m5_cp
    lda mosTMP+2
    sta m5r.m5k
    lda #0
    sta m5r.m5i
    sta m5r.m5i+1
m5_ent:
    jsr m5r.m5_val              ; (in RAM) entry m5i -> m5R
    ldy #3
m5_st:
    lda m5r.m5R,y
    sta (mosPTR2),y
    dey
    bpl m5_st
    lda mosPTR2
    clc
    adc #4
    sta mosPTR2
    bcc m5_nx
    inc mosPTR2+1
m5_nx:
    inc m5r.m5i                 ; the next i, up to n (n DIV 256 in
    bne m5_ent                  ; mosTMP+3)
    inc m5r.m5i+1
    lda m5r.m5i+1
    cmp mosTMP+3
    bcc m5_ent
    rts

; m5_is: C = 1 if the word at m5_wsqr+X (0-terminated, upper case) is at
; mosPTR/Y (any case, no letter after it); then Y is past it. X: the
; kind (its offset). Uses A, mosTMP.
m5_is:
    stx mosTMP
    sty mosTMP+1
m5i_c:
    lda m5_wsqr,x
    beq m5i_end
    eor (mosPTR),y
    and #$DF
    bne m5i_no
    inx
    iny
    bne m5i_c
m5i_end:
    lda (mosPTR),y
    and #$DF
    cmp #'A'
    bcc m5i_yes
    cmp #'Z'+1
    bcc m5i_no
m5i_yes:
    ldx mosTMP
    sec
    rts
m5i_no:
    ldx mosTMP
    ldy mosTMP+1
    clc
    rts
m5_wsqr     dta 'SQR', 0
m5_wrec     dta 'RECIP', 0

; ----------------------------------------------------------------------------
; The RAM image (run in MOSBUF)
m5_img:
    .local m5r
    org MOSBUF, m5_img

; Variables: the top of MOSBUF, outside the copied code
M5_VARS     = $E8
m5k         = MOSBUF+M5_VARS    ; 0 SQR, else RECIP
m5i         = MOSBUF+M5_VARS+1  ; 2: this entry
m5N         = MOSBUF+M5_VARS+3  ; 6: radicand / dividend (quotient at +3)
m5M         = MOSBUF+M5_VARS+9  ; 4: remainder (follows N: one rotation)
m5R         = MOSBUF+M5_VARS+13 ; 4: root / the value
m5T         = MOSBUF+M5_VARS+17 ; 4: trial (to MOSBUF+$FC)

; m5_val
;   Summary: m5R = SQR(m5i) * 65536 (m5k = 0) or 65536 / m5i (else),
;            rounded, 32 bits.
;   Function: square root: N = i * 2^34, 24 times two bits of N into the
;            remainder M, trial T = 4R + 1, M >= T: M - T and a 1 bit
;            into the root R; R = 2 * SQR(i) * 65536, so (R + 1) DIV 2 is
;            it rounded. Reciprocal: N+3 = 65536 + i DIV 2, 24 steps of
;            shift and subtract (i = 0 gives &FFFFFF: the top byte &7F).
;   Uses:    A, X, Y, the variables above.
m5_val:
    ldx #17                     ; N, M, R, T: 0
    lda #0
m5_clr:
    sta m5N,x
    dex
    bpl m5_clr
    lda m5k
    bne m5_rec
    lda m5i                     ; N = i * 2^34
    asl
    sta m5N+4
    lda m5i+1
    rol
    sta m5N+5
    asl m5N+4
    rol m5N+5
    ldy #24
m5_sq:
    clc                         ; two bits of N into M
    jsr m5_rot10
    clc
    jsr m5_rot10
    ldx #3                      ; T = 4R + 1
m5_tr:
    lda m5R,x
    sta m5T,x
    dex
    bpl m5_tr
    clc
    ldx #$FC
    jsr m5_rlT
    sec
    ldx #$FC
    jsr m5_rlT
    sec                         ; T = M - T; C = 1: M >= T
    ldx #0
m5_sub:
    lda m5M,x
    sbc m5T,x
    sta m5T,x
    inx
    txa
    eor #4
    bne m5_sub
    bcc m5_bit
    ldx #3                      ; M = M - T (C stays 1)
m5_mv:
    lda m5T,x
    sta m5M,x
    dex
    bpl m5_mv
m5_bit:
    ldx #$F8                    ; R = 2R + C (T's rotation, 4 back)
    jsr m5_rlT
    dey
    bne m5_sq
    inc m5R                     ; (R + 1) DIV 2
    bne m5_half
    inc m5R+1
    bne m5_half
    inc m5R+2
m5_half:
    lsr m5R+2
    ror m5R+1
    ror m5R
    jmp m5_store
m5_rec:
    lda m5i+1                   ; N+3.. = 65536 + i DIV 2 (rounding)
    lsr
    sta m5N+4
    lda m5i
    ror
    sta m5N+3
    inc m5N+5
    ldy #24                     ; N+3.. = it DIV i, M: the remainder
m5_dl:
    clc
    ldx #$F9
    jsr m5_rl
    lda m5M
    sec
    sbc m5i
    tax
    lda m5M+1
    sbc m5i+1
    bcc m5_dn
    sta m5M+1
    stx m5M
    inc m5N+3
m5_dn:
    dey
    bne m5_dl
    ldx #2
m5_q:
    lda m5N+3,x
    sta m5R,x
    dex
    bpl m5_q
    lda m5i                     ; i = 0: &7FFFFFFF
    ora m5i+1
    bne m5_store
    lda #$7F
    sta m5R+3
m5_store:
    rts

; m5_rot10: N and M (10 bytes) rotated left through C; m5_rl: from
; m5N+10+X-256 to M's end; m5_rlT: from m5T+4+X-256 to T's end (X = $FC:
; T; $F8: R, and T after it, harmless: T is made anew each step). X
; negative: inx keeps C.
m5_rot10:
    ldx #$F6
m5_rl:
    rol m5N+10-256,x
    inx
    bne m5_rl
    rts
m5_rlT:
    rol m5T+4-256,x
    inx
    bne m5_rlT
    rts
m5_end:
    .endl
M5_LEN      = m5r.m5_end - MOSBUF
    org m5_img + M5_LEN
    .if M5_LEN > m5r.M5_VARS
    .error "The *TABLE image runs into its variables"
    .endif

    .endl
