; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- Upic full: the picture in the REU, *UPIC, bank 8
;
; Upic (Aleksi Eeben): 384 x 256 pixels in 16 colours, drawn by the CPU
; into the border colour one pixel at a time. The picture (Upic v1.3
; layout: a 256-byte header with the palette, then 192 byte columns of
; 256 rows, two pixels a byte, the left one in the low nybble) is kept in
; REU bank UPIC_BANK; it is shown by moving BASIC's RAM &0400-&CFFF to
; REU bank UPIC_SWAP, the picture to &1000-&CFFF and the viewer to
; &0400-&0FFF, until a key is pressed, then everything back
; (docs/DESIGN_GRAPHICS.md 10.11). The renderers come from
; tools/upic_gen.py (after ultimate-uci-oscar64's Upic module).
;
; ----------------------------------------------------------------------------

UPIC_BANK   = $09               ; REU &90000: the picture (owner, 2026-10-14)
UPIC_SWAP   = $0A               ; REU &A0000: BASIC's RAM while it shows
UP_REND     = $0400             ; while showing: the renderer (2440 bytes),
UP_NYB      = $0E00             ; the nybble table,
UP_VIEW     = $0F00             ; the viewer (swap, keys)
UP_VIEW2    = $0D90             ; its frame loop and variables (after
                                ; the renderer, before the table)
UP_COLS     = $1000             ; and the picture's columns
UP_TURBO    = $8F               ; $D031 on every line: top speed, no badlines

; ----------------------------------------------------------------------------
; The renderers (assembled for UP_REND) and the viewer (for UP_VIEW)

up_r64:
    org UP_REND, up_r64
    icl 'upic_r64.s'
UP_R64_LEN  = * - UP_REND
    org up_r64 + UP_R64_LEN
up_r48:
    org UP_REND, up_r48
    icl 'upic_r48.s'
UP_R48_LEN  = * - UP_REND
    org up_r48 + UP_R48_LEN
    .if UP_R64_LEN > UP_NYB-UP_REND || UP_R48_LEN > UP_NYB-UP_REND
    .error "Upic renderer too long"
    .endif

upv_image:
    .local upv
    org UP_VIEW, upv_image

; ----------------------------------------------------------------------------
; run (UP_VIEW)
;   Summary: show the picture until a key has been pressed and released.
;   Function: cartridge off (all RAM to &CFFF), &1000-&CFFF to the swap
;            bank, the picture in; RESTORE ignored; the frame loop with
;            the keyboard read between frames (all rows at once); then
;            RAM and registers back, the cartridge's bank 5 back.
;   Input:   interrupts off; renderer, nybble table in place.
;   Output:  frames = frames shown.  Uses: A, X, Y.
run:
    lda #UP_SHOWING             ; for hosts: the mailbox goes out (before
    sta UP_SIG                  ; the swap, cleared after it)
    lda #CART_OFF
    sta CART_CTRL
    lda #CPU_RAMBAS
    sta $01
    lda #$90                    ; C64 -> REU: RAM out
    jsr swap
    lda #<UP_COLS               ; the picture in: REU UPIC_BANK:0100
    sta $DF02
    lda #>UP_COLS
    sta $DF03
    lda #0
    sta $DF04
    lda #1
    sta $DF05
    lda #UPIC_BANK
    sta $DF06
    jsr len48k
    lda #$91
    sta $DF01
    lda $0318                   ; RESTORE: nothing (the MOS is out)
    sta onmi
    lda $0319
    sta onmi+1
    lda #<nmi
    sta $0318
    lda #>nmi
    sta $0319
    lda $D011
    sta od011
    lda $D020
    sta od020
    lda $D031
    sta od031
    lda #0
    sta frames
    sta frames+1
    sta phase
loop:
    jsr frame
    inc frames
    bne keys
    inc frames+1
keys:
    lda limit                   ; a time limit (frames, 0: none) reached?
    ora limit+1
    beq nolim
    lda frames
    cmp limit
    lda frames+1
    sbc limit+1
    bcs done
