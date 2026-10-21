; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the MOS line editor (bank 0)
;
; OSWORD 0 with its own editor instead of the KERNAL screen editor
; (*EDIT BBC, the default; *EDIT C64 brings the full-screen editor back).
; One editor for every screen mode: it only moves the text cursor and
; prints through OSWRCH, so the KERNAL text screen, the bitmap modes and
; MODE 7 behave alike. Lines up to the caller's maximum (238 at BASIC's
; prompt, as on a BBC Micro).
;
; Keys (owner, 2026-10-10; docs/PLAN.md section 25):
;   LEFT / RIGHT        move in the line
;   CLR/HOME            start of the line; SHIFT+CLR/HOME its end
;   DEL / INST          delete left / insert a space
;   UP / DOWN           earlier / later lines (history in the REU)
;   CTRL+cursor keys    move the copy cursor (BBC copy editing)
;   F1                  COPY: the character under the copy cursor
;   RETURN              ends the line (from anywhere in it)
;
; Positions: the line starts at ed_sx/ed_sy (absolute screen character
; position, ed_sy signed: it moves up when the screen scrolls) and wraps
; at the text window's right edge. After each redraw the cursor position
; is read back; a scroll shows as a row above the expected one.
;
; History: REU bank 0, $8000-$FFFF, 128 slots of 256 bytes (length,
; text): slots 0-126 hold the last 127 lines typed at BASIC's prompt,
; slot 127 the line being typed while older lines are shown. Head and
; count at REU $3500.
;
; ----------------------------------------------------------------------------

ED          = MOSBUF+$C0        ; editor state (free while a line is typed)
ed_pos      = ED+0              ; edit position in the line (0..mosCNT)
ed_sx       = ED+1              ; start of the line on screen: column,
ed_sy       = ED+2              ; row (signed)
ed_l        = ED+3              ; text window: left, right, top, bottom
ed_r        = ED+4
ed_t        = ED+5
ed_b        = ED+6
ed_w        = ED+7              ; window width
ed_old      = ED+8              ; length on screen before the redraw
ed_hidx     = ED+9              ; history: 0 the line typed, n the n-th last
ed_cx       = ED+10             ; copy cursor column, row
ed_cy       = ED+11
ed_con      = ED+12             ; 1: copy cursor active (shown)
ed_x        = ED+13             ; ed_where's result: column, row
ed_y        = ED+14
ed_key      = ED+15             ; CTRL+cursor key held (matrix index)
ed_rpt      = ED+16             ; jiffy of its next repeat
ed_from     = ED+17             ; redraw from this position
ed_c16      = ED+18             ; 2: scratch
ed_head     = ED+20             ; history head (next slot), count: a copy
ed_count    = ED+21             ; of REU $3500/$3501
ed_tmp      = ED+22             ; 1: REU byte transfers
ed_ch       = ED+23             ; character being inserted
ed_blk      = ED+24             ; 1: the engine's cursor is drawn
ed_bph      = ED+25             ; blink phase (jiffy clock bit 4)
ed_bt       = ED+26             ; jiffy from which the cursor may show

EDMODE      = $03FC             ; 0: this editor, 1: the KERNAL's (*EDIT)

; key codes (PETSCII from the keyboard buffer; the copy cursor codes are
; made by ed_poll from CTRL+cursor and can be typed by a remote host)
KEY_CUP     = $80
KEY_CDOWN   = $82
KEY_CLEFT   = $84
KEY_CRIGHT  = $8F
KEY_COPY    = $85               ; F1
SFDX        = $CB               ; KERNAL: key held (matrix index, 64 none)
JIFFY       = $A2               ; KERNAL jiffy clock, low byte

REU_HIST    = $80               ; history slots: REU bank 0 page $80-$FF
REU_HMETA   = $3500             ; head, count
HIST_SLOTS  = 127               ; slot 127: the line being typed

