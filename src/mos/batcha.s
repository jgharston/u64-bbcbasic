; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- firmware functions, batch A: drives, storage, clock,
; SoftIEC partitions (docs/ULTIMATE_FUNCTIONS.md). Bank 2.
;
; Wire formats follow ultimate-uci-oscar64 (ultimate_dos_lib.c,
; ultimate_common_lib.c, ultimate_time_lib.c), checked against firmware
; 3.15a there.
;
; ----------------------------------------------------------------------------

DOS_COPY    = $0B
DOS_HOME    = $17
DOS_MOUNT   = $23
DOS_UMOUNT  = $24
DOS_SWAP    = $25
DOS_SETTIME = $27
CTRL_DRIVE_A_ON  = $30          ; +1 off, +2 B on, +3 B off
TARGET_SIEC = 5
SIEC_ADDPART = $20
SIEC_DELPART = $21

; ----------------------------------------------------------------------------
; arg_word
;   Summary: next argument as a word, compared case-insensitively with
;            the 0-terminated word at the address in A (lo) / X (hi).
;   Input:   mosPTR/Y.
;   Output:  C = 1 and Y after the word if it matches; else C = 0, Y
;            unchanged.  Uses: A, mosPTR2, aw_start_y, aw_i, aw_c.
arg_word:
    sta mosPTR2
    stx mosPTR2+1
aw_skip:
    lda (mosPTR),y
    cmp #' '
    bne aw_start
    iny
    bne aw_skip
aw_start:
    sty aw_start_y
    lda #0
    sta aw_i
aw_cmp:
    ldy aw_i
    lda (mosPTR2),y
    beq aw_end
    sta aw_c
    tya
    clc
    adc aw_start_y
    tay
    lda (mosPTR),y
    jsr up2
    cmp aw_c
    bne aw_no
    inc aw_i
    bne aw_cmp
aw_end:
    lda aw_i                    ; the line must not go on with a letter
    clc
    adc aw_start_y
    tay
    lda (mosPTR),y
    jsr up2
    cmp #'A'
    bcc aw_yes
    cmp #'Z'+1
    bcc aw_no
aw_yes:
    sec
    rts
aw_no:
    ldy aw_start_y
    clc
    rts

; ci_skipsp: A = the next non-space character at mosPTR/Y
ci_skipsp:
    lda (mosPTR),y
    cmp #' '
    bne cis_rts
    iny
    bne ci_skipsp
cis_rts:
    rts

; up2: ASCII a-z to A-Z (bank 2 copy of toupper)
up2:
    cmp #'a'
    bcc up2_done
    cmp #'z'+1
    bcs up2_done
    and #$DF
up2_done:
    rts

w_a:  dta 'A', 0
w_b:  dta 'B', 0
w_on: dta 'ON', 0
w_off: dta 'OFF', 0

; ----------------------------------------------------------------------------
; drive_id
;   Summary: device number of drive A (X = 0) or B (X = 1), from the drive
;            info (control command $29).
;   Output:  A = device number; raises "No such drive" if it is not there.
;   Uses:    A, X, Y, fs*, osfblk.
drive_id:
    stx mosTMP+3
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
    ldx mosTMP+3                ; entry X: osfblk+1+3X (type), +2 (device)
    beq di_a
    lda fsCNT
    cmp #7
    bcc di_none
    lda osfblk+4
    cmp #3
    bcs di_none
    lda osfblk+5
    rts
di_a:
    lda fsCNT
    cmp #4
    bcc di_none
    lda osfblk+1
    cmp #3
    bcs di_none
    lda osfblk+2
    rts
di_none:
    brk
    dta 199, 'No such drive', 0

; arg_drive
;   Summary: optional drive argument: A, B or a device number (default A).
;   Output:  A = device number, Y after the argument.  Uses: A, X, fs*.
arg_drive:
    lda #<w_b
    ldx #>w_b
    jsr arg_word
    bcs ad_b
    lda #<w_a
    ldx #>w_a
    jsr arg_word
    bcs ad_a
    sty mosTMP+1
    jsr arg_number
    bcs ad_default
    lda mosNUM
    rts
ad_default:
    ldy mosTMP+1
ad_a:
    sty mosTMP+1
    ldx #0
    jsr drive_id
    ldy mosTMP+1
    rts
