; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- cartridge bank 2: Ultimate command interface, filing
; system and Ultimate * commands. Included by cart.s.
;
; Everything here is reached through the trampoline (resident.s): the
; filing system vectors (FILEV, FINDV, ...), OSCLI commands whose table
; entry names bank 2, and far calls from bank 0 (fs_init, fs_eof).
; Header conventions: see mos.s.
;
; ----------------------------------------------------------------------------

    icl 'uci.s'
    icl 'fs.s'
    icl 'ucmds.s'
    icl 'reu.s'
    icl 'status.s'
    icl 'batcha.s'
    icl 'ulpal.s'
    icl 'font.s'
    icl 'sidcmd.s'
    icl 'reufile.s'
    icl 'srcmd.s'
    icl 'rdglue.s'

; ----------------------------------------------------------------------------
; fs_init
;   Summary: start the filing system: find the REU and the Ultimate, no
;            channels open.
;   Input:   none (cold start).
;   Output:  reu_banks, uci_ok; channels closed.
;   Uses:    A, X.

fs_init:
    lda #0
    sta ch_open
    sta ch_open+1
    jsr reu_detect
    jmp uci_init

bank2_end:
    .if bank2_end > $C000
    .error "Bank 2 overflows 16K"
    .endif
    :[$C000-*] dta $FF
