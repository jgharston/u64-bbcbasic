; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- snapshots (*SNAPSHOT), bank 5
;
; A snapshot is BASIC's world in an REU slot of 32K: BASIC's zero page,
; its workspace &0400-&07FF and the memory from PAGE to HIMEM (program,
; variables), with the screen mode, PAGE, HIMEM and the time in a header.
; Slots 1-9 at SNAP_BANK:0000 + n * &8000 (&B8000-&FFFFF), slot 0 the
; working slot for snapshots read from a file. Taken at the prompt only:
; restoring then resumes where the taking returned, so BASIC finishes
; that line and shows the prompt, with the program and the variables as
; they were (the 6502 stack at the prompt is the same each time).
;
; Slot layout:
;   +$0000  header: "U64SNAP",0, mode, PAGE (page), HIMEM (2), TOP (2),
;           pages of PAGE..HIMEM, (spare), +16: the time (OSWORD 14
;           text, 24 characters)
;   +$0100  page 0 (restored: BASIC's $02-$51 and the user's $70-$8F;
;           not the CPU port $00/$01 nor the MOS's $52-$6F)
;   +$0200  &0400-&07FF
;   +$0600  PAGE..HIMEM-1 (at most &77 pages: PAGE &900, HIMEM &8000)
;
; ----------------------------------------------------------------------------

SNAP_BANK   = $0B               ; slot n: bank SNAP_BANK + n / 2

    .local snap
    icl 'bankhelp.s'

SH_MODE     = 8
SH_PAGE     = 9
SH_HIMEM    = 10
SH_TOP      = 12
SH_PAGES    = 14
SH_TIME     = 16
SN_HDR      = 40                ; header bytes read for the list
ZP_LINE     = $0B               ; BASIC's text pointer (lib/bbc-basic)
ZP_HIMEM    = $06
ZP_TOP      = $12
ZP_PAGE     = $18

; ----------------------------------------------------------------------------
; cmd_snapshot
;   Summary: *SNAPSHOT [n] | LOAD n|file | SAVE n file.
;   Function: n: BASIC's world into slot n (1-9); LOAD n: back from it;
;            alone: the slots in use; SAVE n file: slot n to a file on the
;            Ultimate's drives; LOAD file: a file into slot 0, restored.
;   Input:   mosPTR/Y = rest of the command line.
;   Output:  the slot or the restored state; errors as below.
;   Uses:    A, X, Y, fs*, mosNUM, mosTMP, MOSBUF.
cmd_snapshot:
    jsr s6_hasreu               ; slots up to &FFFFF: an REU of 1 MB
    beq sn_noreu
    lda reu_banks+1
    bne sn_reuok
    lda reu_banks
    cmp #16
    bcs sn_reuok
sn_noreu:
    brk
    dta 254, 'Snapshots need an REU of 1 MB', 0
sn_reuok:
    jsr s6_skipsp
    cmp #13
    bne sn_args
    jmp sn_list
sn_args:
    lda #<sw_load
    ldx #>sw_load
    jsr s6_word
    bcc sn_nload
    jmp sn_load
sn_nload:
    lda #<sw_save
    ldx #>sw_save
    jsr s6_word
    bcc sn_take
    jmp sn_tofile
sn_take:
    jsr sn_slotnum              ; *SNAPSHOT n
    jsr s6_end
    ; fall through

; sn_save: BASIC's world into slot fsSX (at the prompt only).
; Uses: A, X, Y, fs*, mosNUM, MOSBUF.
sn_save:
    lda ZP_LINE+1               ; at the prompt: the text pointer in the
    cmp #>$0700                 ; line buffer
    beq sns_prompt
    brk
    dta 251, 'Snapshot: at the prompt only', 0
sns_prompt:
    ldx #63                     ; the header
    lda #0
sns_clr:
    sta MOSBUF,x
    dex
    bpl sns_clr
    ldx #7
sns_magic:
    lda sn_magic,x
    sta MOSBUF,x
    dex
    bpl sns_magic
    lda vmode
    sta MOSBUF+SH_MODE
    lda ZP_PAGE
    sta MOSBUF+SH_PAGE
    lda ZP_HIMEM
    sta MOSBUF+SH_HIMEM
    lda ZP_HIMEM+1
    sta MOSBUF+SH_HIMEM+1
    lda ZP_TOP
    sta MOSBUF+SH_TOP
    lda ZP_TOP+1
    sta MOSBUF+SH_TOP+1
    lda ZP_HIMEM+1              ; pages PAGE..HIMEM (HIMEM's low byte is
    sec                         ; 0 in every mode)
    sbc ZP_PAGE
    sta MOSBUF+SH_PAGES
    lda #0                      ; the time: OSWORD 14, text form
    sta MOSBUF+SH_TIME
    lda #14
    ldx #<[MOSBUF+SH_TIME]
    ldy #>[MOSBUF+SH_TIME]
    jsr OSWORD
    lda #<MOSBUF                ; header -> +0
    ldx #>MOSBUF
    ldy #0
    jsr sn_set
    lda #64
    sta fsLEN
    lda #REU_TO_REU
    jsr rd_dma
    lda #0                      ; page 0 -> +$100
    tax
    ldy #1
    jsr sn_set
    lda #REU_TO_REU
    jsr rd_dma
    lda #0                      ; &0400-&07FF -> +$200
    ldx #4
    ldy #2
    jsr sn_set
    lda #4
    sta fsLEN+1
    lda #REU_TO_REU
    jsr rd_dma
    lda #0                      ; PAGE.. -> +$600
    ldx ZP_PAGE
    ldy #6
    jsr sn_set
    lda MOSBUF+SH_PAGES
    sta fsLEN+1
    lda #REU_TO_REU
    jmp rd_dma

; sn_set: DMA addresses: C64 A/X (low/high), slot fsSX + Y pages; length
; 256.  Uses: A, fs*.
sn_set:
    sta fsADDR
    stx fsADDR+1
    lda #0
    sta fsTMP
    sta fsLEN
    lda #1
    sta fsLEN+1
    lda fsSX                    ; bank SNAP_BANK + n / 2, page (n AND 1) *
    lsr                         ; &80 + Y
    pha
    lda #0
    ror
    sta fsTMP+1
    tya
    clc
    adc fsTMP+1
    sta fsTMP+1
    pla
    adc #SNAP_BANK
    sta fsTMP+2
    rts

; sn_slotnum: a slot number 1-9 -> fsSX ("Bad slot" otherwise)
sn_slotnum:
    jsr s6_need
    lda mosNUM+1
    bne sn_badslot
    lda mosNUM
    beq sn_badslot
    cmp #10
    bcs sn_badslot
    sta fsSX
    rts
sn_badslot:
    brk
    dta 252, 'Bad slot (1-9)', 0

; ----------------------------------------------------------------------------
; sn_load: LOAD n (a digit, then the end) or LOAD file
sn_load:
    jsr s6_skipsp
    cmp #'1'
    bcc snl_file
    cmp #'9'+1
    bcs snl_file
    iny                         ; a single digit and nothing after it?
    lda (mosPTR),y
    dey
    cmp #13
    beq snl_slot
    cmp #' '
    bne snl_file
snl_slot:
    jsr sn_slotnum
    jsr s6_end
    jmp sn_restore
snl_file:
    jsr s6_name                 ; a file: into slot 0, then restored
    jsr s6_end
    farcall rx_openin, BANK_FS
    lda fsTMP+2                 ; at most 32K
    ora fsTMP+3
    bne snl_big
    lda fsTMP+1
    bmi snl_big
    lda #SNAP_BANK              ; slot 0: bank SNAP_BANK, page 0
    ldy #0
    ldx #$80
    farcall rx_read, BANK_FS
    farcall rx_close, BANK_FS
    lda #0
    sta fsSX
    jmp sn_restore
snl_big:
    farcall rx_close, BANK_FS
sn_bad:
    brk
    dta 253, 'Not a snapshot', 0

; sn_restore: slot fsSX back. Uses: A, X, Y, fs*, MOSBUF.
sn_restore:
    jsr sn_header
    beq snr_ok
    jmp sn_bad
snr_ok:
    lda MOSBUF+SH_PAGE          ; the same PAGE (the sound engine's room)
    cmp ZP_PAGE
    beq snr_page
    brk
    dta 250, 'Snapshot needs another PAGE', 0
snr_page:
    lda MOSBUF+SH_PAGES         ; (kept on the stack: a MODE change uses
    pha                         ; MOSBUF, and the fs variables through
    lda fsSX                    ; the palette code)
    pha
    lda MOSBUF+SH_MODE          ; its screen mode first (its screen memory
    cmp vmode                   ; may lie where the program goes)
    beq snr_mode
    pha
    lda #22
    jsr OSWRCH
    pla
    jsr OSWRCH
snr_mode:
    pla
    sta fsSX
    lda #<MOSBUF                ; page 0 to MOSBUF, then BASIC's part and
    ldx #>MOSBUF                ; the user's into page 0
    ldy #1
    jsr sn_set
    lda #REU_TO_C64
    jsr rd_dma
    ldx #2
snr_zp:
    lda MOSBUF,x
    sta $00,x
    inx
    cpx #$52
    bcc snr_zp
    ldx #$70
snr_user:
    lda MOSBUF,x
    sta $00,x
    inx
    cpx #$90
    bcc snr_user
    lda #0                      ; &0400-&07FF
    ldx #4
    ldy #2
    jsr sn_set
    lda #4
    sta fsLEN+1
    lda #REU_TO_C64
    jsr rd_dma
    lda #0                      ; PAGE..HIMEM
    ldx ZP_PAGE
    ldy #6
    jsr sn_set
    pla
    sta fsLEN+1
    lda #REU_TO_C64
    jmp rd_dma

; sn_header: slot fsSX's header to MOSBUF; Z = 1 if it is a snapshot.
; Uses: A, X, Y, fs*.
sn_header:
    lda #<MOSBUF
    ldx #>MOSBUF
    ldy #0
    jsr sn_set
    lda #SN_HDR
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_C64
    jsr rd_dma
    ldx #7
snh_cmp:
    lda MOSBUF,x
    cmp sn_magic,x
    bne snh_rts
    dex
    bpl snh_cmp
    lda #0
snh_rts:
    rts

; ----------------------------------------------------------------------------
; sn_tofile: SAVE n file: slot n (header and used pages) to a file. The
; slot's address and its length are kept on the stack: the name and the
; UCI routines use the fs variables.
sn_tofile:
    jsr sn_slotnum
    tya
    pha
    jsr sn_header               ; (fs variables, MOSBUF)
    beq snt_ok
    jmp sn_bad
snt_ok:
    lda MOSBUF+SH_PAGES         ; pages: header, page 0, workspace, program
    clc
    adc #6
    pha
    lda fsSX                    ; bank SNAP_BANK + n / 2, page (n AND 1) * &80
    lsr
    pha                         ; (n / 2)
    lda #0
    ror
    sta fsCNT
    pla
    clc
    adc #SNAP_BANK
    tax
    pla                         ; pages
    sta fsCNT+1
    pla                         ; the line position
    tay
    lda fsCNT+1                 ; stack: pages, bank, page
    pha
    txa
    pha
    lda fsCNT
    pha
    jsr s6_name
    jsr s6_end
    farcall rx_create, BANK_FS
    pla
    tay                         ; page
    pla                         ; bank
    sta fsCNT
    pla
    tax                         ; pages
    lda fsCNT
    farcall rx_write, BANK_FS
    farcall rx_close, BANK_FS
    rts

; ----------------------------------------------------------------------------
; sn_list: the slots in use: n, the time, the mode, the program's size
sn_list:
    lda #1
    sta fsSX
snl_loop:
    jsr sn_header
    bne snl_next
    lda fsSX
    ora #'0'
    jsr OSWRCH
    lda #' '
    jsr OSWRCH
    ldx #0
snl_time:
    lda MOSBUF+SH_TIME,x
    cmp #13
    beq snl_mode
    jsr OSWRCH
    inx
    cpx #24
    bcc snl_time
snl_mode:
    jsr s6_text
    dta '  MODE ', 0
    lda MOSBUF+SH_MODE
    jsr s6_dec8
    jsr s6_text
    dta '  ', 0
    lda MOSBUF+SH_TOP           ; program: TOP - PAGE bytes
    sta mosTMP
    lda MOSBUF+SH_TOP+1
    sec
    sbc MOSBUF+SH_PAGE
    sta mosTMP+1
    jsr s6_dec16
    jsr s6_text
    dta ' bytes', 13, 0
snl_next:
    inc fsSX
    lda fsSX
    cmp #10
    bcc snl_loop
    rts

sn_magic    dta 'U64SNAP', 0
sw_load     dta 'LOAD', 0
sw_save     dta 'SAVE', 0
    .endl
