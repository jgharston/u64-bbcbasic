; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *SONG: the song tracker's commands (bank 6)
;
; The song lives in the REU (defs.s REU_SONGBANK, REU_PATBANK; layout in
; docs/DESIGN_TRACKER.md section 2); the SID image plays it (sound_sid.s,
; s_song). Songs are built from BASIC: after *SONG RECORD, SOUND writes
; notes into the song instead of playing them (sg_record, from
; snd_word7), each voice with its own cursor (in rows).
;
; Header (REU $010000): +0 "U64SONG", 0; +8 version 1; +9 tempo (BPM);
; +10 rows per beat; +11 song length (order list entries); +12 loop
; position ($FF: none); +16 title (31 + 0); +48 composer (31 + 0); +128
; the 24 voices' recording cursors (16 bits each).
;
; ----------------------------------------------------------------------------

SH_TEMPO    = 9
SH_RPB      = 10
SH_LEN      = 11
SH_LOOP     = 12
SH_TITLE    = 16
SH_COMP     = 48
SH_CURS     = 128

; ----------------------------------------------------------------------------
; cmd_song
;   Summary: *SONG [NEW [bpm [rows per beat]] | RECORD [OFF] | PLAY [pos]
;            | STOP | TEMPO bpm | TITLE text | COMPOSER text | SAVE file |
;            LOAD file]: the song in the REU; without a word: show it.
;   Input:   mosPTR/Y.  Output: raises on errors.  Uses: A, X, Y, fs*,
;            MOSBUF.
cmd_song:
    jsr s6_hasreu
    bne sg_reu
    brk
    dta 189, 'Songs need an REU', 0
sg_reu:
    ldx #0                      ; the word: sg_words, sg_jumps
sg_try:
    lda sg_words+1,x
    beq sg_none
    stx fsSX
    lda sg_words,x              ; A/X = the word
    pha
    lda sg_words+1,x
    tax
    pla
    jsr s6_word
    ldx fsSX
    bcs sg_found
    inx
    inx
    bne sg_try
sg_found:
    lda sg_jumps+1,x
    pha
    lda sg_jumps,x
    pha
    rts
sg_none:
    jsr s6_end                  ; no word: show the song
    jmp sg_show

sg_words:
    dta a(sw_new), a(sw_record), a(sw_play), a(cw_stop), a(sw_tempo)
    dta a(sw_title), a(sw_comp), a(s6w_save), a(s6w_load), 0, 0
sg_jumps:
    dta a(sg_new-1), a(sg_rec-1), a(sg_play-1), a(sg_stop-1)
    dta a(sg_tempo-1), a(sg_title-1), a(sg_comp-1), a(sg_save-1)
    dta a(sg_load-1)
sw_new      dta 'NEW', 0
sw_record   dta 'RECORD', 0
sw_play     dta 'PLAY', 0
sw_tempo    dta 'TEMPO', 0
sw_title    dta 'TITLE', 0
sw_comp     dta 'COMPOSER', 0

; ----------------------------------------------------------------------------
; REU access for the song: sg_hget / sg_hput: the 256-byte header <->
; MOSBUF; sg_dma: A = command, fsTMP = REU address (3), fsADDR = C64
; address, fsLEN = length

sg_hget:
    lda #REU_TO_C64
    bne sgh_go
sg_hput:
    lda #REU_TO_REU
sgh_go:
    pha
    lda #<REU_HEAD
    sta fsTMP
    lda #>REU_HEAD
    sta fsTMP+1
    lda #REU_SONGBANK
    sta fsTMP+2
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #0
    sta fsLEN
    lda #1
    sta fsLEN+1
    pla
sg_dma:
    php                         ; (interrupts off while the REU is set up:
    sei                         ; the sound interrupt uses it too)
    pha
    lda fsADDR
    sta REU_C64
    lda fsADDR+1
    sta REU_C64+1
    lda fsTMP
    sta REU_ADDR
    lda fsTMP+1
    sta REU_ADDR+1
    lda fsTMP+2
    sta REU_BANK
    lda fsLEN
    sta REU_LEN
    lda fsLEN+1
    sta REU_LEN+1
    lda #0
    sta REU_CTRL
    pla
    sta REU_CMD
    plp
    rts