; ----------------------------------------------------------------------------
; le_line
;   Summary: read a line with the MOS line editor (OSWORD 0, *EDIT BBC).
;   Function: sets up the window and start position, then edits the
;            caller's buffer key by key (see the file header) until
;            RETURN or ESCAPE. A line typed at BASIC's prompt (buffer
;            page &07) goes into the history. Ends in w0_end, which adds
;            the CR, echoes the newline and returns. A remote host's
;            request drops the line typed so far and is handled as at
;            the start of a line.
;   Input:   mosPTR2 buffer, mosMAX, mosMIN, mosHIGH (word0); a key is
;            waiting.
;   Output:  as word0: buffer, Y = length, C = 1 on ESCAPE.
;   Uses:    A, X, Y, mosCNT, ED (MOSBUF+$C0..), REU registers.

le_line:
    lda vtype                   ; the text window
    bne le_bwin
    lda #0
    sta ed_l
    sta ed_t
    lda #39
    sta ed_r
    lda #24
    sta ed_b
    bne le_win
le_bwin:
    lda twl
    sta ed_l
    lda twr
    sta ed_r
    lda twt
    sta ed_t
    lda twb
    sta ed_b
le_win:
    lda ed_r
    sec
    sbc ed_l
    clc
    adc #1
    sta ed_w
    jsr ed_getpos
    stx ed_sx
    sty ed_sy
    lda #0
    sta mosCNT
    sta ed_pos
    sta ed_old
    sta ed_hidx
    sta ed_con
    lda #64
    sta ed_key

le_loop:
    jsr ed_getkey
    bcc le_key
    jmp le_remote
le_key:
    cmp #0
    bne le_k
    jmp le_esc
le_k:
    cmp #13
    bne le_n0d
    jmp le_return
le_n0d:
    ldx #ek_n-1                 ; the editing keys
le_find:
    cmp ek_codes,x
    beq le_do
    dex
    bpl le_find
    tax                         ; a character
    lda pet2asc,x
    jsr ed_insert
    jmp le_loop
le_do:
    lda ek_hi,x
    pha
    lda ek_lo,x
    pha
    rts                         ; to the handler; it ends at le_loop

ek_codes:
    dta $14, $94, $9D, $1D, $13, $93, $91, $11
    dta KEY_CUP, KEY_CDOWN, KEY_CLEFT, KEY_CRIGHT, KEY_COPY
ek_n = *-ek_codes
ek_lo:
    dta <[ek_del-1], <[ek_inst-1], <[ek_left-1], <[ek_right-1]
    dta <[ek_home-1], <[ek_end-1], <[ek_up-1], <[ek_down-1]
    dta <[ek_cup-1], <[ek_cdown-1], <[ek_cleft-1], <[ek_cright-1]
    dta <[ek_copy-1]
ek_hi:
    dta >[ek_del-1], >[ek_inst-1], >[ek_left-1], >[ek_right-1]
    dta >[ek_home-1], >[ek_end-1], >[ek_up-1], >[ek_down-1]
    dta >[ek_cup-1], >[ek_cdown-1], >[ek_cleft-1], >[ek_cright-1]
    dta >[ek_copy-1]

ek_del:                         ; DEL: the character left of the cursor
    ldx ed_pos
    beq ek_none
    dex
    stx ed_pos
    txa
    tay
ekd_move:
    iny
    cpy mosCNT
    bcs ekd_moved
    lda (mosPTR2),y
    dey
    sta (mosPTR2),y
    iny
    bne ekd_move
ekd_moved:
    dec mosCNT
    lda ed_pos
    jsr ed_redraw
ek_none:
    jmp le_loop

ek_inst:                        ; INST: a space at the cursor, which stays
    lda ed_pos
    pha
    lda #' '
    jsr ed_insert
    pla
    sta ed_pos
    jsr ed_setcur
    jmp le_loop

ek_left:
    lda ed_pos
    beq ek_none
    dec ed_pos
    jsr ed_setcur
    jmp le_loop

ek_right:
    lda ed_pos
    cmp mosCNT
    bcs ek_none
    inc ed_pos
    jsr ed_setcur
    jmp le_loop

ek_home:
    lda #0
    beq ekh_set
ek_end:
    lda mosCNT
ekh_set:
    sta ed_pos
    jsr ed_setcur
    jmp le_loop

ek_up:                          ; an older line
    jsr ed_hmeta
    bcs ek_none                 ; no REU
    lda ed_hidx
    cmp ed_count
    bcs ek_none                 ; the oldest is shown
    tax
    bne eku_old
    lda #HIST_SLOTS             ; leaving the line typed: keep it
    jsr ed_hsave
    ldx ed_hidx
