; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *STATUS: the machine and its environment, bank 2
;
; Shows the MOS and cartridge, the Ultimate's hardware, CPU speed, REU,
; BASIC's memory use, the current directory and open files, drives, the
; network address and the clock. Ultimate details only when the command
; interface is there.
;
; ----------------------------------------------------------------------------

; BBC BASIC zero page read here (lib/bbc-basic vars.s, U64 target)
BAS_FSA     = $02               ; VARTOP: end of the variables
BAS_STACK   = $04               ; BASIC stack pointer (grows down from HIMEM)
BAS_HIMEM   = $06
BAS_TOP     = $12
BAS_PAGE    = $18               ; high byte only
BAS_LOMEM   = $50

ST_MAXCOL   = 38                ; values end before column 39: no line
                                ; ever wraps on the 40-column screen

; ----------------------------------------------------------------------------
; cmd_status
;   Summary: *STATUS (also *SYS): print the system overview, one screen
;            line per item (long values are cut at column 38).
;   Input:   none.  Output: text.  Uses: A, X, Y, mosTMP, fs*, osfblk.

cmd_status:
    jsr st_text
    dta 13, 'U64 BBC BASIC 0.1.0, BASIC 3.10', 13
    .if .def CART_TMB
    dta 'Cartridge  TwoMegabyter', 13, 0
    .else
    dta 'Cartridge  EasyFlash', 13, 0
    .endif

    lda uci_ok                  ; Ultimate hardware name
    beq st_cpu
    jsr st_text
    dta 'Machine    ', 0
    lda #TARGET_CTRL
    sta fsTGT
    lda #$28                    ; get hardware info, item 0: product
    ldx #0
    jsr fs_hdr3
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jsr st_reply
    jsr OSNEWL

st_cpu:
    jsr st_text
    dta 'CPU        ', 0
    lda turbo_state
    bne st_turbo
    jsr st_text
    dta '1 MHz', 13, 0
    jmp st_reu
st_turbo:
    cmp #1
    bne st_index
    jsr st_text
    dta 'turbo (firmware speed)', 13, 0
    jmp st_reu
st_index:
    jsr st_text
    dta 'turbo, speed index ', 0
    lda U64_TURBO
    and #$0F
    jsr st_dec8
    jsr OSNEWL

st_reu:
    jsr st_text
    dta 'REU        ', 0
    lda reu_banks+1
    beq st_reu_small
    jsr st_text
    dta '16 MB', 13, 0
    jmp st_memgo
st_reu_small:
    lda reu_banks
    bne st_reu_k
    jsr st_text
    dta 'none', 13, 0
    jmp st_memgo
st_reu_k:
    cmp #16                     ; 1 MB or more: in MB
    bcc st_reu_kb
    lsr
    lsr
    lsr
    lsr
    jsr st_dec8
    jsr st_text
    dta ' MB', 13, 0
    jmp st_memgo
st_reu_kb:
    sta mosTMP                  ; banks * 64 K
    lda #0
    sta mosTMP+1
    ldx #6
st_reu_mul:
    asl mosTMP
    rol mosTMP+1
    dex
    bne st_reu_mul
    jsr st_dec16
    jsr st_text
    dta ' K', 13, 0
    jmp st_memgo

; st_mem: PAGE, TOP, LOMEM, VARTOP, HIMEM and free memory (*STATUS,
; *MEMORY)
st_mem:
    jsr st_text
    dta 'PAGE       &', 0
    lda BAS_PAGE
    ldx #0
    jsr st_hex16
    jsr st_text
    dta '  TOP   &', 0
    lda BAS_TOP+1
    ldx BAS_TOP
    jsr st_hex16
    jsr st_text
    dta 13, 'LOMEM      &', 0
    lda BAS_LOMEM+1
    ldx BAS_LOMEM
    jsr st_hex16
    jsr st_text
    dta '  VARTOP &', 0
    lda BAS_FSA+1
    ldx BAS_FSA
    jsr st_hex16
    jsr st_text
    dta 13, 'HIMEM      &', 0
    lda BAS_HIMEM+1
    ldx BAS_HIMEM
    jsr st_hex16
    jsr st_text
    dta '  free  ', 0
    lda BAS_STACK               ; free = BASIC stack - VARTOP
    sec
    sbc BAS_FSA
    sta mosTMP
    lda BAS_STACK+1
    sbc BAS_FSA+1
    sta mosTMP+1
    jsr st_dec16
    jsr st_text
    dta ' bytes', 13, 0
    rts

