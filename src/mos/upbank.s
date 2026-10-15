; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 8: Upic full
;
; *UPIC and the viewer (upic.s), and MODE 110/111: up_enter (from bank
; 3's MODE code) copies the Upic full drawing engine (gfx_up.s) to
; ENGINE and its REU / console stub (upstub.s) to UP_STUB, sets the
; VIC-II's text screen as the console and clears both
; (docs/DESIGN_GRAPHICS.md 10.11, 10.12).
;
; ----------------------------------------------------------------------------

    icl 'upic.s'
    icl 'bvcmd.s'
    icl 'font46.s'
    icl 'cmap.s'

; ----------------------------------------------------------------------------
; up_enter
;   Summary: start MODE 110 or 111 (vmode_* set by bk_mode).
;   Function: engine and stub into RAM; the VIC-II text screen with the
;            text font as the console; eng_kind 3; the engine clears the
;            picture (colour 0) and the console; a new picture header
;            whose palette shows the mode's logical colours (pal[]).
;   Uses:    A, X, Y, gzp, MOSBUF; mosPTR (saved).
up_enter:
    lda mosPTR
    pha
    lda mosPTR+1
    pha
    php
    sei
    lda #<upe_load              ; the engine
    ldx #>upe_load
    ldy #>ENGINE
    jsr upe_set
    ldx #16
    jsr upe_copy
    lda #<ups_load              ; the stub
    ldx #>ups_load
    ldy #>UP_STUB
    jsr upe_set
    ldx #>[UPS_LEN+255]
    jsr upe_copy
    lda #3                      ; the Upic full engine is in
    sta eng_kind
    plp
    lda #$1B                    ; the console: the VIC-II text screen
    sta $D011
    lda #$C8
    sta $D016
    lda #$0C
    sta $D018
    jsr font_restore
    lda #0
    sta $D020
    sta $D021
    ldx #GX_MODE                ; picture and console cleared, VDU state
    jsr gx_call
    lda UP_DIRTY                ; (a cleared picture is not worth a show)
    and #$80
    sta UP_DIRTY
    sec                         ; a header with the mode's colours
    jsr upic.up_header
    pla
    sta mosPTR+1
    pla
    sta mosPTR
    rts

; ----------------------------------------------------------------------------
; up_vdu19
;   Summary: VDU 19 in MODE 110/111: the picture's palette (its header in
;            the REU; seen at the next show).
;   Function: VDU 19,l,p (p 0-15, a BBC colour): pal[l] = its C64 colour,
;            entry l = that colour's RGB (REU_PAL64). VDU 19,l,16,r,g,b:
;            entry l = r, g, b. Others are ignored.
;   Input:   vdubuf.  Uses: A, X, Y, fs*, PALBUF.
up_vdu19:
    lda vdubuf
    and #15
    sta mosTMP+2                ; l
    lda vdubuf+1
    cmp #16
    beq uv_rgb
    bcs uv_rts
    tax
    lda bbc2c64,x
    ldx mosTMP+2
    sta pal,x
    txa
    jmp up_palent
uv_rgb:
    lda vdubuf+2
    sta PALBUF
    lda vdubuf+3
    sta PALBUF+1
    lda vdubuf+4
    sta PALBUF+2
    jmp upe_put3
uv_rts:
    rts

; up_palall: entries 0-15 from pal[] (VDU 20)
up_palall:
    lda #0
upa_loop:
    pha
    jsr up_palent
    pla
    clc
    adc #1
    cmp #16
    bcc upa_loop
    rts

; up_palent: entry A = the RGB of C64 colour pal[A] (REU_PAL64)
up_palent:
    sta mosTMP+2
    tax
    lda pal,x
    and #15
    sta mosTMP+3
    asl
    adc mosTMP+3                ; * 3
    clc
    adc #<REU_PAL64
    sta fsTMP
    lda #>REU_PAL64
    adc #0
    sta fsTMP+1
    lda #REU_FONT_BANK
    sta fsTMP+2
    jsr upe_pal3
    lda #REU_TO_C64
    jsr upic.up_dma
upe_put3:                       ; PALBUF (3) -> header $D0 + 3 * mosTMP+2
    lda mosTMP+2
    asl
    adc mosTMP+2
    adc #$D0
    sta fsTMP
    lda #0
    sta fsTMP+1
    lda #UPIC_BANK
    sta fsTMP+2
    jsr upe_pal3
    lda #REU_TO_REU
    jmp upic.up_dma
upe_pal3:                       ; fsADDR = PALBUF, fsLEN = 3
    lda #<PALBUF
    sta fsADDR
    lda #>PALBUF
    sta fsADDR+1
    lda #3
    sta fsLEN
    lda #0
    sta fsLEN+1
    rts

; upe_set: source A/X (this bank), destination page Y -> mosPTR, gzp
upe_set:
    sta mosPTR
    stx mosPTR+1
    lda #0
    sta gzp
    sty gzp+1
    rts
; upe_copy: X pages from (mosPTR) to (gzp) with $01 = $33 (the cartridge
; visible, writes reach the RAM under I/O and the KERNAL; interrupts off)
upe_copy:
    lda #$33
    sta $01
    ldy #0
upc_l:
    lda (mosPTR),y
    sta (gzp),y
    iny
    bne upc_l
    inc mosPTR+1
    inc gzp+1
    dex
    bne upc_l
    lda #CPU_ROMS
    sta $01
    rts

; ----------------------------------------------------------------------------
; RAM images (copied by up_enter)

upe_load:
    org ENGINE, upe_load
    icl 'gfx_up.s'
    org upe_load + $1000

ups_load:
    .local upstub
    org UP_STUB, ups_load
    icl 'upstub.s'
UPS_END     = *
    .endl
UPS_LEN     = upstub.UPS_END - UP_STUB
    org ups_load + UPS_LEN
    .if UPS_LEN > UP_BUF-UP_STUB
    .error "Upic stub over its 512 bytes"
    .endif

bank8_end:
    .if bank8_end > $C000
    .error "Bank 8 overflows 16K"
    .endif
    :[$C000-*] dta $FF