eku_old:
    inx
    stx ed_hidx
    jsr ed_hshow
    jmp le_loop

ek_down:                        ; a newer line, at last the one typed
    lda ed_hidx
    beq ek_none
    dec ed_hidx
    jsr ed_hmeta
    jsr ed_hshow
    jmp le_loop

ek_cup:
    jsr ed_cstart
    lda ed_cy
    cmp ed_t
    beq ekc_show
    dec ed_cy
    jmp ekc_show
ek_cdown:
    jsr ed_cstart
    lda ed_cy
    cmp ed_b
    bcs ekc_show
    inc ed_cy
    jmp ekc_show
ek_cleft:
    jsr ed_cstart
    lda ed_cx
    cmp ed_l
    beq ekc_show
    dec ed_cx
    jmp ekc_show
ek_cright:
    jsr ed_cstart
    jsr ed_cnext
ekc_show:
    jsr ed_mark
    jmp le_loop

ek_copy:                        ; COPY: the character under the copy cursor
    lda ed_con
    beq ekc_browse
    jsr ed_cread
    beq ekc_none                ; (none there)
    jsr ed_insert
    jsr ed_mark                 ; the copy cursor one further
    jsr ed_cnext
    jsr ed_mark
ekc_none:
    jmp le_loop
ekc_browse:                     ; no copy cursor: on an empty line at
    lda mosCNT                  ; BASIC's prompt (&0700) F1 opens the
    bne ekc_none                ; file browser: "*BROWSE" as typed and
    lda mosPTR2+1               ; RETURN (owner, 2026-10-21)
    cmp #$07
    bne ekc_none
    ldx #0
ekb_l:
    txa                         ; (X on the stack: ed_insert uses it and
    pha                         ; ed_c16)
    lda ekb_txt,x
    beq ekb_done
    jsr ed_insert
    pla
    tax
    inx
    bne ekb_l
ekb_done:
    pla
    jmp le_return
ekb_txt     dta '*BROWSE', 0

le_remote:                      ; a remote request: the line typed so far
    jsr ed_cend                 ; goes (taken off the screen), the
    lda #0                      ; request is handled as at the start of
    sta mosCNT                  ; the line (w0_waitkey)
    sta ed_pos
    jsr ed_redraw
    jsr w0_waitkey
    bcc le_again                ; a key after all: edit a new line
    jmp w0_end
le_again:
    jmp le_line

