; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the Ultimate's machine commands (batch C,
; docs/ULTIMATE_FUNCTIONS.md): *MENU, *REBOOT, *SAVEMEM, *CONFIG, *SETUP
; and the start-up check of the Ultimate's settings (bank 7, inside
; .local net: its own UCI driver, so payloads come from this bank)
;
; Owner's decisions of 2026-10-16 (PLAN.md 27 item 3): *REBOOT asks first
; (unless *REBOOT Y); when the settings do not suit the MOS (REU not 16 MB,
; or a U64 without its turbo registers), the start-up applies the built-in
; ones itself (src/cfg/u64bbc.cfg, the same as the .cfg the build ships):
; written to /Temp/uci_config.cfg, loaded by the control command &50
; (firmware 3.15+), then the REU and the turbo detected again.
;
; Firmware notes (ultimate-uci-oscar64 manual, uii_load_config and
; uii_save_c64_memory): the control target takes a file name as a C
; string, so its 0 is sent along; *CONFIG can't open a file in the root
; of an SD card or USB stick on 3.15a ("88"): use a folder (/Temp's root
; works).
;
; ----------------------------------------------------------------------------

UC_PATH     = MOSBUF            ; *SAVEMEM / *CONFIG: the full path (to 254)
UC_R        = mosARGS           ; the start-up check: what differs

; ----------------------------------------------------------------------------
; cmd_menu
;   Summary: *MENU: the Ultimate's menu (the freeze button, control &05);
;            the program goes on when the menu is left.
;   Uses:    A, X, Y, fs*.
cmd_menu:
    jsr s6_end
    jsr uci_need
    lda #$05
uc_ctrl:                        ; a control command without payload
    ldx #TARGET_CTRL
    ldy #2
    jsr uc_h
uc_nopay:
    lda #0
    sta fsLEN
    sta fsLEN+1
uc_send:                        ; send, finish, raise the status if not OK
    jsr uci_send
    jsr uci_finish
    bcc uc_rts
    jmp uci_error
uc_rts:
    rts

; uc_h: the header: target X, command A, length Y
uc_h:
    stx uciHDR
    sta uciHDR+1
    sty uciHLEN
    rts

; ----------------------------------------------------------------------------
; cmd_reboot
;   Summary: *REBOOT [Y]: restart the C64 (control &06); asks "Reboot?
;            (Y/N)" unless Y is given (the program in memory is lost).
;   Uses:    A, X, Y, fs*.
cmd_reboot:
    jsr uci_need
    lda #<ucw_y
    ldx #>ucw_y
    jsr s6_word
    php
    jsr s6_end
    plp
    bcs urb_go
    jsr s6_text
    dta 'Reboot? (Y/N) ', 0
    jsr OSRDCH
    bcs urb_no
    and #$DF
    cmp #'Y'
    bne urb_no
    jsr OSWRCH
    jsr OSNEWL
urb_go:
    lda #$06
    bne uc_ctrl
urb_no:
    jsr s6_text
    dta 'N', 13, 0
    lda #$7E                    ; (an ESCAPE acknowledged)
    jmp OSBYTE
ucw_y       dta 'Y', 0

; ----------------------------------------------------------------------------
; cmd_savemem / cmd_config
;   Summary: *SAVEMEM file: all 64K of C64 RAM to a file (control &0F,
;            U64 only); *CONFIG file: Ultimate settings from a .cfg file
;            (control &50, firmware 3.15+).
;   Function: the name as a full path (uc_mkpath: a name without a leading
;            / goes after the current directory), its 0 sent along.
;   Uses:    A, X, Y, fs*, MOSBUF.
cmd_savemem:
    lda #$0F
    bne uc_named
cmd_config:
    lda #$50
uc_named:
    pha
    jsr uci_need
    jsr uc_mkpath
    pla
    pha
    cmp #$0F                    ; *SAVEMEM: an old file goes first (the
    bne ucn_go                  ; firmware does not overwrite: "file
    farcall fs_free_target, BANK_FS ; exists"); not found is fine
    ldx fsTGT
    lda #DOS_DELETE
    ldy #2
    jsr uc_h
    lda #<UC_PATH
    sta fsPTR
    lda #>UC_PATH
    sta fsPTR+1
    ldx mosTMP                  ; (the path without its 0)
    dex
    stx fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_send
    jsr uci_finish
ucn_go:
    pla
    ldx #TARGET_CTRL
    ldy #2
    jsr uc_h
    lda #<UC_PATH               ; the path and its 0
    sta fsPTR
    lda #>UC_PATH
    sta fsPTR+1
    lda mosTMP
    sta fsLEN
    lda #0
    sta fsLEN+1
    jmp uc_send

