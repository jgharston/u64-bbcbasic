; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the REU RAM disk (bank 5)
;
; A flat directory of files kept in the REU from $100000 to its end
; (PLAN.md section 23, item 2), reached as the directory /REU
; (fs.s, ucmds.s route names there). Survives a reset, not switching
; off; recognised at start-up by its header, else made empty.
;
;   $100000   header: "U64RDISK", version 1, (3 free), data end (24 bits)
;   $100020   127 entries of 32 bytes: used flag, name (16, 0 padded),
;             start (24 bits), length (24 bits), load and execution
;             address (16 bits each)
;   $101000   file data, one file after another; deleting a file moves
;             the files after it down (no gaps)
;
; Interface (from bank 2, through MOSBUF): RD_NAME / RD_NAME2 names (up
; to 16 characters, 0 terminated), RD_BUF a 128-byte data piece, RD_ENT
; the entry worked on, RD_LDADR/RD_EXADR addresses; fsADDR/fsLEN C64 address
; and length; errors raise (BRK). Only this bank's code runs here.
;
; ----------------------------------------------------------------------------

RD_BUF      = MOSBUF            ; 128: data piece (*TYPE, *COPY)
RD_NAME     = MOSBUF+$80        ; 17
RD_HDR      = MOSBUF+$91        ; 15: the header
RD_HDRLEN   = 15
RD_ENT      = MOSBUF+$A0        ; 32: an entry
RD_NAME2    = MOSBUF+$C0        ; 17: *RENAME's new name
RD_LDADR     = MOSBUF+$E0        ; 2
RD_EXADR     = MOSBUF+$E2        ; 2
RD_POS      = MOSBUF+$E4        ; 3: reading / writing position (REU)
RD_LEFT     = MOSBUF+$E7        ; 3: bytes left to read
RD_IDX      = MOSBUF+$EA        ; entry being written (rd_create)

RDE_USED    = RD_ENT+0
RDE_NAME    = RD_ENT+1
RDE_START   = RD_ENT+17
RDE_LEN     = RD_ENT+20
RDE_LOAD    = RD_ENT+23
RDE_EXEC    = RD_ENT+25

RD_BANK     = $10               ; header at $100000
RD_DATA     = $1000             ; data from $101000 (bank RD_BANK)
RD_ENTRIES  = 127

; ----------------------------------------------------------------------------
; rd_boot
;   Summary: at start-up: an REU of 2 MB or more gets a RAM disk; its
;            header is kept if valid, else the disk is made empty.
;   Output:  rd_ok (resident) = 1 if there is a RAM disk.
;   Uses:    A, X, Y.
rd_boot:
    lda #0
    sta rd_ok
    lda reu_banks+1             ; 16 MB: 256 banks
    bne rb_size
    lda reu_banks
    cmp #RD_BANK+1
    bcc rb_rts                  ; under 2 MB (with 1 MB nothing is left)
rb_size:
    inc rd_ok
    jsr rd_hdrget               ; the header to RD_HDR
    ldx #7
rb_magic:
    lda RD_HDR,x
    cmp rd_magic,x
    bne rd_format
    dex
    bpl rb_magic
rb_rts:
    rts

; rd_format: an empty disk (header + 127 free entries)
rd_format:
    ldx #RD_HDRLEN-1            ; header: magic, version, data end $101000
rf_clr:
    lda #0
    sta RD_HDR,x
    dex
    bpl rf_clr
    ldx #7
rf_magic:
    lda rd_magic,x
    sta RD_HDR,x
    dex
    bpl rf_magic
    lda #1
    sta RD_HDR+8
    lda #<RD_DATA
    sta RD_HDR+12
    lda #>RD_DATA
    sta RD_HDR+13
    lda #RD_BANK
    sta RD_HDR+14
    jsr rd_hdrput
    lda #0                      ; the entries: all free
    ldx #31
rf_e:
    sta RD_ENT,x
    dex
    bpl rf_e
    ldx #0
rf_ent:
    stx fsSX
    jsr rd_entput
    ldx fsSX
    inx
    cpx #RD_ENTRIES
    bne rf_ent
    rts

rd_magic    dta 'U64RDISK'

; ----------------------------------------------------------------------------
; DMA helpers. rd_dma: A = REU command, C64 address fsADDR, REU address
; fsTMP (3 bytes), length fsLEN.

