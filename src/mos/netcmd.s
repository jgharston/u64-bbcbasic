; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- network: *NET, HTTP (bank 7, inside .local net)
;
; docs/DESIGN_NETWORK.md. The Ultimate's network target (UCI target 3:
; addresses, sockets) and its HTTP target (UCI target 6, firmware 3.15+:
; requests, JSON). HTTP replies are read whole into a 16 KB buffer in the
; REU (the firmware keeps at most 16 KB of a reply, and the command
; interface takes one command at a time, so a reply cannot be written to
; a file while it comes in); *NET GET then writes it to a file.
;
; ----------------------------------------------------------------------------

TARGET_NET  = $03
TARGET_HTTP = $06
NET_GETIP   = $05
NET_GETMAC  = $04
HTTP_HCREATE = $11              ; header create: verb, url -> handle
HTTP_HFREE  = $12
HTTP_FALL   = $10              ; free all handles
HTTP_RAW    = $32               ; exchange, raw reply (stream)
HTTP_GET    = $01
HTTP_NOBODY = $FF

REU_NETBUF  = $4000             ; 16K: HTTP replies (REU bank 0)
NETBUF_PAGES = 64

nt_len      = fsTMP             ; 2: the reply's length (bytes)
nt_hdr      = fsTMP+2           ; the request header handle (not in
                                ; MOSBUF: a download fills all of it)
netvars     = MOSBUF+$F0        ; JSON query results (a query reads at
                                ; most 240 bytes into MOSBUF)

; ----------------------------------------------------------------------------
; cmd_net
;   Summary: *NET: the Ultimate's network address; *NET GET <url> <file>:
;            download (http only; up to 16 KB) to a file (also /REU/...).
;   Input:   mosPTR/Y.  Output: text; raises on errors.
;   Uses:    A, X, Y, fs*, MOSBUF.
cmd_net:
    jsr uci_need
    lda #<nw_get
    ldx #>nw_get
    jsr s6_word
    bcc cn_time
    jmp net_get
cn_time:
    lda #<nw_time
    ldx #>nw_time
    jsr s6_word
    bcc cn_rnd
    jmp net_time
cn_rnd:
    lda #<nw_random
    ldx #>nw_random
    jsr s6_word
    bcc cn_show
    jsr s6_end
    jmp net_random
cn_show:
    jsr s6_end
    lda #TARGET_NET             ; IP address, netmask, gateway (12 bytes)
    sta uciHDR
    lda #NET_GETIP
    sta uciHDR+1
    lda #0
    sta uciHDR+2
    lda #3
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #12
    sta fsLEN
    jsr uci_read_to
    jsr uci_finish
    bcc cn_ok
    jmp uci_error
cn_ok:
    jsr s6_text
    dta 'IP      ', 0
    ldx #0
    jsr cn_quad
    jsr s6_text
    dta 13, 'Netmask ', 0
    ldx #4
    jsr cn_quad
    jsr s6_text
    dta 13, 'Gateway ', 0
    ldx #8
    jsr cn_quad
    jmp OSNEWL
; cn_quad: MOSBUF+X..+3 as a.b.c.d
cn_quad:
    ldy #4
cnq_l:
    stx fsSX
    sty fsSY
    lda MOSBUF,x
    jsr s6_dec8
    ldy fsSY
    ldx fsSX
    inx
    dey
    beq cnq_rts
    lda #'.'
    jsr OSWRCH
    jmp cnq_l
cnq_rts:
    rts

nw_get      dta 'GET', 0
nw_time     dta 'TIME', 0
nw_random   dta 'RANDOM', 0

; ----------------------------------------------------------------------------
; net_get
;   Summary: *NET GET <url> <file>: the reply's body to the file.
;   Function: http_fetch (into the REU buffer), then the file written
;            through bank 2's rx_ routines, a page at a time.
;   Uses:    A, X, Y, fs*, MOSBUF.
net_get:
    jsr s6_hasreu
    bne ng_reu
    brk
    dta 189, 'Downloads need an REU', 0