st_memgo:
    jsr st_mem
    jsr st_text                 ; open files
    dta 'Files      ', 0
    lda #0
    ldx ch_open
    beq st_ch2
    clc
    adc #1
st_ch2:
    ldx ch_open+1
    beq st_chn
    clc
    adc #1
st_chn:
    jsr st_dec8
    jsr st_text
    dta ' of 2 open', 13, 0

    lda uci_ok
    bne st_ultimate
    rts

st_ultimate:
    jsr st_text
    dta 'Directory  ', 0
    lda #TARGET_DOS1
    sta fsTGT
    lda #DOS_GETPATH
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jsr st_reply
    jsr OSNEWL

    jsr st_drives
    jsr st_network

    jsr st_text
    dta 'Clock      ', 0
    lda #TARGET_DOS1
    sta fsTGT
    lda #DOS_TIME
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jsr st_reply
    jmp OSNEWL

; ----------------------------------------------------------------------------
; st_reply
;   Summary: print a UCI text reply as uci_print_reply does, but only up to
;            column ST_MAXCOL; the rest is read and dropped.
;   Uses:    A, X, Y.
st_reply:
srp_loop:
    lda UCI_STAT
    bpl srp_more
    lda UCI_RESP
    cmp #32
    bcc srp_loop
    cmp #127
    bcs srp_loop
    jsr st_capc
    jmp srp_loop
srp_more:
    and #$30
    cmp #$30
    bne srp_done
    jsr uci_ack
    jmp srp_loop
srp_done:
    jmp uci_finish

; st_capc
;   Summary: print A unless the cursor is at column ST_MAXCOL or beyond.
;   Input:   A = character.  Output: A preserved.  Uses: X, Y.
st_capc:
    pha
    sec
    jsr K_PLOT                  ; Y = column
    pla
    cpy #ST_MAXCOL
    bcs stc_skip
    jmp OSWRCH
stc_skip:
    rts

; ----------------------------------------------------------------------------
; st_drives
;   Summary: the Ultimate's drives: type, device number, on/off.
;   Function: control command "get drive info" ($29): a count, then per
;            drive type, device number, power; drive A and B have types
;            0-2 (1541, 1571, 1581), SoftIEC $0F, the printer $50 (as
;            uii_parse_deviceinfo in ultimate-uci-oscar64). Only entries
;            whose bytes arrived are listed: firmware 3.15a counts SoftIEC
;            and printer without sending them.
;   Uses:    A, X, Y, fs*, osfblk (reply buffer, 18 bytes).

st_drives:
    lda #TARGET_CTRL
    sta fsTGT
    lda #$29
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    lda #<osfblk
    sta fsADDR
    lda #>osfblk
    sta fsADDR+1
    lda #18
    sta fsLEN
    jsr uci_read_to
    lda #0
    sta mosARGS                 ; no entries yet
    jsr uci_finish
    bcs sd_scan
    lda fsCNT                   ; entries actually received: (bytes-1)/3.
    sec                         ; Firmware 3.15a counts the SoftIEC and
    sbc #1                      ; printer entries but does not send them
    ldx #0                      ; (fixed upstream 2026-10-02, #941): never
sd_div3:                        ; trust the count beyond the data
    cmp #3
    bcc sd_avail
    sbc #3
    inx
    bne sd_div3
sd_avail:
    cpx osfblk
    bcc sd_fewer
    ldx osfblk                  ; count
sd_fewer:
    stx mosARGS                 ; entries listed from the reply (for the
    txa                         ; serial-bus scan: they are skipped there)
    beq sd_scan
    sta mosTMP+2                ; drives left
    lda #1
    sta mosCNT                  ; index into the reply (st_text uses Y)