rd_dma:
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
    rts

; rd_hdrget / rd_hdrput: the header <-> RD_HDR (not RD_BUF: rd_append
; reads the header while RD_BUF holds the data)
rd_hdrget:
    lda #REU_TO_C64
    bne rh_go
rd_hdrput:
    lda #REU_TO_REU
rh_go:
    pha
    jsr rd_save_regs
    lda #<RD_HDR
    sta fsADDR
    lda #>RD_HDR
    sta fsADDR+1
    lda #0
    sta fsTMP
    sta fsTMP+1
    sta fsLEN+1
    lda #RD_BANK
    sta fsTMP+2
    lda #RD_HDRLEN
    sta fsLEN
    pla
    jsr rd_dma
    jmp rd_rest_regs

; rd_entget / rd_entput: entry fsSX <-> RD_ENT ($100020 + X * 32)
rd_entget:
    lda #REU_TO_C64
    bne re_go
rd_entput:
    lda #REU_TO_REU
re_go:
    pha
    jsr rd_save_regs
    lda #<RD_ENT
    sta fsADDR
    lda #>RD_ENT
    sta fsADDR+1
    lda fsSX                    ; $20 + X * 32 (X < 127: up to $0FE0)
    clc
    adc #1
    sta fsTMP+1
    lda #0
    lsr fsTMP+1
    ror
    lsr fsTMP+1
    ror
    lsr fsTMP+1
    ror
    sta fsTMP
    lda #RD_BANK
    sta fsTMP+2
    lda #32
    sta fsLEN
    lda #0
    sta fsLEN+1
    pla
    jsr rd_dma
    jmp rd_rest_regs

; the caller's fsADDR, fsTMP, fsLEN are kept around the small transfers
rd_save_regs:
    lda fsADDR
    sta rd_sv
    lda fsADDR+1
    sta rd_sv+1
    lda fsTMP
    sta rd_sv+2
    lda fsTMP+1
    sta rd_sv+3
    lda fsTMP+2
    sta rd_sv+4
    lda fsLEN
    sta rd_sv+5
    lda fsLEN+1
    sta rd_sv+6
    rts
rd_rest_regs:
    lda rd_sv
    sta fsADDR
    lda rd_sv+1
    sta fsADDR+1
    lda rd_sv+2
    sta fsTMP
    lda rd_sv+3
    sta fsTMP+1
    lda rd_sv+4
    sta fsTMP+2
    lda rd_sv+5
    sta fsLEN
    lda rd_sv+6
    sta fsLEN+1
    rts
rd_sv       = MOSBUF+$F0        ; 7

; ----------------------------------------------------------------------------
; rd_need: raise if there is no RAM disk
rd_need:
    lda rd_ok
    beq rn_none
    rts
rn_none:
    brk
    dta 214, 'No RAM disk (REU of 2 MB or more needed)', 0

; ----------------------------------------------------------------------------
; rd_lookup
;   Summary: find the file named in RD_NAME (case does not matter).
;   Output:  C = 0: found, fsSX = entry, RD_ENT = it; C = 1: not found,
;            fsSY = a free entry ($FF: none).
;   Uses:    A, X, Y.
rd_lookup:
    jsr rd_need
    lda #$FF
    sta fsSY
    ldx #0
rl_ent:
    stx fsSX
    jsr rd_entget
    lda RDE_USED
    bne rl_cmp
    lda fsSY                    ; the first free one
    cmp #$FF
    bne rl_next
    lda fsSX
    sta fsSY
    jmp rl_next
rl_cmp:
    ldy #0
rl_ch:
    lda RD_NAME,y
    jsr rd_up
    sta fsCNT
    lda RDE_NAME,y
    jsr rd_up
    cmp fsCNT
    bne rl_next
    lda RD_NAME,y               ; both ended?
    beq rl_found
    iny
    cpy #16
    bne rl_ch
rl_found:
    clc
    rts
rl_next:
    ldx fsSX
    inx
    cpx #RD_ENTRIES
    bne rl_ent
    sec
    rts

; ----------------------------------------------------------------------------
; rd_load
;   Summary: OSFILE &FF on /REU: the file to C64 memory.
;   Input:   RD_NAME; fsADDR = address, or fsMODE <> 0: its own load
;            address.  Output: fsLEN = length.  Raises: not found, too
;            long for memory (LOAD_LOW-$7FFF).
;   Uses:    A, X, Y, fs*.
rd_load:
    jsr rd_lookup
    bcc rld_found
    brk
    dta 214, 'File not found', 0
