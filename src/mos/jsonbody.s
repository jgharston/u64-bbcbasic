; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- JSON request bodies: *JSON NEW, *JSON SET, *JSON POST
; (bank 7, inside .local net; 1.0.0 item 7, owner 2026-10-16)
;
; The firmware's HTTP target builds the JSON: a body handle of type JSON
; object (BODY_CREATE &21, format 2), keys added with ADD_INT &23 (4
; bytes, signed), ADD_BOOL &24 and ADD_STRING &25 (wire format: handle,
; key length, key, value; ultimate-uci-oscar64's ultimate_http_lib.c,
; credited). *JSON POST sends it with the JSON exchange (&31): the reply,
; which must be JSON, is kept for *JSON <path> as after *JSON GET. The
; handle is kept in the REU (RH_JBODY, nethttp.s).
;
; ----------------------------------------------------------------------------

HTTP_BCREATE = $21
HTTP_ADDINT  = $23
HTTP_ADDBOOL = $24
HTTP_ADDSTR  = $25
HTTP_HADD    = $13
HTTP_POST    = $03
JT_OBJ       = $02              ; body format: JSON object
JB_X         = MOSBUF+$FD       ; jb_set: where the value goes
JB_E         = MOSBUF+$FE       ; and where it ended

; ----------------------------------------------------------------------------
; jb_words
;   Summary: *JSON NEW / SET key value / POST url, if one of those words
;            is next on the line.
;   Output:  C = 1: done; C = 0: none of them (Y unchanged).
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF.
jb_words:
    lda #<jw_new
    ldx #>jw_new
    jsr s6_word
    bcc jw_set
    jsr s6_end
    jsr jb_new
    sec
    rts
jw_set:
    lda #<jw_setw
    ldx #>jw_setw
    jsr s6_word
    bcc jw_post
    jsr jb_set
    sec
    rts
jw_post:
    lda #<jw_postw
    ldx #>jw_postw
    jsr s6_word
    bcc jbw_rts
    jsr s6_name                 ; the URL
    jsr s6_end
    jsr jb_need                 ; the body
    sta jx_body
    lda #HTTP_POST
    sta jx_verb
    jsr json_exch
    sec
jbw_rts:
    rts
jw_new      dta 'NEW', 0
jw_setw     dta 'SET', 0
jw_postw    dta 'POST', 0
jw_true     dta 'TRUE', 0
jw_false    dta 'FALSE', 0

; ----------------------------------------------------------------------------
; jb_new: a new, empty JSON object body (an earlier one freed)
jb_new:
    jsr s6_hasreu
    bne jn_reu
    brk
    dta 189, 'HTTP needs an REU', 0
jn_reu:
    ldx #<RH_JBODY              ; free the old one (errors ignored)
    jsr hr_rget
    cmp #16
    bcs jn_create
    ldx #HTTP_BFREE
    jsr jf_cmd
jn_create:
    lda #TARGET_HTTP            ; BODY_CREATE, JSON object
    sta uciHDR
    lda #HTTP_BCREATE
    sta uciHDR+1
    lda #JT_OBJ
    sta uciHDR+2
    lda #3
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    lda #$FF
    sta MOSBUF
    jsr uci_send
    lda #<MOSBUF
    ldx #>MOSBUF
    ldy #1
    jsr jg_read
    jsr uci_finish
    bcc jn_ok
    jmp uci_error
jn_ok:
    lda MOSBUF
    ldx #<RH_JBODY
    jmp hr_rput

; jb_need: A = the body handle; "No JSON body (*JSON NEW)" without one
jb_need:
    jsr s6_hasreu
    beq jbn_none
    ldx #<RH_JBODY
    jsr hr_rget
    cmp #16
    bcs jbn_none
    rts
jbn_none:
    brk
    dta 214, 'No JSON body (*JSON NEW)', 0

; ----------------------------------------------------------------------------
; jb_set
;   Summary: *JSON SET key value: "text" a string, TRUE/FALSE, A%-Z% or a
;            number (decimal or &hex, may be negative; 32 bits) an
;            integer, added to the body.
;   Function: the payload is built in MOSBUF: key length, key, value;
;            sent as ADD_STRING / ADD_BOOL / ADD_INT with the handle.
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF.
jb_set:
    jsr jb_need
    sta uciHDR+2
    jsr s6_name                 ; the key
    lda fsLEN
    beq jbs_syn
    cmp #100
    bcs jbs_syn
    sta MOSBUF
    tax                         ; key -> MOSBUF+1..