ad_b:
    sty mosTMP+1
    ldx #1
    jsr drive_id
    ldy mosTMP+1
    rts

; ----------------------------------------------------------------------------
; cmd_mount
;   Summary: *MOUNT <image> [A|B|<device>]: mount a disk image (D64, D71,
;            D81, G64 ...) on an Ultimate drive (default drive A).
;   Input:   command line.  Output: raises the Ultimate's error.
;   Uses:    A, X, Y, fs*, osfblk.
cmd_mount:
    jsr uci_need
    jsr arg_name
    lda fsPTR                   ; keep the name: arg_drive uses fs*
    pha
    lda fsPTR+1
    pha
    lda fsLEN
    pha
    jsr arg_drive
    sta uciHDR+2
    pla
    sta fsLEN
    lda #0
    sta fsLEN+1
    pla
    sta fsPTR+1
    pla
    sta fsPTR
    lda #TARGET_DOS1
    sta fsTGT
    ldx uciHDR+2
    lda #DOS_MOUNT
    jsr fs_hdr3
    jmp uci_cmd_payload

; cmd_unmount
;   Summary: *UNMOUNT [A|B|<device>]: remove the disk image from a drive.
cmd_unmount:
    jsr uci_need
    jsr arg_drive
    tax
    lda #TARGET_DOS1
    sta fsTGT
    lda #DOS_UMOUNT
    jsr fs_hdr3
    jmp uci_cmd

; cmd_swap
;   Summary: *SWAP [A|B|<device>]: next disk of the drive's disk set (the
;            Ultimate's multi-disk swap, firmware dos.cc MENU_1541_SWAP);
;            drive A if none is given. Not "swap A and B".
cmd_swap:
    jsr uci_need
    jsr arg_drive
    tax
    lda #TARGET_DOS1
    sta fsTGT
    lda #DOS_SWAP
    jsr fs_hdr3
    jmp uci_cmd

; ----------------------------------------------------------------------------
; cmd_drive
;   Summary: *DRIVE A|B ON|OFF: switch an Ultimate drive on or off.
;   Input:   command line.  Output: raises "Syntax" on a bad argument.
;   Uses:    A, X, Y, fs*.
cmd_drive:
    jsr uci_need
    lda #<w_a
    ldx #>w_a
    jsr arg_word
    lda #0
    bcs cdv_which
    lda #<w_b
    ldx #>w_b
    jsr arg_word
    bcc cdv_syntax
    lda #2
cdv_which:
    sta mosTMP+1                ; 0 = A, 2 = B
    lda #<w_on
    ldx #>w_on
    jsr arg_word
    bcs cdv_send
    lda #<w_off
    ldx #>w_off
    jsr arg_word
    bcc cdv_syntax
    inc mosTMP+1                ; off: +1
cdv_send:
    lda #TARGET_CTRL
    sta fsTGT
    lda mosTMP+1
    clc
    adc #CTRL_DRIVE_A_ON
    jsr fs_hdr2
    jmp uci_cmd
cdv_syntax:
    jmp an_syntax

; ----------------------------------------------------------------------------
; cmd_copy
;   Summary: *COPY <file> <directory>: copy a file into a directory,
;            same name, no overwrite (firmware dos.cc: fcopy(path, file,
;            destination, file)).
;   Function: payload "file", 0, "directory", built in errbuf+1 as
;            *RENAME does.
cmd_copy:
    jsr uci_need
    jsr arg_name                ; from
    sty fsCNT
    jsr rd_copy                 ; to or from the REU RAM disk? (rdglue.s)
    bcc cc_ult
    rts
cc_ult:
    ldy fsCNT
    ldx #0
    jsr rn_copy
    lda #0
    sta errbuf+1,x
    inx
    stx fsCNT+1
    ldy fsCNT
    jsr arg_name                ; to
    ldy #0                      ; the firmware needs an absolute directory:
    lda (fsPTR),y               ; put the current path before a relative one
    cmp #'/'
    beq cc_dest
    jsr cc_path
cc_dest:
    ldx fsCNT+1
    jsr rn_copy
    stx fsLEN
    lda #0
    sta fsLEN+1
    lda #<[errbuf+1]
    sta fsPTR
    lda #>[errbuf+1]
    sta fsPTR+1
    jsr fs_free_target
    lda #DOS_COPY
    jsr fs_hdr2
    jmp uci_cmd_payload