; uc_mkpath: the name on the line (s6_name) as a full path at UC_PATH, 0
; included in its length mosTMP (at most 254)
uc_mkpath:
    jsr s6_name
    jsr s6_end
    lda reu_cwd                 ; (the /REU RAM disk is the MOS's own)
    beq ucp_ult
    brk
    dta 214, 'Not on /REU', 0
ucp_ult:
    ldx #0
    ldy #0
    lda (fsPTR),y
    cmp #'/'
    beq ucp_name                ; a full path already
    lda fsPTR                   ; the current directory first (DOS
    pha                         ; "get path"), then a /
    lda fsPTR+1
    pha
    lda fsLEN
    pha
    farcall fs_free_target, BANK_FS
    lda fsTGT
    tax
    lda #DOS_GETPATH
    ldy #2
    jsr uc_h
    jsr uc_nopay0
    lda #<UC_PATH
    sta fsADDR
    lda #>UC_PATH
    sta fsADDR+1
    lda #200
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_read_to
    jsr uci_finish
    pla
    sta fsLEN
    pla
    sta fsPTR+1
    pla
    sta fsPTR
    ldx fsCNT
ucp_z:                          ; (a 0 at the reply's end: not part)
    beq ucp_slash
    lda UC_PATH-1,x
    bne ucp_last
    dex
    jmp ucp_z
ucp_last:
    cmp #'/'
    beq ucp_name
ucp_slash:
    lda #'/'
    sta UC_PATH,x
    inx
ucp_name:
    ldy #0                      ; the name, then 0
ucp_c:
    cpy fsLEN
    beq ucp_end
    cpx #253
    bcs ucp_long
    lda (fsPTR),y
    sta UC_PATH,x
    inx
    iny
    bne ucp_c
ucp_end:
    lda #0
    sta UC_PATH,x
    inx
    stx mosTMP
    rts
ucp_long:
    brk
    dta 204, 'Bad name', 0

; uc_nopay0: send the header, no payload (the reply is read after)
uc_nopay0:
    lda #0
    sta fsLEN
    sta fsLEN+1
    jmp uci_send

; ----------------------------------------------------------------------------
; cmd_setup
;   Summary: *SETUP: the built-in Ultimate settings (as the .cfg file the
;            build ships) applied now, then the REU and turbo detected
;            again.
;   Uses:    A, X, Y, fs*, MOSBUF.
cmd_setup:
    jsr s6_end
    jsr uci_need
    jsr uc_apply
    bcc ucs_ok
    jmp uci_error
ucs_ok:
    jsr uc_redetect
    jsr s6_text
    dta 'Ultimate settings set', 13, 0
    rts

; uc_apply: the built-in settings to /Temp/uci_config.cfg (the control
; command's default file), loaded; C = 0 when the firmware took them ("89,
; had errors" counts too: an Ultimate II+ has no U64 items)
uc_apply:
    farcall fs_free_target, BANK_FS ; open (create), on a free DOS target
    ldx fsTGT
    lda #DOS_OPEN
    ldy #3
    jsr uc_h
    lda #FA_CREATE
    sta uciHDR+2
    lda #<uc_file
    sta fsPTR
    lda #>uc_file
    sta fsPTR+1
    lda #UC_FILELEN
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_send
    jsr uci_finish
    bcc uca_text
    rts
uca_text:
    lda #<cfg_text              ; the text (bank 6) in pieces of 128,
    sta mosPTR                  ; each copied to UC_PATH and sent from
    lda #>cfg_text              ; there
    sta mosPTR+1
    lda #<CFG_LEN
    sta fsTMP
    lda #>CFG_LEN
    sta fsTMP+1
uca_w:
    lda fsTMP
    ora fsTMP+1
    beq uca_close
    lda #128
    ldx fsTMP+1
    bne uca_n
    cmp fsTMP
    bcc uca_n
    lda fsTMP
uca_n:
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda fsTMP
    sec
    sbc fsLEN
    sta fsTMP
    bcs uca_h
    dec fsTMP+1
uca_h:
    ldy #0                      ; the piece to RAM (bank_peek, resident)
uca_cp:
    ldx #BANK_SND
    jsr bank_peek
    sta UC_PATH,y
    iny
    cpy fsLEN
    bne uca_cp
    lda #<UC_PATH
    sta fsPTR
    lda #>UC_PATH
    sta fsPTR+1
    lda mosPTR                  ; the next piece
    clc
    adc fsLEN
    sta mosPTR
    bcc uca_hd
    inc mosPTR+1
uca_hd:
    ldx fsTGT
    lda #DOS_WRITE
    ldy #4
    jsr uc_h
    lda #0
    sta uciHDR+2
    sta uciHDR+3
    jsr uci_send
    jsr uci_finish
    bcc uca_w
    rts
uca_close:
    ldx fsTGT
    lda #DOS_CLOSE
    ldy #2
    jsr uc_h
    jsr uc_nopay0
    jsr uci_finish
    bcs uca_rts
    ldx #TARGET_CTRL            ; load it (no name: the default file)
    lda #$50
    ldy #2
    jsr uc_h
    jsr uc_nopay0
    jsr uci_finish
    bcc uca_rts
    lda errbuf+1                ; "89": some items unknown here (fine)
    cmp #'8'
    bne uca_bad
    lda errbuf+2
    cmp #'9'
    bne uca_bad
    clc
uca_rts:
    rts
uca_bad:
    sec
    rts
uc_file     dta '/Temp/uci_config.cfg'
UC_FILELEN  = * - uc_file

; uc_redetect: the REU size and the turbo after new settings
uc_redetect:
    farcall reu_detect, BANK_FS
    farcall turbo_init, BANK_MOS
    rts

; ----------------------------------------------------------------------------
; uc_check
;   Summary: the start-up check (cold start, after fs_init): with the
;            command interface there, an REU other than 16 MB, or a U64
;            (its product name has "64") without its turbo registers, gets
;            the built-in settings (uc_apply) and a line saying so.
;   Uses:    A, X, Y, fs*, MOSBUF, UC_R.
uc_check:
    lda uci_ok
    bne ucc_on
    rts
ucc_on:
    lda #0
    sta UC_R
    lda reu_banks+1             ; 16 MB: 256 banks
    cmp #1
    bne ucc_reu
    lda reu_banks
    beq ucc_turbo
ucc_reu:
    inc UC_R
ucc_turbo:
    lda turbo_state
    bne ucc_go
    ldx #TARGET_CTRL            ; the product (hardware info, item 0)
    lda #$28
    ldy #3
    jsr uc_h
    lda #0
    sta uciHDR+2
    jsr uc_nopay0
    lda #<UC_PATH
    sta fsADDR
    lda #>UC_PATH
    sta fsADDR+1
    lda #40
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_read_to
    jsr uci_finish
    ldx fsCNT                   ; "64" in it: a U64 or C64 Ultimate
    beq ucc_go
ucc_s:
    dex
    beq ucc_go
    lda UC_PATH,x
    cmp #'4'
    bne ucc_s
    lda UC_PATH-1,x
    cmp #'6'
    bne ucc_s
    inc UC_R
ucc_go:
    lda UC_R
    beq ucc_rts
    jsr uc_apply
    bcc ucc_ok
    jsr uc_apply                ; (once more: right after the cartridge's
    bcs ucc_fail                ; start a command can go unanswered)
ucc_ok:
    jsr uc_redetect
    jsr s6_text
    dta 'Settings set (REU, turbo)', 13, 0
ucc_rts:
    rts
ucc_fail:
    jsr s6_text                 ; with the Ultimate's status
    dta '*SETUP: ', 0
    ldx #0
ucf_c:
    lda errbuf+1,x
    beq ucf_e
    jsr OSWRCH
    inx
    bne ucf_c
ucf_e:
    jmp OSNEWL

; (cfg_text, the built-in settings: bank 6, sndbank.s, read by bank_peek)

; ----------------------------------------------------------------------------
; uc_sids
;   Summary: *STATUS SID: the SIDs the Ultimate has, from control &28 item
;            1: per SID its address, a second address (a socket with two
;            SIDs), and its kind.
;   Function: the reply: a count, then 5 bytes per SID: address (2), the
;            second address (2, 0: none), the kind (bit 7: present; 2/3
;            UltiSID, 4/5 a SID socket on the U64, 1 on an Ultimate II+);
;            firmware 3.15a's control_target.cc (GideonZ/1541ultimate).
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF.
uc_sids:
    jsr uci_need
    ldx #TARGET_CTRL            ; hardware info, item 1
    lda #$28
    ldy #3
    jsr uc_h
    lda #1
    sta uciHDR+2
    lda #0
    sta fsLEN
    sta fsLEN+1
    sta MOSBUF
    jsr uci_send
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #41                     ; (count + 8 x 5)
    sta fsLEN
    jsr uci_read_to
    jsr uci_finish
    bcc us_got
    jmp uci_error
us_got:
    lda #0                      ; mosTMP: the SID, mosTMP+1: its offset
    sta mosTMP
    lda #1
    sta mosTMP+1
us_sid:
    lda mosTMP
    cmp MOSBUF
    bcs us_rts
    cmp #8
    bcs us_rts
    jsr s6_text
    dta 'SID ', 0
    lda mosTMP
    clc
    adc #'1'
    jsr OSWRCH
    jsr s6_text
    dta '  &', 0
    ldx mosTMP+1
    jsr us_addr
    lda MOSBUF+2,x              ; a second address
    ora MOSBUF+3,x
    beq us_kind
    jsr s6_text
    dta ' &', 0
    ldx mosTMP+1
    inx
    inx
    jsr us_addr
us_kind:
    ldx mosTMP+1
    lda MOSBUF+4,x
    and #$7F
    cmp #2
    bcc us_sock
    cmp #4
    bcs us_sock
    jsr s6_text
    dta '  UltiSID', 13, 0
    jmp us_next
us_sock:
    jsr s6_text
    dta '  socket', 13, 0
us_next:
    inc mosTMP
    lda mosTMP+1
    clc
    adc #5
    sta mosTMP+1
    bne us_sid
us_rts:
    rts
; us_addr: the address at MOSBUF+X (low, high) as 4 hex digits
us_addr:
    lda MOSBUF+1,x              ; (cn_hex keeps X)
    jsr cn_hex
    lda MOSBUF,x
    jmp cn_hex