jbs_key:
    dex
    sty mosTMP
    txa
    tay
    lda (fsPTR),y
    sta MOSBUF+1,x
    ldy mosTMP
    cpx #0
    bne jbs_key
    ldx MOSBUF                  ; X = where the value goes (key length
    inx                         ; + 1)
    jsr s6_skipsp
    cmp #'"'
    beq jbs_str
    lda #<jw_true
    stx JB_X
    ldx #>jw_true
    jsr s6_word
    ldx JB_X
    lda #1
    bcs jbs_bool
    lda #<jw_false
    ldx #>jw_false
    jsr s6_word
    ldx JB_X
    lda #0
    bcs jbs_bool
    jsr jb_int                  ; mosTMP = the number (32 bits)
    bcs jbs_syn
    ldx JB_X                    ; (Y: the place on the line)
    lda mosTMP
    sta MOSBUF,x
    lda mosTMP+1
    sta MOSBUF+1,x
    lda mosTMP+2
    sta MOSBUF+2,x
    lda mosTMP+3
    sta MOSBUF+3,x
    inx
    inx
    inx
    inx
    lda #HTTP_ADDINT
    bne jbs_send
jbs_syn:
    jmp s6_syntax
jbs_bool:
    sta MOSBUF,x
    inx
    lda #HTTP_ADDBOOL
    bne jbs_send
jbs_str:
    iny                         ; "text": its length, its bytes
    stx JB_X
    inx
jbs_sc:
    lda (mosPTR),y
    cmp #13
    beq jbs_syn
    iny
    cmp #'"'
    beq jbs_se
    sta MOSBUF,x
    inx
    cpx #250
    bcc jbs_sc
    bcs jbs_syn
jbs_se:
    txa                         ; length = X - (start + 1)
    clc
    sbc JB_X
    stx JB_E
    ldx JB_X
    sta MOSBUF,x
    ldx JB_E
    lda #HTTP_ADDSTR
jbs_send:
    sta uciHDR+1                ; (handle in uciHDR+2 since the start)
    stx fsLEN
    jsr s6_end
    lda #TARGET_HTTP
    sta uciHDR
    lda #3
    sta uciHLEN
    lda #<MOSBUF
    sta fsPTR
    lda #>MOSBUF
    sta fsPTR+1
    lda #0
    sta fsLEN+1
    jmp uci_cmd_payload

; jb_int: a number at mosPTR/Y into mosTMP (32 bits): A%-Z%, or [-]
; decimal or &hex. C = 1: none. Uses A, Y, mosTMP, MOSBUF+$F8-$FC.
JI_T        = MOSBUF+$F8        ; 4: scratch (x 10)
JI_NEG      = MOSBUF+$FC        ; 1: negative
jb_int:
    lda #0
    sta mosTMP
    sta mosTMP+1
    sta mosTMP+2
    sta mosTMP+3
    sta JI_NEG
    lda (mosPTR),y
    jsr s6_up
    cmp #'A'                    ; A%-Z%: the variable at &0400 + 4n
    bcc ji_num
    cmp #'Z'+1
    bcs ji_num
    pha
    iny
    lda (mosPTR),y
    cmp #'%'
    beq ji_var
    pla
    sec
    rts
ji_var:
    iny
    pla
    sec
    sbc #'@'
    asl
    asl
    tax
    lda $0400,x
    sta mosTMP
    lda $0401,x
    sta mosTMP+1
    lda $0402,x
    sta mosTMP+2
    lda $0403,x
    sta mosTMP+3
    clc
    rts
ji_num:
    lda (mosPTR),y
    cmp #'-'
    bne ji_sign
    inc JI_NEG
    iny
    lda (mosPTR),y
ji_sign:
    cmp #'&'
    beq ji_hex
    jsr ji_dig
    bcs ji_none
ji_dl:
    lda (mosPTR),y              ; value = value * 10 + digit
    jsr ji_dig
    bcs ji_done
    pha
    jsr ji_x2                   ; * 2, kept in JI_T
    ldx #3
