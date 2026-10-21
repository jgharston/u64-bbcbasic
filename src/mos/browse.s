; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *BROWSE: a file browser (bank 7, inside .local brw)
;
; Reachable at the prompt with F1
; on an empty line (lineed.s: F1 there has nothing to COPY), in the MOS,
; with drives and folders, opening by type, file information and *TYPE,
; delete and rename with a confirmation; then copy, move and paste of
; marked entries, new folders, recursive through folders (decisions:
; SPACE marks several, C copies, X cuts, V pastes in the folder shown; a
; folder is not copied or moved to /REU; a name that exists in the target
; asks per item Y/N/All/Quit; deleting a folder that is not empty asks).
;
; The listing: the current directory's entries (the Ultimate's through
; the command interface, /REU's from the RAM disk's directory), 64 bytes
; each in the REU's file bank (&0A0000: attribute, name length, name; bit
; 7 of the attribute marks the entry), up to 1023. The screen (MODE 100):
; two header bars, 20 entries, a status line, the keys. Keys: cursor
; up/down a line, P/U a page down/up, T/E the top/end, cursor right (or
; RETURN) into a folder, cursor left (or DEL) one folder up, / (or the up
; arrow) the root: as UBoot64-v2's file browser.
; RETURN opens, SPACE marks, L lists (*TYPE), D deletes, R renames, N
; makes a folder, C copies, X cuts, V pastes, Q or ESCAPE leaves. D, C and X act on the marked
; entries, or on the selected one when none is marked.
; Opening by type: a folder (and "..") is entered; a name without '.' is
; taken as a BASIC program and CHAINed (the browser ends and types
; CHAIN "name" through *KEY slot 9: keys.s); .SEQ *SEQ, .MOD *MODPLAY,
; .WAV a sample played (sample 32 on voice 30), .D64/.D71/.D81/.G64
; *MOUNT, .UPIC loaded and shown, .VPL *PALETTE LOAD; others: *TYPE.
; Those go through * commands, whose names end at a space: such names
; cannot be opened.
;
; Errors are caught (br_guard: a stub on BRKV in RAM puts the stack back
; and maps this bank again): the browser shows the message and goes on.
;
; The Ultimate's drives are worked on with the DOS commands directly
; (names with spaces work): CHDIR, DELETE, RENAME, MKDIR and the
; firmware's file copy (COPY: a file of the current folder into a folder;
; it never replaces one). A move within a drive is a rename; otherwise a
; copy, then the source deleted. Folders are walked recursively (br_tr,
; br_del): only the two paths and an index per level are kept (the
; command interface has one directory stream: a level's entry n is read
; again when needed; a delete always takes the first entry), 8 levels.
; /REU (no folders) is reached through *COPY, *DELETE and *RENAME.
;
; RAM, free while a * command runs: BASIC's string buffer (&0600: the
; command for OSCLI; &0680: variables; &06C0: OSWORD block; &06C8: the
; BRKV stub) and its input buffer (&0700: the source path, &0780: the
; folder shown, the target; filled with CR on leaving: br_quit); MOSBUF
; (the entry, UCI payloads). The clipboard is in the REU at &4000 (the
; HTTP buffer, free meanwhile).
;
; ----------------------------------------------------------------------------

BR_BANK     = $0A               ; the listing (the file scratch bank)
BR_MAX      = 1023
BR_ROWS     = 20
BR_ROW0     = 2                 ; first list row (rows 2-21; 22 the status)
BR_CMD      = $0600             ; 128: a command for OSCLI
BV          = $0680             ; 64: the variables
BR_OSW      = $06C0             ; 5: OSWORD 0's block
BR_STUB     = $06C8             ; 12: the BRKV stub
BR_PA       = $0700             ; 128: the source path ('/' ended)
BR_PB       = $0780             ; 128: the folder shown, the target
BR_PMAX     = 126               ; longest path
BR_ENT      = MOSBUF            ; an entry: attr, length, name (to 61)
BR_NAME     = MOSBUF+2
BR_PAY      = MOSBUF+$40        ; 128: a DOS command's payload
BR_ITEM     = MOSBUF+$C0        ; 64: an entry compared (br_find)
BR_CLIP     = $4000             ; REU bank 0: op, count, source path
BR_CLENT    = $4100             ; the clipboard's entries, 64 each
BR_CLMAX    = 240
BR_DEPTH    = 8
DOS_CPY     = $0B               ; (DOS_COPY in batcha.s, bank 2)

br_n        = BV+0              ; 2: entries
br_top      = BV+2              ; 2: the first shown
br_sel      = BV+4              ; 2: the one selected
br_i        = BV+6              ; 2: an entry worked on
br_root     = BV+8              ; 1: at the root (the drives)
br_row      = BV+9
br_attr     = BV+10             ; the opened file's type (br_ext)
br_len      = BV+11
br_key      = BV+12
br_old      = BV+13             ; 2: the selection before a move
br_rdi      = BV+15             ; the RAM disk entry read (bl_reu)
br_nm       = BV+16             ; 2: entries marked
br_sp       = BV+18             ; the stack pointer br_guard keeps
br_tmp      = BV+19             ; 2: br_guard's routine
br_op       = BV+21             ; clipboard: 0 none, 1 copy, 2 cut
br_tgt      = BV+22             ; the DOS target used
br_lvl      = BV+23             ; folder depth in a walk
br_idx      = BV+24             ; 2 x 8: entry index per level
br_j        = BV+40             ; 2: an entry of the listing
br_all      = BV+42             ; All answered
br_cn       = BV+43             ; clipboard entries
br_k        = BV+44             ; the clipboard entry worked on
br_same     = BV+45             ; source and target on one drive
br_gone     = BV+46             ; the item left its folder (moved)
br_quitf    = BV+47             ; Quit answered: the walk ends
br_fail     = BV+48             ; the last DOS command failed
br_x        = BV+49             ; a payload's length
br_eod      = BV+50             ; the directory read to its end
br_ans      = BV+51             ; an answer (Y, N, A, Q)

KEY_UP      = 139               ; OSRDCH's cursor codes
KEY_DOWN    = 138
KEY_LEFT    = 136
KEY_RIGHT   = 137

; ----------------------------------------------------------------------------
; cmd_browse
;   Summary: *BROWSE: the file browser (see the top).
;   Function: MODE 100; the stub in RAM, the clipboard empty; the listing
;            read; keys until Q / ESCAPE or a program to CHAIN.
;   Input:   none.  Output: the screen; maybe a CHAIN typed.
;   Uses:    A, X, Y, fs*, mos*, MOSBUF, &0600-&07FF, REU &4000-&7FFF.
cmd_browse:
    jsr s6_end
    lda #22                     ; MODE 100
    jsr OSWRCH
    lda #100
    jsr OSWRCH
    jsr br_curs0
    ldx #BR_STUBLEN-1
bw_stub:
    lda br_stubsrc,x
    sta BR_STUB,x
    dex
    bpl bw_stub
    lda #0
    sta br_cn
    sta br_op
    lda #<br_load
    ldx #>br_load
    jsr br_guard
bw_draw:
    jsr br_screen
bw_key:
    jsr br_status
bw_key2:
    jsr OSRDCH
    bcc bw_nesc
    lda #$7E                    ; ESCAPE: acknowledged, leave
    jsr OSBYTE
    jmp br_quit
bw_nesc:
    cmp #'a'                    ; letters: either case
    bcc bw_uc
    cmp #'z'+1
    bcs bw_uc
    and #$DF
bw_uc:
    sta br_key
    cmp #'Q'
    bne bw_nq
    jmp br_quit
bw_nq:
    ldx #0                      ; the key table: key, routine (it returns
bw_find:                        ; C = 1 to draw the screen again)
    lda bw_tab,x
    beq bw_none
    cmp br_key
    beq bw_call
    inx
    inx
    inx
    bne bw_find
bw_none:
    jmp bw_key2
bw_call:
    lda bw_tab+1,x
    sta br_tmp
    lda bw_tab+2,x
    sta br_tmp+1
    jsr bw_jmp
    bcs bw_draw
    jmp bw_key
bw_jmp:
    jmp (br_tmp)
bw_tab      dta KEY_DOWN, a(br_down1), KEY_UP, a(br_up1)
            dta KEY_RIGHT, a(br_right), KEY_LEFT, a(br_updir), 127, a(br_updir)
            dta 'P', a(br_pgdn), 'U', a(br_pgup), 'T', a(br_first), 'E', a(br_last)
            dta '/', a(br_rootdir), '^', a(br_rootdir)
            dta 13, a(br_open), 32, a(br_mark)
            dta 'L', a(br_type), 'D', a(br_delete), 'R', a(br_rename)
            dta 'N', a(br_newdir), 'C', a(br_copy), 'X', a(br_cut)
            dta 'V', a(br_paste), 0

; br_down1 / br_up1 / br_pgdn / br_pgup: the selection moved (C = 0)
br_down1:
    jsr br_down
    clc
    rts
br_up1:
    jsr br_up
    clc
    rts

; br_pgdn / br_pgup / br_first / br_last: P, U, T, E (as UBoot64-v2's
; file browser): a page on or back, the first or the last entry; the
; window follows (br_fix). C = 1: drawn again.
br_pgdn:
    lda br_sel
    clc
    adc #BR_ROWS
    sta br_sel
    bcc bpd_t
    inc br_sel+1
bpd_t:
    lda br_top
    clc
    adc #BR_ROWS
    sta br_top
    bcc br_fix
    inc br_top+1
    bcs br_fix
br_pgup:
    lda br_sel
    sec
    sbc #BR_ROWS
    sta br_sel
    bcs bpu_t
    dec br_sel+1
bpu_t:
    lda br_top
    sec
    sbc #BR_ROWS
    sta br_top
    bcs br_fix
    dec br_top+1
    jmp br_fix
br_first:
    lda #0
    sta br_sel
    sta br_sel+1
    beq br_fix
br_last:
    lda #$FF                    ; (past the end: the last)
    sta br_sel
    lsr
    sta br_sel+1
    ; (fall through)