nolim:
    bit ESCFLG                  ; ESCAPE from the remote (u64remote stop):
    bmi done                    ; out, the flag kept for BASIC
    lda UP_SIG                  ; a host's key (u64remote endshow)
    cmp #UP_ENDSHOW
    beq done
    lda #0                      ; all keyboard rows
    sta $DC00
    lda $DC01
    ldx phase                   ; 0: wait until no key is down (the one
    cpx #1                      ; that started it), 1: for a key, 2:
    beq press                   ; until it is released
    cmp #$FF
    bne loop
    cpx #2
    beq done
    inc phase
    jmp loop
press:
    cmp #$FF
    beq loop
    inc phase
    lda norel                   ; GET / INKEY: out at the press (the KERNAL
    bne done                    ; scan then reads the key)
    jmp loop
done:
    lda #$FF
    sta $DC00
    lda #$91                    ; REU -> C64: RAM back
    jsr swap
    lda #0
    sta UP_SIG
    lda onmi
    sta $0318
    lda onmi+1
    sta $0319
    lda od031
    sta $D031
    lda od020
    sta $D020
    lda od011
    sta $D011
    lda #CPU_ROMS               ; bank 8 back (curbank is still BANK_UP)
    sta $01
    lda #BANK_UP
    sta CART_BANK
    lda #CART_MODE16
    sta CART_CTRL
    rts

;  (the second part: in the gap after the renderer)
UPV_LEN     = * - UP_VIEW
    org upv_image + UPV_LEN
upv_image2:
    org UP_VIEW2, upv_image2

; swap: &1000-&CFFF <-> UPIC_SWAP:1000 (A = $90 out, $91 back)
swap:
    pha
    lda #<UP_COLS
    sta $DF02
    sta $DF04
    lda #>UP_COLS
    sta $DF03
    sta $DF05
    lda #UPIC_SWAP
    sta $DF06
    jsr len48k
    pla
    sta $DF01
    rts
len48k:
    lda #0
    sta $DF07
    sta $DF0A
    lda #$C0
    sta $DF08
    rts

; frame: one picture (after ultimate-uci-oscar64's uii_upic_frame_asm,
; the whole window): display off, the frame's start, 256 lines from
; raster line $19, each resynchronised by $D031
frame:
    lda #0
    sta $D011
f1:
    lda $D011                   ; the bottom of the frame...
    bpl f1
f2:
    lda $D011                   ; ...and the wrap to line 0
    bmi f2
    lda #$18
tw:
    cmp $D012
    bne tw
    ldy #0
line:
    lda $D012
lw:
    cmp $D012                   ; the next raster line
    beq lw
    lda #$80                    ; resync: index 0, then top speed
    ldx #UP_TURBO
    sta $D031
    stx $D031
    jsr UP_REND
    iny
    bne line
    rts

nmi:
    rti

onmi        dta 0, 0
od011       dta 0
od020       dta 0
od031       dta 0
phase       dta 0
frames      dta 0, 0
limit       dta 0, 0            ; frames to show at most (0: until a key)
norel       dta 0               ; 1: end at the press, not the release
UPV_LEN2    = * - UP_VIEW2
    org upv_image2 + UPV_LEN2
    .endl
    .if upv.UPV_LEN > UP_COLS-UP_VIEW || upv.UPV_LEN2 > UP_NYB-UP_VIEW2
    .error "Upic viewer too long"
    .endif

    .local upic
    icl 'bankhelp.s'

; ----------------------------------------------------------------------------
; cmd_upic
;   Summary: *UPIC SHOW | LOAD file | SAVE file | CLEAR [c].
;   Input:   mosPTR/Y = rest of the command line.
;   Output:  per command.  Uses: A, X, Y, fs*, mosNUM, mosTMP, MOSBUF.
cmd_upic:
    jsr up_need
    lda #<wd_show
    ldx #>wd_show
    jsr s6_word
    bcc cu_noshow
    lda #0                      ; SHOW [n]: n centiseconds (0: until a key)
    sta mosNUM
    sta mosNUM+1
    jsr s6_skipsp
    cmp #13
    beq cus_go
    jsr s6_need
    jsr s6_end
cus_go:
    lda #0
    sta up_norel
    jmp up_show
cu_noshow:
    lda #<wd_load
    ldx #>wd_load
    jsr s6_word
    bcc cu_noload
    jmp up_load
cu_noload:
    lda #<wd_save
    ldx #>wd_save
    jsr s6_word
    bcc cu_nosave
    jmp up_save
cu_nosave:
    lda #<wd_clear
    ldx #>wd_clear
    jsr s6_word
    bcc cu_noclr
    jmp up_clearcmd
cu_noclr:
    lda #<wd_auto
    ldx #>wd_auto
    jsr s6_word
    bcc cu_syn
    lda #<wd_on                 ; AUTO ON | OFF: bit 7 of UP_DIRTY
    ldx #>wd_on
    jsr s6_word
    bcc cua_off
    jsr s6_end
    lda UP_DIRTY
    and #$7F
    sta UP_DIRTY
    rts
cua_off:
    lda #<wd_off
    ldx #>wd_off
    jsr s6_word
    bcc cu_syn
    jsr s6_end
    lda UP_DIRTY
    ora #$80
    sta UP_DIRTY
    rts
cu_syn:
    jmp s6_syntax

; up_need: an REU of 1 MB
up_need:
    jsr s6_hasreu
    beq upn_reu
    lda reu_banks+1
    bne upn_speed
    lda reu_banks
    cmp #16
    bcs upn_speed
upn_reu:
    brk
    dta 254, 'Upic needs an REU of 1 MB', 0
upn_speed:
    rts

; ----------------------------------------------------------------------------
; up_show
;   Summary: show the picture until a key is pressed (*UPIC SHOW).
;   Function: &0400-&0FFF to the swap bank, the renderer for the
;            machine's speed to &0400, the nybble table, the viewer; the
;            picture's palette; the viewer runs (interrupts off
;            throughout); then &0400-&0FFF back, the mode's palette, and
;            TIME on by the frames shown (2 centiseconds each).
;   Output:  none.  Uses: A, X, Y, fs*, mosPTR, mosPTR2.
up_show:
    lda mosNUM+1                ; the limit: centiseconds / 2 = frames
    lsr                         ; (first: the calls below use mosNUM)
    sta up_lim+1
    lda mosNUM
    ror
    sta up_lim
    ora up_lim+1                ; (1 cs: 1 frame, not none)
    bne ups_lim
    lda mosNUM
    beq ups_lim
    inc up_lim