ng_reu:
    jsr s6_name                 ; the URL (measured like a file name)
    lda fsPTR
    pha
    lda fsPTR+1
    pha
    lda fsLEN
    pha
    jsr s6_name                 ; the file (kept on the stack: the
    jsr s6_end                  ; download fills MOSBUF)
    pla
    tax                         ; X = URL length
    pla
    sta fsTMP+3                 ; URL high
    pla
    sta nt_hdr                  ; URL low (for now)
    lda fsPTR
    pha
    lda fsPTR+1
    pha
    lda fsLEN
    pha
    lda nt_hdr
    sta fsPTR
    lda fsTMP+3
    sta fsPTR+1
    stx fsLEN
    lda #0
    sta fsLEN+1
    jsr http_fetch              ; -> nt_len bytes in the REU buffer
    pla                         ; the file
    sta fsLEN
    pla
    sta fsPTR+1
    pla
    sta fsPTR
    lda #0
    sta fsLEN+1
    farcall rx_create, BANK_FS
    lda #REU_FONT_BANK          ; whole pages
    ldy #>REU_NETBUF
    ldx nt_len+1
    farcall rx_write, BANK_FS
    lda nt_len                  ; the rest
    beq ng_close
    tax
    lda nt_len+1
    clc
    adc #>REU_NETBUF
    tay
    lda #REU_FONT_BANK
    farcall rx_wtail, BANK_FS
ng_close:
    farcall rx_close, BANK_FS
    lda nt_len                  ; "n bytes"
    sta mosTMP
    lda nt_len+1
    sta mosTMP+1
    jsr s6_dec16
    jsr s6_text
    dta ' bytes', 13, 0
    rts

; ----------------------------------------------------------------------------
; http_fetch
;   Summary: GET the URL at fsPTR/fsLEN (http://host[:port]/path, or
;            host/path) through the HTTP target; the body into the REU
;            buffer (REU_NETBUF, at most 16 KB), its length in nt_len.
;   Function: header create (handle), raw exchange: the body comes as a
;            stream, read 256 bytes at a time into MOSBUF and copied to
;            the REU; the header handle is freed. A response line in the
;            status other than 2xx raises it as an error -- but firmware
;            3.15a returns no status after a raw exchange (measured), so
;            an error page comes back like any reply.
;   Output:  nt_len.  Raises: the firmware's or the server's status.
;   Uses:    A, X, Y, fs*, MOSBUF.
http_fetch:
    jsr hf_create               ; nt_hdr = a GET header for the URL
hf_hdr:
    lda #TARGET_HTTP            ; raw exchange: header, no body
    sta uciHDR
    lda #HTTP_RAW
    sta uciHDR+1
    lda nt_hdr
    sta uciHDR+2
    lda #HTTP_NOBODY
    sta uciHDR+3
    lda #4
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    sta nt_len
    sta nt_len+1
    jsr uci_send
hf_page:
    jsr uci_chkesc              ; (ESCAPE ends a reply that does not)
    lda #<MOSBUF                ; 256 bytes at a time
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #0
    sta fsLEN
    lda #1
    sta fsLEN+1
    jsr uci_read_to
    lda fsCNT
    ora fsCNT+1
    beq hf_end
    lda nt_len+1                ; room in the buffer? (none: the command
    cmp #NETBUF_PAGES           ; aborted, what came is kept)
    bcc hf_room
    lda #$04
    sta UCI_CTRL
    jmp hf_end
hf_room:
    lda #0                      ; MOSBUF -> the buffer's next page
    sta REU_ADDR
    sta REU_LEN+1
    sta REU_CTRL
    lda nt_len+1
    clc
    adc #>REU_NETBUF
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<MOSBUF
    sta REU_C64
    lda #>MOSBUF
    sta REU_C64+1
    lda fsCNT
    sta REU_LEN
    lda fsCNT+1                 ; (256: length $0100)
    sta REU_LEN+1
    lda #REU_TO_REU
    sta REU_CMD
    lda nt_len                  ; length += received
    clc
    adc fsCNT
    sta nt_len
    lda nt_len+1
    adc fsCNT+1
    sta nt_len+1
hf_full:
    lda fsCNT+1                 ; a whole page: there may be more
    bne hf_page
hf_end:
    jsr uci_finish              ; the status: the response line
    jsr hf_free
    jsr hf_status
    bcc hf_rts
    jmp uci_error
hf_rts:
    rts

; hf_create
;   Summary: a GET request header for the URL at fsPTR/fsLEN: nt_hdr.
;   Function: when the firmware's 16 header slots are all taken ("507":
;            handles left over, e.g. from an earlier program or a reset of
;            the C64 alone), FREE_ALL and once more (a kept JSON reply is
;            then gone too).
;   Uses:    A, X, Y, fs*.
hf_create:
    lda fsPTR                   ; (kept for the second try)
    sta hc_ptr
    lda fsPTR+1
    sta hc_ptr+1
    lda fsLEN
    sta hc_len
    lda #2
    sta hc_try