le_esc:                         ; ESCAPE: the line ends as it is
    lda #0
    sta NDX                     ; (RUN/STOP's RETURN in the buffer)
    sta kx_n                    ; (and a *KEY text)
    jsr ed_cend
    jmp w0_end
le_return:
    jsr ed_cend
    lda mosCNT                  ; the cursor after the line, then the
    sta ed_pos                  ; newline (w0_end) below it
    jsr ed_setcur
    lda mosPTR2+1               ; a line typed at BASIC's prompt (&0700)
    cmp #$07
    bne le_nohist
    jsr ed_hadd
le_nohist:
    jmp w0_end

; ----------------------------------------------------------------------------
; ed_insert
;   Summary: insert a character at the edit position and redraw.
;   Function: refused (VDU 7) when the line is full; ignored when outside
;            mosMIN..mosHIGH, 0 (no ASCII for the key) or above 126
;            outside MODE 7 (codes the text screens do not show).
;   Input:   A = ASCII character.
;   Output:  the line, the screen, ed_pos one further.
;   Uses:    A, X, Y, ed_ch.
ed_insert:
    sta ed_ch
    cmp #0
    beq ei_none
    cmp mosMIN
    bcc ei_none
    cmp mosHIGH
    beq ei_range
    bcs ei_none
ei_range:
    cmp #127
    bcc ei_ok
    ldx vtype
    cpx #2
    bne ei_none
ei_ok:
    lda mosCNT
    cmp mosMAX
    bcc ei_room
    lda #7                      ; full: the bell, as the BBC MOS
    jmp OSWRCH
ei_room:
    ldy mosCNT                  ; move the rest one to the right
ei_move:
    cpy ed_pos
    beq ei_put
    dey
    lda (mosPTR2),y
    iny
    sta (mosPTR2),y
    dey
    jmp ei_move
ei_put:
    lda ed_ch
    sta (mosPTR2),y
    inc mosCNT
    lda ed_pos
    inc ed_pos
    jmp ed_redraw
ei_none:
    rts

; ----------------------------------------------------------------------------
; ed_redraw
;   Summary: show the line from a position to its end, then put the
;            cursor at the edit position.
;   Function: prints the characters through OSWRCH and as many spaces as
;            the line has become shorter; reads the cursor back and moves
;            the start row (and the copy cursor) up by the rows the screen
;            scrolled. The copy cursor is hidden meanwhile.
;   Input:   A = first position to show; mosCNT, ed_old.
;   Output:  ed_old = mosCNT; cursor at ed_pos.
;   Uses:    A, X, Y, ed_from, ed_c16.
ed_redraw:
    sta ed_from
    jsr ed_mark                 ; (hides it when active)
    lda ed_from
    jsr ed_where
    jsr ed_place
    ldy ed_from
er_char:
    cpy mosCNT
    bcs er_blank
    lda (mosPTR2),y
    jsr ed_out
    iny
    bne er_char
er_blank:
    cpy ed_old                  ; blanks over what was longer
    bcs er_end
    lda #' '
    jsr ed_out
    iny
    bne er_blank
er_end:
    tya                         ; where the cursor should be now
    jsr ed_where
    jsr ed_getpos               ; and where it is
    tya
    sec
    sbc ed_y
    beq er_same
    bpl er_same                 ; (not below: no scroll)
    clc                         ; A = -rows scrolled
    pha
    adc ed_sy
    sta ed_sy
    pla
    clc
    adc ed_cy
    sta ed_cy
er_same:
    lda mosCNT
    sta ed_old
    jsr ed_mark
    ; fall through

; ed_setcur: the text cursor to the edit position.  Uses: A, X, Y.
ed_setcur:
    lda ed_pos
    jsr ed_where
    ; fall through

; ed_place
;   Summary: move the text cursor to ed_x/ed_y, kept inside the window.
;   Input:   ed_x, ed_y (signed row).  Output: cursor.  Uses: A, X, Y.
ed_place:
    lda ed_y
    bmi ep_top
    cmp ed_t
    bcs ep_nottop
ep_top:
    lda ed_t
ep_nottop:
    cmp ed_b
    bcc ep_row
    lda ed_b
ep_row:
    tax
    ldy ed_x
    lda vtype
    bne ep_bitmap
    clc
    jmp K_PLOT
ep_bitmap:
    sty tcx
    stx tcy
    rts

; ed_out
;   Summary: OSWRCH for the editor's own output: not copied to a remote
;            host's capture (as the KERNAL editor's echo is not).
;   Input:   A = character.  Output: screen.  A, X, Y preserved.
ed_out:
    sta wr_a
    stx wr_x
    sty wr_y
    jmp wr_notee

; ed_where
;   Summary: the screen position of a position in the line.
;   Function: column offset from the window's left edge plus the
;            position, divided by the window width (repeated subtraction,
;            at most a few hundred steps).
;   Input:   A = position; ed_sx, ed_sy, ed_l, ed_w.
;   Output:  ed_x = column, ed_y = row (signed, may be off the window).
;   Uses:    A, X, ed_c16.
ed_where:
    clc
    adc ed_sx
    sta ed_c16
    lda #0
    adc #0
    sta ed_c16+1
    lda ed_c16                  ; minus the window's left edge
    sec
    sbc ed_l
    sta ed_c16
    bcs ew_sub
    dec ed_c16+1
ew_sub:
    ldx ed_sy
ew_loop:
    lda ed_c16+1
    bne ew_more
    lda ed_c16
    cmp ed_w
    bcc ew_done
ew_more:
    lda ed_c16
    sec
    sbc ed_w
    sta ed_c16
    bcs ew_nob
    dec ed_c16+1
ew_nob:
    inx
    jmp ew_loop
ew_done:
    stx ed_y
    clc
    adc ed_l
    sta ed_x
    rts