ups_lim:
    lda cpu_class               ; the renderer needs 48 or 64 MHz
    bne ups_speed
    brk
    dta 254, 'Upic needs a 48 or 64 MHz Ultimate', 0
ups_speed:
    jsr up_valid
    lda UP_DIRTY                ; shown: clean again
    and #$80
    sta UP_DIRTY
    php
    sei
    lda #$90                    ; &0400-&0FFF out
    jsr up_low
    lda #<up_r64                ; the renderer
    ldx #>up_r64
    ldy cpu_class
    cpy #2
    beq ups_r
    lda #<up_r48
    ldx #>up_r48
ups_r:
    sta mosPTR
    stx mosPTR+1
    lda #<UP_REND
    sta mosPTR2
    lda #>UP_REND
    sta mosPTR2+1
    ldx #>[UP_NYB-UP_REND]      ; (up to the table: whole pages)
    jsr up_copy
    lda #<upv.upv_image2        ; the viewer's second part (one page:
    sta mosPTR                  ; into the table, which comes next)
    lda #>upv.upv_image2
    sta mosPTR+1
    lda #<UP_VIEW2
    sta mosPTR2
    lda #>UP_VIEW2
    sta mosPTR2+1
    ldx #1
    jsr up_copy
    ldx #0                      ; nyb[i] = i >> 4
