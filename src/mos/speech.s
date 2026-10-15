; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- speech: *SPEECH, *SAY, *SPEAK with the user's own SAM
; (bank 6)
;
; SAM (Software Automatic Mouth, Don't Ask Software 1982) is not part of
; this project (owner, 2026-10-14): *SPEECH LOAD reads the user's copy of
; the C64 package's files into the REU, SAM itself (".sam 1", loaded at
; &9500-&BFFF) and Reciter (".sam 2", &7D00-&947F, English to phonemes).
; Its interface, from the program and groepaz's disassembly of the C64
; SAM (hitmen, 2007): the text at &9A15 ended by &9B; JSR &9A03 speaks
; phonemes, JSR &9A09 runs Reciter on the text first; speed at &BC18,
; pitch &BA3F, throat &97E0, mouth &97E1 (JSR &97E2 applies those two).
;
; SAM's memory is BBC BASIC's RAM copy and the top of the program area,
; its zero page BASIC's: the speaking routine (sv_*, copied to MOSBUF and
; called with the cartridge off) saves zero page and &7D00-&7FFF to the
; REU, copies SAM in, speaks at 1 MHz (SAM's timing; it blanks the screen
; itself), copies BBC BASIC back from cartridge bank 1 (copy_basic) and
; restores the rest. docs/DESIGN_ACORN.md 4.
;
; REU, the last bank (as *SPOOL's, rd_lastbank): &BCF0-&FFEF the image of
; &7D00-&BFFF, &FFF0 the header ("SAM", what is loaded, speed, pitch,
; throat, mouth); *SPOOL stops at &BCF0. REU bank 0 &3880: the saved
; zero page (254 bytes) and &7D00-&7FFF (768).
;
; ----------------------------------------------------------------------------

    .local spch

SV_IMG      = $BCF0             ; the image of &7D00-&BFFF (last bank)
SV_IMGLEN   = $C000-$7D00
SV_HDR      = $FFF0             ; header (16)
SV_SAVE     = $3880             ; REU bank 0: zero page, then &7D00-&7FFF
SV_TEXT     = $0600             ; the text (BASIC's string buffer, free
SV_TMAX     = 230               ; between statements; HDR follows)

H_MAGIC     = 0                 ; header: "SAM"
H_HAVE      = 3                 ; bit 0 SAM, bit 1 Reciter
H_SPEED     = 4
H_PITCH     = 5
H_THROAT    = 6
H_MOUTH     = 7
HDR         = $06F0             ; the header while a command works (16;
                                ; not MOSBUF+$F0: the RAM disk saves its
                                ; registers there, rd_sv)
SVV         = $0248             ; scratch (9; not MOSBUF+$E0-$EA: the RAM
                                ; disk's BGET# uses it)
SV_RA       = $0251             ; 2: the REU address being loaded

S_SAY       = $9A03             ; SAM's entries
S_RECITE    = $9A09
S_BUF       = $9A15
S_SPEED     = $BC18
S_PITCH     = $BA3F
S_THROAT    = $97E0
S_MOUTH     = $97E1
S_KNOBS     = $97E2

; ----------------------------------------------------------------------------
; cmd_speech
;   Summary: *SPEECH: what is loaded and the settings; *SPEECH LOAD f [f]
;            the user's SAM and Reciter files (told apart by their load
;            address, &9500 and &7D00); *SPEECH SPEED|PITCH|THROAT|MOUTH n
;            (SAM's defaults 72, 64, 128, 128; speed: bigger is slower,
;            pitch: smaller is higher).
;   Input:   mosPTR/Y.  Output: text, the REU.  Uses: A, X, Y, MOSBUF,
;            fs*, mosNUM.
cmd_speech:
    jsr sv_need
    jsr sv_hdrget
    jsr s6_skipsp
    cmp #13
    bne csv_word
    jmp sv_status
csv_word:
    lda #<wd_load
    ldx #>wd_load
    jsr s6_word
    bcc csv_set
    jmp sv_load
csv_set:
    ldx #3                      ; SPEED, PITCH, THROAT, MOUTH
csv_find:
    stx MOSBUF+$E0
    lda sv_wlo,x
    pha
    lda sv_whi,x
    tax
    pla
    jsr s6_word
    bcs csv_num
    ldx MOSBUF+$E0
    dex
    bpl csv_find
    jmp s6_syntax
csv_num:
    jsr s6_need
    jsr s6_end
    lda mosNUM+1
    beq csv_ok
    brk
    dta 252, 'Bad number', 0
csv_ok:
    lda MOSBUF+$E0
    clc
    adc #H_SPEED
    tax
    lda mosNUM
    sta HDR,x
    jmp sv_hdrput
sv_wlo:
    dta <wd_speed, <wd_pitch, <wd_throat, <wd_mouth
sv_whi:
    dta >wd_speed, >wd_pitch, >wd_throat, >wd_mouth
wd_load     dta 'LOAD', 0
wd_speed    dta 'SPEED', 0
wd_pitch    dta 'PITCH', 0
wd_throat   dta 'THROAT', 0
wd_mouth    dta 'MOUTH', 0

; sv_status: "SAM loaded, Reciter loaded" and the four settings
sv_status:
    lda HDR+H_HAVE
    and #1
    bne svs_sam
    jsr s6_text
    dta 'No SAM loaded (*SPEECH LOAD)', 13, 0
    rts
svs_sam:
    jsr s6_text
    dta 'SAM loaded', 0
    lda HDR+H_HAVE
    and #2
    beq svs_nor
    jsr s6_text
    dta ', Reciter loaded', 0
svs_nor:
    jsr s6_text
    dta 13, 'Speed ', 0
    lda HDR+H_SPEED
    jsr sv_dec
    jsr s6_text
    dta ', pitch ', 0
    lda HDR+H_PITCH
    jsr sv_dec
    jsr s6_text
    dta ', throat ', 0
    lda HDR+H_THROAT
    jsr sv_dec
    jsr s6_text
    dta ', mouth ', 0
    lda HDR+H_MOUTH
    jsr sv_dec
    jmp OSNEWL
; sv_dec: A in decimal
sv_dec:
    ldx #0
    stx MOSBUF+$E1
svd_100:
    cmp #100
    bcc svd_10
    sbc #100
    inx
    bne svd_100
svd_10:
    jsr svd_dig
    ldx #0
svd_t:
    cmp #10
    bcc svd_1
    sbc #10
    inx
    bne svd_t
svd_1:
    jsr svd_dig
    ora #'0'
    jmp OSWRCH
svd_dig:                        ; X as a digit unless a leading zero
    pha
    txa
    ora MOSBUF+$E1
    beq svd_skip
    sta MOSBUF+$E1
    txa
    ora #'0'
    jsr OSWRCH
svd_skip:
    pla
    rts

; ----------------------------------------------------------------------------
; sv_load: *SPEECH LOAD f [f]: each file a C64 program file: load address
; &9500 (SAM, up to &BFFF) or &7D00 (Reciter, up to &947F); into the
; image at its place in one transfer (fs_reuopen/fs_reurest, bank 2)
sv_load:
    jsr sv_file
    jsr s6_skipsp
    cmp #13
    beq svl_done
    jsr sv_file
svl_done:
    jsr s6_end
    jmp sv_hdrput

; svf_check: load address SVV+6/+7: &9500 (SAM) or &7D00 (Reciter): its
; bit in HDR+H_HAVE, C = 0; else C = 1
svf_check:
    ldx #1                      ; SAM (bit 0) or Reciter (bit 1)?
    lda SVV+7
    cmp #>$9500
    bne svc_nsam
    lda SVV+6
    cmp #<$9500
    beq svc_kind
svc_nsam:
    ldx #2
    lda SVV+7
    cmp #>$7D00
    bne svc_bad
    lda SVV+6
    cmp #<$7D00
    beq svc_kind
svc_bad:
    sec
    rts
svc_kind:
    txa
    ora HDR+H_HAVE
    sta HDR+H_HAVE
    clc
    rts

; svf_addr: SV_RA = SV_IMG + load address (SVV+6/+7) - &7D00
svf_addr:
    lda SVV+7
    sec
    sbc #>$7D00
    sta SV_RA+1
    lda SVV+6
    clc
    adc #<SV_IMG
    sta SV_RA
    lda SV_RA+1
    adc #>SV_IMG
    sta SV_RA+1
    rts

; svf_fast: the file opened by fs_reuopen (bank 2), its load address in
; fsADDR: checked, then the rest loaded straight into the REU
svf_fast:
    ldy SVV+3                   ; the line as it was
    lda SVV+4
    sta (mosPTR),y
    lda fsADDR
    sta SVV+6
    lda fsADDR+1
    sta SVV+7
    jsr svf_check               ; SAM or Reciter? (X: its bit; C = 1 no)
    bcc svff_ok
    farcall fs_reuclose, BANK_FS
    jmp svf_badmsg
svff_ok:
    jsr svf_addr                ; SV_RA
    lda SV_RA
    sta fsTMP
    lda SV_RA+1
    sta fsTMP+1
    jsr sv_lastbank
    sta fsTMP+2
    lda #<SV_HDR                ; room: up to the header
    sec
    sbc SV_RA
    sta fsCNT
    lda #>SV_HDR
    sbc SV_RA+1
    sta fsCNT+1
    farcall fs_reurest, BANK_FS
    ldy SVV+3
    rts

; sv_file: one file at mosPTR/Y (Y past it). Uses SVV+0-8.
sv_file:
    jsr s6_skipsp
    sty SVV+2              ; the name's start; its end
svf_end:
    lda (mosPTR),y
    cmp #13
    beq svf_got
    cmp #' '
    beq svf_got
    iny
    bne svf_end
svf_got:
    sty SVV+3
    lda (mosPTR),y              ; CR in place of the space for OSFIND
    sta SVV+4
    lda #13
    sta (mosPTR),y
    lda SVV+2
    clc
    adc mosPTR
    sta fsPTR
    tax
    lda mosPTR+1
    adc #0
    sta fsPTR+1
    tay
    stx SVV                     ; (the name's address)
    sty SVV+1
    farcall fs_reuopen, BANK_FS ; LOAD_REU from the drives, or a copy
    jmp svf_fast                ; within the REU from /REU (bank 2, 5)
svf_badmsg:
    brk
    dta 254, 'Not SAM (&9500) or Reciter (&7D00)', 0

; ----------------------------------------------------------------------------
; cmd_say / cmd_speak
;   Summary: *SAY text: English (through Reciter); *SPEAK phonemes:
;            SAM's own spelling (e.g. *SPEAK HEH4LOW). Letters are made
;            capitals; up to 230 characters.
;   Function: the text to SV_TEXT ending in &9B, the settings and the
;            DMA list into the speaking routine (sv_run), which is copied
;            to MOSBUF and called with the cartridge off (BANK_RAM).
;   Input:   mosPTR/Y.  Output: speech.  Uses: A, X, Y, MOSBUF, SV_TEXT.
cmd_say:
    lda #2                      ; (needs Reciter)
    bne csa_go
cmd_speak:
    lda #1
csa_go:
    sta SVV
    jsr sv_need
    jsr sv_hdrget
    lda HDR+H_HAVE
    and SVV
    bne csa_have
    lda SVV
    cmp #2
    beq csa_norec
    brk
    dta 254, 'No SAM loaded (*SPEECH LOAD)', 0
csa_norec:
    brk
    dta 254, 'No Reciter loaded: use *SPEAK', 0
csa_have:
    lda HDR+H_HAVE              ; (SAM itself always)
    and #1
    bne csa_text
    brk
    dta 254, 'No SAM loaded (*SPEECH LOAD)', 0
csa_text:
    jsr s6_skipsp
    ldx #0
csa_c:
    lda (mosPTR),y
    cmp #13
    beq csa_end
    cmp #'a'
    bcc csa_up
    cmp #'z'+1
    bcs csa_up
    and #$DF
csa_up:
    sta SV_TEXT,x
    inx
    iny
    cpx #SV_TMAX
    bcc csa_c
csa_end:
    lda #$9B
    sta SV_TEXT,x
    lda SVV                     ; English: words without a vowel spelt
    cmp #2                      ; out ("BBC" -> "B B C"), which Reciter
    bne csa_copy                ; would otherwise skip
    jsr sv_spell
csa_copy:
    ldx #0                      ; the routine into MOSBUF (over 128
csa_cp:                         ; bytes: counted up)
    lda sv_load_img,x
    sta MOSBUF,x
    inx
    cpx #sv_len
    bne csa_cp
    lda #<S_SAY                 ; which entry
    ldx #>S_SAY
    ldy SVV
    cpy #2
    bne csa_ent
    lda #<S_RECITE
    ldx #>S_RECITE
csa_ent:
    sta sv.ENTRY+1
    stx sv.ENTRY+2
    lda HDR+H_SPEED             ; the settings
    sta sv.P_SPEED
    lda HDR+H_PITCH
    sta sv.P_PITCH
    lda HDR+H_THROAT
    sta sv.P_THROAT
    lda HDR+H_MOUTH
    sta sv.P_MOUTH
    jsr sv_lastbank             ; the image's bank
    sta sv.D_IMGBANK
    farcall MOSBUF, BANK_RAM
    ldx #$17                    ; the SID as the sound engine's reset
    lda #0                      ; leaves it (SAM leaves its last sample
csa_sid:                        ; and voice settings: a level that the
    sta $D400,x                 ; next SOUND would sit on)
    dex
    bpl csa_sid
    lda #$0F
    sta $D418
    rts

