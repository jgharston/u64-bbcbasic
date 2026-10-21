; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *BROWSE: a file browser (bank 9, inside .local brw)
;
; Owner, 2026-10-21 (PLAN.md 27 item 9a): reachable at the prompt with F1
; on an empty line (lineed.s: F1 there has nothing to COPY), in the MOS,
; with drives and folders, opening by type, file information and *TYPE,
; delete and rename with a confirmation.
;
; The listing: the current directory's entries (the Ultimate's through
; the command interface, /REU's from the RAM disk's directory), 64 bytes
; each in the REU's file bank (&0A0000: attribute, name length, name), up
; to 1023. The screen (MODE 100): two header bars, 20 entries, a status
; line, the keys. Keys: cursor up/down a line, left/right a page, RETURN
; opens, T types, D deletes, R renames, Q or ESCAPE leaves.
; Opening by type: a folder (and "..") is entered; a name without '.' is
; taken as a BASIC program and CHAINed (the browser ends and types
; CHAIN "name" through *KEY slot 0: keys.s); .SEQ *SEQ, .MOD *MODPLAY,
; .WAV a sample played (sample 32 on voice 30), .D64/.D71/.D81/.G64
; *MOUNT, .UPIC loaded and shown, .VPL *PALETTE LOAD; others: *TYPE.
; Names with a space cannot be opened (the MOS's names end at a space).
; A command that fails (a file that is not what its name says) ends the
; browser with its error at the prompt.
;
; State: BASIC's string buffer, &0600-&06DF (free while a command runs;
; the commands called here use MOSBUF and &06E0-&06FF): the command
; being built at &0600, the variables at &0680.
;
; ----------------------------------------------------------------------------

BR_BANK     = $0A               ; the listing (the file scratch bank)
BR_MAX      = 1023
BR_ROWS     = 20
BR_ROW0     = 3                 ; first list row on the screen
BR_CMD      = $0600             ; 128: a command for OSCLI
BV          = $0680
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
br_path     = BV+16             ; 48: the path shown (0 terminated)
BR_ENT      = MOSBUF            ; an entry: attr, length, name (to 62)
BR_NAME     = MOSBUF+2

KEY_UP      = 139               ; OSRDCH's cursor codes
KEY_DOWN    = 138
KEY_LEFT    = 136
KEY_RIGHT   = 137

; ----------------------------------------------------------------------------
; cmd_browse
;   Summary: *BROWSE: the file browser (see the top).
;   Function: MODE 100; the listing read; keys until Q / ESCAPE or a
;            program to CHAIN.
;   Input:   none.  Output: the screen; maybe a CHAIN typed.
;   Uses:    A, X, Y, fs*, mos*, MOSBUF, &0600-&06DF.
cmd_browse:
    jsr s6_end
    lda #22                     ; MODE 100
    jsr OSWRCH
    lda #100
    jsr OSWRCH
    jsr br_curs0
    jsr br_load
bw_draw:
    jsr br_screen
bw_key:
    jsr br_status
    jsr OSRDCH
    bcc bw_nesc
    lda #$7E                    ; ESCAPE: acknowledged, leave
    jsr OSBYTE
    jmp br_quit
bw_nesc:
    sta br_key
    cmp #KEY_DOWN
    bne bw_up
    jsr br_down
    jmp bw_key
bw_up:
    cmp #KEY_UP
    bne bw_right
    jsr br_up
    jmp bw_key
bw_right:
    cmp #KEY_RIGHT
    bne bw_left
    ldx #BR_ROWS
bwr_l:
    jsr br_down
    dex
    bne bwr_l
    jmp bw_key
bw_left:
    cmp #KEY_LEFT
    bne bw_ret
    ldx #BR_ROWS
bwl_l:
    jsr br_up
    dex
    bne bwl_l
    jmp bw_key
bw_ret:
    cmp #13
    bne bw_letter
    jsr br_open                 ; C = 1: the screen to draw again
    bcs bw_draw
    jmp bw_key
bw_letter:
    and #$DF
    cmp #'Q'
    bne bw_t
    jmp br_quit
bw_t:
    cmp #'T'
    bne bw_d
    jsr br_type
    jmp bw_draw
bw_d:
    cmp #'D'
    bne bw_r
    jsr br_delete
    jmp bw_draw
