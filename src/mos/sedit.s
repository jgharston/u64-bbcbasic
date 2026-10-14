; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the sprite editor (*SEDIT), bank 7
;
; One editor for both kinds of sprite (owner, 2026-10-14): *SEDIT n edits
; GXR sprite n (gxr.s), *SEDIT VIC s the VIC-II shape s (sprite.s). The
; sprite is edited in a buffer in the REU (GXR_SCR, a row every 256 bytes,
; one byte a pixel; a VIC shape as its 24 x 21 bits) on the text screen
; (MODE 100): each pixel one character cell, the palette and the keys on
; the right, a VIC shape also at its real size as hardware sprite 0.
; RETURN keeps the sprite, ESCAPE leaves it as it was; the mode before is
; set again (cleared). docs/DESIGN_SPRITES.md 7.
;
; ----------------------------------------------------------------------------

    .local sed
    icl 'bankhelp.s'

; Variables in MOSBUF+$80-$AF (gxr.s uses MOSBUF+$00-$7F meanwhile)
ED_KIND     = MOSBUF+$80        ; 0 GXR, 1 VIC
ED_N        = MOSBUF+$81        ; the sprite / shape number
ED_W        = MOSBUF+$82        ; size in buffer pixels (VIC: 24 x 21)
ED_H        = MOSBUF+$83
ED_CX       = MOSBUF+$84        ; the cursor (logical pixels)
ED_CY       = MOSBUF+$85
ED_OX       = MOSBUF+$86        ; the grid's top left (logical pixels)
ED_OY       = MOSBUF+$87
ED_COL      = MOSBUF+$88        ; the colour painted
ED_MC       = MOSBUF+$89        ; VIC: multicolour view
ED_MODE     = MOSBUF+$8A        ; the mode before (VDU 22 value)
ED_PIX      = MOSBUF+$8B        ; a pixel byte (DMA)
ED_X        = MOSBUF+$8C        ; pixel access: x, y (logical)
ED_Y        = MOSBUF+$8D
ED_V        = MOSBUF+$8E        ; a value
ED_T        = MOSBUF+$8F        ; scratch (4)
ED_R        = MOSBUF+$93        ; grid drawing: row, column
ED_C        = MOSBUF+$94
ED_FSP       = MOSBUF+$95        ; fill: stack pointer (2, entries)
ED_TGT      = MOSBUF+$97        ; fill: the colour replaced
ED_NUM      = MOSBUF+$98        ; number input (2)

GRID_W      = 24                ; the grid: columns 0-23, rows 1-23
GRID_H      = 23
PANEL       = 25                ; the panel's column
SCRN        = $C000             ; text screen and colour RAM
COLR        = $D800
PREVIEW     = $FF00             ; VIC preview shape (free in text modes)
PREV_PTR    = [PREVIEW-$C000]/64
FILL_BANK   = $0B               ; REU: the fill's stack (snapshot slot 0)

; ----------------------------------------------------------------------------
; cmd_sedit
;   Summary: *SEDIT n | *SEDIT VIC s: the sprite editor.
;   Function: the sprite into the buffer; MODE 100, the screen drawn; keys
;            until RETURN (stored) or ESCAPE; the mode before again.
;   Input:   mosPTR/Y.  Output: the sprite changed or not.
;   Uses:    A, X, Y, everything of the screen, MOSBUF+$80-$AF.
cmd_sedit:
    jsr s6_hasreu
    bne cse_reu
    brk
    dta 254, 'Sprites need an REU', 0
cse_reu:
    lda #0
    sta ED_KIND
    sta ED_MC
    lda #<wd_vic
    ldx #>wd_vic
    jsr s6_word
    bcc cse_num
    inc ED_KIND
cse_num:
    jsr s6_need
    jsr s6_end
    lda mosNUM+1
    bne cse_bad
    lda mosNUM
    sta ED_N
    ldx ED_KIND
    beq cse_load
    cmp #64
    bcc cse_load
cse_bad:
    brk
    dta 252, 'Bad sprite number', 0
cse_load:
    jsr ed_load
    lda vmode                   ; the mode to go back to
    ldx mode_shadow
    beq cse_m
    ora #$80
cse_m:
    sta ED_MODE
    lda spr_page                ; the VIC sprites' multiplexer out (the
    beq cse_nomux               ; MODE afterwards puts it back)
    farcall spr.sp_remove, BANK_RD
cse_nomux:
    lda #22                     ; MODE 100, no cursor
    jsr OSWRCH
    lda #100
    jsr OSWRCH
    jsr ed_curoff
    lda #1                      ; the KERNAL's cursor blink off too (the
    sta BLNSW                   ; text MODE starts it; the grid is ours)
    lda #0
    sta ED_CX
    sta ED_CY
    sta ED_OX
    sta ED_OY
    lda #1
    sta ED_COL
    jsr ed_draw
ed_loop:
    jsr OSRDCH
    bcc ed_key
    lda #$7E                    ; ESCAPE: acknowledged, nothing kept
    jsr OSBYTE
    jmp ed_leave