; cc_path
;   Summary: append the current path (ending in '/') to the *COPY payload.
;   Function: DOS "get path" on the target *COPY will use; the reply goes
;            to errbuf+1+fsCNT+1, the status after it (uci_finish_x), where
;            the destination name then overwrites it.
;   Input:   fsCNT+1 = payload length so far; fsPTR/fsLEN = destination.
;   Output:  fsCNT+1 advanced; fsPTR/fsLEN kept. Raises "Bad directory" if
;            the path cannot be read.  Uses: A, X, Y, fs*, aw_i.
cc_path:
    lda fsCNT+1                 ; the UCI routines use fsCNT: keep the
    sta aw_i                    ; payload length aside
    lda fsPTR
    pha
    lda fsPTR+1
    pha
    lda fsLEN
    pha
    jsr fs_free_target
    lda #DOS_GETPATH
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    lda aw_i
    clc
    adc #<[errbuf+1]
    sta fsADDR
    lda #>[errbuf+1]
    adc #0
    sta fsADDR+1
    lda #ERRMAX-8               ; room left, keeping some for the status
    sec
    sbc aw_i
    sta fsLEN
    jsr uci_read_to
    lda aw_i
    clc
    adc fsCNT
    sta fsCNT+1
    tax
    jsr uci_finish_x
    bcs ccp_bad
    pla
    sta fsLEN
    lda #0
    sta fsLEN+1
    pla
    sta fsPTR+1
    pla
    sta fsPTR
    rts
ccp_bad:
    brk
    dta 214, 'Bad directory', 0

; ----------------------------------------------------------------------------
; cmd_settime
;   Summary: *SETTIME yyyy/mm/dd hh:mm:ss: set the Ultimate's clock.
;   Function: six numbers (year - 1900, month, day, hour, minute,
;            second) to DOS command $27. The firmware answers with the new
;            date as data (uci_finish discards it). May be prohibited in
;            the Ultimate's settings ("98,FUNCTION PROHIBITED").
;   Uses:    A, X, Y, fs*, uciHDR.
cmd_settime:
    jsr uci_need
    ldx #0
cst_field:
    stx mosTMP+3
    jsr arg_sep_number
    bcs cst_syntax
    ldx mosTMP+3
    lda mosNUM
    cpx #0                      ; the year: minus 1900
    bne cst_store
    sec
    sbc #<1900
    pha
    lda mosNUM+1
    sbc #>1900
    bne cst_syntax              ; 1900-2155 only
    pla
cst_store:
    sta uciHDR+2,x
    inx
    cpx #6
    bcc cst_field
    lda #TARGET_DOS1
    sta fsTGT
    lda #DOS_SETTIME
    jsr fs_hdr2
    lda #8
    sta uciHLEN
    jmp uci_cmd
cst_syntax:
    jmp an_syntax

; arg_sep_number
;   Summary: a number after any of the separators / : - space.
;   Output:  C = 0, mosNUM = value; C = 1 if none.
arg_sep_number:
    lda (mosPTR),y
    cmp #'/'
    beq asn_skip
    cmp #':'
    beq asn_skip
    cmp #'-'
    beq asn_skip
    jmp arg_number
asn_skip:
    iny
    bne arg_sep_number

; ----------------------------------------------------------------------------
; cmd_dirhome
;   Summary: *DIR ~ : the Ultimate's home directory (User Interface
;            settings), on both DOS targets.
cmd_dirhome:
    lda #TARGET_DOS1
    jsr dh_target
    lda #TARGET_DOS2
dh_target:
    sta fsTGT
    lda #DOS_HOME
    jsr fs_hdr2
    jmp uci_cmd

; ----------------------------------------------------------------------------
; SoftIEC partitions (firmware 3.15+). The SoftIEC drive only reaches
; files through partitions; without one it serves /Temp.