bw_r:
    cmp #'R'
    bne bw_none
    jsr br_rename
    jmp bw_draw
bw_none:
    jmp bw_key

; br_quit: leave (the screen cleared, the prompt follows)
br_quit:
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
; br_load
;   Summary: the current directory's listing into the REU: br_n entries,
;            the selection on the first; br_path.
;   Function: /REU (reu_cwd): its directory's entries in use; else the
;            Ultimate's path (DOS GETPATH) and, below the root, ".." first,
;            then OPENDIR / READDIR (an entry a packet: the attribute,
;            the name). At the root the drives, and /REU with a RAM disk.
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF.
br_load:
    lda #0
    sta br_n
    sta br_n+1
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
    farcall uci_need, BANK_FS
    jsr bl_getpath
    lda br_path                 ; "/" alone: the root
    cmp #'/'
    bne bl_notroot
    lda br_path+1
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
    farcall fs_free_target, BANK_FS
    lda #$13                    ; OPENDIR
    farcall fs_hdr2, BANK_FS
    lda #0
    sta fsLEN
    sta fsLEN+1
    farcall uci_send, BANK_FS
    farcall uci_finish, BANK_FS
    bcc bl_rd                   ; (empty, or not readable: what there is)
    rts
bl_rd:
    lda #$14                    ; READDIR
    farcall fs_hdr2, BANK_FS
    farcall uci_send, BANK_FS
bl_entry:
    lda UCI_BASE                ; an entry: attribute, then the name
    bpl bl_end
    lda UCI_BASE+2
    sta BR_ENT
    ldx #0
bl_ch:
    lda UCI_BASE
    bpl bl_nend
    lda UCI_BASE+2
    cpx #61
    bcs bl_ch
    sta BR_NAME,x
    inx
    bne bl_ch
bl_nend:
    stx BR_ENT+1
    jsr bl_add
    bit ESCFLG
    bmi bl_end
    lda UCI_BASE                ; another entry follows?
    and #$30
    cmp #$30
    bne bl_end
    farcall uci_ack, BANK_FS
    jmp bl_entry
bl_end:
    farcall uci_finish, BANK_FS
bl_rts:
    rts
bl_reuname  dta 'REU'

; bl_reu: the RAM disk's entries in use (RD_BANK: 127 of 32 bytes from
; &20: in use, name to 16, 0 ended)
bl_reu:
    lda #0
    sta br_rdi
bl_reul:
    lda br_rdi                    ; its 32 bytes -> MOSBUF+$80
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
    ldx #4
blr_p:
    lda blr_txt,x
    sta br_path,x
    dex
    bpl blr_p
    rts
blr_txt     dta '/REU', 0

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
    jsr br_entaddr
    lda #64
    ldx #<BR_ENT
    ldy #>BR_ENT
    jsr br_dmaout
    inc br_n
    bne bla_rts
    inc br_n+1
bla_rts:
    rts

; bl_getpath: the Ultimate's current path into br_path (to 47 bytes)
bl_getpath:
    lda #TARGET_DOS1
    sta fsTGT
    lda #$12                    ; GETPATH
    farcall fs_hdr2, BANK_FS
    lda #0
    sta fsLEN
    sta fsLEN+1
    farcall uci_send, BANK_FS
    lda #<br_path
    sta fsADDR
    lda #>br_path
    sta fsADDR+1
    lda #47
    sta fsLEN
    lda #0
    sta fsLEN+1
    sta br_path
    farcall uci_read_to, BANK_FS
    ldx fsCNT                   ; 0 ended, trailing 0 bytes dropped
    lda #0
    sta br_path,x
    farcall uci_finish, BANK_FS
    rts

; ----------------------------------------------------------------------------
; The screen
br_screen:
    lda #12
    jsr OSWRCH
    jsr s6_text
    dta 17, 130, ' U64 BBC BASIC: files                   ', 0
    jsr s6_text
    dta 17, 141, ' ', 0
    ldx #0                      ; the path, padded to 39
bs_p:
    lda br_path,x
    beq bs_pp
    jsr OSWRCH
    inx
    cpx #39
    bne bs_p
