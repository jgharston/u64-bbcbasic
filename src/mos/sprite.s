; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- sprites (*SPRITE, OSWORD &71), bank 5
;
; Up to 32 sprites on the VIC-II's 8, multiplexed by a raster interrupt
; (spritemux.s, a RAM image below HIMEM: *SPRITE ON loads it and lowers
; HIMEM by 5 pages, *SPRITE OFF gives them back; switched on and off by
; the user, as the sound engine). Positions in BBC graphics coordinates.
; Shapes: 64 of 24 x 21 (63 bytes), kept in the REU (REU_SHAPES); in the
; text screen also at $E000 (VIC-II pointers $80-$BF); in the graphics
; modes and MODE 7 the multiplexer copies them into two blocks at $FF40
; as the sprites come (docs/DESIGN_SPRITES.md); Upic Lite cannot show
; VIC-II sprites.
;
; ----------------------------------------------------------------------------

SPR_PAGES   = 5                 ; the image's size in pages
REU_SHAPES  = $1000             ; REU bank 1 (free beside the song header)
REU_SHBANK  = 1
SHAPE_RAM   = $E000             ; text screen: shapes here (VIC-II $80+)
REU_SCRATCH = $2000             ; REU bank 1, 17 pages: *SPRITE LOAD's file
SCRATCH_PG  = 17

; ----------------------------------------------------------------------------
; The multiplexer images (spritemux.s), assembled for $7B00 and $7700

spr_img7b:
    .local mux7b
    org $7B00, spr_img7b
    icl 'spritemux.s'
    .endl
SPR_LEN     = mux7b.spr_image_end - $7B00
    org spr_img7b + SPR_LEN
    .if SPR_LEN > SPR_PAGES*256
    .error "Sprite image over 5 pages"
    .endif
spr_img77:
    .local mux77
    org $7700, spr_img77
    icl 'spritemux.s'
    .endl
    org spr_img77 + SPR_LEN

; The tables' offsets in the image (the same in both)
O_XLO       = mux7b.sx_lo - $7B00
O_XHI       = mux7b.sx_hi - $7B00
O_Y         = mux7b.sy - $7B00
O_PTR       = mux7b.sptr - $7B00
O_COL       = mux7b.scol - $7B00
O_FLG       = mux7b.sflg - $7B00
O_COLL      = mux7b.scoll - $7B00
O_ORDER     = mux7b.sorder - $7B00
O_NEXT      = mux7b.mx_next - $7B00
O_OLDVEC    = mux7b.mx_oldvec - $7B00
O_IRQ       = mux7b.mx_irq - $7B00
O_BMP       = mux7b.mx_bmp - $7B00
O_BLKSHP    = mux7b.blk_shape - $7B00
    .if O_COLL+32 > 256
    .error "Sprite tables must lie below offset 256"
    .endif

    .local spr
    icl 'bankhelp.s'

; ----------------------------------------------------------------------------
; cmd_sprite
;   Summary: *SPRITE ON | OFF | n ON x,y | n OFF | n SHAPE s | n COLOUR c
;            | n SIZE w h | n BEHIND | n FRONT | DEFINE s hex | (list).
;   Input:   mosPTR/Y = rest of the command line.
;   Output:  per command.  Uses: A, X, Y, fs*, mosNUM, mosPTR2, MOSBUF.
cmd_sprite:
    jsr s6_skipsp
    cmp #13
    bne cs_args
    jmp sp_list
cs_args:
    lda #<wd_on
    ldx #>wd_on
    jsr s6_word
    bcc cs_noon
    jsr s6_end
    jmp sp_on
cs_noon:
    lda #<wd_off
    ldx #>wd_off
    jsr s6_word
    bcc cs_nooff
    jsr s6_end
    jmp sp_off
cs_nooff:
    lda #<wd_define
    ldx #>wd_define
    jsr s6_word
    bcc cs_nodef
    jmp sp_define
cs_nodef:
    lda #<wd_colours
    ldx #>wd_colours
    jsr s6_word
    bcc cs_nocols
    jmp sp_colours
cs_nocols:
    lda #<wd_load
    ldx #>wd_load
    jsr s6_word
    bcc cs_noload
    jmp sp_load