; br_fix: br_sel into 0..n-1 (negative: 0; past the end: the last),
; br_top so that it is in the window and the window as full as can be.
; C = 1.
br_fix:
    lda br_sel+1                ; negative: 0
    bpl bfx_hi
    lda #0
    sta br_sel
    sta br_sel+1
bfx_hi:
    lda br_sel                  ; past the end: n - 1 (0 for none)
    cmp br_n
    lda br_sel+1
    sbc br_n+1
    bcc bfx_top
    lda br_n
    sec
    sbc #1
    sta br_sel
    lda br_n+1
    sbc #0
    sta br_sel+1
    bpl bfx_top
    lda #0
    sta br_sel
    sta br_sel+1
bfx_top:
    lda br_n                    ; top at most n - 20 (not negative)
    sec
    sbc #BR_ROWS
    sta br_old
    lda br_n+1
    sbc #0
    sta br_old+1
    bpl bfx_max
    lda #0
    sta br_old
    sta br_old+1
bfx_max:
    lda br_top+1
    bmi bfx_t0
    lda br_old
    cmp br_top
    lda br_old+1
    sbc br_top+1
    bcs bfx_sel
    lda br_old
    sta br_top
    lda br_old+1
    sta br_top+1
    jmp bfx_sel
bfx_t0:
    lda #0
    sta br_top
    sta br_top+1
bfx_sel:
    lda br_sel                  ; the selection above the window: there
    cmp br_top
    lda br_sel+1
    sbc br_top+1
    bcs bfx_below
    lda br_sel
    sta br_top
    lda br_sel+1
    sta br_top+1
    sec
    rts
bfx_below:
    lda br_sel                  ; below it: the window ends there
    sec
    sbc #BR_ROWS-1
    sta br_old
    lda br_sel+1
    sbc #0
    sta br_old+1
    bmi bfx_ok
    lda br_top
    cmp br_old
    lda br_top+1
    sbc br_old+1
    bcs bfx_ok
    lda br_old
    sta br_top
    lda br_old+1
    sta br_top+1
bfx_ok:
    sec
    rts

; br_right: cursor right: into the selected folder (a file: nothing)
br_right:
    lda br_n
    ora br_n+1
    beq brt_no
    jsr br_getsel
    lda BR_ENT
    and #$10
    beq brt_no
    jmp br_open
brt_no:
    clc
    rts

; br_updir: cursor left or DEL: one folder up (the root: nothing; /REU:
; the root, as its ".." is)
br_updir:
    lda br_root
    bne brt_no
    lda #$10
    sta BR_ENT
    lda #2
    sta BR_ENT+1
    lda #'.'
    sta BR_NAME
    sta BR_NAME+1
    jmp bo_folder

; br_rootdir: / or the up arrow: the root (the drives)
br_rootdir:
    lda #<bod_root
    ldy #>bod_root
    jsr br_cmdword
    lda #13
    sta BR_CMD,x
    jsr br_try
    bcc brd_ok
    jsr br_err
brd_ok:
    jmp bo_dok

; br_quit: leave (the screen cleared, the prompt follows). BASIC's input
; buffer (the paths) filled with CR: after a * command BASIC looks for the
; end of its line there, from where it was, and a path has no CR (it
; searched for ever).
br_quit:
    ldx #0
    lda #13
bq_cr:
    sta BR_PA,x
    inx
    bne bq_cr
    lda #12
    jsr OSWRCH
    ; (fall through)

; br_curs1 / br_curs0: the text cursor on / off (VDU 23,1,n;0;0;0;)
br_curs1:
    lda #1
    bne bcu_go
br_curs0:
    lda #0
bcu_go:
    pha
    lda #23
    jsr OSWRCH
    lda #1
    jsr OSWRCH
    pla
    jsr OSWRCH
    ldy #7
bcu_z:
    lda #0
    jsr OSWRCH
    dey
    bne bcu_z
    rts

; ----------------------------------------------------------------------------
; br_guard
;   Summary: call a routine with errors caught.
;   Function: BRKV and br_sp are kept on the stack, BRKV set to the stub
;            (BR_STUB, RAM), br_sp to the stack pointer; the routine is
;            called. An error (BRK) reaches the stub through BRKV with
;            BASIC mapped: it puts the stack pointer back, maps this bank
;            and goes on at br_caught, which returns here as if the
;            routine had ended. Calls nest (each keeps the one before).
;            ESCAPE is acknowledged.
;   Input:   A/X = the routine.
;   Output:  C = 0 it ended; C = 1 an error: errbuf (number, message).
;   Uses:    A, X, Y (and what the routine uses), br_tmp.
br_guard:
    sta br_tmp
    stx br_tmp+1
    lda BRKV+1
    pha
    lda BRKV
    pha
    lda br_sp
    pha
    lda #<BR_STUB
    sta BRKV
    lda #>BR_STUB
    sta BRKV+1
    tsx
    stx br_sp
    jsr bg_call
    pla
    sta br_sp
    pla
    sta BRKV
    pla
    sta BRKV+1
    clc
    rts
bg_call:
    jmp (br_tmp)
br_caught:                      ; (the stack as at br_guard's tsx)
    pla
    sta br_sp
    pla
    sta BRKV
    pla
    sta BRKV+1
    ldy #0                      ; the message to errbuf (an error from a
bcg_c:                          ; bank is there already, FAULT pointing
    lda (FAULT),y               ; at it)
    sta errbuf,y
    beq bcg_e
    iny
    cpy #ERRMAX-1
    bcc bcg_c
    lda #0
    sta errbuf,y
bcg_e:
    lda errbuf
    cmp #17
    bne bcg_ne
    lda #$7E
    jsr OSBYTE
bcg_ne:
    sec
    rts
; the stub, copied to BR_STUB: ldx br_sp, txs, lda #BANK_NET,
; jsr map_bank, jmp br_caught
br_stubsrc  dta $AE, a(br_sp), $9A, $A9, BANK_NET, $20, a(map_bank)
            dta $4C, a(br_caught)
BR_STUBLEN  = *-br_stubsrc

; br_escack: an ESCAPE pressed during a walk acknowledged (it ended the
; walk; the browser goes on)
br_escack:
    bit ESCFLG
    bpl bea_none
    lda #$7E
    jmp OSBYTE
bea_none:
    rts

; br_try: OSCLI the command at BR_CMD, errors caught (as br_guard).
br_try:
    lda #<bt_cli
    ldx #>bt_cli
    jmp br_guard
bt_cli:
    ldx #<BR_CMD
    ldy #>BR_CMD
    jmp OSCLI

; br_err: the error (errbuf) in the status bar, then a key. A status
; from the command interface ("NN,TEXT") is shown without its number.
br_err:
    jsr br_bar
    ldx #0
    lda errbuf+3
    cmp #','
    bne be_l
    ldx #3
be_l:
    lda errbuf+1,x
    beq be_e
    jsr OSWRCH
    inx
    cpx #ERRMAX-2
    bcc be_l
be_e:
    ; (fall through)

; br_key1: a key; ESCAPE acknowledged (A = 27).  Output: A.  Uses: A, X, Y.
br_key1:
    jsr OSRDCH
    bcc bk1_rts
    lda #$7E
    jsr OSBYTE
    lda #27
bk1_rts:
    rts

; ----------------------------------------------------------------------------
; br_load
;   Summary: the current directory's listing into the REU: br_n entries,
;            none marked, the selection on the first; the path in BR_PB.
;   Function: /REU (reu_cwd): its directory's entries in use; else the
;            Ultimate's path (DOS GETPATH) and, below the root, ".." first,
;            then OPENDIR / READDIR. At the root the drives, and /REU with
;            a RAM disk.
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF.
br_load:
    lda #0
    sta br_n
    sta br_n+1
    sta br_nm
    sta br_nm+1
    jsr bl_top0
    jmp bl_go
bl_top0:                        ; (the selection and the window on the first)
    lda #0
    sta br_top
    sta br_top+1
    sta br_sel
    sta br_sel+1
    rts
bl_go:
    sta br_root
    lda reu_cwd
    beq bl_ult
    jsr bl_reupath
    jsr bl_dotdot
    jmp bl_reu
bl_ult:
    jsr net.uci_need
    jsr bl_getpath
    lda BR_PB                   ; "/" alone: the root
    cmp #'/'
    bne bl_notroot
    lda BR_PB+1
    bne bl_notroot
    inc br_root
    lda rd_ok                   ; the RAM disk as a drive
    beq bl_dir
    lda #$10
    sta BR_ENT
    ldx #3
bl_rn:
    lda bl_reuname-1,x
    sta BR_NAME-1,x
    dex
    bne bl_rn
    lda #3                      ; ("REU")
    sta BR_ENT+1
    jsr bl_add
    jmp bl_dir
bl_notroot:
    jsr bl_dotdot
bl_dir:
    jsr br_target
    jsr br_rdopen
    bcs bl_rts                  ; (empty, or not readable: what there is)
bl_entry:
    jsr br_rdnext
    bcs bl_end
    jsr bl_add
    jmp bl_entry
bl_end:
    jsr net.uci_finish
bl_rts:
    rts
bl_reuname  dta 'REU'

; bl_reu: the RAM disk's entries in use (RD_BANK: 127 of 32 bytes from
; &20: in use, name to 16, 0 ended)
bl_reu:
    lda #0
    sta br_rdi
bl_reul:
    lda br_rdi                  ; its 32 bytes -> MOSBUF+$80
    clc
    adc #1
    sta mosTMP+1
    lda #0
    lsr mosTMP+1
    ror
    lsr mosTMP+1
    ror
    lsr mosTMP+1
    ror
    sta mosTMP
    lda #$10                    ; (RD_BANK)
    sta mosTMP+2
    lda #32
    ldx #<[MOSBUF+$80]
    ldy #>[MOSBUF+$80]
    jsr br_dmain
    lda MOSBUF+$80
    beq bl_reun
    lda #0                      ; a file
    sta BR_ENT
    ldx #0
bl_rc:
    lda MOSBUF+$81,x
    beq bl_rce
    sta BR_NAME,x
    inx
    cpx #16
    bne bl_rc
