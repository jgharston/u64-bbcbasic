; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- placing the RAM fast path for the BASIC V graphics
; commands (fastcmd.s) below HIMEM in the graphics modes (bank 5)
;
; The image is assembled twice, at $1000 and $2000: a byte that differs
; between the two copies is the high byte of an address inside the image,
; so copying it to page P takes copy-1's byte - $10 + P; every other byte
; goes as it is. Three pages below HIMEM (below the sprite multiplexer when
; it is there): BASIC's HIMEM follows (OSBYTE &84 / &85, mos.s).
; docs/DESIGN_GRAPHICS.md section 11.
;
; ----------------------------------------------------------------------------

FP_PAGES    = 3                 ; the image's room below HIMEM

fc_img1:
    .local fci1
    org $1000, fc_img1
    icl 'fastcmd.s'
    .endl
FC_LEN      = fci1.fc_image_end - $1000
    org fc_img1 + FC_LEN
    .if FC_LEN > FP_PAGES*256
    .error "The fast path image is over 3 pages"
    .endif
fc_img2:
    .local fci2
    org $2000, fc_img2
    icl 'fastcmd.s'
    .endl
    org fc_img2 + FC_LEN

    .local fpa

; ----------------------------------------------------------------------------
; fp_place
;   Summary: the fast path in or out after a MODE change or *SPRITE ON /
;            OFF: in a graphics mode (vtype 1) at three pages below HIMEM
;            (below the sprite multiplexer if it is in), CLIV on it; in
;            the text modes and MODE 7 out, CLIV back to v_cli.
;   Function: copies FC_LEN bytes from fc_img1, relocated by comparing
;            with fc_img2; at the prompt BASIC's HIMEM moves too (in a
;            program BASIC takes it from OSBYTE &84 after MODE).
;   Input:   vtype, spr_page, vmode_himem.  Output: fp_page, CLIV, HIMEM.
;   Uses:    A, X, Y, mosPTR, mosPTR2, mosTMP.
fp_place:
    lda vtype
    cmp #1
    beq fpp_gfx
    lda fp_page                 ; out
    beq fpp_rts
    lda #0
    sta fp_page
    php
    sei
    lda #<v_cli
    sta CLIV
    lda #>v_cli
    sta CLIV+1
    plp
fpp_rts:
    rts
fpp_gfx:
    lda spr_page                ; the room: under the multiplexer or HIMEM
    bne fpp_base
    lda vmode_himem
fpp_base:
    sec
    sbc #FP_PAGES
    sta fp_page
    sta mosTMP+1                ; the target
    lda #0
    sta mosTMP
    lda #<fc_img1
    sta mosPTR
    lda #>fc_img1
    sta mosPTR+1
    lda #<fc_img2
    sta mosPTR2
    lda #>fc_img2
    sta mosPTR2+1
    ldx #FP_PAGES               ; three pages (beyond FC_LEN: unused room)
    ldy #0
fpp_copy:
    lda (mosPTR),y
    cmp (mosPTR2),y
    beq fpp_put
    sec                         ; an address's high byte: to page fp_page
    sbc #>$1000
    clc
    adc fp_page
fpp_put:
    sta (mosTMP),y
    iny
    bne fpp_copy
    inc mosPTR+1
    inc mosPTR2+1
    inc mosTMP+1
    dex
    bne fpp_copy
    php                         ; CLIV on the image's start (fc_cli)
    sei
    lda #0
    sta CLIV
    lda fp_page
    sta CLIV+1
    plp
    lda $0C                     ; at the prompt: BASIC's HIMEM now
    cmp #>$0700
    bne fpp_rts
    lda #0
    sta $06
    lda fp_page
    sta $07
    rts

    .endl
