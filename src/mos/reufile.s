; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- REU areas to and from files (bank 2)
;
; For the sound bank's *INSTRUMENT SAVE/LOAD and *SONG SAVE/LOAD: a file
; on the Ultimate's drives is written or read in pieces of 256 bytes
; through MOSBUF, each piece copied to or from the REU by DMA. The caller
; (another bank, through farcall) opens the file, moves whole pages, and
; closes it.
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; rx_create / rx_openin
;   Summary: open the file named at fsPTR (measured, from arg_name) for
;            writing (created or replaced) or reading.
;   Output:  raises the Ultimate's error if it cannot be opened;
;            rx_openin: fsTMP = its size (32 bits).
;   Uses:    A, X, Y, fs*.
rx_create:
    jsr uci_need
    jsr fs_free_target
    lda #FA_CREATE
    jsr fs_open
    bcc rxo_rts
    jmp uci_error
rx_openin:
    jsr uci_need
    jsr fs_free_target
    lda #FA_READ
    jsr fs_open
    bcc rxo_size
    jmp uci_error
rxo_size:
    jmp fs_size
rxo_rts:
    rts

; rx_close: close the file (errors ignored)
rx_close:
    jmp fs_close_tgt

; ----------------------------------------------------------------------------
; rx_write
;   Summary: write X pages of the REU from bank A, page Y (address
;            A:Y:00) to the open file.
;   Output:  raises the Ultimate's error (the file closed).
;   Uses:    A, X, Y, fs*, rx_*.
rx_write:
    jsr rx_set
rxw_page:
    lda rx_n
    beq rxw_rts
    jsr rx_reu
    lda #REU_TO_C64
    sta REU_CMD
    lda #<MOSBUF
    sta fsPTR
    lda #>MOSBUF
    sta fsPTR+1
    lda #0
    sta fsLEN
    lda #1
    sta fsLEN+1
    lda #DOS_WRITE
    jsr fs_hdr2
    lda #0
    sta uciHDR+2
    sta uciHDR+3
    lda #4
    sta uciHLEN
    jsr uci_send
    jsr uci_finish
    bcs rx_err
    jsr rx_next
    jmp rxw_page
rxw_rts:
    rts
rx_err:
    jsr fs_saveerr
    jmp uci_error

; ----------------------------------------------------------------------------
; rx_read
;   Summary: read up to X pages from the open file into the REU at bank
;            A, page Y; a short last piece is padded with zeros.
;   Output:  X = pages read (fewer at the end of the file).
;   Uses:    A, X, Y, fs*, rx_*.
rx_read:
    jsr rx_set
    lda #0
    sta rx_got
rxr_page:
    lda rx_n
    beq rxr_done
    ldx #0                      ; (zeros for a short piece)
    txa
rxr_clr:
    sta MOSBUF,x
    inx
    bne rxr_clr
    lda #DOS_READ               ; 256 bytes to MOSBUF
    jsr fs_hdr2
    lda #0
    sta uciHDR+2
    sta fsLEN
    sta fsLEN+1
    lda #1
    sta uciHDR+3
    lda #4
    sta uciHLEN
    jsr fl_send_nopay
    lda #1
    sta fsLEN+1
    lda #0
    sta fsLEN
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    jsr uci_read_to
    lda fsCNT                   ; bytes received (0: the end)
    ora fsCNT+1
    pha
    jsr uci_finish
    pla
    beq rxr_done
    jsr rx_reu
    lda #REU_TO_REU
    sta REU_CMD
    inc rx_got
    jsr rx_next
    jmp rxr_page
rxr_done:
    ldx rx_got
    rts

; rx_set: rx_bank = A, rx_page = Y, rx_n = X
rx_set:
    sta rx_bank
    sty rx_page
    stx rx_n
    rts

; rx_next: the next page (into the next bank after page $FF)
rx_next:
    dec rx_n
    inc rx_page
    bne rxn_rts
    inc rx_bank
rxn_rts:
    rts

; rx_reu: REU registers for page rx_bank:rx_page <-> MOSBUF (256 bytes)
rx_reu:
    lda #0
    sta REU_ADDR
    sta REU_LEN
    sta REU_CTRL
    lda rx_page
    sta REU_ADDR+1
    lda rx_bank
    sta REU_BANK
    lda #<MOSBUF
    sta REU_C64
    lda #>MOSBUF
    sta REU_C64+1
    lda #1
    sta REU_LEN+1
    rts

rx_bank     = fsSX                ; (fsSX, fsSY: free in these routines)
rx_page     = fsSY
rx_n        = fsMODE
rx_got      = fsCH