bl_rce:
    stx BR_ENT+1
    jsr bl_add
bl_reun:
    inc br_rdi
    lda br_rdi
    cmp #127
    bne bl_reul
    rts
bl_reupath:
    ldx #5
blr_p:
    lda blr_txt,x
    sta BR_PB,x
    dex
    bpl blr_p
    rts
blr_txt     dta '/REU/', 0

; bl_dotdot: ".." (a folder) as the first entry
bl_dotdot:
    lda #$10
    sta BR_ENT
    lda #2
    sta BR_ENT+1
    lda #'.'
    sta BR_NAME
    sta BR_NAME+1
    ; (fall through)

; bl_add: BR_ENT as entry br_n (unless full), br_n + 1
bl_add:
    lda br_n+1
    cmp #>BR_MAX
    bcc bla_ok
    lda br_n
    cmp #<BR_MAX
    bcs bla_rts
bla_ok:
    lda br_n
    sta br_i
    lda br_n+1
    sta br_i+1
    jsr br_put
    inc br_n
    bne bla_rts
    inc br_n+1
bla_rts:
    rts

; bl_getpath: the Ultimate's current path into BR_PB (to 127 bytes)
bl_getpath:
    lda #TARGET_DOS1
    sta br_tgt
    lda #DOS_GETPATH
    ldx #0
    jsr br_dsend
    lda #<BR_PB
    sta fsADDR
    lda #>BR_PB
    sta fsADDR+1
    lda #127
    sta fsLEN
    lda #0
    sta fsLEN+1
    sta BR_PB
    jsr net.uci_read_to
    ldx fsCNT                   ; 0 ended, trailing 0 bytes dropped
    lda #0
    sta BR_PB,x
    jmp net.uci_finish

; ----------------------------------------------------------------------------
; The command interface (bank 7's copy of the driver, uci.s)
;
; br_target: br_tgt = a DOS target with no open channel (as fs.s's
; fs_free_target); raises 192 when both are open.
br_target:
    lda #TARGET_DOS1
    ldx ch_open
    beq bta_set
    lda #TARGET_DOS2
    ldx ch_open+1
    beq bta_set
    brk
    dta 192, 'Too many open files', 0
bta_set:
    sta br_tgt
    rts

; br_dsend: DOS command A to br_tgt with the payload BR_PAY (X bytes),
; sent; br_dos: and finished: C = 1 failed (errbuf+1 "NN,TEXT"; br_fail).
br_dsend:
    sta uciHDR+1
    lda br_tgt
    sta uciHDR
    lda #2
    sta uciHLEN
    stx fsLEN
    lda #0
    sta fsLEN+1
    lda #<BR_PAY
    sta fsPTR
    lda #>BR_PAY
    sta fsPTR+1
    jmp net.uci_send
br_dos:
    jsr br_dsend
    jsr net.uci_finish
    lda #0
    rol
    sta br_fail
    lsr
    rts

; br_rdopen: OPENDIR (the current folder of br_tgt), READDIR sent: the
; entries follow (br_rdnext); C = 1 the folder cannot be read.
br_rdopen:
    lda #DOS_OPENDIR
    ldx #0
    jsr br_dos
    bcs bro_rts
    lda #0
    sta br_eod
    lda #DOS_READDIR
    ldx #0
    jsr br_dsend
    clc
bro_rts:
    rts

; br_rdnext: the next entry into BR_ENT (the attribute, the name);
; C = 1 none left (then net.uci_finish ends the stream)
br_rdnext:
    lda br_eod
    bne brn_end
    lda UCI_BASE                ; an entry: attribute, then the name
    bpl brn_end
    lda UCI_BASE+2
    and #$7F                    ; (bit 7: the mark)
    sta BR_ENT
    ldx #0
brn_ch:
    lda UCI_BASE
    bpl brn_nend
    lda UCI_BASE+2
    cpx #61
    bcs brn_ch
    sta BR_NAME,x
    inx
    bne brn_ch
brn_nend:
    stx BR_ENT+1
    lda #1
    bit ESCFLG                  ; (ESCAPE: the last one)
    bmi brn_last
    lda UCI_BASE                ; another entry follows?
    and #$30
    cmp #$30
    bne brn_last1
    jsr net.uci_ack
    clc
    rts
brn_last1:
    lda #1
brn_last:
    sta br_eod
    clc
    rts
brn_end:
    sec
    rts

; br_entn: entry br_idx[br_lvl] of the folder BR_PA into BR_ENT; C = 1
; none (the folder has fewer entries)
br_entn:
    jsr br_cdpa
    bcs ben_rts
    jsr br_rdopen
    bcs ben_rts
    lda br_lvl
    asl
    tax
    lda br_idx,x
    sta br_j
    lda br_idx+1,x
    sta br_j+1
ben_l:
    jsr br_rdnext
    bcs ben_none
    lda br_j
    ora br_j+1
    beq ben_got
    lda br_j
    bne ben_d
    dec br_j+1
ben_d:
    dec br_j
    jmp ben_l
ben_got:
    jsr net.uci_finish
    clc
    rts
ben_none:
    jsr net.uci_finish
    sec
ben_rts:
    rts

; Payloads: br_pzero X = 0; br_ppath the path at mosPTR2; br_pname the
; entry's name; br_pnul a 0 byte. Each appends at X (C = 1 too long:
; "Path too long" in errbuf).
br_ppath:
    ldy #0
bpp_l:
    lda (mosPTR2),y
    beq bpp_ok
    jsr br_pch
    bcs bpp_rts
    iny
    bne bpp_l
bpp_ok:
    clc
bpp_rts:
    rts
br_pname:
    ldy #0
bpn_l:
    cpy BR_ENT+1
    bcs bpn_ok
    lda BR_NAME,y
    jsr br_pch
    bcs bpn_rts
    iny
    bne bpn_l
bpn_ok:
    clc
bpn_rts:
    rts
br_pnul:
    lda #0
br_pch:
    cpx #127
    bcs bpc_long
    sta BR_PAY,x
    inx
    clc
    rts
bpc_long:
    ldy #0
bpc_c:
    lda bpc_txt,y
    sta errbuf+1,y
    beq bpc_e
    iny
    bne bpc_c
bpc_e:
    sec
    rts
bpc_txt     dta 'Path too long', 0

; br_setpa / br_setpb: mosPTR2 = BR_PA / BR_PB (X and Y kept: payloads
; are being built in X)
br_setpa:
    lda #<BR_PA
    sta mosPTR2
    lda #>BR_PA
    sta mosPTR2+1
    rts
br_setpb:
    lda #<BR_PB
    sta mosPTR2
    lda #>BR_PB
    sta mosPTR2+1
    rts

; br_cdpa / br_cdpb: CHDIR br_tgt to BR_PA / BR_PB; C = 1 failed
br_cdpa:
    jsr br_setpa
    jmp bcd_go
br_cdpb:
    jsr br_setpb
bcd_go:
    ldx #0
    jsr br_ppath
    bcs bcd_rts
    lda #DOS_CHDIR
    jmp br_dos
bcd_rts:
    rts

; br_dname: DOS command A on the entry's name (the current folder)
br_dname:
    pha
    ldx #0
    jsr br_pname
    pla
    bcs bdn_rts
    jmp br_dos
bdn_rts:
    rts

; br_paadd / br_pbadd: the entry's name and '/' added to BR_PA / BR_PB
; (C = 1 too long, nothing added); br_pacut / br_pbcut: the last folder
; taken off; br_pacut puts that folder's name in BR_ENT.
br_paadd:
    jsr br_setpa
    jmp bpa_go
br_pbadd:
    jsr br_setpb
bpa_go:
    ldy #0
bpa_len:
    lda (mosPTR2),y
    beq bpa_end
    iny
    bne bpa_len
bpa_end:
    tya
    clc
    adc BR_ENT+1
    cmp #BR_PMAX
    bcs bpa_long
    ldx #0
bpa_c:
    cpx BR_ENT+1
    bcs bpa_sl
    lda BR_NAME,x
    sta (mosPTR2),y
    inx
    iny
    bne bpa_c
bpa_sl:
    lda #'/'
    sta (mosPTR2),y
    iny
    lda #0
    sta (mosPTR2),y
    clc
    rts
bpa_long:
    ldx #0
    jsr bpc_long
    sec
    rts
br_pacut:
    jsr br_setpa
    jsr bpc_find
    tya
    pha
    jsr bdel_name               ; (BR_ENT: the folder's name)
    pla
    tay
    lda #0
    sta (mosPTR2),y
    rts
br_pbcut:
    jsr br_setpb
    jsr bpc_find
    lda #0
    sta (mosPTR2),y
    rts
bpc_find:                       ; Y = where the last folder's name starts
    ldy #0
bpcu_l:
    lda (mosPTR2),y
    beq bpcu_e
    iny
    bne bpcu_l
bpcu_e:
    dey                         ; (the '/' at the end)
bpcu_b:
    dey
    beq bpcu_0
    lda (mosPTR2),y
    cmp #'/'
    bne bpcu_b
bpcu_0:
    iny                         ; after the '/' before it
    rts

; br_isreu: Z = 1 when the path at mosPTR2 is /REU/ (any case)
br_isreu:
    ldy #4
bir_l:
    lda (mosPTR2),y
    cmp #'a'
    bcc bir_u
    and #$DF
bir_u:
    cmp blr_txt,y
    bne bir_rts
    dey
    bpl bir_l
    lda #0
bir_rts:
    rts

; ----------------------------------------------------------------------------
; The screen
br_screen:
    lda #12
    jsr OSWRCH
    jsr s6_text
    dta 17, 130, ' U64 BBC BASIC: files                   ', 0
    jsr s6_text
    dta 17, 141, 0
    ldy #1                      ; the bar: the full row
    jsr br_tab0
    ldx #40
bs_sp:
    lda #' '
    jsr OSWRCH
    dex
    bne bs_sp
    lda #31
    jsr OSWRCH
    lda #1
    jsr OSWRCH
    jsr OSWRCH
    ldx #0                      ; the path (its last 38 characters)
    ldy #0
bs_len:
    lda BR_PB,y
    beq bs_lend
    iny
    bne bs_len
bs_lend:
    tya
    sec
    sbc #38
    bcc bs_p
    tax
bs_p:
    lda BR_PB,x
    beq bs_pp
    jsr OSWRCH
    inx
    bne bs_p
bs_pp:
    jsr s6_text
    dta 17, 128, 17, 3, 0
    lda #31                     ; (the rest of the bar: VDU 31 to row 2)
    jsr OSWRCH
    lda #0
    jsr OSWRCH
    lda #2
    jsr OSWRCH
    jsr br_list
    ldy #23                     ; (no 0 bytes inside s6_text's texts:
    jsr br_tab0                 ; it stops at the first; TAB(0,y) here)
    jsr s6_text
    dta 17, 6, 'RET', 17, 3, ' open ', 17, 6, 'L', 17, 3, 'ist '
    dta 17, 6, 'D', 17, 3, 'el ', 17, 6, 'R', 17, 3, 'ename ', 17, 6, 'N', 17, 3, 'ew dir '
    dta 17, 6, 'P U T E', 0
    ldy #24
    jsr br_tab0
    jsr s6_text
    dta 17, 6, 'SPACE', 17, 3, ' mark ', 17, 6, 'C', 17, 3, 'opy '
    dta 17, 6, 'X', 17, 3, ' cut ', 17, 6, 'V', 17, 3, ' paste ', 17, 6, '/', 17, 3, ' ', 17, 6, 'Q', 17, 3, 'uit', 0
    rts

