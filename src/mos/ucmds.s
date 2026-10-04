; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- filing system and Ultimate * commands, bank 2
;
; Called from mos_cli (bank 0) through the trampoline with mosPTR = the
; command line and Y = the first character after the command word.
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; arg_name
;   Summary: take the next argument of the command line as a name.
;   Input:   mosPTR/Y.
;   Output:  fsPTR/fsLEN = the name (see fs_name); Y = the character
;            after it.
;   Uses:    A.

arg_name:
    tya
    clc
    adc mosPTR
    sta fsPTR
    lda mosPTR+1
    adc #0
    sta fsPTR+1
    jsr fs_name
    lda fsPTR                   ; Y = fsPTR + fsLEN - mosPTR
    clc
    adc fsLEN
    sec
    sbc mosPTR
    tay
    rts

; arg_number
;   Summary: next argument as a number (decimal or &hex, see cli_number).
;   Input:   mosPTR/Y.
;   Output:  C = 0, mosNUM = value, Y after it; C = 1 if there is none.
arg_number:
    farcall cli_number, BANK_MOS
    rts

; arg_need
;   Summary: like arg_number, but raises "Syntax" if there is no number.
arg_need:
    jsr arg_number
    bcs an_syntax
    rts
an_syntax:
    brk
    dta 220, 'Syntax', 0

; ----------------------------------------------------------------------------
; cmd_dir
;   Summary: *DIR <path> (also *CD): change the current directory of both
;            DOS targets, so channels and LOAD/SAVE agree.
;   Input:   command line.  Output: raises on error.
;   Uses:    A, X, Y, fs*.

cmd_dir:
    jsr uci_need
    jsr arg_name
    lda fsPTR                   ; keep the name for the second target
    pha
    lda fsPTR+1
    pha
    lda #TARGET_DOS1
    jsr cd_target
    pla
    sta fsPTR+1
    pla
    sta fsPTR
    lda #TARGET_DOS2
cd_target:
    sta fsTGT
    lda #DOS_CHDIR
    jsr fs_hdr2
    jmp uci_cmd_payload

; ----------------------------------------------------------------------------
; cmd_pwd
;   Summary: *PWD: print the current directory.
;   Input:   none.  Output: text.  Uses: A, X, Y, fs*.

cmd_pwd:
    jsr uci_need
    lda #TARGET_DOS1
    sta fsTGT
    lda #DOS_GETPATH
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jsr uci_print_reply
    jmp OSNEWL

; ----------------------------------------------------------------------------
; cmd_cat
;   Summary: *CAT (also *.): list the current directory.
;   Function: prints the path, then each entry, two columns of 20; longer
;            names get their own line, directories end in '/'. ESCAPE
;            stops the listing (the read is aborted).
;   Input:   none.  Output: text.
;   Uses:    A, X, Y, fs*, mosCNT (column).

cmd_cat:
    jsr cmd_pwd
    jsr fs_free_target
    lda #DOS_OPENDIR
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jsr uci_finish
    bcc cat_read
    lda errbuf+1                ; "01,DIRECTORY EMPTY" is not an error
    cmp #'0'
    bne cat_err
    lda errbuf+2
    cmp #'1'
    bne cat_err
    rts
cat_err:
    jmp uci_error
cat_read:
    lda #DOS_READDIR
    jsr fs_hdr2
    jsr uci_send
    lda #0
    sta mosCNT                  ; output column
cat_entry:
    lda UCI_STAT                ; entry = attribute byte + name
    bpl cat_end
    lda UCI_RESP
    sta fsMODE                  ; attribute: bit 4 = directory
    lda #0
    sta fsCNT                   ; name length so far
cat_char:
    lda UCI_STAT
    bpl cat_nameend
    lda UCI_RESP
    cmp #32
    bcc cat_char
    cmp #127
    bcs cat_char
    jsr OSWRCH
    inc fsCNT
    jmp cat_char
cat_nameend:
    lda fsMODE
    and #$10
    beq cat_pad
    lda #'/'
    jsr OSWRCH
    inc fsCNT
cat_pad:
    lda mosCNT                  ; second column, or too long: new line
    bne cat_newline
    lda fsCNT
    cmp #20
    bcs cat_newline
cat_spaces:
    lda #' '
    jsr OSWRCH
    inc fsCNT
    lda fsCNT
    cmp #20
    bcc cat_spaces
    lda #20
    sta mosCNT
    bne cat_next
cat_newline:
    jsr OSNEWL
    lda #0
    sta mosCNT
cat_next:
    jsr uci_chkesc
    lda UCI_STAT                ; another entry follows?
    and #$30
    cmp #$30
    bne cat_end
    jsr uci_ack
    jmp cat_entry
cat_end:
    lda mosCNT
    beq cat_done
    jsr OSNEWL
cat_done:
    jsr uci_finish
    rts

; ----------------------------------------------------------------------------
; cmd_delete
;   Summary: *DELETE <name>: delete a file.
;   Input:   command line.  Output: raises on error.  Uses: A, X, Y, fs*.

cmd_delete:
    jsr uci_need
    jsr arg_name
    jsr fs_free_target
    lda #DOS_DELETE
    jsr fs_hdr2
    jmp uci_cmd_payload

; ----------------------------------------------------------------------------
; cmd_mkdir
;   Summary: *MKDIR <name> (also *CDIR): create a directory.
;   Input:   command line.  Output: raises on error.  Uses: A, X, Y, fs*.

cmd_mkdir:
    jsr uci_need
    jsr arg_name
    jsr fs_free_target
    lda #DOS_MKDIR
    jsr fs_hdr2
    jmp uci_cmd_payload

