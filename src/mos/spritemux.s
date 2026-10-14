; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the sprite multiplexer (RAM image)
;
; Assembled twice into bank 5 (sprite.s): for $7B00 (below HIMEM &8000)
; and for $7700 (below MODE 7's &7C00). *SPRITE ON copies the right one
; below the mode's HIMEM and lowers HIMEM by its 5 pages. Everything the
; interrupt needs is here, in RAM: tables for 32 virtual sprites, their
; order by Y, and the raster interrupt that gives the 8 hardware sprites
; to the next virtual ones down the screen (docs/DESIGN_SPRITES.md 2).
;
; Interrupt safety: only absolute addresses here, no zero page.
;
; ----------------------------------------------------------------------------

SPR_N       = 32
FRAME_LINE  = 251               ; the frame interrupt (bottom border)
SCR_PTRS    = $C3F8             ; sprite pointers (screen matrix $C000)

.macro mx_flag reg, mask
    lda :reg
    and mx_nbit,x
    sta mx_tmp
    lda sflg,y
    and #:mask
    beq *+5
    lda mx_bit,x
    ora mx_tmp
    sta :reg
.endm

; Variables first (small offsets for sprite.s), then the tables
mx_next     dta 0               ; next position in sorder to place
mx_n        dta 0               ; virtual sprites shown this frame
mx_oldvec   dta 0, 0            ; the interrupt vector before ours
mx_bit      dta 1, 2, 4, 8, 16, 32, 64, 128
mx_nbit     dta $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F

; The tables (sprite.s writes them with interrupts off; all but sorder
; and skey below offset 256)
sx_lo       :SPR_N dta 0
sx_hi       :SPR_N dta 0        ; VIC X bit 8 (0/1)
sy          :SPR_N dta 0        ; VIC Y of the top line
sptr        :SPR_N dta 0        ; sprite pointer
scol        :SPR_N dta 0        ; colour (VIC colour)
sflg        :SPR_N dta 0        ; bit 0 shown, 1 x2 wide, 2 x2 high,
                                ; 3 behind, 4 multicolour
scoll       :SPR_N dta 0        ; collisions since read: bit 0 sprite,
                                ; bit 1 picture
sorder      :SPR_N dta 0        ; indices by Y (kept from frame to frame)
skey        :SPR_N dta 0        ; sort key: Y, or 255 when hidden
hwown       :8 dta 0            ; hardware sprite s shows virtual hwown[s]
hwend       :8 dta 0            ; ... until (the line after) hwend[s]

; ----------------------------------------------------------------------------
; mx_irq ($0314 while sprites are on)
;   Summary: raster interrupts: the frame (sort, first 8) and the reuse of
;            the hardware sprites; every other interrupt goes on to the
;            vector there was before (CIA: irq_main; MODE 7: tt_irq).
;   Input:   A, X, Y saved by the KERNAL's IRQ entry.
;   Output:  RTI through the KERNAL's exit ($EA81).
;   Uses:    A, X, Y; only the tables above.
mx_irq:
    lda $D019
    and #1
    bne mx_raster
    jmp (mx_oldvec)
mx_raster:
    sta $D019                   ; (acknowledge the raster interrupt)
    lda mx_next
    bne mx_more
    lda $D011                   ; the frame: only at its line (not an
    bmi mx_coll                 ; interrupt left over from the chain)
    lda $D012
    cmp #FRAME_LINE
    bcc mx_coll
    jsr mx_frame                ; the frame: sort, the first 8
    jmp mx_coll
mx_more:
    jsr mx_place                ; the next one (and those due already)
mx_coll:
    lda $D01E                   ; collisions: to the virtual sprites shown
                                ; (read after the placing, which comes
                                ; first: a reused one's go to the new)
    beq mx_nocs
    ldx #7
mx_cs:
    lsr
    pha
    bcc mx_cs_n
    ldy hwown,x
    lda scoll,y
    ora #1
    sta scoll,y
mx_cs_n:
    pla
    dex
    bpl mx_cs
mx_nocs:
    lda $D01F
    beq mx_nocb
    ldx #7
mx_cb:
    lsr
    pha
    bcc mx_cb_n
    ldy hwown,x
    lda scoll,y
    ora #2
    sta scoll,y
mx_cb_n:
    pla
    dex
    bpl mx_cb
mx_nocb:
    jmp $EA81                   ; (the KERNAL's register restore, RTI)

; mx_frame: sort the virtual sprites by Y (insertion sort: they are
; nearly in order from the frame before), hide all, place the first 8,
; and set the next raster line.
mx_frame:
    ldx #SPR_N-1                ; keys: Y, or 255 when hidden
mxf_key:
    lda sflg,x
    lsr
    lda sy,x
    bcs mxf_shown
    lda #255
mxf_shown:
    sta skey,x
    dex
    bpl mxf_key
    ldx #1                      ; insertion sort of sorder by skey
mxf_outer:
    lda sorder,x
    sta mx_tmp
    tay
    lda skey,y
    sta mx_tkey
    txa
    tay                         ; Y: the hole
mxf_inner:
    dey
    bmi mxf_put
    lda sorder,y
    sty mx_tmpy
    tay
    lda skey,y
    ldy mx_tmpy
    cmp mx_tkey
    bcc mxf_put
    beq mxf_put
    lda sorder,y
    sta sorder+1,y
    jmp mxf_inner
mxf_put:
    iny                         ; (Y = $FF -> 0: an index, not an address)
    lda mx_tmp
    sta sorder,y
    inx
    cpx #SPR_N
    bcc mxf_outer
    ldx #0                      ; shown: those before the first 255
mxf_count:
    ldy sorder,x
    lda skey,y
    cmp #255
    beq mxf_counted
    inx
    cpx #SPR_N
    bcc mxf_count
mxf_counted:
    stx mx_n
    lda #0
    sta $D015
    sta mx_next
mxf_first:                      ; the first 8 now (for the frame to come:
    lda mx_next                 ; no comparison with this raster line,
    cmp mx_n                    ; which is the frame's bottom)
    bcs mxf_sched
    cmp #8
    bcs mxf_sched
    jsr mx_put
    inc mx_next
    jmp mxf_first
mxf_sched:
    lda mx_next
    cmp mx_n
    bcs mxp_frame               ; 8 or fewer: the next frame
    and #7                      ; the 9th: when the 1st is drawn
    tax
    lda hwend,x
    jmp mxp_wait

; mx_place: place sorder[mx_next] (and the following, while their slot is
; free already) on hardware sprite mx_next AND 7; then the raster line
; for the next, or the frame line.
mx_place:
    lda mx_next
    cmp mx_n
    bcs mxp_frame
    cmp #8
    bcc mxp_now                 ; the first 8: free
    and #7                      ; its hardware sprite: done drawing?
    tax
    lda hwend,x                 ; (the line after its last)
    cmp $D012
    beq mxp_now
    bcs mxp_wait                ; not yet: an interrupt then
mxp_now:
    jsr mx_put
    inc mx_next
    jmp mx_place
mxp_wait:
    cmp #FRAME_LINE
    bcs mxp_frame
    sta $D012
    sta mx_tmp                  ; passed while setting it: no interrupt
    lda $D011                   ; will come; place now (but not from the
    bmi mxp_rts                 ; frame interrupt: its target is in the
    lda $D012                   ; next frame)
    cmp #FRAME_LINE
    bcs mxp_rts
    cmp mx_tmp
    bcs mxp_now
mxp_rts:
    rts
mxp_frame:
    lda #FRAME_LINE
    sta $D012
    lda #0
    sta mx_next
    rts

; mx_end: A = the line after virtual sprite Y's last: the VIC-II shows
; a sprite from line Y + 1, so Y + 22 (or 43 double high). Y from skey:
; the frame's copy (BASIC may move it meanwhile)
mx_end:
    lda sflg,y
    and #4
    beq mxe_n
    lda #21
mxe_n:
    clc
    adc #22
    adc skey,y
    bcc mxe_rts
    lda #255
mxe_rts:
    rts

; mx_put: sorder[mx_next] onto hardware sprite mx_next AND 7
mx_put:
    ldx mx_next
    ldy sorder,x
    txa
    and #7
    tax                         ; X: hardware sprite s
    asl
    tax
    lda skey,y                  ; Y first (safe while the one before is
    sta $D001,x                 ; still drawn): the frame's copy
    txa
    lsr
    tax
    tya
    sta hwown,x
    jsr mx_end
    sta hwend,x
    lda scol,y
    sta $D027,x
    lda sptr,y
    sta SCR_PTRS,x
    txa
    asl
    tax                         ; X: 2s
    lda sx_lo,y
    sta $D000,x
    txa
    lsr
    tax                         ; X: s
    lda $D010                   ; X bit 8
    and mx_nbit,x
    sta mx_tmp
    lda sx_hi,y
    beq mxu_x
    lda mx_bit,x
mxu_x:
    ora mx_tmp
    sta $D010
    mx_flag $D01D, 2            ; x2 wide
    mx_flag $D017, 4            ; x2 high
    mx_flag $D01B, 8            ; behind the picture
    mx_flag $D01C, 16           ; multicolour
    lda $D015
    ora mx_bit,x
    sta $D015
    rts

; mx_flag reg, mask: bit X of the VIC register set when flag bit mask of
; virtual sprite Y is set, else cleared.  Uses: A, mx_tmp.
mx_tmp      dta 0
mx_tkey     dta 0
mx_tmpy     dta 0

spr_image_end:
