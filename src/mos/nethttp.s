; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- an HTTP/1.0 client over the network target's TCP socket
; (bank 7, inside .local net; 1.0.0 item 7)
;
; Firmware 3.15a's HTTP target gives no status code for raw requests and
; only for valid JSON replies otherwise (measured 2026-10-17, PLAN.md 27
; item 7), so the owner chose: the MOS speaks HTTP/1.0 itself. Used by
; *NET GET/POST/PUT/DELETE and OPENIN "http://" (*JSON keeps the
; firmware's JSON parser).
;
; A request: TCP open to the host (port 80 unless given), then
;   VERB path HTTP/1.0 / Host: host[:port] / Connection: close / the
;   *NET HEADER lines / Content-Length: n (with a body) / an empty line /
;   the body (a string from the command line, or a file).
; The reply is read 254 bytes at a time (NET_READ into MOSBUF); the status
; line and the headers are parsed byte by byte (Content-Length is
; honoured), the body goes to the sink: the REU buffer (OPENIN, up to
; 16K), a file (streamed, no size limit) or the screen. A status of 400 or
; more stops at the headers and raises error 223 "HTTP 404 Not Found".
;
; State: the top of BASIC's string buffer (&06E0-&06FF, free while a
; command works, as speech's &06F0; a command line in page 6 must end
; before it). REU bank 0 &3C80-&3FFF (docs/ARCHITECTURE.md 7): the last
; status code and line, a socket left open by an error, the *NET HEADER
; lines.
;
; ----------------------------------------------------------------------------

REU_HTTP    = $3C80             ; REU bank 0:
RH_CODE     = REU_HTTP+0        ; 2: the last status code (0: none)
RH_HLEN     = REU_HTTP+2        ; 2: length of the header lines
RH_SOCK     = REU_HTTP+4        ; a socket an error left open ($FF: none)
RH_JBODY    = REU_HTTP+5        ; *JSON NEW's body handle ($FF: none)
RH_LINE     = REU_HTTP+8        ; 40: the last status line ("HTTP 404 ...")
RH_HDRS     = REU_HTTP+$40      ; 832: *NET HEADER lines, CR LF each
RH_HMAX     = $4000-RH_HDRS

HS          = $06E0             ; state (32 bytes, to &06FF)
hs_sock     = HS+0              ; the socket
hs_phase    = HS+1              ; 0 status line, 1 headers, 2 body
hs_col      = HS+2              ; column in the line (to 255)
hs_clm      = HS+3              ; 1: this header line is Content-Length
hs_clen     = HS+4              ; 3: body bytes still to come
hs_have     = HS+7              ; 1: Content-Length known
hs_sink     = HS+8              ; HK_*
hs_code     = HS+9              ; 2: the status code
hs_idle     = HS+11             ; 2: empty reads in a row
hs_verb     = HS+13             ; HV_* (an offset into hv_text)
hs_bkind    = HS+14             ; 0 no body, 1 string, 2 file
hs_bptr     = HS+15             ; 2: the body string
hs_blen     = HS+17             ; 2: the body's length
hs_url      = HS+19             ; 2: the URL
hs_ulen     = HS+21
hs_out      = HS+22             ; 2: the output file's name
hs_olen     = HS+24
hs_i        = HS+25             ; position in the chunk
hs_n        = HS+26             ; bytes in the chunk
hs_fopen    = HS+27             ; 1: the output file is open
hs_host     = HS+28             ; the host's offset in the URL
hs_hlen     = HS+29             ; host[:port]'s length
hs_path     = HS+30             ; the path's offset (= hs_ulen: none)
hs_port     = HS+31             ; (scratch: ":port" found)

HK_REU      = 0                 ; sinks
HK_FILE     = 1
HK_SCREEN   = 2
HR_CHUNK    = 254               ; NET_READ: count (2) + data <= 256
HR_IDLEMAX  = 750               ; 750 empty reads of 40 ms: 30 s

