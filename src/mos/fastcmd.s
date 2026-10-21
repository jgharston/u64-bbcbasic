; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the RAM fast path for the BASIC V graphics commands
; (an image, assembled twice by fastpath.s and copied below HIMEM in the
; graphics modes; docs/DESIGN_GRAPHICS.md section 11)
;
; On CLIV while a graphics mode is on. *POINT, *LINE, *RECTANGLE [FILL],
; *CIRCLE [FILL] and *ELLIPSE [FILL] cost about 2 ms through the normal
; OSCLI path (bank 0 and bank 8 code runs from the cartridge at 1 MHz),
; a PLOT 0.06 ms: here they are recognised, their arguments read and their
; VDU bytes sent at turbo speed. They send exactly what bvcmd.s sends.
; Anything else, an abbreviation, or anything this path does not read
; cleanly (it raises no errors) goes on to the normal path (v_cli), which
; also gives the errors.
;
; Self-contained: no subroutine outside the image but OSWRCH and v_cli;
; zero page mosPTR, mosNUM (foreground MOS only, as all * commands).
;
; ----------------------------------------------------------------------------

; fc_cli
;   Summary: OSCLI through CLIV in the graphics modes.
;   Input:   X/Y = the command line (CR-terminated).
;   Output:  the command done, or the normal path taken.
;   Uses:    A, X, Y, mosPTR, mosNUM, the image's variables.
fc_cli:
    stx mosPTR
    sty mosPTR+1
    ldy #0
fc_skip:
    lda (mosPTR),y
    cmp #' '
    beq fc_sk1
    cmp #'*'
    bne fc_word
fc_sk1:
    iny
    bne fc_skip
fc_word:
    sty fc_y0
    ldx #0
fc_try:
    lda fc_names,x              ; the next name ($FF: none matched)
    cmp #$FF
    beq fc_back
    ldy fc_y0
fc_cmp:
    lda fc_names,x
    beq fc_endname
    sta fc_t
    lda (mosPTR),y
    and #$DF                    ; (upper case)
    cmp fc_t
    bne fc_next
    inx
    iny
    bne fc_cmp
fc_endname:
    lda (mosPTR),y              ; the word ends here (no letter follows)
    and #$DF
    cmp #'A'
    bcc fc_found
    cmp #'Z'+1
    bcs fc_found
fc_next:
    lda fc_names,x              ; past this name's 0 and opcode
    beq fc_nx2
    inx
    bne fc_next
fc_nx2:
    inx
    inx
    bne fc_try
fc_back:
    ldx mosPTR                  ; the normal path
    ldy mosPTR+1
    jmp v_cli
fc_found:
    lda fc_names+1,x
    sta fc_op
    lda #0
    sta fc_fill
    lda fc_op                   ; FILL (rectangle, circle, ellipse)
    cmp #2
    bcc fc_args
    jsr fc_sp
    sty fc_y0
    ldx #0
fc_fl:
    lda (mosPTR),y
    and #$DF
    cmp fc_wfill,x
    bne fc_nofill
    iny
    inx
    cpx #4
    bcc fc_fl
    lda (mosPTR),y
    and #$DF
    cmp #'A'
    bcc fc_isfill
    cmp #'Z'+1
    bcc fc_nofill
fc_isfill:
    inc fc_fill
    bne fc_args
fc_nofill:
    ldy fc_y0
fc_args:
    ldx fc_op                   ; the arguments into fc_a (16 bits each)
    lda fc_nargs,x
    sta fc_n
    ldx #0
fc_al:
    jsr fc_arg
    bcs fc_back
    lda mosNUM
    sta fc_a,x
    lda mosNUM+1
    sta fc_a+1,x
    inx
    inx
    dec fc_n
    bne fc_al
    lda fc_op                   ; RECTANGLE: h is w unless given
    cmp #2
    bne fc_end
    lda fc_a+4
    sta fc_a+6
    lda fc_a+5
    sta fc_a+7
    jsr fc_sp
    cmp #13
    beq fc_go
    jsr fc_arg
    bcs fc_bk
    lda mosNUM
    sta fc_a+6
    lda mosNUM+1
    sta fc_a+7