hc_again:
    lda hc_ptr
    sta fsPTR
    lda hc_ptr+1
    sta fsPTR+1
    lda hc_len
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #TARGET_HTTP            ; header: GET url
    sta uciHDR
    lda #HTTP_HCREATE
    sta uciHDR+1
    lda #HTTP_GET
    sta uciHDR+2
    lda #3
    sta uciHLEN
    jsr uci_send
    lda #<nt_hdr
    sta fsADDR
    lda #>nt_hdr
    sta fsADDR+1
    lda #1
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_read_to
    jsr uci_finish
    bcc hc_rts
    dec hc_try
    beq hc_err
    lda errbuf+1                ; "507 NO HEADER SLOT": free all, again
    cmp #'5'
    bne hc_err
    lda errbuf+3
    cmp #'7'
    bne hc_err
    jsr http_freeall
    jmp hc_again
hc_err:
    jmp uci_error
hc_rts:
    rts
hc_ptr      = netvars           ; 2 (MOSBUF+$F0: not used by the create)
hc_len      = netvars+2
hc_try      = netvars+3

; http_freeall: every header and body handle of the HTTP target freed
; (FREE_ALL); the kept JSON reply is gone
http_freeall:
    lda #$FF
    sta json_body
    sta json_rhdr
    lda #TARGET_HTTP
    sta uciHDR
    lda #HTTP_FALL
    sta uciHDR+1
    lda #2
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    ldx #ERRMAX-24
    jmp uci_finish_x

; hf_free: free the request header (errors ignored; errbuf kept)
hf_free:
    lda #TARGET_HTTP
    sta uciHDR
    lda #HTTP_HFREE
    sta uciHDR+1
    lda nt_hdr
    sta uciHDR+2
    lda #3
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    ldx #ERRMAX-24              ; (its status lands at the end of errbuf)
    jmp uci_finish_x

; hf_status: C = 0 if errbuf+1 holds a 2xx response ("HTTP/1.x 2.."), or
; is empty; else C = 1 (errbuf+1 says why)
hf_status:
    lda errbuf+1
    beq hs_ok
    cmp #'0'                    ; the code first ("200 ok", JSON exchange)
    bcc hs_line
    cmp #'9'+1
    bcs hs_line
    cmp #'2'
    bne hs_bad
    clc
    rts
hs_line:
    ldx #0                      ; "HTTP/1.1 200 OK": after the first space
hs_sp:
    lda errbuf+1,x
    beq hs_bad
    inx
    cmp #' '
    bne hs_sp
    lda errbuf+1,x
    cmp #'2'
    bne hs_bad
hs_ok:
    clc
    rts
hs_bad:
    sec
    rts