; sg_valid: the header in MOSBUF; raises "No song" unless it is one
sg_valid:
    jsr sg_hget
    ldx #7
sgv_l:
    lda MOSBUF,x
    cmp sg_magic,x
    bne sgv_bad
    dex
    bpl sgv_l
    rts
sgv_bad:
    brk
    dta 214, 'No song (*SONG NEW)', 0
sg_magic    dta 'U64SONG', 0

; ----------------------------------------------------------------------------
; *SONG NEW [bpm [rows per beat]]: an empty song: header (tempo 120, 4
; rows per beat by default), order list 0, 1, 2, ..., 64 rows per pattern,
; every pattern cleared, cursors 0; playing and recording stop
sg_new:
    lda #120
    sta fsSY                    ; tempo
    lda #4
    sta fsSX                    ; rows per beat
    jsr s6_num
    bcs sgn_go
    jsr sg_bpmchk
    sta fsSY
    jsr s6_num
    bcs sgn_go
    lda mosNUM+1
    bne sgn_syn
    lda mosNUM
    beq sgn_syn
    cmp #17
    bcc sgn_rpb
sgn_syn:
    jmp s6_syntax
sgn_rpb:
    sta fsSX
sgn_go:
    jsr s6_end
    jsr sg_halt
    lda #0
    sta t_rec
    ldx #0                      ; header
    txa
sgn_clr:
    sta MOSBUF,x
    inx
    bne sgn_clr
    ldx #7
sgn_magic:
    lda sg_magic,x
    sta MOSBUF,x
    dex
    bpl sgn_magic
    lda #1
    sta MOSBUF+8
    lda fsSY
    sta MOSBUF+SH_TEMPO
    lda fsSX
    sta MOSBUF+SH_RPB
    lda #$FF
    sta MOSBUF+SH_LOOP
    jsr sg_hput
    ldx #0                      ; order list: 0, 1, 2, ...
sgn_ord:
    txa
    sta MOSBUF,x
    inx
    bne sgn_ord
    lda #>REU_ORDER
    jsr sg_page
    ldx #0                      ; rows: 64 each
    lda #64
sgn_rows:
    sta MOSBUF,x
    inx
    bne sgn_rows
    lda #>REU_ROWS
    jsr sg_page
    lda #0                      ; patterns: banks 2 and 3 to 0 (one zero
    sta MOSBUF                  ; byte, the C64 address held still)
    lda #REU_PATBANK
    jsr sg_zbank
    lda #REU_PATBANK+1
    ; (fall through)
; sg_zbank: REU bank A (64K) to 0 from MOSBUF+0 (= 0)
sg_zbank:
    php
    sei
    sta REU_BANK
    lda #0
    sta REU_ADDR
    sta REU_ADDR+1
    sta REU_LEN                 ; (0: 64K)
    sta REU_LEN+1
    lda #<MOSBUF
    sta REU_C64
    lda #>MOSBUF
    sta REU_C64+1
    lda #$80                    ; the C64 address held
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    lda #0
    sta REU_CTRL
    plp
    rts
sgn_bad:
    jmp s6_syntax

; sg_page: MOSBUF (256 bytes) to the song bank's page A
sg_page:
    sta fsTMP+1
    lda #0
    sta fsTMP
    sta fsLEN
    lda #REU_SONGBANK
    sta fsTMP+2
    lda #1
    sta fsLEN+1
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #REU_TO_REU
    jmp sg_dma

; sg_bpmchk: mosNUM = tempo 25-255 -> A ("Syntax" otherwise)
sg_bpmchk:
    lda mosNUM+1
    bne sgn_bad
    lda mosNUM
    cmp #25
    bcc sgn_bad
    rts

; ----------------------------------------------------------------------------
; *SONG RECORD: SOUND writes into the song from now on (SID mode);
; *SONG RECORD OFF: back to playing; the song's length follows from the
; furthest cursor (the last pattern as long as needed)
sg_rec:
    lda #<s6w_off
    ldx #>s6w_off
    jsr s6_word
    php
    jsr s6_end
    jsr sg_valid
    plp
    bcs sgr_off
    jsr sg_halt
    lda #1
    sta t_rec
    rts
