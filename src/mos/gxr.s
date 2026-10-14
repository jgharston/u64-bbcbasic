; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- GXR software sprites: the store and the commands, bank 5
;
; The GXR's / BBC Master's sprite commands (docs/DESIGN_SPRITES.md 6):
; *SGET, *SCHOOSE, *SDELETE, *SNEW, *SRENUMBER, *SLOAD, *SMERGE, *SSAVE,
; *SSPACE, *SEDIT (later), VDU 23,27; and *SMASK (U64). Sprites live in
; the REU, one byte (the logical colour) per pixel, so they plot in every
; graphics mode; PLOT 232-239 is drawn by bank 3 (gxshape.s, bs_sprite).
; Real GXR sprite files are decoded on loading (their mode's screen
; bytes; the layout checked against the GXR sprite disc's files).
;
; REU bank GXR_BANK:
;   GXR_DESC  the selected sprite: data address (2), width, height, mask
;             ($FF: none), valid (bank 3 reads it for each plot)
;   GXR_CUR   its number ($FF: none);  GXR_END  the end of the data (2)
;   GXR_DIR   256 entries of 6: address (2), width, height, mask, used
;   GXR_DATA  the pixels, sprite after sprite, to $FFFF
;
; ----------------------------------------------------------------------------

GXR_BANK    = 1
GXR_DESC    = $4000
GXR_CUR     = $4006
GXR_END     = $4008
GXR_DIR     = $4100
GXR_DATA    = $4800
GXR_SCR     = $0A               ; REU bank for files (Upic's swap bank)

    .local gxr
    icl 'bankhelp.s'

; Variables in MOSBUF (RAM; this bank is ROM): pixels/bytes in $00-$BF,
; these in $E0-$EF (not $C0-$DA: the line editor's state)
GE          = MOSBUF+$E0        ; an entry: address (2), w, h, mask, used
GE_LO       = GE
GE_HI       = GE+1
GE_W        = GE+2
GE_H        = GE+3
GE_MASK     = GE+4
GE_USED     = GE+5
gv_n        = MOSBUF+$E6        ; the sprite number in hand
gv_m        = MOSBUF+$E7        ; a second number
gv_s        = MOSBUF+$E8        ; a size (2)
gv_a        = MOSBUF+$EA        ; an REU address (2)
gv_b        = MOSBUF+$EC        ; another (2)
gv_r        = MOSBUF+$EE        ; a counter
gv_t        = MOSBUF+$EF        ; scratch
gl_pp       = MOSBUF+$F0        ; *SLOAD of a GXR file: pixels per byte,
gl_mode     = MOSBUF+$F1        ; its mode, width in bytes, rows to go,
gl_wb       = MOSBUF+$F2        ; the byte in the row, the byte, a colour
gl_rows     = MOSBUF+$F3
gl_k        = MOSBUF+$F4
gl_v        = MOSBUF+$F5
gl_c        = MOSBUF+$F6
gl_fp       = MOSBUF+$F8        ; the file pointer (2; $F8-$FE: fnt46's
gl_ds       = MOSBUF+$FA        ; during a MODE change only), the record's
                                ; data start (2)

; ----------------------------------------------------------------------------
; gx_dma: fsADDR (C64) <-> GXR_BANK:fsTMP/+1, fsLEN bytes, command A
gx_dma:
    pha
    lda #GXR_BANK
    sta fsTMP+2
    pla
    jmp rd_dma

; gx_rdent / gx_wrent: directory entry gv_n <-> GE
gx_rdent:
    lda #REU_TO_C64
    bne gxe_go
gx_wrent:
    lda #REU_TO_REU
gxe_go:
    pha
    lda #<GE
    sta fsADDR
    lda #>GE
    sta fsADDR+1
    jsr gx_entaddr
    lda #6
    sta fsLEN
    lda #0
    sta fsLEN+1
    pla
    jmp gx_dma

; gx_entaddr: fsTMP = GXR_DIR + gv_n * 6 (n * 3, then * 2)
gx_entaddr:
    lda gv_n
    asl
    sta fsTMP
    lda #0
    rol
    sta fsTMP+1                 ; n * 2
    lda fsTMP
    clc
    adc gv_n
    sta fsTMP
    lda fsTMP+1
    adc #0
    sta fsTMP+1                 ; n * 3
    asl fsTMP
    rol fsTMP+1                 ; n * 6
    lda fsTMP
    clc
    adc #<GXR_DIR
    sta fsTMP
    lda fsTMP+1
    adc #>GXR_DIR
    sta fsTMP+1
    rts

; gx_state: the state (GXR_CUR: the current sprite, a spare byte,
; GXR_END: the data end) <-> gx_stbuf; command A
gx_state:
    pha
    lda #<gx_stbuf
    sta fsADDR
    lda #>gx_stbuf
    sta fsADDR+1
    lda #<GXR_CUR
    sta fsTMP
    lda #>GXR_CUR
    sta fsTMP+1
    lda #4
    sta fsLEN
    lda #0
    sta fsLEN+1
    pla
    jmp gx_dma
gx_stbuf    = MOSBUF+$DC        ; current, (spare), end (2): $DC-$DF

; ----------------------------------------------------------------------------
; gxr_init (cold start, with an REU): no sprites, none selected
;   Uses: A, X, Y, fs*, MOSBUF.
gxr_init:
    lda #0
    ldx #$BF
gi_zero:
    sta MOSBUF,x
    dex
    cpx #$FF
    bne gi_zero
    lda #<GXR_DIR               ; the directory: 6 * 256 = $600, 8 x $C0
    sta gv_a
    lda #>GXR_DIR
    sta gv_a+1
    lda #8
    sta gv_r
gi_dir:
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gv_a
    sta fsTMP
    lda gv_a+1
    sta fsTMP+1
    lda #$C0
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jsr gx_dma
    lda gv_a
    clc
    adc #$C0
    sta gv_a
    bcc gi_n
    inc gv_a+1
gi_n:
    dec gv_r
    bne gi_dir
    lda #<GXR_DESC              ; descriptor: not valid (6 zeros)
    sta fsTMP
    lda #>GXR_DESC
    sta fsTMP+1
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda #6
    sta fsLEN
    lda #REU_TO_REU
    jsr gx_dma
    lda #$FF                    ; none selected, the data empty
    sta gx_stbuf
    lda #<GXR_DATA
    sta gx_stbuf+2
    lda #>GXR_DATA
    sta gx_stbuf+3
    lda #REU_TO_REU
    jmp gx_state

; gxr_cold (cold start, with an REU): the VIC-II shapes cleared too (the
; REU holds whatever it had at power-on), then gxr_init
gxr_cold:
    lda #0
    ldx #$BF
gc_zero:
    sta MOSBUF,x
    dex
    cpx #$FF
    bne gc_zero
    lda #<$1000                 ; the VIC-II shapes (REU_SHAPES, 64 x
    sta gv_a                    ; 64 = 4K = 21 x $C0 + $40): all 0 at the
    lda #>$1000                 ; start (the REU holds whatever it had)
    sta gv_a+1
    lda #22
    sta gv_r
gi_shp:
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gv_a
    sta fsTMP
    lda gv_a+1
    sta fsTMP+1
    lda #$C0
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jsr gx_dma
    lda gv_a
    clc
    adc #$C0
    sta gv_a
    bcc gi_sn
    inc gv_a+1
gi_sn:
    dec gv_r
    bne gi_shp
    jmp gxr_init

; gx_need: an REU ("Sprites need an REU")
gx_need:
    jsr s6_hasreu
    beq gxn_no
    rts
gxn_no:
    brk
    dta 254, 'Sprites need an REU', 0

; gx_num: a sprite number 0-255 -> gv_n
gx_num:
    jsr s6_need
    lda mosNUM+1
    beq gxm_ok
    brk
    dta 252, 'Bad sprite number', 0
gxm_ok:
    lda mosNUM
    sta gv_n
    rts

; ----------------------------------------------------------------------------
; gx_select: sprite gv_n becomes the selected one ("Sprite doesn't exist")
gx_select:
    jsr gx_rdent
    lda GE_USED
    bne gs_ok
    brk
    dta 134, 'Sprite doesn''t exist', 0
gs_ok:
    jsr gx_desc
    lda #REU_TO_C64
    jsr gx_state
    lda gv_n
    sta gx_stbuf
    lda #REU_TO_REU
    jmp gx_state
; gx_desc: GE (used) -> GXR_DESC
gx_desc:
    lda #<GE
    sta fsADDR
    lda #>GE
    sta fsADDR+1
    lda #<GXR_DESC
    sta fsTMP
    lda #>GXR_DESC
    sta fsTMP+1
    lda #6
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jmp gx_dma

; gx_reselect: after a change: the current sprite's descriptor again
; (or none if it is gone)
gx_reselect:
    lda gv_n                    ; (gv_n kept: callers go on with it)
    pha
    jsr grs_go
    pla
    sta gv_n
    rts
grs_go:
    lda #REU_TO_C64
    jsr gx_state
    lda gx_stbuf
    cmp #$FF
    beq gr_none
    sta gv_n
    jsr gx_rdent
    lda GE_USED
    bne gr_desc
gr_none:
    lda #0                      ; not valid
    sta GE_USED
gr_desc:
    jmp gx_desc

; gx_size: gv_s = GE_W * GE_H
gx_size:
    lda #0
    sta gv_s
    sta gv_s+1
    ldx GE_H
    beq gsz_rts
gsz_l:
    lda gv_s
    clc
    adc GE_W
    sta gv_s
    bcc gsz_n
    inc gv_s+1
gsz_n:
    dex
    bne gsz_l
gsz_rts:
    rts

; ----------------------------------------------------------------------------
; gx_delete: sprite gv_n out, the data after it moved down, the
; directory's later addresses lowered
gx_delete:
    jsr gx_rdent
    lda GE_USED
    bne gd_go
    rts
gd_go:
    jsr gx_size
    lda GE_LO                   ; gv_a = destination, gv_b = source
    sta gv_a
    clc
    adc gv_s
    sta gv_b
    lda GE_HI
    sta gv_a+1
    adc gv_s+1
    sta gv_b+1
    lda #0                      ; the entry unused
    sta GE_USED
    jsr gx_wrent
    lda gv_n
    pha
    lda #REU_TO_C64
    jsr gx_state
gd_move:                        ; while source < end: 128 bytes at a time
    lda gv_b
    cmp gx_stbuf+2
    lda gv_b+1
    sbc gx_stbuf+3
    bcs gd_moved
    lda gx_stbuf+2              ; len = min(128, end - source)
    sec
    sbc gv_b
    sta fsLEN
    lda gx_stbuf+3
    sbc gv_b+1
    bne gd_128
    lda fsLEN
    cmp #128
    bcc gd_len
gd_128:
    lda #128
    sta fsLEN
gd_len:
    lda #0
    sta fsLEN+1
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gv_b
    sta fsTMP
    lda gv_b+1
    sta fsTMP+1
    lda #REU_TO_C64
    jsr gx_dma
    lda gv_a
    sta fsTMP
    lda gv_a+1
    sta fsTMP+1
    lda #REU_TO_REU
    jsr gx_dma
    lda fsLEN
    clc
    adc gv_a
    sta gv_a
    bcc gd_a
    inc gv_a+1
gd_a:
    lda fsLEN
    clc
    adc gv_b
    sta gv_b
    bcc gd_move
    inc gv_b+1
    bne gd_move
gd_moved:
    lda gx_stbuf+2              ; end -= size
    sec
    sbc gv_s
    sta gx_stbuf+2
    lda gx_stbuf+3
    sbc gv_s+1
    sta gx_stbuf+3
    lda #REU_TO_REU
    jsr gx_state
    lda GE_LO                   ; addresses above the gap: - size
    sta gv_b
    lda GE_HI
    sta gv_b+1
    lda #0
    sta gv_n
gd_fix:
    jsr gx_rdent
    lda GE_USED
    beq gd_next
    lda GE_LO
    cmp gv_b
    lda GE_HI
    sbc gv_b+1
    bcc gd_next
    lda GE_LO
    sec
    sbc gv_s
    sta GE_LO
    lda GE_HI
    sbc gv_s+1
    sta GE_HI
    jsr gx_wrent
gd_next:
    inc gv_n
    bne gd_fix
    pla
    sta gv_n
    jmp gx_reselect

; gx_alloc: a new sprite gv_n of GE_W x GE_H (mask GE_MASK) at the end
; of the data: "No room for sprite"; replaces an old one of that number.
; Output: GE_LO/HI its address (the caller writes the pixels there).
gx_alloc:
    lda GE_W
    pha
    lda GE_H
    pha
    lda GE_MASK
    pha
    jsr gx_delete
    pla
    sta GE_MASK
    pla
    sta GE_H
    pla
    sta GE_W
    jsr gx_size
    lda #REU_TO_C64
    jsr gx_state
    lda gx_stbuf+2              ; end + size <= $10000?
    clc
    adc gv_s
    lda gx_stbuf+3
    adc gv_s+1
    bcc ga_room
    bne ga_full
    lda gx_stbuf+2              ; (exactly $10000: fits)
    clc
    adc gv_s
    beq ga_room
ga_full:
    brk
    dta 130, 'No room for sprite', 0
ga_room:
    lda gx_stbuf+2
    sta GE_LO
    clc
    adc gv_s
    sta gx_stbuf+2
    lda gx_stbuf+3
    sta GE_HI
    adc gv_s+1
    sta gx_stbuf+3
    lda #REU_TO_REU
    jsr gx_state
    lda #1
    sta GE_USED
    jmp gx_wrent

; ----------------------------------------------------------------------------
; cmd_schoose: *SCHOOSE n
cmd_schoose:
    jsr gx_need
    jsr gx_num
    jsr s6_end
    jmp gx_select

; cmd_sdelete: *SDELETE n
cmd_sdelete:
    jsr gx_need
    jsr gx_num
    jsr s6_end
    jmp gx_delete

; cmd_snew: *SNEW
cmd_snew:
    jsr gx_need
    jsr s6_end
    jmp gxr_init

; cmd_sspace: *SSPACE n: accepted (the sprites live in the REU: 46K)
cmd_sspace:
    jsr s6_need
    jmp s6_end

; ----------------------------------------------------------------------------
; gxr_edload / gxr_edstore (for the sprite editor, sedit.s, bank 7)
;   Summary: sprite gv_n into the editor's buffer (REU GXR_SCR, a row every
;            256 bytes: pixel x,y at y * 256 + x), and back.
;   Function: edload: GE_W/GE_H its size (a missing sprite: 16 x 16, all
;            colour 0); edstore: a new sprite gv_n of GE_W x GE_H (its mask
;            kept), the rows copied in, selected. Rows go through MOSBUF in
;            64-byte pieces (the editor's own variables are at MOSBUF+$80).
;   Input:   gv_n; edstore: GE_W, GE_H.  Output: edload: GE_W, GE_H.
;   Uses:    A, X, Y, fs*, GE, gv_*, MOSBUF+$00-$3F.
gxr_edload:
    jsr gx_rdent
    lda GE_USED
    bne gel_have
    lda #16                     ; new: 16 x 16, cleared
    sta GE_W
    sta GE_H
    jmp ged_clear
gel_have:
    jsr ged_clear               ; (columns beyond the width: 0)
    lda GE_LO
    sta gv_s
    lda GE_HI
    sta gv_s+1
    lda #0                      ; buffer row address (low 0, high = row)
    sta gv_b
    sta gv_b+1
    lda GE_H
    sta gv_r
gel_row:
    lda #0
    sta gv_t                    ; x of the piece
gel_piece:
    jsr ged_len                 ; fsLEN = min(64, w - x)
    lda gv_s                    ; sprite row -> MOSBUF
    sta fsTMP
    lda gv_s+1
    sta fsTMP+1
    jsr ged_mosbuf
    lda #REU_TO_C64
    jsr gx_dma
    lda gv_t                    ; MOSBUF -> buffer row, column gv_t
    sta fsTMP
    lda gv_b+1
    sta fsTMP+1
    lda #GXR_SCR
    sta fsTMP+2
    jsr ged_mosbuf
    lda #REU_TO_REU
    jsr rd_dma
    lda fsLEN
    clc
    adc gv_s
    sta gv_s
    bcc gel_s
    inc gv_s+1
gel_s:
    lda gv_t
    clc
    adc fsLEN
    sta gv_t
    cmp GE_W
    bcc gel_piece
    inc gv_b+1
    dec gv_r
    bne gel_row
    rts

gxr_edstore:
    lda #$FF                    ; the mask kept (a new sprite: none)
    sta GE_MASK
    lda GE_W
    pha
    lda GE_H
    pha
    jsr gx_rdent
    lda GE_USED
    beq ges_nomask
    lda GE_MASK
    sta gv_t
    jmp ges_m
ges_nomask:
    lda #$FF
    sta gv_t
ges_m:
    pla
    sta GE_H
    pla
    sta GE_W
    lda gv_t
    sta GE_MASK
    jsr gx_alloc
    lda GE_LO
    sta gv_s
    lda GE_HI
    sta gv_s+1
    lda #0
    sta gv_b+1
    lda GE_H
    sta gv_r
ges_row:
    lda #0
    sta gv_t
ges_piece:
    jsr ged_len
    lda gv_t                    ; buffer -> MOSBUF
    sta fsTMP
    lda gv_b+1
    sta fsTMP+1
    lda #GXR_SCR
    sta fsTMP+2
    jsr ged_mosbuf
    lda #REU_TO_C64
    jsr rd_dma
    lda gv_s                    ; MOSBUF -> the sprite
    sta fsTMP
    lda gv_s+1
    sta fsTMP+1
    jsr ged_mosbuf
    lda #REU_TO_REU
    jsr gx_dma
    lda fsLEN
    clc
    adc gv_s
    sta gv_s
    bcc ges_s
    inc gv_s+1
ges_s:
    lda gv_t
    clc
    adc fsLEN
    sta gv_t
    cmp GE_W
    bcc ges_piece
    inc gv_b+1
    dec gv_r
    bne ges_row
    jmp gx_select

; ged_len: fsLEN = min(64, GE_W - gv_t)
ged_len:
    lda GE_W
    sec
    sbc gv_t
    cmp #64
    bcc gln_ok
    lda #64
gln_ok:
    sta fsLEN
    lda #0
    sta fsLEN+1
    rts
; ged_mosbuf: fsADDR = MOSBUF (fsLEN kept)
ged_mosbuf:
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    rts
; ged_clear: the buffer all 0 (64K, by DMA from one 0 byte)
ged_clear:
    lda #0
    sta gv_t
    php
    sei
    lda #<gv_t
    sta REU_C64
    lda #>gv_t
    sta REU_C64+1
    lda #0
    sta REU_ADDR
    sta REU_ADDR+1
    sta REU_LEN
    sta REU_LEN+1               ; (0 = 65536)
    lda #GXR_SCR
    sta REU_BANK
    lda #$80
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    lda #0
    sta REU_CTRL
    plp
    rts

; cmd_srenumber: *SRENUMBER n,m: sprite n becomes m (an old m goes)
cmd_srenumber:
    jsr gx_need
    jsr gx_num
    lda gv_n
    sta gv_m                    ; n
    jsr s6_skipsp
    cmp #','
    beq csr_c
    brk
    dta 135, 'Missing comma', 0
csr_c:
    iny
    jsr gx_num                  ; gv_n = m
    jsr s6_end
    lda gv_n
    cmp gv_m
    bne csr_ne
    brk
    dta 136, 'Sprite numbers are equal', 0
csr_ne:
    lda gv_n
    pha                         ; m
    lda gv_m
    sta gv_n
    jsr gx_rdent                ; n must exist
    lda GE_USED
    bne csr_ex
    pla
    brk
    dta 134, 'Sprite doesn''t exist', 0
csr_ex:
    pla
    sta gv_n
    jsr gx_delete               ; m out (moves data: n's entry read after)
    lda gv_n
    pha
    lda gv_m
    sta gv_n
    jsr gx_rdent                ; n's entry, unused now
    lda #0
    sta GE_USED
    jsr gx_wrent
    pla
    sta gv_n                    ; written as m
    lda #1
    sta GE_USED
    jsr gx_wrent
    lda #REU_TO_C64             ; the current sprite: n -> m
    jsr gx_state
    lda gx_stbuf
    cmp gv_m
    bne csr_done
    lda gv_n
    sta gx_stbuf
    lda #REU_TO_REU
    jsr gx_state
csr_done:
    jmp gx_reselect

; cmd_smask: *SMASK n c | OFF: colour c of sprite n left out (U64)
cmd_smask:
    jsr gx_need
    jsr gx_num
    jsr gx_rdent
    lda GE_USED
    bne csm_ex
    brk
    dta 134, 'Sprite doesn''t exist', 0
csm_ex:
    lda #<wd_off
    ldx #>wd_off
    jsr s6_word
    lda #$FF
    bcs csm_set
    jsr s6_need
    lda mosNUM
    and #15
csm_set:
    sta GE_MASK
    jsr s6_end
    jsr gx_wrent
    jmp gx_reselect

; ----------------------------------------------------------------------------
; cmd_sget: *SGET n. gxr_vdu23: VDU 23,27,0,n (choose) / 1,n (get), from
; bank 3's bk_vdu23
cmd_sget:
    jsr gx_need
    jsr gx_num
    jsr s6_end
    jmp gx_get
gxr_vdu23:
    jsr gx_need
    lda vdubuf+2
    sta gv_n
    lda vdubuf+1
    bne gv_n0
    jmp gx_select
gv_n0:
    cmp #1
    beq gx_get
    rts

; gx_get
;   Summary: the rectangle between the last two graphics points becomes
;            sprite gv_n (GXR *SGET), selected.
;   Function: both corners to device pixels (the engine), ordered; up to
;            192 x 255 pixels ("Sprite too big"); each pixel's logical
;            colour through the engine's POINT (0 outside the window),
;            a row at a time into MOSBUF, then into the REU.
gx_get:
    lda vtype                   ; a graphics mode
    cmp #1
    beq gg_gfx
    brk
    dta 254, 'Sprites need a graphics MODE', 0
gg_gfx:
    lda gpx                     ; the previous point
    sta pk_x
    lda gpx+1
    sta pk_x+1
    lda gpy
    sta pk_y
    lda gpy+1
    sta pk_y+1
    ldx #GX_TODEV
    jsr gx_call
    lda ex
    pha
    lda ex+1
    pha
    lda ey
    pha
    lda gcx                     ; the current point
    sta pk_x
    lda gcx+1
    sta pk_x+1
    lda gcy
    sta pk_y
    lda gcy+1
    sta pk_y+1
    ldx #GX_TODEV
    jsr gx_call
    pla                         ; y: top = smaller device y
    cmp ey
    bcc gg_y
    ldx ey
    sta ey
    txa
gg_y:
    sta gv_b                    ; top
    lda ey
    sec
    sbc gv_b
    sta GE_H                    ; height - 1
    pla                         ; x: left = smaller
    sta gv_a+1
    pla
    sta gv_a
    lda ex
    cmp gv_a
    lda ex+1
    sbc gv_a+1
    bcs gg_x
    lda ex                      ; swap
    ldx gv_a
    stx ex
    sta gv_a
    lda ex+1
    ldx gv_a+1
    stx ex+1
    sta gv_a+1
gg_x:
    lda ex                      ; width - 1 = right - left
    sec
    sbc gv_a
    sta GE_W
    lda ex+1
    sbc gv_a+1
    bne gg_big
    lda GE_W
    cmp #192
    bcs gg_big
    lda GE_H
    cmp #255
    bcc gg_ok
gg_big:
    brk
    dta 130, 'Sprite too big (192 x 255)', 0
gg_ok:
    inc GE_W
    inc GE_H
    lda #$FF
    sta GE_MASK
    ldx #3                      ; (gv_a, gv_b: the box; gx_delete uses
gg_sv:                          ; them when an old sprite n goes)
    lda gv_a,x
    pha
    dex
    bpl gg_sv
    jsr gx_alloc                ; GE_LO/HI: where it goes
    ldx #0
gg_rs:
    pla
    sta gv_a,x
    inx
    cpx #4
    bcc gg_rs
    lda GE_LO
    sta gv_s                    ; (the REU pointer)
    lda GE_HI
    sta gv_s+1
    lda gv_b                    ; ey = top
    sta ey
    lda #0
    sta ey+1
    lda GE_H
    sta gv_r
gg_row:
    lda gv_a
    sta ex
    lda gv_a+1
    sta ex+1
    ldy #0
gg_px:
    sty gv_t
    ldx #GX_POINTDEV
    jsr gx_call
    ldy gv_t
    lda gx_res
    cmp #$FF
    bne gg_in
    lda #0
gg_in:
    sta MOSBUF,y
    inc ex
    bne gg_ex
    inc ex+1
gg_ex:
    iny
    cpy GE_W
    bcc gg_px
    lda #<MOSBUF                ; the row to the REU
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gv_s
    sta fsTMP
    lda gv_s+1
    sta fsTMP+1
    lda GE_W
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jsr gx_dma
    lda gv_s
    clc
    adc GE_W
    sta gv_s
    bcc gg_s
    inc gv_s+1
gg_s:
    inc ey
    dec gv_r
    bne gg_row
    jmp gx_select

; ----------------------------------------------------------------------------
; cmd_sload / cmd_smerge: *SLOAD file (all replaced) / *SMERGE file
; (added; same numbers replaced). The file is read into REU bank GXR_SCR,
; then each sprite stored: our format ("U64SPR", 1, count; per sprite
; number, width, height, mask, the pixels) or a GXR file (length (2),
; count; per sprite width in bytes - 1, height - 1, data size (2), mode,
; number, the mode's screen bytes, rows top to bottom, each right to left)
cmd_sload:
    jsr gx_need
    jsr s6_name
    jsr s6_end
    jsr gs_namesave
    jsr gxr_init
    jsr gs_namerest
    jmp gl_read
cmd_smerge:
    jsr gx_need
    jsr s6_name
    jsr s6_end
gl_read:
    farcall rx_openin, BANK_FS
    lda #GXR_SCR
    ldy #0
    ldx #255
    farcall rx_read, BANK_FS
    farcall rx_close, BANK_FS
    lda #0                      ; the header: 7 bytes
    sta gl_fp
    sta gl_fp+1
    ldx #7
    jsr gl_bytes
    lda MOSBUF                  ; 'U64SPR'?
    cmp #'U'
    bne gl_gxr
    lda MOSBUF+1
    cmp #'6'
    bne gl_gxr
    lda MOSBUF+6
    cmp #1
    bne gl_bad
    ldx #1                      ; the count
    jsr gl_bytes
    lda MOSBUF
    sta gl_k
    beq gl_done
gl_own:
    ldx #4                      ; number, width, height, mask
    jsr gl_bytes
    lda MOSBUF
    sta gv_n
    lda MOSBUF+1
    sta GE_W
    lda MOSBUF+2
    sta GE_H
    lda MOSBUF+3
    sta GE_MASK
    jsr gx_alloc
    jsr gl_copy                 ; w * h bytes from the file to GE_LO/HI
    dec gl_k
    bne gl_own
gl_done:
    rts
gl_bad:
    brk
    dta 214, 'Not a sprite file', 0

gl_gxr:
    lda MOSBUF+2                ; GXR: the count, records from offset 3
    sta gl_k
    beq gl_done
    lda #3
    sta gl_fp
    lda #0
    sta gl_fp+1
gl_rec:
    ldx #6
    jsr gl_bytes
    lda gl_fp                   ; the data starts here
    sta gl_ds
    lda gl_fp+1
    sta gl_ds+1
    lda MOSBUF+2                ; the next record: after the data
    clc
    adc gl_fp
    sta gl_fp
    lda MOSBUF+3
    adc gl_fp+1
    sta gl_fp+1
    lda MOSBUF+5
    sta gv_n
    lda MOSBUF+4                ; pixels per byte by the mode
    and #7
    sta gl_mode
    tax
    lda gl_ppb,x
    beq gl_bad
    sta gl_pp
    lda MOSBUF                  ; width in bytes, height
    clc
    adc #1
    sta gl_wb
    lda MOSBUF+1
    clc
    adc #1
    sta GE_H
    lda #0                      ; pixels wide = bytes * ppb (<= 192)
    ldx gl_pp
gl_w:
    clc
    adc gl_wb
    bcs gl_bigj
    dex
    bne gl_w
    cmp #193
    bcc gl_wok
gl_bigj:
    jmp gl_big
gl_wok:
    sta GE_W
    lda #$FF
    sta GE_MASK
    jsr gx_alloc
    lda GE_LO
    sta gv_s
    lda GE_HI
    sta gv_s+1
    lda GE_H
    sta gl_rows
gl_row:                         ; a row: decode from its leftmost byte,
    ldy #0                      ; which the file holds last
    lda gl_wb
    sta gl_c                    ; (bytes to go)
gl_byte:
    dec gl_c                    ; file byte gl_ds + gl_c (right to left)
    lda gl_ds
    clc
    adc gl_c
    sta fsTMP
    lda gl_ds+1
    adc #0
    sta fsTMP+1
    lda #GXR_SCR
    sta fsTMP+2
    lda #<gl_v
    sta fsADDR
    lda #>gl_v
    sta fsADDR+1
    lda #1
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_C64
    jsr rd_dma
    jsr gl_decode               ; its pixels to MOSBUF+Y..
    lda gl_c
    bne gl_byte
    lda gl_ds                   ; the next row of the file
    clc
    adc gl_wb
    sta gl_ds
    bcc gl_dsn
    inc gl_ds+1
gl_dsn:
    lda #<MOSBUF                ; the row to the REU
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gv_s
    sta fsTMP
    lda gv_s+1
    sta fsTMP+1
    lda GE_W
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jsr gx_dma
    lda gv_s
    clc
    adc GE_W
    sta gv_s
    bcc gl_s
    inc gv_s+1
gl_s:
    dec gl_rows
    beq gl_rowsd
    jmp gl_row
gl_rowsd:
    dec gl_k
    beq gl_end
    jmp gl_rec
gl_end:
    rts
gl_big:
    brk
    dta 130, 'Sprite too big (192 x 255)', 0

; gl_decode: the GXR screen byte gl_v (mode gl_mode) as pixels at
; MOSBUF+Y (Y counts on). MODE 0/4: bit 7 the leftmost; 1/5: pixel i =
; bits 7-i (high) and 3-i; 2: pixel i = bits 7-i, 5-i, 3-i, 1-i.
gl_decode:
    lda gl_pp
    cmp #8
    beq gld_1
    cmp #4
    beq gld_2
    ldx #0                      ; 2 pixels of 4 bits
gld_4:
    lda #0
    sta MOSBUF+$F7
    lda gl_v
    and gl_m4a,x
    beq gld_4b
    lda #8
    sta MOSBUF+$F7
gld_4b:
    lda gl_v
    and gl_m4b,x
    beq gld_4c
    lda #4
    ora MOSBUF+$F7
    sta MOSBUF+$F7
gld_4c:
    lda gl_v
    and gl_m4c,x
    beq gld_4d
    lda #2
    ora MOSBUF+$F7
    sta MOSBUF+$F7
gld_4d:
    lda gl_v
    and gl_m4d,x
    beq gld_4e
    lda #1
    ora MOSBUF+$F7
    sta MOSBUF+$F7
gld_4e:
    lda MOSBUF+$F7
    sta MOSBUF,y
    iny
    inx
    cpx #2
    bcc gld_4
    rts
gld_1:                          ; 8 pixels of 1 bit
    ldx #8
gld_1l:
    lda #0
    asl gl_v
    rol
    sta MOSBUF,y
    iny
    dex
    bne gld_1l
    rts
gld_2:                          ; 4 pixels of 2 bits: bits 7-i and 3-i
    ldx #0
gld_2l:
    lda #0
    sta MOSBUF+$F7
    lda gl_v
    and gl_bit,x                ; bit 7-i: the high bit
    beq gld_2a
    lda #2
    sta MOSBUF+$F7
gld_2a:
    lda gl_v
    and gl_bit+4,x              ; bit 3-i: the low bit
    beq gld_2b
    inc MOSBUF+$F7
gld_2b:
    lda MOSBUF+$F7
    sta MOSBUF,y
    iny
    inx
    cpx #4
    bcc gld_2l
    rts

gl_bit      dta $80, $40, $20, $10, $08, $04, $02, $01
gl_m4a      dta $80, $40        ; MODE 2: pixel 0 / 1, colour bit 3
gl_m4b      dta $20, $10        ; bit 2
gl_m4c      dta $08, $04        ; bit 1
gl_m4d      dta $02, $01        ; bit 0
gl_ppb      dta 8, 4, 2, 0, 8, 4, 0, 0  ; pixels per byte, MODE 0-7

; gl_bytes: X bytes of the file (REU GXR_SCR:gl_fp) to MOSBUF, gl_fp on
gl_bytes:
    stx fsLEN
    lda #0
    sta fsLEN+1
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gl_fp
    sta fsTMP
    lda gl_fp+1
    sta fsTMP+1
    lda #GXR_SCR
    sta fsTMP+2
    txa
    clc
    adc gl_fp
    sta gl_fp
    bcc glb_n
    inc gl_fp+1
glb_n:
    lda #REU_TO_C64
    jmp rd_dma

; gl_copy: GE_W x GE_H bytes from the file (gl_fp on) to GE_LO/HI, a row
; at a time through MOSBUF
gl_copy:
    lda GE_LO
    sta gv_s
    lda GE_HI
    sta gv_s+1
    lda GE_H
    sta gl_rows
glc_row:
    ldx GE_W
    jsr gl_bytes
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gv_s
    sta fsTMP
    lda gv_s+1
    sta fsTMP+1
    lda GE_W
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_REU
    jsr gx_dma
    lda gv_s
    clc
    adc GE_W
    sta gv_s
    bcc glc_s
    inc gv_s+1
glc_s:
    dec gl_rows
    bne glc_row
    rts

; ----------------------------------------------------------------------------
; cmd_ssave: *SSAVE file: every sprite in our format ("U64SPR", 1, count;
; per sprite number, width, height, mask, the pixels), put together in REU
; bank GXR_SCR and written in whole pages (*SLOAD reads by the count)
cmd_ssave:
    jsr gx_need
    jsr s6_name
    jsr s6_end
    jsr gs_namesave
    lda #0                      ; count the sprites
    sta gl_k
    sta gv_n
css_cnt:
    jsr gx_rdent
    lda GE_USED
    beq css_cn
    inc gl_k
css_cn:
    inc gv_n
    bne css_cnt
    lda gl_k
    bne css_some
    brk
    dta 131, 'No sprites', 0
css_some:
    ldx #6                      ; the header
css_h:
    lda css_magic,x
    sta MOSBUF,x
    dex
    bpl css_h
    lda gl_k
    sta MOSBUF+7
    lda #0
    sta gl_fp
    sta gl_fp+1
    ldx #8
    jsr gs_put
css_one:                        ; each sprite (gv_n from 0 again)
    jsr gx_rdent
    lda GE_USED
    beq css_next
    lda gv_n
    sta MOSBUF
    lda GE_W
    sta MOSBUF+1
    lda GE_H
    sta MOSBUF+2
    lda GE_MASK
    sta MOSBUF+3
    ldx #4
    jsr gs_put
    lda GE_LO                   ; its pixels, a row at a time
    sta gv_s
    lda GE_HI
    sta gv_s+1
    lda GE_H
    sta gl_rows
css_row:
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gv_s
    sta fsTMP
    lda gv_s+1
    sta fsTMP+1
    lda GE_W
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_C64
    jsr gx_dma
    ldx GE_W
    jsr gs_put
    lda gv_s
    clc
    adc GE_W
    sta gv_s
    bcc css_s
    inc gv_s+1
css_s:
    dec gl_rows
    bne css_row
css_next:
    inc gv_n
    bne css_one
    jsr gs_namerest
    farcall rx_create, BANK_FS  ; the pages that hold it
    lda gl_fp
    cmp #1
    lda gl_fp+1
    adc #0
    tax
    lda #GXR_SCR
    ldy #0
    farcall rx_write, BANK_FS
    farcall rx_close, BANK_FS
    rts
css_magic   dta 'U64SPR', 1

; gs_namesave / gs_namerest: the file name (s6_name: fsPTR, fsLEN) kept
; at gs_nm meanwhile (the DMAs use fsLEN)
gs_namesave:
    lda fsPTR
    sta gs_nm
    lda fsPTR+1
    sta gs_nm+1
    lda fsLEN
    sta gs_nm+2
    lda fsLEN+1
    sta gs_nm+3
    rts
gs_namerest:
    lda gs_nm
    sta fsPTR
    lda gs_nm+1
    sta fsPTR+1
    lda gs_nm+2
    sta fsLEN
    lda gs_nm+3
    sta fsLEN+1
    rts
gs_nm       = MOSBUF+$FC        ; (4: past gl_ds)

; gs_put: X bytes from MOSBUF to the file being made (GXR_SCR:gl_fp)
gs_put:
    stx fsLEN
    lda #0
    sta fsLEN+1
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    lda gl_fp
    sta fsTMP
    lda gl_fp+1
    sta fsTMP+1
    lda #GXR_SCR
    sta fsTMP+2
    txa
    clc
    adc gl_fp
    sta gl_fp
    bcc gsp_n
    inc gl_fp+1
gsp_n:
    lda #REU_TO_REU
    jmp rd_dma

wd_off      dta 'OFF', 0
    .endl