; ed_getpos
;   Summary: read the text cursor's screen position.
;   Function: text screen: the KERNAL's row and column (a column of a
;            continued logical line counts from its own row); else the
;            engine's text cursor.
;   Input:   none.  Output: X = column, Y = row.  Uses: A.
ed_getpos:
    lda vtype
    bne eg_bitmap
    sec
    jsr K_PLOT                  ; X = row, Y = column in the logical line
    tya
eg_col:
    cmp #40
    bcc eg_text
    sbc #40
    bcs eg_col
eg_text:
    pha
    txa
    tay
    pla
    tax
    rts
eg_bitmap:
    ldx tcx
    ldy tcy
    rts

; ----------------------------------------------------------------------------
; ed_getkey
;   Summary: wait for a key with the cursor shown.
;   Function: the text screen blinks the KERNAL cursor; the other modes
;            blink the engine's cursor (a line under the cell, drawn by
;            inverting: it first shows 8 jiffies after the last output,
;            when MODE 7's refresh has redrawn the changed rows, else the
;            refresh would wipe it and the next toggle draw it instead).
;            VDU 23,1,0 (cursor off) hides it in all modes. While waiting, CTRL with a cursor
;            key (which the KERNAL does not decode) gives the copy cursor
;            codes, repeating while held (ed_poll). A request from a
;            remote host (docs/REMOTE_DEV.md) ends the wait too.
;   Input:   none.
;   Output:  C = 0: A = PETSCII code, or 0 when ESCAPE is pending;
;            C = 1: a remote request is waiting.
;   Uses:    A, X, Y.
ed_getkey:
    lda #0
    sta ed_blk
    lda vtype
    bne egk_bm
    lda curson
    beq egk_wait
    lda #0
    sta BLNSW
    beq egk_wait
egk_bm:
    lda JIFFY
    clc
    adc #8
    sta ed_bt
    lda #$FF                    ; (a phase that never matches: the first
    sta ed_bph                  ; toggle draws it)
egk_wait:
    bit ESCFLG
    bmi egk_esc
    jsr ed_poll
    bne egk_got
    lda MB_HSEQ
    cmp MB_CSEQ
    bne egk_remote
    jsr key_avail
    bne egk_key
    jsr egk_blink
    jmp egk_wait
egk_key:
    jsr egk_hide
    jsr key_get
    cmp #0                      ; (none after all, e.g. a *KEY control
    beq ed_getkey               ; code that cannot be typed: wait on)
    clc
    rts
egk_esc:
    lda #0
egk_got:
    pha
    jsr egk_hide
    pla
    clc
    rts
egk_remote:
    jsr egk_hide
    sec
    rts
egk_hide:
    lda vtype
    bne egk_bmh
    jmp wk_hide
egk_bmh:
    lda ed_blk
    beq egk_none
    lda #0
    sta ed_blk
    jmp w0b_cursor
egk_none:
    rts