bs_pp:
    lda #' '
    jsr OSWRCH
    inx
    cpx #39
    bcc bs_pp
    jsr s6_text
    dta 17, 128, 17, 3, 0
    jsr br_list
    ldy #23                     ; (no 0 bytes inside s6_text's texts:
    jsr br_tab0                 ; it stops at the first; TAB(0,y) here)
    jsr s6_text
    dta 17, 6, 'RETURN', 17, 3, ' open  ', 17, 6, 'T', 17, 3, 'ype  '
    dta 17, 6, 'D', 17, 3, 'elete  ', 17, 6, 'R', 17, 3, 'ename  ', 17, 6, 'Q', 17, 3, 'uit', 0
    ldy #24
    jsr br_tab0
    jsr s6_text
    dta 17, 6, 'cursor keys', 17, 3, ' line / page', 0
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
    ldy #39                     ; (39: the 40th would scroll the screen)
bb_sp:
    lda #' '
    jsr OSWRCH
    dey
    bne bb_sp
    ldy #22
    jmp br_tab0

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

; br_row1: entry br_i at its row (br_row): blank past the end
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

; br_status: the selected entry: its kind and size (row 22)
br_status:
    jsr br_bar
    lda br_n
    ora br_n+1
    bne bst_some
    jsr s6_text
    dta ' (empty)', 0
    jmp bst_pad
bst_some:
    lda br_sel
    sta br_i
    lda br_sel+1
    sta br_i+1
    jsr br_get
    lda BR_ENT
    and #$10
    beq bst_file
    jsr s6_text
    dta ' folder', 0
    jmp bst_pad
bst_file:
    jsr br_size                 ; mosTMP = its length (24 bits), C = 1:
    bcs bst_nosz                ; unknown
    jsr s6_text
    dta ' ', 0
    farcall st_dec16, BANK_FS   ; (to 64K; more: the K below)
    jsr s6_text
    dta ' bytes', 0
    jmp bst_pad
bst_nosz:
    jsr s6_text
    dta ' file', 0
bst_pad:
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
    lda #5
    ldx #<$0640
    ldy #>$0640
    jsr OSFILE
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

; br_cmdname: the selected entry's name at BR_CMD, CR ended; X = length
br_cmdname:
    ldx #0
    beq bcn_go
; br_cmdput: the name after the X bytes already at BR_CMD, CR ended
br_cmdput:
bcn_go:
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
    lda br_sel
    sta br_i
    lda br_sel+1
    sta br_i+1
    jsr br_get
    lda BR_ENT
    and #$10
    beq bo_file
    ldx #4                      ; a folder: *DIR name (at the root: /name;
    jsr bo_word                 ; ".." on /REU: "/", the root, as /REU is
    lda reu_cwd                 ; one of its drives)
    beq bo_nreu
    lda BR_NAME
    cmp #'.'
    bne bo_nreu
    lda #'/'
    sta BR_CMD+4
    lda #13
    sta BR_CMD+5
    bne bo_cli
bo_nreu:
    lda br_root
    beq bo_dirn
    lda #'/'
    sta BR_CMD,x
    inx
bo_dirn:
    jsr br_cmdput
bo_cli:
    jsr br_cli
    jsr br_load
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
    jsr br_cli
    jsr br_after                ; after: .WAV played, .UPIC shown
    lda br_sel                  ; the listing read again (a Upic picture
    pha                         ; shown keeps BASIC's RAM in its REU
    lda br_sel+1                ; bank meanwhile), the selection kept
    pha
    lda br_top
    pha
    lda br_top+1
    pha
    jsr br_load
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
    bcc bot_rts
    jsr bl_top0
bot_rts:
    sec
    rts
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

; bo_word: "DIR " at BR_CMD, X = 4
bo_word:
    ldx #3
bow_l:
    lda bow_txt,x
    sta BR_CMD,x
    dex
    bpl bow_l
    ldx #4
    rts
bow_txt     dta 'DIR '

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
    ldx #>baf_show
    ldy #0                      ; (the command from ROM: OSCLI reads it
    jmp br_clirom               ; through a RAM copy)
baf_type:
    cmp #7
    bne baf_rts
    jmp br_waitkey
baf_rts:
    rts