cs_noload:
    jsr s6_need                 ; *SPRITE n ...
    lda mosNUM+1
    bne cs_badn
    lda mosNUM
    cmp #32
    bcc cs_n
cs_badn:
    jmp sp_badn
cs_n:
    sta fsSX                    ; the sprite
    jsr sp_need                 ; (the image is in RAM)
    lda #<wd_on
    ldx #>wd_on
    jsr s6_word
    bcc cs_n_off
    jmp sp_non
cs_n_off:
    lda #<wd_off
    ldx #>wd_off
    jsr s6_word
    bcc cs_n_shape
    jsr s6_end
    lda #0                      ; flag bit 0 off
    ldx #$FE
    jmp sp_flag
cs_n_shape:
    lda #<wd_shape
    ldx #>wd_shape
    jsr s6_word
    bcc cs_n_col
    jsr sp_byte64
    clc
    adc #$80                    ; text screen: pointer $80 + shape
    ldx #O_PTR
    jmp sp_set
cs_n_col:
    lda #<wd_colour
    ldx #>wd_colour
    jsr s6_word
    bcc cs_n_size
    jsr s6_need
    lda mosNUM
    and #15
    tax
    lda sp_bbc2c64,x
    ldx #O_COL
    jmp sp_set
cs_n_size:
    lda #<wd_size
    ldx #>wd_size
    jsr s6_word
    bcc cs_n_multi
    jmp sp_size
cs_n_multi:
    lda #<wd_multi
    ldx #>wd_multi
    jsr s6_word
    bcc cs_n_behind
    lda #<wd_on
    ldx #>wd_on
    jsr s6_word
    bcc csm_off
    jsr s6_end
    lda #16                     ; flag bit 4: multicolour
    ldx #$FF
    jmp sp_flag
csm_off:
    lda #<wd_off
    ldx #>wd_off
    jsr s6_word
    bcc cs_syn2
    jsr s6_end
    lda #0
    ldx #$EF
    jmp sp_flag
cs_syn2:
    jmp s6_syntax
cs_n_behind:
    lda #<wd_behind
    ldx #>wd_behind
    jsr s6_word
    bcc cs_n_front
    jsr s6_end
    lda #8
    ldx #$FF
    jmp sp_flag
cs_n_front:
    lda #<wd_front
    ldx #>wd_front
    jsr s6_word
    bcc cs_syn
    jsr s6_end
    lda #0
    ldx #$F7
    jmp sp_flag
cs_syn:
    jmp s6_syntax
sp_badn:
    brk
    dta 252, 'Bad sprite (0-31)', 0

; sp_need: the image must be in RAM ("Sprites are off" otherwise)
sp_need:
    lda spr_page
    beq spn_off
    rts
spn_off:
    brk
    dta 251, 'Sprites are off (*SPRITE ON)', 0

; sp_byte64: a number 0-63 -> A ("Bad shape")
sp_byte64:
    jsr s6_need
    lda mosNUM+1
    bne spb_bad
    lda mosNUM
    cmp #64
    bcs spb_bad
    pha
    jsr s6_end
    pla
    rts
spb_bad:
    brk
    dta 250, 'Bad shape (0-63)', 0

; sp_set: table X (offset), sprite fsSX := A (interrupts off)
sp_set:
    pha
    txa
    clc
    adc fsSX
    sta mosPTR2
    lda spr_page
    sta mosPTR2+1
    pla
    ldy #0
    php
    sei
    sta (mosPTR2),y
    plp
    rts

; sp_flag: sprite fsSX's flags := (flags AND X) OR A (interrupts off)
sp_flag:
    sta mosTMP
    stx mosTMP+1
    lda #O_FLG
    clc
    adc fsSX
    sta mosPTR2
    lda spr_page
    sta mosPTR2+1
    ldy #0
    php
    sei
    lda (mosPTR2),y
    and mosTMP+1
    ora mosTMP
    sta (mosPTR2),y
    plp
    rts

; ----------------------------------------------------------------------------
; sp_non: n ON x,y: the position (BBC coordinates) and shown
sp_non:
    jsr s6_need                 ; x
    lda mosNUM
    sta fsTMP
    lda mosNUM+1
    sta fsTMP+1
    jsr s6_skipsp
    cmp #','
    bne spo_y
    iny
