; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- BASIC V graphics as * commands, bank 8
;
; The Archimedes' graphics statements as MOS commands, for writing new
; programs (the interpreter stays BASIC 3.10): each
; becomes the BBC's VDU sequence, so it works in every graphics mode.
;   *RECTANGLE [FILL] x,y,w[,h]  *CIRCLE [FILL] x,y,r  *LINE x1,y1,x2,y2
;   *ELLIPSE [FILL] x,y,a,b      *POINT x,y            *COLOUR n,r,g,b
;   *GCOL [a,]c TINT t           *OFF  *ON
; An argument is a number (decimal, &hex, negative) or one of BASIC's
; resident integer variables A%-Z%, read from &0404 + 4 n (no
; expressions). *GCOL c TINT t chooses the logical colour whose palette
; RGB is nearest to the Archimedes 256-colour one.
;
; ----------------------------------------------------------------------------

    .local bvc
    icl 'bankhelp.s'

; Variables in MOSBUF (RAM: this bank is ROM; not MOSBUF+$C0-$DA, the
; line editor's state)
BV_PAL      = MOSBUF+$00        ; *GCOL TINT: the 16 palette RGBs (48),
                                ; the C64 colours' (48) after them
BVA_BUF     = MOSBUF+$60        ; up to 4 arguments, 16 bits each
bv_x        = MOSBUF+$68        ; the point to plot (2)
bv_y        = MOSBUF+$6A        ; (2)
bv_k        = MOSBUF+$6C        ; FILL given
bv_t        = MOSBUF+$6D        ; scratch
bv_rgb      = MOSBUF+$6E        ; *GCOL TINT: the wanted RGB (3)
bv_bd       = MOSBUF+$71        ; the best distance (2)
bv_best     = MOSBUF+$73        ; its logical colour
bv_d        = MOSBUF+$74        ; a distance (2)
bv_l        = MOSBUF+$76        ; the logical colour looked at

; ----------------------------------------------------------------------------
; bv_args
;   Summary: parse X arguments (2 to 4) into BVA_BUF, then the line's end.
;   Function: commas or spaces between them; each a number or A%-Z%.
;   Input:   mosPTR/Y, X = count.  Output: BVA_BUF; "Syntax" otherwise.
;   Uses:    A, X, Y, mosNUM, mosTMP.
bv_args:
    stx mosTMP+3
    ldx #0
bva_next:
    stx mosTMP+2
    jsr bv_arg
    ldx mosTMP+2
    lda mosNUM
    sta BVA_BUF,x
    lda mosNUM+1
    sta BVA_BUF+1,x
    inx
    inx
    txa
    lsr
    cmp mosTMP+3
    bcc bva_next
    jmp s6_end

; bv_arg: one argument into mosNUM (16 bits, two's complement)
bv_arg:
    jsr s6_skipsp
    cmp #','
    bne bvg_go
    iny
    jsr s6_skipsp
bvg_go:
    jsr s6_up
    cmp #'A'
    bcc bvg_num
    cmp #'Z'+1
    bcs bvg_num
    pha                         ; a letter: A%-Z%?
    iny
    lda (mosPTR),y
    dey
    cmp #'%'
    beq bvg_var
    pla
    jmp s6_syntax
bvg_var:
    pla
    sec                         ; &0400 + (letter - '@') * 4
    sbc #'@'
    asl
    asl
    tax
    lda $0400,x
    sta mosNUM
    lda $0401,x
    sta mosNUM+1
    iny
    iny
    rts
bvg_num:
    lda (mosPTR),y
    cmp #'-'
    bne bvg_pos
    iny
    jsr s6_need
    lda #0                      ; negative
    sec
    sbc mosNUM
    sta mosNUM
    lda #0
    sbc mosNUM+1
    sta mosNUM+1
    rts
bvg_pos:
    jmp s6_need

; bv_fill: C = 1 and Y past it when the word FILL follows
bv_fill:
    lda #<wd_fill
    ldx #>wd_fill
    jmp s6_word

; ----------------------------------------------------------------------------
; bv_plotxy: VDU 25,A,bv_x;bv_y; (PLOT A,bv_x,bv_y)
bv_plotxy:
    pha
    lda #25
    jsr OSWRCH
    pla
    jsr OSWRCH
    lda bv_x
    jsr OSWRCH
    lda bv_x+1
    jsr OSWRCH
    lda bv_y
    jsr OSWRCH
    lda bv_y+1
    jmp OSWRCH

; bv_xy: bv_x/bv_y = argument pair X (offset: 0 = args 1-2, 4 = 3-4)
bv_xy:
    lda BVA_BUF,x
    sta bv_x
    lda BVA_BUF+1,x
    sta bv_x+1
    lda BVA_BUF+2,x
    sta bv_y
    lda BVA_BUF+3,x
    sta bv_y+1
    rts

; bv_addx / bv_addy: bv_x += argument X / bv_y += argument X
bv_addx:
    lda bv_x
    clc
    adc BVA_BUF,x
    sta bv_x
    lda bv_x+1
    adc BVA_BUF+1,x
    sta bv_x+1
    rts
bv_addy:
    lda bv_y
    clc
    adc BVA_BUF,x
    sta bv_y
    lda bv_y+1
    adc BVA_BUF+1,x
    sta bv_y+1
    rts

; bv_move: MOVE to the first two arguments
bv_move:
    ldx #0
    jsr bv_xy
    lda #4
    jmp bv_plotxy

; ----------------------------------------------------------------------------
; cmd_rectangle: *RECTANGLE [FILL] x,y,w[,h] (h = w if left out):
; MOVE x,y, then PLOT 101 (filled) or 221 (outline, U64) to x+w,y+h
cmd_rectangle:
    jsr bv_fill
    lda #0
    rol
    sta bv_k                    ; 1: FILL
    jsr bv_arg                  ; x, y, w
    lda mosNUM
    sta BVA_BUF
    lda mosNUM+1
    sta BVA_BUF+1
    jsr bv_arg
    lda mosNUM
    sta BVA_BUF+2
    lda mosNUM+1
    sta BVA_BUF+3
    jsr bv_arg
    lda mosNUM
    sta BVA_BUF+4
    sta BVA_BUF+6
    lda mosNUM+1
    sta BVA_BUF+5
    sta BVA_BUF+7
    jsr s6_skipsp               ; h (optional)
    cmp #13
    beq bvr_go
    jsr bv_arg
    lda mosNUM
    sta BVA_BUF+6
    lda mosNUM+1
    sta BVA_BUF+7
    jsr s6_end
bvr_go:
    jsr bv_move
    ldx #4
    jsr bv_addx
    ldx #6
    jsr bv_addy
    lda #221
    ldx bv_k
    beq bvr_k
    lda #101
bvr_k:
    jmp bv_plotxy

; cmd_circle: *CIRCLE [FILL] x,y,r: MOVE x,y, PLOT 149/157 (absolute) to
; x+r,y
cmd_circle:
    jsr bv_fill
    lda #0
    rol
    sta bv_k
    ldx #3
    jsr bv_args
    jsr bv_move
    ldx #4
    jsr bv_addx
    lda #149
    ldx bv_k
    beq bvc_k
    lda #157
bvc_k:
    jmp bv_plotxy

; cmd_ellipse: *ELLIPSE [FILL] x,y,a,b: MOVE x,y, MOVE x+a,y, PLOT 197/205
; to x,y+b (the BBC's ellipse: centre, end of the horizontal axis, height)
cmd_ellipse:
    jsr bv_fill
    lda #0
    rol
    sta bv_k
    ldx #4
    jsr bv_args
    jsr bv_move
    ldx #4
    jsr bv_addx
    lda #4
    jsr bv_plotxy
    ldx #0
    jsr bv_xy
    ldx #6
    jsr bv_addy
    lda #197
    ldx bv_k
    beq bve_k
    lda #205
bve_k:
    jmp bv_plotxy

; cmd_line: *LINE x1,y1,x2,y2: MOVE, DRAW
cmd_line:
    ldx #4
    jsr bv_args
    jsr bv_move
    ldx #4
    jsr bv_xy
    lda #5
    jmp bv_plotxy

; cmd_point: *POINT x,y: PLOT 69
cmd_point:
    ldx #2
    jsr bv_args
    ldx #0
    jsr bv_xy
    lda #69
    jmp bv_plotxy

; cmd_colour: *COLOUR n,r,g,b: VDU 19,n,16,r,g,b
cmd_colour:
    ldx #4
    jsr bv_args
    lda #19
    jsr OSWRCH
    lda BVA_BUF
    jsr OSWRCH
    lda #16
    jsr OSWRCH
    lda BVA_BUF+2
    jsr OSWRCH
    lda BVA_BUF+4
    jsr OSWRCH
    lda BVA_BUF+6
    jmp OSWRCH

; cmd_off / cmd_on: the text cursor (VDU 23,1,n;0;0;0;)
cmd_off:
    jsr s6_end
    lda #0
    beq bvo_go
cmd_on:
    jsr s6_end
    lda #1
bvo_go:
    pha
    lda #23
    jsr OSWRCH
    lda #1
    jsr OSWRCH
    pla
    jsr OSWRCH
    ldx #7
bvo_zero:
    lda #0
    jsr OSWRCH
    dex
    bne bvo_zero
    rts

; ----------------------------------------------------------------------------
; cmd_gcol
;   Summary: *GCOL [a,]c TINT t: the Archimedes 256-colour c (0-63) with
;            tint t (0, 64, 128, 192) as the nearest logical colour.
;   Function: RGB (4 bits each, x 17): red = (c AND 3) * 4 + t DIV 64,
;            green = (c DIV 4 AND 3) * 4 + ..., blue = (c DIV 16 AND 3) *
;            4 + ...; then the logical colour 0..ncol-1 whose palette RGB
;            is nearest (sum of the differences): Upic full the picture's
;            palette, Upic Lite and teletext REU_LRGB, the VIC-II modes
;            the C64 colour pal[l] (REU_PAL64); VDU 18,a,l.
;   Uses:    A, X, Y, fs*, mosTMP, BVA_BUF, BV_PAL.
cmd_gcol:
    jsr bv_arg                  ; [a,]c
    lda mosNUM
    sta BVA_BUF+2               ; c (if no action follows)
    lda #0
    sta BVA_BUF                 ; action 0
    jsr s6_skipsp
    cmp #','
    bne bvgc_tint
    lda BVA_BUF+2
    sta BVA_BUF
    jsr bv_arg
    lda mosNUM
    sta BVA_BUF+2
bvgc_tint:
    lda #<wd_tint
    ldx #>wd_tint
    jsr s6_word
    bcs bvgc_t
    jmp s6_syntax
bvgc_t:
    jsr bv_arg
    jsr s6_end
    lda mosNUM                  ; tint bits (0-3)
    rol
    rol
    rol
    and #3
    sta mosTMP
    lda BVA_BUF+2               ; the three components, 0-15, x 17
    ldx #0
bvgc_comp:
    pha
    and #3
    asl
    asl
    ora mosTMP
    sta bv_t                    ; * 17 = * 16 + 1
    asl
    asl
    asl
    asl
    ora bv_t
    sta bv_rgb,x
    pla
    lsr
    lsr
    inx
    cpx #3
    bcc bvgc_comp
    jsr s6_hasreu
    bne bvgc_reu
    brk
    dta 254, 'TINT needs an REU', 0
bvgc_reu:
    jsr bv_palette              ; BV_PAL: the logical colours' RGBs
    lda #$FF                    ; the nearest: bv_best (distance bv_bd)
    sta bv_bd
    sta bv_bd+1
    lda #0
    sta bv_best
    ldx #0                      ; logical colour X, RGB at BV_PAL + 3X
    ldy #0
bvgc_l:
    lda #0
    sta bv_d
    sta bv_d+1
    stx bv_l
    ldx #0
bvgc_c:
    lda BV_PAL,y
    sec
    sbc bv_rgb,x
    bcs bvgc_pos
    eor #$FF
    adc #1
bvgc_pos:
    clc
    adc bv_d
    sta bv_d
    bcc bvgc_nc
    inc bv_d+1
bvgc_nc:
    iny
    inx
    cpx #3
    bcc bvgc_c
    ldx bv_l
    lda bv_d                    ; nearer than the best so far?
    cmp bv_bd
    lda bv_d+1
    sbc bv_bd+1
    bcs bvgc_far
    lda bv_d
    sta bv_bd
    lda bv_d+1
    sta bv_bd+1
    stx bv_best
bvgc_far:
    inx
    cpx vmode_ncol
    bcc bvgc_l
    lda #18                     ; VDU 18,a,l
    jsr OSWRCH
    lda BVA_BUF
    jsr OSWRCH
    lda bv_best
    jmp OSWRCH

; bv_palette: BV_PAL = the RGB of logical colours 0-15 in this mode
bv_palette:
    lda #<BV_PAL
    sta fsADDR
    lda #>BV_PAL
    sta fsADDR+1
    lda #48
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda eng_kind
    cmp #3
    bne bvp_n3
    lda #$D0                    ; Upic full: the picture's header
    sta fsTMP
    lda #0
    sta fsTMP+1
    lda #UPIC_BANK
    sta fsTMP+2
    lda #REU_TO_C64
    jmp upic.up_dma
bvp_n3:
    lda #REU_FONT_BANK
    sta fsTMP+2
    lda eng_kind
    beq bvp_vic
    lda #<REU_LRGB              ; Upic Lite, teletext
    sta fsTMP
    lda #>REU_LRGB
    sta fsTMP+1
    lda #REU_TO_C64
    jmp upic.up_dma
bvp_vic:
    lda #<REU_PAL64             ; the VIC-II: C64 colour pal[l] (the C64
    sta fsTMP                   ; colours at BV_PAL+48, then in order)
    lda #>REU_PAL64
    sta fsTMP+1
    lda #<[BV_PAL+48]
    sta fsADDR
    lda #>[BV_PAL+48]
    sta fsADDR+1
    lda #REU_TO_C64
    jsr upic.up_dma
    ldx #0
    ldy #0
bvp_l:
    stx bv_l
    lda pal,x
    and #15
    sta bv_t
    asl
    adc bv_t
    tax
    lda BV_PAL+48,x
    sta BV_PAL,y
    lda BV_PAL+49,x
    sta BV_PAL+1,y
    lda BV_PAL+50,x
    sta BV_PAL+2,y
    iny
    iny
    iny
    ldx bv_l
    inx
    cpx #16
    bcc bvp_l
    rts

wd_fill     dta 'FILL', 0
wd_tint     dta 'TINT', 0
    .endl