ups_nyb:
    txa
    lsr
    lsr
    lsr
    lsr
    sta UP_NYB,x
    inx
    bne ups_nyb
    lda #<upv_image
    sta mosPTR
    lda #>upv_image
    sta mosPTR+1
    lda #<UP_VIEW
    sta mosPTR2
    lda #>UP_VIEW
    sta mosPTR2+1
    ldx #1
    jsr up_copy
    lda #<PALBUF                ; the picture's palette
    sta fsADDR
    lda #>PALBUF
    sta fsADDR+1
    lda #$D0
    sta fsTMP
    lda #0
    sta fsTMP+1
    lda #UPIC_BANK
    sta fsTMP+2
    lda #48
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_C64
    jsr up_dma
    farcall pal_send, BANK_FS
    lda up_lim                  ; the limit and the key mode
    sta upv.limit
    lda up_lim+1
    sta upv.limit+1
    lda up_norel
    sta upv.norel
    jsr upv.run
    lda upv.phase               ; ended by a key (1) or the time (0)
    cmp #2
    lda #0
    rol
    sta up_bykey
    lda upv.frames              ; TIME on: 2 cs a frame
    asl
    sta mosTMP
    lda upv.frames+1
    rol
    sta mosTMP+1
    lda #$91                    ; &0400-&0FFF back
    jsr up_low
    lda mostime
    clc
    adc mosTMP
    sta mostime
    lda mostime+1
    adc mosTMP+1
    sta mostime+1
    bcc ups_pal
    inc mostime+2
    bne ups_pal
    inc mostime+3
    bne ups_pal
    inc mostime+4
ups_pal:
    plp
    lda eng_kind                ; the mode's palette back: Upic Lite and
    cmp #1                      ; teletext their own, the VIC-II modes and
    beq ups_ul                  ; Upic full's console the C64's
    cmp #2
    bne ups_c64
ups_ul:
    farcall ul_setpal, BANK_FS
    rts
ups_c64:
    farcall pal_apply, BANK_FS
    rts

; ----------------------------------------------------------------------------
; up_auto
;   Summary: the automatic show of MODE 110/111 (owner: when a program
;            ends, in GET and in a long INKEY), if the picture changed.
;   Function: only with eng_kind 3, auto on, the picture changed since
;            the last show (UP_DIRTY = 1), a 48/64 MHz Ultimate. A = 0:
;            the BASIC prompt, until a key (pressed and released: it is
;            not typed); 1: GET, until a key, which the KERNAL scan then
;            puts in the keyboard buffer for GET; 2: INKEY(mosNUM cs),
;            only from 50 cs on, at most that long (TIME goes on, so INKEY
;            times out after it), a key as with GET.
;   Input:   A = kind, mosNUM (INKEY).  Output: none.  Uses: A, X, Y, fs*.
up_auto:
    sta up_kind
    lda eng_kind
    cmp #3
    bne upa_no
    lda UP_DIRTY
    cmp #1
    bne upa_no
    lda cpu_class
    beq upa_no
    lda up_kind
    cmp #2
    bne upa_go
    lda mosNUM+1                ; INKEY: 50 cs or more
    bne upa_go
    lda mosNUM
    cmp #50
    bcc upa_no
upa_go:
    lda up_kind
    cmp #2
    beq upa_t
    lda #0                      ; (prompt, GET: no limit; mosNUM is only
    sta mosNUM                  ; INKEY's)
    sta mosNUM+1
upa_t:
    lda up_kind                 ; GET / INKEY: end at the press
    beq upa_rel
    lda #1
upa_rel:
    sta up_norel
    ldx #3                      ; (OSWORD 0's pointers: up_show copies
upa_save:                       ; with mosPTR, mosPTR2)
    lda mosPTR,x
    pha
    dex
    bpl upa_save
    jsr up_show
    ldx #0