; ----------------------------------------------------------------------------
; http_req
;   Summary: one HTTP request: hs_verb, hs_url/hs_ulen, the body (hs_bkind,
;            hs_bptr/hs_blen or the file at hs_bptr/hs_blen), the sink
;            (hs_sink; the file hs_out/hs_olen).
;   Function: closes a socket an earlier error left open, parses the URL,
;            opens the TCP connection, sends the request, reads the reply
;            (hr_receive), closes; a status of 400 or more raises error
;            223 with the status line.
;   Output:  hs_code; REU sink: nt_len bytes at REU_NETBUF. RH_CODE and
;            RH_LINE in the REU (OSBYTE &65).
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF, HS.
http_req:
    jsr s6_hasreu
    bne hr_reu
    brk
    dta 189, 'HTTP needs an REU', 0
hr_reu:
    jsr uci_need
    jsr hr_oldsock
    lda #0
    sta hs_code
    sta hs_code+1
    sta hs_fopen
    jsr hr_putcode              ; (no status yet)
    jsr hr_parse
    jsr hr_open
    jsr hr_request
    lda #0                      ; (nt_len is fsTMP: also nc_port and the
    sta nt_len                  ; body file's size until here)
    sta nt_len+1
    sta hs_blen                 ; the body bytes received (24 bits: the
    sta hs_blen+1               ; request's fields are free now)
    sta hs_bptr
    jsr hr_receive
    jsr hr_close
    lda hs_fopen
    beq hr_nofile
    farcall rx_close, BANK_FS
hr_nofile:
    jsr hr_isbad                ; >= 400: error 223, the status line
    bcs hr_bad
    rts
hr_bad:
    jmp hr_raise

; hr_isbad: C = 1 if hs_code >= 400
hr_isbad:
    lda hs_code
    cmp #<400
    lda hs_code+1
    sbc #>400
    rts

; hr_oldsock: close the socket an error left open (RH_SOCK), mark none
hr_oldsock:
    ldx #<RH_SOCK
    jsr hr_rget
    cmp #$FF
    beq hos_rts
    sta hs_sock
    jsr hr_close
hos_rts:
    rts

; http_code (OSBYTE &65): X/Y = the last status code (low, high; 0: none
; or no REU). Uses A, mosTMP (none: it keeps the caller's mosTMP+3).
http_code:
    ldx #0
    ldy #0
    jsr s6_hasreu
    beq hcd_rts
    ldx #<[RH_CODE+1]
    jsr hr_rget
    tay
    ldx #<RH_CODE
    jsr hr_rget
    tax
hcd_rts:
    rts

; ----------------------------------------------------------------------------
; hr_parse
;   Summary: split the URL: "http://" (optional), host, ":port"
;            (optional), path (optional: "/").
;   Output:  hs_host, hs_hlen, hs_path; the host with a 0 in MOSBUF (the
;            TCP open's payload); nc_port.
;   Uses:    A, X, Y, fsPTR, nc_port.
hr_parse:
    lda hs_url
    sta fsPTR
    lda hs_url+1
    sta fsPTR+1
    lda hs_url+1                ; (page 6: the state lies at &06E0)
    cmp #>HS
    bne hp_len
    lda hs_url
    clc
    adc hs_ulen
    bcs hp_long
    cmp #<HS
    bcc hp_len
hp_long:
    brk
    dta 204, 'Line too long', 0
hp_len:
    ldy #0                      ; "http://"?
    jsr nc_isnet
    bcc hp_host0
    cmp #3
    bne hp_host0
    ldy #7
    .byte $2C
hp_host0:
    ldy #0
    sty hs_host
    lda #0
    sta hs_port
    sta nc_port+1
    lda #80                     ; port 80 unless given
    sta nc_port
    ldx #0
hp_host:
    cpy hs_ulen
    bcs hp_end
    lda (fsPTR),y
    cmp #'/'
    beq hp_end
    cmp #':'
    beq hp_colon
    sta MOSBUF,x
    inx
    iny
    cpx #200
    bcc hp_host
hp_bad:
    brk
    dta 204, 'Bad URL', 0
hp_colon:
    lda #0                      ; the host ends; the port follows
    sta MOSBUF,x
    inc hs_port
    sta nc_port
hp_dig:
    iny
    cpy hs_ulen
    bcs hp_pend
    lda (fsPTR),y
    cmp #'/'
    beq hp_pend
    sec
    sbc #'0'
    cmp #10
    bcs hp_bad
    pha                         ; port = port * 10 + digit
    lda nc_port
    ldx nc_port+1
    asl nc_port
    rol nc_port+1
    asl nc_port
    rol nc_port+1
    clc
    adc nc_port
    sta nc_port
    txa
    adc nc_port+1
    sta nc_port+1
    asl nc_port
    rol nc_port+1
    pla
    clc
    adc nc_port
    sta nc_port
    bcc hp_dig
    inc nc_port+1
    bne hp_dig
hp_pend:
    lda nc_port
    ora nc_port+1
    beq hp_bad
    bne hp_path
hp_end:
    lda hs_port                 ; (a port ended the host already)
    bne hp_path
    lda #0
    sta MOSBUF,x
hp_path:
    sty hs_path
    tya                         ; host[:port] = host .. path
    sec
    sbc hs_host
    beq hp_bad
    sta hs_hlen
    rts

; ----------------------------------------------------------------------------
; hr_open: TCP open to the host (MOSBUF, 0) on nc_port: hs_sock; raises
; the firmware's error ("Network error" when it gives no reason)
hr_open:
    lda #<MOSBUF
    sta fsPTR
    lda #>MOSBUF
    sta fsPTR+1
    ldx #0                      ; the payload: the host and its 0
ho_len:
    lda MOSBUF,x
    beq ho_got
    inx
    bne ho_len
ho_got:
    inx
    stx fsLEN
    lda #0
    sta fsLEN+1
    lda #TARGET_NET
    sta uciHDR
    lda #NET_TCPOPEN
    sta uciHDR+1
    lda nc_port
    sta uciHDR+2
    lda nc_port+1
    sta uciHDR+3
    lda #4
    sta uciHLEN
    jsr uci_send
    lda #<hs_sock
    sta fsADDR
    lda #>hs_sock
    sta fsADDR+1
    lda #1
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_read_to
    jsr uci_finish
    bcc ho_ok
    jmp uci_error
ho_ok:
    lda hs_sock                 ; kept in the REU until it is closed
    ldx #<RH_SOCK
    jmp hr_rput

; hr_close: close hs_sock (errors ignored), RH_SOCK = none
hr_close:
    lda #TARGET_NET
    sta uciHDR
    lda #NET_CLOSE
    sta uciHDR+1
    lda hs_sock
    sta uciHDR+2
    lda #3
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    ldx #32
    jsr uci_finish_x
    lda #$FF
    ldx #<RH_SOCK
    jmp hr_rput

; ----------------------------------------------------------------------------
; hr_request
;   Summary: send the request line, the headers and the body.
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF.
hr_request:
    ldx hs_verb                 ; "VERB "
    lda hv_len,x
    tay
    lda hv_tab,x
    ldx #>hv_text
    clc
    adc #<hv_text
    bcc hq_v
    inx
hq_v:
    jsr hr_write
    lda hs_path                 ; the path, or "/"
    cmp hs_ulen
    bcc hq_path
    lda #<hq_slash
    ldx #>hq_slash
    ldy #1
    jsr hr_write
    jmp hq_ver
hq_path:
    lda hs_ulen                 ; Y = its length (hr_urlptr keeps Y)
    sec
    sbc hs_path
    tay
    lda hs_path
    jsr hr_urlptr
    jsr hr_write
hq_ver:
    lda #<hq_v10                ; " HTTP/1.0", "Host: host[:port]"
    ldx #>hq_v10
    ldy #hq_v10e-hq_v10
    jsr hr_write
    lda hs_host
    jsr hr_urlptr
    ldy hs_hlen
    jsr hr_write
    lda #<hq_close              ; "Connection: close"
    ldx #>hq_close
    ldy #hq_closee-hq_close
    jsr hr_write
    jsr hr_headers              ; *NET HEADER's lines
    lda hs_bkind                ; a body: its length (a file: opened)
    beq hq_end
    cmp #2
    bne hq_len
    jsr hr_fopen
hq_len:
    lda #<hq_clen
    ldx #>hq_clen
    ldy #hq_clene-hq_clen
    jsr hr_write
    jsr hr_decbl                ; hs_blen in decimal (MOSBUF+$F0)
    jsr hr_write
hq_end:
    lda #<hq_crlf               ; the empty line: the end of the headers
    ldx #>hq_crlf
    ldy #2
    jsr hr_write
    lda hs_bkind
    beq hq_rts
    cmp #2
    beq hr_fbody
    ldy hs_blen                 ; a string body (none if empty)
    beq hq_rts
    lda hs_bptr
    ldx hs_bptr+1
    jmp hr_write
hq_rts:
    rts

; hr_fbody: the file's bytes (opened by hr_fopen), a page at a time
; through MOSBUF; then the file closed
hr_fbody:
    lda hs_blen
    ora hs_blen+1
    beq hfb_close
    lda #REU_FONT_BANK          ; one page (also left in MOSBUF)
    ldy #>REU_NETBUF
    ldx #1
    farcall rx_read, BANK_FS
    ldy #0                      ; this piece: 256 or what is left
    lda hs_blen+1
    bne hfb_page
    ldy hs_blen
hfb_page:
    tya
    pha
    lda #<MOSBUF
    ldx #>MOSBUF
    jsr hr_write
    pla                         ; length -= piece (0: 256)
    beq hfb_256
    lda #0
    sta hs_blen
    beq hfb_close
hfb_256:
    dec hs_blen+1
    jmp hr_fbody
hfb_close:
    farcall rx_close, BANK_FS
    rts

; hr_fopen: open the body file (hs_bptr/hs_blen: its name): hs_blen = its
; size (at most 65535, else "Body too big")
hr_fopen:
    lda hs_bptr
    sta fsPTR
    lda hs_bptr+1
    sta fsPTR+1
    lda hs_blen
    sta fsLEN
    lda #0
    sta fsLEN+1
    farcall rx_openin, BANK_FS  ; fsTMP = the size (32 bits)
    lda fsTMP+2
    ora fsTMP+3
    beq hfo_ok
    farcall rx_close, BANK_FS
    brk
    dta 204, 'Body too big (64K)', 0
hfo_ok:
    lda fsTMP
    sta hs_blen
    lda fsTMP+1
    sta hs_blen+1
    rts

; hr_urlptr: A/X = hs_url + A
hr_urlptr:
    ldx hs_url+1
    clc
    adc hs_url
    bcc hu_rts
    inx
hu_rts:
    rts

; hr_dec: mosTMP/+1/+2 (24 bits) as decimal and CR LF at MOSBUF+$F0:
; A/X its address, Y its length (with the CR LF). hr_decbl: of hs_blen.
; Uses mosTMP+0-2.
hr_decbl:
    lda hs_blen
    sta mosTMP
    lda hs_blen+1
    sta mosTMP+1
    lda #0
    sta mosTMP+2
hr_dec:
    ldx #8                      ; eight digits, leading zeros dropped
hd_dig:
    lda #0                      ; mosTMP DIV 10, the remainder in A
    ldy #24
hd_div:
    asl mosTMP
    rol mosTMP+1
    rol mosTMP+2
    rol
    cmp #10
    bcc hd_lt
    sbc #10
    inc mosTMP
hd_lt:
    dey
    bne hd_div
    ora #'0'
    dex
    sta MOSBUF+$F0,x
    txa
    bne hd_dig
    ldx #0                      ; skip leading zeros (keep the last)
hd_skip:
    lda MOSBUF+$F0,x
    cmp #'0'
    bne hd_go
    inx
    cpx #7
    bcc hd_skip
hd_go:
    lda #13
    sta MOSBUF+$F8
    lda #10
    sta MOSBUF+$F9
    stx mosTMP
    lda #10
    sec
    sbc mosTMP
    tay
    txa
    clc
    adc #<[MOSBUF+$F0]
    ldx #>[MOSBUF+$F0]
    rts

; hr_headers: the *NET HEADER lines (REU RH_HDRS, RH_HLEN bytes), up to
; 200 bytes at a time through MOSBUF. Uses mosTMP (address, remaining),
; mosNUM.
hr_headers:
    ldx #<RH_HLEN
    jsr hr_rget
    sta mosTMP+2
    ldx #<[RH_HLEN+1]
    jsr hr_rget
    sta mosTMP+3
    lda #<RH_HDRS
    sta mosTMP
    lda #>RH_HDRS
    sta mosTMP+1
hh_piece:
    lda mosTMP+2
    ora mosTMP+3
    beq hh_rts
    ldy #200
    lda mosTMP+3
    bne hh_n
    lda mosTMP+2
    cmp #200
    bcs hh_n
    tay
hh_n:
    sty mosNUM                  ; this piece
    tya
    ldx #<MOSBUF
    ldy #>MOSBUF
    jsr hr_dmain                ; REU mosTMP -> MOSBUF, A bytes
    lda #<MOSBUF
    ldx #>MOSBUF
    ldy mosNUM
    jsr hr_write
    lda mosTMP                  ; on
    clc
    adc mosNUM
    sta mosTMP
    bcc hh_sub
    inc mosTMP+1
hh_sub:
    lda mosTMP+2
    sec
    sbc mosNUM
    sta mosTMP+2
    bcs hh_piece
    dec mosTMP+3
    jmp hh_piece
hh_rts:
    rts

; hr_write: send Y bytes (1-255; 0: 256) at A/X on the socket
; (NET_WRITE); raises the firmware's error
hr_write:
    sta fsPTR
    stx fsPTR+1
    sty fsLEN
    lda #0
    cpy #0
    bne hw_len
    lda #1
hw_len:
    sta fsLEN+1
    lda #TARGET_NET
    sta uciHDR
    lda #NET_WRITE
    sta uciHDR+1
    lda hs_sock
    sta uciHDR+2
    lda #3
    sta uciHLEN
    jsr uci_send
    jsr uci_finish
    bcc hw_rts
    jmp uci_error
hw_rts:
    rts

; hr_count: print "n bytes" (the body bytes received)
hr_count:
    lda hs_blen
    sta mosTMP
    lda hs_blen+1
    sta mosTMP+1
    lda hs_bptr
    sta mosTMP+2
    jsr hr_dec
    stx mosTMP+1
    sta mosTMP
    dey                         ; (without the CR LF)
    dey
    sty mosTMP+2
    ldy #0
hcn_l:
    lda (mosTMP),y
    jsr OSWRCH
    iny
    cpy mosTMP+2
    bne hcn_l
    jsr s6_text
    dta ' bytes', 13, 0
    rts

; ----------------------------------------------------------------------------
; hr_receive
;   Summary: read the reply until the socket closes, Content-Length is
;            reached, the REU buffer is full (16K), or nothing has come
;            for 30 s ("Timeout"); ESCAPE stops it.
;   Function: each chunk: the status line and headers byte by byte
;            (hr_hbyte), then the rest of the chunk to the sink. A status
;            of 400 or more ends it at the empty line.
;   Uses:    A, X, Y, fs*, MOSBUF, HS.
hr_receive:
    lda #0
    sta hs_phase
    sta hs_col
    sta hs_clm
    sta hs_have
    sta hs_idle
    sta hs_idle+1
hv_read:
    bit ESCFLG
    bpl hv_noesc
    jsr hr_close
    jmp uci_chkesc
hv_noesc:
    lda #TARGET_NET             ; NET_READ: up to HR_CHUNK bytes
    sta uciHDR
    lda #NET_READ
    sta uciHDR+1
    lda hs_sock
    sta uciHDR+2
    lda #HR_CHUNK
    sta uciHDR+3
    lda #0
    sta uciHDR+4
    lda #5
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    lda #<MOSBUF                ; count (2 bytes), then the data
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #0
    sta fsLEN
    lda #1
    sta fsLEN+1
    jsr uci_read_to
    ldx #32                     ; (its status behind the status line)
    jsr uci_finish_x
    lda errbuf+33               ; "00,OK" (or none): data; "02,NO DATA":
    beq hv_data                 ; none yet; anything else: closed
    cmp #'0'
    bne hv_done
    lda errbuf+34
    cmp #'2'
    beq hv_none
    cmp #'0'
    bne hv_done
hv_data:
    lda fsCNT+1                 ; anything beyond the count?
    bne hv_some
    lda fsCNT
    cmp #3
    bcc hv_none
hv_some:
    lda MOSBUF
    beq hv_none
    sta hs_n
    lda #0
    sta hs_idle
    sta hs_idle+1
    sta hs_i
hv_byte:
    lda hs_phase                ; status line and headers
    cmp #2
    bcs hv_body
    ldx hs_i
    cpx hs_n
    bcc hv_next
    jmp hv_read
hv_next:
    lda MOSBUF+2,x
    inc hs_i
    jsr hr_hbyte
    bcc hv_byte
hv_done:
    rts
hv_body:
    jsr hr_body                 ; the rest of the chunk; C = 1: all came
    bcs hv_done
    jmp hv_read
hv_none:
    inc hs_idle                 ; nothing: 30 s at most
    bne hv_idle
    inc hs_idle+1
hv_idle:
    lda hs_idle
    cmp #<HR_IDLEMAX
    lda hs_idle+1
    sbc #>HR_IDLEMAX
    bcs hv_tout
    jmp hv_read
hv_tout:
    jsr hr_close
    brk
    dta 223, 'Timeout', 0

; ----------------------------------------------------------------------------
; hr_hbyte
;   Summary: one byte of the status line or the headers (A).
;   Function: the status line goes to errbuf+1 (up to 31 characters) as
;            "HTTP" and what follows the version ("HTTP 404 Not Found");
;            at its end the code is taken from it and kept in the REU.
;            Header lines: "Content-Length:" (any case) gives hs_clen. The
;            empty line starts the body (phase 2); C = 1 there when the
;            status is 400 or more (nothing more is read).
;   Uses:    A, X, Y.
hr_hbyte:
    cmp #13
    beq hb_ok                   ; (CR: ignored)
    cmp #10
    beq hb_eol
    ldx hs_phase
    bne hb_hdr
    ldx hs_col                  ; status line: "HTTP/1.x " -> "HTTP "
    cpx #4
    bcc hb_st
    ldy hs_clm                  ; (hs_clm: past the version's space)
    bne hb_st
    cmp #' '
    bne hb_col
    inc hs_clm
hb_st:
    cpx #31
    bcs hb_col
    sta errbuf+1,x
    inc hs_col
    lda #0
    sta errbuf+2,x
hb_ok:
    clc
    rts
hb_col:
    clc
    rts
hb_hdr:
    ldx hs_col                  ; a header line: "Content-Length:"?
    cpx #15
    bcs hb_val
    cpx #0
    bne hb_cmp
    ldy #1
    sty hs_clm
hb_cmp:
    ora #$20                    ; (lower case; ':' and '-' stay)
    cmp hb_cl,x
    beq hb_next
    ldy #0
    sty hs_clm
hb_next:
    inc hs_col
    clc
    rts
hb_val:
    ldy hs_clm                  ; its digits (spaces skipped)
    beq hb_next2
    sec
    sbc #'0'
    cmp #10
    bcs hb_next2
    pha                         ; clen = clen * 10 + digit (24 bits)
    lda #1
    sta hs_have
    jsr hr_x10
    pla
    clc
    adc hs_clen
    sta hs_clen
    bcc hb_next2
    inc hs_clen+1
    bne hb_next2
    inc hs_clen+2
hb_next2:
    lda hs_col
    cmp #255
    bcs hb_ok
    inc hs_col
    clc
    rts
hb_eol:
    lda hs_phase
    bne hb_hend
    jsr hr_status               ; the status line ends
    lda #1
    sta hs_phase
    lda #0
    sta hs_col
    sta hs_clm
    sta hs_clen
    sta hs_clen+1
    sta hs_clen+2
    clc
    rts
hb_hend:
    lda hs_col                  ; an empty line: the body
    beq hb_body
    lda #0
    sta hs_col
    clc
    rts
hb_body:
    lda #2
    sta hs_phase
    jmp hr_isbad                ; 400 or more: C = 1, stop here
hb_cl       dta 'content-length:'

; hr_x10: hs_clen = hs_clen * 10 (24 bits). Uses A, mosTMP.
hr_x10:
    lda hs_clen
    sta mosTMP
    lda hs_clen+1
    sta mosTMP+1
    lda hs_clen+2
    sta mosTMP+2
    jsr hx_2                    ; * 2
    jsr hx_2                    ; * 4
    lda hs_clen                 ; * 5
    clc
    adc mosTMP
    sta hs_clen
    lda hs_clen+1
    adc mosTMP+1
    sta hs_clen+1
    lda hs_clen+2
    adc mosTMP+2
    sta hs_clen+2
hx_2:
    asl hs_clen
    rol hs_clen+1
    rol hs_clen+2
    rts

; hr_status: the status line in errbuf+1: hs_code from its three digits
; after "HTTP " (none: 0); the code and the line to the REU
hr_status:
    lda #0
    sta hs_code
    sta hs_code+1
    ldx #0                      ; the first space
hst_sp:
    lda errbuf+1,x
    beq hst_put
    inx
    cmp #' '
    bne hst_sp
    ldy #3
hst_dig:
    lda errbuf+1,x
    sec
    sbc #'0'
    cmp #10
    bcs hst_put
    pha                         ; code = code * 10 + digit
    lda hs_code
    asl
    sta mosTMP
    lda hs_code+1
    rol
    sta mosTMP+1
    asl hs_code
    rol hs_code+1
    asl hs_code
    rol hs_code+1
    asl hs_code
    rol hs_code+1
    lda hs_code
    clc
    adc mosTMP
    sta hs_code
    lda hs_code+1
    adc mosTMP+1
    sta hs_code+1
    pla
    clc
    adc hs_code
    sta hs_code
    bcc hst_nx
    inc hs_code+1
hst_nx:
    inx
    dey
    bne hst_dig
hst_put:
    jsr hr_putcode
    lda #<RH_LINE               ; the line (32 bytes) to the REU
    sta mosTMP
    lda #>RH_LINE
    sta mosTMP+1
    ldx #<[errbuf+1]
    ldy #>[errbuf+1]
    lda #32
    jmp hr_dmaout

; hr_putcode: hs_code to the REU (RH_CODE)
hr_putcode:
    lda hs_code
    ldx #<RH_CODE
    jsr hr_rput
    lda hs_code+1
    ldx #<[RH_CODE+1]
    jmp hr_rput

; hr_raise: error 223 with the last status line (from the REU: the
; commands since then overwrote errbuf)
hr_raise:
    lda #<RH_LINE
    sta mosTMP
    lda #>RH_LINE
    sta mosTMP+1
    ldx #<[errbuf+1]
    ldy #>[errbuf+1]
    lda #32
    jsr hr_dmain
    lda #0
    sta errbuf+33
    lda #223
    sta errbuf
    jmp raise_errbuf

; ----------------------------------------------------------------------------
; hr_body
;   Summary: the body bytes of this chunk (MOSBUF+2+hs_i .. hs_n) to the
;            sink, at most hs_clen when it is known.
;   Output:  C = 1 when all came (Content-Length reached, REU buffer
;            full); C = 0: read on.
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF.
hr_body:
    lda hs_n                    ; n = the rest of the chunk
    sec
    sbc hs_i
    sta mosNUM
    lda hs_have                 ; at most what is still to come
    beq hy_n
    lda hs_clen+1
    ora hs_clen+2
    bne hy_sub
    lda hs_clen
    cmp mosNUM
    bcs hy_sub
    sta mosNUM
hy_sub:
    lda hs_clen
    sec
    sbc mosNUM
    sta hs_clen
    bcs hy_n
    lda hs_clen+1
    bne hy_dec
    dec hs_clen+2
hy_dec:
    dec hs_clen+1
hy_n:
    lda mosNUM
    bne hy_some
    jmp hy_end
hy_some:
    clc                         ; counted (hr_count prints it)
    adc hs_blen
    sta hs_blen
    bcc hy_cnt
    inc hs_blen+1
    bne hy_cnt
    inc hs_bptr
hy_cnt:
    lda hs_sink
    beq hy_reu
    cmp #HK_FILE
    beq hy_file
    ldx hs_i                    ; the screen: CR skipped, LF a new line,
hy_scr:                         ; other control codes skipped
    lda MOSBUF+2,x
    cmp #10
    beq hy_nl
    cmp #' '
    bcc hy_sk
    jsr OSWRCH
    jmp hy_sk
hy_nl:
    jsr OSNEWL
hy_sk:
    inx
    dec mosNUM
    bne hy_scr
    jmp hy_end
hy_file:
    lda hs_fopen                ; a file: opened at the first bytes
    bne hy_fw
    jsr hr_outopen
hy_fw:
    lda #<[REU_NETBUF]          ; the bytes -> REU, then written
    sta mosTMP
    lda #>[REU_NETBUF]
    sta mosTMP+1
    jsr hr_chunkout
    lda #REU_FONT_BANK
    ldy #>REU_NETBUF
    ldx mosNUM
    farcall rx_wtail, BANK_FS
    jmp hy_end
hy_reu:
    lda nt_len+1                ; room in the buffer? (none: all)
    cmp #NETBUF_PAGES
    bcs hy_full
    lda nt_len                  ; REU_NETBUF + nt_len (the 16K buffer:
    sta mosTMP                  ; a chunk may pass its end by < 256,
    lda nt_len+1                ; into the line editor's history area:
    clc                         ; cut to fit)
    adc #>REU_NETBUF
    sta mosTMP+1
    lda nt_len                  ; room = 16K - nt_len
    eor #$FF
    clc
    adc #1
    tax
    lda #NETBUF_PAGES
    sbc nt_len+1
    bne hy_fits                 ; a page or more: the chunk fits
    cpx mosNUM
    bcs hy_fits
    stx mosNUM
hy_fits:
    jsr hr_chunkout
    lda nt_len
    clc
    adc mosNUM
    sta nt_len
    bcc hy_end
    inc nt_len+1
hy_end:
    lda hs_have                 ; all that was announced?
    beq hy_more
    lda hs_clen
    ora hs_clen+1
    ora hs_clen+2
    beq hy_all
hy_more:
    clc
    rts
hy_full:
hy_all:
    sec
    rts

; hr_chunkout: mosNUM bytes from MOSBUF+2+hs_i to the REU (bank 0) at
; mosTMP/+1
hr_chunkout:
    lda #<[MOSBUF+2]
    clc
    adc hs_i
    tax
    ldy #>[MOSBUF+2]
    lda mosNUM
    jmp hr_dmaout

; hr_outopen: create the output file (hs_out/hs_olen)
hr_outopen:
    lda hs_out
    sta fsPTR
    lda hs_out+1
    sta fsPTR+1
    lda hs_olen
    sta fsLEN
    lda #0
    sta fsLEN+1
    farcall rx_create, BANK_FS
    lda #1
    sta hs_fopen
    rts

; ----------------------------------------------------------------------------
; REU bank 0 transfers (interrupts off while the REU is set up: the sound
; interrupt uses it too)
; hr_dmaout / hr_dmain: A bytes (1-255; 0: 256) between C64 X/Y (low/
; high) and REU bank 0 at mosTMP/+1 (mosTMP+2/+3 kept). hr_rget /
; hr_rput: the byte at REU page >REU_HTTP, low byte X -> A, or A ->
; there (Y kept).
hr_dmaout:
    sec                         ; (C: the direction)
    bcs hd_go2
hr_dmain:
    clc
hd_go2:
    php
    sei
    stx REU_C64
    sty REU_C64+1
    sta REU_LEN
    ldx #0                      ; (0: 256; ora keeps C)
    ora #0
    bne hd_l
    inx
hd_l:
    stx REU_LEN+1
    lda mosTMP
    sta REU_ADDR
    lda mosTMP+1
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #0
    sta REU_CTRL
    lda #REU_TO_C64
    bcc hd_cmd
    lda #REU_TO_REU
hd_cmd:
    sta REU_CMD
    plp
    rts
hr_rget:
    lda #REU_TO_C64
    bne hr_r1
hr_rput:
    sta nc_byte
    lda #REU_TO_REU
hr_r1:
    php
    sei
    pha
    stx REU_ADDR
    lda #>REU_HTTP
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<nc_byte
    sta REU_C64
    lda #>nc_byte
    sta REU_C64+1
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    pla
    sta REU_CMD
    plp
    lda nc_byte
    rts

; ----------------------------------------------------------------------------
; Texts. Verbs: hv_tab = offset in hv_text, hv_len = length with the space
HV_GET      = 0
HV_POST     = 1
HV_PUT      = 2
HV_DELETE   = 3
hv_text     dta 'GET POST PUT DELETE '
hv_tab      dta 0, 4, 9, 13
hv_len      dta 4, 5, 4, 7
hq_slash    dta '/'
hq_v10      dta ' HTTP/1.0', 13, 10, 'Host: '
hq_v10e:
hq_close    dta 13, 10, 'Connection: close', 13, 10
hq_closee:
hq_clen     dta 'Content-Length: '
hq_clene:
hq_crlf     dta 13, 10