; sv_spell: SV_TEXT (ended by &9B) rewritten: a word of two or more
; letters without a vowel (A E I O U Y) gets a space between its letters;
; built in MOSBUF (up to 230 characters), then copied back.
; Uses: A, X, Y, SVV+1-3, MOSBUF+$00-$E7.
SP_OMAX     = 230
sv_spell:
    ldx #0                      ; X: SV_TEXT, Y: MOSBUF
    ldy #0
sps_next:
    lda SV_TEXT,x
    cmp #$9B
    beq sps_end
    jsr sps_letter
    bcs sps_word
    jsr sps_put                 ; not a letter: as it is
    inx
    bne sps_next
sps_word:
    stx SVV+1                   ; the word: its start, a vowel in it?
    lda #0
    sta SVV+3
sps_scan:
    lda SV_TEXT,x
    jsr sps_letter
    bcc sps_wend
    jsr sps_vowel
    bcc sps_nv
    inc SVV+3
sps_nv:
    inx
    bne sps_scan
sps_wend:
    stx SVV+2                   ; its end (past it)
    txa
    sec
    sbc SVV+1
    cmp #2                      ; one letter, or a vowel: as it is
    bcc sps_copyw
    lda SVV+3
    bne sps_copyw
    ldx SVV+1                   ; spelt: a space between the letters