sd_next:
    lda mosTMP+2
    beq sd_scan
    dec mosTMP+2
    ldy mosCNT
    cpy #15
    bcc sd_entry
sd_exit:
    rts
sd_scan:
    jmp st_iecscan
sd_entry:
    lda osfblk,y                ; type
    sta mosTMP+3
    jsr st_text
    dta 'Drive      ', 0
    lda mosTMP+3
    cmp #$0F
    beq sd_softiec
    cmp #$50
    beq sd_printer
    cmp #3
    bcs sd_scan                 ; unknown type: stop
    tax
    lda sd_types,x              ; 1541 / 1571 / 1581
    sta mosTMP
    lda sd_types+3,x
    sta mosTMP+1
    jsr st_dec16
    jmp sd_device
sd_softiec:
    jsr st_text
    dta 'SoftIEC', 0
    jmp sd_device
sd_printer:
    jsr st_text
    dta 'printer', 0
sd_device:
    jsr st_text
    dta ' #', 0
    ldy mosCNT
    lda osfblk+1,y              ; device number
    jsr st_dec8
    ldy mosCNT
    lda osfblk+2,y              ; power
    bne sd_on
    jsr st_text
    dta ' off', 13, 0
    jmp sd_after
sd_on:
    jsr st_text
    dta ' on', 13, 0
sd_after:
    lda mosCNT                  ; next entry: 3 bytes on
    clc
    adc #3
    sta mosCNT
    jmp sd_next

; ----------------------------------------------------------------------------
; st_iecscan
;   Summary: list the serial-bus devices the drive info did not report.
;   Function: as UBoot64 (src/core.c, iec_present and getDeviceType):
;            probe device 4 and 8-30 with LISTEN; for each device that is
;            present and not already listed, read its command channel and
;            show the DOS name from the "73,<name>,..." power-on message
;            ("U64" in it: the SoftIEC drive). If the channel holds
;            another message, send "UI" (warm reset) once to get it, as
;            UBoot64 does. This also covers firmware 3.15a, whose drive
;            info leaves out the SoftIEC drive and the printer. The CPU runs
;            at 1 MHz meanwhile (KERNAL serial timing).
;   Input:   osfblk = drive info reply, mosARGS = entries listed.
;   Uses:    A, X, Y, mosTMP, mosARGS+1/+2, errbuf (status text).

KL_LISTEN   = $FFB1
KL_SECOND   = $FF93
KL_CIOUT    = $FFA8
KL_UNLSN    = $FFAE
KL_TALK     = $FFB4
KL_TKSA     = $FF96
KL_ACPTR    = $FFA5
KL_UNTLK    = $FFAB
KL_STATUS   = $90

st_iecscan:
    lda U64_TURBO               ; 1 MHz for the KERNAL serial routines
    sta mosARGS+2
    lda turbo_state
    cmp #2
    bne si_slow
    lda #$80
    sta U64_TURBO
si_slow:
    ldx #si_ids_end-si_ids-1
si_next:
    stx mosARGS+1
    lda si_ids,x
    jsr si_known
    bcs si_skip
    jsr iec_present
    bcc si_skip
    jsr st_text
    dta 'Drive      #', 0
    ldx mosARGS+1
    lda si_ids,x
    sta iec_dev
    jsr st_dec8
    lda #' '
    jsr OSWRCH
    ldx mosARGS+1
    lda si_ids,x
    cmp #4
    beq si_printer
    jsr iec_ident
    jmp si_line
si_printer:
    jsr st_text
    dta 'printer', 0
si_line:
    jsr OSNEWL
si_skip:
    ldx mosARGS+1
    dex
    bpl si_next
    lda turbo_state             ; speed back
    cmp #2
    bne si_done
    lda mosARGS+2
    sta U64_TURBO
si_done:
    rts

si_ids:
    dta 4, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22
    dta 23, 24, 25, 26, 27, 28, 29, 30
si_ids_end:

; si_known
;   Summary: is device A one of the drives listed from the drive info?
;   Input:   A = device, osfblk, mosARGS = entries.
;   Output:  C = 1 if listed.  Uses: X, mosTMP+3.
si_known:
    sta mosTMP+3
    ldx mosARGS
    beq sk_no
    lda #2                      ; device number of entry n: osfblk+3n+2
sk_loop:
    tay
    lda osfblk,y
    cmp mosTMP+3
    beq sk_yes
    tya
    clc
    adc #3
    dex
    bne sk_loop
sk_no:
    lda mosTMP+3
    clc
    rts
sk_yes:
    lda mosTMP+3
    sec
    rts

; iec_present
;   Summary: is there a device on the serial bus at A? (UBoot64's
;            iec_present: LISTEN, a secondary address, check STATUS.)
;   Input:   A = device.  Output: C = 1 if present.  Uses: A, X, Y.
iec_present:
    pha
    lda #0
    sta KL_STATUS
    pla
    jsr KL_LISTEN
    lda #$FF
    jsr KL_SECOND
    lda KL_STATUS
    sta mosTMP+2
    jsr KL_UNLSN
    lda mosTMP+2                ; bit 7 set: no device
    eor #$80
    asl                         ; C = 1: present
    rts

; iec_ident
;   Summary: print the DOS name of the device iec_dev (and note it in
;            softiec_dev if it is the SoftIEC drive).
;   Function: reads the command channel; if it is not a "73," message,
;            sends "UI" and reads it again (a real drive needs up to about
;            a second after the reset: retried for ~2 s).
;   Uses:    A, X, Y, errbuf, mosTMP.
iec_ident:
    jsr ii_get73
    jmp ii_print

; ii_get73
;   Summary: get the device's "73,<DOS name>,..." message into errbuf+1:
;            read the command channel; if it holds another message, send
;            "UI" (warm reset) and read again for up to ~2 s.
;   Input:   iec_dev.  Uses: A, X, Y, errbuf, mosTMP+2.
ii_get73:
    jsr ii_read
    lda errbuf+1
    cmp #'7'
    bne ii_reset
    lda errbuf+2
    cmp #'3'
    beq ii_got
ii_reset:
    lda iec_dev
    jsr KL_LISTEN
    lda #$6F                    ; command channel 15
    jsr KL_SECOND
    lda #'U'
    jsr KL_CIOUT
    lda #'I'
    jsr KL_CIOUT
    jsr KL_UNLSN
    lda #100                    ; up to ~2 s (100 frames)
    sta mosTMP+2
ii_retry:
    jsr wait_frame
    jsr ii_read
    lda errbuf+1
    cmp #'7'
    beq ii_got
    dec mosTMP+2
    bne ii_retry
ii_got:
    rts

ii_print:
    ldx #0                      ; the name: after the first comma
ii_comma:
    lda errbuf+1,x
    beq ii_whole
    inx
    cmp #','
    bne ii_comma
    stx mosTMP+3
    jsr ii_isu64
    bcc ii_name
    lda iec_dev                 ; remember it for *PARTITIONS and *CP
    sta softiec_dev
    jsr st_text
    dta 'SoftIEC ', 0
ii_name:
    ldx mosTMP+3
ii_nloop:
    lda errbuf+1,x
    beq ii_done
    cmp #','
    beq ii_done
    stx mosTMP+3
    jsr st_capc                 ; long DOS names are cut at the edge
    ldx mosTMP+3
    inx
    bne ii_nloop
ii_whole:                       ; no comma: print what there is
    ldx #0
    stx mosTMP+3
    beq ii_nloop
ii_done:
    rts

; ii_isu64: C = 1 if the text from errbuf+1+mosTMP+3 contains "U64" or "ULT"
ii_isu64:
    ldx mosTMP+3
iu_loop:
    lda errbuf+1,x
    beq iu_no
    cmp #'U'                    ; "U64" or "ULT" (as in "ULTIMATE DOS"):
    bne iu_next                 ; a byte lost on the bus (seen once in
    lda errbuf+2,x              ; seven runs) must not hide the drive;
    cmp #'L'                    ; a 1541's "CBM DOS" matches neither
    beq iu_ult
    cmp #'6'
    bne iu_next
    lda errbuf+3,x
    cmp #'4'
    bne iu_next
