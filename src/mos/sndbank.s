; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 6: sound
;
; The two engine images (sound.s: BBC and SID), loaded into RAM by
; *SOUND; the pitch tables; the sound commands and OSWORD 7/8 (sndcmd.s);
; the default instruments. Design: docs/DESIGN_SOUND.md.
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Engine images: assembled for SOUNDRAM, stored here

snd_imgsid:
    .local snds
    org SOUNDRAM, snd_imgsid
SIDIMG      = 1
    icl 'sound.s'
    .endl
SNDS_LEN    = snds.s_vars - SOUNDRAM
    org snd_imgsid + SNDS_LEN

snd_imgbbc:
    .local sndb
    org SOUNDRAM, snd_imgbbc
SIDIMG      = 0
    icl 'sound.s'
    .endl
SNDB_LEN    = sndb.s_vars - SOUNDRAM
    org snd_imgbbc + SNDB_LEN

    icl 'sound_tables.s'

; ----------------------------------------------------------------------------
; snd_load
;   Summary: put engine image A (0 SID, 1 BBC) into RAM and start it.
;   Function: the interrupt leaves the engine alone meanwhile (snd_on 0);
;            the image to SOUNDRAM, its variables cleared, s_mode set,
;            then the engine's own reset (voices, SIDs silent).
;   Input:   A = mode; the shared data (SIDs found, tables) in place.
;   Output:  snd_on = 1.  Uses: A, X, Y, mosPTR, mosPTR2, fsCNT.
snd_load:
    sta s_mode
    lda #0
    sta snd_on
    lda s_mode
    bne sld_bbc
    lda #<snd_imgsid
    ldx #>snd_imgsid
    ldy #>SNDS_LEN
    sty fsCNT+1
    ldy #<SNDS_LEN
    sty fsCNT
    jmp sld_copy
sld_bbc:
    lda #<snd_imgbbc
    ldx #>snd_imgbbc
    ldy #>SNDB_LEN
    sty fsCNT+1
    ldy #<SNDB_LEN
    sty fsCNT
sld_copy:
    sta mosPTR
    stx mosPTR+1
    lda #<SOUNDRAM
    sta mosPTR2
    lda #>SOUNDRAM
    sta mosPTR2+1
    ldx fsCNT+1                 ; whole pages, then the rest
    ldy #0
sld_page:
    cpx #0
    beq sld_rest
sld_pb:
    lda (mosPTR),y
    sta (mosPTR2),y
    iny
    bne sld_pb
    inc mosPTR+1
    inc mosPTR2+1
    dex
    bne sld_page
sld_rest:
    cpy fsCNT
    beq sld_vars
    lda (mosPTR),y
    sta (mosPTR2),y
    iny
    bne sld_rest
sld_vars:
    lda #0                      ; the rest up to the shared data to 0 (the
    sta mosPTR2                 ; variables follow the image): from Y in
sld_z:                          ; the page mosPTR2 points at
    ldx mosPTR2+1
    cpx #>SNDSHR
    bcs sld_last
    sta (mosPTR2),y
    iny
    bne sld_z
    inc mosPTR2+1
    bne sld_z
sld_last:                       ; the page of SNDSHR: up to it
    cpy #<SNDSHR
    bcs sld_init
    sta (mosPTR2),y
    iny
    bne sld_last
sld_init:
    jsr SNDV_INIT
    lda #1
    sta snd_on
    rts

; ----------------------------------------------------------------------------
; snd_tables
;   Summary: the pitch and noise tables for the machine's clock (PAL or
;            NTSC, KERNAL flag $02A6) into the shared data.
;   Uses:    A, X.
snd_tables:
    ldx #47                     ; the octave of middle C
    lda $02A6
    beq stb_ntsc
stb_pal:
    lda snd_fpal_lo,x
    sta ftab_lo,x
    lda snd_fpal_hi,x
    sta ftab_hi,x
    dex
    bpl stb_pal
    ldx #5
stb_npal:
    lda snd_npal_lo,x
    sta ntab_lo,x
    lda snd_npal_hi,x
    sta ntab_hi,x
    dex
    bpl stb_npal
    rts
stb_ntsc:
    lda snd_fntsc_lo,x
    sta ftab_lo,x
    lda snd_fntsc_hi,x
    sta ftab_hi,x
    dex
    bpl stb_ntsc
    ldx #5
stb_nn:
    lda snd_nntsc_lo,x
    sta ntab_lo,x
    lda snd_nntsc_hi,x
    sta ntab_hi,x
    dex
    bpl stb_nn
    rts

; ----------------------------------------------------------------------------
; Helpers (s6_word, s6_num, s6_text, ...): bankhelp.s

    icl 'bankhelp.s'

; ----------------------------------------------------------------------------

    icl 'sndcmd.s'
    icl 'songcmd.s'
    icl 'speech.s'
    icl 'font46.s'                ; (moved from bank 8, 2026-10-16)
    icl 'petscii.s'
    icl 'cfg_text.s'                ; *SETUP's settings (ultctl.s, bank 7)
    icl 'reucmd.s'                  ; *REULOAD, *REUSAVE, *REU

bank6_end:
    .if bank6_end > $C000
    .error "Bank 6 overflows 16K"
    .endif
    :[$C000-*] dta $FF