spo_y:
    jsr s6_need                 ; y
    jsr s6_end
    lda mosNUM
    sta fsTMP+2
    lda mosNUM+1
    sta fsTMP+3
    jsr sp_move                 ; the VIC-II position
    lda #1
    ldx #$FF
    jmp sp_flag

; sp_move: sprite fsSX to BBC x = fsTMP/+1, y = fsTMP+2/+3 (both 16 bits,
; kept inside 0-1279 and 0-1023): VIC x = x / 4 + 24, VIC y (its top) =
; 50 + (1023 - y) * 200 / 1024 - 20 (- 21 more when it is double high).
; Uses: A, X, Y, fsCNT, mosTMP, mosPTR2.
sp_move:
    lda fsTMP+1                 ; x: 0-1279
    bmi spm_x0
    cmp #>1280
    bcc spm_xok
    bne spm_xmax
    lda fsTMP
    cmp #<1280
    bcc spm_xok
spm_xmax:
    lda #<1279
    sta fsTMP
    lda #>1279
    sta fsTMP+1
    bne spm_xok
spm_x0:
    lda #0
    sta fsTMP
    sta fsTMP+1
spm_xok:
    lsr fsTMP+1                 ; / 4
    ror fsTMP
    lsr fsTMP+1
    ror fsTMP
    lda fsTMP
    clc
    adc #24
    sta fsCNT                   ; VIC x low
    lda fsTMP+1
    adc #0
    sta fsCNT+1                 ; bit 8
    lda fsTMP+3                 ; y: 0-1023
    bmi spm_y0
    cmp #4
    bcc spm_yok
    lda #<1023
    sta fsTMP+2
    lda #>1023
    sta fsTMP+3
    bne spm_yok
spm_y0:
    lda #0
    sta fsTMP+2
    sta fsTMP+3
spm_yok:
    lda #<1023                  ; d = 1023 - y
    sec
    sbc fsTMP+2
    sta mosTMP
    lda #>1023
    sbc fsTMP+3
    sta mosTMP+1
    lda mosTMP                  ; d * 25 = d * 16 + d * 8 + d
    sta mosTMP+2
    lda mosTMP+1
    sta mosTMP+3
    ldx #3
spm_x8:
    asl mosTMP
    rol mosTMP+1
    dex
    bne spm_x8                  ; d * 8
    lda mosTMP
    clc
    adc mosTMP+2
    sta mosTMP+2
    lda mosTMP+1
    adc mosTMP+3
    sta mosTMP+3                ; d * 9
    asl mosTMP
    rol mosTMP+1                ; d * 16
    lda mosTMP
    clc
    adc mosTMP+2
    sta mosTMP
    lda mosTMP+1
    adc mosTMP+3
    sta mosTMP+1                ; d * 25
    asl mosTMP                  ; / 128: the high byte after one shift
    lda mosTMP+1
    rol
    clc
    adc #50-20                  ; the screen's top line, the sprite's top
    sta mosTMP                  ; (row 0-199; the carry: never over 255)
    lda #O_FLG                  ; double high: 21 lines more above
    clc
    adc fsSX
    sta mosPTR2
    lda spr_page
    sta mosPTR2+1
    ldy #0
    lda (mosPTR2),y
    and #4
    beq spm_store
    lda mosTMP
    sec
    sbc #21
    bcs spm_hi
    lda #0
spm_hi:
    sta mosTMP
spm_store:
    php                         ; x low, x bit 8, y: together
    sei
    lda #O_XLO
    jsr spm_ptr
    lda fsCNT
    sta (mosPTR2),y
    lda #O_XHI
    jsr spm_ptr
    lda fsCNT+1
    sta (mosPTR2),y
    lda #O_Y
    jsr spm_ptr
    lda mosTMP
    sta (mosPTR2),y
    plp
    rts
; spm_ptr: mosPTR2 = table A (offset) of sprite fsSX, Y = 0 (the page
; every time: the print helpers use mosPTR2)
spm_ptr:
    clc
    adc fsSX
    sta mosPTR2
    lda spr_page
    sta mosPTR2+1
    ldy #0
    rts