iu_yes:
    sec
    rts
iu_ult:
    lda errbuf+3,x
    cmp #'T'
    beq iu_yes
iu_next:
    inx
    cpx #ERRMAX-4
    bcc iu_loop
iu_no:
    clc
    rts

; ii_read
;   Summary: read the command channel of device iec_dev into errbuf+1
;            (0-terminated, at most ERRMAX-2 characters, CR dropped).
;   Uses:    A, X, Y.
ii_read:
    lda #0
    sta KL_STATUS
    sta errbuf+1
    lda iec_dev
    jsr KL_TALK
    lda #$6F
    jsr KL_TKSA
    ldy #0
ir_loop:
    lda KL_STATUS
    bne ir_end                  ; time-out or end of data
    jsr iec_get
    cmp #13
    beq ir_eoi
    cpy #ERRMAX-2
    bcs ir_eoi
    sta errbuf+1,y
    iny
ir_eoi:
    bit KL_STATUS               ; EOI after this byte?
    bvc ir_loop
ir_end:
    lda #0
    sta errbuf+1,y
    jmp KL_UNTLK

; ----------------------------------------------------------------------------
; iec_get
;   Summary: KL_ACPTR with a time-out.
;   Function: the KERNAL waits without limit for the talker to release the
;            clock line; a device that holds it (a stuck drive) would hang
;            the machine. Waits up to ~0.8 s (at 1 MHz) for CLK IN ($DD00
;            bit 6) first; on time-out sets KL_STATUS bit 1 and returns
;            a CR, which ends the callers' read loops.
;   Input:   a TALK session.  Output: A = byte (or 13).  X, Y kept.
iec_get:
    txa
    pha
    ldx #0
ig_out:
    lda #0
ig_in:
    bit $DD00
    bvs ig_ready
    clc
    adc #1
    bne ig_in
    dex
    bne ig_out
    pla
    tax
    lda KL_STATUS
    ora #2
    sta KL_STATUS
    lda #13
    rts
ig_ready:
    pla
    tax
    jmp KL_ACPTR

sd_types:
    dta <1541, <1571, <1581, >1541, >1571, >1581

; ----------------------------------------------------------------------------
; st_network
;   Summary: the Ultimate's IP address (network target, "get IP address"
;            of interface 0: address, netmask, gateway, 4 bytes each).
;   Uses:    A, X, Y, fs*, osfblk.

st_network:
    lda #3                      ; network target
    sta fsTGT
    lda #$05
    ldx #0
    jsr fs_hdr3
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    lda #<osfblk
    sta fsADDR
    lda #>osfblk
    sta fsADDR+1
    lda #12
    sta fsLEN
    jsr uci_read_to
    jsr uci_finish
    bcs sn_done
    lda fsCNT
    cmp #4
    bcc sn_done
    jsr st_text
    dta 'Network    ', 0
    ldy #0
sn_byte:
    lda osfblk,y
    sty mosTMP+4
    jsr st_dec8
    ldy mosTMP+4
    iny
    cpy #4
    beq sn_end
    lda #'.'
    jsr OSWRCH
    jmp sn_byte
sn_end:
    jsr OSNEWL
sn_done:
    rts

; ----------------------------------------------------------------------------
; st_text
;   Summary: print the 0-terminated text that follows the JSR, continue
;            after it.
;   Input:   text after the call.  Output: text.  Uses: A, Y, mosPTR2.
st_text:
    pla
    sta mosPTR2
    pla
    sta mosPTR2+1
    ldy #1
stt_loop:
    lda (mosPTR2),y
    beq stt_end
    jsr OSASCI
    iny
    bne stt_loop
stt_end:
    tya                         ; return past the 0
    clc
    adc mosPTR2
    tax
    lda mosPTR2+1
    adc #0
    pha
    txa
    pha
    rts