; br_tab0: the text cursor to column 0, row Y.  Uses: A.
br_tab0:
    lda #31
    jsr OSWRCH
    lda #0
    jsr OSWRCH
    tya
    jmp OSWRCH

; br_bar: the status bar (row 22) cleared in its colours (white on red),
; the text cursor at its start.  Uses: A, Y.
br_bar:
    ldy #22
    jsr br_tab0
    jsr s6_text
    dta 17, 129, 17, 7, 0
    ldy #40                     ; (the full row: only the last row scrolls)
bb_sp:
    lda #' '
    jsr OSWRCH
    dey
    bne bb_sp
    ldy #22
    jmp br_tab0

; br_barname: the status bar with the entry's name after a space
br_barname:
    jsr br_bar
    lda #' '
    jsr OSWRCH
    ldx #0
bbn_l:
    cpx BR_ENT+1
    bcs bbn_e
    lda BR_NAME,x
    jsr OSWRCH
    inx
    cpx #20
    bcc bbn_l
bbn_e:
    rts

; br_list: the 20 rows from br_top (the selected one reversed)
br_list:
    lda #0
    sta br_row
    lda br_top
    sta br_i
    lda br_top+1
    sta br_i+1
bli_row:
    jsr br_row1
    inc br_i
    bne bli_n
    inc br_i+1
bli_n:
    inc br_row
    lda br_row
    cmp #BR_ROWS
    bne bli_row
    rts

; br_row1: entry br_i at its row (br_row): blank past the end; a marked
; one with '*' in front
br_row1:
    lda #31
    jsr OSWRCH
    lda #0
    jsr OSWRCH
    lda br_row
    clc
    adc #BR_ROW0
    jsr OSWRCH
    lda br_i                    ; past the end: a blank row
    cmp br_n
    lda br_i+1
    sbc br_n+1
    bcc br1_ent
    ldx #40
br1_bl:
    lda #' '
    jsr OSWRCH
    dex
    bne br1_bl
    rts
br1_ent:
    jsr br_get                  ; -> BR_ENT
    lda br_i                    ; selected: reversed (COLOUR 128+3)
    cmp br_sel
    bne br1_norm
    lda br_i+1
    cmp br_sel+1
    bne br1_norm
    lda #17                     ; reversed: background 3, text 0
    jsr OSWRCH
    lda #131
    jsr OSWRCH
    lda #17
    jsr OSWRCH
    lda #0
    jsr OSWRCH
    jmp br1_name
br1_norm:
    jsr s6_text
    dta 17, 128, 17, 3, 0
    lda BR_ENT                  ; folders cyan
    and #$10
    beq br1_name
    jsr s6_text
    dta 17, 6, 0
br1_name:
    lda #' '
    bit BR_ENT
    bpl br1_nm
    lda #'*'
br1_nm:
    jsr OSWRCH
    ldx #0
    ldy #38
br1_c:
    cpx BR_ENT+1
    bcs br1_dir
    lda BR_NAME,x
    jsr OSWRCH
    inx
    dey
    cpx #36
    bcc br1_c
br1_dir:
    lda BR_ENT
    and #$10
    beq br1_pad
    lda #'/'
    jsr OSWRCH
    dey
br1_pad:
    lda #' '
    jsr OSWRCH
    dey
    bpl br1_pad
    jsr s6_text
    dta 17, 128, 17, 3, 0
    rts

; br_status: the selected entry: its kind and size (row 22); the marks
; and the clipboard on the right
br_status:
    jsr br_bar
    lda br_n
    ora br_n+1
    bne bst_some
    jsr s6_text
    dta ' (empty)', 0
    jmp bst_pad
bst_some:
    jsr br_getsel
    lda BR_ENT
    and #$10
    beq bst_file
    jsr s6_text
    dta ' folder', 0
    jmp bst_pad
bst_file:
    jsr br_size                 ; mosTMP = its length (16 bits), C = 1:
    bcs bst_nosz                ; unknown
    jsr s6_text
    dta ' ', 0
    farcall st_dec16, BANK_FS   ; (to 65535)
    jsr s6_text
    dta ' bytes', 0
    jmp bst_pad
bst_nosz:
    jsr s6_text
    dta ' file', 0
bst_pad:
    lda br_nm                   ; "n marked"
    ora br_nm+1
    beq bst_clip
    lda #31
    jsr OSWRCH
    lda #17
    jsr OSWRCH
    lda #22
    jsr OSWRCH
    lda br_nm
    sta mosTMP
    lda br_nm+1
    sta mosTMP+1
    farcall st_dec16, BANK_FS
    jsr s6_text
    dta ' marked', 0
bst_clip:
    lda br_cn                   ; "n to paste"
    beq bst_end
    lda #31
    jsr OSWRCH
    lda #28
    jsr OSWRCH
    lda #22
    jsr OSWRCH
    lda br_cn
    sta mosTMP
    lda #0
    sta mosTMP+1
    farcall st_dec16, BANK_FS
    jsr s6_text
    dta ' to paste', 0
bst_end:
    jsr s6_text
    dta 17, 128, 17, 3, 0
    rts

; br_size: the selected file's length (OSFILE 5) in mosTMP (16 bits;
; 65535 when more); C = 1 when it cannot be read
br_size:
    jsr br_cmdname              ; the name at BR_CMD, CR ended
    lda #<BR_CMD                ; the OSFILE block at &0640
    sta $0640
    lda #>BR_CMD
    sta $0641
    lda #<bsz_call
    ldx #>bsz_call
    jsr br_guard
    bcs bsz_no
    lda br_x
    cmp #1
    bcc bsz_no
    lda $064C                   ; the length's high bytes
    ora $064D
    beq bsz_ok
    lda #$FF
    sta $064A
    sta $064B
bsz_ok:
    lda $064A
    sta mosTMP
    lda $064B
    sta mosTMP+1
    clc
    rts
bsz_no:
    sec
    rts
bsz_call:
    lda #5
    ldx #<$0640
    ldy #>$0640
    jsr OSFILE
    sta br_x
    rts

; br_cmdname: the selected entry's name at BR_CMD, CR ended; X = length
br_cmdname:
    ldx #0
; br_cmdput: the name after the X bytes already at BR_CMD, CR ended
br_cmdput:
    ldy #0
bcn_l:
    cpy BR_ENT+1
    bcs bcn_end
    lda BR_NAME,y
    sta BR_CMD,x
    inx
    iny
    bne bcn_l
bcn_end:
    lda #13
    sta BR_CMD,x
    rts
; br_cmdword: the text at A/Y (0 ended) at BR_CMD; X = its length
br_cmdword:
    sta mosPTR2
    sty mosPTR2+1
    ldy #0
bcw_l:
    lda (mosPTR2),y
    beq bcw_e
    sta BR_CMD,y
    iny
    bne bcw_l
bcw_e:
    tya
    tax
    rts

; ----------------------------------------------------------------------------
; Moving the selection: br_down / br_up one entry (nothing at the ends);
; the window scrolls to keep it in view, else the old and the new row are
; drawn again. Keep X.
br_down:
    lda br_sel                  ; the last? nothing
    clc
    adc #1
    sta br_i
    lda br_sel+1
    adc #0
    sta br_i+1
    lda br_i
    cmp br_n
    lda br_i+1
    sbc br_n+1
    bcc bm_go
    rts
br_up:
    lda br_sel
    ora br_sel+1
    bne bu_go
    rts
bu_go:
    lda br_sel
    sec
    sbc #1
    sta br_i
    lda br_sel+1
    sbc #0
    sta br_i+1
bm_go:
    txa
    pha
    lda br_sel                  ; the old one kept, the new one selected
    sta br_old
    lda br_sel+1
    sta br_old+1
    lda br_i
    sta br_sel
    lda br_i+1
    sta br_sel+1
    lda br_sel                  ; above the window: it starts there
    cmp br_top
    lda br_sel+1
    sbc br_top+1
    bcs bm_below
    lda br_sel
    sta br_top
    lda br_sel+1
    sta br_top+1
    jmp bm_list
bm_below:
    lda br_sel                  ; below it: one further
    sec
    sbc br_top
    tax
    lda br_sel+1
    sbc br_top+1
    bne bm_scroll
    cpx #BR_ROWS
    bcc bm_rows
bm_scroll:
    inc br_top
    bne bm_list
    inc br_top+1
bm_list:
    jsr br_list
    jmp bm_rts