ed_key:
    jsr ed_dokey
    bcs ed_store                ; RETURN
    jsr ed_draw
    jmp ed_loop
ed_store:
    jsr ed_save
ed_leave:
    lda #0                      ; preview off, the mode before again
    sta $D015
    lda #22
    jsr OSWRCH
    lda ED_MODE
    jsr OSWRCH
    lda #23                     ; cursor on
    jsr OSWRCH
    lda #1
    jsr OSWRCH
    lda #1
    jsr OSWRCH
    ldx #7
    lda #0
cse_z:
    jsr OSWRCH
    dex
    bne cse_z
    rts
ed_curoff:
    lda #23
    jsr OSWRCH
    lda #1
    jsr OSWRCH
    ldx #8
    lda #0
eco_z:
    jsr OSWRCH
    dex
    bne eco_z
    rts

; ----------------------------------------------------------------------------
; ed_load / ed_save: the sprite <-> the buffer. GXR through bank 5
; (gxr_edload/edstore); a VIC shape (REU bank 1, REU_SHAPES + s * 64)
; as 24 x 21 bits, one byte each.
ed_load:
    lda ED_KIND
    bne edl_vic
    lda ED_N
    sta gxr.gv_n
    farcall gxr.gxr_edload, BANK_RD
    lda gxr.GE_W
    sta ED_W
    lda gxr.GE_H
    sta ED_H
    rts
edl_vic:
    lda #24
    sta ED_W
    lda #21
    sta ED_H
    jsr edv_shape               ; the 63 bytes to MOSBUF+$00
    lda #REU_TO_C64
    jsr ed_dma
    lda #0                      ; each bit to its buffer byte
    sta ED_Y
edl_row:
    lda #0
    sta ED_X
edl_byte:
    lda ED_Y                    ; byte = row * 3 + x / 8
    asl
    adc ED_Y
    sta ED_T
    lda ED_X
    lsr
    lsr
    lsr
    clc
    adc ED_T
    tax
    lda MOSBUF,x
    sta ED_T+1
    ldx #8
edl_bit:
    lda #0
    asl ED_T+1
    rol
    jsr ed_bufput               ; buffer (ED_X, ED_Y) = A
    inc ED_X
    dex
    bne edl_bit
    lda ED_X
    cmp #24
    bcc edl_byte
    inc ED_Y
    lda ED_Y
    cmp #21
    bcc edl_row
    rts

ed_save:
    lda ED_KIND
    bne eds_vic
    lda ED_N
    sta gxr.gv_n
    lda ED_W
    sta gxr.GE_W
    lda ED_H
    sta gxr.GE_H
    farcall gxr.gxr_edstore, BANK_RD
    rts
eds_vic:
    jsr ed_encode               ; the 63 bytes to MOSBUF+$00 (and +63 = 0)
    jsr edv_shape
    lda #REU_TO_REU
    jmp ed_dma

; ed_encode: the buffer's 24 x 21 bits -> 63 bytes at MOSBUF+$00..$3E
ed_encode:
    lda #0
    sta MOSBUF+63
    sta ED_Y
ede_row:
    lda #0
    sta ED_X
ede_byte:
    lda #0
    sta ED_T+1
    ldx #8
ede_bit:
    jsr ed_bufget
    lsr
    rol ED_T+1
    inc ED_X
    dex
    bne ede_bit
    lda ED_Y
    asl
    adc ED_Y
    sta ED_T
    lda ED_X                    ; (x is 8 further now)
    sec
    sbc #8
    lsr
    lsr
    lsr
    clc
    adc ED_T
    tax
    lda ED_T+1
    sta MOSBUF,x
    lda ED_X
    cmp #24
    bcc ede_byte
    inc ED_Y
    lda ED_Y
    cmp #21
    bcc ede_row
    rts

; edv_shape: fsADDR = MOSBUF, fsTMP = REU bank 1 $1000 + s * 64, 64 bytes
edv_shape:
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda ED_N
    lsr
    lsr
    clc
    adc #>REU_SHAPES
    sta fsTMP+1
    lda ED_N
    and #3
    lsr
    ror
    ror
    sta fsTMP
    lda #REU_SHBANK
    sta fsTMP+2
    lda #64
    sta fsLEN
    lda #0
    sta fsLEN+1
    rts

; ed_dma: as rd_dma: fsADDR <-> fsTMP/+1/+2, fsLEN, command A
ed_dma:
    php
    sei
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

; ----------------------------------------------------------------------------
; The buffer: ed_bufget / ed_bufput: byte (ED_X, ED_Y) of the buffer
; (REU GXR_SCR: y * 256 + x) -> / <- A.  Uses: A; X, Y kept.
ed_bufget:
    lda #REU_TO_C64
    jsr ed_bufdma
    lda ED_PIX
    rts
ed_bufput:
    sta ED_PIX
    lda #REU_TO_REU