; st_hex16
;   Summary: print A (high) and X (low) as 4 hexadecimal digits.
;   Uses:    A.
st_hex16:
    pha
    jsr st_hex8
    pla
    txa
st_hex8:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr st_nibble
    pla
st_nibble:
    and #$0F
    cmp #10
    bcc stn_digit
    adc #6                      ; C=1: 'A' - '0' - 10 - 1
stn_digit:
    adc #'0'
    jmp OSWRCH

; st_dec8
;   Summary: print A (0-255) in decimal.  Uses: A, X, Y, mosTMP.
st_dec8:
    sta mosTMP
    lda #0
    sta mosTMP+1

; st_dec16
;   Summary: print mosTMP/mosTMP+1 in decimal, no leading zeros.
;   Uses:    A, X, Y, mosTMP, mosNUM.
st_dec16:
    ldy #0                      ; 1 once a digit is printed
    ldx #8
sd16_digit:
    lda #'0'
    sta mosNUM
sd16_sub:
    lda mosTMP
    sec
    sbc sd16_pow,x
    pha
    lda mosTMP+1
    sbc sd16_pow+1,x
    bcc sd16_done
    sta mosTMP+1
    pla
    sta mosTMP
    inc mosNUM
    bne sd16_sub
sd16_done:
    pla
    lda mosNUM
    cmp #'0'
    bne sd16_print
    cpy #0
    bne sd16_print
    cpx #0
    bne sd16_next
sd16_print:
    jsr OSWRCH
    ldy #1
sd16_next:
    dex
    dex
    bpl sd16_digit
    rts
sd16_pow:
    dta a(1), a(10), a(100), a(1000), a(10000)

; ----------------------------------------------------------------------------
; cmd_memory
;   Summary: *MEMORY: the memory map of the running program and the
;            screen; *MEMORY UPIC ON|OFF|AUTO chooses Upic Lite or the
;            VIC-II for the BBC modes 0-6 from the next MODE on (OFF =
;            *SHADOW: HIMEM &8000; ON and AUTO = Upic Lite where the
;            machine can show it, *SHADOW 1).
;   Input:   mosPTR/Y.  Output: text, or the setting.
;   Uses:    A, X, Y, mosTMP, fs*.
cmd_memory:
    lda #<mw_upic
    ldx #>mw_upic
    jsr arg_word
    bcc cm_show
    lda #<w_off
    ldx #>w_off
    jsr arg_word
    bcs cm_off
    lda #<w_on
    ldx #>w_on
    jsr arg_word
    bcs cm_on
    lda #<mw_auto
    ldx #>mw_auto
    jsr arg_word
    bcs cm_on
    jmp an_syntax
cm_off:
    lda #1
    sta shadow
    rts
cm_on:
    lda #0
    sta shadow
    rts

cm_show:
    jsr st_mem
    jsr st_text
    dta 'Screen     MODE ', 0
    lda vmode
    ldx mode_shadow
    beq cm_mnum
    ora #$80
cm_mnum:
    jsr st_dec8
    lda vtype
    cmp #2
    bne cm_n7
    jsr st_text
    dta ', teletext at &7C00', 13, 0
    jmp cm_upic
cm_n7:
    lda vmode_ul
    beq cm_vic
    jsr st_text
    dta ', Upic Lite at &', 0
    lda vmode_himem
    ldx #0
    jsr st_hex16
    jsr OSNEWL
    jmp cm_upic
cm_vic:
    jsr st_text
    dta ', VIC-II (above HIMEM)', 13, 0
cm_upic:
    jsr st_text
    dta 'Upic Lite  ', 0
    lda ul_ok
    bne cm_ulok
    jsr st_text
    dta 'not possible (64 MHz)', 13, 0
    rts
cm_ulok:
    lda shadow
    bne cm_uloff
    jsr st_text
    dta 'on (BBC modes 0-6)', 13, 0
    rts
cm_uloff:
    jsr st_text
    dta 'off (*SHADOW)', 13, 0
    rts

mw_upic     dta 'UPIC', 0
mw_auto     dta 'AUTO', 0