bm_rows:
    lda br_old                  ; the old row, then the new one
    sta br_i
    lda br_old+1
    sta br_i+1
    jsr br_rowof
    lda br_sel
    sta br_i
    lda br_sel+1
    sta br_i+1
    jsr br_rowof
bm_rts:
    pla
    tax
    rts
; br_rowof: entry br_i drawn at its row in the window
br_rowof:
    lda br_i
    sec
    sbc br_top
    sta br_row
    jmp br_row1

; br_getsel: the selected entry in BR_ENT (br_i = br_sel)
br_getsel:
    lda br_sel
    sta br_i
    lda br_sel+1
    sta br_i+1
    jmp br_get

; ----------------------------------------------------------------------------
; br_mark
;   Summary: SPACE: the selected entry marked or unmarked, then the next
;            one selected. Not ".." and not the drives at the root.
;   Output:  C = 0 (the rows drawn here).
br_mark:
    lda br_n
    ora br_n+1
    beq bmk_rts
    lda br_root
    bne bmk_rts
    jsr br_getsel
    jsr br_isdots
    beq bmk_rts
    lda BR_ENT
    eor #$80
    sta BR_ENT
    bmi bmk_inc
    lda br_nm                   ; one fewer
    bne bmk_d
    dec br_nm+1
bmk_d:
    dec br_nm
    jmp bmk_put
bmk_inc:
    inc br_nm
    bne bmk_put
    inc br_nm+1
bmk_put:
    jsr br_put
    jsr br_rowof
    jsr br_down
bmk_rts:
    clc
    rts

; br_isdots: Z = 1 when BR_ENT is ".."
br_isdots:
    lda BR_ENT+1
    cmp #2
    bne bid_rts
    lda BR_NAME
    cmp #'.'
    bne bid_rts
    lda BR_NAME+1
    cmp #'.'
bid_rts:
    rts

; br_each: the next entry acted on, from br_j on: the marked ones, or
; the selected one when none is marked (not ".."). C = 0: BR_ENT, br_j
; one after it; C = 1: no more. br_each0 starts at the first.
br_each0:
    lda #0
    sta br_j
    sta br_j+1
br_each:
    lda br_j
    cmp br_n
    lda br_j+1
    sbc br_n+1
    bcs bea_rts                 ; (C = 1: the end)
    lda br_j
    sta br_i
    lda br_j+1
    sta br_i+1
    inc br_j
    bne bea_get
    inc br_j+1
bea_get:
    jsr br_get
    jsr br_isdots
    beq br_each
    lda br_nm
    ora br_nm+1
    beq bea_sel
    bit BR_ENT                  ; marked?
    bpl br_each
    clc
    rts
bea_sel:
    lda br_i                    ; the selected one
    cmp br_sel
    bne br_each
    lda br_i+1
    cmp br_sel+1
    bne br_each
    clc
bea_rts:
    rts

; ----------------------------------------------------------------------------
; br_open
;   Summary: RETURN on the selected entry (see the top).
;   Output:  C = 1: the screen to draw again (the listing may be new).
br_open:
    lda br_n
    ora br_n+1
    bne bo_some
    clc
    rts
bo_some:
    jsr br_getsel
    lda BR_ENT
    and #$10
    beq bo_file
bo_folder:
    lda #<bo_dir                ; a folder: entered
    ldx #>bo_dir
    jsr br_guard
    bcc bo_dok
    jsr br_err
bo_dok:
    lda #<br_load
    ldx #>br_load
    jsr br_guard
    sec
    rts
bo_file:
    jsr br_ext                  ; A = the type (0: none)
    cmp #0
    bne bo_typed
    jmp br_chain
bo_typed:
    sta br_attr                 ; (kept for br_after: MOSBUF goes)
    asl                         ; the command for it
    tax
    lda bo_tab-2,x
    sta mosPTR2
    lda bo_tab-1,x
    sta mosPTR2+1
    ldy #0                      ; "XXXX " then the name (then a tail)
    ldx #0
bot_c:
    lda (mosPTR2),y
    beq bot_n
    sta BR_CMD,x
    inx
    iny
    bne bot_c
bot_n:
    iny
    sty br_len                  ; (the tail follows the 0)
    jsr br_cmdput
    ldy br_len                  ; the tail: " ..." then 0
    lda (mosPTR2),y
    beq bot_go
bot_t:
    lda (mosPTR2),y
    beq bot_te
    sta BR_CMD,x
    inx
    iny
    bne bot_t
bot_te:
    lda #13
    sta BR_CMD,x
bot_go:
    jsr br_try
    bcc bot_after
    jsr br_err
    jmp bot_load
bot_after:
    lda #<br_after              ; after: .WAV played, .UPIC shown
    ldx #>br_after
    jsr br_guard
bot_load:
    jmp br_reload

; the types: 1 SEQ, 2 MOD, 3 WAV, 4 D64/D71/D81/G64, 5 UPIC, 6 VPL,
; 7 others (*TYPE)
bo_tab      dta a(bo_seq), a(bo_mod), a(bo_wav), a(bo_d64), a(bo_upic)
            dta a(bo_vpl), a(bo_type)
bo_seq      dta 'SEQ ', 0, 0
bo_mod      dta 'MODPLAY ', 0, 0
bo_wav      dta 'SAMPLE LOAD 32 ', 0, 0
bo_d64      dta 'MOUNT ', 0, 0
bo_upic     dta 'UPIC LOAD ', 0, 0
bo_vpl      dta 'PALETTE LOAD ', 0, ' VPL', 0
bo_type     dta 'TYPE ', 0, 0

; bo_dir: into the folder BR_ENT: "*DIR /REU" from the root, "*DIR /"
; for ".." on /REU (the root: /REU is one of its drives); otherwise DOS
; CHDIR to the name ("..", or a name, spaces too) on both targets, as
; *DIR does
bo_dir:
    lda reu_cwd
    beq bod_ult
    lda #<bod_root
    ldy #>bod_root
    bne bod_cli
bod_ult:
    lda br_root
    beq bod_cd
    lda BR_NAME
    cmp #'R'
    bne bod_cd
    lda BR_ENT+1
    cmp #3
    bne bod_cd
    lda #<bod_reu
    ldy #>bod_reu
bod_cli:
    jsr br_cmdword
    lda #13
    sta BR_CMD,x
    jmp bt_cli
bod_cd:
    lda #TARGET_DOS1
    jsr bod_one
    lda #TARGET_DOS2
bod_one:
    sta br_tgt
    lda #DOS_CHDIR
    jsr br_dname
    bcc bod_rts
    brk                         ; (shown by br_open)
    dta 214, 'No such folder', 0
bod_rts:
    rts
bod_root    dta 'DIR /', 0
bod_reu     dta 'DIR /REU', 0

; br_reload: the listing read again, the selection kept where it can be
; (C = 1: the screen to draw again)
br_reload:
    lda br_sel
    pha
    lda br_sel+1
    pha
    lda br_top
    pha
    lda br_top+1
    pha
    lda #<br_load
    ldx #>br_load
    jsr br_guard
    pla
    sta br_top+1
    pla
    sta br_top
    pla
    sta br_sel+1
    pla
    sta br_sel
    cmp br_n                    ; (past the end now: the first)
    lda br_sel+1
    sbc br_n+1
    bcc brl_rts
    jsr bl_top0
brl_rts:
    sec
    rts

; br_after: what follows a typed command: a sample is played (SOUND
; 30,32,53,0 through OSWORD 7), a Upic picture shown (*UPIC SHOW), a
; text waits for a key
br_after:
    lda br_attr
    cmp #3
    bne baf_upic
    ldx #7                      ; the OSWORD 7 block at &0640
baf_b:
    lda baf_snd,x
    sta $0640,x
    dex
    bpl baf_b
    lda #7
    ldx #<$0640
    ldy #>$0640
    jmp OSWORD
baf_upic:
    cmp #5
    bne baf_type
    lda #<baf_show
    ldy #>baf_show
    jsr br_cmdword
    lda #13
    sta BR_CMD,x
    jmp bt_cli
baf_type:
    cmp #7
    bne baf_rts
    jmp br_waitkey
baf_rts:
    rts
baf_snd     dta 30, 0, 32, 0, 53, 0, 0, 0
baf_show    dta 'UPIC SHOW', 0

; br_ext: A = the selected entry's type by its extension (bo_tab), 0 for
; a name without '.' (a BASIC program)
br_ext:
    ldx BR_ENT+1                ; the last '.'
bx_find:
    dex
    bmi bx_none
    lda BR_NAME,x
    cmp #'.'
    bne bx_find
    inx                         ; the extension (upper case) -> mosTMP
    ldy #0
bx_cp:
    cpx BR_ENT+1
    bcs bx_end
    lda BR_NAME,x
    cmp #'a'
    bcc bx_up
    and #$DF
bx_up:
    sta mosTMP,y
    inx
    iny
    cpy #4
    bcc bx_cp
bx_end:
    lda #0                      ; (to 4, 0 padded)
bx_pad:
    cpy #4
    bcs bx_cmp
    sta mosTMP,y
    iny
    bne bx_pad
bx_cmp:
    ldx #0                      ; the table: 4 bytes and the type each
bx_t:
    lda bx_tab+4,x
    beq bx_other
    ldy #0
bx_tc:
    lda bx_tab,x
    cmp mosTMP,y
    bne bx_tnext
    inx
    iny
    cpy #4
    bne bx_tc
    lda bx_tab,x                ; (the type after the 4 bytes)
    rts
bx_tnext:
    txa                         ; the next entry: (X - Y) + 5
    sty mosNUM
    sec
    sbc mosNUM
    clc
    adc #5
    tax
    bne bx_t
bx_other:
    lda #7
    rts
bx_none:
    lda #0
    rts
bx_tab      dta 'SEQ', 0, 1, 'MOD', 0, 2, 'WAV', 0, 3, 'D64', 0, 4
            dta 'D71', 0, 4, 'D81', 0, 4, 'G64', 0, 4, 'UPIC', 5
            dta 'VPL', 0, 6, 0, 0, 0, 0, 0