ji_cp:
    lda mosTMP,x
    sta JI_T,x
    dex
    bpl ji_cp
    jsr ji_x2                   ; * 8
    jsr ji_x2
    clc                         ; + * 2, + digit
    ldx #0
ji_add:
    lda mosTMP,x
    adc JI_T,x
    sta mosTMP,x
    inx
    txa
    eor #4
    bne ji_add
    pla
    jsr ji_addd
    iny
    bne ji_dl
ji_hex:
    iny
    lda (mosPTR),y
    jsr ji_hdig
    bcs ji_none
ji_hl:
    lda (mosPTR),y
    jsr ji_hdig
    bcs ji_done
    pha
    jsr ji_x2                   ; * 16
    jsr ji_x2
    jsr ji_x2
    jsr ji_x2
    pla
    jsr ji_addd
    iny
    bne ji_hl
ji_done:
    lda JI_NEG                  ; negative: 0 - value
    beq ji_ok
    ldx #0
    sec
ji_ngl:
    lda #0
    sbc mosTMP,x
    sta mosTMP,x
    inx
    txa
    eor #4
    bne ji_ngl
ji_ok:
    clc
    rts
ji_none:
    sec
    rts
; ji_x2: mosTMP * 2; ji_addd: mosTMP + A
ji_x2:
    asl mosTMP
    rol mosTMP+1
    rol mosTMP+2
    rol mosTMP+3
    rts
ji_addd:
    clc
    adc mosTMP
    sta mosTMP
    bcc jad_rts
    inc mosTMP+1
    bne jad_rts
    inc mosTMP+2
    bne jad_rts
    inc mosTMP+3
jad_rts:
    rts
; ji_dig: A a decimal digit -> 0-9, C = 0; ji_hdig: hex too
ji_dig:
    cmp #'0'
    bcc jid_no
    cmp #'9'+1
    bcs jid_no
    sbc #'0'-1
    clc
    rts
jid_no:
    sec
    rts
ji_hdig:
    jsr ji_dig
    bcc jih_rts
    jsr s6_up
    cmp #'A'
    bcc jid_no
    cmp #'F'+1
    bcs jid_no
    sbc #'A'-11
    clc
jih_rts:
    rts

; ----------------------------------------------------------------------------
; hf_addhdrs
;   Summary: *NET HEADER's lines to the firmware request header nt_hdr
;            (HEADER_ADD &13 each), for *JSON GET and POST.
;   Function: from the REU (RH_HDRS, RH_HLEN bytes), a line at a time:
;            210 bytes to MOSBUF, the line is up to its CR.
;   Uses:    A, X, Y, fs*, mosTMP, mosNUM, MOSBUF.
hf_addhdrs:
    jsr s6_hasreu
    beq hah_rts
    ldx #<RH_HLEN               ; mosTMP+2/+3: bytes left
    jsr hr_rget
    sta mosTMP+2
    ldx #<[RH_HLEN+1]
    jsr hr_rget
    sta mosTMP+3
    lda #<RH_HDRS
    sta mosTMP
    lda #>RH_HDRS
    sta mosTMP+1
hah_line:
    lda mosTMP+2
    ora mosTMP+3
    beq hah_rts
    lda #210
    ldx #<MOSBUF
    ldy #>MOSBUF
    jsr hr_dmain
    ldx #0                      ; the line: up to its CR
hah_cr:
    lda MOSBUF,x
    cmp #13
    beq hah_got
    inx
    cpx #210
    bcc hah_cr
hah_rts:
    rts
hah_got:
    stx fsLEN                   ; HEADER_ADD nt_hdr, the line
    inx                         ; (on: the line, CR, LF)
    inx
    stx mosNUM
    lda #0
    sta fsLEN+1
    lda #<MOSBUF
    sta fsPTR
    lda #>MOSBUF
    sta fsPTR+1
    lda #TARGET_HTTP
    sta uciHDR
    lda #HTTP_HADD
    sta uciHDR+1
    lda nt_hdr
    sta uciHDR+2
    lda #3
    sta uciHLEN
    jsr uci_cmd_payload
    lda mosTMP                  ; the next line
    clc
    adc mosNUM
    sta mosTMP
    bcc hah_sub
    inc mosTMP+1
hah_sub:
    lda mosTMP+2
    sec
    sbc mosNUM
    sta mosTMP+2
    bcs hah_line
    dec mosTMP+3
    jmp hah_line
