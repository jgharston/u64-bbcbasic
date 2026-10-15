; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- BASIC toolkit: *SEARCH, *FIND, *REPLACE, *XREF,
; *VARLIST, *CRUNCH, *PACK (bank 7)
;
; In the style of Beebug's Toolkit Plus (owner, 2026-10-14; its manual
; scanned at 8bs.com, "Beebug Toolkit Plus"): *SEARCH s1[,s2] with the
; Parameters prompt, *XREF with its letters, *CRUNCH with letters that
; switch functions off. *FIND, *REPLACE, *VARLIST and *PACK are short
; forms. Variable names are never contracted (owner's decision).
; docs/DESIGN_ACORN.md 3.
;
; The program is at PAGE: CR, then lines (number high, low, length from
; the high byte to the CR, text, CR); a high byte with bit 7 ends it.
; Values are printed by BBC BASIC's own routines in its RAM copy (FLDA,
; FCON: BANK_RAM), its variables read from its catalogue at &0480.
;
; ----------------------------------------------------------------------------

    .local tk
    icl 'bankhelp.s'
    icl 'list_tokens.s'         ; lt_lo, lt_hi, lt_text (tools/genlist.py)

; BBC BASIC 3.10 (lib/bbc-basic; addresses from build/basic.lst: the
; interpreter is pinned, make compare-core)
B_FLDA      = $A3CB             ; FACC = the real at (zpARGP)
B_FCON      = $9EF5             ; STRACC = number (Y bit 7: FACC, else IACC)
B_SETFSA    = $BD23             ; LOMEM = VARTOP = TOP, catalogue cleared
zpTXTP      = $18               ; PAGE (high byte)
zpTOP       = $12               ; 2: TOP
zpHIMEM     = $06
zpIACC      = $2A
zpCLEN      = $36
zpARGP      = $4B
zpPRINTF    = $15
STRACC      = $0600
VARL        = $0400

T_CONST     = $8D               ; tokens
T_DATA      = $DC
T_DEF       = $DD
T_IF        = $E7
T_ON        = $EE
T_PROC      = $F2
T_REM       = $F4
T_FN        = $A4
T_ELSE      = $8B

; Scalars ($0240-$0258, shared with dfs.s: never at the same time)
TK_OPT      = $0240             ; options (bits below)
TK_N1       = $0241             ; search string length
TK_N2       = $0242             ; replacement length
TK_P        = $0243             ; position in the line
TK_E        = $0244             ; the line's CR (offset)
TK_ST       = $0245             ; scan state (bits below)
TK_SH       = $0246             ; this line shown
TK_MOD      = $0247             ; the program changed
TK_A        = $0248             ; 2: scratch
TK_B        = $024A             ; 2
TK_C        = $024C             ; 2
TK_D        = $024E             ; 2
TK_X        = $0250             ; 9

TK_L        = fsPTR             ; zp: the line (tk_show keeps it)
TK_Q        = fsADDR            ; zp: a second pointer