; egk_blink: bitmap modes and MODE 7: toggle the engine's cursor when the
; jiffy clock's bit 4 changes (about 4 times a second), from ed_bt on.
; Uses: A, X, Y.
egk_blink:
    lda vtype
    beq egk_none
    lda curson
    beq egk_none
    lda JIFFY
    sec
    sbc ed_bt
    bmi egk_none                ; (not yet: the refresh catches up)
    lda JIFFY                   ; started: keep the start up to date (the
    sta ed_bt                   ; signed difference turned negative after
    and #16                     ; 128 jiffies and the blinking stopped)
    cmp ed_bph
    beq egk_none
    sta ed_bph
    lda ed_blk
    eor #1
    sta ed_blk
    jmp w0b_cursor

; ed_poll
;   Summary: CTRL+cursor keys as copy cursor moves; F1 (COPY) repeating.
;   Function: a cursor key (matrix 2 right, 7 down; with SHIFT left, up)
;            held with CTRL gives its code at once, after 20 jiffies again
;            and then every 3, as the KERNAL repeats keys. F1 (matrix 4,
;            no SHIFT/C=/CTRL) held: its first press comes through the
;            keyboard buffer, the repeats from here (the KERNAL does not
;            repeat function keys).
;   Input:   SHFLAG, SFDX, JIFFY.
;   Output:  A = KEY_C* code (Z = 0), or A = 0 (Z = 1).
;   Uses:    A, X.
ed_poll:
    lda SHFLAG
    bne epl_ctrl
    lda kx_def                  ; (*KEY 1 set: F1 is no COPY)
    lsr
    bcs epl_none
    lda SFDX                    ; F1 held
    cmp #4
    bne epl_none
    cmp ed_key
    beq epl_f1held
    sta ed_key                  ; just pressed: the buffer has it; repeat
    lda JIFFY                   ; from 20 jiffies on
    clc
    adc #20
    sta ed_rpt
    jmp epl_no
epl_f1held:
    lda JIFFY
    sec
    sbc ed_rpt
    bmi epl_no
    lda JIFFY
    clc
    adc #3
    sta ed_rpt
    lda #KEY_COPY
    rts
epl_ctrl:
    and #4
    beq epl_none
    lda SFDX
    cmp #2
    beq epl_key
    cmp #7
    bne epl_none
epl_key:
    cmp ed_key
    beq epl_held
    sta ed_key
    lda #20
    bne epl_fire
epl_held:
    lda JIFFY
    sec
    sbc ed_rpt
    bmi epl_no
    lda #3
epl_fire:
    clc
    adc JIFFY
    sta ed_rpt
    lda SHFLAG
    and #1                      ; X = 0..3: right, left, down, up
    tax
    lda ed_key
    cmp #7
    bne epl_code
    inx
    inx
epl_code:
    lda epl_codes,x
    rts
epl_none:
    lda #64
    sta ed_key
epl_no:
    lda #0
    rts
epl_codes:
    dta KEY_CRIGHT, KEY_CLEFT, KEY_CDOWN, KEY_CUP

; ----------------------------------------------------------------------------
; Copy cursor (BBC copy editing). It starts where the text cursor is;
; ed_mark toggles its mark: the cell's reverse bit on the text screen,
; the engine's cursor line elsewhere.

; ed_cstart: activate the copy cursor at the text cursor, else hide its
; mark for the move.  Uses: A, X, Y.
ed_cstart:
    lda ed_con
    bne ecs_hide
    jsr ed_getpos
    stx ed_cx
    sty ed_cy
    lda #1
    sta ed_con
    rts
ecs_hide:
    jmp ed_mark

; ed_cend: the copy cursor off (its mark removed).  Uses: A, X, Y.
ed_cend:
    jsr ed_mark
    lda #0
    sta ed_con
    rts

; ed_cnext: the copy cursor one to the right; past the window's right
; edge the next row's start (not below the window).  Uses: A.
ed_cnext:
    lda ed_cx
    cmp ed_r
    bcs ecn_wrap
    inc ed_cx
    rts
ecn_wrap:
    lda ed_cy
    cmp ed_b
    bcs ecn_done
    inc ed_cy
    lda ed_l
    sta ed_cx
ecn_done:
    rts

; ed_mark
;   Summary: toggle the copy cursor's mark (nothing when it is off or
;            off the window).
;   Input:   ed_con, ed_cx, ed_cy.  Output: screen.  Uses: A, X, Y.
ed_mark:
    lda ed_con
    beq emk_done
    lda ed_cy
    bmi emk_done
    cmp ed_t
    bcc emk_done
    lda vtype
    bne emk_bitmap
    jsr ed_scraddr
    lda (mosTMP),y
    eor #$80
    sta (mosTMP),y
emk_done:
    rts
emk_bitmap:
    lda tcx
    pha
    lda tcy
    pha
    lda ed_cx
    sta tcx
    lda ed_cy
    sta tcy
    jsr w0b_cursor
    pla
    sta tcy
    pla
    sta tcx
    rts

; ed_cread
;   Summary: the character under the copy cursor.
;   Function: the text screen: its screen code as ASCII (scr2asc, reverse
;            ignored); MODE 7: the code in the screen memory at &7C00;
;            bitmap modes: read from the pixels (gxb_chr, bank 5: the
;            cell against the font, as a BBC Micro does), the copy
;            cursor's mark hidden meanwhile; Upic full: its text console.
;   Input:   ed_cx, ed_cy.  Output: A = ASCII, Z = 1 when none.
;   Uses:    A, X, Y, mosTMP.
ed_cread:
    lda vtype
    beq ecr_text
    cmp #2
    beq ecr_ttx
    lda eng_kind                ; Upic full: the text console
    cmp #3
    beq ecr_text
    jsr ed_mark                 ; (the mark is drawn into the cell)
    ldx ed_cx
    ldy ed_cy
    farcall gxb.gxb_chr, BANK_RD
    pha
    jsr ed_mark
    pla
    rts