; sp_size: n SIZE w h (1 or 2 each): flag bits 1 and 2; the top line
; moves with the height (the bottom left stays)
sp_size:
    jsr s6_need
    lda mosNUM
    sta fsTMP
    jsr s6_skipsp
    cmp #','
    bne sps_h
    iny
sps_h:
    jsr s6_need
    jsr s6_end
    lda #0
    ldx fsTMP
    cpx #2
    bne sps_w
    ora #2
sps_w:
    ldx mosNUM
    cpx #2
    bne sps_set
    ora #4
sps_set:
    pha                         ; the top: Y + 21 when it got lower, - 21
    lda #O_FLG                  ; when higher
    jsr spm_ptr
    lda spr_page
    sta mosPTR2+1
    lda (mosPTR2),y
    and #4
    sta mosTMP+3                ; was double high
    pla
    pha
    and #4
    cmp mosTMP+3
    beq sps_same
    lda #O_Y
    jsr spm_ptr
    lda mosTMP+3
    bne sps_lower
    lda (mosPTR2),y             ; now double high: 21 higher
    sec
    sbc #21
    bcs sps_y
    lda #0
    beq sps_y
sps_lower:
    lda (mosPTR2),y
    clc
    adc #21
sps_y:
    php
    sei
    sta (mosPTR2),y
    plp
sps_same:
    pla
    ldx #$F9
    jmp sp_flag

; ----------------------------------------------------------------------------
; sp_on: *SPRITE ON. sp_off: *SPRITE OFF.
sp_on:
    jsr s6_hasreu
    bne spo_reu
    brk
    dta 254, 'Sprites need an REU', 0
spo_reu:
    lda eng_kind                ; Upic Lite and Upic full: the VIC-II's
    cmp #1                      ; picture is not shown
    beq spo_upic
    cmp #3
    bne spo_vic
spo_upic:
    brk
    dta 249, 'Sprites need a VIC-II mode: MODE 128+n', 0
spo_vic:
    lda #1
    sta spr_on
    lda spr_page
    bne spo_rts                 ; (on already)
    lda $0C                     ; at the prompt: now (BASIC's HIMEM moves
    cmp #>$0700                 ; down); in a program: with the next MODE
    bne spo_rts
    jsr sp_install
    lda spr_page                ; BASIC's HIMEM
    sta $07
    lda #0
    sta $06
spo_rts:
    rts

sp_off:
    lda #0
    sta spr_on
    jsr sp_remove
    lda $0C                     ; at the prompt: BASIC's HIMEM back
    cmp #>$0700
    bne spf_rts
    lda vmode_himem
    sta $07
    lda #0
    sta $06
spf_rts:
    rts

; ----------------------------------------------------------------------------
; sp_install
;   Summary: the multiplexer below the mode's HIMEM, running.
;   Function: copies the image for that address ($7B00 or $7700), puts
;            the 32 sprites in order, hidden, the text screen's shapes at
;            $E000 from the REU, and starts the raster interrupt (the old
;            vector kept in the image for the other interrupts).
;   Input:   vmode_himem ($80 or $7C).  Output: spr_page.
;   Uses:    A, X, Y, mosPTR, mosPTR2.
sp_install:
    lda vmode_himem
    sec
    sbc #SPR_PAGES
    sta mosPTR2+1
    lda #0
    sta mosPTR2
    lda #<spr_img7b
    ldx #>spr_img7b
    ldy mosPTR2+1
    cpy #$7B
    beq spi_src
    lda #<spr_img77
    ldx #>spr_img77
spi_src:
    sta mosPTR
    stx mosPTR+1
    ldy #0                      ; copy SPR_LEN bytes
    ldx #>[SPR_LEN+255]
spi_copy:
    lda (mosPTR),y
    sta (mosPTR2),y
    iny
    bne spi_copy
    inc mosPTR+1
    inc mosPTR2+1
    dex
    bne spi_copy
    lda vmode_himem
    sec
    sbc #SPR_PAGES
    sta mosPTR2+1
    lda #<O_ORDER               ; sorder = 0, 1, ... 31 (it crosses a
    sta mosPTR2                 ; page: through the pointer)
    lda mosPTR2+1
    clc
    adc #>O_ORDER
    sta mosPTR2+1
    ldy #0