ed_bufdma:
    php
    sei
    pha
    lda #<ED_PIX
    sta REU_C64
    lda #>ED_PIX
    sta REU_C64+1
    lda ED_X
    sta REU_ADDR
    lda ED_Y
    sta REU_ADDR+1
    lda #GXR_SCR
    sta REU_BANK
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    pla
    sta REU_CMD
    plp
    rts

; ed_lw: A = the logical width (VIC multicolour: 12 double pixels)
ed_lw:
    lda ED_MC
    beq elw_w
    lda #12
    rts
elw_w:
    lda ED_W
    rts

; ed_get / ed_put: the logical pixel (ED_X, ED_Y) -> / <- A. A VIC shape
; in multicolour: buffer pixels 2x and 2x+1 make the 2-bit value.
; Uses: A, ED_T+3; X, Y kept.
ed_get:
    lda ED_MC
    bne eg_mc
    jmp ed_bufget
eg_mc:
    lda ED_X
    pha
    asl
    sta ED_X
    jsr ed_bufget
    asl
    sta ED_T+3
    inc ED_X
    jsr ed_bufget
    ora ED_T+3
    sta ED_T+3
    pla
    sta ED_X
    lda ED_T+3
    rts
ed_put:
    sta ED_V
    lda ED_MC
    bne ep_mc
    lda ED_V
    jmp ed_bufput
ep_mc:
    lda ED_X
    pha
    asl
    sta ED_X
    lda ED_V
    lsr
    and #1
    jsr ed_bufput
    inc ED_X
    lda ED_V
    and #1
    jsr ed_bufput
    pla
    sta ED_X
    rts

; ----------------------------------------------------------------------------
; ed_draw
;   Summary: the screen: the title, the grid (the visible part of the
;            sprite, the cursor in it), the panel, the VIC preview.
;   Uses:    A, X, Y, ED_R, ED_C, ED_X, ED_Y.
ed_draw:
    jsr ed_scroll               ; the cursor inside the grid's view
    ldx #0                      ; title row
edd_t:
    lda #' '
    sta SCRN,x
    lda #1
    sta COLR,x
    inx
    cpx #40
    bcc edd_t
    ldx #0
    ldy #0
    jsr ed_at
    lda ED_KIND
    bne edd_tv
    jsr ed_str
    dta 'GXR sprite ', 0
    jmp edd_tn
edd_tv:
    jsr ed_str
    dta 'VIC shape ', 0
edd_tn:
    lda ED_N
    jsr ed_dec
    jsr ed_str
    dta '  ', 0
    jsr ed_lw
    jsr ed_dec
    lda #'x'
    jsr ed_chr
    lda ED_H
    jsr ed_dec
    lda #0                      ; the grid: rows 1-23, columns 0-23
    sta ED_R
edd_row:
    lda #0
    sta ED_C
edd_col:
    jsr ed_cell
    inc ED_C
    lda ED_C
    cmp #GRID_W
    bcc edd_col
    inc ED_R
    lda ED_R
    cmp #GRID_H
    bcc edd_row
    jsr ed_panel
    lda ED_KIND
    beq edd_rts
    jmp ed_preview
edd_rts:
    rts

; ed_cell: grid cell ED_C, ED_R: the pixel there (a block in its colour,
; '.' for 0, the cursor '+'), or blank outside the sprite
ed_cell:
    lda ED_R                    ; screen address: row 1 + R, column C
    clc
    adc #1
    tay
    ldx ED_C
    jsr ed_at
    lda ED_C
    clc
    adc ED_OX
    sta ED_X
    lda ED_R
    clc
    adc ED_OY
    sta ED_Y
    jsr ed_lw
    cmp ED_X
    beq ec_out
    bcc ec_out
    lda ED_Y
    cmp ED_H
    bcs ec_out
    jsr ed_get
    sta ED_V
    jsr ed_dispcol              ; A = its C64 colour (0: none)
    sta ED_T+2
    ldx ED_V
    lda #$A0                    ; a block
    cpx #0
    bne ec_blk
    lda #11                     ; 0: a dark grey dot
    sta ED_T+2
    lda #'.'
ec_blk:
    ldx ED_X                    ; the cursor?
    cpx ED_CX
    bne ec_put
    ldx ED_Y
    cpx ED_CY
    bne ec_put
    eor #$2B ^ '.'              ; '.' -> '+', block -> reversed '+'
    cmp #$2B
    beq ec_cw
    lda #$AB
    bne ec_put
ec_cw:
    ldx #1                      ; on an empty pixel: a white '+'
    stx ED_T+2
ec_put:
    ldy #0
    sta (mosPTR2),y
    lda ED_T+2
    sta (ed_cp),y
    rts
ec_out:
    lda #' '
    ldy #0
    sta (mosPTR2),y
    rts

