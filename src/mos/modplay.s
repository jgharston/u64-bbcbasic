; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- *MODPLAY and *MODSTOP (bank 10, inside .local aud)
;
; A ProTracker MOD in the background on Ultimate Audio channels 0-3. The
; engine (modengine.s, ported from ModPlayer_16k by Freshness/6510nl,
; CSDb release 131522) is a third sound engine image: *MODPLAY puts it in
; the place of the SID or BBC engine (&0900-&1C5F), *MODSTOP brings that
; engine back. The module goes to the REU at
; &F20000 (up to 768K); its header is read there into the image's tables
; (ModPlayer_16k's detectmod and setmodstructures, rewritten to read the
; REU; a 15-sample module's patterns at 600, where the original has 604).
;
; ----------------------------------------------------------------------------

MP_MAX      = $0C               ; 768K: banks &F2-&FD
AD_PREV     = $010B             ; REU AD_BANK: the engine to go back to

; ----------------------------------------------------------------------------
; The image, assembled for SOUNDRAM, stored here
mi_img:
    .local modi
    org SOUNDRAM, mi_img
    icl 'modengine.s'
    .endl
MI_LEN      = modi.mi_end - SOUNDRAM
    org mi_img + MI_LEN
    .if SOUNDRAM + MI_LEN > SNDSHR
    .error "The MOD engine image runs into the shared sound data"
    .endif
    .if >modi.division != >[modi.division+15]
    .error "The MOD engine's row crosses a page"
    .endif

; The tables (ModPlayer_16k's Tools/), 2176 bytes, for the REU (aud_init)
mp_tables:
    ins 'modtables/notelookupgls.bin'
    ins 'modtables/finetune.bin'
MP_TABLEN   = * - mp_tables

; mp_upload (aud_init): the tables to the REU at modi.MP_TABLES, 9 pages
; through MOSBUF (the last one partly beyond them: AD_DATA follows at
; &0B00). Uses A, X, Y, mosPTR, AD_T.
mp_upload:
    lda #<mp_tables
    sta mosPTR
    lda #>mp_tables
    sta mosPTR+1
    lda #<modi.MP_TABLES
    sta AD_T
    lda #>modi.MP_TABLES
    sta AD_T+1
    lda #^modi.MP_TABLES
    sta AD_T+2
mu_page:
    ldy #0
mu_cp:
    lda (mosPTR),y
    sta MOSBUF,y
    iny
    bne mu_cp
    jsr ad_put256
    inc mosPTR+1
    inc AD_T+1
    lda AD_T+1
    cmp #>[modi.MP_TABLES+MP_TABLEN+$FF]
    bcc mu_page
    rts
    .if modi.MP_TABLES+$900 > AD_BANK*$10000+AD_DATA
    .error "The MOD tables run into the samples"
    .endif

; ----------------------------------------------------------------------------
; cmd_modplay
;   Summary: *MODPLAY <file>: load a MOD into the REU and play it in the
;            background (channels 0-3); the sound engine in RAM makes way.
;   Function: rx_openin (its size, 768K at most); the current engine
;            stopped (its kind kept for *MODSTOP); LOAD_REU to &F20000;
;            the image copied in; the header read into its tables
;            (mp_header); the engine started (modi.mi_start).
;   Uses:    A, X, Y, fs*, mosTMP, mosNUM, MOSBUF, SL_*.
cmd_modplay:
    jsr ad_need
    jsr s6_name
    jsr s6_end
    farcall rx_openin, BANK_FS  ; fsTMP = the size
    lda fsTMP+3
    bne mpl_big
    lda fsTMP+2
    cmp #MP_MAX
    bcc mpl_size
    bne mpl_big
    lda fsTMP
    ora fsTMP+1
    beq mpl_size
mpl_big:
    farcall rx_close, BANK_FS
    brk
    dta 198, 'MOD too big (768K)', 0
mpl_size:
    lda fsTMP                   ; (kept: fs_reurest3 uses fsTMP)
    sta SL_SIZE
    lda fsTMP+1
    sta SL_SIZE+1
    lda fsTMP+2
    sta SL_SIZE+2
    jsr mp_quiet                ; the engine in RAM stopped
    lda SL_SIZE                 ; LOAD_REU: the whole file at &F20000
    sta fsCNT
    lda SL_SIZE+1
    sta fsCNT+1
    lda SL_SIZE+2
    sta FR_LENH
    lda #0
    sta fsTMP
    sta fsTMP+1
    sta FR_ONREU
    lda #modi.MP_BANK
    sta fsTMP+2
    farcall fs_reurest3, BANK_FS
    jsr mp_copy                 ; the image to SOUNDRAM
    lda #2                      ; MOD mode
    sta s_mode
    jsr mp_header               ; the tables
    jsr modi.mi_start
    lda #1
    sta snd_on
    rts

; mp_copy: the image (MI_LEN bytes from mi_img, bank ROM) to SOUNDRAM
; through mosPTR/mosPTR2: whole pages, then the rest. Uses A, X, Y.
mp_copy:
    lda #<mi_img
    sta mosPTR
    lda #>mi_img
    sta mosPTR+1
    lda #<SOUNDRAM
    sta mosPTR2
    lda #>SOUNDRAM
    sta mosPTR2+1
    ldx #>MI_LEN
    ldy #0
mc_page:
    cpx #0
    beq mc_rest
mc_pb:
    lda (mosPTR),y
    sta (mosPTR2),y
    iny
    bne mc_pb
    inc mosPTR+1
    inc mosPTR2+1
    dex
    jmp mc_page
mc_rest:
    cpy #<MI_LEN
    beq mc_rts
    lda (mosPTR),y
    sta (mosPTR2),y
    iny
    bne mc_rest
mc_rts:
    rts

; mp_quiet: the engine in RAM silent and out of the interrupt (snd_on 0);
; if it is not the MOD engine, its kind kept for *MODSTOP
mp_quiet:
    lda snd_on
    beq mq_off
    jsr SNDV_STOP
mq_off:
    lda #0
    sta snd_on
    lda s_mode
    cmp #2
    beq mq_rts
    sta mosARGS+1
    ldx #<AD_PREV
    lda #>AD_PREV
    jmp ad_rput
mq_rts:
    rts

; ----------------------------------------------------------------------------
; cmd_modstop
;   Summary: *MODSTOP: the MOD silent, the engine there was before back
;            (SID or BBC mode).
;   Uses:    A, X, Y, fs*, mosPTR, mosPTR2.
cmd_modstop:
    jsr s6_end
    lda snd_on
    beq mps_rts
    lda s_mode
    cmp #2
    bne mps_rts
    jsr SNDV_STOP               ; silent, the 60 Hz timer back
    ldx #<AD_PREV
    lda #>AD_PREV
    jsr ad_rget
    cmp #2
    bcc mps_load
    lda #0
mps_load:
    farcall snd_load, BANK_SND
mps_rts:
    rts

; ----------------------------------------------------------------------------
; mp_header
;   Summary: the module's header (REU &F20000) into the engine's tables:
;            31 or 15 samples (the format id at 1080: M.K., M!K!, 4CHN,
;            FLT4; otherwise 15 if the bytes there are not text, as
;            detectmod), the order table, the number of patterns, per
;            sample its REU address, length, loop and volume.
;   Function: ModPlayer_16k's setmodstructures, reading the REU.
;   Uses:    A, X, Y, mosTMP, mosNUM, MOSBUF, AD_T, SL_*.
MH_N        = SL+20             ; the sample
MH_PAT      = SL+21             ; 2: the patterns' offset
MH_PTR      = SL+23             ; 3: the next sample's REU address
mp_header:
    lda #<1080                  ; the format id
    ldx #>1080
    ldy #4
    jsr mh_get
    ldx #3*4
mh_fmt:
    ldy #3
mh_fc:
    lda MOSBUF,y
    cmp mh_ids,x
    bne mh_fnext
    inx
    dey
    bpl mh_fc
    lda #31
    bne mh_nset
mh_fnext:
    txa                         ; the next id (X at its start + bytes
    and #$FC                    ; matched)
    sec
    sbc #4
    tax
    bpl mh_fmt
    ldy #3                      ; none: text there means 31 samples of an
mh_txt:                         ; unknown kind (not supported)
    lda MOSBUF,y
    cmp #$20
    bcc mh_15
    cmp #$7F
    bcs mh_15
    dey
    bpl mh_txt
    brk
    dta 254, 'Not a ProTracker MOD', 0
mh_15:
    lda #15
mh_nset:
    sta modi.nsamples
    sta MH_N
    lda MH_N                    ; songlenght at 20 + 30n, the orders at +2
    ldx #30
    jsr mh_mul                  ; mosNUM = 30 n
    lda mosNUM
    clc
    adc #20
    pha
    lda mosNUM+1
    adc #0
    tax
    pla
    ldy #1
    jsr mh_get
    lda MOSBUF
    sta modi.songlenght
    lda mosNUM                  ; the order table (128) into the image
    clc
    adc #22
    sta AD_T
    lda mosNUM+1
    adc #0
    sta AD_T+1
    lda #modi.MP_BANK
    sta AD_T+2
    lda #128
    ldx #<modi.mp_order
    ldy #>modi.mp_order
    jsr ad_getn
    lda MH_N                    ; patterns: 1084 (31), 600 (15)
    cmp #31
    bne mh_p15
    lda #<1084
    ldx #>1084
    bne mh_pset
mh_p15:
    lda #<600
    ldx #>600
mh_pset:
    sta modi.patternptr
    stx modi.patternptr+1
    ldy #127                    ; the number of patterns: the highest + 1
    lda #0
mh_max:
    cmp modi.mp_order,y
    bcs mh_mx
    lda modi.mp_order,y
mh_mx:
    dey
    bpl mh_max
    clc
    adc #1
    sta modi.patternsnumber
    lda #0                      ; the first sample: &F2:patterns + n *
    sta MH_PTR                  ; 1024 (n * 1024: n * 4 the middle byte,
    lda modi.patternsnumber     ; n / 64 the high one)
    asl
    asl
    sta MH_PTR+1
    lda modi.patternsnumber
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    sta MH_PTR+2
    lda MH_PTR
    clc
    adc modi.patternptr
    sta MH_PTR
    lda MH_PTR+1
    adc modi.patternptr+1
    sta MH_PTR+1
    lda MH_PTR+2
    adc #modi.MP_BANK
    sta MH_PTR+2
    ldx #31                     ; the tables cleared (32 x 15)
    lda #0
mh_clr:
    sta modi.sampleptrl,x
    sta modi.sampleptrm,x
    sta modi.sampleptrh,x
    sta modi.samplelenl,x
    sta modi.samplelenm,x
    sta modi.samplelenh,x
    sta modi.samplerepal,x
    sta modi.samplerepam,x
    sta modi.samplerepah,x
    sta modi.samplerepbl,x
    sta modi.samplerepbm,x
    sta modi.samplerepbh,x
    sta modi.samplerep,x
    sta modi.samplevol,x
    sta modi.sampleft,x
    dex
    bpl mh_clr
    ldx #0
mh_smp:
    stx MH_N                    ; (the sample index now)
    txa                         ; its 30 bytes at 20 + 30 i -> MOSBUF
    ldx #30
    jsr mh_mul
    lda mosNUM
    clc
    adc #20
    pha
    lda mosNUM+1
    adc #0
    tax
    pla
    ldy #30
    jsr mh_get
    ldx MH_N
    lda MH_PTR                  ; its address
    sta modi.sampleptrl,x
    lda MH_PTR+1
    sta modi.sampleptrm,x
    lda MH_PTR+2
    sta modi.sampleptrh,x
    lda MOSBUF+23               ; length = words * 2
    asl
    sta modi.samplelenl,x
    lda MOSBUF+22
    rol
    sta modi.samplelenm,x
    lda #0
    rol
    sta modi.samplelenh,x
    lda MOSBUF+24               ; finetune
    and #$0F
    sta modi.sampleft,x
    lda MOSBUF+25               ; volume 0-64 -> * 255 / 256
    cmp #65
    bcc mh_vol
    lda #64
mh_vol:
    beq mh_v0
    sec
    sbc #1
mh_v0:
    sta modi.samplevol,x
    lda MH_PTR                  ; the next sample's address
    clc
    adc modi.samplelenl,x
    sta MH_PTR
    lda MH_PTR+1
    adc modi.samplelenm,x
    sta MH_PTR+1
    lda MH_PTR+2
    adc modi.samplelenh,x
    sta MH_PTR+2
    lda MOSBUF+29               ; a loop of 2 words or more
    cmp #2
    bcs mh_rep
    lda MOSBUF+28
    beq mh_next
mh_rep:
    lda #1
    sta modi.samplerep,x
    lda MOSBUF+27               ; loop start = words * 2 (relative)
    asl
    sta modi.samplerepal,x
    lda MOSBUF+26
    rol
    sta modi.samplerepam,x
    lda #0
    rol
    sta modi.samplerepah,x
    lda MOSBUF+29               ; loop end = start + length * 2
    asl
    sta mosTMP
    lda MOSBUF+28
    rol
    sta mosTMP+1
    lda #0
    rol
    sta mosTMP+2
    lda modi.samplerepal,x
    clc
    adc mosTMP
    sta modi.samplerepbl,x
    lda modi.samplerepam,x
    adc mosTMP+1
    sta modi.samplerepbm,x
    lda modi.samplerepah,x
    adc mosTMP+2
    sta modi.samplerepbh,x
mh_next:
    ldx MH_N
    inx
    cpx modi.nsamples
    beq mh_rts
    jmp mh_smp
mh_rts:
    rts

; mh_get: Y bytes (1-255) of the module at offset A/X (low/high) -> MOSBUF
mh_get:
    sta AD_T
    stx AD_T+1
    lda #modi.MP_BANK
    sta AD_T+2
    tya
    ldx #<MOSBUF
    ldy #>MOSBUF
    jmp ad_getn

; mh_mul: mosNUM = A * X (8 x 8 bits). Uses A, X.
mh_mul:
    sta mosTMP
    stx mosTMP+1
    lda #0
    sta mosNUM
    sta mosNUM+1
    ldx #8
mhm_l:
    asl mosNUM
    rol mosNUM+1
    asl mosTMP
    bcc mhm_n
    lda mosNUM
    clc
    adc mosTMP+1
    sta mosNUM
    bcc mhm_n
    inc mosNUM+1
mhm_n:
    dex
    bne mhm_l
    rts

; the format ids, each backwards (compared from its last byte)
mh_ids:
    dta '4TLF'                  ; FLT4
    dta '.K.M'                  ; M.K.
    dta '!K!M'                  ; M!K!
    dta 'NHC4'                  ; 4CHN