spi_order:
    tya
    sta (mosPTR2),y
    iny
    cpy #32
    bcc spi_order
    lda vmode_himem
    sec
    sbc #SPR_PAGES
    sta mosPTR2+1
    lda #0
    sta mosPTR2
    ldy #O_COL                  ; colours white, pointers shape 0
    lda #1
    ldx #32
spi_col:
    sta (mosPTR2),y
    iny
    dex
    bne spi_col
    ldy #O_PTR
    lda #$80
    ldx #32
spi_ptr:
    sta (mosPTR2),y
    iny
    dex
    bne spi_ptr
    lda vtype                   ; the text screen: the shapes to $E000;
    bne spi_bmp                 ; a bitmap: the multiplexer copies them
    jsr sp_shapes
    jmp spi_vec
spi_bmp:
    ldy #O_BMP
    lda #1
    sta (mosPTR2),y
spi_vec:
    lda mosPTR2+1
    sta spr_page
    php                         ; the raster interrupt
    sei
    lda $0314
    ldy #O_OLDVEC
    sta (mosPTR2),y
    lda $0315
    iny
    sta (mosPTR2),y
    lda #<O_IRQ
    sta $0314
    lda spr_page
    clc
    adc #>O_IRQ
    sta $0315
    lda #mux7b.FRAME_LINE
    sta $D012
    lda $D011
    and #$7F
    sta $D011
    lda #1
    sta $D019
    lda $D01A
    ora #1
    sta $D01A
    plp
    rts

; sp_remove: the multiplexer stopped (the old vector back), sprites hidden
sp_remove:
    lda spr_page
    beq spr_rts
    sta mosPTR2+1
    lda #0
    sta mosPTR2
    php
    sei
    lda $D01A
    and #$FE
    sta $D01A
    lda #1
    sta $D019
    lda #0
    sta $D015
    ldy #O_OLDVEC
    lda (mosPTR2),y
    sta $0314
    iny
    lda (mosPTR2),y
    sta $0315
    lda #0
    sta spr_page
    plp
spr_rts:
    rts

; sp_shapes: the 64 shapes from the REU to SHAPE_RAM (text screen)
sp_shapes:
    lda #<SHAPE_RAM
    sta fsADDR
    lda #>SHAPE_RAM
    sta fsADDR+1
    lda #<REU_SHAPES
    sta fsTMP
    lda #>REU_SHAPES
    sta fsTMP+1
    lda #REU_SHBANK
    sta fsTMP+2
    lda #0
    sta fsLEN
    lda #>[64*64]
    sta fsLEN+1
    lda #REU_TO_C64
    jmp rd_dma

; ----------------------------------------------------------------------------
; spr_modehook (from bk_mode, bank 3): after a MODE change with sprites
; on (bk_mode took the multiplexer out before it): in again below the new
; HIMEM, the sprites hidden as a MODE clears; not in a Upic Lite mode.
spr_modehook:
smh_in:
    lda eng_kind
    cmp #1
    beq smh_rts
    cmp #3
    beq smh_rts
    jmp sp_install
smh_rts:
    rts

; ----------------------------------------------------------------------------
; sp_define: DEFINE s hex: shape s from 126 hex digits (63 bytes, 3 a row
; of 24 dots, as SpritePad); to the REU, and to $E000 when sprites are on
; in the text screen
sp_define:
    jsr sp_byte64n
    sta fsSX
    ldx #0
spd_byte:
    jsr s6_skipsp
    jsr spd_hex
    asl
    asl
    asl
    asl
    sta mosTMP
    iny
    lda (mosPTR),y
    jsr spd_hex
    ora mosTMP
    sta MOSBUF,x
    iny
    inx
    cpx #63
    bcc spd_byte
    jsr s6_end
    lda #0
    sta MOSBUF+63
    lda #<MOSBUF                ; to the REU: REU_SHAPES + s * 64
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    jsr spd_reuaddr
    lda #64
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jsr rd_dma
    jsr sp_inval                ; (a block may hold the old shape)
    lda spr_page                ; and to $E000 + s * 64
    beq spd_rts
    lda vtype
    bne spd_rts
    lda fsSX
    lsr
    lsr
    clc
    adc #>SHAPE_RAM
    sta mosPTR2+1
    lda fsSX
    and #3
    lsr
    ror
    ror
    sta mosPTR2
    ldy #63