upa_rest:
    pla
    sta mosPTR,x
    inx
    cpx #4
    bcc upa_rest
    lda up_kind
    beq upa_no
    lda up_bykey
    beq upa_no
    jsr $FF9F                   ; SCNKEY: the key into the buffer
upa_no:
    rts


; up_low: &0400-&0FFF <-> UPIC_SWAP:0400 (A = REU_TO_REU out, REU_TO_C64
; back)
up_low:
    pha
    lda #<$0400
    sta fsADDR
    sta fsTMP
    lda #>$0400
    sta fsADDR+1
    sta fsTMP+1
    lda #UPIC_SWAP
    sta fsTMP+2
    lda #0
    sta fsLEN
    lda #$0C
    sta fsLEN+1
    pla
    jmp up_dma

; up_copy: X pages from (mosPTR) to (mosPTR2)
up_copy:
    ldy #0
upc_loop:
    lda (mosPTR),y
    sta (mosPTR2),y
    iny
    bne upc_loop
    inc mosPTR+1
    inc mosPTR2+1
    dex
    bne upc_loop
    rts

; up_valid: the picture's header must say Upic ('U' at 0, $AE at 7)
up_valid:
    jsr up_hdr4
    lda MOSBUF
    cmp #'U'
    bne upv_no
    lda MOSBUF+7
    cmp #$AE
    bne upv_no
    rts
upv_no:
    brk
    dta 246, 'No Upic picture (*UPIC LOAD or CLEAR)', 0

; up_hdr4: the header's first 8 bytes to MOSBUF
up_hdr4:
    lda #8
    jsr up_hdrdma
    lda #REU_TO_C64
    jmp up_dma
; up_hdrdma: fsADDR = MOSBUF, fsTMP = UPIC_BANK:0000, fsLEN = A
up_hdrdma:
    sta fsLEN
    lda #0
    sta fsLEN+1
    sta fsTMP
    sta fsTMP+1
    lda #UPIC_BANK
    sta fsTMP+2
    lda #<MOSBUF
    sta fsADDR
    lda #>MOSBUF
    sta fsADDR+1
    rts

; ----------------------------------------------------------------------------
; up_clearcmd: CLEAR [c]: a new picture of colour c (0), the C64 palette
up_clearcmd:
    lda #0
    sta mosNUM
    jsr s6_skipsp
    cmp #13
    beq upcc_go
    jsr s6_need
    jsr s6_end
upcc_go:
    lda mosNUM
    and #15
    clc                         ; (the C64 palette)
    jsr up_header
    jmp up_clear

; up_clear: the bitmap all colour A (both nybbles), by DMA from one byte
up_clear:
    sta mosTMP
    asl
    asl
    asl
    asl
    ora mosTMP
    sta mosTMP
    lda #<mosTMP
    sta fsADDR
    lda #>mosTMP
    sta fsADDR+1
    lda #0
    sta fsTMP
    sta fsLEN
    lda #1
    sta fsTMP+1
    lda #UPIC_BANK
    sta fsTMP+2
    lda #$C0
    sta fsLEN+1
    php                         ; (fixed C64 address: rd_dma clears
    sei                         ; REU_CTRL, so set it up here)
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
    lda #$80
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    lda #0
    sta REU_CTRL
    plp
    rts