sps_sp:
    lda SV_TEXT,x
    jsr sps_put
    inx
    cpx SVV+2
    beq sps_done
    lda #' '
    jsr sps_put
    jmp sps_sp
sps_copyw:
    ldx SVV+1
sps_cw:
    cpx SVV+2
    beq sps_done
    lda SV_TEXT,x
    jsr sps_put
    inx
    bne sps_cw
sps_done:
    ldx SVV+2
    jmp sps_next
sps_end:
    lda #$9B
    sta MOSBUF,y
    ldx #0                      ; back into SV_TEXT
sps_back:
    lda MOSBUF,x
    sta SV_TEXT,x
    inx
    cmp #$9B
    bne sps_back
    rts
; sps_put: A into MOSBUF at Y (full: dropped)
sps_put:
    cpy #SP_OMAX
    bcs spp_full
    sta MOSBUF,y
    iny
spp_full:
    rts
; sps_vowel: C = 1 if A is a vowel (A E I O U Y); X, Y kept
sps_vowel:
    cmp #'A'
    beq spv_yes
    cmp #'E'
    beq spv_yes
    cmp #'I'
    beq spv_yes
    cmp #'O'
    beq spv_yes
    cmp #'U'
    beq spv_yes
    cmp #'Y'
    beq spv_yes
    clc
    rts
