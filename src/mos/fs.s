; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- filing system on the Ultimate's DOS targets, bank 2
;
; Files live on the Ultimate's own storage (USB, SD, RAM disk /Temp),
; addressed with Ultimate paths relative to the current directory (*DIR).
; The firmware offers two DOS targets with one open file each, so BASIC
; can have two files open at once: channel &11 uses DOS target 1, channel
; &12 DOS target 2. LOAD/SAVE use whichever target is free.
;
; Channel state (ch_open, ch_ptr, ch_ext) is kept here; PTR# and EXT# are
; tracked locally (EXT# read with "file info" when a file is opened).
;
; Memory guard: LOAD and SAVE only move bytes in $0400-$7FFF (and LOAD
; only from $0800 up): $8000-$BFFF holds BASIC itself, $C000+ the screen
; and the resident MOS.
;
; ----------------------------------------------------------------------------

DOS_OPEN    = $02
DOS_CLOSE   = $03
DOS_READ    = $04
DOS_WRITE   = $05
DOS_SEEK    = $06
DOS_INFO    = $07
DOS_STAT    = $08
DOS_DELETE  = $09
DOS_RENAME  = $0A
DOS_CHDIR   = $11
DOS_GETPATH = $12
DOS_OPENDIR = $13
DOS_READDIR = $14
DOS_MKDIR   = $16
DOS_TIME    = $26
DOS_IDENT   = $01

FA_READ     = $01
FA_WRITE    = $02
FA_CREATE   = $0A               ; write + create always (overwrite). Not
                                ; $0E: with CREATE_NEW ($04) the firmware
                                ; answers "File exists" for existing files

CHAN_BASE   = $11               ; channel numbers &11, &12
; the LOAD destination range starts at lo_page (not the sound engine)
MEM_HIGH    = $8000             ; LOAD/SAVE end limit (BASIC starts here)

; ----------------------------------------------------------------------------
; fs_name
;   Summary: measure a filename: from (fsPTR) up to CR or space.
;   Function: skips leading spaces and a leading quote; stops at CR,
;            space or a closing quote. Empty names raise "Bad name" (204),
;            names over 127 characters too.
;   Input:   fsPTR = name.
;   Output:  fsPTR = first character, fsLEN = length (1-127).
;   Uses:    A, Y.

fs_name:
    ldy #0
fn_skip:
    lda (fsPTR),y
    cmp #' '
    beq fn_lead
    cmp #'"'
    bne fn_start
fn_lead:
    inc fsPTR
    bne fn_skip
    inc fsPTR+1
    bne fn_skip
fn_start:
    lda (fsPTR),y
    cmp #13
    beq fn_end
    cmp #' '
    beq fn_end
    cmp #'"'
    beq fn_end
    iny
    bpl fn_start
fn_bad:
    brk
    dta 204, 'Bad name', 0
fn_end:
    cpy #0
    beq fn_bad
    sty fsLEN
    lda #0
    sta fsLEN+1
    rts

; ----------------------------------------------------------------------------
; fs_hdr2 / fs_hdr3
;   Summary: start a DOS command header for target fsTGT.
;   Input:   A = command (fs_hdr3: X = one argument byte).
;   Output:  uciHDR, uciHLEN = 2 or 3.
;   Uses:    A.

fs_hdr3:
    stx uciHDR+2
    pha
    lda #3
    bne fh_set
fs_hdr2:
    pha
    lda #2
fh_set:
    sta uciHLEN
    pla
    sta uciHDR+1
    lda fsTGT
    sta uciHDR
    rts

; ----------------------------------------------------------------------------
; fs_free_target
;   Summary: pick a DOS target with no open channel for LOAD/SAVE/*TYPE.
;   Output:  fsTGT = 1 or 2; raises "Too many open files" (192) if both
;            channels are open.
;   Uses:    A.

fs_free_target:
    lda ch_open
    bne fft_two
    lda #TARGET_DOS1
    sta fsTGT
    rts
fft_two:
    lda ch_open+1
    bne fft_none
    lda #TARGET_DOS2
    sta fsTGT
    rts
fft_none:
    brk
    dta 192, 'Too many open files', 0

; ----------------------------------------------------------------------------
; fs_open
;   Summary: open the file named at (fsPTR) on target fsTGT.
;   Input:   fsPTR = name (CR/space terminated), A = access (FA_*).
;   Output:  C = 0 opened; C = 1 failed (status text in errbuf+1).
;   Uses:    A, X, Y, fsLEN, fsCNT.

fs_open:
    pha
    jsr uci_need
    jsr fs_name
    pla
    tax
    lda #DOS_OPEN
    jsr fs_hdr3
    jsr uci_send
    jmp uci_finish

; ----------------------------------------------------------------------------
; fs_close_tgt
;   Summary: close the file of target fsTGT; errors are ignored.
;   Uses:    A, X, Y, fsLEN.

fs_close_tgt:
    lda #DOS_CLOSE
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    jmp uci_finish

; ----------------------------------------------------------------------------
; fs_size
;   Summary: size of the open file of target fsTGT ("file info").
;   Output:  fsTMP = size (32 bits); raises on error.
;   Uses:    A, X, Y, fsADDR, fsLEN, fsCNT.

fs_size:
    lda #DOS_INFO
    jsr fs_hdr2
    lda #0
    sta fsLEN
    sta fsLEN+1
    sta fsTMP
    sta fsTMP+1
    sta fsTMP+2
    sta fsTMP+3
    jsr uci_send
    lda #<fsTMP
    sta fsADDR
    lda #>fsTMP
    sta fsADDR+1
    lda #4
    sta fsLEN
    jsr uci_read_to
    jsr uci_finish
    bcs fs_uerr
    rts
fs_uerr:
    jmp uci_error

; ----------------------------------------------------------------------------
; fs_chan
;   Summary: check a channel number.
;   Input:   Y = channel (&11 or &12).
;   Output:  X = index 0/1, fsCH = X, fsTGT = target; raises "Channel"
;            (222) if the channel is not open.
;   Uses:    A.

fs_chan:
    tya
    sec
    sbc #CHAN_BASE
    cmp #2
    bcs fc_bad
    tax
    lda ch_open,x
    beq fc_bad
    stx fsCH
    inx
    stx fsTGT
    dex
    rts
fc_bad:
    brk
    dta 222, 'Channel', 0

; ----------------------------------------------------------------------------
; fs_find (OSFIND)
;   Summary: open or close a file channel.
;   Function: A = &40 OPENIN (read), &80 OPENOUT (create/overwrite),
;            &C0 OPENUP (read/write). As on the BBC, OPENIN and OPENUP
;            return 0 when the file cannot be opened; OPENOUT raises the
;            error. A = 0 closes channel Y, or all channels if Y = 0.
;   Input:   A = mode; X/Y = name (open) or Y = channel (close).
;   Output:  open: A = channel (&11/&12) or 0. close: A = 0.
;            X and Y preserved.
;   Uses:    A, fsPTR, fsLEN, fsCNT, fsTGT, fsCH, fsMODE, fsTMP.

fs_find:
    sta fsMODE
    stx fsSX                    ; caller's X and Y, restored at the end
    sty fsSY
    cmp #0
    bne ff_open
    cpy #0                      ; CLOSE#0: all channels
    bne ff_close1
    ldx #0
ff_closeall:
    lda ch_open,x
    beq ff_cnext
    stx fsCH
    lsr                         ; (bit 0: on the REU RAM disk, nothing to
    bcs ff_creu                 ; close there; bit 1: the network)
    lsr
    bcc ff_cufile
    farcall net.nc_close, BANK_NET
    jmp ff_creu
ff_cufile:
    inx
    stx fsTGT
    jsr fs_close_tgt
ff_creu:
    ldx fsCH
    lda #0
    sta ch_open,x
ff_cnext:
    inx
    cpx #2
    bcc ff_closeall
    bcs ff_ret0
ff_close1:
    jsr fs_chan
    lda ch_open,x
    lsr
    bcs ff_c1reu
    lsr                         ; (the network: bank 7)
    bcc ff_c1file
    farcall net.nc_close, BANK_NET
    jmp ff_c1reu
ff_c1file:
    jsr fs_close_tgt
ff_c1reu:
    ldx fsCH
    lda #0
    sta ch_open,x
ff_ret0:
    lda #0
    jmp ff_ret

ff_open:
    stx fsPTR
    sty fsPTR+1
    ldx #0                      ; free channel
    lda ch_open
    beq ff_got
    inx
    lda ch_open+1
    beq ff_got
    brk
    dta 192, 'Too many open files', 0
ff_got:
    stx fsCH
    farcall net.nc_isnet, BANK_NET ; TCP:, UDP:, http://? (netchan.s)
    bcc ff_file
    ldx fsCH
    lda fsMODE
    farcall net.nc_open, BANK_NET
    jmp ff_ret
ff_file:
    jsr rd_route                ; a file on the REU RAM disk?
    bcc ff_ult
    jmp rd_ffopen
ff_ult:
    ldx fsCH
    inx
    stx fsTGT
    lda fsMODE
    and #$C0
    cmp #$40
    beq ff_in
    cmp #$80
    beq ff_out
    lda #FA_READ|FA_WRITE       ; OPENUP
    bne ff_try
ff_in:
    lda #FA_READ
    bne ff_try
ff_out:
    lda #FA_CREATE
ff_try:
    jsr fs_open
    bcc ff_opened
    lda fsMODE                  ; failed: OPENOUT raises, others give 0
    and #$C0
    cmp #$80
    beq ff_oerr
    jmp ff_ret0
ff_oerr:
    jmp uci_error
ff_opened:
    ldx fsCH                    ; PTR = 0
    txa
    asl
    asl
    tay
    lda #0
    sta ch_ptr,y
    sta ch_ptr+1,y
    sta ch_ptr+2,y
    sta ch_ptr+3,y
    lda fsMODE                  ; EXT: 0 for OPENOUT, else the file size
    and #$C0
    cmp #$80
    beq ff_ext0
    jsr fs_size
    jmp ff_setext
ff_ext0:
    lda #0
    sta fsTMP
    sta fsTMP+1
    sta fsTMP+2
    sta fsTMP+3
ff_setext:
    ldx fsCH
    txa
    asl
    asl
    tay
    lda fsTMP
    sta ch_ext,y
    lda fsTMP+1
    sta ch_ext+1,y
    lda fsTMP+2
    sta ch_ext+2,y
    lda fsTMP+3
    sta ch_ext+3,y
    lda fsMODE
    and #$C0
    sta ch_open,x
    txa
    clc
    adc #CHAN_BASE
ff_ret:
    ldx fsSX
    ldy fsSY
    rts

; ----------------------------------------------------------------------------
; fs_ateof
;   Summary: compare PTR# with EXT# of channel index X.
;   Input:   X = channel index.
;   Output:  C = 1 if PTR >= EXT (end of file).
;   Uses:    A, Y.

fs_ateof:
    txa
    asl
    asl
    tay
    lda ch_ptr,y
    cmp ch_ext,y
    lda ch_ptr+1,y
    sbc ch_ext+1,y
    lda ch_ptr+2,y
    sbc ch_ext+2,y
    lda ch_ptr+3,y
    sbc ch_ext+3,y
    rts

; fs_incptr
;   Summary: PTR# + 1 for channel index X; EXT# follows when PTR passes it.
;   Input:   X = channel index.  Output: ch_ptr, ch_ext.  Uses: A, Y.
fs_incptr:
    txa                         ; X = offset of the 32-bit PTR
    asl
    asl
    tax
    inc ch_ptr,x
    bne fip_index
    inc ch_ptr+1,x
    bne fip_index
    inc ch_ptr+2,x
    bne fip_index
    inc ch_ptr+3,x
fip_index:
    txa                         ; back to the channel index
    lsr
    lsr
    tax
fip_ext:
    jsr fs_ateof                ; PTR > EXT? (C=1 and not equal)
    bcc fip_done
    lda ch_ptr,y
    sta ch_ext,y
    lda ch_ptr+1,y
    sta ch_ext+1,y
    lda ch_ptr+2,y
    sta ch_ext+2,y
    lda ch_ptr+3,y
    sta ch_ext+3,y
fip_done:
    rts

; ----------------------------------------------------------------------------
; fs_eof (OSBYTE &7F, from mos_byte)
;   Summary: EOF#: end of file test.
;   Input:   X = channel.
;   Output:  X = $FF at end of file, else 0. Y preserved.
;   Uses:    A.

fs_eof:
    sty fsSY
    txa
    tay
    jsr fs_chan
    jsr fs_isnet
    beq fe_file
    farcall net.nc_eof, BANK_NET
    jmp fe_c
fe_file:
    jsr fs_ateof
fe_c:
    ldx #0
    bcc fe_ret
    dex
fe_ret:
    ldy fsSY
    rts

; ----------------------------------------------------------------------------
; fs_bget (OSBGET)
;   Summary: BGET#: read one byte.
;   Input:   Y = channel.
;   Output:  A = byte, C = 0; at end of file A = $FE, C = 1.
;            X and Y preserved.
;   Uses:    fsPTR, fsLEN, fsADDR, fsCNT, fsTMP, uciHDR.

fs_bget:
    stx fsSX
    sty fsSY
    jsr fs_chan
    jsr fs_isnet                ; the network (netchan.s)?
    beq fb_file
    farcall net.nc_bget, BANK_NET
    ldx fsSX
    ldy fsSY
    rts
fb_file:
    jsr fs_ateof
    bcs fb_eof
    lda ch_open,x               ; on the REU RAM disk?
    lsr
    bcc fb_ult
    jsr rd_chptr
    farcall rd_fbget, BANK_RD
    bcs fb_eof
    sta fsTMP
    jmp fb_got
fb_ult:
    lda #DOS_READ
    jsr fs_hdr2
    lda #1
    sta uciHDR+2
    lda #0
    sta uciHDR+3
    lda #4
    sta uciHLEN
    lda #0
    sta fsLEN
    sta fsLEN+1
    jsr uci_send
    lda #<fsTMP
    sta fsADDR
    lda #>fsTMP
    sta fsADDR+1
    lda #1
    sta fsLEN
    jsr uci_read_to
    lda fsCNT
    pha
    jsr uci_finish
    pla
    beq fb_eof                  ; no byte: the file ended early
fb_got:
    ldx fsCH
    jsr fs_incptr
    lda fsTMP
    clc
    bcc fb_ret
fb_eof:
    lda #$FE
    sec
fb_ret:
    ldx fsSX
    ldy fsSY
    rts

; ----------------------------------------------------------------------------
; fs_bput (OSBPUT)
;   Summary: BPUT#: write one byte.
;   Input:   A = byte, Y = channel.
;   Output:  A, X, Y preserved; raises the Ultimate's error on failure.
;   Uses:    fsPTR, fsLEN, fsCNT, fsTMP, uciHDR.

fs_bput:
    sta fsTMP
    stx fsSX
    sty fsSY
    jsr fs_chan
    jsr fs_isnet                ; the network?
    beq fp_file
    lda fsTMP
    farcall net.nc_bput, BANK_NET
    lda fsTMP
    ldx fsSX
    ldy fsSY
    rts
fp_file:
    lda ch_open,x               ; on the REU RAM disk?
    lsr
    bcc fp_ult
    lda fsTMP
    sta RD_CBYTE
    jsr rd_chptr
    farcall rd_fbput, BANK_RD
    jmp fpu_done
fp_ult:
    lda #DOS_WRITE
    jsr fs_hdr2
    lda #0
    sta uciHDR+2
    sta uciHDR+3
    lda #4
    sta uciHLEN
    lda #<fsTMP
    sta fsPTR
    lda #>fsTMP
    sta fsPTR+1
    lda #1
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_cmd_payload
fpu_done:
    ldx fsCH
    jsr fs_incptr
    lda fsTMP
    ldx fsSX
    ldy fsSY
    rts

; ----------------------------------------------------------------------------
; fs_args (OSARGS)
;   Summary: PTR#, EXT# and filing system information.
;   Function: Y = 0: A = 0 returns the filing system number (21 here);
;            other calls do nothing. Y = channel: A = 0 reads PTR#,
;            A = 1 sets PTR# (a seek), A = 2 reads EXT#, A = &FF (flush)
;            does nothing; 4-byte values at zero page X.
;   Input:   A, X, Y as above.
;   Output:  zero page X..X+3; A = 21 for A = 0, Y = 0. X and Y preserved.
;   Uses:    fsTMP, fsMODE, uciHDR.

fs_args:
    sta fsMODE
    stx fsSX
    sty fsSY
    cpy #0
    bne fa_chan
    cmp #0
    beq fa_fsnum
    jmp fa_ret
fa_fsnum:
    lda #21                     ; filing system number
    jmp fa_retA
fa_chan:
    jsr fs_chan
    jsr fs_isnet                ; the network: EXT#, setting PTR# there
    beq fa_file
    lda fsMODE
    cmp #2
    bne fa_nptr
    farcall net.nc_ext, BANK_NET
    ldx fsSX
    ldy #0
fa_next:
    lda fsTMP,y
    sta $00,x
    inx
    iny
    cpy #4
    bne fa_next
    jmp fa_ret
fa_nptr:
    cmp #1
    bne fa_file
    farcall net.nc_setptr, BANK_NET
    jmp fa_ret
fa_file:
    ldx fsCH
    lda fsMODE
    cmp #2
    beq fa_ext
    cmp #1
    beq fa_setptr
    cmp #0
    beq fa_rdptr
    jmp fa_ret
fa_rdptr:
    txa                         ; A=0: read PTR#
    asl
    asl
    tay
    ldx fsSX
    lda ch_ptr,y
    sta $00,x
    lda ch_ptr+1,y
    sta $01,x
    lda ch_ptr+2,y
    sta $02,x
    lda ch_ptr+3,y
    sta $03,x
    jmp fa_ret
fa_ext:
    txa                         ; A=2: read EXT#
    asl
    asl
    tay
    ldx fsSX
    lda ch_ext,y
    sta $00,x
    lda ch_ext+1,y
    sta $01,x
    lda ch_ext+2,y
    sta $02,x
    lda ch_ext+3,y
    sta $03,x
    jmp fa_ret
fa_setptr:                      ; A=1: seek
    ldx fsCH                    ; on the REU RAM disk: only PTR# (EXT#
    lda ch_open,x               ; grows when a byte is written there)
    lsr
    bcc fa_useek
    txa
    asl
    asl
    tay
    ldx fsSX
    lda $00,x
    sta ch_ptr,y
    lda $01,x
    sta ch_ptr+1,y
    lda $02,x
    sta ch_ptr+2,y
    lda $03,x
    sta ch_ptr+3,y
    jmp fa_ret
fa_useek:
    lda #DOS_SEEK
    jsr fs_hdr2
    ldx fsSX
    lda $00,x
    sta uciHDR+2
    lda $01,x
    sta uciHDR+3
    lda $02,x
    sta uciHDR+4
    lda $03,x
    sta uciHDR+5
    lda #6
    sta uciHLEN
    jsr uci_cmd
    lda fsCH
    asl
    asl
    tay
    lda uciHDR+2
    sta ch_ptr,y
    lda uciHDR+3
    sta ch_ptr+1,y
    lda uciHDR+4
    sta ch_ptr+2,y
    lda uciHDR+5
    sta ch_ptr+3,y
    ldx fsCH                    ; seeking past the end extends EXT
    jsr fip_ext
fa_ret:
    lda fsMODE
fa_retA:
    ldx fsSX
    ldy fsSY
    rts

; ----------------------------------------------------------------------------
; fs_gbpb (OSGBPB)
;   Summary: not supported; returns with C = 1 (operation not done), as a
;            BBC filing system without OSGBPB does. BBC BASIC never calls it.

fs_gbpb:
    sec
    rts

; ----------------------------------------------------------------------------
; fs_file (OSFILE)
;   Summary: whole-file operations.
;   Function: A = &FF load, A = 0 save, A = 5 read information, A = 6
;            delete. Others return unchanged.
;   Input:   A; X/Y = parameter block: +0 name address, +2 load address,
;            +6 execution address (load: low byte 0 = use +2), +10 start
;            (save) / length (returned), +14 end (save).
;   Output:  A = object type (1 file, 0 not found); block +10 = length.
;            X and Y preserved.
;   Uses:    fsBLK, fsPTR, fsLEN, fsCNT, fsADDR, fsTGT, fsTMP, fsMODE.

fs_file:
    sta fsMODE
    stx fsBLK
    sty fsBLK+1
    stx fsSX                    ; caller's X and Y, restored at the end
    sty fsSY
    ldy #0
    lda (fsBLK),y
    sta fsPTR
    iny
    lda (fsBLK),y
    sta fsPTR+1
    lda fsMODE
    cmp #$FF
    beq fl_load
    cmp #0
    bne fl_n0
    jmp fl_save
fl_n0:
    cmp #5
    bne fl_n5
    jmp fl_info
fl_n5:
    cmp #6
    bne fl_ret
    jmp fl_delete
fl_ret:
    lda fsMODE
fl_retA:
    ldx fsSX
    ldy fsSY
    rts

; OSFILE &FF: load
fl_load:
    jsr fl_remote               ; LOAD "$REMOTE": program already at PAGE
    bcc fl_file
    jmp fl_rload
fl_file:
    jsr rd_route                ; the REU RAM disk? (rdglue.s)
    bcc fl_ufile
    jmp rf_load
fl_ufile:
    ldy #6                      ; own load address wanted?
    lda (fsBLK),y
    beq fl_addr
    brk
    dta 252, 'Load address needed', 0
fl_addr:
    ldy #2
    lda (fsBLK),y
    sta fsADDR
    iny
    lda (fsBLK),y
    sta fsADDR+1
    jsr lo_page                 ; destination >= the lowest PAGE
    sta fsCNT
    lda fsADDR+1
    cmp fsCNT
    bcs fl_open
fl_range:
    brk
    dta 192, 'Address out of range', 0
fl_open:
    jsr fs_free_target
    lda #FA_READ
    jsr fs_open
    bcc fl_opened
    jmp uci_error
fl_opened:
    lda fsADDR                  ; fs_size uses fsADDR: keep the destination
    pha
    lda fsADDR+1
    pha
    jsr fs_size
    pla
    sta fsADDR+1
    pla
    sta fsADDR
    lda fsTMP+2                 ; size must be < 64K ...
    ora fsTMP+3
    bne fl_toobig
    lda fsADDR                  ; ... and end at or below MEM_HIGH
    clc
    adc fsTMP
    sta fsCNT
    lda fsADDR+1
    adc fsTMP+1
    bcs fl_toobig
    sta fsCNT+1
    lda fsCNT
    cmp #<[MEM_HIGH+1]
    lda fsCNT+1
    sbc #>[MEM_HIGH+1]
    bcc fl_fits
fl_toobig:
    jsr fs_close_tgt
    brk
    dta 198, 'No room', 0
fl_fits:
    lda #DOS_READ               ; read the whole file in one transfer
    jsr fs_hdr2
    lda fsTMP
    sta uciHDR+2
    sta fsLEN
    lda fsTMP+1
    sta uciHDR+3
    pha
    lda #4
    sta uciHLEN
    lda #0
    sta fsLEN+1
    jsr fl_send_nopay
    pla
    sta fsLEN+1
    jsr uci_read_to
    jsr uci_finish
    jsr fs_close_tgt
    ldy #10                     ; length = bytes read
    lda fsCNT
    sta (fsBLK),y
    iny
    lda fsCNT+1
    sta (fsBLK),y
    iny
    lda #0
    sta (fsBLK),y
    iny
    sta (fsBLK),y
    lda #1
    jmp fl_retA

fl_rload:
    lda #1
    jmp fl_retA

; fl_remote
;   Summary: recognise LOAD/CHAIN "$REMOTE" after a remote program request
;            (docs/REMOTE_DEV.md): the host has written the program to
;            PAGE by DMA, so there is nothing to read. Only while MB_PROG
;            is set; it is cleared here, so "$REMOTE" is an ordinary name
;            otherwise.
;   Input:   fsPTR = name (CR terminated).
;   Output:  C = 1 if it is the remote program.
;   Uses:    A, Y.
fl_remote:
    lda MB_PROG
    beq flr_no
    ldy #0
flr_cmp:
    lda (fsPTR),y
    cmp flr_name,y
    bne flr_no
    iny
    cpy #7
    bcc flr_cmp
    lda (fsPTR),y               ; name must end here
    cmp #13
    beq flr_yes
    cmp #' '
    bne flr_no
flr_yes:
    lda #0
    sta MB_PROG
    sec
    rts
flr_no:
    clc
    rts
flr_name:
    dta '$REMOTE', 0

; uci_send with an empty payload, keeping fsLEN for the caller
fl_send_nopay:
    lda fsLEN
    pha
    lda #0
    sta fsLEN
    jsr uci_send
    pla
    sta fsLEN
    rts

; OSFILE 0: save start..end
fl_save:
    jsr rd_route                ; the REU RAM disk?
    bcc fl_usave
    jmp rf_save
fl_usave:
    ldy #10
    lda (fsBLK),y
    sta fsADDR
    iny
    lda (fsBLK),y
    sta fsADDR+1
    ldy #14                     ; fsCNT = end
    lda (fsBLK),y
    sta fsCNT
    iny
    lda (fsBLK),y
    sta fsCNT+1
    lda fsCNT                   ; end <= MEM_HIGH and end >= start
    cmp #<[MEM_HIGH+1]
    lda fsCNT+1
    sbc #>[MEM_HIGH+1]
    bcc fs_endok
    jmp fl_range
fs_endok:
    lda fsCNT
    sec
    sbc fsADDR
    sta fsLEN
    lda fsCNT+1
    sbc fsADDR+1
    sta fsLEN+1
    bcs fs_lenok
    jmp fl_range
fs_lenok:
    lda fsLEN                   ; total length, for the block
    pha
    lda fsLEN+1
    pha
    jsr fs_free_target
    lda #FA_CREATE
    jsr fs_open                 ; (fs_open uses fsPTR/fsLEN for the name)
    bcc fs_saveopen
    jmp uci_error
fs_saveopen:
    pla
    sta fsCNT+1                 ; fsCNT = bytes still to write
    pla
    sta fsCNT
    lda fsADDR                  ; payload pointer
    sta fsPTR
    lda fsADDR+1
    sta fsPTR+1
fs_chunk:
    lda fsCNT
    ora fsCNT+1
    beq fs_saved
    lda #0                      ; next chunk: up to 256 bytes
    sta fsLEN+1
    lda fsCNT+1
    beq fs_small
    lda #0
    sta fsLEN
    inc fsLEN+1                 ; 256
    bne fs_sendchunk
fs_small:
    lda fsCNT
    sta fsLEN
fs_sendchunk:
    lda fsCNT                   ; fsCNT -= chunk
    sec
    sbc fsLEN
    sta fsTMP
    lda fsCNT+1
    sbc fsLEN+1
    sta fsTMP+1
    lda #DOS_WRITE
    jsr fs_hdr2
    lda #0
    sta uciHDR+2
    sta uciHDR+3
    lda #4
    sta uciHLEN
    jsr uci_send                ; advances fsPTR
    jsr uci_finish
    bcc fs_chunkok
    jsr fs_saveerr
fs_chunkok:
    lda fsTMP
    sta fsCNT
    lda fsTMP+1
    sta fsCNT+1
    jsr uci_chkesc
    jmp fs_chunk
fs_saved:
    jsr fs_close_tgt
    lda #1
    jmp fl_retA

; fs_saveerr: close the file, then raise the write error
fs_saveerr:
    ldx #ERRMAX-1               ; keep the status text: closing overwrites it
fse_copy:
    lda errbuf,x
    pha
    dex
    bpl fse_copy
    jsr fs_close_tgt
    ldx #0
fse_back:
    pla
    sta errbuf,x
    inx
    cpx #ERRMAX
    bcc fse_back
    jmp uci_error

; OSFILE 5: read information (A = 1 and length, or A = 0 if not found)
fl_info:
    jsr rd_route                ; the REU RAM disk?
    bcc fl_uinfo
    jmp rf_info
fl_uinfo:
    jsr fs_free_target
    lda #FA_READ
    jsr fs_open
    bcc fi_open
    lda #0
    jmp fl_retA
fi_open:
    jsr fs_size
    jsr fs_close_tgt
    ldy #10
    ldx #0
fi_len:
    lda fsTMP,x
    sta (fsBLK),y
    iny
    inx
    cpx #4
    bcc fi_len
    lda #1
    jmp fl_retA

; OSFILE 6: delete
fl_delete:
    jsr rd_route                ; the REU RAM disk?
    bcc fl_udel
    jmp rf_delete
fl_udel:
    jsr uci_need
    jsr fs_free_target
    jsr fs_name
    lda #DOS_DELETE
    jsr fs_hdr2
    jsr uci_send
    jsr uci_finish
    lda #0
    bcs fd_ret
    lda #1
fd_ret:
    jmp fl_retA

; ----------------------------------------------------------------------------
; lo_page
;   Summary: A = the high byte of the lowest address programs may use
;            (OSHWM: &1D, or &09 under *SOUND NONE).
;   Uses:    A.
lo_page:
    lda snd_on
    beq lop_none
    lda #>OSHWM
    rts
lop_none:
    lda #>OSHWM_NONE
    rts

; fs_isnet: channel index X: Z = 0 if it is a network channel (bit 1 of
; ch_open: netchan.s). X kept.  Uses: A.
fs_isnet:
    lda ch_open,x
    and #2
    rts