spd_ram:
    lda MOSBUF,y
    sta (mosPTR2),y
    dey
    bpl spd_ram
spd_rts:
    rts
spd_reuaddr:
    lda fsSX
    lsr
    lsr
    clc
    adc #>REU_SHAPES
    sta fsTMP+1
    lda fsSX
    and #3
    lsr
    ror
    ror
    sta fsTMP
    lda #REU_SHBANK
    sta fsTMP+2
    rts
; spd_hex: A (a hex digit) -> 0-15 ("Syntax" otherwise)
spd_hex:
    jsr s6_up
    cmp #'0'
    bcc spd_bad
    cmp #'9'+1
    bcc spd_dig
    cmp #'A'
    bcc spd_bad
    cmp #'F'+1
    bcs spd_bad
    sbc #'A'-10-1               ; (C = 0 here)
    rts
spd_dig:
    and #15
    rts
spd_bad:
    jmp s6_syntax
; sp_byte64n: as sp_byte64, more may follow
sp_byte64n:
    jsr s6_need
    lda mosNUM+1
    bne spbn_bad
    lda mosNUM
    cmp #64
    bcs spbn_bad
    rts
spbn_bad:
    jmp spb_bad

; ----------------------------------------------------------------------------
; sp_list: *SPRITE alone: on or off, then each sprite shown: number,
; shape, VIC position
sp_list:
    lda spr_page
    bne spl_on
    jsr s6_text
    dta 'Sprites off', 13, 0
    rts
spl_on:
    jsr s6_text
    dta 'Sprites on at &', 0
    lda spr_page
    jsr spl_hex
    jsr s6_text
    dta '00', 13, 0
    lda #0
    sta fsSX
spl_loop:
    lda #O_FLG
    jsr spm_ptr
    lda spr_page
    sta mosPTR2+1
    lda (mosPTR2),y
    lsr
    bcc spl_next
    lda fsSX
    jsr s6_dec8
    jsr s6_text
    dta ' shape ', 0
    lda #O_PTR
    jsr spm_ptr
    lda (mosPTR2),y
    sec
    sbc #$80
    jsr s6_dec8
    jsr s6_text
    dta ' at ', 0
    lda #O_XLO
    jsr spm_ptr
    lda (mosPTR2),y
    sta mosTMP
    lda #O_XHI
    jsr spm_ptr
    lda (mosPTR2),y
    sta mosTMP+1
    jsr s6_dec16
    lda #','
    jsr OSWRCH
    lda #O_Y
    jsr spm_ptr
    lda (mosPTR2),y
    jsr s6_dec8
    jsr OSNEWL
spl_next:
    inc fsSX
    lda fsSX
    cmp #32
    bcc spl_loop
    rts
; spl_hex: A as two hex digits
spl_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr splh_d
    pla
    and #15
splh_d:
    cmp #10
    bcc splh_n
    adc #'A'-'0'-10-1
splh_n:
    adc #'0'
    jmp OSWRCH

; ----------------------------------------------------------------------------
; spr_word (OSWORD &71)
;   Summary: sprites from programs without command parsing.
;   Function: block +0 sprite (0-31), +1 action: 0 hide, 1 show at
;            +2/+3 x, +4/+5 y (BBC), 2 shape +6, 3 colour +6, 4 read the
;            collisions into +6 (bit 0 another sprite, bit 1 the picture;
;            cleared).
;   Input:   mosPTR = the block.  Output: +6 for action 4.
;   Uses:    A, X, Y, fs*, mosTMP, mosPTR2.
spr_word:
    lda spr_page
    beq sw_rts                  ; (sprites off: nothing)
    ldy #0
    lda (mosPTR),y
    cmp #32
    bcs sw_rts
    sta fsSX
    iny
    lda (mosPTR),y
    beq sw_hide
    cmp #1
    beq sw_show
    cmp #2
    beq sw_shape
    cmp #3
    beq sw_colour
    cmp #4
    beq sw_coll