; up_header: a v1.3 header in the REU: magic, size, text (line 4 says
; what made it), the C64 palette (C = 0) or entry l = the C64 colour
; pal[l] (C = 1: MODE 110/111, the mode's logical colours as in MODE 2)
up_header:
    pha
    php
    ldx #0
    lda #0
uph_zero:
    sta MOSBUF,x
    inx
    bne uph_zero
    ldx #15
uph_fix:
    lda uph_start,x
    sta MOSBUF,x
    dex
    bpl uph_fix
    ldx #159                    ; text: spaces, then line 4
    lda #' '
uph_sp:
    sta MOSBUF+$30,x
    dex
    bpl uph_sp
    ldx #uph_made_len-1
uph_made:
    lda uph_made_t,x
    sta MOSBUF+$30+120,x
    dex
    bpl uph_made
    lda #<[MOSBUF+$D0]          ; the C64 palette from the REU
    sta fsADDR
    lda #>[MOSBUF+$D0]
    sta fsADDR+1
    lda #<REU_PAL64
    sta fsTMP
    lda #>REU_PAL64
    sta fsTMP+1
    lda #REU_FONT_BANK
    sta fsTMP+2
    lda #48
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_C64
    jsr up_dma
    plp
    bcc uph_hdr
    ldx #47                     ; logical colours: through pal[]
uph_save:
    lda MOSBUF+$D0,x
    sta PALBUF,x
    dex
    bpl uph_save
    ldy #0                      ; entry l (Y = 3l)
    ldx #0
uph_pal:
    stx mosTMP
    lda pal,x
    and #15
    sta mosTMP+1
    asl
    adc mosTMP+1                ; C64 colour * 3
    tax
    lda PALBUF,x
    sta MOSBUF+$D0,y
    lda PALBUF+1,x
    sta MOSBUF+$D1,y
    lda PALBUF+2,x
    sta MOSBUF+$D2,y
    iny
    iny
    iny
    ldx mosTMP
    inx
    cpx #16
    bne uph_pal
uph_hdr:
    lda #0                      ; the header to UPIC_BANK:0000
    jsr up_hdrdma
    inc fsLEN+1                 ; (256 bytes)
    lda #REU_TO_REU
    jsr up_dma
    pla
    rts
uph_start:
    dta 'Upic1.3', $AE
    dta a(384), a(256), a(16), a(49152)
uph_made_t:
    dta 'Created with U64 BBC BASIC'
uph_made_len = * - uph_made_t

; ----------------------------------------------------------------------------
; up_load: LOAD file: a Upic v1.3 file (49408 bytes), or a bare bitmap
; (49152 bytes: the header made here, with the C64 palette)
up_load:
    jsr s6_name
    jsr s6_end
    farcall rx_openin, BANK_FS
    lda fsTMP+2                 ; 49408 = &C100, 49152 = &C000
    ora fsTMP+3
    ora fsTMP
    beq upl_size
    jmp upl_bad
upl_size:
    lda fsTMP+1
    cmp #$C1
    beq upl_v13
    cmp #$C0
    beq upl_bare
    jmp upl_bad
upl_bare:
    lda #0                      ; bare: a header first, the bitmap at page 1
    clc
    jsr up_header
    lda #UPIC_BANK
    ldy #1
    ldx #$C0
    farcall rx_read, BANK_FS
    farcall rx_close, BANK_FS
    jmp upl_dirty
upl_v13:
    lda #UPIC_BANK
    ldy #0
    ldx #$C1
    farcall rx_read, BANK_FS
    farcall rx_close, BANK_FS
    jsr up_valid
upl_dirty:
    lda UP_DIRTY                ; new picture: shown automatically
    ora #1
    sta UP_DIRTY
    rts
upl_bad:
    farcall rx_close, BANK_FS
    brk
    dta 246, 'Not a Upic file', 0

; up_save: SAVE file: the picture as a v1.3 file
up_save:
    jsr s6_name
    jsr s6_end
    jsr up_valid
    farcall rx_create, BANK_FS
    lda #UPIC_BANK
    ldy #0
    ldx #$C1
    farcall rx_write, BANK_FS
    farcall rx_close, BANK_FS
    rts

; up_dma: as rd_dma (bank 5): DMA between fsADDR (C64) and fsTMP/+1/+2
; (REU), fsLEN bytes, command A; interrupts off while it is set up
up_dma:
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

wd_show     dta 'SHOW', 0
wd_auto     dta 'AUTO', 0
wd_on       dta 'ON', 0
wd_off      dta 'OFF', 0
wd_load     dta 'LOAD', 0
wd_save     dta 'SAVE', 0
wd_clear    dta 'CLEAR', 0
    .endl
