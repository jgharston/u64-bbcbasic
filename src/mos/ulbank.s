; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- bank 4: Upic Lite RAM images and their set-up
;
; ul_enter (from bank 3's MODE code, through the trampoline) copies the
; Upic Lite engine, frame loop, renderer, shift tables and the shapes'
; RAM copy from this bank into RAM (docs/DESIGN_GRAPHICS.md section 10.8).
; The copy routine has to run from the bank that holds the images.
;
; ----------------------------------------------------------------------------

; ul_enter
;   Summary: start Upic Lite for the mode in vmode_*: engine, frame code,
;            renderer and tables into RAM, buffer cleared, palette to the
;            Ultimate, raster interrupt on (CIA timer interrupts off: the
;            frame interrupt also scans the keyboard and counts TIME).
;   Uses:    A, X, Y, gzp; mosPTR (saved).
ul_enter:
    lda mosPTR
    pha
    lda mosPTR+1
    pha
    sei
    lda #0                      ; renderer off while it is replaced
    sta $D01A
    lda #$0F
    sta $D019
    lda #<ule_load              ; engine
    ldx #>ule_load
    ldy #>ENGINE
    jsr ul_pages16
    lda #<ulf_load              ; frame code
    ldx #>ulf_load
    ldy #>UL_FRAME
    jsr ul_page1
    lda vmode_rend
    cmp #1
    bne ue_n1
    lda #<ulr1_load
    ldx #>ulr1_load
    ldy #>UL_LINE
    jsr ul_set
    ldx #>[ulr1_len+255]
    jsr ul_copy
    jmp ue_go
ue_n1:
    cmp #2
    bne ue_n2
    lda #<ulr2_load
    ldx #>ulr2_load
    ldy #>UL_LINE
    jsr ul_set
    ldx #>[ulr2_len+255]
    jmp ue_rcopy
ue_n2:
    cmp #3
    bne ue_n3
    lda #<ulr3_load
    ldx #>ulr3_load
    ldy #>UL_LINE
    jsr ul_set
    ldx #>[ulr3_len+255]
    jmp ue_rcopy
ue_n3:
    lda #<ulr4_load
    ldx #>ulr4_load
    ldy #>UL_LINE
    jsr ul_set
    ldx #>[ulr4_len+255]
ue_rcopy:
    jsr ul_copy
    lda #<ult_load              ; shift tables (2 and 4 bits per pixel)
    ldx #>ult_load
    ldy #>UL_TABLES
    jsr ul_set
    ldx #3
    jsr ul_copy
ue_go:
    cli
    lda #$0B                    ; display off: the whole screen is border
    sta $D011
    lda #0
    sta $D020
    ldx #GX_MODE                ; clear the buffer, reset the VDU state
    jsr gx_call
    farcall ul_setpal, BANK_FS
    sei
    lda #$7F                    ; CIA 1 interrupts off
    sta $DC0D
    lda $DC0D
    lda #UL_IRQLINE
    sta $D012
    lda $D011
    and #$7F
    sta $D011
    lda #<ul_irq
    sta $0314
    lda #>ul_irq
    sta $0315
    lda #1
    sta $D01A
    sta ul_active
    sta eng_kind                ; the Upic Lite engine is in
    lda #$0F
    sta $D019
    cli
    pla
    sta mosPTR+1
    pla
    sta mosPTR
    rts

; ul_set: source A/X (bank 4), destination page Y -> mosPTR, gzp
ul_set:
    sta mosPTR
    stx mosPTR+1
    lda #0
    sta gzp
    sty gzp+1
    rts
; ul_page1 / ul_pages16: copy 1 / 16 pages from A/X to page Y
ul_page1:
    jsr ul_set
    ldx #1
    bne ul_copy
ul_pages16:
    jsr ul_set
    ldx #16
; ul_copy: X pages from (mosPTR) to (gzp), with $01 = $33: the cartridge
; stays visible, writes reach the RAM under I/O and the KERNAL
; (interrupts are off: the caller's SEI)
ul_copy:
    lda #$33
    sta $01
    ldy #0
ulc_loop:
    lda (mosPTR),y
    sta (gzp),y
    iny
    bne ulc_loop
    inc mosPTR+1
    inc gzp+1
    dex
    bne ulc_loop
    lda #CPU_ROMS
    sta $01
    rts

; ----------------------------------------------------------------------------
; Upic Lite RAM images (copied by ul_enter)

UL_FRAME   = $E000
UL_LINE    = $E100
UL_TABLES  = $E900
UL_IRQLINE = $10                ; raster interrupt; the picture starts at $19

; Frame loop, from the raster interrupt (core's ul_irq, $01 = $35).
; The line loop is the one the renderers were calibrated with
; (tests/proto/upiclite_proto.py; ultimate-uci-oscar64's
; uii_upic_frame_asm, after Aleksi Eeben's Upic).
ulf_load:
    org UL_FRAME, ulf_load
ulf_entry:
    lda $D011                   ; late (past line $17): skip this frame
    bmi uf_skip
    lda $D012
    cmp #$18
    bcs uf_skip
    lda $D031
    sta uf_turbo
    lda #$18
uf_wait:
    cmp $D012
    bne uf_wait
    ldy #0
uf_line:
    lda $D012
uf_lw:
    cmp $D012
    beq uf_lw
    lda #$80                    ; resync: index 0, then back to turbo
    ldx #$8F
    sta $D031
    stx $D031
    jsr UL_LINE
    iny
    bne uf_line
    lda uf_turbo
    sta $D031
uf_skip:
    rts
uf_turbo:
    dta 0
ulf_len = * - UL_FRAME
    .if ulf_len > $100
    .error "Upic Lite frame code over a page"
    .endif
    :[UL_FRAME+$100-*] dta 0    ; a full page: MADS leaves gaps out
    org ulf_load + $100

ulr1_load:
    org UL_LINE, ulr1_load
    icl 'ul_r1.s'
ulr1_len = * - UL_LINE
    org ulr1_load + ulr1_len

ulr2_load:
    org UL_LINE, ulr2_load
    icl 'ul_r2.s'
ulr2_len = * - UL_LINE
    .if UL_LINE + ulr2_len > UL_TABLES
    .error "Upic Lite renderer runs into its tables"
    .endif
    org ulr2_load + ulr2_len

ulr3_load:                      ; MODE 5: 160 wide, 2 bits per pixel
    org UL_LINE, ulr3_load
    icl 'ul_r3.s'
ulr3_len = * - UL_LINE
    org ulr3_load + ulr3_len

ulr4_load:                      ; MODE 2: 160 wide, 4 bits per pixel
    org UL_LINE, ulr4_load
    icl 'ul_r4.s'
ulr4_len = * - UL_LINE
    org ulr4_load + ulr4_len

ult_load:                       ; b >> 2, b >> 4, b >> 6
    :256 dta [#>>2]
    :256 dta [#>>4]
    :256 dta [#>>6]

ule_load:
    org ENGINE, ule_load
    icl 'gfx_ul.s'
    org ule_load + $1000

; ----------------------------------------------------------------------------
; Sound engine image (sound.s), copied to SOUNDRAM by snd_install

snd_load:
    org SOUNDRAM, snd_load
    icl 'sound.s'
snd_len = snd.s_vars - SOUNDRAM
    org snd_load + snd_len

    icl 'sound_tables.s'

; ----------------------------------------------------------------------------
; snd_install
;   Summary: at start-up, before interrupts are on: the sound engine to
;            SOUNDRAM, its variables cleared, the pitch and noise tables
;            for the machine's clock (PAL or NTSC, KERNAL flag $02A6),
;            then the SIDs found and the engine reset.
;   Uses:    A, X, Y, mosPTR, mosPTR2.
snd_install:
    lda #<snd_load              ; image
    sta mosPTR
    lda #>snd_load
    sta mosPTR+1
    lda #<SOUNDRAM
    sta mosPTR2
    lda #>SOUNDRAM
    sta mosPTR2+1
    ldx #>snd_len               ; whole pages, then the rest
    ldy #0
sni_page:
    cpx #0
    beq sni_rest
sni_pb:
    lda (mosPTR),y
    sta (mosPTR2),y
    iny
    bne sni_pb
    inc mosPTR+1
    inc mosPTR2+1
    dex
    bne sni_page
sni_rest:
    cpy #<snd_len
    beq sni_vars
    lda (mosPTR),y
    sta (mosPTR2),y
    iny
    bne sni_rest
sni_vars:
    lda #<snd.s_vars            ; variables to 0
    sta mosPTR2
    lda #>snd.s_vars
    sta mosPTR2+1
    ldx #>[snd.s_end-snd.s_vars+255]
    lda #0
    tay
sni_z:
    sta (mosPTR2),y
    iny
    bne sni_z
    inc mosPTR2+1
    dex
    bne sni_z
    ldx #0                      ; pitch table for the clock
    lda $02A6
    beq sni_ntsc
sni_pal:
    lda snd_ppal_lo,x
    sta snd.ptab_lo,x
    lda snd_ppal_hi,x
    sta snd.ptab_hi,x
    inx
    bne sni_pal
    ldx #5
sni_npal:
    lda snd_npal_lo,x
    sta snd.ntab_lo,x
    lda snd_npal_hi,x
    sta snd.ntab_hi,x
    dex
    bpl sni_npal
    bmi sni_go
sni_ntsc:
    lda snd_pntsc_lo,x
    sta snd.ptab_lo,x
    lda snd_pntsc_hi,x
    sta snd.ptab_hi,x
    inx
    bne sni_ntsc
    ldx #5
sni_nn:
    lda snd_nntsc_lo,x
    sta snd.ntab_lo,x
    lda snd_nntsc_hi,x
    sta snd.ntab_hi,x
    dex
    bpl sni_nn
sni_go:
    jsr SOUNDRAM+18             ; find the SIDs
    jmp SOUNDRAM+0              ; reset the engine

bank4_end:
    .if bank4_end > $C000
    .error "Bank 4 overflows 16K"
    .endif
    :[$C000-*] dta $FF
