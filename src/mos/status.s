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

; ----------------------------------------------------------------------------
; cmd_status
;   Summary: *STATUS (also *SYS): print the system overview.
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
    jsr uci_print_reply
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
    jmp st_mem
st_reu_small:
    lda reu_banks
    bne st_reu_k
    jsr st_text
    dta 'none', 13, 0
    jmp st_mem
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
    jmp st_mem
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
    jsr uci_print_reply
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
    jsr uci_print_reply
    jmp OSNEWL

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
    jsr uci_finish
    bcs sd_exit
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
    txa
    beq sd_exit
    sta mosTMP+2                ; drives left
    lda #1
    sta mosCNT                  ; index into the reply (st_text uses Y)
sd_next:
    lda mosTMP+2
    beq sd_exit
    dec mosTMP+2
    ldy mosCNT
    cpy #15
    bcc sd_entry
sd_exit:
    rts
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
    bcs sd_exit                 ; unknown type: stop
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
