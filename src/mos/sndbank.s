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
; Helpers. Routines here cannot call bank 2's directly: those that only
; take registers go through farcall; those that read text from their
; caller's bank (keywords, inline messages) have copies here.

; s6_word: as arg_word (batcha.s): C = 1 if the word at A/X (here) is next
; on the line (case does not matter, no letter may follow); Y past it
s6_word:
    sta mosPTR2
    stx mosPTR2+1
s6w_skip:
    lda (mosPTR),y
    cmp #' '
    bne s6w_start
    iny
    bne s6w_skip
s6w_start:
    sty aw_start_y
    lda #0
    sta aw_i
s6w_cmp:
    ldy aw_i
    lda (mosPTR2),y
    beq s6w_end
    sta aw_c
    tya
    clc
    adc aw_start_y
    tay
    lda (mosPTR),y
    jsr s6_up
    cmp aw_c
    bne s6w_no
    inc aw_i
    bne s6w_cmp
s6w_end:
    lda aw_i
    clc
    adc aw_start_y
    tay
    lda (mosPTR),y
    jsr s6_up
    cmp #'A'
    bcc s6w_yes
    cmp #'Z'+1
    bcc s6w_no
s6w_yes:
    sec
    rts
s6w_no:
    ldy aw_start_y
    clc
    rts

; s6_up: A in upper case (a-z only)
s6_up:
    cmp #'a'
    bcc s6u_rts
    cmp #'z'+1
    bcs s6u_rts
    and #$DF
s6u_rts:
    rts

; s6_num: as arg_number: the next number at mosPTR/Y into mosNUM (C = 1:
; none)
s6_num:
    farcall cli_number, BANK_MOS
    rts

; s6_need: s6_num, raising "Syntax" if there is none
s6_need:
    jsr s6_num
    bcs s6_syntax
    rts
s6_syntax:
    brk
    dta 220, 'Syntax', 0

; s6_skipsp: A = the next non-space character at mosPTR/Y
s6_skipsp:
    lda (mosPTR),y
    cmp #' '
    bne s6s_rts
    iny
    bne s6_skipsp
s6s_rts:
    rts

; s6_end: nothing else may follow on the line ("Syntax")
s6_end:
    jsr s6_skipsp
    cmp #13
    bne s6_syntax
    rts

; s6_signed: as sm_signed: [-]n, mosNUM = 0-255, mosNUM+1 = 1 if negative
; (C = 1: none, or over 255)
s6_signed:
    jsr s6_skipsp
    ldx #0
    cmp #'-'
    bne s6g_num
    iny
    inx
s6g_num:
    stx fsTMP
    jsr s6_num
    bcs s6g_rts
    lda mosNUM+1
    beq s6g_ok
    sec
    rts
s6g_ok:
    lda fsTMP
    sta mosNUM+1
    clc
s6g_rts:
    rts

; s6_name: as arg_name: the file name at mosPTR/Y -> fsPTR/fsLEN, Y past it
s6_name:
    farcall arg_name, BANK_FS
    rts

; s6_dec8 / s6_dec16: A / mosTMP in decimal
s6_dec8:
    farcall st_dec8, BANK_FS
    rts
s6_dec16:
    farcall st_dec16, BANK_FS
    rts

; s6_text: print the 0-terminated text after the JSR (as st_text)
s6_text:
    pla
    sta mosPTR2
    pla
    sta mosPTR2+1
    ldy #1
s6t_loop:
    lda (mosPTR2),y
    beq s6t_end
    jsr OSASCI
    iny
    bne s6t_loop
s6t_end:
    tya
    clc
    adc mosPTR2
    tax
    lda mosPTR2+1
    adc #0
    pha
    txa
    pha
    rts

; s6_hasreu: Z = 0 if there is an REU
s6_hasreu:
    lda reu_banks
    ora reu_banks+1
    rts

s6w_bbc     dta 'BBC', 0
s6w_off     dta 'OFF', 0
s6w_on      dta 'ON', 0
s6w_none    dta 'NONE', 0
s6w_default dta 'DEFAULT', 0
s6w_save    dta 'SAVE', 0
s6w_load    dta 'LOAD', 0

; ----------------------------------------------------------------------------

    icl 'sndcmd.s'
    icl 'songcmd.s'

bank6_end:
    .if bank6_end > $C000
    .error "Bank 6 overflows 16K"
    .endif
    :[$C000-*] dta $FF