TK_S1       = MOSBUF+$00        ; 48: search string
TK_S2       = MOSBUF+$30        ; 48: replacement
TK_SMAX     = 47
DF_LINE     = $0700             ; a line typed (BASIC's input line)

O_CASE      = $01               ; *SEARCH options
O_DATA      = $02
O_REM       = $04
O_QUOTE     = $08
O_KEY       = $10
O_GLOBAL    = $20
O_REPL      = $80               ; (a replacement was given)

S_QUOTE     = $01               ; scan state
S_REM       = $02
S_DATA      = $04
S_STAR      = $08

; ----------------------------------------------------------------------------
; Program walking

; tk_first: TK_L = the first line (PAGE + 1)
tk_first:
    lda #1
    sta TK_L
    lda zpTXTP
    sta TK_L+1
    rts

; tk_next: TK_L = the next line; C = 1 at the end (also at the start:
; a line whose high byte has bit 7 set)
tk_next:
    ldy #2
    lda (TK_L),y
    clc
    adc TK_L
    sta TK_L
    bcc tk_atend
    inc TK_L+1
tk_atend:
    ldy #0
    lda (TK_L),y
    asl                         ; (C = bit 7)
    rts

; tk_show: the line at TK_L listed (*LIST's printer, bank 2)
tk_show:
    lda TK_L
    sta fsBLK
    pha
    lda TK_L+1
    sta fsBLK+1
    pha
    lda TK_Q+1                  ; (ls_show spells keywords out through
    pha                         ; fsPTR; TK_Q kept too)
    lda TK_Q
    pha
    farcall ls_one, BANK_FS
    pla
    sta TK_Q
    pla
    sta TK_Q+1
    pla
    sta TK_L+1
    pla
    sta TK_L
    rts

; tk_ident: C = 1 if A may be part of a name (A-Z a-z 0-9 _ ` @)
tk_ident:
    cmp #'0'
    bcc tid_no
    cmp #'9'+1
    bcc tid_yes
    cmp #'@'
    bcc tid_no
    cmp #'Z'+1
    bcc tid_yes
    cmp #'_'
    bcc tid_no
    cmp #'z'+1
    bcc tid_yes
    clc
    rts
tid_yes:
    sec
    rts
tid_no:
    clc
    rts

; tk_state: the scan state after the byte at TK_P (quotes, REM, DATA,
; a * command: the rest of the line is text). Input: A = the byte.
tk_state:
    tax
    lda TK_ST
    and #S_REM+S_DATA+S_STAR
    bne tst_rts                 ; the rest of the line: no change
    cpx #'"'
    bne tst_nq
    lda TK_ST
    eor #S_QUOTE
    sta TK_ST
    rts
tst_nq:
    lda TK_ST
    and #S_QUOTE
    bne tst_rts
    cpx #T_REM
    bne tst_nrem
    lda #S_REM
    bne tst_set
tst_nrem:
    cpx #T_DATA
    bne tst_rts
    lda #S_DATA
tst_set:
    ora TK_ST
    sta TK_ST
tst_rts:
    rts

; tk_dec / tk_decw: A/X (low/high) in decimal; tk_decw right-aligned
; in Y places. Uses: A, X, Y, TK_X+0-7.
tk_dec:
    ldy #0
tk_decw:
    sty TK_X+2
    sta TK_X
    stx TK_X+1
    ldx #0
tdc_div:
    lda #0
    ldy #16
tdc_bit:
    asl TK_X
    rol TK_X+1
    rol
    cmp #10
    bcc tdc_nb
    sbc #10
    inc TK_X
tdc_nb:
    dey
    bne tdc_bit
    sta TK_X+3,x                ; the digits, lowest first
    inx
    lda TK_X
    ora TK_X+1
    bne tdc_div
    stx TK_X                    ; (their number)
    lda TK_X+2                  ; spaces first
    sec
    sbc TK_X
    bcc tdc_np
    beq tdc_np
    tay
tdc_sp:
    lda #' '
    jsr OSWRCH
    dey
    bne tdc_sp
tdc_np:
    ldx TK_X
tdc_out:
    dex
    lda TK_X+3,x
    ora #'0'
    jsr OSWRCH
    cpx #0
    bne tdc_out
    rts

; tk_lnum: the line number of TK_L, 6 wide (for *XREF's lists)
tk_lnum:
    ldy #0
    lda (TK_L),y
    tax
    iny
    lda (TK_L),y
    ldy #6
    jmp tk_decw

; tk_yn: "Y/N" key: C = 1 for Y; ESCAPE acknowledged and raised
tk_yn:
    jsr OSRDCH
    bcs tyn_esc
    and #$DF
    cmp #'Y'
    beq tyn_y
    cmp #'N'
    bne tk_yn
    jsr OSWRCH
    jsr OSNEWL
    clc
    rts
tyn_y:
    jsr OSWRCH
    jsr OSNEWL
    sec
    rts
tyn_esc:
    lda #$7E
    jsr OSBYTE
    brk
    dta 17, 'Escape', 0

; ----------------------------------------------------------------------------
; cmd_search / cmd_find / cmd_replace
;   Summary: *SEARCH s1[,s2]: the lines holding s1 (listed); with s2 each
;            match may be replaced (Replace Y/N:). The Parameters prompt
;            takes letters: C case ignored, D not in DATA, R not in REM,
;            " not in strings, K s1 (and s2) are keywords, G replace all
;            without asking (S, ignore spaces, is accepted). # in s1
;            matches any character. *FIND s1 and *REPLACE s1,s2 skip
;            the prompt. Keywords are tokens: without K they are not
;            found. Line number constants (GOTO 100) are never matched.
;   Function: each line scanned byte by byte with the scan state; a
;            replacement moves the program after it (tk_shift), TOP with
;            it; afterwards the variables are cleared (SETFSA) as an edit
;            does. "Line too long" past 255 bytes.
;   Input:   mosPTR/Y.  Output: the listing, the program.
;   Uses:    A, X, Y, TK_*, MOSBUF+$00-$5F, DF_LINE, fs*, mosTMP.
cmd_find:
    lda #0
    beq cse_go
cmd_replace:
    lda #1
    bne cse_go
cmd_search:
    lda #2                      ; (ask for parameters)
cse_go:
    sta TK_X+8
    jsr tk_strings
    lda TK_X+8
    cmp #1
    bne cse_nrep
    lda TK_OPT                  ; *REPLACE needs s1,s2
    bmi cse_kw
    jmp s6_syntax
cse_nrep:
    cmp #2
    bne cse_kw
    jsr s6_text
    dta 'Parameters ', 0
    ldx #4
cse_blk:
    lda cse_word,x
    sta TK_X,x
    dex
    bpl cse_blk
    ldx #<TK_X
    ldy #>TK_X
    lda #0
    jsr OSWORD
    bcs tyn_esc
    ldx #0                      ; the letters
cse_opt:
    lda DF_LINE,x
    cmp #13
    beq cse_kw
    and #$DF
    ldy #5
cse_find:
    cmp cse_letters,y
    beq cse_set
    dey
    bpl cse_find
    bmi cse_onext
cse_set:
    lda cse_bits,y
    ora TK_OPT
    sta TK_OPT
cse_onext:
    inx
    cpx #10
    bcc cse_opt
    bcs cse_kw
cse_kw:
    lda TK_OPT                  ; K: the strings to tokens
    and #O_KEY
    beq cse_scan
    jsr tk_keyword
cse_scan:
    lda #0
    sta TK_MOD
    jsr tk_first
    jsr tk_atend
    bcs cse_done
cse_line:
    bit ESCFLG
    bmi cse_esc
    jsr tk_sline
    jsr tk_next
    bcc cse_line
cse_done:
    lda TK_MOD
    beq cse_rts
    farcall B_SETFSA, BANK_RAM
cse_rts:
    rts
cse_esc:
    lda TK_MOD
    bne cse_escm
    jmp tyn_esc
cse_escm:
    farcall B_SETFSA, BANK_RAM
    jmp tyn_esc
cse_word:
    dta <DF_LINE, >DF_LINE, 10, 32, 126
cse_letters:
    dta 'C', 'D', 'R', $02, 'K', 'G'          ; ($02: '"' AND &DF)
cse_bits:
    dta O_CASE, O_DATA, O_REM, O_QUOTE, O_KEY, O_GLOBAL

; tk_strings: s1 (to a comma or the end) and, after a comma, s2 from the
; line; TK_OPT = O_REPL if there is a comma. "Syntax" without s1.
tk_strings:
    lda #0
    sta TK_OPT
    sta TK_N1
    sta TK_N2
    jsr s6_skipsp
    cmp #13
    bne tst1
    jmp s6_syntax
tst1:
    lda (mosPTR),y
    cmp #13
    beq tst_end
    cmp #','
    beq tst_comma
    ldx TK_N1
    cpx #TK_SMAX
    bcs tst_long
    sta TK_S1,x
    inc TK_N1
    iny
    bne tst1
tst_comma:
    lda #O_REPL
    sta TK_OPT
    iny
tst2:
    lda (mosPTR),y
    cmp #13
    beq tst_end
    ldx TK_N2
    cpx #TK_SMAX
    bcs tst_long
    sta TK_S2,x
    inc TK_N2
    iny
    bne tst2
tst_end:
    lda TK_N1
    bne tst_rts2
    jmp s6_syntax
tst_rts2:
    rts
tst_long:
    brk
    dta 253, 'String too long', 0

; tk_keyword: K: s1 (and s2) that spell a keyword become its token
tk_keyword:
    ldx #<TK_S1
    lda TK_N1
    jsr tkw_one
    sta TK_N1
    lda TK_OPT
    bpl tkw_rts
    ldx #<TK_S2
    lda TK_N2
    jsr tkw_one
    sta TK_N2
tkw_rts:
    rts
; tkw_one: the string at MOSBUF+X (length A): a keyword's spelling ->
; its token (length 1). Output: A = the length.
tkw_one:
    sta TK_A                    ; length
    stx TK_A+1                  ; offset in MOSBUF
    lda #$80                    ; tokens $80-$FF (lt_lo/lt_hi: the text,
    sta TK_B                    ; bit 7 set on its last letter)
tko_tok:
    ldx TK_B
    lda lt_lo-$80,x
    sta TK_Q
    lda lt_hi-$80,x
    sta TK_Q+1
    ldy #0
    ldx TK_A+1
tko_ch:
    cpy TK_A
    beq tko_next                ; the string ended first
    lda (TK_Q),y
    pha
    and #$7F
    cmp MOSBUF,x
    bne tko_pnext
    pla
    bmi tko_last
    inx
    iny
    bne tko_ch
tko_last:
    iny
    cpy TK_A                    ; the whole string spelt it?
    bne tko_next
    ldx TK_A+1
    lda TK_B
    sta MOSBUF,x
    lda #1
    rts
tko_pnext:
    pla
tko_next:
    inc TK_B
    bne tko_tok
    lda TK_A
    rts

; tk_sline: one line searched (and replaced)
tk_sline:
    lda #0
    sta TK_ST
    sta TK_SH
    lda #3
    sta TK_P
tsl_e:
    ldy #2                      ; the CR's offset
    lda (TK_L),y
    sec
    sbc #1
    sta TK_E
tsl_byte:
    ldy TK_P
    cpy TK_E
    bcc tsl_more
    lda TK_SH                   ; shown and changed: shown again
    cmp #2
    bne tsl_rts
    jmp tk_show
tsl_rts:
    rts
tsl_more:
    lda (TK_L),y
    cmp #T_CONST                ; a line number: 4 bytes, never matched
    bne tsl_try
    lda TK_ST
    and #S_QUOTE+S_REM+S_DATA
    bne tsl_try
    lda TK_P
    clc
    adc #4
    sta TK_P
    bne tsl_byte
tsl_try:
    jsr tk_allowed
    bcc tsl_adv
    jsr tk_match
    bcs tsl_hit
tsl_adv:
    ldy TK_P
    lda (TK_L),y
    jsr tk_state
    inc TK_P
    bne tsl_byte
tsl_hit:
    lda TK_SH
    bne tsl_shown
    inc TK_SH
    jsr tk_show
tsl_shown:
    lda TK_OPT
    bmi tsl_repl
    lda #3                      ; (search only: the next line)
    sta TK_SH
    rts
tsl_repl:
    and #O_GLOBAL
    bne tsl_do
    jsr s6_text
    dta 'Replace Y/N: ', 0
    jsr tk_yn
    bcc tsl_adv
tsl_do:
    jsr tk_replace
    lda #2
    sta TK_SH
    lda TK_P                    ; on after the new text
    clc
    adc TK_N2
    sta TK_P
    jmp tsl_e

; tk_allowed: C = 1 if a match may start here (the options and state)
tk_allowed:
    lda TK_ST
    and #S_QUOTE
    beq tal_nq
    lda TK_OPT
    and #O_QUOTE
    bne tal_no
tal_nq:
    lda TK_ST
    and #S_REM
    beq tal_nr
    lda TK_OPT
    and #O_REM
    bne tal_no
tal_nr:
    lda TK_ST
    and #S_DATA
    beq tal_yes
    lda TK_OPT
    and #O_DATA
    bne tal_no
tal_yes:
    sec
    rts
tal_no:
    clc
    rts

; tk_match: C = 1 if s1 is at TK_P (# any character; C: case ignored)
tk_match:
    ldx #0
    ldy TK_P
tmt_ch:
    cpx TK_N1
    beq tmt_yes
    cpy TK_E
    bcs tmt_no
    lda TK_S1,x
    cmp #'#'
    beq tmt_ok
    eor (TK_L),y
    beq tmt_ok
    cmp #$20                    ; differ only in bit 5: a letter's case?
    bne tmt_no
    lda TK_OPT
    and #O_CASE
    beq tmt_no
    lda TK_S1,x
    and #$DF
    cmp #'A'
    bcc tmt_no
    cmp #'Z'+1
    bcs tmt_no
tmt_ok:
    inx
    iny
    bne tmt_ch
tmt_yes:
    sec
    rts
tmt_no:
    clc
    rts

; tk_replace: s1 at TK_P becomes s2: the program moved by N2 - N1,
; the line's length and TOP with it
tk_replace:
    ldy #2
    lda (TK_L),y
    clc
    adc TK_N2
    bcs trp_long
    sec
    sbc TK_N1
    bcc trp_long                ; (cannot happen)
    sta TK_A                    ; the new length
    lda TK_N2                   ; growing: room below HIMEM (256 bytes
    cmp TK_N1                   ; for BASIC's stack)
    bcc trp_ok
    lda zpTOP+1
    clc
    adc #1
    cmp zpHIMEM+1
    bcs trp_room
trp_ok:
    lda TK_L                    ; from = line + P + N1
    clc
    adc TK_P
    sta TK_Q
    lda TK_L+1
    adc #0
    sta TK_Q+1
    lda TK_Q
    clc
    adc TK_N1
    sta TK_Q
    bcc trp_q
    inc TK_Q+1
trp_q:
    lda TK_N2
    sec
    sbc TK_N1
    jsr tk_shift                ; [from, TOP) moved by A (signed)
    ldy #2
    lda TK_A
    sta (TK_L),y
    lda TK_P                    ; s2 in
    clc
    adc TK_L
    sta TK_Q
    lda TK_L+1
    adc #0
    sta TK_Q+1
    ldy #0
trp_cp:
    cpy TK_N2
    beq trp_done
    lda TK_S2,y
    sta (TK_Q),y
    iny
    bne trp_cp
trp_done:
    lda #1
    sta TK_MOD
    rts
trp_long:
    brk
    dta 254, 'Line too long', 0
trp_room:
    brk
    dta 0, 'No room', 0

; tk_shift
;   Summary: the bytes from TK_Q up to TOP moved by A (signed, -128 to
;            127), TOP with them.
;   Uses:    A, X, Y, mosPTR2, mosTMP.
tk_shift:
    sta TK_B
    cmp #0
    bne tsh_go
    rts
tsh_go:
    lda zpTOP                   ; count = TOP - from
    sec
    sbc TK_Q
    sta mosTMP
    lda zpTOP+1
    sbc TK_Q+1
    sta mosTMP+1
    lda TK_B
    bmi tsh_down
    clc                         ; up: from the end down (TOP - 1 first)
    adc zpTOP
    sta zpTOP
    bcc tsh_up
    inc zpTOP+1
tsh_up:
    lda TK_Q                    ; src = from + count - 1, backwards; the
    clc                         ; byte at count - 1 .. 0
    adc mosTMP
    sta mosPTR2
    lda TK_Q+1
    adc mosTMP+1
    sta mosPTR2+1               ; mosPTR2 = from + count (one past)
tsh_ul:
    lda mosTMP
    ora mosTMP+1
    beq tsh_rts
    lda mosPTR2
    bne tsh_ud
    dec mosPTR2+1
tsh_ud:
    dec mosPTR2
    lda mosTMP
    bne tsh_uc
    dec mosTMP+1
tsh_uc:
    dec mosTMP
    ldy #0
    lda (mosPTR2),y
    ldy TK_B
    sta (mosPTR2),y
    jmp tsh_ul
tsh_down:
    clc                         ; down: from the start up
    adc zpTOP
    sta zpTOP
    bcs tsh_d1
    dec zpTOP+1
tsh_d1:
    lda TK_Q                    ; dst = from + A (A negative)
    clc
    adc TK_B
    sta mosPTR2
    lda TK_Q+1
    adc #$FF
    sta mosPTR2+1
    ldy #0
tsh_dl:
    lda mosTMP
    ora mosTMP+1
    beq tsh_rts
    lda (TK_Q),y
    sta (mosPTR2),y
    inc TK_Q
    bne tsh_d2
    inc TK_Q+1
tsh_d2:
    inc mosPTR2
    bne tsh_d3
    inc mosPTR2+1
tsh_d3:
    lda mosTMP
    bne tsh_dc
    dec mosTMP+1
tsh_dc:
    dec mosTMP
    jmp tsh_dl
tsh_rts:
    rts

; ----------------------------------------------------------------------------
; cmd_xref / cmd_varlist
;   Summary: *XREF [R I S A F P H L]: the variables, arrays, procedures
;            and functions with their values and the lines that use them
;            (R reals, I integers, S strings, A arrays, F functions, P
;            procedures; none: all; H values in hexadecimal, L no line
;            numbers). *VARLIST is *XREF L. As in the toolkit: only what
;            the program has run so far is known; A%-Z% when the program
;            uses them.
;   Function: BASIC's catalogue (&0480: a list per first letter, &04F6
;            procedures, &04F8 functions); values printed by BASIC's FCON
;            (with @%); the program scanned for each name.
;   Input:   mosPTR/Y.  Output: the list.  Uses: A, X, Y, TK_*, MOSBUF.
X_R         = $01
X_I         = $02
X_S         = $04
X_A         = $08
X_F         = $10
X_P         = $20
X_HEX       = $40
X_NOLN      = $80
TK_NAME     = MOSBUF+$60        ; 48: the name worked on
cmd_varlist:
    lda #X_NOLN
    sta TK_OPT
    jsr s6_end
    jmp cxr_all
cmd_xref:
    lda #0
    sta TK_OPT
cxr_opt:
    jsr s6_skipsp
    cmp #13
    beq cxr_go
    and #$DF
    ldx #7
cxr_find:
    cmp cxr_letters,x
    beq cxr_set
    dex
    bpl cxr_find
    jmp s6_syntax
cxr_set:
    lda cxr_bits,x
    ora TK_OPT
    sta TK_OPT
    iny
    bne cxr_opt
cxr_go:
    lda TK_OPT                  ; no kind chosen: all
    and #$3F
    bne cxr_list
cxr_all:
    lda TK_OPT
    ora #$3F
    sta TK_OPT
cxr_list:
    lda zpPRINTF
    pha
    lda TK_OPT                  ; H: BASIC's hex flag (bit 7)
    and #X_HEX
    beq cxr_dec
    lda #$80
cxr_dec:
    sta zpPRINTF
    lda TK_OPT
    and #X_I
    beq cxr_dyn
    jsr xr_static
cxr_dyn:
    lda #'@'                    ; the lists '@'..'z'
    sta TK_C
cxr_letter:
    lda TK_C
    asl
    tax
    jsr xr_list
    inc TK_C
    lda TK_C
    cmp #'z'+1
    bcc cxr_letter
    lda TK_OPT
    and #X_P
    beq cxr_nop
    lda #0
    sta TK_C
    ldx #$F6
    jsr xr_list
cxr_nop:
    lda TK_OPT
    and #X_F
    beq cxr_end
    lda #1
    sta TK_C
    ldx #$F8
    jsr xr_list
cxr_end:
    pla
    sta zpPRINTF
    rts
cxr_letters:
    dta 'R', 'I', 'S', 'A', 'F', 'P', 'H', 'L'
cxr_bits:
    dta X_R, X_I, X_S, X_A, X_F, X_P, X_HEX, X_NOLN

; xr_static: A%-Z% (and @%) that the program uses, with their values
xr_static:
    lda #'@'
    sta TK_C
xst_l:
    lda TK_C
    sta TK_NAME
    lda #'%'
    sta TK_NAME+1
    lda #2
    sta TK_N1
    sta TK_D                    ; (2: a variable, not a PROC/FN)
    jsr xr_used                 ; C = 1 if some line uses it
    bcc xst_next
    jsr xr_name
    lda TK_C                    ; value: VARL + (letter - '@') * 4
    sec
    sbc #'@'
    asl
    asl
    clc
    adc #<VARL
    sta TK_Q
    lda #>VARL
    sta TK_Q+1
    jsr xr_int
    jsr xr_lines
xst_next:
    inc TK_C
    lda TK_C
    cmp #'Z'+1
    bcc xst_l
    rts

; xr_list: the catalogue list at VARL+X; TK_C = its first letter (0
; procedures, 1 functions)
xr_list:
    lda VARL,x
    sta TK_A
    lda VARL+1,x
    sta TK_A+1
xrl_entry:
    lda TK_A+1
    bne xrl_have
    rts
xrl_have:
    bit ESCFLG
    bpl xrl_noesc
    jmp tyn_esc
xrl_noesc:
    lda TK_A                    ; TK_Q: the entry
    sta TK_Q
    lda TK_A+1
    sta TK_Q+1
    ldy #0                      ; the next entry (its link)
    lda (TK_Q),y
    sta TK_A
    iny
    lda (TK_Q),y
    sta TK_A+1
    ldx #0                      ; the name: the letter, then the bytes
    lda TK_C
    sta TK_D                    ; (0/1: PROC/FN, kept for xr_used)
    cmp #2
    bcc xrl_pf
    sta TK_NAME
    inx
xrl_pf:
    iny
xrl_nm:
    lda (TK_Q),y
    beq xrl_end
    cpx #TK_SMAX
    bcs xrl_end
    sta TK_NAME,x
    inx
    iny
    bne xrl_nm
xrl_end:
    stx TK_N1
    iny                         ; TK_Q -> the value
    tya
    clc
    adc TK_Q
    sta TK_Q
    bcc xrl_kind
    inc TK_Q+1
xrl_kind:
    jsr xr_kind                 ; A = its bit (X_*)
    and TK_OPT
    beq xrl_entry
    jsr xr_name
    lda TK_D                    ; procedures and functions: no value
    cmp #2
    bcc xrl_lines
    ldx TK_N1
    lda TK_NAME-1,x
    cmp #'('
    beq xrl_lines               ; arrays: no value
    cmp #'%'
    bne xrl_nint
    jsr xr_int
    jmp xrl_lines
xrl_nint:
    cmp #'$'
    bne xrl_real
    jsr xr_str
    jmp xrl_lines
xrl_real:
    jsr xr_real
xrl_lines:
    jsr xr_lines
    jmp xrl_entry

; xr_kind: A = the X_* bit of the name in TK_NAME (TK_D 0/1: P/F)
xr_kind:
    lda TK_D
    beq xk_p
    cmp #1
    beq xk_f
    ldx TK_N1
    lda TK_NAME-1,x
    cmp #'('
    beq xk_a
    cmp #'%'
    beq xk_i
    cmp #'$'
    beq xk_s
    lda #X_R
    rts
xk_a:
    lda #X_A
    rts
xk_i:
    lda #X_I
    rts
xk_s:
    lda #X_S
    rts
xk_p:
    lda #X_P
    rts
xk_f:
    lda #X_F
    rts

; xr_name: the name (PROC/FN with its keyword), padded to 14
xr_name:
    ldx #0
    lda TK_D
    cmp #2
    bcs xn_chars
    tay                         ; 0 PROC, 1 FN
    lda xn_kw_lo,y
    sta mosTMP
    lda #>xn_proc
    sta mosTMP+1
    ldy #0
xn_kw:
    lda (mosTMP),y
    beq xn_chars
    jsr OSWRCH
    inx
    iny
    bne xn_kw
xn_chars:
    ldy #0
xn_c:
    cpy TK_N1
    beq xn_pad
    lda TK_NAME,y
    jsr OSWRCH
    inx
    iny
    bne xn_c
xn_pad:
    lda #' '
    jsr OSWRCH
    inx
    cpx #14
    bcc xn_pad
    rts
xn_kw_lo:
    dta <xn_proc, <xn_fn
xn_proc     dta 'PROC', 0
xn_fn       dta 'FN', 0
    .if >xn_proc != >xn_fn
    .error "xr_name's keywords cross a page"
    .endif

; xr_int: the integer at (TK_Q) through FCON
xr_int:
    ldy #3
xi_c:
    lda (TK_Q),y
    sta zpIACC,y
    dey
    bpl xi_c
    ldy #$40
    bne xr_fcon
; xr_real: the real at (TK_Q) through FLDA, FCON
xr_real:
    lda TK_Q
    sta zpARGP
    lda TK_Q+1
    sta zpARGP+1
    farcall B_FLDA, BANK_RAM
    ldy #$FF
xr_fcon:
    farcall B_FCON, BANK_RAM
    ldx #0
xf_out:
    cpx zpCLEN
    beq xf_rts
    lda STRACC,x
    jsr OSWRCH
    inx
    bne xf_out
xf_rts:
    rts
; xr_str: the string at (TK_Q): address, room, length; quoted, at most 20
xr_str:
    ldy #0
    lda (TK_Q),y
    sta mosTMP
    iny
    lda (TK_Q),y
    sta mosTMP+1
    ldy #3
    lda (TK_Q),y
    sta TK_B
    lda #'"'
    jsr OSWRCH
    ldy #0
xs_c:
    cpy TK_B
    beq xs_end
    cpy #20
    bcs xs_more
    lda (mosTMP),y
    jsr OSWRCH
    iny
    bne xs_c
xs_more:
    lda #'.'
    jsr OSWRCH
    jsr OSWRCH
xs_end:
    lda #'"'
    jmp OSWRCH

; xr_lines: the numbers of the lines that use the name (unless L)
xr_lines:
    lda TK_OPT
    bmi xli_nl
    lda #0
    sta TK_SH                   ; numbers on this row
    jsr OSNEWL
    jsr tk_first
    jsr tk_atend
    bcs xli_nl
xli_line:
    jsr xr_inline
    bcc xli_next
    lda TK_SH
    cmp #6
    bcc xli_put
    jsr OSNEWL
    lda #0
    sta TK_SH
xli_put:
    inc TK_SH
    jsr tk_lnum
xli_next:
    jsr tk_next
    bcc xli_line
xli_nl:
    jmp OSNEWL

; xr_used: C = 1 if any line uses the name
xr_used:
    jsr tk_first
    jsr tk_atend
    bcs xu_no
xu_line:
    jsr xr_inline
    bcs xu_rts
    jsr tk_next
    bcc xu_line
xu_no:
    clc
xu_rts:
    rts

; xr_inline: C = 1 if the line at TK_L uses the name (TK_NAME, TK_N1;
; TK_D 0/1: after PROC/FN): outside strings, REM and DATA, not inside a
; longer name, not followed by a name character (or % $ ( for a plain
; real's name; ( for an integer's or string's)
xr_inline:
    lda #0
    sta TK_ST
    lda #3
    sta TK_P
    ldy #2
    lda (TK_L),y
    sec
    sbc #1
    sta TK_E
xin_byte:
    ldy TK_P
    cpy TK_E
    bcc xin_more
    clc
    rts
xin_more:
    lda (TK_L),y
    cmp #T_CONST
    bne xin_try
    lda TK_ST
    bne xin_try
    lda TK_P
    clc
    adc #4
    sta TK_P
    bne xin_byte
xin_try:
    lda TK_ST
    bne xin_adv
    jsr xr_at
    bcs xin_rts
xin_adv:
    ldy TK_P
    lda (TK_L),y
    jsr tk_state
    inc TK_P
    bne xin_byte
xin_rts:
    rts

; xr_at: C = 1 if the name starts at TK_P (PROC/FN: after their token)
xr_at:
    ldy TK_P
    lda TK_D
    cmp #2
    bcs xa_var
    tax                         ; PROC/FN: the token, then the name
    lda (TK_L),y
    cmp xa_tok,x
    bne xa_no
    iny
    jmp xa_cmp
xa_var:
    cpy #4                      ; the byte before: not a name character
    bcc xa_cmp
    dey
    lda (TK_L),y
    iny
    jsr tk_ident
    bcs xa_no
xa_cmp:
    ldx #0
xa_c:
    cpx TK_N1
    beq xa_after
    cpy TK_E
    bcs xa_no
    lda (TK_L),y
    cmp TK_NAME,x
    bne xa_no
    inx
    iny
    bne xa_c
xa_after:
    ldx TK_N1                   ; an array's name ends in "(": matched
    lda TK_NAME-1,x
    cmp #'('
    beq xa_yes
    lda (TK_L),y                ; the byte after: no name character
    jsr tk_ident
    bcs xa_no
    lda (TK_L),y                ; ( after a name that is not an array's
                                ; (A%( is another variable than A%)
    cmp #'('
    beq xa_chk
    cmp #'%'                    ; % or $ after a real's name
    beq xa_real
    cmp #'$'
    bne xa_yes
xa_real:
    lda TK_D                    ; (PROC/FN names: % and $ are allowed in
    cmp #2                      ; them, so nothing follows a match)
    bcc xa_no
    lda TK_NAME-1,x
    cmp #'%'
    beq xa_yes
    cmp #'$'
    beq xa_yes
    bne xa_no
xa_chk:
    lda TK_D                    ; "PROCname(": a call with parameters
    cmp #2
    bcc xa_yes
xa_no:
    clc
    rts
xa_yes:
    sec
    rts
xa_tok:
    dta T_PROC, T_FN

; ----------------------------------------------------------------------------
; cmd_crunch / cmd_pack
;   Summary: *CRUNCH [C R S :] (also *PACK): the program made shorter:
;            spaces, REM statements, extra colons removed, lines joined;
;            each letter given switches that part off (C joining, R REMs,
;            S spaces, : colons; B, L, T and V are accepted: brackets,
;            LET, THEN and variable names are never changed). Asks first;
;            prints the sizes. Lines that GOTO, GOSUB, RESTORE (or THEN,
;            ELSE n) name keep their number and their REM. A computed
;            GOTO's targets are not known: such programs need C off.
;   Function: pass 1 marks the line numbers named (a 4K bitmap in the
;            REU: needs one). Pass 2 reads each line into MOSBUF, writes
;            it shortened into TK_BUILD (&0600, the line being built, joined
;            lines added with ":"), and writes finished lines back at the
;            write position, which never passes the read position.
;            Assembler ([ ... ]), DATA, * commands and strings are kept
;            as they are. A line is not joined after IF, ON, DATA, REM,
;            ELSE or a * command, nor is a DEF or DATA line joined onto
;            the one before. Variables are cleared (SETFSA).
;   Input:   mosPTR/Y.  Output: the program.  Uses: A, X, Y, TK_*,
;            MOSBUF, TK_BUILD, mosTMP, mosPTR2.
TK_BUILD    = STRACC            ; the line being built (BASIC's string
                                ; buffer, free between statements; not
                                ; &0700: BASIC still reads the command's
                                ; line there afterwards)
C_JOIN      = $01               ; (TK_OPT: functions off)
C_REM       = $02
C_SPACE     = $04
C_COLON     = $08
REU_TGTMAP  = $4000             ; REU bank 0: the bitmap (HTTP buffer)
cmd_pack:
cmd_crunch:
    lda #0
    sta TK_OPT
ccr_opt:
    jsr s6_skipsp
    cmp #13
    beq ccr_go
    ldx #8
    and #$DF
    cmp #':' & $DF
    bne ccr_find
    lda #':'
ccr_find:
    cmp ccr_letters,x
    beq ccr_set
    dex
    bpl ccr_find
    jmp s6_syntax
ccr_set:
    lda ccr_bits,x
    ora TK_OPT
    sta TK_OPT
    iny
    bne ccr_opt
ccr_go:
    jsr s6_hasreu
    bne ccr_reu
    brk
    dta 254, '*CRUNCH needs an REU', 0
ccr_reu:
    jsr s6_text
    dta 'Crunch the program: are you sure? ', 0
    jsr tk_yn
    bcs ccr_yes
    rts
ccr_yes:
    lda zpTOP
    sta TK_D                    ; old TOP (for the sizes)
    lda zpTOP+1
    sta TK_D+1
    jsr cr_targets
    jsr cr_pass
    farcall B_SETFSA, BANK_RAM
    jsr s6_text                 ; sizes
    dta 'Old program size = ', 0
    lda TK_D
    sec
    sbc #0
    sta TK_A
    lda TK_D+1
    sbc zpTXTP
    tax
    lda TK_A
    jsr tk_dec
    jsr s6_text
    dta 13, 'Bytes saved = ', 0
    lda TK_D
    sec
    sbc zpTOP
    pha
    lda TK_D+1
    sbc zpTOP+1
    tax
    pla
    jsr tk_dec
    jsr s6_text
    dta 13, 'New program size = ', 0
    lda zpTOP+1
    sec
    sbc zpTXTP
    tax
    lda zpTOP
    jsr tk_dec
    jmp OSNEWL
ccr_letters:
    dta 'C', 'R', 'S', ':', 'B', 'L', 'T', 'V', 0
ccr_bits:
    dta C_JOIN, C_REM, C_SPACE, C_COLON, 0, 0, 0, 0, 0

; cr_targets: the bitmap cleared, then every line number constant's bit set
cr_targets:
    lda #0                      ; 4K of 0 (DMA from one 0 byte)
    sta DF_BYTE
    php
    sei
    lda #<DF_BYTE
    sta REU_C64
    lda #>DF_BYTE
    sta REU_C64+1
    lda #<REU_TGTMAP
    sta REU_ADDR
    lda #>REU_TGTMAP
    sta REU_ADDR+1
    lda #0
    sta REU_BANK
    sta REU_LEN
    lda #$10
    sta REU_LEN+1
    lda #$80
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    lda #0
    sta REU_CTRL
    plp
    jsr tk_first
    jsr tk_atend
    bcs ctg_rts
ctg_line:
    lda #0
    sta TK_ST
    lda #3
    sta TK_P
    ldy #2
    lda (TK_L),y
    sec
    sbc #1
    sta TK_E
ctg_byte:
    ldy TK_P
    cpy TK_E
    bcs ctg_next
    lda (TK_L),y
    cmp #T_CONST
    bne ctg_st
    lda TK_ST
    and #S_QUOTE+S_REM+S_DATA
    bne ctg_st
    iny                         ; decode (as BASIC's SPGETN)
    lda (TK_L),y
    asl
    asl
    tax
    and #$C0
    iny
    eor (TK_L),y
    sta TK_A
    txa
    asl
    asl
    iny
    eor (TK_L),y
    sta TK_A+1
    jsr cr_mark
    lda TK_P
    clc
    adc #4
    sta TK_P
    bne ctg_byte
ctg_st:
    jsr tk_state
    inc TK_P
    bne ctg_byte
ctg_next:
    jsr tk_next
    bcc ctg_line
ctg_rts:
    rts

; cr_bit: TK_A = a line number -> REU address (TK_B) and its bit (TK_C)
cr_bit:
    lda TK_A                    ; byte = n / 8, bit = n AND 7
    and #7
    tax
    lda ac_bit8,x
    sta TK_C
    lda TK_A+1
    and #$7F
    sta TK_B+1
    lda TK_A
    lsr TK_B+1
    ror
    lsr TK_B+1
    ror
    lsr TK_B+1
    ror
    sta TK_B
    lda TK_B+1
    clc
    adc #>REU_TGTMAP
    sta TK_B+1
    rts
ac_bit8:
    dta 1, 2, 4, 8, 16, 32, 64, 128
; cr_mark: line TK_A marked; cr_istgt: C = 1 if line TK_A is marked
cr_mark:
    jsr cr_bit
    jsr cr_rd
    ora TK_C
    sta DF_BYTE
    lda #REU_TO_REU
    jmp cr_dma
cr_istgt:
    jsr cr_bit
    jsr cr_rd
    and TK_C
    cmp #1
    rts
cr_rd:
    lda #REU_TO_C64
    jsr cr_dma
    lda DF_BYTE
    rts
cr_dma:
    php
    sei
    pha
    lda #<DF_BYTE
    sta REU_C64
    lda #>DF_BYTE
    sta REU_C64+1
    lda TK_B
    sta REU_ADDR
    lda TK_B+1
    sta REU_ADDR+1
    lda #0
    sta REU_BANK
    sta REU_LEN+1
    sta REU_CTRL
    lda #1
    sta REU_LEN
    pla
    sta REU_CMD
    plp
    rts

; ----------------------------------------------------------------------------
; cr_pass: pass 2 (see cmd_crunch). TK_L reads, TK_Q writes; the line
; built (number TK_X+0/1, text TK_BUILD, length TK_N2, may take more
; lines: TK_X+2) is written when a line cannot join it.
CR_ASM      = TK_X+3            ; inside [ ... ]
CR_HAVE     = TK_X+4            ; a line is being built
CR_TLEN     = TK_X+5            ; the shortened text's length (MOSBUF)
CR_JOINOK   = TK_X+2            ; the line built may take the next one
cr_pass:
    jsr tk_first
    lda TK_L
    sta TK_Q
    lda TK_L+1
    sta TK_Q+1
    lda #0
    sta CR_ASM
    sta CR_HAVE
    jsr tk_atend
    bcc crp_line
    jmp crp_end
crp_line:
    jsr cr_shorten              ; MOSBUF = the line's text, shortened
    ldy #0                      ; its number
    lda (TK_L),y
    sta TK_A+1
    iny
    lda (TK_L),y
    sta TK_A
    jsr cr_istgt
    php
    lda CR_TLEN                 ; nothing left (a REM line)?
    bne crp_text
    plp
    bcc crp_skip                ; not named: the line goes
    jsr cr_rawcopy              ; named: kept as it was
    php
crp_text:
    plp
    bcs crp_new                 ; a named line starts a new one
    lda CR_HAVE
    beq crp_new
    lda CR_JOINOK
    beq crp_new
    lda TK_OPT
    and #C_JOIN
    bne crp_new
    lda MOSBUF                  ; DEF or DATA at the start: not joined
    cmp #T_DEF
    beq crp_new
    cmp #T_DATA
    beq crp_new
    lda TK_N2                   ; room: 4 + built + 1 + text <= 255
    clc
    adc CR_TLEN
    bcs crp_new
    cmp #250
    bcs crp_new
    ldx TK_N2                   ; ":" and the text onto the line built
    lda #':'
    sta TK_BUILD,x
    inx
    ldy #0
crp_app:
    lda MOSBUF,y
    sta TK_BUILD,x
    inx
    iny
    cpy CR_TLEN
    bcc crp_app
    stx TK_N2
    jsr cr_joinable
    jmp crp_skip
crp_new:
    jsr cr_flush                ; the line built, written
    lda TK_A
    sta TK_X
    lda TK_A+1
    sta TK_X+1
    ldx #0
crp_cp:
    cpx CR_TLEN
    beq crp_cpd
    lda MOSBUF,x
    sta TK_BUILD,x
    inx
    bne crp_cp
crp_cpd:
    stx TK_N2
    lda #1
    sta CR_HAVE
    jsr cr_joinable
crp_skip:
    jsr tk_next
    bcs crp_end
    jmp crp_line
crp_end:
    jsr cr_flush
    ldy #0                      ; the end mark; TOP after it
    lda #$FF
    sta (TK_Q),y
    lda TK_Q
    clc
    adc #1
    sta zpTOP
    lda TK_Q+1
    adc #0
    sta zpTOP+1
    rts

; cr_flush: the line built (if any) written at TK_Q
cr_flush:
    lda CR_HAVE
    bne crf_go
    rts
crf_go:
    ldy #0
    lda TK_X+1
    sta (TK_Q),y
    iny
    lda TK_X
    sta (TK_Q),y
    iny
    lda TK_N2
    clc
    adc #4
    sta (TK_Q),y
    ldx #0
crf_c:
    cpx TK_N2
    beq crf_cr
    iny
    lda TK_BUILD,x
    sta (TK_Q),y
    inx
    bne crf_c
crf_cr:
    iny
    lda #13
    sta (TK_Q),y
    iny
    tya
    clc
    adc TK_Q
    sta TK_Q
    bcc crf_done
    inc TK_Q+1
crf_done:
    lda #0
    sta CR_HAVE
    rts

; cr_rawcopy: MOSBUF = the line's text as it is (a named REM line)
cr_rawcopy:
    ldy #2
    lda (TK_L),y
    sec
    sbc #4
    sta CR_TLEN
    ldx #0
crr_c:
    cpx CR_TLEN
    beq crr_rts
    txa
    clc
    adc #3
    tay
    lda (TK_L),y
    sta MOSBUF,x
    inx
    bne crr_c
crr_rts:
    rts

; cr_joinable: CR_JOINOK = 0 if the line built ends in a part that the
; next line may not follow (IF, ON, ELSE, DATA, REM, a * command,
; assembler): scanned outside strings
cr_joinable:
    lda #0
    sta CR_JOINOK
    lda CR_ASM
    bne crj_rts
    sta TK_ST
    ldx #0
    stx TK_B                    ; at a statement's start
    inc TK_B
crj_c:
    cpx TK_N2
    beq crj_ok
    lda TK_BUILD,x
    cmp #'"'
    bne crj_nq
    lda TK_ST
    eor #1
    sta TK_ST
    jmp crj_n
crj_nq:
    ldy TK_ST
    bne crj_n
    cmp #T_CONST
    bne crj_t
    inx
    inx
    inx
    jmp crj_n
crj_t:
    cmp #T_IF
    beq crj_rts
    cmp #T_ON
    beq crj_rts
    cmp #T_ELSE
    beq crj_rts
    cmp #T_DATA
    beq crj_rts
    cmp #T_REM
    beq crj_rts
    cmp #'['
    beq crj_rts
    cmp #'*'
    bne crj_n
    ldy TK_B
    bne crj_rts                 ; a * command
crj_n:
    lda TK_BUILD,x               ; statement start after ':'
    ldy #0
    cmp #':'
    bne crj_st
    iny
crj_st:
    cmp #' '
    beq crj_sp
    sty TK_B
crj_sp:
    inx
    bne crj_c
crj_ok:
    inc CR_JOINOK
crj_rts:
    rts

; cr_shorten
;   Summary: the line at TK_L shortened into MOSBUF (CR_TLEN): spaces
;            out (S), REM to the end (R), extra colons (:); strings,
;            DATA, * commands and line number constants copied as they
;            are; assembler lines ([ to ]) copied whole.
;   Uses:    A, X, Y, TK_P, TK_E, TK_ST, TK_B.
cr_shorten:
    lda #0
    sta TK_ST
    sta CR_TLEN
    lda #1
    sta TK_B                    ; at a statement's start
    ldy #2
    lda (TK_L),y
    sec
    sbc #1
    sta TK_E
    lda CR_ASM
    bne crs_asm
    ldy #3                      ; a [ in the line (outside strings)?
crs_fa:
    cpy TK_E
    bcs crs_noasm
    lda (TK_L),y
    cmp #'"'
    bne crs_fa1
    lda TK_ST
    eor #1
    sta TK_ST
crs_fa1:
    lda TK_ST
    bne crs_fa2
    lda (TK_L),y
    cmp #T_REM
    beq crs_noasm
    cmp #'['
    beq crs_asmon
crs_fa2:
    iny
    bne crs_fa
crs_asmon:
    lda #1
    sta CR_ASM
crs_asm:
    jsr cr_rawcopy              ; the whole line; ] ends the block
    ldx #0
crs_fe:
    cpx CR_TLEN
    beq crs_arts
    lda MOSBUF,x
    cmp #']'
    beq crs_aend
    inx
    bne crs_fe
crs_aend:
    lda #0
    sta CR_ASM
crs_arts:
    rts
crs_noasm:
    lda #0
    sta TK_ST
    lda #3
    sta TK_P
crs_byte:
    ldy TK_P
    cpy TK_E
    bcc crs_more
    jmp crs_trail
crs_more:
    lda (TK_L),y
    ldx TK_ST
    bne crs_copy                ; string, REM, DATA, *: as it is
    cmp #T_CONST
    bne crs_nconst
    ldx #4                      ; four bytes
crs_c4:
    lda (TK_L),y
    jsr crs_put
    iny
    dex
    bne crs_c4
    sty TK_P
    lda #0
    sta TK_B
    beq crs_byte
crs_nconst:
    cmp #T_REM
    bne crs_nrem
    lda TK_OPT
    and #C_REM
    bne crs_copy
    jmp crs_trail               ; REM: the rest goes
crs_nrem:
    cmp #' '
    bne crs_nsp
    lda TK_OPT
    and #C_SPACE
    bne crs_copy
    jsr crs_spneed              ; a space between two name characters
    bcc crs_skip                ; stays
    lda #' '
    bne crs_copy
crs_nsp:
    cmp #':'
    bne crs_ncol
    lda TK_OPT
    and #C_COLON
    bne crs_colon
    lda TK_B                    ; at a statement's start: a second colon
    bne crs_skip
    ldx CR_TLEN                 ; at the line's start
    beq crs_skip
crs_colon:
    lda #':'
    jsr crs_put
    lda #1
    sta TK_B
    bne crs_skip
crs_ncol:
    cmp #'*'
    bne crs_copy
    ldx TK_B
    beq crs_copy
    pha                         ; a * command: the rest as it is
    lda #S_STAR
    sta TK_ST
    pla
crs_copy:
    jsr crs_put
    ldy TK_P
    lda (TK_L),y
    jsr tk_state
    lda #0
    sta TK_B
crs_skip:
    inc TK_P
    jmp crs_byte
crs_trail:                      ; spaces and colons at the end go
    lda TK_ST                   ; (not after DATA or a * command: there
    and #S_DATA+S_STAR          ; they are part of it; nor when kept by
    bne crs_rts                 ; the options)
    lda TK_OPT
    and #C_SPACE+C_COLON
    cmp #C_SPACE+C_COLON
    beq crs_rts
    ldx CR_TLEN
    beq crs_rts
    lda MOSBUF-1,x
    cmp #' '
    bne crs_tc
    lda TK_OPT
    and #C_SPACE
    bne crs_rts
    beq crs_cut
crs_tc:
    cmp #':'
    bne crs_rts
    lda TK_OPT
    and #C_COLON
    bne crs_rts
crs_cut:
    dec CR_TLEN
    jmp crs_trail
crs_rts:
    rts
; crs_put: A onto MOSBUF (at most 251)
crs_put:
    ldx CR_TLEN
    cpx #251
    bcs crp_rts
    sta MOSBUF,x
    inc CR_TLEN
crp_rts:
    rts
; crs_spneed: C = 1 if the space at TK_P is needed: the character
; written before it and the one after it both name characters
crs_spneed:
    ldx CR_TLEN
    beq csn_no
    lda MOSBUF-1,x
    jsr tk_ident
    bcc csn_rts
    ldy TK_P
csn_next:
    iny
    cpy TK_E
    bcs csn_no
    lda (TK_L),y
    cmp #' '
    beq csn_next
    jmp tk_ident
csn_no:
    clc
csn_rts:
    rts

    .endl