rld_found:
    lda fsMODE
    beq rld_addr
    lda RDE_LOAD
    sta fsADDR
    lda RDE_LOAD+1
    sta fsADDR+1
rld_addr:
    lda RDE_LEN+2               ; 32K at most
    bne rld_big
    lda RDE_LEN
    sta fsLEN
    lda RDE_LEN+1
    sta fsLEN+1
    lda fsADDR+1                ; LOAD_LOW <= address, end <= $8000
    cmp #>LOAD_LOW
    bcc rld_big
    lda fsADDR
    clc
    adc fsLEN
    lda fsADDR+1
    adc fsLEN+1
    bcs rld_big
    cmp #$80
    bcc rld_ok
    bne rld_big
    lda fsADDR
    clc
    adc fsLEN
    bne rld_big
rld_ok:
    lda fsLEN                   ; an empty file: nothing to copy
    ora fsLEN+1
    beq rld_rts
    lda RDE_START
    sta fsTMP
    lda RDE_START+1
    sta fsTMP+1
    lda RDE_START+2
    sta fsTMP+2
    lda #REU_TO_C64
    jmp rd_dma
rld_rts:
    rts
rld_big:
    brk
    dta 198, 'No room', 0

; ----------------------------------------------------------------------------
; rd_save
;   Summary: OSFILE 0 on /REU: C64 memory fsADDR, fsLEN bytes, to the file
;            RD_NAME (an old file of that name is replaced), with load and
;            execution addresses RD_LDADR, RD_EXADR.
;   Uses:    A, X, Y, fs*.
rd_save:
    jsr rd_lookup
    bcs rsv_new
    lda fsADDR                  ; replace: the old one goes first (its
    pha                         ; move uses fsADDR and fsLEN)
    lda fsADDR+1
    pha
    lda fsLEN
    pha
    lda fsLEN+1
    pha
    jsr rd_delent
    pla
    sta fsLEN+1
    pla
    sta fsLEN
    pla
    sta fsADDR+1
    pla
    sta fsADDR
    jsr rd_lookup               ; (for a free entry)
rsv_new:
    lda fsSY
    cmp #$FF
    bne rsv_entry
    brk
    dta 196, 'RAM disk full (127 files)', 0
rsv_entry:
    sta fsSX
    jsr rd_room                 ; fsTMP = data end; room for fsLEN?
    lda fsLEN
    ora fsLEN+1
    beq rsv_put
    lda #REU_TO_REU
    jsr rd_dma
rsv_put:
    jsr rd_newent               ; entry: name, start fsTMP, length fsLEN
    jmp rd_endadd               ; data end += length

; rd_room: fsTMP = the data end; raises if fsLEN more bytes do not fit
rd_room:
    jsr rd_hdrget
    lda RD_HDR+12
    sta fsTMP
    lda RD_HDR+13
    sta fsTMP+1
    lda RD_HDR+14
    sta fsTMP+2
    lda fsTMP                   ; end + length (24 bits) <= REU size
    clc
    adc fsLEN
    lda fsTMP+1
    adc fsLEN+1
    lda fsTMP+2
    adc #0
    bcs rrm_full                ; past 16 MB
    ldx reu_banks+1
    bne rrm_ok                  ; 16 MB: every 24-bit address is there
    cmp reu_banks               ; bank of the end < REU banks (an end on
    bcc rrm_ok                  ; a bank boundary: equal is fine only
    bne rrm_full                ; with no bytes in that bank)
    lda fsTMP
    clc
    adc fsLEN
    bne rrm_full
    lda fsTMP+1
    adc fsLEN+1
    bne rrm_full
rrm_ok:
    rts
rrm_full:
    brk
    dta 198, 'RAM disk full', 0

; rd_newent: entry fsSX = name RD_NAME, start fsTMP, length fsLEN (16
; bits), RD_LDADR, RD_EXADR
rd_newent:
    ldx #31
rne_clr:
    lda #0
    sta RD_ENT,x
    dex
    bpl rne_clr
    lda #1
    sta RDE_USED
    ldy #0
rne_name:
    lda RD_NAME,y
    sta RDE_NAME,y
    beq rne_named
    iny
    cpy #16
    bne rne_name