; ----------------------------------------------------------------------------
; JSON (owner, 2026-10-09): a reply parsed by the firmware is kept as a
; body handle (json_body); values are queried by path ("main/temp",
; "list%2/title", "%0" for an array's first element).

HTTP_JEXCH  = $31               ; exchange, JSON reply -> header, body handle
HTTP_BFREE  = $22
HTTP_BQUERY = $2A
JT_INT      = $01               ; value types in a query's reply
JT_BOOL     = $02
JT_STRING   = $03
JT_OBJECT   = $04
JT_ARRAY    = $05

; net_init: at start-up: no JSON reply kept
net_init:
    lda #$FF
    sta json_body
    sta json_rhdr
    lda uci_ok                  ; handles a previous session left: freed
    beq ni_rts
    jmp http_freeall
ni_rts:
    rts

; ----------------------------------------------------------------------------
; cmd_json
;   Summary: *JSON GET <url>: fetch a JSON reply and keep it (parsed by the
;            Ultimate); *JSON <path>: print the value at path.
;   Input:   mosPTR/Y.  Output: text; raises on errors.
;   Uses:    A, X, Y, fs*, MOSBUF.
cmd_json:
    jsr uci_need
    lda #<nw_get
    ldx #>nw_get
    jsr s6_word
    bcs cj_get
    jsr s6_name                 ; the path
    jsr s6_end
    jsr json_query              ; -> jq_type, jq_text (MOSBUF), jq_len
    ldx #0
cj_print:
    cpx jq_len
    beq cj_nl
    lda MOSBUF,x
    jsr OSASCI
    inx
    bne cj_print
cj_nl:
    jmp OSNEWL
cj_get:
    jsr s6_name                 ; the URL
    jsr s6_end
    jmp json_get

; ----------------------------------------------------------------------------
; json_get
;   Summary: GET the URL at fsPTR/fsLEN as JSON; the reply's body handle
;            kept in json_body (an earlier one freed first).
;   Output:  raises the firmware's or the server's status (2xx needed;
;            "400 NO VALID JSON" when the reply is not JSON).
;   Uses:    A, X, Y, fs*.
json_get:
    lda fsPTR                   ; (json_free uses fsPTR/fsLEN)
    pha
    lda fsPTR+1
    pha
    lda fsLEN
    pha
    jsr json_free
    pla
    sta fsLEN
    lda #0
    sta fsLEN+1
    pla
    sta fsPTR+1
    pla
    sta fsPTR
    jsr hf_create               ; nt_hdr = a GET header for the URL
jg_hdr:
    lda #TARGET_HTTP            ; JSON exchange: header, no body
    sta uciHDR
    lda #HTTP_JEXCH
    sta uciHDR+1
    lda nt_hdr
    sta uciHDR+2
    lda #HTTP_NOBODY
    sta uciHDR+3
    lda #4
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    lda #$FF
    sta MOSBUF
    sta MOSBUF+1
    jsr uci_send
    lda #<MOSBUF                ; the response header and body handles
    ldx #>MOSBUF
    ldy #2
    jsr jg_read
    jsr uci_finish
    jsr hf_free                 ; (the request header)
    lda MOSBUF                  ; both handles valid?
    cmp #16
    bcs jg_err
    lda MOSBUF+1
    cmp #16
    bcs jg_err
    sta json_body
    lda MOSBUF
    sta json_rhdr
    jsr hf_status               ; the server said 2xx?
    bcs jg_err
    rts
jg_err:
    jmp uci_error

; jg_read: read up to Y bytes of the reply to A/X (low/high)
jg_read:
    sta fsADDR
    stx fsADDR+1
    sty fsLEN
    lda #0
    sta fsLEN+1
    jmp uci_read_to

; json_free: free the kept reply (body and response header handles)
json_free:
    lda json_body
    cmp #16
    bcs jf_hdr
    ldx #HTTP_BFREE
    jsr jf_cmd
    lda #$FF
    sta json_body
jf_hdr:
    lda json_rhdr
    cmp #16
    bcs jf_rts
    ldx #HTTP_HFREE
    jsr jf_cmd
    lda #$FF
    sta json_rhdr
jf_rts:
    rts
; jf_cmd: HTTP target command X with handle A (errors ignored)
jf_cmd:
    sta uciHDR+2
    stx uciHDR+1
    lda #TARGET_HTTP
    sta uciHDR
    lda #3
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    ldx #ERRMAX-24
    jmp uci_finish_x

; ----------------------------------------------------------------------------
; json_query
;   Summary: the value at the path fsPTR/fsLEN of the kept reply, as text.
;   Function: the firmware's query: a type byte and the value. As text in
;            MOSBUF (jq_len bytes): a string as it is (up to 240
;            characters), an integer in decimal, TRUE/FALSE; an object or
;            an array gives its entry count (jq_count) and no text.
;   Output:  jq_type (0: none), jq_len, jq_count, MOSBUF. Raises "No JSON"
;            without a reply, the firmware's status for a wrong path.
;   Uses:    A, X, Y, fs*, MOSBUF.
json_query:
    lda json_body
    cmp #16
    bcc jq_have
    brk
    dta 214, 'No JSON reply (*JSON GET)', 0
jq_have:
    sta uciHDR+2
    lda #TARGET_HTTP
    sta uciHDR
    lda #HTTP_BQUERY
    sta uciHDR+1
    lda #3
    sta uciHLEN
    lda #0
    sta fsLEN+1
    jsr uci_send                ; (payload: the path)
    lda #<MOSBUF                ; the reply (type, value)
    ldx #>MOSBUF
    ldy #240
    jsr jg_read
    lda UCI_STAT                ; more than that (an object or array with
    bpl jq_finish               ; all its content: firmware 3.15a may then
    lda #$04                    ; stream without end): abort the command,
    sta UCI_CTRL                ; the type and count are in what came
jq_abort:
    bit ESCFLG
    bmi jq_finish
    lda UCI_STAT                ; until the interface is idle again
    and #$34
    bne jq_abort
    jmp jq_got
jq_finish:
    jsr uci_finish
    bcc jq_got
    jmp uci_error
jq_got:
    lda #0
    sta jq_len
    sta jq_count
    lda fsCNT                   ; nothing: no type
    bne jq_type1
    sta jq_type
    rts
jq_type1:
    lda MOSBUF
    sta jq_type
    cmp #JT_STRING
    beq jq_string
    cmp #JT_INT
    beq jq_int
    cmp #JT_BOOL
    beq jq_bool
    lda MOSBUF+1                ; object, array: the count
    sta jq_count
    rts
jq_string:
    ldx #0                      ; MOSBUF+2.. down to MOSBUF
    ldy MOSBUF+1
    beq jqs_end
jqs_copy:
    lda MOSBUF+2,x
    sta MOSBUF,x
    inx
    cpx #238
    bcs jqs_end
    dey
    bne jqs_copy
jqs_end:
    stx jq_len
    rts
jq_bool:
    lda MOSBUF+1
    beq jqb_false
    ldx #3
jqb_t:
    lda jqb_true,x
    sta MOSBUF,x
    dex
    bpl jqb_t
    lda #4
    sta jq_len
    rts
jqb_false:
    ldx #4
jqb_f:
    lda jqb_fls,x
    sta MOSBUF,x
    dex
    bpl jqb_f
    lda #5
    sta jq_len
    rts
jqb_true    dta 'TRUE'
jqb_fls     dta 'FALSE'
jq_int:
    ldx #3                      ; the 32-bit value aside
jqi_cp:
    lda MOSBUF+1,x
    sta jq_num,x
    dex
    bpl jqi_cp
    ldx #0                      ; X = text length
    lda jq_num+3                ; negative: "-" and the value negated
    bpl jqi_dec
    lda #'-'
    sta MOSBUF
    inx
    sec                         ; 0 - value, 4 bytes (unrolled: a compare
    lda #0                      ; in a loop would lose the borrow)
    sbc jq_num
    sta jq_num
    lda #0
    sbc jq_num+1
    sta jq_num+1
    lda #0
    sbc jq_num+2
    sta jq_num+2
    lda #0
    sbc jq_num+3
    sta jq_num+3
; jqi_dec: jq_num (unsigned 32) in decimal after MOSBUF+X
jqi_dec:
    stx jq_len
    ldy #0                      ; digits, reversed, on the stack
jqd_div:
    lda #0                      ; jq_num / 10, remainder in A
    ldx #32
jqd_bit:
    asl jq_num
    rol jq_num+1
    rol jq_num+2
    rol jq_num+3
    rol
    cmp #10
    bcc jqd_nb
    sbc #10
    inc jq_num
jqd_nb:
    dex
    bne jqd_bit
    pha
    iny
    lda jq_num
    ora jq_num+1
    ora jq_num+2
    ora jq_num+3
    bne jqd_div
    ldx jq_len
jqd_out:
    pla
    ora #'0'
    sta MOSBUF,x
    inx
    dey
    bne jqd_out
    stx jq_len
    rts

jq_type     = netvars+6
jq_len      = netvars+7
jq_count    = netvars+8
jq_num      = netvars+9         ; 4
json_body   = $03FE             ; the kept reply's body handle ($FF: none)
json_rhdr   = $03FF             ; and its response header handle

; ----------------------------------------------------------------------------
; json_word (OSWORD &70)
;   Summary: a value of the kept JSON reply for a program (the BASIC
;            library's FNjson).
;   Function: block +0/+1 the path's address, +2 its length; +3/+4 where
;            the value goes, +5 room there (bytes). Returns +6 the type
;            (0 none, 1 integer, 2 TRUE/FALSE, 3 string, 4 object, 5
;            array), +7 the text's length (cut to the room), +8 the entry
;            count of an object or array. The text as json_query.
;   Input:   mosPTR = block.  Output: the block, the text.
;   Uses:    A, X, Y, fs*, MOSBUF.
json_word:
    ldy #0
    lda (mosPTR),y
    sta fsPTR
    iny
    lda (mosPTR),y
    sta fsPTR+1
    iny
    lda (mosPTR),y
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr json_query
    ldy #6
    lda jq_type
    sta (mosPTR),y
    ldy #8
    lda jq_count
    sta (mosPTR),y
    ldy #5                      ; length: at most the room
    lda jq_len
    cmp (mosPTR),y
    bcc jw_len
    lda (mosPTR),y
jw_len:
    ldy #7
    sta (mosPTR),y
    sta fsCNT
    ldy #3                      ; the text to +3/+4
    lda (mosPTR),y
    sta fsADDR
    iny
    lda (mosPTR),y
    sta fsADDR+1
    ldy #0
jw_copy:
    cpy fsCNT
    beq jw_rts
    lda MOSBUF,y
    sta (fsADDR),y
    iny
    bne jw_copy
jw_rts:
    rts

; ----------------------------------------------------------------------------
; net_time
;   Summary: *NET TIME [server]: the Ultimate sets its clock from the
;            internet (its own SNTP client: "SNTP Enable", and the server
;            as "Time Server 1" if given); then the time is shown.
;   Function: a configuration file loaded through the firmware ("load
;            config", as *SID PAN); the time zone is the Ultimate's
;            setting.
;   Uses:    A, X, Y, fs*, MOSBUF, osfblk.
net_time:
    ldx #0                      ; the file in MOSBUF
    lda #<nt_cfg1
    ldy #>nt_cfg1
    jsr nt_str
    jsr s6_skipsp               ; a server?
    cmp #13
    beq nt_save
    sty fsCNT                   ; (nt_str uses Y)
    lda #<nt_cfg2
    ldy #>nt_cfg2
    jsr nt_str
    ldy fsCNT
nt_srv:
    lda (mosPTR),y
    cmp #' '+1
    bcc nt_srvend
    sta MOSBUF,x
    inx
    iny
    cpx #120                    ; (MOSBUF+$E0 holds the file name)
    bcc nt_srv
nt_srvend:
    lda #13
    sta MOSBUF,x
    inx
    lda #10
    sta MOSBUF,x
    inx
nt_save:
    txa                         ; OSFILE 0: MOSBUF .. +X as the file
    clc
    adc #<MOSBUF
    sta osfblk+14
    lda #>MOSBUF
    adc #0
    sta osfblk+15
    lda #<MOSBUF
    sta osfblk+10
    lda #>MOSBUF
    sta osfblk+11
    ldx #nt_fend-nt_file-1      ; the name into RAM (OSFILE reads it with
nt_name:                        ; bank 2 mapped): MOSBUF+$E0, CR-ended
    lda nt_file,x
    bne nt_nch
    lda #13
nt_nch:
    sta MOSBUF+$E0,x
    dex
    bpl nt_name
    lda #<[MOSBUF+$E0]
    sta osfblk
    lda #>[MOSBUF+$E0]
    sta osfblk+1
    lda #0
    ldx #<osfblk
    ldy #>osfblk
    jsr OSFILE
    lda #<nt_file               ; load config: the path, 0
    sta fsPTR
    lda #>nt_file
    sta fsPTR+1
    lda #nt_fend-nt_file
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #TARGET_CTRL
    sta uciHDR
    lda #$50
    sta uciHDR+1
    lda #2
    sta uciHLEN
    jsr uci_send
    jsr uci_finish
    bcc nt_show
    jmp uci_error
nt_show:
    lda #0                      ; the clock (OSWORD 14, the string)
    sta MOSBUF
    lda #14
    ldx #<MOSBUF
    ldy #>MOSBUF
    jsr OSWORD
    ldx #0
nts_l:
    lda MOSBUF,x
    cmp #13
    beq nts_end
    jsr OSWRCH
    inx
    cpx #30
    bne nts_l
nts_end:
    jmp OSNEWL

; nt_str: the 0-terminated text at A/Y (low/high; this bank) to MOSBUF+X
nt_str:
    sta fsBLK
    sty fsBLK+1
    ldy #0
nts_c:
    lda (fsBLK),y
    beq nts_rts
    sta MOSBUF,x
    inx
    iny
    bne nts_c
nts_rts:
    rts

nt_cfg1     dta '[Network Settings]', 13, 10, 'SNTP Enable=Enabled', 13, 10, 0
nt_cfg2     dta 'Time Server 1=', 0
nt_file     dta '/Temp/bbcnet.cfg', 0
nt_fend

; ----------------------------------------------------------------------------
; net_random
;   Summary: *NET RANDOM: seed BASIC's RND from the internet: the drand
;            beacon's latest randomness (http://api.drand.sh/public/latest,
;            JSON), its first 40 bits into RND's seed (&0D-&11) (PLAN.md
;            section 21).
;   Function: json_get, json_query "randomness" (64 hex digits), the kept
;            JSON reply freed again.
;   Uses:    A, X, Y, fs*, MOSBUF.
net_random:
    lda #<nr_url
    sta fsPTR
    lda #>nr_url
    sta fsPTR+1
    lda #nr_uend-nr_url
    sta fsLEN
    jsr json_get
    lda #<nr_path
    sta fsPTR
    lda #>nr_path
    sta fsPTR+1
    lda #nr_pend-nr_path
    sta fsLEN
    jsr json_query
    lda jq_len
    cmp #10
    bcc nr_bad
    ldx #0                      ; 10 hex digits -> 5 bytes
    ldy #0
nr_byte:
    lda MOSBUF,y
    jsr nr_hex
    asl
    asl
    asl
    asl
    sta nc_byte
    lda MOSBUF+1,y
    jsr nr_hex
    ora nc_byte
    sta zpSEEDMOS,x
    iny
    iny
    inx
    cpx #5
    bne nr_byte
    lda zpSEEDMOS               ; (an all-zero seed would stick)
    ora zpSEEDMOS+1
    ora zpSEEDMOS+2
    ora zpSEEDMOS+3
    ora zpSEEDMOS+4
    bne nr_ok
    inc zpSEEDMOS
nr_ok:
    jsr json_free
    jsr s6_text
    dta 'RND seeded from drand', 13, 0
    rts
nr_bad:
    jsr json_free
    brk
    dta 214, 'No randomness', 0
; nr_hex: A = the value of hex digit A (0-9, a-f, A-F)
nr_hex:
    cmp #'A'
    bcc nrh_dig
    and #$DF
    sbc #'A'-10
    rts
nrh_dig:
    and #$0F
    rts

nr_url      dta 'http://api.drand.sh/public/latest'
nr_uend
nr_path     dta 'randomness'
nr_pend
zpSEEDMOS   = $0D               ; BASIC's RND seed, 5 bytes (vars.s zpSEED)
