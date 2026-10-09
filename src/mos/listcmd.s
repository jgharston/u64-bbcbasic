; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *LIST: the program, indented by its structure (bank 2)
;
; PLAN.md section 20: BASIC's LISTO indents FOR/NEXT and REPEAT/UNTIL,
; not procedure bodies; *LIST indents those too, without changing the
; interpreter. The keywords come from build/gen/list_tokens.s
; (tools/genlist.py, the interpreter's own token table).
;
; Program at PAGE: CR, then per line: line number high, low, length (from
; the high byte to the CR), the tokenised text, CR; a high byte $FF ends.
;
; ----------------------------------------------------------------------------

LT_FOR      = $E3               ; tokens that open and close levels
LT_NEXT     = $ED
LT_REPEAT   = $F5
LT_UNTIL    = $FD
LT_DEF      = $DD
LT_PROC     = $F2
LT_ENDPROC  = $E1
LT_FN       = $A4
LT_REM      = $F4
LT_DATA     = $DC
LT_CONST    = $8D               ; a line number constant (3 bytes follow)

ls_level    = fsSX              ; indentation level
ls_print    = fsSY              ; the level this line is printed at
ls_delta    = fsCNT             ; the line's effect (signed)
ls_fn       = fsCNT+1           ; multi-line DEF FNs open
ls_quote    = fsCH              ; inside a string
ls_len      = fsLEN             ; the line's length
ls_y        = fsLEN+1           ; scan position
ls_from     = fsADDR            ; 2: first line to list
ls_to       = fsTMP+2           ; 2: last line to list

; ----------------------------------------------------------------------------
; cmd_list
;   Summary: *LIST [from][,[to]]: list the program indented: two spaces per
;            level of DEF PROC .. ENDPROC, a multi-line DEF FN .. "=",
;            FOR .. NEXT and REPEAT .. UNTIL.
;   Function: line ranges as LIST: "*LIST 100" that line, "*LIST 100,"
;            from it, "*LIST ,200" up to it, "*LIST 100,200". The text's
;            own leading spaces are replaced by the indentation; a line
;            that starts with a closer (NEXT, UNTIL, ENDPROC, "=") is
;            printed one level out. ESCAPE stops.
;   Input:   mosPTR/Y.  Output: the listing.  Uses: A, X, Y, fs*, mosTMP.
cmd_list:
    lda #0                      ; whole program by default
    sta ls_from
    sta ls_from+1
    lda #$FF
    sta ls_to
    sta ls_to+1
    jsr ci_skipsp
    cmp #','
    beq cl_comma
    jsr arg_number
    bcs cl_go                   ; nothing: all
    lda mosNUM
    sta ls_from
    sta ls_to
    lda mosNUM+1
    sta ls_from+1
    sta ls_to+1
    jsr ci_skipsp
    cmp #','
    bne cl_go                   ; one number: that line only
    lda #$FF
    sta ls_to
    sta ls_to+1
cl_comma:
    iny                         ; ",": the end follows (or not)
    jsr arg_number
    bcs cl_go
    lda mosNUM
    sta ls_to
    lda mosNUM+1
    sta ls_to+1
cl_go:
    jsr ff_end
    lda #0
    sta ls_level
    sta ls_fn
    sta fsBLK                   ; fsBLK -> the first line (PAGE + 1)
    lda zpTXTP
    sta fsBLK+1
    inc fsBLK
cl_line:
    bit ESCFLG
    bmi cl_rts
    ldy #0
    lda (fsBLK),y               ; high byte $FF: the end
    bmi cl_rts
    ldy #2
    lda (fsBLK),y
    sta ls_len
    jsr ls_scan                 ; ls_print, the level after the line
    jsr ls_inrange
    bcc cl_next
    jsr ls_show
cl_next:
    lda fsBLK                   ; next line
    clc
    adc ls_len
    sta fsBLK
    bcc cl_line
    inc fsBLK+1
    bne cl_line
cl_rts:
    rts

; ls_inrange: C = 1 if the line number lies in ls_from..ls_to
ls_inrange:
    ldy #1
    lda (fsBLK),y               ; number >= from?
    cmp ls_from
    dey
    lda (fsBLK),y
    sbc ls_from+1
    bcc lir_rts
    lda ls_to                   ; to >= number?
    ldy #1
    cmp (fsBLK),y
    lda ls_to+1
    dey
    sbc (fsBLK),y
lir_rts:
    rts

; ----------------------------------------------------------------------------
; ls_scan
;   Summary: the line's effect on the indentation: ls_print = the level
;            it is printed at, ls_level = the level after it.
;   Function: openers FOR, REPEAT, DEF PROC, DEF FN without "=" on the
;            line: +1; closers NEXT, UNTIL, ENDPROC: -1; "=" at the start
;            of a line while a multi-line FN is open: -1. A line starting
;            with a closer is printed one level out. Strings, REM and
;            DATA are skipped.
;   Uses:    A, X, Y.
ls_scan:
    lda #0
    sta ls_delta
    sta ls_quote
    jsr ls_first                ; Y at the first character, A = it
    ldx #0                      ; X = 1: the line starts with a closer
    cmp #LT_NEXT
    beq lsc_lead
    cmp #LT_UNTIL
    beq lsc_lead
    cmp #LT_ENDPROC
    beq lsc_lead
    cmp #'='
    bne lsc_scan
    lda ls_fn                   ; "=": closes a multi-line FN
    beq lsc_scan
    dec ls_fn
    dec ls_delta
lsc_lead:
    inx
lsc_scan:
    stx ls_print                ; (the lead, for now)
lsc_byte:
    cpy ls_end
    bcs lsc_done
    lda (fsBLK),y
    iny
    cmp #'"'
    bne lsc_nq
    lda ls_quote
    eor #1
    sta ls_quote
    jmp lsc_byte
lsc_nq:
    ldx ls_quote
    bne lsc_byte
    cmp #LT_REM
    beq lsc_done
    cmp #LT_DATA
    beq lsc_done
    cmp #LT_CONST
    bne lsc_tok
    iny
    iny
    iny
    jmp lsc_byte
lsc_tok:
    cmp #LT_FOR
    beq lsc_open
    cmp #LT_REPEAT
    beq lsc_open
    cmp #LT_NEXT
    beq lsc_close
    cmp #LT_UNTIL
    beq lsc_close
    cmp #LT_ENDPROC
    beq lsc_close
    cmp #LT_DEF
    bne lsc_byte
    jsr ls_skipsp               ; DEF PROC / DEF FN
    cmp #LT_PROC
    beq lsc_open
    cmp #LT_FN
    bne lsc_byte
    jsr ls_hasq                 ; "=" further on: a one-line FN
    bcs lsc_byte
    inc ls_fn
lsc_open:
    inc ls_delta
    jmp lsc_byte
lsc_close:
    dec ls_delta
    jmp lsc_byte
lsc_done:
    lda ls_level                ; printed at level - lead (at least 0)
    sec
    sbc ls_print
    bcs lsc_pr
    lda #0
lsc_pr:
    sta ls_print
    lda ls_level                ; after the line: level + delta (>= 0)
    clc
    adc ls_delta
    bit ls_delta
    bpl lsc_set
    bcs lsc_set                 ; (adding a negative: no borrow)
    lda #0
lsc_set:
    sta ls_level
    rts

; ls_first: Y = the first non-space character of the line (offset 3 on),
; A = it; ls_end = the offset of the line's CR
ls_first:
    lda ls_len
    sec
    sbc #1
    sta ls_end
    ldy #3
ls_skipsp:
    cpy ls_end
    bcs lsf_rts
    lda (fsBLK),y
    cmp #' '
    bne lsf_rts
    iny
    bne ls_skipsp
lsf_rts:
    rts
ls_end      = fsTMP+1           ; offset of the line's CR

; ls_hasq: C = 1 if an "=" follows on the line (outside strings) from Y;
; Y kept
ls_hasq:
    sty fsTMP
    lda #0
    sta ls_quote
lhq_byte:
    cpy ls_end
    bcs lhq_no
    lda (fsBLK),y
    iny
    cmp #'"'
    bne lhq_nq
    lda ls_quote
    eor #1
    sta ls_quote
    jmp lhq_byte
lhq_nq:
    ldx ls_quote
    bne lhq_byte
    cmp #'='
    bne lhq_byte
    ldy fsTMP
    sec
    rts
lhq_no:
    ldy fsTMP
    lda #0
    sta ls_quote
    clc
    rts

; ----------------------------------------------------------------------------
; ls_show: the line: number (5 wide), a space, the indentation, the text
; (its own leading spaces left out), keywords spelt out
ls_show:
    ldy #0
    lda (fsBLK),y
    sta mosTMP+1
    iny
    lda (fsBLK),y
    sta mosTMP
    jsr cps_digits              ; fsTMP = digits: 5 - digits spaces
    lda #5
    sec
    sbc fsTMP
    tax
    beq lss_num
lss_pad:
    lda #' '
    jsr OSWRCH
    dex
    bne lss_pad
lss_num:
    jsr st_dec16
    lda ls_print                ; 1 + 2 * level spaces
    asl
    tax
    inx
lss_ind:
    lda #' '
    jsr OSWRCH
    dex
    bne lss_ind
    jsr ls_first
    lda #0
    sta ls_quote
lss_byte:
    cpy ls_end
    bcs lss_eol
    lda (fsBLK),y
    iny
    cmp #'"'
    bne lss_nq
    pha
    lda ls_quote
    eor #1
    sta ls_quote
    pla
lss_chr:
    jsr OSWRCH
    jmp lss_byte
lss_nq:
    ldx ls_quote
    bne lss_chr
    cmp #$80
    bcc lss_chr
    cmp #LT_CONST
    beq lss_const
    sty ls_y
    pha
    tax                         ; the keyword
    lda lt_lo-$80,x
    sta fsPTR
    lda lt_hi-$80,x
    sta fsPTR+1
    ldy #0
lss_kw:
    lda (fsPTR),y
    pha
    and #$7F
    beq lss_kwend               ; (no keyword: the empty entry)
    jsr OSWRCH
lss_kwend:
    pla
    iny
    asl
    bcc lss_kw
    pla                         ; REM, DATA: the rest as it is
    ldy ls_y
    cmp #LT_REM
    beq lss_raw
    cmp #LT_DATA
    bne lss_byte
lss_raw:
    cpy ls_end
    bcs lss_eol
    lda (fsBLK),y
    iny
    jsr OSWRCH
    jmp lss_raw
lss_const:
    lda (fsBLK),y               ; line number: SPGETN (basic.s)
    asl
    asl
    sta fsTMP                   ; x = b1 << 2
    and #$C0
    iny
    eor (fsBLK),y
    sta mosTMP                  ; lo = (x AND $C0) EOR b2
    lda fsTMP
    asl
    asl
    iny
    eor (fsBLK),y
    sta mosTMP+1                ; hi = (x << 2) EOR b3
    iny
    sty ls_y
    jsr st_dec16
    ldy ls_y
    jmp lss_byte
lss_eol:
    jmp OSNEWL

    icl 'list_tokens.s'