; ed_dispcol: A = logical value ED_V -> C64 colour shown. GXR: the BBC
; colour (bbc2c64); VIC: 1 white (the sprite's), multicolour 1 $D025,
; 2 white, 3 $D026.
ed_dispcol:
    lda ED_KIND
    bne edc_vic
    lda ED_V
    and #15
    tax
    lda bbc2c64,x
    rts
edc_vic:
    lda ED_MC
    bne edc_mc
    lda #1
    rts
edc_mc:
    lda ED_V
    cmp #1
    bne edc_n1
    lda $D025
    and #15
    rts
edc_n1:
    cmp #2
    bne edc_3
    lda #1
    rts
edc_3:
    lda $D026
    and #15
    rts

; ed_scroll: the grid's origin so that the cursor is in view
ed_scroll:
    lda ED_CX
    cmp ED_OX
    bcs eds_x1
    sta ED_OX
eds_x1:
    lda ED_OX
    clc
    adc #GRID_W-1
    cmp ED_CX
    bcs eds_y
    lda ED_CX
    sec
    sbc #GRID_W-1
    sta ED_OX
eds_y:
    lda ED_CY
    cmp ED_OY
    bcs eds_y1
    sta ED_OY
eds_y1:
    lda ED_OY
    clc
    adc #GRID_H-1
    cmp ED_CY
    bcs eds_rts
    lda ED_CY
    sec
    sbc #GRID_H-1
    sta ED_OY
eds_rts:
    rts

; ed_panel: position, colour, the swatches, the keys (the area cleared
; first: the swatches' number changes)
ed_panel:
    lda #1
    sta ED_T+1
epa_clr:
    ldx #PANEL
    ldy ED_T+1
    jsr ed_at
    ldy #39-PANEL
    lda #' '
epa_cc:
    sta (mosPTR2),y
    dey
    bpl epa_cc
    inc ED_T+1
    lda ED_T+1
    cmp #24
    bcc epa_clr
    ldx #PANEL
    ldy #1
    jsr ed_at
    jsr ed_str
    dta 'x', 0
    lda ED_CX
    jsr ed_dec3
    jsr ed_str
    dta ' y', 0
    lda ED_CY
    jsr ed_dec3
    ldx #PANEL
    ldy #2
    jsr ed_at
    jsr ed_str
    dta 'colour ', 0
    lda ED_COL
    jsr ed_dec3
    lda #0                      ; swatches: 4 a row, as many as there are
    sta ED_V
epa_sw:
    jsr ed_ncol
    cmp ED_V
    beq epa_keys
    bcc epa_keys
    lda ED_V                    ; row 4 + v / 4, column PANEL + (v AND 3) * 4
    lsr
    lsr
    clc
    adc #4
    tay
    lda ED_V
    and #3
    asl
    asl
    clc
    adc #PANEL
    tax
    jsr ed_at
    lda ED_V
    jsr ed_hexd
    lda #$A0
    ldy #1
    sta (mosPTR2),y
    jsr ed_dispcol
    ldy #1
    sta (ed_cp),y
    inc ED_V
    bne epa_sw
epa_keys:
    ldx #0
    ldy #9
epa_k:
    stx ED_T
    sty ED_T+1
    ldx #PANEL
    jsr ed_at
    ldx ED_T
epa_c:
    lda ed_help,x
    beq epa_n
    jsr ed_chr
    inx
    bne epa_c
epa_n:
    inx
    lda ed_help,x
    beq epa_done
    ldy ED_T+1
    iny
    cpy #24
    bcc epa_k
epa_done:
    rts
ed_help:
    dta '0-9 +- colour', 0
    dta 'SPC paint', 0
    dta 'P pick', 0
    dta 'F fill C clear', 0
    dta 'H V flip', 0
    dta 'IJKL shift', 0
    dta 'S size', 0
    dta 'G n get', 0
    dta 'M multicolour', 0
    dta 'RETURN keep', 0
    dta 'ESCAPE cancel', 0
    dta 0

; ed_ncol: A = the colours: GXR 16, VIC 2, VIC multicolour 4
ed_ncol:
    lda ED_KIND
    bne enc_v
    lda #16
    rts
enc_v:
    lda ED_MC
    beq enc_2
    lda #4
    rts
enc_2:
    lda #2
    rts

; ed_preview: the VIC shape at its real size: hardware sprite 0, its
; 63 bytes at PREVIEW (RAM under the KERNAL: written through)
ed_preview:
    jsr ed_encode
    ldx #63
epv_cp:
    lda MOSBUF,x
    sta PREVIEW,x
    dex
    bpl epv_cp
    lda #PREV_PTR
    sta SCRN+$3F8
    lda #1
    sta $D027
    lda #<[24+30*8]             ; x (VIC): column 30 (264: bit 8 set)
    sta $D000
    lda #1
    sta $D010
    lda #50+8*20                ; y: rows 20-22, below the key help
    sta $D001
    lda ED_MC
    sta $D01C
    lda #0
    sta $D017
    sta $D01D
    lda #1
    sta $D015
    rts

; ----------------------------------------------------------------------------
; ed_at: the screen position X (column), Y (row) -> mosPTR2 (screen) and
; ed_cp (colour RAM); ed_chr: A (ASCII) there, white, then on.
ed_cp       = fsPTR             ; (zero page: free while the editor runs)
ed_at:
    lda #0
    sta mosPTR2+1
    tya                         ; row * 40 = row * 32 + row * 8
    asl
    asl
    asl
    sta mosPTR2                 ; row * 8 (< 200)
    asl
    rol mosPTR2+1
    asl
    rol mosPTR2+1               ; row * 32
    clc
    adc mosPTR2
    sta mosPTR2
    lda mosPTR2+1
    adc #0
    sta mosPTR2+1
    txa
    clc
    adc mosPTR2
    sta mosPTR2
    sta ed_cp
    lda mosPTR2+1
    adc #>SCRN
    sta mosPTR2+1
    clc
    adc #>[COLR-SCRN]
    sta ed_cp+1
    rts
ed_chr:
    jsr ed_scr                  ; ASCII -> screen code
    ldy #0
    sta (mosPTR2),y
    lda #1
    sta (ed_cp),y
    inc mosPTR2
    bne edc_c
    inc mosPTR2+1
edc_c:
    inc ed_cp
    bne edc_rts
    inc ed_cp+1
edc_rts:
    rts
; ed_scr: ASCII A -> the text screen's screen code (lower case set)
ed_scr:
    cmp #'a'
    bcc es_nl
    cmp #'z'+1
    bcs es_nl
    sbc #'a'-1-1                ; (C = 0: -$60) a-z -> 1-26
    rts
es_nl:
    cmp #'A'
    bcc es_nu
    cmp #'Z'+1
    bcs es_nu
    rts                         ; A-Z -> 65-90 (shifted letters)
es_nu:
    cmp #'@'
    bne es_rts
    lda #0
es_rts:
    rts
; ed_str: the 0-terminated text after the JSR
ed_str:
    pla
    sta ed_sp
    pla
    sta ed_sp+1
    ldy #0
eds_l:
    inc ed_sp
    bne eds_h
    inc ed_sp+1
eds_h:
    lda (ed_sp),y
    beq eds_end
    sty ED_T+3
    jsr ed_chr
    ldy ED_T+3
    jmp eds_l
eds_end:
    lda ed_sp+1
    pha
    lda ed_sp
    pha
    rts
ed_sp       = fsLEN             ; (zero page: free meanwhile)
; ed_dec / ed_dec3: A in decimal (ed_dec3: 3 places, spaces before)
ed_dec3:
    ldx #' '
    stx ED_T+2
    bne edn_go
ed_dec:
    ldx #0
    stx ED_T+2
edn_go:
    ldx #0                      ; hundreds
edn_100:
    cmp #100
    bcc edn_h
    sbc #100
    inx
    bne edn_100
edn_h:
    pha
    txa
    jsr edn_dig
    pla
    ldx #0
edn_10:
    cmp #10
    bcc edn_t
    sbc #10
    inx
    bne edn_10
edn_t:
    pha
    txa
    jsr edn_dig
    pla
    ora #'0'
    jmp ed_chr
edn_dig:                        ; a leading zero: nothing, or a space
    bne edn_d
    lda ED_T+2
    beq edn_none
    jmp ed_chr
edn_d:
    ora #'0'
    pha
    lda #'0'                    ; (later zeros are digits)
    sta ED_T+2
    pla
    jmp ed_chr
edn_none:
    rts
; ed_hexd: A (0-15) as one hex digit
ed_hexd:
    cmp #10
    bcc ehd_d
    adc #'A'-10-1
    jmp ed_chr
ehd_d:
    ora #'0'
    jmp ed_chr

; ----------------------------------------------------------------------------
; ed_dokey
;   Summary: one key: move, colour, paint and the functions.
;   Input:   A = the key (OSRDCH: 136-139 the cursor keys).
;   Output:  C = 1: RETURN (keep and leave).
ed_dokey:
    cmp #13
    bne edk_n13
    sec
    rts
edk_n13:
    cmp #'a'                    ; lower case letters as capitals
    bcc edk_up
    cmp #'z'+1
    bcs edk_up
    and #$DF
edk_up:
    ldx #edk_n-1
edk_find:
    cmp edk_keys,x
    beq edk_go
    dex
    bpl edk_find
    cmp #'0'                    ; 0-9: a colour
    bcc edk_none
    cmp #'9'+1
    bcs edk_none
    and #15
    sta ED_V
    jsr ed_ncol
    cmp ED_V
    beq edk_none
    bcc edk_none
    lda ED_V
    sta ED_COL
edk_none:
    clc
    rts
edk_go:
    txa
    asl
    tax
    lda edk_jmp+1,x
    pha
    lda edk_jmp,x
    pha
    rts
edk_keys:
    dta 136, 137, 138, 139, ' ', '+', '-', 'P', 'F', 'C', 'H', 'V'
    dta 'I', 'J', 'K', 'L', 'S', 'G', 'M'
edk_n       = * - edk_keys
edk_jmp:
    dta a(ek_left-1), a(ek_right-1), a(ek_down-1), a(ek_up-1)
    dta a(ek_paint-1), a(ek_plus-1), a(ek_minus-1), a(ek_pick-1)
    dta a(ek_fill-1), a(ek_clear-1), a(ek_fliph-1), a(ek_flipv-1)
    dta a(ek_sup-1), a(ek_sleft-1), a(ek_sdown-1), a(ek_sright-1)
    dta a(ek_size-1), a(ek_get-1), a(ek_mc-1)

ek_left:
    lda ED_CX
    beq ekl_r
    dec ED_CX
ekl_r:
    clc
    rts
ek_right:
    jsr ed_lw
    sec
    sbc #1
    cmp ED_CX
    beq ekr_r
    bcc ekr_r
    inc ED_CX
ekr_r:
    clc
    rts
ek_up:
    lda ED_CY
    beq eku_r
    dec ED_CY
eku_r:
    clc
    rts
ek_down:
    lda ED_H
    sec
    sbc #1
    cmp ED_CY
    beq ekd_r
    bcc ekd_r
    inc ED_CY
ekd_r:
    clc
    rts
ek_paint:
    jsr ed_atcur
    lda ED_COL
    jsr ed_put
    clc
    rts
ek_pick:
    jsr ed_atcur
    jsr ed_get
    sta ED_COL
    clc
    rts
ek_plus:
    inc ED_COL
    jsr ed_ncol
    cmp ED_COL
    bne ekp_r
    lda #0
    sta ED_COL
ekp_r:
    clc
    rts
ek_minus:
    dec ED_COL
    bpl ekm_r
    jsr ed_ncol
    sec
    sbc #1
    sta ED_COL
ekm_r:
    clc
    rts
ek_mc:
    lda ED_KIND                 ; VIC only: multicolour view on/off
    beq ekmc_r
    lda ED_MC
    eor #1
    sta ED_MC
    beq ekmc_hi
    lsr ED_CX                   ; 12 double pixels: half the column
    lda #3
    bne ekmc_col
ekmc_hi:
    asl ED_CX
    lda #1
ekmc_col:
    cmp ED_COL                  ; the colour within the colours there are
    bcs ekmc_o
    sta ED_COL
ekmc_o:
    lda #0
    sta ED_OX
ekmc_r:
    clc
    rts
ed_atcur:
    lda ED_CX
    sta ED_X
    lda ED_CY
    sta ED_Y
    rts

; ek_clear: every pixel 0
ek_clear:
    lda #0
    sta ED_Y
ekc_r:
    lda #0
    sta ED_X
ekc_c:
    lda #0
    jsr ed_put
    inc ED_X
    jsr ed_lw
    cmp ED_X
    beq ekc_n
    bcs ekc_c
ekc_n:
    inc ED_Y
    lda ED_Y
    cmp ED_H
    bcc ekc_r
    clc
    rts

; ek_fliph: each row mirrored. ek_flipv: the rows in reverse order.
ek_fliph:
    lda #0
    sta ED_Y
ekh_r:
    lda #0
    sta ED_T                    ; left
    jsr ed_lw
    sec
    sbc #1
    sta ED_T+1                  ; right
ekh_s:
    lda ED_T
    cmp ED_T+1
    bcs ekh_n
    jsr ed_swapx
    inc ED_T
    dec ED_T+1
    jmp ekh_s
ekh_n:
    inc ED_Y
    lda ED_Y
    cmp ED_H
    bcc ekh_r
    clc
    rts
; ed_swapx: pixels (ED_T, ED_Y) and (ED_T+1, ED_Y) exchanged
ed_swapx:
    lda ED_T
    sta ED_X
    jsr ed_get
    pha
    lda ED_T+1
    sta ED_X
    jsr ed_get
    pha
    lda ED_T
    sta ED_X
    pla
    jsr ed_put
    lda ED_T+1
    sta ED_X
    pla
    jmp ed_put

ek_flipv:
    lda #0
    sta ED_T                    ; top
    lda ED_H
    sec
    sbc #1
    sta ED_T+1                  ; bottom
ekv_s:
    lda ED_T
    cmp ED_T+1
    bcs ekv_d
    lda #0
    sta ED_X
ekv_x:
    lda ED_T
    sta ED_Y
    jsr ed_get
    pha
    lda ED_T+1
    sta ED_Y
    jsr ed_get
    pha
    lda ED_T
    sta ED_Y
    pla
    jsr ed_put
    lda ED_T+1
    sta ED_Y
    pla
    jsr ed_put
    inc ED_X
    jsr ed_lw
    cmp ED_X
    beq ekv_n
    bcs ekv_x
ekv_n:
    inc ED_T
    dec ED_T+1
    jmp ekv_s
ekv_d:
    clc
    rts

; ek_sleft / ek_sright / ek_sup / ek_sdown: the image shifted a pixel,
; what falls out coming in on the other side
ek_sleft:
    lda #0
    sta ED_Y
eksl_r:
    lda #0
    sta ED_X
    jsr ed_get
    pha                         ; the left pixel
eksl_c:
    inc ED_X
    jsr ed_lw
    cmp ED_X
    beq eksl_e
    jsr ed_get
    dec ED_X
    jsr ed_put
    inc ED_X
    jmp eksl_c
eksl_e:
    dec ED_X
    pla
    jsr ed_put
    inc ED_Y
    lda ED_Y
    cmp ED_H
    bcc eksl_r
    clc
    rts
ek_sright:
    lda #0
    sta ED_Y
eksr_r:
    jsr ed_lw
    sec
    sbc #1
    sta ED_X
    jsr ed_get
    pha                         ; the right pixel
eksr_c:
    lda ED_X
    beq eksr_e
    dec ED_X
    jsr ed_get
    inc ED_X
    jsr ed_put
    dec ED_X
    jmp eksr_c
eksr_e:
    pla
    jsr ed_put
    inc ED_Y
    lda ED_Y
    cmp ED_H
    bcc eksr_r
    clc
    rts
ek_sup:
    lda #0
    sta ED_X
eksu_c:
    lda #0
    sta ED_Y
    jsr ed_get
    pha
eksu_r:
    inc ED_Y
    lda ED_Y
    cmp ED_H
    beq eksu_e
    jsr ed_get
    dec ED_Y
    jsr ed_put
    inc ED_Y
    jmp eksu_r
eksu_e:
    dec ED_Y
    pla
    jsr ed_put
    inc ED_X
    jsr ed_lw
    cmp ED_X
    beq eksu_d
    bcs eksu_c
eksu_d:
    clc
    rts
ek_sdown:
    lda #0
    sta ED_X
eksd_c:
    lda ED_H
    sec
    sbc #1
    sta ED_Y
    jsr ed_get
    pha
eksd_r:
    lda ED_Y
    beq eksd_e
    dec ED_Y
    jsr ed_get
    inc ED_Y
    jsr ed_put
    dec ED_Y
    jmp eksd_r
eksd_e:
    pla
    jsr ed_put
    inc ED_X
    jsr ed_lw
    cmp ED_X
    beq eksd_d
    bcs eksd_c
eksd_d:
    clc
    rts

; ----------------------------------------------------------------------------
; ek_fill: the area of the cursor's colour around it (4 neighbours) in
; the colour painted: a scan-line fill, its stack (x, y pairs) in REU
; bank FILL_BANK (up to 32K pairs)
ek_fill:
    jsr ed_atcur
    jsr ed_get
    cmp ED_COL
    bne ekf_go
    clc                         ; (the same colour: nothing to do)
    rts
ekf_go:
    sta ED_TGT
    lda #0
    sta ED_FSP
    sta ED_FSP+1
    jsr ekf_push                ; the cursor's pixel
ekf_pop:
    lda ED_FSP
    ora ED_FSP+1
    bne ekf_take
    clc
    rts
ekf_take:
    lda ED_FSP                   ; pop: (x, y) into ED_X, ED_Y
    bne ekf_d
    dec ED_FSP+1
ekf_d:
    dec ED_FSP
    jsr ekf_addr
    lda #REU_TO_C64
    jsr ekf_dma
    lda ED_T+2
    sta ED_X
    lda ED_T+3
    sta ED_Y
    jsr ed_get
    cmp ED_TGT
    bne ekf_pop
ekf_left:                       ; the run: left to its start
    lda ED_X
    beq ekf_runs
    dec ED_X
    jsr ed_get
    cmp ED_TGT
    beq ekf_left
    inc ED_X
ekf_runs:
    lda #0                      ; flags: above / below a run was pushed
    sta ED_T
    sta ED_T+1
ekf_run:
    lda ED_COL                  ; fill this pixel
    jsr ed_put
    lda ED_Y                    ; above
    beq ekf_noup
    dec ED_Y
    jsr ed_get
    inc ED_Y
    cmp ED_TGT
    bne ekf_upend
    lda ED_T
    bne ekf_noup
    dec ED_Y
    jsr ekf_push
    inc ED_Y
    lda #1
    sta ED_T
    bne ekf_noup
ekf_upend:
    lda #0
    sta ED_T
ekf_noup:
    lda ED_Y                    ; below
    clc
    adc #1
    cmp ED_H
    bcs ekf_nodn
    inc ED_Y
    jsr ed_get
    dec ED_Y
    cmp ED_TGT
    bne ekf_dnend
    lda ED_T+1
    bne ekf_nodn
    inc ED_Y
    jsr ekf_push
    dec ED_Y
    lda #1
    sta ED_T+1
    bne ekf_nodn
ekf_dnend:
    lda #0
    sta ED_T+1
ekf_nodn:
    inc ED_X                    ; on to the right while the colour is it
    jsr ed_lw
    cmp ED_X
    beq ekf_next
    jsr ed_get
    cmp ED_TGT
    beq ekf_run
ekf_next:
    jmp ekf_pop
; ekf_push: (ED_X, ED_Y) onto the stack (full: ignored)
ekf_push:
    lda ED_FSP+1
    cmp #$40                    ; 16K pairs: the bank's first 32K
    bcs ekp_full
    lda ED_X
    sta ED_T+2
    lda ED_Y
    sta ED_T+3
    jsr ekf_addr
    lda #REU_TO_REU
    jsr ekf_dma
    inc ED_FSP
    bne ekp_full
    inc ED_FSP+1
ekp_full:
    rts
; ekf_addr: fsTMP = ED_FSP * 2 in FILL_BANK
ekf_addr:
    lda ED_FSP
    asl
    sta fsTMP
    lda ED_FSP+1
    rol
    sta fsTMP+1
    lda #FILL_BANK
    sta fsTMP+2
    rts
ekf_dma:
    pha
    lda #<[ED_T+2]
    sta fsADDR
    lda #>[ED_T+2]
    sta fsADDR+1
    lda #2
    sta fsLEN
    lda #0
    sta fsLEN+1
    pla
    jmp ed_dma

; ----------------------------------------------------------------------------
; ek_size (GXR): width and height asked on the bottom row; the content
; kept, new parts 0. ek_get (GXR): another sprite into the buffer.
ek_size:
    lda ED_KIND
    bne eks_no
    jsr ed_ask
    dta 'Width (1-192)? ', 0
    bcs eks_no
    beq eks_no
    cmp #193
    bcs eks_no
    pha
    jsr ed_ask
    dta 'Height (1-255)? ', 0
    tax
    pla
    bcs eks_no
    cpx #0
    beq eks_no
    sta ED_T                    ; new size
    stx ED_T+1
    lda ED_W                    ; clear what is new: columns >= old width
    sta ED_X                    ; in every row up to the new height, and
    lda #0                      ; the rows below the old height
    sta ED_Y
    jsr eks_clear
    lda ED_T
    sta ED_W
    lda ED_T+1
    sta ED_H
    lda #0                      ; the cursor inside
    sta ED_CX
    sta ED_CY
    sta ED_OX
    sta ED_OY
eks_no:
    clc
    rts
; eks_clear: buffer columns ED_X.. of rows 0..new h-1 and whole rows
; from the old height on: 0 (simply: every byte outside old w x old h
; inside the new size)
eks_clear:
    lda #0
    sta ED_Y
eksc_r:
    lda #0
    sta ED_X
eksc_c:
    lda ED_X
    cmp ED_W
    bcs eksc_z
    lda ED_Y
    cmp ED_H
    bcc eksc_n
eksc_z:
    lda #0
    jsr ed_bufput
eksc_n:
    inc ED_X
    lda ED_X
    cmp ED_T
    bcc eksc_c
    inc ED_Y
    lda ED_Y
    cmp ED_T+1
    bcc eksc_r
    rts

ek_get:
    lda ED_KIND                 ; GXR only: another sprite into the buffer
    bne ekg_no                  ; (stored under this one's number)
    jsr ed_ask
    dta 'Get sprite (0-255)? ', 0
    bcs ekg_no
    tax
    lda ED_N
    pha
    stx ED_N
    jsr ed_load
    pla
    sta ED_N
    lda #0
    sta ED_CX
    sta ED_CY
    sta ED_OX
    sta ED_OY
ekg_no:
    clc
    rts

; ed_ask: the text after the JSR on the bottom row, then a number typed
; (digits, DELETE, RETURN; ESCAPE cancels). Output: A = the number (low
; byte; Z for 0); C = 1 when cancelled or nothing typed.
ed_ask:
    pla                         ; the text's address (after the JSR)
    sta ed_sp
    pla
    sta ed_sp+1
    ldx #39                     ; the bottom row cleared
    lda #' '
eda_cl:
    sta SCRN+24*40,x
    dex
    bpl eda_cl
    ldx #0
    ldy #24
    jsr ed_at
    ldy #0
eda_t:
    inc ed_sp
    bne eda_h
    inc ed_sp+1
eda_h:
    lda (ed_sp),y
    beq eda_te
    sty ED_T+3
    jsr ed_chr
    ldy ED_T+3
    jmp eda_t
eda_te:
    lda ed_sp+1                 ; return past the text
    pha
    lda ed_sp
    pha
    lda #0
    sta ED_NUM
    sta ED_NUM+1                ; (digits typed)
eda_key:
    jsr OSRDCH
    bcc eda_k
    lda #$7E                    ; ESCAPE: acknowledged, cancelled
    jsr OSBYTE
    sec
    rts
eda_k:
    cmp #13
    beq eda_done
    cmp #127                    ; DELETE: start again
    bne eda_dig
    lda #0
    sta ED_NUM
    sta ED_NUM+1
    jmp eda_key
eda_dig:
    cmp #'0'
    bcc eda_key
    cmp #'9'+1
    bcs eda_key
    pha
    jsr ed_chr                  ; echo
    pla
    and #15
    sta ED_V
    lda ED_NUM                  ; num = num * 10 + digit (8 bits)
    asl
    sta ED_T
    asl
    asl
    clc
    adc ED_T
    clc
    adc ED_V
    sta ED_NUM
    inc ED_NUM+1
    jmp eda_key
eda_done:
    lda ED_NUM+1                ; nothing typed: C = 1
    bne eda_some
    sec
    rts
eda_some:
    clc
    lda ED_NUM                  ; (Z for 0)
    rts

wd_vic      dta 'VIC', 0
    .endl