sgr_off:
    lda #0
    sta t_rec
    sta fsCNT                   ; the furthest cursor (rows)
    sta fsCNT+1
    ldx #0
sgr_max:
    lda MOSBUF+SH_CURS,x
    cmp fsCNT
    lda MOSBUF+SH_CURS+1,x
    sbc fsCNT+1
    bcc sgr_next
    lda MOSBUF+SH_CURS,x
    sta fsCNT
    lda MOSBUF+SH_CURS+1,x
    sta fsCNT+1
sgr_next:
    inx
    inx
    cpx #NV*2
    bne sgr_max
    lda fsCNT                   ; patterns = (rows + 63) / 64
    ora fsCNT+1
    bne sgr_some
    lda #0
    sta MOSBUF+SH_LEN
    jmp sg_hput
sgr_some:
    lda fsCNT                   ; rows - 1: the last row's pattern and row
    sec
    sbc #1
    sta fsTMP
    lda fsCNT+1
    sbc #0
    sta fsTMP+1
    lda fsTMP                   ; last row in its pattern + 1
    and #63
    clc
    adc #1
    sta fsSY
    ldx #6                      ; pattern = (rows - 1) / 64
sgr_div:
    lsr fsTMP+1
    ror fsTMP
    dex
    bne sgr_div
    lda fsTMP
    sta fsSX
    clc
    adc #1
    sta MOSBUF+SH_LEN
    jsr sg_hput
    lda fsSX                    ; rows of the last pattern
    sta fsTMP
    lda #>REU_ROWS
    sta fsTMP+1
    lda #REU_SONGBANK
    sta fsTMP+2
    lda #<fsSY
    sta fsADDR
    lda #>fsSY
    sta fsADDR+1
    lda #1
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jmp sg_dma

; ----------------------------------------------------------------------------
; sg_record
;   Summary: SOUND while recording: the note in s_qbuf (amplitude, pitch,
;            duration) on voice X goes into the song at the voice's
;            cursor, which moves on by the duration (in rows).
;   Function: pitch P (quarter semitones) -> note (P + 145) / 4 (49 =
;            middle C, 1-96); amplitude 1-64 = instrument, -15..-1 = the
;            voice's instrument at that level (effect &1v), 0 = a rest
;            (key off); duration 0 counts as 1; 255 (-1): one row, no key
;            off after it. A key off goes to the cell after the note (a
;            following note overwrites it). A tied note (flag 4) only
;            continues the note before it (254).
;   Input:   X = voice, s_qbuf.  Output: raises "Song full".
;   Uses:    A, X, Y, fs*, MOSBUF.
sg_record:
    stx fsSX
    txa                         ; the cursor: header +128 + 2 * voice
    asl
    clc
    adc #SH_CURS
    sta fsTMP
    sta fsSY                    ; (kept for the write back)
    lda #>REU_HEAD
    sta fsTMP+1
    lda #REU_SONGBANK
    sta fsTMP+2
    lda #<sg_cur
    sta fsADDR
    lda #>sg_cur
    sta fsADDR+1
    lda #2
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_C64
    jsr sg_dma
    lda s_qbuf+1                ; the cell
    beq sgc_rest
    bmi sgc_level
    sta sg_cell+1               ; instrument (with a level: effect &1v)
    lda s_qlvl
    beq sgc_ilvl
    ora #$10
sgc_ilvl:
    sta sg_cell+2
    jmp sgc_pitch
sgc_level:
    eor #$FF                    ; effect &1v, v = -A
    clc
    adc #1
    and #15
    ora #$10
    sta sg_cell+2
    lda #0
    sta sg_cell+1
sgc_pitch:
    lda s_qbuf+2                ; note = (P + 145) / 4
    clc
    adc #<145
    sta fsCNT
    lda s_qbuf+3
    adc #>145
    bmi sgc_low
    lsr
    ror fsCNT
    lsr
    ror fsCNT
    tax                         ; (the high byte: over 255?)
    bne sgc_high
    lda fsCNT
    beq sgc_low
    cmp #97
    bcc sgc_note
sgc_high:
    lda #96
    bne sgc_note
sgc_low:
    lda #1
sgc_note:
    sta sg_cell
    jmp sgc_put
