; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *TABLE: integer maths tables for programs (bank 8)
;
; DESIGN_GRAPHICS.md section 4, option (a), decided 2026-10-07 (PLAN 19),
; built 2026-10-16 for the Schraf demos: BBC BASIC's SIN takes about
; 775 us at 64 MHz, a table read about 30 us. The interpreter stays
; unchanged; a program asks for a table in its own memory:
;   DIM S% 4095:*TABLE SIN S%
;   S%!(4*(A% AND 1023)) = SIN(A% * PI / 512) * 65536, rounded
; 1024 steps a full turn, 32-bit values (65536 = 1). COS the same, a
; quarter turn on. *TABLE SIN S% 256 (or 512) makes a smaller table, a
; full turn in 256 steps (1K: BASIC has under 5K in MODE 2 on Upic Lite,
; 2026-10-16); COS is then S%!(4*((A%+64) AND 255)). The cartridge holds a quarter wave (genmath.py, 514
; bytes); the rest follows by symmetry.
;
; ----------------------------------------------------------------------------

    .local mtab

BAS_HIMEM   = $06               ; BBC BASIC's HIMEM (2), PAGE (high byte)
BAS_PAGE    = $18
TB_COS      = mosARGS           ; 1 for COS (a quarter turn on)
TB_I        = mosTMP            ; 2: the entry (0-1023)
TB_IDX      = mosTMP+2          ; the quarter wave's entry (0-255; with
TB_TOP      = mosTMP+3          ; TB_TOP 1: entry 256, 65536)
TB_STEP     = mosARGS+1         ; 1024 / steps: 1, 2 or 4

; ----------------------------------------------------------------------------
; cmd_tab
;   Summary: *TABLE SIN|COS addr [steps]: steps (1024, 512 or 256; 1024
;            when not given) 32-bit values of SIN or COS (x 65536, a full
;            turn in that many steps) to addr.
;   Function: checks that addr .. addr + 4095 lie between PAGE and HIMEM
;            ("Bad address"), then for each entry i: the angle k = i (+
;            256 for COS) AND 1023; quarter k DIV 256, r = k AND 255;
;            quarters 1 and 3 read the quarter wave backwards (256 - r),
;            quarters 2 and 3 negate.
;   Input:   mosPTR/Y: SIN or COS, then a number or A%-Z% (bvcmd.s).
;   Output:  the table.  Uses: A, X, Y, mosTMP, mosARGS, mosPTR2, mosNUM.
cmd_tab:
    lda #<tw_sin
    ldx #>tw_sin
    jsr bvc.s6_word
    lda #0
    bcs ct_fn
    lda #<tw_cos
    ldx #>tw_cos
    jsr bvc.s6_word
    bcs ct_cos
    jmp bvc.s6_syntax
ct_cos:
    lda #1
ct_fn:
    sta TB_COS
    jsr bvc.bv_arg
    lda mosNUM                  ; (addr)
    pha
    lda mosNUM+1
    pha
    lda #1                      ; steps: 1024 (step 1, 16 pages)
    sta TB_STEP
    jsr bvc.s6_skipsp
    cmp #13
    beq ct_steps
    jsr bvc.bv_arg
    lda mosNUM
    bne ct_badst
    lda mosNUM+1
    ldx #4
    cmp #1                      ; 256: step 4
    beq ct_st
    ldx #2
    cmp #2                      ; 512: step 2
    beq ct_st
    ldx #1
    cmp #4
    beq ct_st
ct_badst:
    brk
    dta 254, 'Steps: 256, 512 or 1024', 0
ct_st:
    stx TB_STEP
ct_steps:
    jsr bvc.s6_end
    pla
    sta mosNUM+1
    pla
    sta mosNUM
    lda mosNUM+1                ; addr >= PAGE
    cmp BAS_PAGE
    bcc ct_bad
    lda #16                     ; the size in pages: 16 / step
    ldx TB_STEP
    cpx #1
    beq ct_pg
    lsr
    cpx #2
    beq ct_pg
    lsr
ct_pg:
    clc                         ; end = addr + size (low byte: addr's)
    adc mosNUM+1
    bcs ct_bad
    sta mosPTR2+1               ; (scratch)
    lda BAS_HIMEM               ; HIMEM - end >= 0
    cmp mosNUM
    lda BAS_HIMEM+1
    sbc mosPTR2+1
    bcs ct_ok
ct_bad:
    brk
    dta 254, 'Bad address (between PAGE and HIMEM)', 0
ct_ok:
    lda mosNUM
    sta mosPTR2
    lda mosNUM+1
    sta mosPTR2+1
    lda #0
    sta TB_I
    sta TB_I+1
ct_entry:
    lda #0
    sta TB_TOP
    lda TB_I+1                  ; the quarter
    clc
    adc TB_COS
    and #3
    tax
    lda TB_I                    ; r
    cpx #1
    beq ct_back
    cpx #3
    bne ct_fwd
ct_back:
    eor #$FF                    ; 256 - r (r = 0: entry 256)
    clc
    adc #1
    bne ct_fwd
    inc TB_TOP
ct_fwd:
    sta TB_IDX
    txa
    pha
    ldy TB_IDX                  ; the value: 0..65535, or 65536
    lda TB_TOP
    beq ct_tab
    lda #0
    tax
    ldy #1
    bne ct_val
ct_tab:
    lda sinq_lo,y
    tax
    lda sinq_hi,y
    ldy #0
ct_val:                         ; X low, A high, Y third byte
    sta TB_IDX
    pla
    cmp #2                      ; quarters 2 and 3: negative
    bcc ct_store
    txa                         ; 0 - value (32 bits)
    eor #$FF
    clc
    adc #1
    tax
    lda TB_IDX
    eor #$FF
    adc #0
    sta TB_IDX
    tya
    eor #$FF
    adc #0
    tay
    lda #$FF
    adc #0
    bne ct_neg                  ; (top byte: $FF, or 0 for 0)
ct_store:
    lda #0
ct_neg:
    pha                         ; the fourth byte
    tya
    pha                         ; the third
    txa
    ldy #0
    sta (mosPTR2),y
    iny
    lda TB_IDX
    sta (mosPTR2),y
    iny
    pla
    sta (mosPTR2),y
    iny
    pla
    sta (mosPTR2),y
    lda mosPTR2                 ; the next entry
    clc
    adc #4
    sta mosPTR2
    bcc ct_n
    inc mosPTR2+1
ct_n:
    lda TB_I                    ; the next angle: + 1024 / steps
    clc
    adc TB_STEP
    sta TB_I
    bcc ct_more
    inc TB_I+1
    lda TB_I+1
    cmp #4
    bcc ct_more
    rts
ct_more:
    jmp ct_entry

tw_sin      dta 'SIN', 0
tw_cos      dta 'COS', 0

    icl 'math_tables.s'

    .endl