sw_rts:
    rts
sw_hide:
    lda #0
    ldx #$FE
    jmp sp_flag
sw_show:
    ldy #2
swh_copy:
    lda (mosPTR),y
    sta fsTMP-2,y
    iny
    cpy #6
    bcc swh_copy
    jsr sp_move
    lda #1
    ldx #$FF
    jmp sp_flag
sw_shape:
    ldy #6
    lda (mosPTR),y
    and #63
    ora #$80
    ldx #O_PTR
    jmp sp_set
sw_colour:
    ldy #6
    lda (mosPTR),y
    and #15
    tax
    lda sp_bbc2c64,x
    ldx #O_COL
    jmp sp_set
sw_coll:
    lda #O_COLL
    jsr spm_ptr
    lda spr_page
    sta mosPTR2+1
    php
    sei
    lda (mosPTR2),y
    tax
    lda #0
    sta (mosPTR2),y
    plp
    txa
    ldy #6
    sta (mosPTR),y
    rts

; sp_inval: a graphics mode's shape blocks emptied (the multiplexer
; copies again): after DEFINE and LOAD. Uses: A, Y, mosPTR2.
sp_inval:
    lda spr_page
    beq spv_rts
    sta mosPTR2+1
    lda #O_BLKSHP
    sta mosPTR2
    ldy #0
    lda #$FF
    php
    sei
    sta (mosPTR2),y
    iny
    sta (mosPTR2),y
    plp
spv_rts:
    rts

; ----------------------------------------------------------------------------
; sp_colours: COLOURS c1 c2: the multicolour pair, shared by every sprite
; (the VIC-II has one pair: $D025, $D026)
sp_colours:
    jsr s6_need
    lda mosNUM
    and #15
    tax
    lda sp_bbc2c64,x
    sta $D025
    jsr s6_skipsp
    cmp #','
    bne spc_2
    iny
spc_2:
    jsr s6_need
    jsr s6_end
    lda mosNUM
    and #15
    tax
    lda sp_bbc2c64,x
    sta $D026
    rts

; ----------------------------------------------------------------------------
; sp_load
;   Summary: LOAD s file: shapes from s on, from a file.
;   Function: reads up to 17 pages into REU_SCRATCH, then copies the
;            shapes (64 bytes each) to REU_SHAPES: a SpritePad file
;            ('SPD', versions 1-5: a 9, 16 or 20-byte header, the count in
;            byte 4 (V1, count - 1) or bytes 5-6 (V2-V5)), a
;            file with a 3-byte header (its length 64n + 3), or plain
;            64-byte shapes (the last may be 63 bytes).
;   Input:   mosPTR/Y = 's file'.
;   Output:  the shapes; the $E000 copy or the blocks renewed.
;   Uses:    A, X, Y, fs*, mosTMP, MOSBUF.
sp_load:
    jsr s6_hasreu
    bne spl_reu
    brk
    dta 254, 'Sprites need an REU', 0
spl_reu:
    jsr sp_byte64n
    pha                         ; the first shape
    jsr s6_name
    jsr s6_end
    farcall rx_openin, BANK_FS
    lda fsTMP+2                 ; size: at most the scratch area
    ora fsTMP+3
    bne spl_big
    lda fsTMP+1
    cmp #SCRATCH_PG
    bcc spl_size
spl_big:
    lda #0
    sta fsTMP
    lda #SCRATCH_PG
    sta fsTMP+1
