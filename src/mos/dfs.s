; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- DFS commands: *EXEC, *SPOOL, *BUILD, *DUMP, *INFO, *RUN
;
; Bank 7 (.local dfs). They work on any file the filing system reaches
; (the Ultimate's drives, /REU) through the OS calls (OSFIND, OSBGET,
; OSBPUT, OSFILE): no filing-system internals here. docs/DESIGN_ACORN.md 2.
;
; *SPOOL never writes to the file from inside OSWRCH: MOS commands print
; while a UCI transfer or the filing system's variables are in use, and a
; nested BPUT# would break them. The output goes into the REU's last 64K
; (a stub at DF_STUB on WRCHV, sp_put); *SPOOL alone (or another *SPOOL,
; CLOSE#0) writes it to the file and closes it.
;
; *EXEC: key_get (keys.s, bank 0) reads the file's bytes as keys while
; DF_EXEC is set (ex_get); ESCAPE closes it (by_ackesc), as on the BBC.
;
; ----------------------------------------------------------------------------

    .local dfs
    icl 'bankhelp.s'

DF_T        = $0240             ; scratch (8; not MOSBUF: the RAM disk's
                                ; BGET#/BPUT# use it)
DF_DBUF     = $0248             ; 8: *DUMP's line; *BUILD's digits
DF_LINE     = $0700             ; *BUILD's line (BASIC's input line: the
                                ; command was read from it already)
DF_LMAX     = 238
SP_MAX      = $BCF0             ; *SPOOL's room in the REU's last bank

; ----------------------------------------------------------------------------
; cmd_spool
;   Summary: *SPOOL [name]: copy everything printed into a file; *SPOOL
;            alone ends it (the file written and closed).
;   Function: an open spool is written and closed first; the file is
;            opened (created) now, so a bad name fails at once; the REU's
;            last bank collects the output (up to 48368 bytes, &BCF0; more
;            is lost) through the stub on WRCHV.
;   Input:   mosPTR/Y.  Output: DF_SPCH, WRCHV.  Uses: A, X, Y, DF_T.
cmd_spool:
    sty DF_T+6                  ; (the line position: the calls below
    jsr sp_close                ; change Y)
    ldy DF_T+6
    jsr s6_skipsp
    cmp #13
    bne csp_open
    rts
csp_open:
    jsr s6_hasreu
    bne csp_reu
    brk
    dta 254, '*SPOOL needs an REU', 0
csp_reu:
    sty DF_T+6
    farcall rd_spoolok, BANK_RD  ; the RAM disk must end below its bank
    ldy DF_T+6
    bcc csp_room
    brk
    dta 254, 'RAM disk uses the last 64K', 0
csp_room:
    lda #$80                    ; OPENOUT the name on the line
    jsr df_find
    sta DF_SPCH
    farcall rd_lastbank, BANK_RD
    sta DF_SPBANK
    lda #0
    sta DF_SPLEN
    sta DF_SPLEN+1
    ldx #sps_len-1              ; the stub into RAM, on WRCHV
csp_cp:
    lda sps_load,x
    sta DF_STUB,x
    dex
    bpl csp_cp
    php
    sei
    lda #<DF_STUB
    sta WRCHV
    lda #>DF_STUB
    sta WRCHV+1
    plp
    rts

; sp_close: the spool (if any) ended: WRCHV back, the bytes from the REU
; into the file (OSBPUT), the file closed. Uses: A, X, Y, DF_T.
sp_close:
    lda DF_SPCH
    bne spc_go
    rts
spc_go:
    php
    sei
    lda #<mos_wrch
    sta WRCHV
    lda #>mos_wrch
    sta WRCHV+1
    plp
    lda DF_SPCH
    sta DF_T+4                  ; the channel
    lda #0
    sta DF_SPCH
    sta DF_T                    ; position (2)
    sta DF_T+1
spc_byte:
    lda DF_T                    ; all written?
    cmp DF_SPLEN
    lda DF_T+1
    sbc DF_SPLEN+1
    bcs spc_done
    lda DF_T
    sta DF_T+2
    lda DF_T+1
    sta DF_T+3
    jsr sp_rd                   ; A = the byte at DF_T+2/+3
    ldy DF_T+4
    jsr OSBPUT
    inc DF_T
    bne spc_byte
    inc DF_T+1
    bne spc_byte
spc_done:
    lda #0
    ldy DF_T+4
    jmp OSFIND

; sp_rd: A = byte DF_T+2/+3 of the spool bank (through DF_BYTE)
sp_rd:
    php
    sei
    lda #<DF_BYTE
    sta REU_C64
    lda #>DF_BYTE
    sta REU_C64+1
    lda DF_T+2
    sta REU_ADDR
    lda DF_T+3
    sta REU_ADDR+1
    lda DF_SPBANK
    sta REU_BANK
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    plp
    lda DF_BYTE
    rts

; ----------------------------------------------------------------------------
; sp_put (from the stub, on every OSWRCH while spooling)
;   Summary: the byte into the spool bank at DF_SPLEN, which counts on (it
;            stops at 65535: later bytes overwrite the last).
;   Input:   A.  Output: A, X, Y kept.  Uses: DF_BYTE.
sp_put:
    sta DF_BYTE
    php
    sei
    lda #<DF_BYTE
    sta REU_C64
    lda #>DF_BYTE
    sta REU_C64+1
    lda DF_SPLEN
    sta REU_ADDR
    lda DF_SPLEN+1
    sta REU_ADDR+1
    lda DF_SPBANK
    sta REU_BANK
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    plp
    inc DF_SPLEN                ; on, up to &BCF0 (the bank's rest is
    bne spp_chk                 ; speech's: SAM's image, speech.s)
    inc DF_SPLEN+1
spp_chk:
    lda DF_SPLEN+1
    cmp #>SP_MAX
    bcc spp_rts
    lda DF_SPLEN
    cmp #<SP_MAX
    bcc spp_rts
    lda #<[SP_MAX-1]            ; full: the last byte overwritten
    sta DF_SPLEN
    lda #>[SP_MAX-1]
    sta DF_SPLEN+1
spp_rts:
    lda DF_BYTE
    rts

; The stub (copied to DF_STUB, on WRCHV while spooling)
sps_load:
    .local sps
    org DF_STUB, sps_load
    farcall dfs.sp_put, BANK_NET
    jmp mos_wrch
LEN         = * - DF_STUB
    .endl
sps_len     = sps.LEN
    org sps_load + sps_len
    .if DF_STUB + sps_len > $0259
    .error "The *SPOOL stub overflows $0258"
    .endif

; ----------------------------------------------------------------------------
; cmd_exec
;   Summary: *EXEC [name]: the file's bytes are read as if typed, until
;            its end (or ESCAPE); *EXEC alone closes an *EXEC file.
;   Input:   mosPTR/Y.  Output: DF_EXEC.  Uses: A, X, Y.
cmd_exec:
    sty DF_T+6
    jsr ex_close
    ldy DF_T+6
    jsr s6_skipsp
    cmp #13
    bne cex_open
    rts
cex_open:
    lda #$40                    ; OPENIN
    jsr df_find
    sta DF_EXEC
    lda #0
    sta DF_EXCR
    rts

; ex_close: the *EXEC file (if any) closed.  Uses: A, Y.
ex_close:
    ldy DF_EXEC
    beq exc_rts
    lda #0
    sta DF_EXEC
    jmp OSFIND
exc_rts:
    rts

; dfs_closeall (CLOSE#0, fs.s): the spool written and closed, *EXEC
; closed, before the filing system closes everything
dfs_closeall:
    jsr sp_close
    jmp ex_close

; df_find: OSFIND A (&40 in, &80 out) on the name at mosPTR/Y (CR or
; space ends it).  Output: A = the channel ("Not found" for a missing
; file).  Uses: A, X, Y.
df_find:
    pha
    jsr s6_skipsp
    tya
    clc
    adc mosPTR
    tax
    lda mosPTR+1
    adc #0
    tay
    pla
    jsr OSFIND
    cmp #0
    bne dff_rts
    brk
    dta 214, 'Not found', 0
dff_rts:
    rts

; ----------------------------------------------------------------------------
; cmd_build
;   Summary: *BUILD name: lines typed go into the file, each ended by CR,
;            until ESCAPE (as on the BBC: line numbers are shown, not
;            written).
;   Function: the file is opened (created); each line is read with OSWORD
;            0 into DF_LINE and written with OSBPUT; ESCAPE acknowledged,
;            the file closed.
;   Input:   mosPTR/Y.  Output: the file.  Uses: A, X, Y, DF_T, DF_LINE.
cmd_build:
    lda #$80
    jsr df_find
    sta DF_T+4
    lda #0                      ; line number
    sta DF_T+5
    sta DF_T+6
cbu_line:
    lda DF_T+5                  ; number += 10, shown in 5 places
    clc
    adc #10
    sta DF_T+5
    bcc cbu_n
    inc DF_T+6
cbu_n:
    jsr df_num5
    lda #' '
    jsr OSWRCH
    ldx #4                      ; OSWORD 0: DF_LINE, length, 32-255 (the
cbu_blk:                        ; block in DF_DBUF: DF_T+4 is the channel)
    lda cbu_word,x
    sta DF_DBUF,x
    dex
    bpl cbu_blk
    ldx #<DF_DBUF
    ldy #>DF_DBUF
    lda #0
    jsr OSWORD
    bcs cbu_end                 ; ESCAPE
    sty DF_T+7                  ; length
    ldx #0
cbu_put:
    cpx DF_T+7
    beq cbu_cr
    lda DF_LINE,x
    ldy DF_T+4
    jsr OSBPUT
    inx
    bne cbu_put
cbu_cr:
    lda #13
    ldy DF_T+4
    jsr OSBPUT
    jmp cbu_line
cbu_end:
    lda #$7E
    jsr OSBYTE
    jsr OSNEWL
    lda #0
    ldy DF_T+4
    jmp OSFIND
cbu_word:
    dta <DF_LINE, >DF_LINE, DF_LMAX, 32, 255

; df_num5: DF_T+5/+6 in decimal, right-aligned in 5 places
df_num5:
    lda DF_T+5
    sta mosNUM
    lda DF_T+6
    sta mosNUM+1
    ldx #4                      ; the digits into DF_T+8.. (reversed)
dn5_div:
    lda #0                      ; mosNUM / 10, remainder in A
    ldy #16
dn5_bit:
    asl mosNUM
    rol mosNUM+1
    rol
    cmp #10
    bcc dn5_nb
    sbc #10
    inc mosNUM
dn5_nb:
    dey
    bne dn5_bit
    sta DF_DBUF,x
    dex
    bpl dn5_div
    ldx #0                      ; leading zeros as spaces
dn5_out:
    lda DF_DBUF,x
    bne dn5_dig
    cpx #4
    beq dn5_dig
    lda #' '
    jsr OSWRCH
    inx
    bne dn5_out
dn5_dig:
    lda DF_DBUF,x
    ora #'0'
    jsr OSWRCH
    inx
    cpx #5
    bcc dn5_dig
    rts

; ----------------------------------------------------------------------------
; cmd_dump
;   Summary: *DUMP name: the file in hexadecimal and as characters, 8
;            bytes a line with the offset (fits 40 columns). ESCAPE stops.
;   Input:   mosPTR/Y.  Output: text.  Uses: A, X, Y, DF_T.
cmd_dump:
    lda #$40
    jsr df_find
    sta DF_T+4
    lda #0
    sta DF_T+5                  ; offset (2)
    sta DF_T+6
cdu_line:
    bit ESCFLG
    bpl cdu_go
    jmp cdu_esc
cdu_go:
    ldx #0                      ; up to 8 bytes into DF_DBUF
cdu_rd:
    stx DF_T+7
    ldy DF_T+4
    jsr OSBGET
    ldx DF_T+7
    bcs cdu_eof
    sta DF_DBUF,x
    inx
    cpx #8
    bcc cdu_rd
cdu_eof:
    stx DF_T+7                  ; bytes in this line
    txa
    beq cdu_end
    lda DF_T+6                  ; offset
    jsr df_hex2
    lda DF_T+5
    jsr df_hex2
    ldx #0
cdu_hex:
    lda #' '
    jsr OSWRCH
    cpx DF_T+7
    bcs cdu_sp
    lda DF_DBUF,x
    jsr df_hex2
    jmp cdu_hn
cdu_sp:
    lda #' '                    ; (a short last line: padded)
    jsr OSWRCH
    jsr OSWRCH
cdu_hn:
    inx
    cpx #8
    bcc cdu_hex
    lda #' '
    jsr OSWRCH
    ldx #0
cdu_chr:
    lda DF_DBUF,x
    cmp #32
    bcc cdu_dot
    cmp #127
    bcc cdu_c
cdu_dot:
    lda #'.'
cdu_c:
    jsr OSWRCH
    inx
    cpx DF_T+7
    bcc cdu_chr
    jsr OSNEWL
    lda DF_T+5
    clc
    adc #8
    sta DF_T+5
    bcc cdu_more
    inc DF_T+6
cdu_more:
    lda DF_T+7
    cmp #8
    bne cdu_end
    jmp cdu_line
cdu_end:
    lda #0
    ldy DF_T+4
    jmp OSFIND
cdu_esc:
    lda #0
    ldy DF_T+4
    jsr OSFIND
    brk
    dta 17, 'Escape', 0

; df_hex2: A as two hex digits
df_hex2:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr dh_dig
    pla
    and #15
dh_dig:
    cmp #10
    bcc dh_d
    adc #'A'-10-1
    jmp OSWRCH
dh_d:
    ora #'0'
    jmp OSWRCH

; ----------------------------------------------------------------------------
; cmd_info
;   Summary: *INFO name: name, attributes (L locked), load and execution
;            address and length in hexadecimal, as DFS (OSFILE 5). Files
;            on the Ultimate's drives have no addresses (0).
;   Input:   mosPTR/Y.  Output: one line.  Uses: A, X, Y, osfblk.
cmd_info:
    jsr df_blk                  ; osfblk: the name, the rest 0
    lda #5
    ldx #<osfblk
    ldy #>osfblk
    jsr OSFILE
    cmp #0
    bne cin_have
    brk
    dta 214, 'Not found', 0
cin_have:
    ldy DF_T                    ; the name, padded to 12
    ldx #0
cin_name:
    lda (mosPTR),y
    cmp #13
    beq cin_pad
    cmp #' '
    beq cin_pad
    jsr OSWRCH
    iny
    inx
    bne cin_name
cin_pad:
    lda #' '
    jsr OSWRCH
    inx
    cpx #12
    bcc cin_pad
    lda osfblk+14               ; L
    and #8
    beq cin_nl
    lda #'L'
    bne cin_l
cin_nl:
    lda #' '
cin_l:
    jsr OSWRCH
    lda #' '
    jsr OSWRCH
    ldx #3                      ; load, exec (6 digits each, as DFS)
    jsr cin_addr
    ldx #7
    jsr cin_addr
    ldx #12                     ; length (3 bytes)
    lda osfblk,x
    jsr df_hex2
    dex
    lda osfblk,x
    jsr df_hex2
    dex
    lda osfblk,x
    jsr df_hex2
    jmp OSNEWL
cin_addr:                       ; "00" and the 16-bit address at X-1, X
    lda #0
    jsr df_hex2
    lda osfblk,x
    jsr df_hex2
    dex
    lda osfblk,x
    jsr df_hex2
    lda #' '
    jmp OSWRCH

; df_blk: osfblk all 0, +0 the address of the name at mosPTR/Y (its
; first character's position also in DF_T)
df_blk:
    ldx #17
    lda #0
dbk_z:
    sta osfblk,x
    dex
    bpl dbk_z
    jsr s6_skipsp
    cmp #13
    bne dbk_name
    jmp s6_syntax
dbk_name:
    sty DF_T
    tya
    clc
    adc mosPTR
    sta osfblk
    lda mosPTR+1
    adc #0
    sta osfblk+1
    rts

; ----------------------------------------------------------------------------
; cmd_run
;   Summary: *RUN name: load machine code and call it.
;   Function: a file with a load address (*SAVE on /REU): loaded there
;            (OSFILE &FF), called at its execution address (or the load
;            address). Otherwise a C64 program file: its first two bytes
;            are the load address, the rest is loaded there and called at
;            it. Only &0400-&7FFF ("Address out of range" otherwise).
;   Input:   mosPTR/Y.  Output: what the code does.  Uses: A, X, Y,
;            DF_T, osfblk, mosTMP.
cmd_run:
    jsr df_blk
    lda #5
    ldx #<osfblk
    ldy #>osfblk
    jsr OSFILE
    cmp #0
    bne crn_have
    brk
    dta 214, 'Not found', 0
crn_have:
    lda osfblk+2
    ora osfblk+3
    beq crn_prg
    lda osfblk+6                ; exec (0: the load address)
    ora osfblk+7
    bne crn_ex
    lda osfblk+2
    sta osfblk+6
    lda osfblk+3
    sta osfblk+7
crn_ex:
    lda osfblk+6
    pha
    lda osfblk+7
    pha
    lda #0                      ; OSFILE &FF at its own address
    sta osfblk+6
    lda #$FF
    ldx #<osfblk
    ldy #>osfblk
    jsr OSFILE
    pla
    sta mosTMP+1
    pla
    sta mosTMP
    jmp (mosTMP)
crn_prg:
    ldy DF_T                    ; OPENIN, the two address bytes
    lda #$40
    jsr df_find
    sta DF_T+4
    tay
    jsr OSBGET
    sta mosTMP
    sta DF_T+2
    ldy DF_T+4
    jsr OSBGET
    sta mosTMP+1
    sta DF_T+3
crn_byte:
    ldy DF_T+4
    jsr OSBGET
    bcs crn_go
    pha
    jsr crn_range               ; (this byte's address)
    pla
    ldy #0
    sta (mosTMP),y
    inc mosTMP
    bne crn_byte
    inc mosTMP+1
    bne crn_byte
crn_go:
    lda #0
    ldy DF_T+4
    jsr OSFIND
    jmp (DF_T+2)
; crn_range: mosTMP inside &0400-&7FFF, else the file closed and an error
crn_range:
    lda mosTMP+1
    cmp #$04
    bcc crn_bad
    cmp #$80
    bcs crn_bad
    rts
crn_bad:
    lda #0
    ldy DF_T+4
    jsr OSFIND
    brk
    dta 192, 'Address out of range', 0

    .endl