rne_named:
    lda fsTMP
    sta RDE_START
    lda fsTMP+1
    sta RDE_START+1
    lda fsTMP+2
    sta RDE_START+2
    lda fsLEN
    sta RDE_LEN
    lda fsLEN+1
    sta RDE_LEN+1
    lda RD_LDADR
    sta RDE_LOAD
    lda RD_LDADR+1
    sta RDE_LOAD+1
    lda RD_EXADR
    sta RDE_EXEC
    lda RD_EXADR+1
    sta RDE_EXEC+1
    jmp rd_entput

; rd_endadd: header data end += fsLEN
rd_endadd:
    jsr rd_hdrget
    lda RD_HDR+12
    clc
    adc fsLEN
    sta RD_HDR+12
    lda RD_HDR+13
    adc fsLEN+1
    sta RD_HDR+13
    bcc rea_put
    inc RD_HDR+14
rea_put:
    jmp rd_hdrput

; ----------------------------------------------------------------------------
; rd_delete
;   Summary: *DELETE / OSFILE 6 on /REU.
;   Output:  C = 1 if there was no such file.  Uses: A, X, Y, fs*.
rd_delete:
    jsr rd_lookup
    bcs rdd_rts
    jsr rd_delent
    clc
rdd_rts:
    rts

; rd_delent
;   Summary: remove entry fsSX (in RD_ENT) and its data (rd_gapdel).
;   Uses:    A, X, Y, fs*.
rd_delent:
    ldx #1                      ; open on a channel? (as a BBC: "Open")
rdl_open:
    lda ch_open,x
    lsr
    bcc rdl_shut
    lda rd_chent,x
    cmp fsSX
    bne rdl_shut
    brk
    dta 194, 'Open', 0
rdl_shut:
    dex
    bpl rdl_open
    lda #0                      ; the entry is free
    sta RDE_USED
    jsr rd_entput
    ldx #2                      ; the gap: its data
rde_gap:
    lda RDE_START,x
    sta rd_to,x
    lda RDE_LEN,x
    sta rd_gap,x
    dex
    bpl rde_gap
    ; (fall through)

; rd_gapdel
;   Summary: close the gap of rd_gap bytes at REU address rd_to: the data
;            after it moves down (through RD_BUF, 128 bytes at a time),
;            the entries of those files follow, the data end comes down.
;   Uses:    A, X, Y, fs*.
rd_gapdel:
    lda rd_to                   ; from = to + gap (also kept in rd_del:
    clc                         ; the files from there on move down)
    adc rd_gap
    sta rd_from
    sta rd_del
    lda rd_to+1
    adc rd_gap+1
    sta rd_from+1
    sta rd_del+1
    lda rd_to+2
    adc rd_gap+2
    sta rd_from+2
    sta rd_del+2
    jsr rd_hdrget               ; bytes to move = data end - from
    lda RD_HDR+12
    sec
    sbc rd_from
    sta rd_cnt
    lda RD_HDR+13
    sbc rd_from+1
    sta rd_cnt+1
    lda RD_HDR+14
    sbc rd_from+2
    sta rd_cnt+2
    lda RD_HDR+12               ; data end -= gap
    sec
    sbc rd_gap
    sta RD_HDR+12
    lda RD_HDR+13
    sbc rd_gap+1
    sta RD_HDR+13
    lda RD_HDR+14
    sbc rd_gap+2
    sta RD_HDR+14
    jsr rd_hdrput
    jsr rd_move
    ldx #0                      ; files after the gap: start -= gap
rdl_e:
    stx fsSX
    jsr rd_entget
    lda RDE_USED
    beq rdl_en
    lda RDE_START               ; start >= the gap's end? (a file of
    sec                         ; length 0 at the gap's start stays)
    sbc rd_del
    lda RDE_START+1
    sbc rd_del+1
    lda RDE_START+2
    sbc rd_del+2
    bcc rdl_en
    lda RDE_START
    sec
    sbc rd_gap
    sta RDE_START
    lda RDE_START+1
    sbc rd_gap+1
    sta RDE_START+1
    lda RDE_START+2
    sbc rd_gap+2
    sta RDE_START+2
    jsr rd_entput
rdl_en:
    ldx fsSX
    inx
    cpx #RD_ENTRIES
    bne rdl_e
    rts