; ----------------------------------------------------------------------------
; br_chain: a BASIC program: the browser ends and CHAIN "name" is typed
; (*KEY slot 9 in the REU, which no C64 key reaches, the expansion
; started as an F-key's: keys.s). Reached by a jmp from br_open, itself
; jumped to by bw_jmp: its return dropped, the browser ends here.
br_chain:
    ldx #0
bc_c:
    lda bc_txt,x
    beq bc_name
    sta BR_CMD+1,x              ; (+0: the length, as a *KEY slot)
    inx
    bne bc_c
bc_name:
    inx                         ; (X: the next position after the length)
    jsr br_cmdput               ; the name, CR (at BR_CMD+X)
    lda #'"'                    ; the closing quote over the CR, then CR
    sta BR_CMD,x
    lda #13
    sta BR_CMD+1,x
    inx                         ; the length: X - 1 + 1
    stx BR_CMD
    lda #<[REU_KEYS+9*64]       ; slot 9: REU bank 0
    sta mosTMP
    lda #>[REU_KEYS+9*64]
    sta mosTMP+1
    lda #0
    sta mosTMP+2
    lda #64
    ldx #<BR_CMD
    ldy #>BR_CMD
    jsr br_dmaout
    lda #9                      ; the expansion: key 9, from the start
    sta kx_key
    lda #0
    sta kx_pos
    lda BR_CMD
    sta kx_n
    pla                         ; (bw_jmp's return: br_open was jumped
    pla                         ; to)
    jmp br_quit
bc_txt      dta 'CHAIN "', 0

; ----------------------------------------------------------------------------
; T: *TYPE the selected file
br_type:
    jsr br_getsel
    lda BR_ENT
    and #$10
    bne bty_rts
    lda #<bty_txt
    ldy #>bty_txt
    jsr br_cmdword
    jsr br_cmdput
    lda #12
    jsr OSWRCH
    jsr br_try
    bcc bty_w
    jsr br_err
    sec
    rts
bty_w:
    jsr br_waitkey
    sec
    rts
bty_rts:
    clc
    rts
bty_txt     dta 'TYPE ', 0

; br_waitkey: "Press a key", then one
br_waitkey:
    jsr s6_text
    dta 13, 10, 17, 6, 'Press a key', 17, 3, 0
    jmp br_key1

; br_yn: the question in the status bar (A/Y, 0 ended, after what is
; there), then a key: Z = 1 for Y.  Uses: A, X, Y.
br_yn:
    sta mosPTR2
    sty mosPTR2+1
    ldy #0
byn_l:
    lda (mosPTR2),y
    beq byn_k
    jsr OSWRCH
    iny
    bne byn_l
byn_k:
    jsr br_key1
    and #$DF
    sta br_ans
    cmp #'Y'
    rts

; ----------------------------------------------------------------------------
; R: rename the selected entry (DOS RENAME on the Ultimate's drives: any
; name; *RENAME on /REU)
br_rename:
    lda br_n
    ora br_n+1
    beq brn_none
    lda br_root
    bne brn_none
    jsr br_getsel
    jsr br_isdots
    bne brn_go
brn_none:
    clc
    rts
brn_go:
    jsr br_bar
    jsr s6_text
    dta ' New name: ', 0
    jsr br_input                ; the name at BR_PA, br_len
    bcs brn_none
    lda reu_cwd
    bne brn_reu
    ldx #0                      ; old, 0, new (the current folder)
    jsr br_pname
    jsr br_pnul
    ldy #0
brn_n:
    lda BR_PA,y
    jsr br_pch
    iny
    cpy br_len
    bne brn_n
    stx br_x
    lda #<brn_dos
    ldx #>brn_dos
    jsr br_guard
    bcs brn_err
    lda br_fail
    beq brn_done
brn_err:
    jsr br_err
brn_done:
    jmp br_reload
brn_dos:
    jsr br_target
    lda #DOS_RENAME
    ldx br_x
    jmp br_dos
brn_reu:
    lda #<brn_txt               ; *RENAME old new
    ldy #>brn_txt
    jsr br_cmdword
    jsr br_cmdput
    lda #' '
    sta BR_CMD,x
    inx
    ldy #0
brn_c:
    lda BR_PA,y
    sta BR_CMD,x
    inx
    iny
    cpy br_len
    bne brn_c
    lda #13
    sta BR_CMD,x
    jsr br_try
    bcs brn_err
    bcc brn_done
brn_txt     dta 'RENAME ', 0

; br_input: a line from the keyboard (OSWORD 0) at BR_PA, 60 at most:
; br_len; C = 1 none (empty or ESCAPE)
br_input:
    lda #<BR_PA
    sta BR_OSW
    lda #>BR_PA
    sta BR_OSW+1
    lda #60
    sta BR_OSW+2
    lda #32
    sta BR_OSW+3
    lda #126
    sta BR_OSW+4
    jsr br_curs1
    lda #0
    ldx #<BR_OSW
    ldy #>BR_OSW
    jsr OSWORD
    php
    sty br_len
    jsr br_curs0
    plp
    bcs bin_esc
    lda br_len
    beq bin_no
    clc
    rts
bin_esc:
    lda #$7E
    jsr OSBYTE
bin_no:
    sec
    rts

; ----------------------------------------------------------------------------
; N: a new folder in the one shown (not at the root, not on /REU)
br_newdir:
    lda br_root
    ora reu_cwd
    bne bnd_no
    jsr br_bar
    jsr s6_text
    dta ' New folder: ', 0
    jsr br_input
    bcs bnd_no
    ldx #0                      ; the folder shown, then the name
    jsr br_setpb
    jsr br_ppath
    ldy #0
bnd_n:
    lda BR_PA,y
    jsr br_pch
    bcs bnd_err
    iny
    cpy br_len
    bne bnd_n
    stx br_x
    lda #<bnd_dos
    ldx #>bnd_dos
    jsr br_guard
    bcs bnd_err
    lda br_fail
    beq bnd_done
bnd_err:
    jsr br_err
bnd_done:
    jmp br_reload
bnd_no:
    clc
    rts
bnd_dos:
    jsr br_target
    lda #DOS_MKDIR
    ldx br_x
    jmp br_dos

; ----------------------------------------------------------------------------
; D: delete the marked entries (or the selected one), after a question;
; a folder that is not empty asks again (Y/N/All/Quit), then goes with
; everything in it (br_del)
br_delete:
    lda br_root
    bne bdl_no0
    jsr br_each0
    bcc bdl_ask
bdl_no0:
    clc
    rts
bdl_ask:
    jsr br_bar
    jsr s6_text
    dta ' Delete ', 0
    lda br_nm
    ora br_nm+1
    bne bdl_n
    ldx #0                      ; the name
bdl_nm:
    cpx BR_ENT+1
    bcs bdl_q
    lda BR_NAME,x
    jsr OSWRCH
    inx
    cpx #20
    bcc bdl_nm
    bcs bdl_q
bdl_n:
    lda br_nm
    sta mosTMP
    lda br_nm+1
    sta mosTMP+1
    farcall st_dec16, BANK_FS
    jsr s6_text
    dta ' marked', 0
bdl_q:
    lda #<bdl_yn
    ldy #>bdl_yn
    jsr br_yn
    bne bdl_none
    lda #0
    sta br_all
    sta br_quitf
    lda #<bdl_walk
    ldx #>bdl_walk
    jsr br_guard
    bcc bdl_done
    jsr br_err
bdl_done:
    jsr br_escack
    lda #<bdl_back              ; (the folder shown again)
    ldx #>bdl_back
    jsr br_guard
    jmp br_reload
bdl_none:
    clc
    rts
bdl_yn      dta '? (Y/N)', 0
bdl_back:
    lda reu_cwd
    bne bdb_rts
    jsr br_target
    jmp br_cdpb
bdb_rts:
    rts

; bdl_walk: each entry acted on deleted (on /REU: *DELETE)
bdl_walk:
    lda reu_cwd
    bne bdw_reu
    jsr br_target
    ldx #127                    ; the source path: the folder shown
bdw_cp:
    lda BR_PB,x
    sta BR_PA,x
    dex
    bpl bdw_cp
    lda #0
    sta br_lvl
    jsr br_each0
bdw_l:
    bcs bdw_rts
    lda br_j                    ; (br_del reads other entries)
    pha
    lda br_j+1
    pha
    jsr br_del
    pla
    sta br_j+1
    pla
    sta br_j
    lda br_quitf
    bne bdw_rts
    jsr br_each
    jmp bdw_l
bdw_rts:
    rts
bdw_reu:
    jsr br_each0
bdw_rl:
    bcs bdw_rts
    lda #<bdl_txt
    ldy #>bdl_txt
    jsr br_cmdword
    jsr br_cmdput
    jsr br_try
    bcc bdw_rn
    jsr br_err
bdw_rn:
    jsr br_each
    jmp bdw_rl
bdl_txt     dta 'DELETE ', 0

; br_del
;   Summary: delete the entry BR_ENT of the folder BR_PA (br_tgt), a
;            folder with everything in it.
;   Function: a file: CHDIR, DELETE. A folder: into it (BR_PA, a level
;            deeper); at the first level, if it is not empty, the question
;            (Y/N/All/Quit); then its first entry deleted while there is
;            one (recursively); back up; the folder deleted. A failure is
;            shown and ends the walk (br_quitf): it would come back.
;   Input:   BR_ENT, BR_PA, br_lvl, br_all.
;   Output:  br_quitf.  Uses: A, X, Y, BR_ENT, BR_PAY, the paths.
br_del:
    lda BR_ENT
    and #$10
    bne bdel_dir
    jsr br_barname
    jsr br_cdpa
    bcs bdel_fail
    lda #DOS_DELETE
    jsr br_dname
    bcc bdel_rts
bdel_fail:
    jsr br_err
    lda #1
    sta br_quitf
bdel_rts:
    rts
bdel_dir:
    lda br_lvl
    cmp #BR_DEPTH
    bcc bdel_deep
    jsr bdel_long               ; ("Too deep")
    jmp bdel_fail
bdel_deep:
    jsr br_paadd
    bcs bdel_fail
    inc br_lvl
    lda br_lvl                  ; entry 0 at this level
    asl
    tax
    lda #0
    sta br_idx,x
    sta br_idx+1,x
    lda br_lvl                  ; the first level: not empty? ask
    cmp #1
    bne bdel_loop
    lda br_all
    bne bdel_loop
    jsr br_entn
    bcs bdel_loop               ; (empty)
    jsr bdel_ask
    lda br_ans
    cmp #'A'
    bne bdel_n
    sta br_all
    bne bdel_loop
bdel_n:
    cmp #'Y'
    beq bdel_loop
    cmp #'Q'
    bne bdel_up
    sta br_quitf
    bne bdel_up
bdel_loop:
    jsr br_entn                 ; the first entry left
    bcs bdel_empty
    jsr br_del
    lda br_quitf
    bne bdel_up
    bit ESCFLG
    bpl bdel_loop
bdel_empty:
    jsr br_pacut                ; up, the folder's name taken back
    jsr br_cdpa
    bcs bdel_up2
    lda #DOS_DELETE
    jsr br_dname
    bcc bdel_up2
    dec br_lvl
    jmp bdel_fail
bdel_up:
    jsr br_pacut
bdel_up2:
    dec br_lvl
    rts
; bdel_name: BR_ENT's name = the path's piece cut off (BR_PA+Y to '/')
bdel_name:
    ldx #0
bdn_c:
    lda BR_PA,y
    cmp #'/'
    beq bdn_e
    sta BR_NAME,x
    inx
    iny
    bne bdn_c
bdn_e:
    stx BR_ENT+1
    lda #$10
    sta BR_ENT
    rts
; bdel_ask: "<name>/ is not empty: delete all?" (the folder's name: the
; last piece of BR_PA)
bdel_ask:
    jsr br_bar
    jsr s6_text
    dta ' Not empty: delete everything? (Y/N/A/Q)', 0
    jsr br_key1
    and #$DF
    sta br_ans
    rts
bdel_long:
    ldy #0
bdl_c:
    lda bdl_deep,y
    sta errbuf+1,y
    beq bdl_e
    iny
    bne bdl_c
bdl_e:
    rts
bdl_deep    dta 'Folders too deep (8 levels)', 0

; ----------------------------------------------------------------------------
; C, X: the marked entries (or the selected one) to the clipboard, to be
; copied or moved by P
br_copy:
    lda #1
    bne bcp_go
br_cut:
    lda #2
bcp_go:
    sta br_op
    lda br_root
    bne bcp_none
    lda #0
    sta br_cn
    jsr br_each0
bcp_l:
    bcs bcp_end
    lda br_cn                   ; entry -> BR_CLENT + n * 64
    cmp #BR_CLMAX
    bcs bcp_end
    jsr br_clad
    lda #64
    ldx #<BR_ENT
    ldy #>BR_ENT
    jsr br_dmaout
    inc br_cn
    jsr br_each
    jmp bcp_l
bcp_end:
    lda #<BR_CLIP               ; the source: the folder shown
    sta mosTMP
    lda #>BR_CLIP
    sta mosTMP+1
    lda #0
    sta mosTMP+2
    lda #128
    ldx #<BR_PB
    ldy #>BR_PB
    jsr br_dmaout
    lda br_cn
    bne bcp_unmark
bcp_none:
    lda #0
    sta br_cn
    clc
    rts
bcp_unmark:
    jmp br_reload               ; (the marks gone)

; br_clad: mosTMP = the clipboard's entry br_cn (A) in the REU
br_clad:
    lsr
    sta mosTMP+1
    lda #0
    ror
    lsr mosTMP+1
    ror
    sta mosTMP
    lda mosTMP+1
    clc
    adc #>BR_CLENT
    sta mosTMP+1
    lda #0
    sta mosTMP+2
    rts

; ----------------------------------------------------------------------------
; P: the clipboard pasted into the folder shown (br_tr for each entry;
; /REU through *COPY): copied, or moved for X
br_paste:
    lda br_cn
    beq bps_no
    lda br_root
    bne bps_no
    lda #<BR_CLIP               ; the source path -> BR_PA
    sta mosTMP
    lda #>BR_CLIP
    sta mosTMP+1
    lda #0
    sta mosTMP+2
    lda #128
    ldx #<BR_PA
    ldy #>BR_PA
    jsr br_dmain
    ldx #0                      ; the same folder: nothing to do
bps_cmp:
    lda BR_PA,x
    cmp BR_PB,x
    bne bps_go
    inx
    cmp #0
    bne bps_cmp
    jsr br_bar
    jsr s6_text
    dta ' That is the same folder', 0
    jsr br_key1
bps_no:
    clc
    rts
bps_go:
    lda #0
    sta br_all
    sta br_quitf
    sta br_lvl
    lda #<bps_walk
    ldx #>bps_walk
    jsr br_guard
    bcc bps_done
    jsr br_err
bps_done:
    jsr br_escack
    lda br_op                   ; a move: the clipboard used up
    cmp #2
    bne bps_back
    lda #0
    sta br_cn
bps_back:
    lda #<bdl_back
    ldx #>bdl_back
    jsr br_guard
    jmp br_reload

; bps_walk: each clipboard entry: into /REU, out of /REU, or between the
; Ultimate's folders (br_tr)
bps_walk:
    jsr br_target
    ldx #0                      ; one drive: the paths agree to the
bpw_dr:                         ; second '/'
    lda BR_PA,x
    cmp BR_PB,x
    bne bpw_two
    inx
    cmp #'/'
    bne bpw_dr
    cpx #1
    beq bpw_dr
    lda #1
    bne bpw_one
bpw_two:
    lda #0
bpw_one:
    sta br_same
    lda #0
    sta br_k
bpw_l:
    lda br_k
    cmp br_cn
    bcs bpw_rts
    jsr br_clad
    lda #64
    ldx #<BR_ENT
    ldy #>BR_ENT
    jsr br_dmain
    jsr br_barname
    jsr br_setpb
    jsr br_isreu
    bne bpw_npb
    jsr bpw_toreu
    jmp bpw_next
bpw_npb:
    jsr br_setpa
    jsr br_isreu
    bne bpw_ult
    jsr bpw_fromreu
    jmp bpw_next
bpw_ult:
    lda #0
    sta br_lvl
    jsr br_tr
bpw_next:
    lda br_quitf
    bne bpw_rts
    bit ESCFLG
    bmi bpw_rts
    inc br_k
    bne bpw_l
bpw_rts:
    rts

; bpw_toreu: a file into /REU: *COPY <source path><name> /REU (a folder
; refused); a name there asks first (*DELETE then); a move deletes the
; source (DOS)
bpw_toreu:
    lda BR_ENT
    and #$10
    beq btr_file
    ldy #0
btr_m:
    lda btr_nofold,y
    sta errbuf+1,y
    beq btr_e
    iny
    bne btr_m
btr_e:
    jmp br_err
btr_file:
    jsr br_find                 ; there already?
    bcs btr_copy
    jsr br_ask
    bne btr_rts
    jsr br_cl2ent               ; (BR_ENT again: br_find used it)
    lda #<bdl_txt               ; *DELETE name (the current folder: /REU)
    ldy #>bdl_txt
    jsr br_cmdword
    jsr br_cmdput
    jsr br_try
    bcs btr_err
btr_copy:
    jsr br_cl2ent
    lda #<bcy_txt               ; *COPY <path><name> /REU
    ldy #>bcy_txt
    jsr br_cmdword
    jsr bcy_path
    jsr br_cmdput
    ldy #0
btr_t:
    lda btr_reu,y
    sta BR_CMD,x
    inx
    iny
    cpy #6
    bne btr_t
    jsr br_try
    bcs btr_err
    lda br_op                   ; a move: the source deleted
    cmp #2
    bne btr_rts
    jsr br_cl2ent
    jsr br_cdpa
    bcs btr_err2
    lda #DOS_DELETE
    jsr br_dname
    bcc btr_rts
btr_err2:
btr_err:
    jmp br_err
btr_rts:
    rts
btr_reu     dta ' /REU', 13
btr_nofold  dta 'No folders on /REU', 0
bcy_txt     dta 'COPY ', 0
; bcy_path: BR_PA (the source path) after the X bytes at BR_CMD
bcy_path:
    ldy #0
bcyp_l:
    lda BR_PA,y
    beq bcyp_e
    sta BR_CMD,x
    inx
    iny
    cpx #100
    bcc bcyp_l
bcyp_e:
    rts

; bpw_fromreu: a /REU file into the folder shown: *COPY /REU/<name>
; <path> (a name there asks first: DOS DELETE then); a move deletes the
; /REU file (*DELETE /REU/<name>)
bpw_fromreu:
    jsr br_find
    bcs bfr_copy
    jsr br_ask
    bne bfr_rts
    jsr br_cl2ent
    jsr br_cdpb
    bcs bfr_err
    lda #DOS_DELETE
    jsr br_dname
    bcs bfr_err
bfr_copy:
    jsr br_cl2ent
    lda #<bcy_txt
    ldy #>bcy_txt
    jsr br_cmdword
    jsr bcy_path                ; ("/REU/")
    jsr br_cmdput
    lda #' '
    sta BR_CMD,x
    inx
    ldy #0                      ; the target, without its last '/'
bfr_p:
    lda BR_PB,y
    beq bfr_pe
    sta BR_CMD,x
    inx
    iny
    cpx #120
    bcc bfr_p
bfr_pe:
    lda #13
    sta BR_CMD-1,x
    jsr br_try
    bcs bfr_err
    lda br_op
    cmp #2
    bne bfr_rts
    jsr br_cl2ent
    lda #<bdl_txt               ; *DELETE /REU/<name>
    ldy #>bdl_txt
    jsr br_cmdword
    jsr bcy_path
    jsr br_cmdput
    jsr br_try
    bcc bfr_rts
bfr_err:
    jmp br_err
bfr_rts:
    rts

; br_cl2ent: the clipboard's entry br_k into BR_ENT
br_cl2ent:
    lda br_k
    jsr br_clad
    lda #64
    ldx #<BR_ENT
    ldy #>BR_ENT
    jmp br_dmain

; br_find: is BR_ENT's name in the listing (the folder shown, any case)?
; C = 0 yes.  Uses: A, X, Y, br_j, BR_ITEM, BR_ENT.
br_find:
    ldx #63
bfi_cp:
    lda BR_ENT,x
    sta BR_ITEM,x
    dex
    bpl bfi_cp
    lda #0
    sta br_j
    sta br_j+1
bfi_l:
    lda br_j
    cmp br_n
    lda br_j+1
    sbc br_n+1
    bcs bfi_rts
    lda br_j
    sta br_i
    lda br_j+1
    sta br_i+1
    jsr br_get
    inc br_j
    bne bfi_n
    inc br_j+1
bfi_n:
    lda BR_ENT+1
    cmp BR_ITEM+1
    bne bfi_l
    tax
bfi_c:
    dex
    bmi bfi_yes
    lda BR_NAME,x
    eor BR_ITEM+2,x
    and #$DF
    beq bfi_c
    bne bfi_l
bfi_yes:
    clc
bfi_rts:
    rts

; br_ask: "<name> exists: replace? (Y/N/A/Q)" unless All was answered:
; Z = 1 to go on (Y or A); Q sets br_quitf
br_ask:
    lda br_all
    bne bas_yes
    jsr br_barname
    lda #<bas_txt
    ldy #>bas_txt
    jsr br_yn
    beq bas_rts
    lda br_ans
    cmp #'A'
    bne bas_q
    sta br_all
bas_yes:
    lda #0
    rts
bas_q:
    cmp #'Q'
    bne bas_no
    sta br_quitf
bas_no:
    lda #1
bas_rts:
    rts
bas_txt     dta ' exists: replace? (Y/N/A/Q)', 0

; ----------------------------------------------------------------------------
; br_tr
;   Summary: copy or move (br_op) the entry BR_ENT of the folder BR_PA
;            into the folder BR_PB, both on the Ultimate's drives.
;   Function: a move on one drive (br_same) is a RENAME. Otherwise a file
;            is copied (the firmware's COPY) and, for a move, deleted. A
;            name already there asks (br_ask: Y/All replace: a file is
;            deleted first, a folder is merged). A folder: MKDIR in the
;            target, then into both (a level deeper), each entry in turn
;            (recursively; an entry that left the source does not move
;            the index on), back up; for a move the source folder deleted
;            when it is empty. A folder into itself is refused.
;   Input:   BR_ENT, BR_PA, BR_PB, br_tgt, br_op, br_same, br_lvl.
;   Output:  br_gone = 1 when the entry left BR_PA; br_quitf.
;   Uses:    A, X, Y, BR_ENT, BR_PAY, errbuf.
br_tr:
    lda #0
    sta br_gone
    jsr br_barname
    lda br_op
    cmp #2
    bne btr_nmv
    lda br_same
    beq btr_nmv
    jsr btr_rename              ; a move on one drive: RENAME
    bcc btr_gone
    jsr br_exists
    bne btr_fail
    jsr br_ask
    bne btr_done
    lda BR_ENT
    and #$10
    bne btr_dir                 ; (a folder: merged)
    jsr btr_deltg               ; a file: the old one deleted
    bcs btr_fail
    jsr btr_rename
    bcs btr_fail
btr_gone:
    lda #1
    sta br_gone
btr_done:
    rts
btr_fail:
    jmp br_err
btr_nmv:
    lda BR_ENT
    and #$10
    bne btr_dir
    jsr btr_copy1               ; a file: COPY
    bcc btr_cpd
    jsr br_exists
    bne btr_fail
    jsr br_ask
    bne btr_done
    jsr btr_deltg
    bcs btr_fail
    jsr btr_copy1
    bcs btr_fail
btr_cpd:
    lda br_op                   ; a move: the source deleted
    cmp #2
    bne btr_done
    jsr br_cdpa
    bcs btr_fail
    lda #DOS_DELETE
    jsr br_dname
    bcs btr_fail
    bcc btr_gone
btr_dir:
    jsr btr_inself              ; into itself?
    bcs btr_fail
    ldx #0                      ; MKDIR <target><name>
    jsr br_setpb
    jsr br_ppath
    jsr br_pname
    bcs btr_fail
    lda #DOS_MKDIR
    jsr br_dos
    bcc btr_down
    jsr br_exists               ; there: merged (asked unless moving,
    bne btr_fail                ; which asked already)
    lda br_op
    cmp #2
    bne btr_dask
    lda br_same
    bne btr_down
btr_dask:
    jsr br_ask
    bne btr_done
btr_down:
    lda br_lvl
    cmp #BR_DEPTH
    bcc btr_dd
    jsr bdel_long
    jmp btr_fail
btr_dd:
    jsr br_paadd                ; one level down in both
    bcs btr_fail
    jsr br_pbadd
    bcc btr_dd2
    jsr br_pacut
    jmp btr_fail
btr_dd2:
    inc br_lvl
    lda br_lvl
    asl
    tax
    lda #0
    sta br_idx,x
    sta br_idx+1,x
btr_dl:
    jsr br_entn
    bcs btr_up
    jsr br_tr
    lda br_quitf
    bne btr_up
    bit ESCFLG
    bmi btr_up
    lda br_gone                 ; still there: the next index
    bne btr_dl
    lda br_lvl
    asl
    tax
    inc br_idx,x
    bne btr_dl
    inc br_idx+1,x
    bne btr_dl
btr_up:
    jsr br_pbcut
    jsr br_pacut                ; (BR_ENT: the folder again)
    dec br_lvl
    lda #0
    sta br_gone
    lda br_op                   ; a move: the source folder deleted
    cmp #2                      ; when empty now
    bne btr_upr
    jsr br_cdpa
    bcs btr_upr
    lda #DOS_DELETE
    jsr br_dname
    bcs btr_upr
    lda #1
    sta br_gone
btr_upr:
    rts

; btr_rename: CHDIR to the source, RENAME name -> <target><name>
btr_rename:
    jsr br_cdpa
    bcs btrr_rts
    ldx #0
    jsr br_pname
    jsr br_pnul
    jsr br_setpb
    jsr br_ppath
    jsr br_pname
    bcs btrr_rts
    lda #DOS_RENAME
    jmp br_dos
btrr_rts:
    rts
; btr_copy1: CHDIR to the source, COPY name -> <target> (without its
; last '/', as *COPY gives it)
btr_copy1:
    jsr br_cdpa
    bcs btrc_rts
    ldx #0
    jsr br_pname
    jsr br_pnul
    jsr br_setpb
    jsr br_ppath
    bcs btrc_rts
    dex                         ; (the last '/' off: never the root, P
    lda #DOS_CPY                ; refuses that)
    jmp br_dos
btrc_rts:
    rts
; btr_deltg: the target's entry of that name deleted (a file)
btr_deltg:
    jsr br_cdpb
    bcs btd_rts
    lda #DOS_DELETE
    jmp br_dname
btd_rts:
    rts
; btr_inself: C = 1 (errbuf) when BR_PB starts with BR_PA, the name and
; '/' (a folder into itself)
btr_inself:
    ldy #0
bti_a:
    lda BR_PA,y
    beq bti_n
    cmp BR_PB,y
    bne bti_no
    iny
    bne bti_a
bti_n:
    ldx #0
bti_nl:
    cpx BR_ENT+1
    bcs bti_sl
    lda BR_NAME,x
    eor BR_PB,y
    and #$DF
    bne bti_no
    inx
    iny
    bne bti_nl
bti_sl:
    lda BR_PB,y
    cmp #'/'
    bne bti_no
    ldy #0
bti_m:
    lda bti_txt,y
    sta errbuf+1,y
    beq bti_e
    iny
    bne bti_m
bti_e:
    sec
    rts
bti_no:
    clc
    rts
bti_txt     dta 'Not into itself', 0

; br_exists: Z = 1 when the last status (errbuf+1) says EXISTS
br_exists:
    ldx #0
bex_l:
    lda errbuf+1,x
    beq bex_no
    cmp #'E'
    bne bex_n
    ldy #0
bex_c:
    lda errbuf+2,x
    and #$DF
    cmp bex_txt,y
    bne bex_n
    inx
    iny
    cpy #5
    bne bex_c
    lda #0
    rts
bex_n:
    inx
    cpx #ERRMAX-2
    bcc bex_l
bex_no:
    lda #1
    rts
bex_txt     dta 'XISTS'

; ----------------------------------------------------------------------------
; The listing in the REU: entry br_i at BR_BANK:br_i*64
br_get:
    jsr br_entaddr
    lda #64
    ldx #<BR_ENT
    ldy #>BR_ENT
    jmp br_dmain
br_put:
    jsr br_entaddr
    lda #64
    ldx #<BR_ENT
    ldy #>BR_ENT
    jmp br_dmaout
br_entaddr:
    lda br_i                    ; mosTMP = br_i * 64: the low byte br_i
    asl                         ; << 6, the middle one br_i >> 2 (br_i
    asl                         ; to 1023), the bank BR_BANK
    asl
    asl
    asl
    asl
    sta mosTMP
    lda br_i+1
    sta mosTMP+1
    lda br_i
    lsr mosTMP+1
    ror
    lsr mosTMP+1
    ror
    sta mosTMP+1
    lda #BR_BANK
    sta mosTMP+2
    rts

; br_dmain / br_dmaout: A bytes between C64 X/Y and REU mosTMP..+2
; (interrupts off from the first register to the command)
br_dmaout:
    sec
    bcs bdm_go
br_dmain:
    clc
bdm_go:
    php
    sei
    stx REU_C64
    sty REU_C64+1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    lda mosTMP
    sta REU_ADDR
    lda mosTMP+1
    sta REU_ADDR+1
    lda mosTMP+2
    sta REU_BANK
    lda #0
    sta REU_CTRL
    lda #REU_TO_C64
    bcc bdm_cmd
    lda #REU_TO_REU
bdm_cmd:
    sta REU_CMD
    plp
    rts