spl_size:
    lda fsTMP
    pha
    lda fsTMP+1
    pha
    lda #REU_SHBANK
    ldy #>REU_SCRATCH
    ldx #SCRATCH_PG
    farcall rx_read, BANK_FS
    farcall rx_close, BANK_FS
    pla
    sta mosTMP+3                ; the size
    pla
    sta mosTMP+2
    pla
    sta mosTMP                  ; the shape to fill
    lda #0                      ; the first 7 bytes: the header?
    sta fsCNT
    sta fsCNT+1
    lda #7
    jsr spl_get
    ldx #0                      ; offset: 0, 3 or 9
    lda MOSBUF
    cmp #'S'
    bne spl_raw
    lda MOSBUF+1
    cmp #'P'
    bne spl_raw
    lda MOSBUF+2
    cmp #'D'
    bne spl_raw
    lda MOSBUF+3                ; the header's length by version
    ldx #9                      ; (SpritePad's help: V1 9 bytes, V2/V3
    cmp #1                      ; 16, V4/V5 20; the sprites follow it)
    beq spl_off
    ldx #16
    cmp #2
    bcc spl_badv
    cmp #4
    bcc spl_off
    ldx #20
    cmp #6
    bcc spl_off
spl_badv:
    brk
    dta 247, 'SPD version 1-5 only', 0
spl_raw:
    lda mosTMP+2
    and #63
    cmp #3
    bne spl_off
    ldx #3
spl_off:
    stx fsCNT
    lda mosTMP+2                ; count = (size - offset + 1) / 64
    sec
    sbc fsCNT
    sta mosTMP+2
    lda mosTMP+3
    sbc #0
    sta mosTMP+3
    bcc spl_none
    inc mosTMP+2
    bne spl_div
    inc mosTMP+3
spl_div:
    ldx #6
spl_div6:
    lsr mosTMP+3
    ror mosTMP+2
    dex
    bne spl_div6
    lda mosTMP+2
    sta mosTMP+1
    lda fsCNT                   ; SPD: its sprite count (tiles and
    cmp #9                      ; animations may follow the sprites)
    bcc spl_copy
    bne spl_v2
    ldx MOSBUF+4                ; V1: count - 1
    inx
    beq spl_copy                ; (256: the file decides)
    bne spl_cap
spl_v2:
    lda MOSBUF+6                ; V2-V5: 16 bits
    bne spl_copy                ; (256 or more: the file decides)
    ldx MOSBUF+5
spl_cap:
    cpx mosTMP+1
    bcs spl_copy
    stx mosTMP+1
spl_copy:
    lda mosTMP+1
    beq spl_done
    lda mosTMP
    cmp #64
    bcs spl_done
    lda #64                     ; the scratch -> MOSBUF -> its place
    jsr spl_get
    lda mosTMP
    sta fsSX
    jsr spd_reuaddr
    jsr spl_mosbuf
    lda #REU_TO_REU
    jsr rd_dma
    lda fsCNT
    clc
    adc #64
    sta fsCNT
    bcc spl_nx
    inc fsCNT+1
spl_nx:
    inc mosTMP
    dec mosTMP+1
    jmp spl_copy
spl_none:
spl_done:
    jsr sp_inval
    lda spr_page                ; the text screen: the $E000 copy
    beq spl_rts
    lda vtype
    bne spl_rts
    jmp sp_shapes
spl_rts:
    rts
; spl_get: A bytes from REU_SCRATCH + fsCNT to MOSBUF
spl_get:
    pha
    lda fsCNT
    sta fsTMP
    lda fsCNT+1
    clc
    adc #>REU_SCRATCH
    sta fsTMP+1
    lda #REU_SHBANK
    sta fsTMP+2
    jsr spl_mosbuf
    pla
    sta fsLEN
    lda #REU_TO_C64
    jmp rd_dma
; spl_mosbuf: fsADDR = MOSBUF, fsLEN = 64
spl_mosbuf:
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #64
    sta fsLEN
    lda #0
    sta fsLEN+1
    rts

; BBC colours 0-15 -> C64 colours (as COLOUR in the text screen)
sp_bbc2c64:
    dta 0, 2, 5, 7, 6, 4, 3, 1, 8, 9, 10, 11, 12, 13, 14, 15

wd_on       dta 'ON', 0
wd_off      dta 'OFF', 0
wd_shape    dta 'SHAPE', 0
wd_colour   dta 'COLOUR', 0
wd_size     dta 'SIZE', 0
wd_behind   dta 'BEHIND', 0
wd_front    dta 'FRONT', 0
wd_define   dta 'DEFINE', 0
wd_colours  dta 'COLOURS', 0
wd_load     dta 'LOAD', 0
wd_multi    dta 'MULTI', 0
    .endl