spv_yes:
    sec
    rts
; sps_letter: C = 1 if A is a capital letter
sps_letter:
    cmp #'A'
    bcc spl_no
    cmp #'Z'+1
    bcs spl_no
    sec
    rts
spl_no:
    clc
    rts

; ----------------------------------------------------------------------------
; The speaking routine, run at MOSBUF with the cartridge off. DMA list:
; C64 address, REU address (3), length, command.
sv_load_img:
    .local sv
    org MOSBUF, sv_load_img
    php
    sei
    ldx #0                      ; save zero page, &7D00-&7FFF; SAM in
    jsr dmas
    ldx #3*8
    jsr dmas
    ldx #2*8
    jsr dmas
    ldy #0                      ; the text
tx:
    lda SV_TEXT,y
    sta S_BUF,y
    iny
    cmp #$9B
    bne tx
P_SPEED = *+1
    lda #$48
    sta S_SPEED
P_PITCH = *+1
    lda #$40
    sta S_PITCH
P_THROAT = *+1
    lda #$80
    sta S_THROAT
P_MOUTH = *+1
    lda #$80
    sta S_MOUTH
    jsr S_KNOBS
    lda #$36                    ; ($01 as BANK_RAM: S_KNOBS changes it)
    sta $01
    lda $D011                   ; (SAM blanks the screen and sets $D011
    pha                         ; again: the mode's own value kept)
    lda U64_TURBO               ; 1 MHz: SAM's timing
    pha
    lda U64_TURBOEN
    pha
    ldx turbo_state
    cpx #2
    bne t1
    lda #0
    sta U64_TURBO
t1:
    cpx #1
    bne t2
    and #$FE
    sta U64_TURBOEN
t2:
ENTRY:
    jsr S_SAY
    pla                         ; the turbo as it was
    ldx turbo_state
    cpx #1
    bne r1
    sta U64_TURBOEN
r1:
    pla
    cpx #2
    bne r2
    sta U64_TURBO
r2:
    pla
    sta $D011
    lda #$36
    sta $01
    jsr copy_basic              ; BBC BASIC back from bank 1 (ends with
                                ; bank 0 in; the DMA below does not mind,
                                ; the caller's trampoline maps its bank)
    ldx #4*8                    ; &7D00-&7FFF, then zero page (last)
    jsr dmas
    ldx #1*8
    jsr dmas
    plp
    rts
; dmas: the DMA list entry at X
dmas:
    lda list,x
    sta REU_C64
    lda list+1,x
    sta REU_C64+1
    lda list+2,x
    sta REU_ADDR
    lda list+3,x
    sta REU_ADDR+1
    lda list+4,x
    sta REU_BANK
    lda list+5,x
    sta REU_LEN
    lda list+6,x
    sta REU_LEN+1
    lda #0
    sta REU_CTRL
    lda list+7,x
    sta REU_CMD
    rts
list:
    dta a($0002), a(SV_SAVE), 0, a(254), REU_TO_REU          ; 0 zp out
    dta a($0002), a(SV_SAVE), 0, a(254), REU_TO_C64          ; 1 zp in
    dta a($7D00), a(SV_IMG)
D_IMGBANK:
    dta 0, a(SV_IMGLEN), REU_TO_C64                         ; 2 SAM in
    dta a($7D00), a(SV_SAVE+256), 0, a($0300), REU_TO_REU   ; 3 out
    dta a($7D00), a(SV_SAVE+256), 0, a($0300), REU_TO_C64   ; 4 in
LEN         = * - MOSBUF
    .endl
sv_len      = sv.LEN
    org sv_load_img + sv_len
    .if sv_len > $100
    .error "The speaking routine overflows MOSBUF"
    .endif

; ----------------------------------------------------------------------------
; helpers

; sv_need: an REU ("Speech needs an REU")
sv_need:
    jsr s6_hasreu
    bne svn_rts
    brk
    dta 254, 'Speech needs an REU', 0
svn_rts:
    rts

; sv_lastbank: A = the REU's last bank (as rd_lastbank)
sv_lastbank:
    lda reu_banks+1
    bne slb_16
    lda reu_banks
    sec
    sbc #1
    rts
slb_16:
    lda #$FF
    rts

; sv_hdrget / sv_hdrput: the header <-> HDR; one without "SAM" reads as
; nothing loaded with the defaults
sv_hdrget:
    lda #REU_TO_C64
    jsr sv_hdrdma
    lda HDR+H_MAGIC
    cmp #'S'
    bne svh_new
    lda HDR+H_MAGIC+1
    cmp #'A'
    bne svh_new
    lda HDR+H_MAGIC+2
    cmp #'M'
    beq svh_rts
svh_new:
    ldx #15
    lda #0
svh_z:
    sta HDR,x
    dex
    bpl svh_z
    lda #'S'
    sta HDR+H_MAGIC
    lda #'A'
    sta HDR+H_MAGIC+1
    lda #'M'
    sta HDR+H_MAGIC+2
    lda #72
    sta HDR+H_SPEED
    lda #64
    sta HDR+H_PITCH
    lda #128
    sta HDR+H_THROAT
    sta HDR+H_MOUTH
svh_rts:
    rts
sv_hdrput:
    lda #REU_TO_REU
sv_hdrdma:
    pha
    lda #<HDR
    sta fsADDR
    lda #>HDR
    sta fsADDR+1
    lda #<SV_HDR
    sta fsTMP
    lda #>SV_HDR
    sta fsTMP+1
    jsr sv_lastbank
    sta fsTMP+2
    lda #16
    sta fsLEN
    lda #0
    sta fsLEN+1
    pla
; sv_dma: fsADDR <-> fsTMP/+1/+2, fsLEN; command A (interrupts off)
sv_dma:
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

    .endl