; rd_move
;   Summary: copy rd_cnt bytes (24 bits) in the REU from rd_from to rd_to,
;            lowest address first (a move down, or to free space above).
;   Function: 128 bytes at a time through RD_BUF.
;   Output:  rd_from, rd_to advanced; rd_cnt = 0.  Uses: A, X, fs*.
rd_move:
    lda rd_cnt
    ora rd_cnt+1
    ora rd_cnt+2
    bne rmv_piece
    rts
rmv_piece:
    lda #128
    ldx rd_cnt+1
    bne rmv_n
    ldx rd_cnt+2
    bne rmv_n
    lda rd_cnt
    cmp #128
    bcc rmv_n
    lda #128
rmv_n:
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #<RD_BUF
    sta fsADDR
    lda #>RD_BUF
    sta fsADDR+1
    ldx #2
rmv_src:
    lda rd_from,x
    sta fsTMP,x
    dex
    bpl rmv_src
    lda #REU_TO_C64
    jsr rd_dma
    ldx #2
rmv_dst:
    lda rd_to,x
    sta fsTMP,x
    dex
    bpl rmv_dst
    lda #REU_TO_REU
    jsr rd_dma
    ldx #0                      ; from, to += piece; count -= piece
    jsr rdl_add
    ldx #3
    jsr rdl_add
    lda rd_cnt
    sec
    sbc fsLEN
    sta rd_cnt
    bcs rd_move
    lda rd_cnt+1
    bne rmv_dec
    dec rd_cnt+2
rmv_dec:
    dec rd_cnt+1
    jmp rd_move

; rdl_add: the 3 bytes at rd_from + X += fsLEN (rd_to is rd_from + 3)
rdl_add:
    lda rd_from,x
    clc
    adc fsLEN
    sta rd_from,x
    bcc rda_rts
    inc rd_from+1,x
    bne rda_rts
    inc rd_from+2,x
rda_rts:
    rts

; rd_tolast
;   Summary: make the file of entry RD_IDX (in RD_ENT) the last one, so
;            that it can grow (an open file written past its end).
;   Function: already last: nothing. Length 0: its start becomes the data
;            end. Else its data is copied to the data end, the entry
;            points there, and the gap it leaves is closed (rd_gapdel,
;            which moves the copy down with the files after the gap).
;   Output:  RD_ENT = the entry, now ending at the data end.
;   Uses:    A, X, Y, fs*.
rd_tolast:
    lda RD_IDX
    sta fsSX
    jsr rd_entget
    jsr rd_hdrget
    lda RDE_START               ; start + length = data end?
    clc
    adc RDE_LEN
    tax
    lda RDE_START+1
    adc RDE_LEN+1
    tay
    lda RDE_START+2
    adc RDE_LEN+2
    cmp RD_HDR+14
    bne rtl_move
    cpy RD_HDR+13
    bne rtl_move
    cpx RD_HDR+12
    bne rtl_move
    rts
rtl_move:
    lda RDE_LEN                 ; room for a copy?
    sta fsLEN
    lda RDE_LEN+1
    sta fsLEN+1
    lda RDE_LEN+2
    beq rtl_room
    brk
    dta 198, 'RAM disk full', 0