; ----------------------------------------------------------------------------
; cmd_rename
;   Summary: *RENAME <old> <new>.
;   Function: payload = old name, 0, new name (the DOS rename format).
;            Both names are copied into errbuf+1 to form the payload
;            (bounded by ERRMAX); errbuf is free until an error.
;   Input:   command line.  Output: raises on error.  Uses: A, X, Y, fs*.

cmd_rename:
    jsr uci_need
    jsr arg_name                ; old
    sty fsCNT                   ; command line position (rn_copy uses Y)
    ldx #0
    jsr rn_copy
    lda #0
    sta errbuf+1,x
    inx
    stx fsCNT+1                 ; (saved; arg_name does not touch it)
    ldy fsCNT
    jsr arg_name                ; new
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
    lda #DOS_RENAME
    jsr fs_hdr2
    jmp uci_cmd_payload

; rn_copy: append the name at fsPTR/fsLEN to errbuf+1 at X; X advanced.
; Raises "Bad name" if it would not fit.
rn_copy:
    ldy #0
rnc_loop:
    cpy fsLEN
    beq rnc_done
    cpx #ERRMAX-2
    bcs rnc_bad
    lda (fsPTR),y
    sta errbuf+1,x
    inx
    iny
    bne rnc_loop
rnc_done:
    rts
rnc_bad:
    jmp fn_bad

; ----------------------------------------------------------------------------
; cmd_load
;   Summary: *LOAD <name> <address>: load a file into memory.
;   Input:   command line.  Output: raises on error (see fl_load).
;   Uses:    A, X, Y, fs*, osfblk.

cmd_load:
    jsr arg_name
    jsr osf_name
    jsr arg_need
    lda mosNUM
    sta osfblk+2
    lda mosNUM+1
    sta osfblk+3
    lda #0
    sta osfblk+6                ; use the given address
    lda #$FF
    bne osf_call

; osf_name: put the name address (fsPTR) in the OSFILE block
osf_name:
    lda fsPTR
    sta osfblk
    lda fsPTR+1
    sta osfblk+1
    rts

; osf_call: OSFILE A with the block osfblk
osf_call:
    ldx #<osfblk
    ldy #>osfblk
    jmp fs_file

; ----------------------------------------------------------------------------
; cmd_save
;   Summary: *SAVE <name> <start> <end> or *SAVE <name> <start> +<length>.
;   Input:   command line.  Output: raises on error (see fl_save).
;   Uses:    A, X, Y, fs*, osfblk.

cmd_save:
    jsr arg_name
    jsr osf_name
    jsr arg_need
    lda mosNUM
    sta osfblk+10
    lda mosNUM+1
    sta osfblk+11
cs_skip:
    lda (mosPTR),y              ; "+length"?
    cmp #' '
    bne cs_plus
    iny
    bne cs_skip
cs_plus:
    cmp #'+'
    bne cs_end
    iny
    jsr arg_need
    lda osfblk+10
    clc
    adc mosNUM
    sta osfblk+14
    lda osfblk+11
    adc mosNUM+1
    sta osfblk+15
    jmp cs_call
cs_end:
    jsr arg_need
    lda mosNUM
    sta osfblk+14
    lda mosNUM+1
    sta osfblk+15
cs_call:
    lda #0
    beq osf_call

; ----------------------------------------------------------------------------
; cmd_type
;   Summary: *TYPE <name>: print a text file.
;   Function: reads the file in 256-byte requests and prints each byte as
;            ASCII: CR is a newline, LF and other control codes are
;            skipped. ESCAPE stops (the read is aborted, the file closed).
;   Input:   command line.  Output: text.  Uses: A, X, Y, fs*.

cmd_type:
    jsr arg_name
    jsr fs_free_target
    lda #FA_READ
    jsr fs_open
    bcc ct_loop
    jmp uci_error
ct_loop:
    lda #DOS_READ
    jsr fs_hdr2
    lda #0
    sta uciHDR+2                ; 256 bytes per request
    lda #1
    sta uciHDR+3
    lda #4
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    sta fsCNT
    sta fsCNT+1
    jsr uci_send
ct_byte:
    lda UCI_STAT
    bpl ct_packet
    lda UCI_RESP
    inc fsCNT
    bne ct_print
    inc fsCNT+1
ct_print:
    cmp #13
    beq ct_out
    cmp #32
    bcc ct_byte
    cmp #127
    bcs ct_byte
ct_out:
    jsr OSASCI
    jmp ct_byte
ct_packet:
    and #$30
    cmp #$30
    bne ct_chunk
    jsr uci_ack
    jmp ct_byte
ct_chunk:
    jsr uci_finish
    bit ESCFLG
    bmi ct_esc
    lda fsCNT+1                 ; a full 256 bytes: there may be more
    bne ct_loop
ct_done:
    jsr fs_close_tgt
    jmp OSNEWL
ct_esc:
    jsr fs_close_tgt
    jmp uci_chkesc

; ----------------------------------------------------------------------------
; cmd_uver
;   Summary: *UVER: identification of the Ultimate's DOS and control
;            targets.
;   Input:   none.  Output: text.  Uses: A, X, Y, fs*.

cmd_uver:
    jsr uci_need
    lda #TARGET_DOS1
    jsr uv_ident
    lda #TARGET_CTRL
uv_ident:
    sta fsTGT
    lda #DOS_IDENT
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jsr uci_print_reply
    jmp OSNEWL

; ----------------------------------------------------------------------------
; cmd_time
;   Summary: *TIME: print the date and time of the Ultimate's clock.
;   Input:   none.  Output: text.  Uses: A, X, Y, fs*.

cmd_time:
    jsr uci_need
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