baf_snd     dta 30, 0, 32, 0, 53, 0, 0, 0
baf_show    dta 'UPIC SHOW', 13

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
; started as an F-key's: keys.s). Reached by a jmp from br_open: the
; return to cmd_browse dropped, the browser ends here.
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
    pla                         ; (br_open's return)
    pla
    jmp br_quit
bc_txt      dta 'CHAIN "', 0

; ----------------------------------------------------------------------------
; T, D, R
br_type:
    jsr br_selget
    bcs bty_rts
    ldx #5
bty_w:
    lda bty_txt,x
    sta BR_CMD,x
    dex
    bpl bty_w
    ldx #5
    jsr br_cmdput
    lda #12
    jsr OSWRCH
    jsr br_cli
    jmp br_waitkey
bty_rts:
    rts
bty_txt     dta 'TYPE  '

br_delete:
    jsr br_selget
    bcs bdl_rts
    jsr br_bar
    jsr s6_text
    dta ' Delete it? (Y/N)', 0
    jsr OSRDCH
    and #$DF
    cmp #'Y'
    bne bdl_rts
    ldx #6
bdl_w:
    lda bdl_txt,x
    sta BR_CMD,x
    dex
    bpl bdl_w
    ldx #7
    jsr br_cmdput
    jsr br_cli
    jsr br_load
bdl_rts:
    rts
bdl_txt     dta 'DELETE '

br_rename:
    jsr br_selget
    bcc brn_go
    rts
brn_go:
    jsr br_bar
    jsr s6_text
    dta ' New name: ', 0
    lda #$60                    ; OSWORD 0 (block &06A0): a line to
    sta $06A0                   ; &0660, 40 at most, ASCII 32-126
    lda #$06
    sta $06A1
    lda #40
    sta $06A2
    lda #32
    sta $06A3
    lda #126
    sta $06A4
    jsr br_curs1
    lda #0
    ldx #<$06A0
    ldy #>$06A0
    jsr OSWORD
    php
    sty br_len
    jsr br_curs0
    ldy br_len
    plp
    bcs brn_esc
    cpy #0
    beq brn_rts
    sty br_len
    ldx #6                      ; "RENAME " old " " new
brn_w:
    lda brn_txt,x
    sta BR_CMD,x
    dex
    bpl brn_w
    ldx #7
    jsr br_cmdput
    lda #' '
    sta BR_CMD,x
    inx
    ldy #0
brn_n:
    lda $0660,y
    sta BR_CMD,x
    inx
    iny
    cpy br_len
    bne brn_n
    lda #13
    sta BR_CMD,x
    jsr br_cli
    jsr br_load
brn_rts:
    rts
brn_esc:
    lda #$7E
    jmp OSBYTE
brn_txt     dta 'RENAME '

; br_selget: the selected entry in BR_ENT; C = 1 if none or a folder
br_selget:
    lda br_n
    ora br_n+1
    beq bsg_no
    lda br_sel
    sta br_i
    lda br_sel+1
    sta br_i+1
    jsr br_get
    lda BR_ENT
    and #$10
    bne bsg_no
    clc
    rts
bsg_no:
    sec
    rts

; br_waitkey: "Press a key", then one
br_waitkey:
    jsr s6_text
    dta 13, 10, 17, 6, 'Press a key', 17, 3, 0
    jsr OSRDCH
    bcc bwk_rts
    lda #$7E
    jsr OSBYTE
bwk_rts:
    rts

; br_cli: OSCLI the command at BR_CMD. An error ends the browser with
; its message at the prompt (catching it would need a RAM stub on BRKV:
; there is no RAM left for one; F1 brings the browser back). br_clirom:
; the command at A/X (ROM, CR ended) copied to BR_CMD first.
br_clirom:
    sta mosPTR2
    stx mosPTR2+1
    ldy #0
bcr_c:
    lda (mosPTR2),y
    sta BR_CMD,y
    iny
    cmp #13
    bne bcr_c
br_cli:
    jsr br_curs1                ; (on, should it end in an error)
    ldx #<BR_CMD
    ldy #>BR_CMD
    jsr OSCLI
    jmp br_curs0

; ----------------------------------------------------------------------------
; The listing in the REU: entry br_i at BR_BANK:br_i*64
br_get:
    jsr br_entaddr
    lda #64
    ldx #<BR_ENT
    ldy #>BR_ENT
    jmp br_dmain
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