rtl_room:
    jsr rd_room                 ; (fsTMP = data end; files over 64K
    ldx #2                      ; that are not last cannot grow)
rtl_set:
    lda RDE_START,x             ; copy: from the start to the data end
    sta rd_from,x
    lda fsTMP,x
    sta rd_to,x
    lda RDE_LEN,x
    sta rd_cnt,x
    sta rd_gap,x
    dex
    bpl rtl_set
    lda fsTMP                   ; the new start (rd_move uses fsTMP)
    pha
    lda fsTMP+1
    pha
    lda fsTMP+2
    pha
    jsr rd_move
    lda RDE_LEN
    sta fsLEN
    lda RDE_LEN+1
    sta fsLEN+1
    jsr rd_endadd               ; data end += length
    lda RDE_START               ; the gap: the old place
    sta rd_to
    lda RDE_START+1
    sta rd_to+1
    lda RDE_START+2
    sta rd_to+2
    pla                         ; the entry: at the old data end
    sta RDE_START+2
    pla
    sta RDE_START+1
    pla
    sta RDE_START
    lda RD_IDX
    sta fsSX
    jsr rd_entput
    jsr rd_gapdel
    lda RD_IDX
    sta fsSX
    jmp rd_entget

rd_from     = MOSBUF+$F8        ; 3 (rd_to must follow)
rd_to       = rd_from+3         ; 3 (to $FD)
rd_gap      = MOSBUF+$EB        ; 3
rd_del      = MOSBUF+$D1        ; 3: end of the gap (rd_gapdel)
rd_cnt      = RD_POS            ; 3 (RD_POS: reading only, not then)

; ----------------------------------------------------------------------------
; rd_rename: RD_NAME -> RD_NAME2 (raises if missing or the new name is
; taken)
rd_rename:
    ldx #16                     ; new name taken?
rrn_sw1:
    lda RD_NAME,x
    pha
    lda RD_NAME2,x
    sta RD_NAME,x
    pla
    sta RD_NAME2,x
    dex
    bpl rrn_sw1
    jsr rd_lookup
    php
    ldx #16                     ; names back
rrn_sw2:
    lda RD_NAME,x
    pha
    lda RD_NAME2,x
    sta RD_NAME,x
    pla
    sta RD_NAME2,x
    dex
    bpl rrn_sw2
    plp
    bcs rrn_free
    brk
    dta 196, 'File exists', 0
rrn_free:
    jsr rd_lookup
    bcc rrn_found
    brk
    dta 214, 'File not found', 0
rrn_found:
    ldy #0
rrn_copy:
    lda RD_NAME2,y
    sta RDE_NAME,y
    beq rrn_pad
    iny
    cpy #16
    bne rrn_copy
    jmp rd_entput
rrn_pad:
    lda #0
rrn_pl:
    sta RDE_NAME,y
    iny
    cpy #16
    bne rrn_pl
    jmp rd_entput

; ----------------------------------------------------------------------------
; rd_cat
;   Summary: *CAT on /REU: "/REU", then name and length of each file, and
;            the space used and free.
;   Uses:    A, X, Y, fs*.
rd_cat:
    jsr rd_need
    jsr rd_text
    dta '/REU', 13, 0
    lda #0
    sta fsSY                    ; files
    ldx #0
rc_ent:
    stx fsSX
    jsr rd_entget
    lda RDE_USED
    beq rc_next
    inc fsSY
    ldy #0                      ; name, padded to 17
rc_name:
    lda RDE_NAME,y
    beq rc_pad
    jsr OSWRCH
    iny
    cpy #16
    bne rc_name
rc_pad:
    lda #' '
    jsr OSWRCH
    iny
    cpy #17
    bcc rc_pad
    lda RDE_LEN+2               ; length (24 bits, decimal)
    sta rd_n+2
    lda RDE_LEN+1
    sta rd_n+1
    lda RDE_LEN
    sta rd_n
    jsr rd_dec24
    jsr OSNEWL
rc_next:
    ldx fsSX
    inx
    cpx #RD_ENTRIES
    bne rc_ent
    lda fsSY
    sta rd_n
    lda #0
    sta rd_n+1
    sta rd_n+2
    jsr rd_dec24
    jsr rd_text
    dta ' files, ', 0
    jsr rd_hdrget               ; free = REU size - data end, in K
    lda #0
    sec
    sbc RD_HDR+13               ; (low byte of the size is 0)
    sta rd_n
    lda reu_banks
    sbc RD_HDR+14
    sta rd_n+1
    lda reu_banks+1
    sbc #0
    sta rd_n+2
    ldx #2                      ; / 1024: >> 2 of the bank-and-page value
rc_k:
    lsr rd_n+2
    ror rd_n+1
    ror rd_n
    dex
    bne rc_k
    jsr rd_dec24
    jsr rd_text
    dta 'K free', 13, 0
    rts
rd_n        = RD_NAME2          ; 3 (for printing)

; rd_dec24: print rd_n (24 bits) in decimal
rd_dec24:
    ldx #0                      ; digits pushed in reverse
rdd_div:
    lda #0                      ; rd_n / 10, remainder in A
    ldy #24
rdd_bit:
    asl rd_n
    rol rd_n+1
    rol rd_n+2
    rol
    cmp #10
    bcc rdd_nb
    sbc #10
    inc rd_n
rdd_nb:
    dey
    bne rdd_bit
    pha
    inx
    lda rd_n
    ora rd_n+1
    ora rd_n+2
    bne rdd_div
rdd_out:
    pla
    ora #'0'
    jsr OSWRCH
    dex
    bne rdd_out
    rts

; rd_text: print the 0-terminated text after the JSR
rd_text:
    pla
    sta fsBLK
    pla
    sta fsBLK+1
    ldy #1
rt_loop:
    lda (fsBLK),y
    beq rt_end
    jsr OSASCI
    iny
    bne rt_loop
rt_end:
    tya
    clc
    adc fsBLK
    tax
    lda fsBLK+1
    adc #0
    pha
    txa
    pha
    rts

; ----------------------------------------------------------------------------
; Reading in pieces (*TYPE, *COPY from /REU) and writing (*COPY to /REU)

; rd_open: the file RD_NAME for reading: RD_POS = start, RD_LEFT = length
rd_open:
    jsr rd_lookup
    bcc rop_found
    brk
    dta 214, 'File not found', 0
rop_found:
    ldx #2
rop_c:
    lda RDE_START,x
    sta RD_POS,x
    lda RDE_LEN,x
    sta RD_LEFT,x
    dex
    bpl rop_c
    rts

; rd_read: the next piece (up to 128 bytes) into RD_BUF; A = its length
; (0 at the end of the file)
rd_read:
    lda RD_LEFT+1
    ora RD_LEFT+2
    bne rrd_128
    lda RD_LEFT
    beq rrd_rts
    cmp #128
    bcc rrd_n
rrd_128:
    lda #128
rrd_n:
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #<RD_BUF
    sta fsADDR
    lda #>RD_BUF
    sta fsADDR+1
    lda RD_POS
    sta fsTMP
    lda RD_POS+1
    sta fsTMP+1
    lda RD_POS+2
    sta fsTMP+2
    lda #REU_TO_C64
    jsr rd_dma
    lda RD_POS                  ; position += n, left -= n
    clc
    adc fsLEN
    sta RD_POS
    bcc rrd_l
    inc RD_POS+1
    bne rrd_l
    inc RD_POS+2
rrd_l:
    lda RD_LEFT
    sec
    sbc fsLEN
    sta RD_LEFT
    bcs rrd_done
    lda RD_LEFT+1
    bne rrd_d1
    dec RD_LEFT+2
rrd_d1:
    dec RD_LEFT+1
rrd_done:
    lda fsLEN
rrd_rts:
    rts

; rd_create: a new, empty file RD_NAME at the data end, to be filled with
; rd_append and finished with rd_finish (an old one is replaced)
rd_create:
    jsr rd_lookup
    bcs rcr_new
    jsr rd_delent
    jsr rd_lookup
rcr_new:
    lda fsSY
    cmp #$FF
    bne rcr_ok
    brk
    dta 196, 'RAM disk full (127 files)', 0
rcr_ok:
    sta fsSX
    sta RD_IDX
    lda #0
    sta fsLEN
    sta fsLEN+1
    sta RD_LDADR
    sta RD_LDADR+1
    sta RD_EXADR
    sta RD_EXADR+1
    jsr rd_room                 ; fsTMP = data end
    jsr rd_newent               ; length 0 so far
    ldx #2
rcr_pos:
    lda fsTMP,x
    sta RD_POS,x
    dex
    bpl rcr_pos
    rts

; rd_append: A bytes of RD_BUF (1-128) onto the file being written
rd_append:
    sta fsLEN
    lda #0
    sta fsLEN+1
    jsr rd_room                 ; (the file grows at the data end)
    lda #<RD_BUF
    sta fsADDR
    lda #>RD_BUF
    sta fsADDR+1
    lda #REU_TO_REU
    jsr rd_dma
    jsr rd_endadd               ; data end and length += n
    lda RD_IDX
    sta fsSX
    jsr rd_entget
    lda RDE_LEN
    clc
    adc fsLEN
    sta RDE_LEN
    bcc rap_put
    inc RDE_LEN+1
    bne rap_put
    inc RDE_LEN+2
rap_put:
    jmp rd_entput

; rd_info: OSFILE 5 on /REU: C = 1 not found; else RD_ENT holds the entry
rd_info:
    jmp rd_lookup

; rd_up: A in upper case (a-z only); this bank cannot reach bank 2's up2
rd_up:
    cmp #'a'
    bcc ru_rts
    cmp #'z'+1
    bcs ru_rts
    and #$DF
ru_rts:
    rts

; ----------------------------------------------------------------------------
; Open files (OPENIN, OPENOUT, OPENUP, BGET#, BPUT#, PTR#, EXT#, EOF#):
; bank 2 (rdglue.s) keeps PTR# and EXT# per channel as for the Ultimate's
; files, plus the entry (rd_chent); here the data. A file being written
; past its end is moved to the end of the data first (rd_tolast).
; RD_CPTR = PTR# (24 bits), RD_CBYTE = the byte.

RD_CPTR     = MOSBUF+$D4        ; 3
RD_CBYTE    = MOSBUF+$D7

; ----------------------------------------------------------------------------
; rd_fopen
;   Summary: open the file RD_NAME: A = &40 OPENIN, &80 OPENOUT (a new
;            empty file, an old one replaced), &C0 OPENUP.
;   Output:  C = 0: A = entry, RDE_LEN = length (EXT#); C = 1: not found
;            (OPENIN, OPENUP).  Uses: A, X, Y, fs*.
rd_fopen:
    cmp #$80
    bne rfo_find
    jsr rd_create
    lda RD_IDX
    clc
    rts
rfo_find:
    jsr rd_lookup
    bcs rfo_rts
    lda fsSX
rfo_rts:
    rts

; rd_fext: A = entry -> RDE_LEN = its length (EXT#)
rd_fext:
    sta fsSX
    jmp rd_entget

; ----------------------------------------------------------------------------
; rd_fbget
;   Summary: BGET# from entry X at RD_CPTR.
;   Output:  C = 0: A = the byte; C = 1: PTR# at or past the end.
;   Uses:    A, X, Y, fs*.
rd_fbget:
    stx fsSX
    jsr rd_entget
    jsr rd_cpos                 ; past the end?
    bcs rfb_rts
    lda #<RD_CBYTE
    sta fsADDR
    lda #>RD_CBYTE
    sta fsADDR+1
    lda #REU_TO_C64
    jsr rd_dma
    lda RD_CBYTE
    clc
rfb_rts:
    rts

; rd_cpos: C = 1 if RD_CPTR >= the length; else fsTMP = start + PTR#,
; fsLEN = 1
rd_cpos:
    lda RD_CPTR
    cmp RDE_LEN
    lda RD_CPTR+1
    sbc RDE_LEN+1
    lda RD_CPTR+2
    sbc RDE_LEN+2
    bcs rcp_rts
    lda RDE_START
    adc RD_CPTR                 ; (C = 0)
    sta fsTMP
    lda RDE_START+1
    adc RD_CPTR+1
    sta fsTMP+1
    lda RDE_START+2
    adc RD_CPTR+2
    sta fsTMP+2
    lda #1
    sta fsLEN
    lda #0
    sta fsLEN+1
    clc
rcp_rts:
    rts

; ----------------------------------------------------------------------------
; rd_fbput
;   Summary: BPUT# RD_CBYTE to entry X at RD_CPTR.
;   Function: inside the file: written in place. At or past its end: the
;            file is made the last one (rd_tolast), zeros fill up to
;            PTR#, then the byte is appended.
;   Output:  RDE_LEN = the new length (for EXT#).  Uses: A, X, Y, fs*.
rd_fbput:
    stx fsSX
    stx RD_IDX
    jsr rd_entget
    jsr rd_cpos
    bcs rbp_grow
    lda #<RD_CBYTE
    sta fsADDR
    lda #>RD_CBYTE
    sta fsADDR+1
    lda #REU_TO_REU
    jmp rd_dma
rbp_grow:
    jsr rd_tolast
rbp_fill:
    lda RD_CPTR                 ; zeros while length < PTR#
    sec
    sbc RDE_LEN
    sta fsCNT
    lda RD_CPTR+1
    sbc RDE_LEN+1
    tax
    lda RD_CPTR+2
    sbc RDE_LEN+2
    bne rbp_z128
    txa
    bne rbp_z128
    lda fsCNT
    beq rbp_byte
    cmp #128
    bcc rbp_zero
rbp_z128:
    lda #128
rbp_zero:
    pha
    ldx #127
    lda #0
rbp_clr:
    sta RD_BUF,x
    dex
    bpl rbp_clr
    pla
    jsr rd_append
    jmp rbp_fill
rbp_byte:
    lda RD_CBYTE
    sta RD_BUF
    lda #1
    jmp rd_append