ecr_ttx:
    lda #<TTXBUF
    sta mosTMP
    lda #>TTXBUF
    jsr ed_rowaddr
    lda (mosTMP),y
    rts
ecr_text:
    jsr ed_scraddr
    lda (mosTMP),y
    and #$7F
    tax
    lda scr2asc,x
    rts

; ed_scraddr: mosTMP = the text screen row of the copy cursor, Y its
; column.  Uses: A, X, Y.
ed_scraddr:
    lda #0
    sta mosTMP
    lda HIBASE
    ; fall through

; ed_rowaddr: mosTMP = (A * 256 + mosTMP) + ed_cy * 40, Y = ed_cx.
; Uses: A, X, Y.
ed_rowaddr:
    sta mosTMP+1
    ldx ed_cy
    beq era_col
era_row:
    lda mosTMP
    clc
    adc #40
    sta mosTMP
    bcc era_n
    inc mosTMP+1
era_n:
    dex
    bne era_row
era_col:
    ldy ed_cx
    rts

; ----------------------------------------------------------------------------
; History in the REU (see the file header). Without an REU there is none.

; ed_hmeta: read head and count; values out of range (an REU never
; written) count as an empty history.  Output: C = 1 without an REU.
; Uses: A.
ed_hmeta:
    lda reu_banks
    ora reu_banks+1
    bne ehm_reu
    sec
    rts
ehm_reu:
    php                         ; (interrupts off while the REU is set up:
    sei                         ; the sound interrupt uses it too)
    lda #<ed_head
    ldx #>ed_head
    jsr ed_meta
    lda #REU_TO_C64
    sta REU_CMD
    plp
    lda ed_head                 ; not written yet (a new REU's contents):
    cmp #HIST_SLOTS             ; an empty history
    bcs ehm_reset
    lda ed_count
    cmp #HIST_SLOTS+1
    bcc ehm_ok
ehm_reset:
    lda #0
    sta ed_head
    sta ed_count
ehm_ok:
    clc
    rts

; ed_meta: REU registers for the 2-byte head/count at REU_HMETA from or
; to A/X.  Uses: A.
ed_meta:
    sta REU_C64
    stx REU_C64+1
    lda #<REU_HMETA
    sta REU_ADDR
    lda #>REU_HMETA
    sta REU_ADDR+1
    lda #2
    bne ed_reu0

; ed_slot: REU registers for slot A (its length byte) and the byte
; ed_tmp.  Uses: A.
ed_slot:
    clc
    adc #REU_HIST
    sta REU_ADDR+1
    lda #0
    sta REU_ADDR
    lda #<ed_tmp
    sta REU_C64
    lda #>ed_tmp
    sta REU_C64+1
    lda #1
ed_reu0:
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_BANK
    sta REU_CTRL
    rts

; ed_text: REU registers for the text of the slot set by ed_slot (from
; its byte 1), to or from the line buffer, length mosCNT.  Uses: A.
ed_text:
    lda #1
    sta REU_ADDR
    lda mosPTR2
    sta REU_C64
    lda mosPTR2+1
    sta REU_C64+1
    lda mosCNT
    sta REU_LEN
    rts

; ed_hsave
;   Summary: store the line in a history slot.
;   Input:   A = slot; the line (mosPTR2, mosCNT).
;   Output:  the slot.  Uses: A, ed_tmp.
ed_hsave:
    php                         ; (interrupts off: see ed_hmeta)
    sei
    jsr ed_slot
    lda mosCNT
    sta ed_tmp
    lda #REU_TO_REU
    sta REU_CMD
    lda mosCNT
    beq ehs_done
    jsr ed_text
    lda #REU_TO_REU
    sta REU_CMD
ehs_done:
    plp
    rts

; ed_hshow
;   Summary: show history entry ed_hidx as the line being edited.
;   Function: entry 0 is the line that was being typed (slot 127), entry
;            n the n-th last line (slot head - n, modulo 127). Its length
;            is cut to the caller's maximum; the cursor goes to its end.
;   Input:   ed_hidx, ed_head (ed_hmeta read).
;   Output:  buffer, mosCNT, ed_pos, screen.  Uses: A, X, Y, ed_tmp.
ed_hshow:
    php                         ; (interrupts off: see ed_hmeta)
    sei
    lda #HIST_SLOTS
    ldx ed_hidx
    beq ehw_slot
    lda ed_head
    sec
    sbc ed_hidx
    bcs ehw_slot
    adc #HIST_SLOTS
ehw_slot:
    pha
    jsr ed_slot
    lda #REU_TO_C64
    sta REU_CMD
    pla
    jsr ed_slot                 ; (the address again for the text)
    lda ed_tmp
    cmp mosMAX
    bcc ehw_len
    lda mosMAX
ehw_len:
    sta mosCNT
    sta ed_pos
    cmp #0                      ; (an empty line: no transfer; a length
    beq ehw_show                ; of 0 would copy 64K over everything)
    jsr ed_text
    lda #REU_TO_C64
    sta REU_CMD
