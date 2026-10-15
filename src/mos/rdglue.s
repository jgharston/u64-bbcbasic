; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- routing names to the REU RAM disk (bank 2)
;
; The RAM disk itself is bank 5 (reudisk.s); here: which names belong to
; it (/REU/name, or a name without a path while /REU is the current
; directory), and the parts of OSFILE, *DIR, *PWD, *CAT, *DELETE,
; *RENAME, *TYPE and *COPY that go there (PLAN.md section 23).
;
; ----------------------------------------------------------------------------

; rd_route
;   Summary: does the name at fsPTR belong to the RAM disk?
;   Function: measures it (fs_name); "/REU/leaf", or "leaf" while reu_cwd
;            is set, put leaf (up to 16 characters, no '/') into RD_NAME.
;   Output:  C = 1: RAM disk, RD_NAME set; C = 0: an Ultimate path
;            (fsPTR/fsLEN as fs_name left them).
;   Uses:    A, X, Y.
rd_route:
    jsr fs_name
    lda rd_ok
    beq rr_no
    ldy #0
    lda (fsPTR),y
    cmp #'/'
    bne rr_rel
    jsr rr_prefix               ; "/REU/"?
    bcc rr_no
    ldx #5
    bne rr_copy
rr_rel:
    lda reu_cwd
    beq rr_no
    ldx #0
rr_copy:
    lda #0                      ; leaf -> RD_NAME
    sta rr_out
rr_c:
    cpx fsLEN
    beq rr_end
    stx rr_in
    txa
    tay
    lda (fsPTR),y
    cmp #'/'
    beq rr_bad
    ldy rr_out
    sta RD_NAME,y
    inc rr_out
    ldx rr_in
    inx
    lda rr_out
    cmp #17
    bcc rr_c
rr_bad:
    brk
    dta 204, 'Bad name', 0
rr_end:
    ldy rr_out
    beq rr_bad                  ; "/REU/" with no name
    lda #0
    sta RD_NAME,y
    lda #0
    sta rr_out
    sec
    rts
rr_no:
    clc
    rts
rr_out      = RD_ENT+31         ; output index (scratch)
rr_in       = RD_ENT+30         ; input index (fsCNT is the caller's)

; rr_prefix: C = 1 if the measured name starts "/REU/" (or is "/REU",
; "/REU/" when fsLEN <= 5: then rr_isdir says so)
rr_prefix:
    lda fsLEN
    cmp #5
    bcc rp_no
    ldy #1
rp_ch:
    lda (fsPTR),y
    jsr up2
    cmp rp_reu-1,y
    bne rp_no
    iny
    cpy #4
    bne rp_ch
    lda (fsPTR),y
    cmp #'/'
    bne rp_no
    sec
    rts
rp_no:
    clc
    rts
rp_reu      dta 'REU'

; rr_isdir: C = 1 if the measured name is "/REU" or "/REU/"
rr_isdir:
    lda fsLEN
    cmp #4
    bcc rp_no
    cmp #6
    bcs rp_no
    ldy #0
    lda (fsPTR),y
    cmp #'/'
    bne rp_no
    iny
rid_ch:
    lda (fsPTR),y
    jsr up2
    cmp rp_reu-1,y
    bne rp_no
    iny
    cpy #4
    bne rid_ch
    cpy fsLEN
    beq rid_yes
    lda (fsPTR),y
    cmp #'/'
    bne rp_no
rid_yes:
    sec
    rts

; ----------------------------------------------------------------------------
; OSFILE on the RAM disk: rf_load, rf_save, rf_info, rf_delete
;   Summary: as fs_file's operations, for a name in RD_NAME.
;   Input:   fsBLK = the OSFILE block.  Output: A = object type, through
;            fl_retA.

rf_load:
    ldy #6                      ; own load address wanted?
    lda (fsBLK),y
    sta fsMODE
    ldy #2
    lda (fsBLK),y
    sta fsADDR
    iny
    lda (fsBLK),y
    sta fsADDR+1
    farcall rd_load, BANK_RD
    ldy #10                     ; length
    lda fsLEN
    sta (fsBLK),y
    iny
    lda fsLEN+1
    sta (fsBLK),y
    lda #0
    iny
    sta (fsBLK),y
    iny
    sta (fsBLK),y
    lda #1
    jmp fl_retA

rf_save:
    ldy #10                     ; start, end -> fsADDR, fsLEN
    lda (fsBLK),y
    sta fsADDR
    iny
    lda (fsBLK),y
    sta fsADDR+1
    ldy #14
    lda (fsBLK),y
    sec
    sbc fsADDR
    sta fsLEN
    iny
    lda (fsBLK),y
    sbc fsADDR+1
    sta fsLEN+1
    bcs rfs_len
    jmp fl_range
rfs_len:
    lda (fsBLK),y               ; end <= MEM_HIGH
    cmp #>[MEM_HIGH+1]
    bcc rfs_ok
    jmp fl_range
rfs_ok:
    ldy #2                      ; load and execution address
    lda (fsBLK),y
    sta RD_LDADR
    iny
    lda (fsBLK),y
    sta RD_LDADR+1
    ldy #6
    lda (fsBLK),y
    sta RD_EXADR
    iny
    lda (fsBLK),y
    sta RD_EXADR+1
    farcall rd_save, BANK_RD
    lda #1
    jmp fl_retA

rf_info:
    farcall rd_info, BANK_RD
    lda #0
    bcs rfi_ret
    ldy #2
    lda RDE_LOAD
    sta (fsBLK),y
    iny
    lda RDE_LOAD+1
    sta (fsBLK),y
    ldy #6
    lda RDE_EXEC
    sta (fsBLK),y
    iny
    lda RDE_EXEC+1
    sta (fsBLK),y
    ldy #10
    ldx #0
rfi_len:
    lda RDE_LEN,x
    sta (fsBLK),y
    iny
    inx
    cpx #3
    bne rfi_len
    lda #0
    sta (fsBLK),y
    iny                         ; +14: attributes, bit 3 locked (as DFS)
    lda RDE_USED
    and #2
    asl
    asl
    sta (fsBLK),y
    lda #1
rfi_ret:
    jmp fl_retA

rf_delete:
    farcall rd_delete, BANK_RD
    lda #0
    bcs rfd_ret
    lda #1
rfd_ret:
    jmp fl_retA

; ----------------------------------------------------------------------------
; *TYPE on the RAM disk: the file RD_NAME, printable characters and CR
rd_type:
    farcall rd_open, BANK_RD
rty_piece:
    farcall rd_read, BANK_RD
    tax
    beq rty_done
    stx fsCNT+1
    ldx #0
rty_byte:
    stx fsCNT
    lda RD_BUF,x
    cmp #13
    beq rty_out
    cmp #32
    bcc rty_next
    cmp #127
    bcs rty_next
rty_out:
    jsr OSASCI
rty_next:
    ldx fsCNT
    inx
    cpx fsCNT+1
    bne rty_byte
    bit ESCFLG
    bpl rty_piece
    jmp uci_chkesc
rty_done:
    jmp OSNEWL

; ----------------------------------------------------------------------------
; *COPY between the RAM disk and the Ultimate's drives
;   Summary: rc_from_reu: the file RD_NAME to the Ultimate directory at
;            (fsPTR) (the name is kept); rc_to_reu: the Ultimate file at
;            (fsPTR) to the RAM disk (its last path part as the name).
;   Function: 128 bytes at a time through RD_BUF.
;   Uses:    A, X, Y, fs*, errbuf.

; rc_from_reu: destination path in errbuf+1: [current path] dir / leaf
rc_from_reu:
    lda #0
    sta fsCNT+1
    ldy #0
    lda (fsPTR),y
    cmp #'/'
    beq rcf_abs
    jsr cc_path                 ; (as *COPY: absolute for the firmware)
rcf_abs:
    ldx fsCNT+1
    jsr rn_copy                 ; the directory
    lda errbuf,x                ; ends in '/' already?
    cmp #'/'
    beq rcf_leaf
    lda #'/'
    sta errbuf+1,x
    inx
rcf_leaf:
    ldy #0
rcf_l:
    lda RD_NAME,y
    beq rcf_named
    sta errbuf+1,x
    inx
    iny
    bne rcf_l
rcf_named:
    lda #13
    sta errbuf+1,x
    lda #<[errbuf+1]
    sta fsPTR
    lda #>[errbuf+1]
    sta fsPTR+1
    farcall rd_open, BANK_RD    ; (RD_NAME still the source)
    jsr fs_free_target
    lda #FA_CREATE
    jsr fs_open
    bcc rcf_piece
    jmp uci_error
rcf_piece:
    farcall rd_read, BANK_RD
    cmp #0
    beq rcf_done
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #<RD_BUF
    sta fsPTR
    lda #>RD_BUF
    sta fsPTR+1
    lda #DOS_WRITE
    jsr fs_hdr2
    lda #0
    sta uciHDR+2
    sta uciHDR+3
    lda #4
    sta uciHLEN
    jsr uci_send
    jsr uci_finish
    bcc rcf_piece
    jsr fs_saveerr
    jmp uci_error
rcf_done:
    jmp fs_close_tgt

; rc_to_reu: the Ultimate file (fsPTR, measured) to the RAM disk
rc_to_reu:
    ldy fsLEN                   ; the name: after the last '/'
    ldx #0
rct_find:
    dey
    bmi rct_from
    lda (fsPTR),y
    cmp #'/'
    bne rct_find
rct_from:
    iny
rct_c:
    cpy fsLEN
    beq rct_end
    lda (fsPTR),y
    sta RD_NAME,x
    iny
    inx
    cpx #16
    bne rct_c
rct_end:
    lda #0
    sta RD_NAME,x
    jsr fs_free_target          ; open the source first
    lda #FA_READ
    jsr fs_open
    bcc rct_open
    jmp uci_error
rct_open:
    farcall rd_create, BANK_RD
rct_piece:
    lda #DOS_READ               ; 128 bytes to RD_BUF
    jsr fs_hdr2
    lda #128
    sta uciHDR+2
    sta fsLEN
    lda #0
    sta uciHDR+3
    sta fsLEN+1
    lda #4
    sta uciHLEN
    jsr fl_send_nopay
    lda #<RD_BUF
    sta fsADDR
    lda #>RD_BUF
    sta fsADDR+1
    lda #128
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr uci_read_to
    lda fsCNT                   ; bytes received
    pha
    jsr uci_finish
    pla
    beq rct_done
    pha
    farcall rd_append, BANK_RD
    pla
    cmp #128
    beq rct_piece
rct_done:
    jmp fs_close_tgt

; ----------------------------------------------------------------------------
; cd_reu
;   Summary: *DIR /REU makes the RAM disk the current directory (the
;            Ultimate's own current directory is kept); *DIR .. or any
;            other directory leaves it.
;   Output:  C = 1: done here; C = 0: an Ultimate directory follows (Y
;            unchanged).  Uses: A, X, fs*.
cd_reu:
    sty fsCNT
    jsr arg_name
    jsr rr_isdir
    bcc cdr_other
    lda rd_ok
    bne cdr_set
    brk
    dta 214, 'No RAM disk (REU of 2 MB or more needed)', 0
cdr_set:
    lda #1
    sta reu_cwd
    sec
    rts
cdr_other:
    lda reu_cwd                 ; ".." from /REU: back to the Ultimate's
    beq cdr_ult                 ; current directory
    lda #0
    sta reu_cwd
    lda fsLEN
    cmp #2
    bne cdr_ult
    ldy #0
    lda (fsPTR),y
    cmp #'.'
    bne cdr_ult
    iny
    lda (fsPTR),y
    cmp #'.'
    bne cdr_ult
    sec
    rts
cdr_ult:
    ldy fsCNT
    clc
    rts

; rd_ren: *RENAME on the RAM disk: old in RD_NAME, the new name (a name
; without a path counts as on the RAM disk) next on the line
rd_ren:
    ldx #16
rrn_old:
    lda RD_NAME,x
    sta RD_NAME2,x
    dex
    bpl rrn_old
    ldy fsCNT
    jsr arg_name
    lda reu_cwd
    pha
    lda #1
    sta reu_cwd
    jsr rd_route
    pla
    sta reu_cwd
    bcs rrn_new
    jmp rr_bad
rrn_new:
    ldx #16                     ; RD_NAME = old, RD_NAME2 = new
rrn_sw:
    lda RD_NAME,x
    pha
    lda RD_NAME2,x
    sta RD_NAME,x
    pla
    sta RD_NAME2,x
    dex
    bpl rrn_sw
    farcall rd_rename, BANK_RD
    rts

; rd_copy
;   Summary: *COPY when the RAM disk is involved: from it to an Ultimate
;            directory, or from an Ultimate file to /REU.
;   Input:   fsPTR/fsLEN = the source (measured), fsCNT = line position.
;   Output:  C = 1 done; C = 0 not the RAM disk's (an Ultimate copy).
;   Uses:    A, X, Y, fs*, aw_*.
rd_copy:
    lda fsPTR                   ; keep the source
    sta aw_start_y
    lda fsPTR+1
    sta aw_i
    lda fsLEN
    sta aw_c
    jsr rd_route
    bcs rcp_from
    ldy fsCNT                   ; the destination: /REU?
    jsr arg_name
    jsr rr_isdir
    bcc rcp_no
    lda aw_start_y
    sta fsPTR
    lda aw_i
    sta fsPTR+1
    lda aw_c
    sta fsLEN
    jsr rc_to_reu
    sec
    rts
rcp_no:
    lda aw_start_y
    sta fsPTR
    lda aw_i
    sta fsPTR+1
    lda aw_c
    sta fsLEN
    clc
    rts
rcp_from:
    ldy fsCNT
    jsr arg_name                ; the destination directory
    jsr rr_isdir
    bcc rcp_ok
    jmp rr_bad                  ; RAM disk to RAM disk
rcp_ok:
    jsr rc_from_reu
    sec
    rts

; ----------------------------------------------------------------------------
; rd_ffopen
;   Summary: OSFIND's open on the REU RAM disk (from fs_find, the name
;            routed into RD_NAME, channel index fsCH free).
;   Function: rd_fopen in bank 5; the channel gets PTR# 0, EXT# the
;            length, its entry in rd_chent and ch_open = mode + 1 (bit 0:
;            on the RAM disk). OPENIN/OPENUP of a missing file give 0.
;   Output:  through ff_ret / ff_ret0: A = channel or 0.
;   Uses:    A, X, Y, fs*.
rd_ffopen:
    lda fsMODE
    and #$C0
    farcall rd_fopen, BANK_RD
    bcc rfo_ok
    jmp ff_ret0
rfo_ok:
    ldx fsCH
    sta rd_chent,x
    txa
    asl
    asl
    tay
    lda #0
    sta ch_ptr,y
    sta ch_ptr+1,y
    sta ch_ptr+2,y
    sta ch_ptr+3,y
    sta ch_ext+3,y
    lda RDE_LEN
    sta ch_ext,y
    lda RDE_LEN+1
    sta ch_ext+1,y
    lda RDE_LEN+2
    sta ch_ext+2,y
    lda fsMODE
    and #$C0
    ora #1
    sta ch_open,x
    txa
    clc
    adc #CHAN_BASE
    jmp ff_ret

; rd_chptr: channel index X: RD_CPTR = its PTR# (24 bits), X = its entry
rd_chptr:
    txa
    asl
    asl
    tay
    lda ch_ptr,y
    sta RD_CPTR
    lda ch_ptr+1,y
    sta RD_CPTR+1
    lda ch_ptr+2,y
    sta RD_CPTR+2
    lda rd_chent,x
    tax
    rts
