; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- network channels (bank 7, inside .local net)
;
; docs/DESIGN_NETWORK.md: OPENIN "http://..." (the reply, read as a file),
; OPENUP "TCP:host:port" and "UDP:host:port" (sockets). They use the two
; filing system channels (fs.s), marked by bit 1 of ch_open; fs.s hands
; them over here (nc_*).
;
; HTTP: the body is fetched at the open into the REU buffer (http_req,
;       nethttp.s: the MOS's own HTTP/1.0 client);
;       PTR# and EXT# as for a file; rd_chent = $FF.
; Sockets: rd_chent = the firmware's socket number; per channel a 256-byte
;       receive buffer and a 256-byte send buffer in the REU (bank 0,
;       REU_NETRX/REU_NETTX + channel * 256); their counters in the
;       channel's EXT# bytes (ch_ext+0 receive position, +1 receive fill,
;       +2 flags, +3 send fill); PTR# counts the bytes read.
;
; ----------------------------------------------------------------------------

NET_TCPOPEN = $07
NET_UDPOPEN = $08
NET_CLOSE   = $09
NET_READ    = $10
NET_WRITE   = $11
REU_NETRX   = $3100             ; 2 x 256: receive buffers (REU bank 0)
REU_NETTX   = $3300             ; 2 x 256: send buffers
NCF_CLOSED  = $01               ; ch_ext+2: the other side has closed
NCF_UDP     = $04

nc_port     = fsTMP             ; 2 (open)
nc_ch       = fsSY              ; the channel index (not fsTMP+2: that
                                ; is http_fetch's header handle, nt_hdr)
nc_byte     = fsTMP+3

; ----------------------------------------------------------------------------
; nc_isnet
;   Summary: is the name at fsPTR a network one?
;   Output:  C = 1 and A = 1 TCP, 2 UDP, 3 HTTP; C = 0 otherwise.
;   Uses:    A, X, Y.
nc_isnet:
    ldx #0                      ; nc_names: "TCP:", "UDP:", "HTTP://"
ni_try:
    ldy #0
ni_ch:
    lda nc_names,x
    beq ni_yes                  ; the whole prefix matched
    sta nc_byte
    lda (fsPTR),y
    jsr s6_up
    cmp nc_byte
    bne ni_next
    inx
    iny
    bne ni_ch
ni_next:
    lda nc_names,x              ; to the next prefix
    beq ni_skip
    inx
    bne ni_next
ni_skip:
    inx
    inx                         ; (past the 0 and the kind)
    lda nc_names,x
    bne ni_try
    clc
    rts
ni_yes:
    lda nc_names+1,x            ; the kind
    sec
    rts
nc_names:
    dta 'TCP:', 0, 1, 'UDP:', 0, 2, 'HTTP://', 0, 3, 0

; ----------------------------------------------------------------------------
; nc_open
;   Summary: open the network name at fsPTR on channel index X (free) for
;            OSFIND mode A (&40, &80, &C0).
;   Output:  A = the channel number (&11, &12), or 0 if it could not be
;            opened (OPENOUT raises the error instead, as for files).
;   Uses:    A, X, Y, fs*, MOSBUF.
nc_open:
    pha
    jsr uci_need                ; ("No Ultimate" in VICE, as *NET)
    pla
    stx nc_ch
    and #$C0
    sta fsMODE
    jsr nc_isnet
    cmp #3
    beq no_http
    sta nc_byte                 ; 1 TCP, 2 UDP
    jsr no_parse                ; MOSBUF = host, 0; nc_port
    lda #TARGET_NET
    sta uciHDR
    ldx #NET_TCPOPEN
    lda nc_byte
    cmp #2
    bne no_tcp
    ldx #NET_UDPOPEN
no_tcp:
    stx uciHDR+1
    lda nc_port
    sta uciHDR+2
    lda nc_port+1
    sta uciHDR+3
    lda #4
    sta uciHLEN
    jsr uci_send                ; (payload: host, 0)
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #1
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_read_to
    jsr uci_finish
    bcc no_sock
    jmp no_fail
no_sock:
    ldx nc_ch
    lda MOSBUF                  ; the socket
    sta rd_chent,x
    txa
    asl
    asl
    tay
    lda #0
    sta ch_ext,y
    sta ch_ext+1,y
    sta ch_ext+3,y
    lda nc_byte                 ; flags: UDP
    cmp #2
    bne no_flags
    lda #NCF_UDP
    .byte $2C                   ; (BIT abs: skips the LDA)
no_flags:
    lda #0
    sta ch_ext+2,y
    jmp no_done
no_http:
    jsr s6_hasreu
    beq no_fail
    jsr no_measure              ; fsLEN = the URL's length
    lda fsPTR                   ; a GET into the REU buffer (nethttp.s;
    sta hs_url                  ; raises on errors, also 400 and more)
    lda fsPTR+1
    sta hs_url+1
    lda fsLEN
    sta hs_ulen
    lda #HV_GET
    sta hs_verb
    lda #0
    sta hs_bkind
    lda #HK_REU
    sta hs_sink
    jsr http_req
    ldx nc_ch
    lda #$FF                    ; HTTP: no socket
    sta rd_chent,x
    txa
    asl
    asl
    tay
    lda nt_len                  ; EXT# = the reply's length
    sta ch_ext,y
    lda nt_len+1
    sta ch_ext+1,y
    lda #0
    sta ch_ext+2,y
    sta ch_ext+3,y
no_done:
    ldx nc_ch
    txa
    asl
    asl
    tay
    lda #0                      ; PTR# 0
    sta ch_ptr,y
    sta ch_ptr+1,y
    sta ch_ptr+2,y
    sta ch_ptr+3,y
    lda fsMODE
    ora #2                      ; (bit 1: a network channel)
    sta ch_open,x
    txa
    clc
    adc #CHAN_BASE
    rts
no_fail:
    lda fsMODE                  ; OPENOUT raises, the others give 0
    cmp #$80
    bne no_zero
    jmp uci_error
no_zero:
    lda #0
    rts

; no_measure: fsLEN = length of the name at fsPTR (to CR, space or quote)
no_measure:
    ldy #0
nm_l:
    lda (fsPTR),y
    cmp #' '+1
    bcc nm_end
    cmp #'"'
    beq nm_end
    iny
    bne nm_l
nm_end:
    sty fsLEN
    lda #0
    sta fsLEN+1
    rts

; no_parse: "TCP:host:port": MOSBUF = host and a 0 (the payload: fsPTR,
; fsLEN), nc_port = port (decimal)
no_parse:
    ldy #4                      ; after "TCP:" / "UDP:"
    ldx #0
np_host:
    lda (fsPTR),y
    cmp #':'
    beq np_port
    cmp #' '+1
    bcc np_bad
    sta MOSBUF,x
    inx
    iny
    cpx #200
    bcc np_host
np_bad:
    brk
    dta 204, 'Bad name (TCP:host:port)', 0
np_port:
    lda #0
    sta MOSBUF,x
    inx
    stx fsLEN
    lda #0
    sta fsLEN+1
    sta nc_port
    sta nc_port+1
    iny
np_dig:
    lda (fsPTR),y
    sec
    sbc #'0'
    cmp #10
    bcs np_end
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
    bcc np_next
    inc nc_port+1
np_next:
    iny
    bne np_dig
np_end:
    lda nc_port
    ora nc_port+1
    beq np_bad
    lda #<MOSBUF
    sta fsPTR
    lda #>MOSBUF
    sta fsPTR+1
    rts

; ----------------------------------------------------------------------------
; nc_close: channel index X: send what is waiting, close the socket
nc_close:
    stx nc_ch
    lda rd_chent,x
    cmp #$FF
    beq ncc_rts                 ; (HTTP: nothing to close)
    jsr nc_flush
    ldx nc_ch
    lda #TARGET_NET
    sta uciHDR
    lda #NET_CLOSE
    sta uciHDR+1
    lda rd_chent,x
    sta uciHDR+2
    lda #3
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jsr uci_finish              ; (errors ignored: it may be closed)
ncc_rts:
    rts

; ----------------------------------------------------------------------------
; nc_bget
;   Summary: BGET# on network channel index X.
;   Output:  C = 0: A = the byte; C = 1: the end (A = $FE).
;   Function: HTTP: the byte at PTR# from the REU buffer. Socket: from the
;            receive buffer, refilled from the socket when empty (waits
;            until data comes or the other side closes; ESCAPE stops).
;   Uses:    A, X, Y, fs*, MOSBUF.
nc_bget:
    stx nc_ch
    lda rd_chent,x
    cmp #$FF
    bne nb_sock
    txa                         ; HTTP: PTR# < EXT#?
    asl
    asl
    tay
    lda ch_ptr,y
    cmp ch_ext,y
    lda ch_ptr+1,y
    sbc ch_ext+1,y
    bcc nb_http
    jmp nb_end
nb_http:
    php                         ; (interrupts off while the REU is set up:
    sei                         ; the sound interrupt uses it too)
    lda ch_ptr,y                ; the byte at REU_NETBUF + PTR#
    sta REU_ADDR
    lda ch_ptr+1,y
    clc
    adc #>REU_NETBUF
    sta REU_ADDR+1
    jsr nc_get1
    plp
    jmp nb_got
nb_sock:
    jsr nc_flush                ; (what was written goes first)
nb_again:
    ldx nc_ch
    txa
    asl
    asl
    tay
    lda ch_ext,y                ; position < fill?
    cmp ch_ext+1,y
    bcc nb_buf
    lda ch_ext+2,y
    and #NCF_CLOSED
    bne nb_end
    jsr nc_fill                 ; read the socket
    bit ESCFLG
    bmi nb_end
    jmp nb_again
nb_buf:
    php
    sei
    lda ch_ext,y                ; the byte at REU_NETRX + ch * 256 + pos
    sta REU_ADDR
    lda nc_ch
    clc
    adc #>REU_NETRX
    sta REU_ADDR+1
    jsr nc_get1
    plp
    ldx nc_ch
    txa
    asl
    asl
    tay
    lda ch_ext,y
    clc
    adc #1
    sta ch_ext,y
nb_got:
    ldx nc_ch                   ; PTR# + 1
    txa
    asl
    asl
    tay
    lda ch_ptr,y
    clc
    adc #1
    sta ch_ptr,y
    bcc nb_ret
    lda ch_ptr+1,y
    adc #0
    sta ch_ptr+1,y
    bcc nb_ret
    lda ch_ptr+2,y
    adc #0
    sta ch_ptr+2,y
nb_ret:
    lda nc_byte
    clc
    rts
nb_end:
    lda #$FE
    sec
    rts

; nc_get1: nc_byte = one byte from REU bank 0 at REU_ADDR (set)
nc_get1:
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
    lda #REU_TO_C64
    sta REU_CMD
    rts

; nc_fill: one read of socket nc_ch (waits at most 40 ms in the firmware)
; into its receive buffer: fill = bytes read, position 0; the other side
; closed: the closed flag
nc_fill:
    ldx nc_ch
    lda #TARGET_NET
    sta uciHDR
    lda #NET_READ
    sta uciHDR+1
    lda rd_chent,x
    sta uciHDR+2
    lda #254                    ; at most 254: the count (2) and the data
    sta uciHDR+3                ; fill MOSBUF exactly (255 wrote &0900)
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
    jsr uci_finish
    ldx nc_ch
    txa
    asl
    asl
    tay
    lda errbuf+1                ; "00,OK" (or none): data; "02,NO DATA":
    beq nf_data                 ; none yet; anything else: closed
    cmp #'0'
    bne nf_closed
    lda errbuf+2
    cmp #'2'
    beq nf_none
    cmp #'0'
    bne nf_closed
nf_data:
    lda fsCNT+1                 ; anything beyond the 2-byte count?
    bne nf_some
    lda fsCNT
    cmp #3
    bcc nf_none
nf_some:
    lda MOSBUF                  ; the count (at most 255: asked for 255)
    beq nf_none
    sta ch_ext+1,y              ; fill
    lda #0
    sta ch_ext,y                ; position
    php
    sei
    lda #<REU_NETRX             ; MOSBUF+2 -> the receive buffer
    sta REU_ADDR
    lda nc_ch
    clc
    adc #>REU_NETRX
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<[MOSBUF+2]
    sta REU_C64
    lda #>[MOSBUF+2]
    sta REU_C64+1
    lda ch_ext+1,y
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    plp
nf_none:
    rts
nf_closed:
    lda ch_ext+2,y
    ora #NCF_CLOSED
    sta ch_ext+2,y
    rts

; ----------------------------------------------------------------------------
; nc_bput
;   Summary: BPUT# A on network channel index X: into the send buffer;
;            sent when full, at a line end (TCP), before a read, at
;            CLOSE#.
;   Uses:    A, X, Y, fs*, MOSBUF.
nc_bput:
    stx nc_ch
    sta nc_byte
    lda rd_chent,x
    cmp #$FF
    beq nbp_rts                 ; (HTTP: read only)
    txa
    asl
    asl
    tay
    php
    sei
    lda ch_ext+3,y              ; the byte at REU_NETTX + ch * 256 + fill
    sta REU_ADDR
    lda nc_ch
    clc
    adc #>REU_NETTX
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
    lda #REU_TO_REU
    sta REU_CMD
    plp
    lda ch_ext+3,y
    clc
    adc #1
    sta ch_ext+3,y
    cmp #255                    ; full
    bcs nc_flush
    lda ch_ext+2,y              ; TCP: a line end sends the line
    and #NCF_UDP
    bne nbp_rts
    lda nc_byte
    cmp #13
    beq nc_flush
    cmp #10
    beq nc_flush
nbp_rts:
    rts

; nc_flush: send the send buffer of channel nc_ch (if any)
nc_flush:
    ldx nc_ch
    txa
    asl
    asl
    tay
    lda ch_ext+3,y
    beq nfl_rts
    sta fsLEN                   ; REU -> MOSBUF, then a write command
    php
    sei
    lda #0
    sta ch_ext+3,y
    sta fsLEN+1
    sta REU_ADDR
    sta REU_LEN+1
    sta REU_CTRL
    lda fsLEN
    sta REU_LEN
    lda nc_ch
    clc
    adc #>REU_NETTX
    sta REU_ADDR+1
    lda #REU_FONT_BANK
    sta REU_BANK
    lda #<MOSBUF
    sta REU_C64
    sta fsPTR
    lda #>MOSBUF
    sta REU_C64+1
    sta fsPTR+1
    lda #REU_TO_C64
    sta REU_CMD
    plp
    lda #TARGET_NET
    sta uciHDR
    lda #NET_WRITE
    sta uciHDR+1
    lda rd_chent,x
    sta uciHDR+2
    lda #3
    sta uciHLEN
    jsr uci_send
    jsr uci_finish              ; (a closed socket shows at the next read)
nfl_rts:
    rts

; ----------------------------------------------------------------------------
; nc_eof: channel index X: C = 1 at the end (HTTP: PTR# >= EXT#; socket:
; nothing waiting, nothing comes within 40 ms, and the other side closed)
nc_eof:
    stx nc_ch
    lda rd_chent,x
    cmp #$FF
    bne ne_sock
    txa
    asl
    asl
    tay
    lda ch_ptr,y
    cmp ch_ext,y
    lda ch_ptr+1,y
    sbc ch_ext+1,y
    rts
ne_sock:
    jsr nc_waiting              ; A = bytes waiting (after a read)
    bne ne_no
    ldx nc_ch
    txa
    asl
    asl
    tay
    lda ch_ext+2,y
    and #NCF_CLOSED
    beq ne_no
    sec
    rts
ne_no:
    clc
    rts

; nc_ext: channel index X: fsTMP+0..+3 = EXT# (HTTP: the length; socket:
; the bytes waiting)
nc_ext:
    stx nc_ch
    lda rd_chent,x
    cmp #$FF
    bne nx_sock
    txa
    asl
    asl
    tay
    lda ch_ext,y
    sta fsTMP
    lda ch_ext+1,y
    sta fsTMP+1
    lda #0
    sta fsTMP+2
    sta fsTMP+3
    rts
nx_sock:
    jsr nc_waiting
    sta fsTMP
    lda #0
    sta fsTMP+1
    sta fsTMP+2
    sta fsTMP+3
    rts

; nc_waiting: A = bytes waiting in the receive buffer of nc_ch, read from
; the socket if it is empty (Z set when none)
nc_waiting:
    jsr nc_flush
    jsr nw_count
    bne nw_rts
    ldx nc_ch
    txa
    asl
    asl
    tay
    lda ch_ext+2,y
    and #NCF_CLOSED
    bne nw_zero
    jsr nc_fill
nw_count:
    ldx nc_ch
    txa
    asl
    asl
    tay
    lda ch_ext+1,y
    sec
    sbc ch_ext,y
nw_rts:
    rts
nw_zero:
    lda #0
    rts

; nc_setptr: PTR#c = n on network channel index X (value at zero page
; fsSX): HTTP: as a file (within the reply); socket: PTR#c=0 sends what
; is waiting (a UDP datagram), other values are ignored
nc_setptr:
    stx nc_ch
    lda rd_chent,x
    cmp #$FF
    beq nsp_http
    jmp nc_flush
nsp_http:
    txa
    asl
    asl
    tay
    ldx fsSX
    lda $00,x
    sta ch_ptr,y
    lda $01,x
    sta ch_ptr+1,y
    lda #0
    sta ch_ptr+2,y
    sta ch_ptr+3,y
    rts