; find_softiec
;   Summary: device number of the SoftIEC drive in softiec_dev.
;   Function: known from an earlier *STATUS or scan: kept. Otherwise
;            probes devices 8-30 and identifies them (iec_present,
;            iec_ident without printing: ii_read and "U64").
;   Output:  A = device; raises "No SoftIEC drive" if there is none.
;   Uses:    A, X, Y, mosARGS+1, mosTMP, errbuf.
find_softiec:
    lda softiec_dev
    bne fsi_done
    lda U64_TURBO
    sta mosARGS+2
    jsr iec_slow
    ldx #si_ids_end-si_ids-1
fsi_next:
    stx mosARGS+1
    lda si_ids,x
    cmp #8
    bcc fsi_skip
    sta iec_dev
    jsr iec_present
    bcc fsi_skip
    jsr ii_get73
    lda #0
    sta mosTMP+3
    jsr ii_isu64
    bcc fsi_skip
    lda iec_dev
    sta softiec_dev
    jsr iec_fast
    lda softiec_dev
fsi_done:
    rts
fsi_skip:
    ldx mosARGS+1
    dex
    bpl fsi_next
    jsr iec_fast
    brk
    dta 199, 'No SoftIEC drive', 0

; iec_slow / iec_fast
;   Summary: 1 MHz for the KERNAL serial routines, and back.
;   Input:   mosARGS+2 = saved $D031 (iec_fast).  Uses: A.
iec_slow:
    lda turbo_state
    cmp #2
    bne isl_done
    lda #$80
    sta U64_TURBO
isl_done:
    rts
iec_fast:
    lda turbo_state
    cmp #2
    bne isl_done
    lda mosARGS+2
    sta U64_TURBO
    rts