fc_end:
    jsr fc_sp                   ; nothing else on the line
    cmp #13
    beq fc_go
fc_bk:
    jmp fc_back
fc_go:
    lda fc_a                    ; the first point (MOVE, or the point)
    sta fc_px
    lda fc_a+1
    sta fc_px+1
    lda fc_a+2
    sta fc_py
    lda fc_a+3
    sta fc_py+1
    ldx fc_op
    bne fc_notpt
    lda #69                     ; *POINT x,y: PLOT 69
    jmp fc_plot
fc_notpt:
    lda #4
    jsr fc_plot
    ldx fc_op
    dex
    bne fc_notln
    lda fc_a+4                  ; *LINE: DRAW x2,y2
    sta fc_px
    lda fc_a+5
    sta fc_px+1
    lda fc_a+6
    sta fc_py
    lda fc_a+7
    sta fc_py+1
    lda #5
    jmp fc_plot
fc_notln:
    jsr fc_addw                 ; x + the third argument
    ldx fc_op
    cpx #4
    beq fc_ell
    cpx #3
    beq fc_circ
    jsr fc_addh                 ; *RECTANGLE: to x+w,y+h, 221 or 101
    lda #221
    ldx fc_fill
    beq fc_r
    lda #101
fc_r:
    jmp fc_plot
fc_circ:
    lda #149                    ; *CIRCLE: to x+r,y, 149 or 157
    ldx fc_fill
    beq fc_c
    lda #157
fc_c:
    jmp fc_plot
fc_ell:
    lda #4                      ; *ELLIPSE: MOVE x+a,y, then to x,y+b,
    jsr fc_plot                 ; 197 or 205
    lda fc_a
    sta fc_px
    lda fc_a+1
    sta fc_px+1
    jsr fc_addh
    lda #197
    ldx fc_fill
    beq fc_e
    lda #205
fc_e:
    jmp fc_plot

; fc_addw / fc_addh: fc_px += argument 3 / fc_py += argument 4
fc_addw:
    lda fc_px
    clc
    adc fc_a+4
    sta fc_px
    lda fc_px+1
    adc fc_a+5
    sta fc_px+1
    rts
fc_addh:
    lda fc_py
    clc
    adc fc_a+6
    sta fc_py
    lda fc_py+1
    adc fc_a+7
    sta fc_py+1
    rts

; fc_plot: VDU 25,A,fc_px;fc_py; (PLOT A,x,y)
fc_plot:
    pha
    lda #25
    jsr OSWRCH
    pla
    jsr OSWRCH
    ldx #0                      ; x and y (fc_px, fc_py: 4 bytes in a row)
fp_b:
    lda fc_px,x
    jsr OSWRCH
    inx
    cpx #4
    bne fp_b
    rts

; fc_sp: A = the next character that is not a space (Y on it)
fc_sp:
    lda (mosPTR),y
    cmp #' '
    bne fc_sprts
    iny
    bne fc_sp
fc_sprts:
    rts

; fc_arg: an argument as bvcmd.s reads it (spaces, an optional comma, then
; A%-Z% or a number: -, decimal or &hex): mosNUM, C = 0; C = 1 if none.
; Uses: A, Y, mosNUM, fc_t, fc_neg.
fc_arg:
    jsr fc_sp
    cmp #','
    bne fa_go
    iny
    jsr fc_sp
fa_go:
    and #$DF                    ; a letter followed by %: A%-Z%
    cmp #'A'
    bcc fa_num
    cmp #'Z'+1
    bcs fa_num
    sta fc_t
    iny
    lda (mosPTR),y
    cmp #'%'
    beq fa_var
    sec                         ; (no: none)
    rts
