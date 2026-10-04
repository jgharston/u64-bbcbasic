; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- RAM Expansion Unit (REU), bank 2
;
; REU registers (1700/1750-compatible, as emulated by the Ultimate):
; $DF00 status, $DF01 command, $DF02/3 C64 address, $DF04/5 REU address,
; $DF06 REU bank (64K), $DF07/8 length, $DF09 interrupt mask, $DF0A
; address control. DMA moves one byte per bus cycle (about 1 MB/s) and
; stops the CPU meanwhile.
;
; ----------------------------------------------------------------------------

REU_STATUS  = $DF00
REU_CMD     = $DF01
REU_C64     = $DF02
REU_ADDR    = $DF04
REU_BANK    = $DF06
REU_LEN     = $DF07
REU_CTRL    = $DF0A

REU_TO_REU  = $90               ; execute now, C64 -> REU
REU_TO_C64  = $91               ; execute now, REU -> C64

; ----------------------------------------------------------------------------
; reu_xfer1
;   Summary: move the byte reu_tmp to or from offset 0 of REU bank X.
;   Input:   A = REU_TO_REU or REU_TO_C64, X = bank.
;   Output:  reu_tmp (REU_TO_C64).  Uses: A.

reu_xfer1:
    pha
    lda #<reu_tmp
    sta REU_C64
    lda #>reu_tmp
    sta REU_C64+1
    lda #0
    sta REU_ADDR
    sta REU_ADDR+1
    stx REU_BANK
    sta REU_LEN+1
    sta REU_CTRL
    lda #1
    sta REU_LEN
    pla
    sta REU_CMD                 ; starts the transfer
    rts

; reu_read / reu_write
;   Summary: byte at offset 0 of bank X -> A, or A -> there.
;   Uses:    A (reu_read), reu_tmp.
reu_read:
    lda #0
    sta reu_tmp
    lda #REU_TO_C64
    jsr reu_xfer1
    lda reu_tmp
    rts
reu_write:
    sta reu_tmp
    lda #REU_TO_REU
    jmp reu_xfer1

; ----------------------------------------------------------------------------
; reu_detect
;   Summary: find the REU and its size, without changing its contents.
;   Function: the C64 address register must keep a written value; a byte
;            written to bank 0 must read back (with an EasyFlash, $DF00 is
;            plain RAM: the first test passes, this one does not). Then
;            for S = 1, 2, 4 ... 128 banks: does bank S alias bank 0? The
;            two bytes involved are saved and restored each time.
;   Input:   none.
;   Output:  reu_banks = number of 64K banks (0: no REU, 256: 16 MB).
;   Uses:    A, X, Y, reu_tmp, reu_save0, reu_saveS.

reu_detect:
    lda #0
    sta reu_banks
    sta reu_banks+1
    lda #$55
    sta REU_C64
    cmp REU_C64
    bne rd_none
    lda #$AA
    sta REU_C64
    cmp REU_C64
    bne rd_none
    ldx #0                      ; bank 0 must hold what is written
    jsr reu_read
    sta reu_save0
    lda #$A5
    jsr reu_write
    jsr reu_read
    cmp #$A5
    bne rd_restore0
    ldy #1                      ; S
rd_size:
    tya
    tax
    jsr reu_read
    sta reu_saveS
    ldx #0
    lda #$A5
    jsr reu_write
    tya
    tax
    lda #$5A
    jsr reu_write
    ldx #0
    jsr reu_read                ; bank 0 changed: bank S is bank 0
    pha
    tya
    tax
    lda reu_saveS
    jsr reu_write
    pla
    cmp #$5A
    beq rd_found
    tya
    asl
    tay
    bne rd_size
    lda #1                      ; no alias up to 128: 256 banks (16 MB)
    sta reu_banks+1
    bne rd_restore0
rd_found:
    sty reu_banks
rd_restore0:
    ldx #0
    lda reu_save0
    jsr reu_write
rd_none:
    rts