; cmd_partition
;   Summary: *PARTITION <n> <path> [<name>]: make SoftIEC partition n
;            point to a directory (add or overwrite; SoftIEC add partition
;            $20, payload "NAME:/path"). *PARTITION <n> OFF removes it
;            ($21; ineffective on firmware 3.15a hardware, see the
;            library's uii_del_partition).
;   Uses:    A, X, Y, fs*, errbuf.
cmd_partition:
    jsr uci_need
    jsr arg_byte_need
    sta mosTMP+1                ; n
    lda #<w_off
    ldx #>w_off
    jsr arg_word
    bcc cpa_add
    lda #TARGET_SIEC
    sta fsTGT
    ldx mosTMP+1
    lda #SIEC_DELPART
    jsr fs_hdr3
    lda #0
    sta fsLEN
    sta fsLEN+1
    jmp siec_cmd
cpa_add:
    jsr arg_name                ; path
    lda fsPTR
    pha
    lda fsPTR+1
    pha
    lda fsLEN
    pha
    tya
    pha
    jsr arg_name_opt            ; name (optional)
    ldx #0                      ; errbuf+1 = "NAME:" + path
    bcs cpa_defname
    jsr rn_copy
    jmp cpa_colon
cpa_defname:
    lda #'P'                    ; default name: P<n>
    sta errbuf+1
    inx
    lda mosTMP+1
    jsr cpa_digits
cpa_colon:
    lda #':'
    sta errbuf+1,x
    inx
    pla
    pla
    sta fsLEN
    pla
    sta fsPTR+1
    pla
    sta fsPTR
    jsr rn_copy
    stx fsLEN
    lda #0
    sta fsLEN+1
    lda #<[errbuf+1]
    sta fsPTR
    lda #>[errbuf+1]
    sta fsPTR+1
    lda #TARGET_SIEC
    sta fsTGT
    ldx mosTMP+1
    lda #SIEC_ADDPART
    jsr fs_hdr3
    jmp siec_cmd

; siec_cmd
;   Summary: send a SoftIEC target command and check its status. The
;            SoftIEC target answers with one binary byte (firmware
;            softiec_target.cc): 0 = OK, 1-9 = the errors in siec_msgs.
;   Input:   header set up (fs_hdr3), fsPTR/fsLEN = payload.
;   Output:  returns if OK, else raises the error.  Uses: A, X, Y, fs*.
siec_cmd:
    jsr uci_send
    jsr uci_finish
    ldx uf_end                  ; no status, or a 0 byte: OK
    beq sc_ok
    ldx errbuf+1
    beq sc_ok
    cpx #10
    bcc sc_known
    ldx #0
sc_known:
    lda siec_msgidx,x           ; copy "message",0 behind a BRK
    tay
    ldx #0
sc_copy:
    lda siec_msgs,y
    sta errbuf+1,x
    beq sc_raise
    iny
    inx
    bne sc_copy
sc_raise:
    lda #199
    sta errbuf
    jmp raise_errbuf
sc_ok:
    rts
siec_msgidx:
    dta 0, sim1-siec_msgs, sim2-siec_msgs, sim3-siec_msgs, sim4-siec_msgs
    dta sim5-siec_msgs, sim6-siec_msgs, sim7-siec_msgs, sim8-siec_msgs, sim9-siec_msgs
siec_msgs:
    dta 'SoftIEC error', 0
sim1: dta 'File not found', 0
sim2: dta 'Save error', 0
sim3: dta 'No input channel', 0
sim4: dta 'Unknown command', 0
sim5: dta 'SoftIEC not loaded', 0
sim6: dta 'Invalid parameters', 0
sim7: dta 'Invalid name', 0
sim8: dta 'Invalid partition', 0
sim9: dta 'Invalid directory', 0

; cpa_digits: append A (1-255) in decimal to errbuf+1 at X; X advanced.
cpa_digits:
    ldy #100
    jsr cpd_digit
    ldy #10
    jsr cpd_digit
    ora #'0'
    sta errbuf+1,x
    inx
    rts
cpd_digit:
    sty mosTMP+2
    ldy #'0'-1
cpd_sub:
    iny
    sec
    sbc mosTMP+2
    bcs cpd_sub
    adc mosTMP+2
    cpy #'0'
    beq cpd_skip
    pha
    tya
    sta errbuf+1,x
    inx
    pla
cpd_skip:
    rts

; arg_name_opt: like arg_name, C = 1 if the line ends instead
arg_name_opt:
    lda (mosPTR),y
    cmp #' '
    bne ano_check
    iny
    bne arg_name_opt
ano_check:
    cmp #13
    beq ano_none
    jsr arg_name
    clc
    rts
ano_none:
    sec
    rts

; arg_byte_need: a number 0-255, else "Syntax"/"Bad number"
arg_byte_need:
    jsr arg_need
    lda mosNUM+1
    beq abn_ok
    farcall cli_badnum, BANK_MOS
abn_ok:
    lda mosNUM
    rts

; ----------------------------------------------------------------------------
; cmd_cp
;   Summary: *CP <n>: select SoftIEC partition n ("CPn" over the serial
;            bus, as UBoot64's iec_select_partition); prints the drive's
;            message if it is not OK.
cmd_cp:
    jsr arg_byte_need
    sta mosTMP+1
    jsr find_softiec
    sta iec_dev
    lda U64_TURBO
    sta mosARGS+2
    jsr iec_slow
    lda iec_dev
    jsr KL_LISTEN
    lda #$6F
    jsr KL_SECOND
    lda #'C'
    jsr KL_CIOUT
    lda #'P'
    jsr KL_CIOUT
    ldx #0
    lda mosTMP+1
    jsr cpa_digits
    lda #0                      ; 0-terminated: the KERNAL may change X
    sta errbuf+1,x
    sta mosTMP+2
ccp_send:
    ldy mosTMP+2
    lda errbuf+1,y
    beq ccp_sent
    jsr KL_CIOUT
    inc mosTMP+2
    bne ccp_send
ccp_sent:
    jsr KL_UNLSN
    jsr ii_read
    jsr iec_fast
    lda errbuf+1                ; "00" or "02" (partition selected): quiet
    cmp #'0'
    bne ccp_show
    rts
ccp_show:
    ldx #0
ccp_print:
    lda errbuf+1,x
    beq ccp_nl
    jsr OSWRCH
    inx
    bne ccp_print
ccp_nl:
    jmp OSNEWL

; ----------------------------------------------------------------------------
; cmd_partitions
;   Summary: *PARTITIONS: list the SoftIEC drive's partitions (the
;            directory "$=P" over the serial bus: number, name, type).
;   Function: LOAD-style read of channel 0: skip the load address, then
;            per line: link (0 = end), line number, text up to 0. Reverse
;            and other control codes are skipped. ESCAPE stops.
cmd_partitions:
    jsr find_softiec
    sta iec_dev
    lda U64_TURBO
    sta mosARGS+2
    jsr iec_slow
    lda #0
    sta KL_STATUS
    lda iec_dev
    jsr KL_LISTEN
    lda #$F0                    ; open channel 0
    jsr KL_SECOND
    ldx #0
cps_name:
    lda cps_dollar,x
    beq cps_named
    jsr KL_CIOUT
    inx
    bne cps_name
cps_named:
    jsr KL_UNLSN
    lda iec_dev
    jsr KL_TALK
    lda #$60
    jsr KL_TKSA
    jsr cps_byte                ; load address
    jsr cps_byte
    lda #0
    sta fsTMP+3                 ; 0: the header line
cps_line:
    jsr cps_byte                ; link
    sta mosTMP
    jsr cps_byte
    ora mosTMP
    beq cps_end
    bit KL_STATUS
    bvs cps_end
    jsr cps_byte                ; line number
    sta mosTMP
    jsr cps_byte
    sta mosTMP+1
    jsr cps_digits              ; (fsTMP = its digits)
    jsr st_dec16
    lda #0                      ; leading spaces not printed yet
    sta fsTMP+1
    sta fsTMP+2                 ; 0: before the first character
cps_text:
    jsr cps_byte
    beq cps_eol
    cmp #32
    bcc cps_text
    cmp #127
    bcs cps_text
    ldx fsTMP+2
    bne cps_out
    cmp #' '                    ; the drive's padding: counted, not printed
    bne cps_first
    inc fsTMP+1
    bne cps_text
cps_first:
    inc fsTMP+2
    jsr cps_pad
cps_out:
    jsr st_capc
    jmp cps_text
cps_eol:
    jsr OSNEWL
    inc fsTMP+3                 ; (not the header line any more)
    bit ESCFLG
    bmi cps_end
    lda KL_STATUS
    beq cps_line
cps_end:
    jsr KL_UNTLK
    lda iec_dev                 ; close channel 0
    jsr KL_LISTEN
    lda #$E0
    jsr KL_SECOND
    jsr KL_UNLSN
    jmp iec_fast

cps_byte:
    jsr iec_get
    pha
    pla
    rts

cps_dollar:
    dta '$=P', 0

; cps_digits: fsTMP = the number of digits of mosTMP (1-5)
cps_digits:
    ldx #1
    ldy #3
cpd_try:
    lda mosTMP                  ; mosTMP >= 10, 100, 1000, 10000?
    cmp cpd_lo,y
    lda mosTMP+1
    sbc cpd_hi,y
    bcc cpd_done
    inx
    dey
    bpl cpd_try
cpd_done:
    stx fsTMP
    rts
cpd_lo:
    dta <10000, <1000, <100, <10
cpd_hi:
    dta >10000, >1000, >100, >10

; cps_pad: before the first character of a line (A, kept): an entry's
; quote goes to column 5, as a 1541 lists (the Ultimate pads 3-digit
; numbers one short); other lines keep the drive's spacing
cps_pad:
    pha
    ldx fsTMP+1                 ; the drive's spaces + 1
    inx
    cmp #'"'
    bne cpp_out
    lda fsTMP+3
    beq cpp_out                 ; (the header line)
    lda #5                      ; spaces = 5 - digits, at least 1
    sec
    sbc fsTMP
    tax
    beq cpp_one
    bpl cpp_out
cpp_one:
    ldx #1
cpp_out:
    lda #' '
    jsr OSWRCH
    dex
    bne cpp_out
    pla
    rts

; ----------------------------------------------------------------------------
; clock_word (OSWORD 14, from mos_word)
;   Summary: BBC "read real-time clock": the Ultimate's clock.
;   Function: block +0 = 0: a 25-byte string "Day,dd Mon yyyy.hh:mm:ss"
;            plus CR; = 1: 7 BCD bytes year (2 digits), month, day,
;            day of week (1 = Sunday), hour, minute, second. Other
;            reasons leave the block alone. Fields come from the DOS
;            "get time" text "yyyy/mm/dd hh:mm:ss".
;   Input:   mosPTR = block.  Output: block.
;   Uses:    A, X, Y, fs*, mosTMP, mosARGS, mosNUM.
clock_word:
    ldy #0
    lda (mosPTR),y
    cmp #2
    bcs cw_done
    sta mosCNT                  ; reason
    jsr uci_need
    lda #TARGET_DOS1
    sta fsTGT
    lda #DOS_TIME
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jsr cw_parse
    jsr uci_finish
    jsr cw_dow
    lda mosCNT
    bne cw_bcd
    jmp cw_string
cw_done:
    rts
cw_bcd:
    lda mosTMP                  ; year mod 100 (16-bit year)
    sta mosNUM
    lda mosTMP+1
    sta mosNUM+1
    ldx #100
    jsr cwd_div
    ldy #0
    lda cwd_rem
    jsr cw_tobcd
    sta (mosPTR),y
    lda mosTMP+2                ; month
    jsr cw_bcdput
    lda mosTMP+3                ; day
    jsr cw_bcdput
    lda mosHIGH                 ; day of week, 1 = Sunday
    jsr cw_bcdput
    lda mosARGS                 ; hour
    jsr cw_bcdput
    lda mosARGS+1
    jsr cw_bcdput
    lda mosARGS+2
cw_bcdput:
    iny
    jsr cw_tobcd
    sta (mosPTR),y
    rts

; cw_tobcd: A (0-99) -> BCD
cw_tobcd:
    ldx #0
ctb_ten:
    cmp #10
    bcc ctb_done
    sbc #10
    inx
    bne ctb_ten
ctb_done:
    sta mosNUM
    txa
    asl
    asl
    asl
    asl
    ora mosNUM
    rts

; cw_parse: read the reply text, numbers into year (mosTMP/+1), month
; (mosTMP+2), day (+3), hour/minute/second (mosARGS..+2)
cw_parse:
    lda #0
    sta mosNUM
    sta mosNUM+1
    sta mosHIGH                 ; field index
cwp_loop:
    lda UCI_STAT
    bpl cwp_more
    lda UCI_RESP
    cmp #'0'
    bcc cwp_sep
    cmp #'9'+1
    bcs cwp_sep
    and #$0F                    ; mosNUM = mosNUM * 10 + digit
    pha
    lda mosNUM
    ldx mosNUM+1
    asl mosNUM
    rol mosNUM+1
    asl mosNUM
    rol mosNUM+1
    clc
    adc mosNUM
    sta mosNUM
    txa
    adc mosNUM+1
    sta mosNUM+1
    asl mosNUM
    rol mosNUM+1
    pla
    clc
    adc mosNUM
    sta mosNUM
    bcc cwp_loop
    inc mosNUM+1
    bne cwp_loop
cwp_sep:
    jsr cwp_store
    jmp cwp_loop
cwp_more:
    and #$30
    cmp #$30
    bne cwp_end
    jsr uci_ack
    jmp cwp_loop
cwp_end:
cwp_store:                      ; store mosNUM in field mosHIGH (max 6)
    ldx mosHIGH
    cpx #6
    bcs cws_done
    cpx #0
    bne cws_byte
    lda mosNUM                  ; field 0: the year, 16 bits
    sta mosTMP
    lda mosNUM+1
    sta mosTMP+1
    jmp cws_next
cws_byte:
    lda cw_field_addr,x
    tax
    lda mosNUM
    sta $00,x
cws_next:
    inc mosHIGH
    lda #0
    sta mosNUM
    sta mosNUM+1
cws_done:
    rts
cw_field_addr:
    dta mosTMP, mosTMP+2, mosTMP+3, mosARGS, mosARGS+1, mosARGS+2

; cw_dow: day of week (Sakamoto), 1 = Sunday, into mosHIGH
cw_dow:
    lda mosTMP                  ; y = year, minus 1 for January/February
    sta mosNUM
    lda mosTMP+1
    sta mosNUM+1
    lda mosTMP+2
    cmp #3
    bcs cwd_y
    lda mosNUM
    bne cwd_dec
    dec mosNUM+1
cwd_dec:
    dec mosNUM
cwd_y:                          ; sum = y + y/4 - y/100 + y/400 + t[m] + d
    lda mosNUM                  ; (16 bits in mosPTR2)
    sta mosPTR2
    lda mosNUM+1
    sta mosPTR2+1
    ldx #4
    jsr cwd_div_add
    ldx #100
    jsr cwd_div_sub
    ldx #200                    ; y/400 = (y/2)/200
    lsr mosNUM+1
    ror mosNUM
    jsr cwd_div_add
    ldx mosTMP+2
    lda cwd_t-1,x
    clc
    adc mosTMP+3
    adc mosPTR2
    sta mosPTR2
    bcc cwd_mod
    inc mosPTR2+1
cwd_mod:                        ; mod 7
    lda mosPTR2
    sec
    sbc #7
    tax
    lda mosPTR2+1
    sbc #0
    bcc cwd_res
    sta mosPTR2+1
    stx mosPTR2
    jmp cwd_mod
cwd_res:
    lda mosPTR2
    clc
    adc #1
    sta mosHIGH
    rts
cwd_t:
    dta 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4

; cwd_div_add / cwd_div_sub: mosPTR2 +/- mosNUM / X (16 bits / 8 bits)
cwd_div_add:
    jsr cwd_div
    clc
    adc mosPTR2
    sta mosPTR2
    lda cwd_qh
    adc mosPTR2+1
    sta mosPTR2+1
    rts
cwd_div_sub:
    jsr cwd_div
    lda mosPTR2
    sec
    sbc cwd_ql
    sta mosPTR2
    lda mosPTR2+1
    sbc cwd_qh
    sta mosPTR2+1
    rts
; cwd_div
;   Summary: mosNUM / X, shift-and-subtract, 16 bits by 8 bits.
;   Output:  A = cwd_ql = low byte, cwd_qh = high byte, cwd_rem.
;   Uses:    A, Y.
cwd_div:
    stx cwd_dv
    lda #0
    sta cwd_ql
    sta cwd_qh
    sta cwd_rem
    lda mosNUM
    sta cwd_n
    lda mosNUM+1
    sta cwd_n+1
    ldy #16
cdv_bit:
    asl cwd_n
    rol cwd_n+1
    rol cwd_rem
    lda cwd_rem
    bcs cdv_sub                 ; remainder overflowed 8 bits
    cmp cwd_dv
    bcc cdv_zero
cdv_sub:
    sbc cwd_dv
    sta cwd_rem
    sec
    bcs cdv_q
cdv_zero:
    clc
cdv_q:
    rol cwd_ql
    rol cwd_qh
    dey
    bne cdv_bit
    lda cwd_ql
    rts

; cw_string: "Day,dd Mon yyyy.hh:mm:ss" + CR into the block
cw_string:
    lda mosTMP                  ; year / 100 and mod 100 first (cwd_div
    sta mosNUM                  ; uses Y)
    lda mosTMP+1
    sta mosNUM+1
    ldx #100
    jsr cwd_div
    sta mosCNT                  ; century (reason no longer needed)
    lda cwd_rem
    sta mosMAX
    ldy #0
    lda mosHIGH                 ; day name
    sec
    sbc #1
    sta mosNUM
    asl
    adc mosNUM                  ; *3
    tax
    jsr cws_3
    lda #','
    jsr cws_put
    lda mosTMP+3
    jsr cws_2
    lda #' '
    jsr cws_put
    lda mosTMP+2                ; month name
    sec
    sbc #1
    sta mosNUM
    asl
    adc mosNUM
    clc
    adc #21                     ; months follow the 7 day names
    tax
    jsr cws_3
    lda #' '
    jsr cws_put
    lda mosCNT                  ; year: 4 digits
    jsr cws_2
    lda mosMAX
    jsr cws_2
    lda #'.'
    jsr cws_put
    lda mosARGS
    jsr cws_2
    lda #':'
    jsr cws_put
    lda mosARGS+1
    jsr cws_2
    lda #':'
    jsr cws_put
    lda mosARGS+2
    jsr cws_2
    lda #13
cws_put:
    sta (mosPTR),y
    iny
    rts
cws_2:                          ; two digits
    jsr cw_tobcd
    pha
    lsr
    lsr
    lsr
    lsr
    ora #'0'
    jsr cws_put
    pla
    and #$0F
    ora #'0'
    jmp cws_put
cws_3:                          ; three characters from cws_names,X
    lda cws_names,x
    jsr cws_put
    lda cws_names+1,x
    jsr cws_put
    lda cws_names+2,x
    jmp cws_put
cws_names:
    dta 'SunMonTueWedThuFriSat'
    dta 'JanFebMarAprMayJunJulAugSepOctNovDec'