ehw_show:
    plp
    lda #0
    jmp ed_redraw

; ed_hadd
;   Summary: add the line to the history.
;   Function: not empty lines, and not the same line as the last one;
;            the oldest is overwritten when all 127 slots are in use.
;   Input:   the line.  Output: the slot, head and count.
;   Uses:    A, X, Y, ed_tmp.
ed_hadd:
    lda mosCNT
    beq eha_rts
    jsr ed_hmeta
    bcs eha_rts
    php                         ; (interrupts off: see ed_hmeta)
    sei
    lda ed_count
    beq eha_new
    ldx ed_head                 ; the last line: the same?
    dex
    bpl eha_last
    ldx #HIST_SLOTS-1
eha_last:
    stx ed_c16                  ; (the slot)
    txa
    jsr ed_slot
    lda #REU_TO_C64
    sta REU_CMD
    lda ed_tmp
    cmp mosCNT
    bne eha_new
    ldy #0                      ; compare byte by byte
eha_cmp:
    lda ed_c16
    jsr ed_slot
    iny
    sty REU_ADDR
    lda #REU_TO_C64
    sta REU_CMD
    lda ed_tmp
    dey
    cmp (mosPTR2),y
    bne eha_new
    iny
    cpy mosCNT
    bcc eha_cmp
eha_done:
    plp                         ; (the same: not again)
eha_rts:
    rts
eha_new:
    lda ed_head
    jsr ed_hsave
    ldx ed_head
    inx
    cpx #HIST_SLOTS
    bcc eha_head
    ldx #0
eha_head:
    stx ed_head
    lda ed_count
    cmp #HIST_SLOTS
    bcs eha_full
    inc ed_count
eha_full:
    lda #<ed_head
    ldx #>ed_head
    jsr ed_meta
    lda #REU_TO_REU
    sta REU_CMD
    plp
    rts

; ----------------------------------------------------------------------------
; cmd_edit
;   Summary: *EDIT BBC | C64: choose the line editor; *EDIT alone shows
;            which one is in use.
;   Function: BBC: the MOS line editor (le_line); C64: the KERNAL's
;            full-screen editor (in bitmap modes the BBC way without
;            editing, as before).
;   Input:   mosPTR/Y = rest of the command line.
;   Output:  EDMODE; text.  Uses: A, X, Y.
cmd_edit:
    jsr cli_skipsp
    jsr toupper
    cmp #'B'
    beq ced_bbc
    cmp #'C'
    beq ced_c64
    cmp #13
    beq ced_show
    jmp cli_bad
ced_bbc:
    lda #0
    beq ced_set
ced_c64:
    lda #1
ced_set:
    sta EDMODE
    rts
ced_show:
    ldx #0
    lda EDMODE
    beq ced_print
    ldx #ced_c64t-ced_bbct
ced_print:
    lda ced_bbct,x
    beq ced_nl
    jsr OSWRCH
    inx
    bne ced_print
ced_nl:
    jmp OSNEWL
ced_bbct:
    dta 'BBC', 0
ced_c64t:
    dta 'C64', 0