sgc_rest:
    lda #255
    sta sg_cell
    lda #0
    sta sg_cell+1
    sta sg_cell+2
sgc_put:
    lda s_qbuf                  ; tied (SOUND &4vv): the note goes on (254
    and #QF_TIE                 ; over the key off written after it)
    beq sgc_put2
    lda sg_cell
    cmp #255
    beq sgc_put2
    lda #254
    sta sg_cell
sgc_put2:
    jsr sg_cellput              ; the cell at the cursor
    lda s_qbuf+4                ; cursor += duration
    bne sgc_d
    lda #1
sgc_d:
    cmp #255
    bne sgc_dur
    lda #1
    sta s_qbuf+4                ; (-1: one row, no key off)
    lda #0
    sta sg_cell                 ; (nothing written after it)
    lda #1
sgc_dur:
    clc
    adc sg_cur
    sta sg_cur
    bcc sgc_koff
    inc sg_cur+1
sgc_koff:
    lda sg_cell                 ; a key off after a note (not a rest)
    beq sgc_save
    cmp #255
    beq sgc_save
    lda #255
    sta sg_cell
    lda #0
    sta sg_cell+1
    sta sg_cell+2
    jsr sg_cellput2             ; (past the last pattern: not written)
sgc_save:
    lda fsSY                    ; the cursor back
    sta fsTMP
    lda #>REU_HEAD
    sta fsTMP+1
    lda #REU_SONGBANK
    sta fsTMP+2
    lda #<sg_cur
    sta fsADDR
    lda #>sg_cur
    sta fsADDR+1
    lda #2
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jmp sg_dma

; sg_cellput: sg_cell (3 bytes) to the song at row sg_cur, voice fsSX;
; raises "Song full" past the last pattern (sg_cellput2: then nothing)
sg_cellput:
    jsr sg_celladdr
    bcc sgp_put
    brk
    dta 198, 'Song full', 0
sg_cellput2:
    jsr sg_celladdr
    bcc sgp_put
    rts
sgp_put:
    lda #<sg_cell
    sta fsADDR
    lda #>sg_cell
    sta fsADDR+1
    lda #3
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jmp sg_dma

; sg_celladdr: fsTMP = REU address of row sg_cur, voice fsSX: REU_PAT +
; (row / 64) * $1200 + (row AND 63) * 72 + voice * 3; C = 1 past the end
sg_celladdr:
    lda sg_cur+1                ; pattern = row / 64 (< PAT_MAX)
    sta fsTMP+1
    lda sg_cur
    asl
    rol fsTMP+1
    asl
    rol fsTMP+1
    lda fsTMP+1
    cmp #PAT_MAX
    bcc sga_ok
    rts
sga_ok:
    sta fsCNT                   ; pattern * 18 pages (16 bits: fsTMP+1/+2)
    lda #0
    sta fsTMP+2
    lda fsCNT
    asl
    rol fsTMP+2
    sta fsCNT+1                 ; (pattern * 2)
    lda fsTMP+2
    pha
    lda fsCNT+1
    ldx #3
sga_16:
    asl
    rol fsTMP+2
    dex
    bne sga_16
    clc
    adc fsCNT+1
    sta fsTMP+1
    pla
    adc fsTMP+2
    adc #REU_PATBANK
    sta fsTMP+2
    lda #0
    sta fsTMP
    lda sg_cur                  ; + (row AND 63) * 72 (up to 4536)
    and #63
    sta fsCNT                   ; row * 64 + row * 8
    lda #0
    sta fsCNT+1
    ldx #3
sga_r8:
    asl fsCNT
    rol fsCNT+1
    dex
    bne sga_r8
    lda fsCNT                   ; (row * 8 aside)
    pha
    lda fsCNT+1
    pha
    ldx #3
sga_r64:
    asl fsCNT
    rol fsCNT+1
    dex
    bne sga_r64
    pla
    tax
    pla
    clc
    adc fsCNT
    sta fsCNT
    txa
    adc fsCNT+1
    sta fsCNT+1
    lda fsSX                    ; + voice * 3
    asl
    adc fsSX
    clc
    adc fsCNT
    sta fsCNT
    bcc sga_add
    inc fsCNT+1
sga_add:
    lda fsTMP                   ; fsTMP += fsCNT
    clc
    adc fsCNT
    sta fsTMP
    lda fsTMP+1
    adc fsCNT+1
    sta fsTMP+1
    bcc sga_rts
    inc fsTMP+2
sga_rts:
    clc
    rts

sg_cur      = MOSBUF+$F8        ; 2: the voice's cursor (sg_record)
sg_cell     = MOSBUF+$FA        ; 3: the cell

; ----------------------------------------------------------------------------
; *SONG PLAY [position]: play the song from the start (or that order
; list position); needs the SID engine. *SONG STOP: stop it.
sg_play:
    lda #0
    sta fsSX                    ; position
    jsr s6_num
    bcs sgp_go
    lda mosNUM+1
    bne sgp_syn
    lda mosNUM
    sta fsSX
sgp_go:
    jsr s6_end
    jsr sg_sidchk
    jsr sg_valid
    lda MOSBUF+SH_LEN
    bne sgp_some
    brk
    dta 214, 'The song is empty', 0
sgp_syn:
    jmp s6_syntax
sgp_some:
    lda fsSX
    cmp MOSBUF+SH_LEN
    bcs sgp_syn
    lda #0
    sta t_rec
    jsr sg_rowlen               ; fsCNT = row length (cs * 256)
    php
    sei
    lda #0
    sta snds.t_on
    sta snds.t_row
    lda fsSX
    sta snds.t_ord
    lda MOSBUF+SH_LEN
    sta snds.t_len
    lda MOSBUF+SH_LOOP
    sta snds.t_loop
    lda fsCNT
    sta snds.t_rlen
    sta snds.t_acc              ; (the first row at the next interrupt)
    lda fsCNT+1
    sta snds.t_rlen+1
    sta snds.t_acc+1
    lda #1
    sta snds.t_on
    plp
    rts

; sg_sidchk: raises unless the SID engine is in RAM
sg_sidchk:
    lda snd_on
    beq sgs_no
    lda SNDV_IMG
    beq sgs_no
    rts
sgs_no:
    brk
    dta 254, 'Songs play in SID mode (*SOUND SID)', 0

; sg_stop: *SONG STOP
sg_stop:
    jsr s6_end
    ; (fall through)
; sg_halt: the song stops (if the SID engine plays one); its notes (the
; voices without an end) are released
sg_halt:
    lda snd_on
    beq sgh_rts
    lda SNDV_IMG
    beq sgh_rts
    php
    sei
    lda snds.t_on
    beq sgh_done
    lda #0
    sta snds.t_on
    ldx #NV-1
sgh_v:
    stx snds.s_ch
    lda snds.c_state,x
    cmp #1                      ; (ST_PLAY)
    bne sgh_n
    lda snds.c_dur,x
    cmp #$FF
    bne sgh_n
    jsr snds.s_noteend
sgh_n:
    ldx snds.s_ch
    dex
    bpl sgh_v
sgh_done:
    plp
sgh_rts:
    rts

; sg_rowlen: fsCNT = 1536000 / (tempo * rows per beat): a row in
; centiseconds * 256 (header in MOSBUF)
sg_rowlen:
    lda MOSBUF+SH_TEMPO         ; divisor = tempo * rows per beat
    sta fsTMP
    lda #0
    sta fsTMP+1
    sta fsLEN                   ; product
    sta fsLEN+1
    ldx MOSBUF+SH_RPB
    bne sgl_mul
    inx
sgl_mul:
    lda fsLEN
    clc
    adc fsTMP
    sta fsLEN
    lda fsLEN+1
    adc fsTMP+1
    sta fsLEN+1
    dex
    bne sgl_mul
    lda #<1536000               ; dividend (24 bits) in fsADDR, fsMODE
    sta fsADDR
    lda #>1536000
    sta fsADDR+1
    lda #^1536000
    sta fsTMP+2
    lda #0                      ; remainder
    sta fsCNT
    sta fsCNT+1
    ldx #24
sgl_div:
    asl fsADDR
    rol fsADDR+1
    rol fsTMP+2
    rol fsCNT
    rol fsCNT+1
    lda fsCNT
    sec
    sbc fsLEN
    tay
    lda fsCNT+1
    sbc fsLEN+1
    bcc sgl_no
    sta fsCNT+1
    sty fsCNT
    inc fsADDR
sgl_no:
    dex
    bne sgl_div
    lda fsADDR                  ; quotient (at most 16 bits: tempo * rpb
    sta fsCNT                   ; >= 25)
    lda fsADDR+1
    sta fsCNT+1
    rts

; ----------------------------------------------------------------------------
; *SONG TEMPO bpm: the song's tempo (at once if it plays)
sg_tempo:
    jsr s6_num
    bcs sgt_syn
    jsr sg_bpmchk
    pha
    jsr s6_end
    jsr sg_valid
    pla
    sta MOSBUF+SH_TEMPO
    jsr sg_hput
    lda snd_on
    beq sgt_rts
    lda SNDV_IMG
    beq sgt_rts
    jsr sg_rowlen
    php
    sei
    lda fsCNT
    sta snds.t_rlen
    lda fsCNT+1
    sta snds.t_rlen+1
    plp
sgt_rts:
    rts
sgt_syn:
    jmp s6_syntax

; *SONG TITLE text / COMPOSER text: up to 31 characters
sg_title:
    lda #SH_TITLE
    bne sgt_text
sg_comp:
    lda #SH_COMP
sgt_text:
    pha
    jsr s6_skipsp
    sty fsCNT
    jsr sg_valid
    ldy fsCNT
    pla
    tax
    lda #31
    sta fsCNT+1
sgt_ch:
    lda (mosPTR),y
    cmp #13
    beq sgt_end
    sta MOSBUF,x
    inx
    iny
    dec fsCNT+1
    bne sgt_ch
sgt_end:
    lda #0
    sta MOSBUF,x
    jmp sg_hput

; ----------------------------------------------------------------------------
; *SONG: title, composer, tempo, length, and what it does now
sg_show:
    jsr sg_valid
    lda MOSBUF+SH_TITLE
    beq sgs_comp
    ldx #SH_TITLE
    jsr sg_str
    jsr OSNEWL
sgs_comp:
    lda MOSBUF+SH_COMP
    beq sgs_tempo
    ldx #SH_COMP
    jsr sg_str
    jsr OSNEWL
sgs_tempo:
    lda MOSBUF+SH_TEMPO
    jsr s6_dec8
    jsr s6_text
    dta ' bpm, ', 0
    lda MOSBUF+SH_RPB
    jsr s6_dec8
    jsr s6_text
    dta ' rows per beat, ', 0
    lda MOSBUF+SH_LEN
    jsr s6_dec8
    jsr s6_text
    dta ' patterns', 13, 0
    lda t_rec
    beq sgs_play
    jsr s6_text
    dta 'Recording', 13, 0
    rts
sgs_play:
    lda snd_on
    beq sgs_rts
    lda SNDV_IMG
    beq sgs_rts
    lda snds.t_on
    beq sgs_rts
    jsr s6_text
    dta 'Playing: position ', 0
    lda snds.t_ord
    jsr s6_dec8
    jsr s6_text
    dta ', row ', 0
    lda snds.t_row
    jsr s6_dec8
    jsr OSNEWL
sgs_rts:
    rts
; sg_str: print the text at MOSBUF+X (0-terminated)
sg_str:
    lda MOSBUF,x
    beq sgst_rts
    jsr OSASCI
    inx
    bne sg_str
sgst_rts:
    rts

; ----------------------------------------------------------------------------
; *SONG SAVE file: header, order list, rows (3 pages) and the patterns
; up to the highest one the order list uses (18 pages each).
; *SONG LOAD file: the same back (whatever the file holds).
sg_save:
    jsr s6_name
    jsr s6_end
    jsr sg_valid
    jsr sg_halt
    lda #0                      ; the highest pattern used
    sta fsSY
    lda #>REU_ORDER             ; (order list to MOSBUF)
    sta fsTMP+1
    lda #0
    sta fsTMP
    lda #REU_SONGBANK
    sta fsTMP+2
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #0
    sta fsLEN
    lda #1
    sta fsLEN+1
    lda #REU_TO_C64
    jsr sg_dma
    jsr sg_hdrlen               ; X = song length (from the header)
    beq sgv_open
sgv_max:
    dex
    lda MOSBUF,x
    cmp fsSY
    bcc sgv_n
    sta fsSY
sgv_n:
    txa
    bne sgv_max
sgv_open:
    jsr sg_pages                ; fsCNT = (highest + 1) * 18 pages: in two
    lda fsCNT                   ; writes of at most 252 (kept on the stack:
    sec                         ; the UCI routines use the fs variables)
    sbc #252
    tax
    lda fsCNT+1
    sbc #0
    bcs sgv_two
    lda #0                      ; under 252: one write
    pha
    lda fsCNT
    pha
    jmp sgv_go
sgv_two:
    txa
    pha                         ; second: total - 252
    lda #252
    pha                         ; first: 252
sgv_go:
    farcall rx_create, BANK_FS
    lda #REU_SONGBANK
    ldy #0
    ldx #3
    farcall rx_write, BANK_FS
    pla
    tax
    lda #REU_PATBANK
    ldy #0
    farcall rx_write, BANK_FS
    pla
    beq sgv_close
    tax
    lda #REU_PATBANK
    ldy #252
    farcall rx_write, BANK_FS
sgv_close:
    farcall rx_close, BANK_FS
    rts

; sg_hdrlen: X = the song length (header byte, read from the REU)
sg_hdrlen:
    php
    sei
    lda #SH_LEN
    sta REU_ADDR
    lda #>REU_HEAD
    sta REU_ADDR+1
    lda #REU_SONGBANK
    sta REU_BANK
    lda #<fsCNT
    sta REU_C64
    lda #>fsCNT
    sta REU_C64+1
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    plp
    ldx fsCNT
    rts

; sg_pages: fsCNT (16 bits) = (fsSY + 1) * 18, at most PAT_MAX * 18
sg_pages:
    lda fsSY
    cmp #PAT_MAX
    bcc sgpg_ok
    lda #PAT_MAX-1
sgpg_ok:
    clc
    adc #1
    sta fsTMP
    lda #0
    sta fsCNT
    sta fsCNT+1
    ldx #18
sgpg_mul:
    lda fsCNT
    clc
    adc fsTMP
    sta fsCNT
    bcc sgpg_n
    inc fsCNT+1
sgpg_n:
    dex
    bne sgpg_mul
    rts

sg_load:
    jsr s6_name
    jsr s6_end
    jsr sg_halt
    lda #0
    sta t_rec
    farcall rx_openin, BANK_FS
    lda #REU_SONGBANK
    ldy #0
    ldx #3
    farcall rx_read, BANK_FS
    cpx #3
    bne sgl_bad
    lda #REU_PATBANK            ; the patterns: up to PAT_MAX
    ldy #0
    ldx #252
    farcall rx_read, BANK_FS
    cpx #252
    bne sgl_done
    lda #REU_PATBANK
    ldy #252
    ldx #PAT_MAX*18-252
    farcall rx_read, BANK_FS
sgl_done:
    farcall rx_close, BANK_FS
    jmp sg_valid
sgl_bad:
    farcall rx_close, BANK_FS
    brk
    dta 214, 'No song', 0

; ----------------------------------------------------------------------------
; sg_adval: ADVAL(-29-v) (X = &E3 - v, v = 0-23): the note (1-96, 49 =
; middle C) voice v plays now in SID mode, 0 if none; ADVAL(-53) and
; lower: 0
sg_adval:
    cpx #$CC
    bcc sga_zero
    lda snd_on
    beq sga_zero
    lda SNDV_IMG
    beq sga_zero
    txa                         ; v = &E3 - X
    eor #$FF
    sec
    sbc #$1C
    tax
    lda snds.c_state,x
    cmp #1                      ; (ST_PLAY)
    bne sga_zero
    lda snds.c_mod,x
    bmi sga_zero                ; (a raw frequency)
    lda snds.c_tgtlo,x          ; note = (pitch - 1472 + 32) / 64
    sec
    sbc #<[1472-32]
    sta fsCNT
    lda snds.c_tgthi,x
    sbc #>[1472-32]
    bcc sga_zero
    asl fsCNT
    rol
    asl fsCNT
    rol                         ; (/ 64: the high byte after << 2)
    beq sga_zero
    cmp #97
    bcs sga_zero
    tax
    rts
sga_zero:
    ldx #0
    rts