fa_var:
    iny
    stx fc_x
    lda fc_t
    sec                         ; &0400 + (letter - '@') * 4
    sbc #'@'
    asl
    asl
    tax
    lda $0400,x
    sta mosNUM
    lda $0401,x
    sta mosNUM+1
    ldx fc_x
    clc
    rts
fa_num:
    lda #0
    sta fc_neg
    sta mosNUM
    sta mosNUM+1
    lda (mosPTR),y
    cmp #'-'
    bne fa_sign
    inc fc_neg
    iny
    lda (mosPTR),y
fa_sign:
    cmp #'&'
    beq fa_hex
    jsr fa_dig
    bcs fa_none
fa_dl:
    lda (mosPTR),y              ; mosNUM = mosNUM * 10 + digit
    jsr fa_dig
    bcs fa_done
    sta fc_t
    lda mosNUM
    sta fc_t+1
    lda mosNUM+1
    asl mosNUM
    rol mosNUM+1
    asl mosNUM
    rol mosNUM+1
    pha
    lda mosNUM
    clc
    adc fc_t+1
    sta mosNUM
    pla
    adc mosNUM+1
    sta mosNUM+1
    asl mosNUM
    rol mosNUM+1
    lda mosNUM
    clc
    adc fc_t
    sta mosNUM
    bcc fa_dn
    inc mosNUM+1
fa_dn:
    iny
    bne fa_dl
fa_hex:
    iny
    lda (mosPTR),y
    jsr fa_hdig
    bcs fa_none
fa_hl:
    lda (mosPTR),y
    jsr fa_hdig
    bcs fa_done
    sta fc_t
    lda mosNUM                  ; mosNUM = mosNUM * 16 + digit
    asl
    rol mosNUM+1
    asl
    rol mosNUM+1
    asl
    rol mosNUM+1
    asl
    rol mosNUM+1
    ora fc_t
    sta mosNUM
    iny
    bne fa_hl
fa_done:
    lda fc_neg                  ; negative: 0 - the number
    beq fa_ok
    lda #0
    sec
    sbc mosNUM
    sta mosNUM
    lda #0
    sbc mosNUM+1
    sta mosNUM+1
fa_ok:
    clc
    rts
fa_none:
    sec
    rts

; fa_dig: A a decimal digit -> 0-9, C = 0; C = 1 if not
fa_dig:
    cmp #'0'
    bcc fd_no
    cmp #'9'+1
    bcs fd_no
    sbc #'0'-1                  ; (C = 0 here: subtracts '0')
    clc
    rts
fd_no:
    sec
    rts

; fa_hdig: A a hex digit (0-9, A-F, a-f) -> 0-15, C = 0; C = 1 if not
fa_hdig:
    jsr fa_dig
    bcc fh_rts
    and #$DF
    cmp #'A'
    bcc fd_no
    cmp #'F'+1
    bcs fd_no
    sbc #'A'-11                 ; (C = 0: A-10)
    clc
fh_rts:
    rts

; The names (upper case, 0, the operation), $FF at the end
fc_names:
    dta 'POINT', 0, 0
    dta 'LINE', 0, 1
    dta 'RECTANGLE', 0, 2
    dta 'CIRCLE', 0, 3
    dta 'ELLIPSE', 0, 4
    dta $FF
fc_nargs    dta 2, 4, 3, 3, 4   ; arguments per operation (RECTANGLE: 3,
                                ; a 4th optional)
fc_wfill    dta 'FILL'

; Variables (RAM: the image is in RAM)
fc_y0       dta 0
fc_t        dta 0, 0
fc_x        dta 0
fc_op       dta 0
fc_fill     dta 0
fc_n        dta 0
fc_neg      dta 0
fc_a        dta 0, 0, 0, 0, 0, 0, 0, 0
fc_px       dta 0, 0
fc_py       dta 0, 0
fc_image_end:
