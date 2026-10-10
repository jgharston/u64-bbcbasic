; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- Ultimate Command Interface (UCI) driver, bank 2
;
; 6502 port of the protocol layer of ultimate-uci-oscar64
; (github.com/xahmol/ultimate-uci-oscar64, include/ultimate_common_lib.c:
; uii_detect, uii_enable, uii_sendcommand_data, uii_readdata_to,
; uii_readstatus, uii_accept, uii_abort), itself based on the Ultimate II
; DOS library by Scott Hutter and Francesco Sblendorio, with the handshake
; fixes by Christian Gleissner. Adapted: hand-written assembler, no
; buffers (commands stream from memory, replies go straight to their
; destination), every wait loop can be left with ESCAPE, and the register
; base is a build symbol (EasyFlash makes the firmware move UCI to $DE1C).
;
; Registers (UCI_BASE): +0 control (write) / status (read), +1 command
; data (write) / identification $C9 (read), +2 response data, +3 status
; data. Status bits: 0 command busy, 1 data acknowledge pending, 2 abort
; pending, 3 error, 4-5 state (00 idle, 01 busy, 10 last data, 11 more
; data), 6 status data available, 7 response data available.
;
; ----------------------------------------------------------------------------

UCI_CTRL    = UCI_BASE          ; write
UCI_STAT    = UCI_BASE          ; read
UCI_CMDDATA = UCI_BASE+1        ; write
UCI_ID      = UCI_BASE+1        ; read: $C9
UCI_RESP    = UCI_BASE+2        ; read
UCI_SDAT    = UCI_BASE+3        ; read

TARGET_DOS1 = $01
TARGET_DOS2 = $02
TARGET_CTRL = $04

; ----------------------------------------------------------------------------
; uci_init
;   Summary: find the command interface, switching it on if needed.
;   Function: if the identification register does not read $C9, send the
;            firmware 3.15+ unlock ($AB to $D038, $CD to $D036; harmless
;            elsewhere) and wait up to ~0.5 s (25 frames). Only unlocks
;            when the interface is not mapped yet (the unlock re-enables it
;            and leaves an abort pending). Ends with an abort, as
;            uii_detect does.
;   Input:   none.
;   Output:  uci_ok = 1 if found, else 0.
;   Uses:    A, X.

uci_init:
    lda #0
    sta uci_ok
    lda UCI_ID
    cmp #$C9
    beq ui_found
    lda #$AB
    sta $D038
    lda #$CD
    sta $D036
    ldx #25
ui_wait:
    lda UCI_ID
    cmp #$C9
    beq ui_found
    jsr wait_frame
    dex
    bne ui_wait
    rts
ui_found:
    lda #$04                    ; abort: start from a clean state
    sta UCI_CTRL
    lda #1
    sta uci_ok
    rts

; wait_frame
;   Summary: wait for the next video frame (raster line 251), real time
;            at any CPU speed.
;   Input: none.  Output: none.  Uses: A.
wait_frame:
    lda $D012
    cmp #251
    beq wait_frame
wf_wait:
    lda $D012
    cmp #251
    bne wf_wait
    rts

; ----------------------------------------------------------------------------
; uci_need
;   Summary: raise "No Ultimate" unless the command interface was found.
;   Input:   uci_ok.  Output: returns if present.  Uses: A.

uci_need:
    lda uci_ok
    beq un_none
    rts
un_none:
    brk
    dta 199, 'No Ultimate command interface', 0

; ----------------------------------------------------------------------------
; uci_chkesc
;   Summary: leave a UCI wait loop on ESCAPE.
;   Function: if ESCAPE is pending, aborts the command (control bit 2)
;            and raises the BBC "Escape" error (17). BASIC acknowledges
;            the escape itself.
;   Input:   ESCFLG.  Output: returns if no ESCAPE.  Uses: A.

uci_chkesc:
    bit ESCFLG
    bmi uce_abort
    rts
uce_abort:
    lda #$04
    sta UCI_CTRL
    brk
    dta 17, 'Escape', 0

; ----------------------------------------------------------------------------
; uci_send
;   Summary: send one command: header, then an optional payload.
;   Function: as uii_sendcommand_data: waits (bounded) for a pending abort
;            to finish, then for the idle state (releasing a stale reply
;            left from an earlier command), writes the bytes, pushes, and
;            on the error bit clears it and sends again. Afterwards waits
;            until the firmware has taken the command and has answered or
;            finished. All waits end on ESCAPE.
;   Input:   uciHDR = header (byte 0 = target), uciHLEN = header length
;            (1-8); fsPTR/fsLEN = payload (fsLEN = 0: none).
;   Output:  command accepted; the reply (if any) is ready to read;
;            fsPTR advanced past the payload.
;   Uses:    A, X, Y, fsCNT.

uci_send:
    ldx #0                      ; let a pending abort finish: bounded
    ldy #0
us_abort:
    lda UCI_STAT
    and #$04
    beq us_idle
    dex
    bne us_abort
    dey
    bne us_abort
us_idle:
    lda UCI_STAT
    and #$30
    beq us_write
    lda UCI_STAT
    and #$20
    beq us_noreply
    lda #$02                    ; stale reply: acknowledge it away
    sta UCI_CTRL
us_noreply:
    jsr uci_chkesc
    jmp us_idle
us_write:
    ldx #0
us_hdr:
    lda uciHDR,x
    sta UCI_CMDDATA
    inx
    cpx uciHLEN
    bne us_hdr
    lda fsLEN                   ; payload: fsLEN bytes from (fsPTR);
    sta fsCNT                   ; fsPTR is advanced past it
    lda fsLEN+1
    sta fsCNT+1
    ldy #0
us_data:
    lda fsCNT
    ora fsCNT+1
    beq us_push
    lda (fsPTR),y
    sta UCI_CMDDATA
    inc fsPTR
    bne us_dec
    inc fsPTR+1
us_dec:
    lda fsCNT
    bne us_declo
    dec fsCNT+1
us_declo:
    dec fsCNT
    jmp us_data
us_push:
    lda #$01                    ; push command
    sta UCI_CTRL
    lda UCI_STAT
    and #$08
    beq us_taken
    lda #$08                    ; error: clear and send again
    sta UCI_CTRL
    jmp us_idle
us_taken:
    lda UCI_STAT                ; wait while busy or still "command busy"
    lsr
    bcs us_busy
    and #$18
    cmp #$08
    bne us_done
us_busy:
    jsr uci_chkesc
    jmp us_taken
us_done:
    rts

; ----------------------------------------------------------------------------
; uci_read_to
;   Summary: read the reply into memory, packet after packet.
;   Function: stores reply bytes at (fsADDR) while data is available and
;            fewer than fsLEN bytes have been stored. If more packets are
;            announced ("more data") and room is left, acknowledges the
;            packet and goes on. Bytes beyond fsLEN are left for
;            uci_finish to discard.
;   Input:   fsADDR = destination, fsLEN = maximum number of bytes.
;   Output:  fsCNT = number of bytes stored; fsADDR advanced.
;   Uses:    A, Y.

uci_read_to:
    lda #0
    sta fsCNT
    sta fsCNT+1
urt_loop:
    lda fsCNT                   ; room left?
    cmp fsLEN
    lda fsCNT+1
    sbc fsLEN+1
    bcs urt_done
    lda UCI_STAT
    bpl urt_nodata
    lda UCI_RESP
    ldy #0
    sta (fsADDR),y
    inc fsADDR
    bne urt_cnt
    inc fsADDR+1
urt_cnt:
    inc fsCNT
    bne urt_loop
    inc fsCNT+1
    bne urt_loop
urt_nodata:
    and #$30                    ; another packet follows?
    cmp #$30
    bne urt_done
    jsr uci_ack
    jsr uci_chkesc
    jmp urt_loop
urt_done:
    rts

; ----------------------------------------------------------------------------
; uci_finish
;   Summary: end a command: discard unread reply data, read the status
;            into errbuf+1, acknowledge.
;   Input:   none. uci_finish_x: X = offset in errbuf+1 for the status, so
;            that text built before it survives (*COPY).
;   Output:  errbuf+1+offset = status text (bounded at errbuf+ERRMAX-1,
;            0-terminated); C = 0 if it starts with "00" (OK), C = 1 if not.
;   Uses:    A, X, uf_off, uf_end.

uci_finish:
    ldx #0
uci_finish_x:
    stx uf_off
uf_drain:
    lda UCI_STAT
    bpl uf_nodata
    lda UCI_RESP
    bit ESCFLG                  ; (a reply that does not end: ESCAPE)
    bpl uf_drain
    jmp uci_chkesc
uf_nodata:
    and #$30                    ; more packets: acknowledge and drain them
    cmp #$30
    bne uf_status
    jsr uci_ack
    jmp uf_drain
uf_status:
    ldx uf_off
uf_sloop:
    lda UCI_STAT
    and #$40
    beq uf_send
    lda UCI_SDAT
    cpx #ERRMAX-2               ; bounded: extra characters are dropped
    bcs uf_sloop
    sta errbuf+1,x
    inx
    bne uf_sloop
uf_send:
    lda #0
    sta errbuf+1,x
    stx uf_end
    jsr uci_ack
    ldx uf_off
    lda errbuf+1,x
    cmp #'0'
    bne uf_bad
    lda errbuf+2,x
    cmp #'0'
    bne uf_bad
    clc
    rts
uf_bad:
    cpx uf_end                  ; no status at all counts as OK
    bne uf_bad2
    clc
    rts
uf_bad2:
    sec
    rts

; ----------------------------------------------------------------------------
; uci_ack
;   Summary: acknowledge the current reply packet (control bit 1) and wait
;            until the firmware has taken it.
;   Input:   none.  Output: none.  Uses: A.

uci_ack:
    lda #$02
    sta UCI_CTRL
ua_wait:
    lda UCI_STAT
    and #$02
    beq ua_done
    jsr uci_chkesc
    jmp ua_wait
ua_done:
    rts

; ----------------------------------------------------------------------------
; uci_error
;   Summary: raise the Ultimate status in errbuf+1 as a BBC error.
;   Function: drops a leading "NN," status number, writes the message in
;            sentence case ("FILE NOT FOUND" -> "File not found") and
;            picks a BBC error number: 214 for "not found" and "doesn't
;            exist", 189 for "access denied", 199 otherwise.
;   Input:   errbuf+1 = status text (from uci_finish).
;   Output:  does not return.
;   Uses:    A, X, Y.

uci_error:
    lda errbuf+1                ; "NN," prefix?
    jsr ue_isdigit
    bcs ue_text
    lda errbuf+2
    jsr ue_isdigit
    bcs ue_text
    lda errbuf+3
    cmp #','
    bne ue_text
    ldx #0                      ; shift the message 3 places left
ue_shift:
    lda errbuf+4,x
    sta errbuf+1,x
    beq ue_text
    inx
    cpx #ERRMAX-4
    bcc ue_shift
    lda #0
    sta errbuf+1,x
ue_text:
    ldx #1                      ; sentence case
ue_case:
    lda errbuf+1,x
    beq ue_number
    cmp #'A'
    bcc ue_next
    cmp #'Z'+1
    bcs ue_next
    ora #$20
    sta errbuf+1,x
ue_next:
    inx
    cpx #ERRMAX-1
    bcc ue_case
ue_number:
    ldy #199
    ldx #0
ue_find:                        ; search "not found" / "ccess denied"
    lda errbuf+1,x
    beq ue_set
    cmp #'f'
    bne ue_acc
    lda errbuf+2,x
    cmp #'o'
    bne ue_acc
    lda errbuf+3,x
    cmp #'u'
    bne ue_acc
    lda errbuf+4,x
    cmp #'n'
    bne ue_acc
    ldy #214
    bne ue_set
ue_acc:
    lda errbuf+1,x              ; "doesn't exist" (missing file)
    cmp #'e'
    bne ue_acc2
    lda errbuf+2,x
    cmp #'x'
    bne ue_acc2
    lda errbuf+3,x
    cmp #'i'
    bne ue_acc2
    lda errbuf+4,x
    cmp #'s'
    bne ue_acc2
    ldy #214
    bne ue_set
ue_acc2:
    lda errbuf+1,x
    cmp #'d'
    bne ue_more
    lda errbuf+2,x
    cmp #'e'
    bne ue_more
    lda errbuf+3,x
    cmp #'n'
    bne ue_more
    lda errbuf+4,x
    cmp #'i'
    bne ue_more
    ldy #189
    bne ue_set
ue_more:
    inx
    cpx #ERRMAX-5
    bcc ue_find
ue_set:
    sty errbuf
    jmp raise_errbuf

ue_isdigit:
    cmp #'0'
    bcc ue_no
    cmp #'9'+1
    bcs ue_no
    clc
    rts
ue_no:
    sec
    rts

; ----------------------------------------------------------------------------
; uci_cmd
;   Summary: send a command without payload and finish it; raise any
;            error from the Ultimate.
;   Input:   uciHDR/uciHLEN.  Output: none (raises on error).
;   Uses:    A, X, Y, fsLEN.

uci_cmd:
    lda #0
    sta fsLEN
    sta fsLEN+1
uci_cmd_payload:
    jsr uci_send
    jsr uci_finish
    bcc ucp_ok
    jmp uci_error
ucp_ok:
    rts

; ----------------------------------------------------------------------------
; uci_print_reply
;   Summary: print the text reply of a command (e.g. identification or
;            the time) and finish it.
;   Function: prints reply bytes through OSASCI until the reply ends;
;            non-printable bytes are skipped.
;   Input:   a command has just been sent.
;   Output:  text; C as uci_finish.
;   Uses:    A, X, Y.

uci_print_reply:
upr_loop:
    lda UCI_STAT
    bpl upr_more
    lda UCI_RESP
    cmp #32
    bcc upr_loop
    cmp #127
    bcs upr_loop
    jsr OSWRCH
    jmp upr_loop
upr_more:
    and #$30
    cmp #$30
    bne upr_done
    jsr uci_ack
    jmp upr_loop
upr_done:
    jmp uci_finish
