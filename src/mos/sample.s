; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- Ultimate Audio samples: *SAMPLE and SOUND on voices
; 24-30 (bank 10, inside .local aud; 1.0.0 item 8a, step 1)
;
; Owner's decisions (2026-10-17, PLAN.md 27 item 8a): samples in the REU
; below *MAP's bank (16 MB REU: &EE0000-&F1FFFF); 8-bit mono WAV (rate
; from the header, unsigned data made signed on load) and raw signed
; 8-bit files; SOUND 24+c, A, P, D plays on Ultimate Audio channel c
; (0-6): A = sample n (1-32, + 256 * level 1-15 for its volume), -15..-1
; the channel's last sample at that volume, 0 silence; P the BBC pitch
; scale, 53 = the sample's own rate (4 steps a semitone); D in 1/20 s
; (0: to the end, 255: looped). The length plays out in the hardware: D
; becomes a byte count, so no interrupt is involved.
;
; Ultimate Audio registers (per channel at &DF20 + 32c), big-endian, as
; ultimate-uci-oscar64's ultimate_audio_lib.c writes them (after
; ModPlayer_16k by Freshness/6510nl, CSDb release 131522): +0 control
; (1 start, 2 loop between the loop points, 4 the channel's interrupt:
; measured 2026-10-17, not the library's "restart"; 0 stop), +1 volume
; (0-63), +2 pan, +4 start (&01, then the REU address high, middle,
; low), +9 length (3), +14 rate (2: 6.25 MHz / Hz), +17 / +21 loop
; start and end (relative to the start), +31 interrupt acknowledge.
; Samples are signed 8-bit (MOD sample data plays as it is).
;
; ----------------------------------------------------------------------------

UA_BASE     = $DF20             ; channel c at UA_BASE + 32 c
UA_CTRL     = 0
UA_VOL      = 1
UA_PAN      = 2
UA_START    = 4
UA_LEN      = 9
UA_RATE     = 14
UA_RPA      = 17                ; loop start (3), relative
UA_RPB      = 21                ; loop end (3), relative
UA_IRQ      = 31
UA_STATUS   = 0                 ; (read)

AD_BANK     = $EE               ; the sample area's REU bank (16 MB REU)
AD_DIR      = $0000             ; 32 x 8: start (3), length (3), rate (2)
AD_FREE     = $0100             ; 3: the next free REU address
AD_LAST     = $0103             ; 7: per channel the last sample (0: none)
AD_OK       = $010A             ; 1: Ultimate Audio found (aud_init)
AD_DATA     = $0B00             ; sample data from &EE0B00 (the MOD
                                ; engine's tables at &EE0200, modplay.s) ...
AD_ENDBANK  = $F2               ; ... to &F1FFFF (the MOD from &F20000)
SA_MAX      = 32

; zero page while a command works (foreground MOS only)
AD_T        = mosTMP            ; 4: scratch, the dividend / product
AD_N        = mosNUM            ; 2

; ----------------------------------------------------------------------------
; aud_init
;   Summary: at the cold start: is there Ultimate Audio (16 MB REU only)?
;            The sample directory emptied.
;   Function: as ultimate_audio_lib.c's uii_audio_detect (from
;            ModPlayer_16k's detectaudio): all channels stopped, channel
;            0's status must stay 0, then a silent looping sample must
;            raise it to 1.
;   Uses:    A, X, Y, mosTMP, MOSBUF.
aud_init:
    lda reu_banks+1             ; (256 banks: 16 MB)
    bne ai_16
    rts
ai_16:
    ldx #0                      ; MOSBUF: the area's header, all 0
    txa
ai_clr:
    sta MOSBUF,x
    inx
    bne ai_clr
    jsr ad_detect
    sta MOSBUF+<AD_OK
    lda #<AD_DATA               ; the free pointer
    sta MOSBUF+<AD_FREE
    lda #>AD_DATA
    sta MOSBUF+<[AD_FREE+1]
    lda #AD_BANK
    sta MOSBUF+<[AD_FREE+2]
    jsr ad_hdrput               ; the header page, then the directory
    ldx #0                      ; (zeros)
    txa
ai_c2:
    sta MOSBUF,x
    inx
    bne ai_c2
    jsr ad_dirput
    jmp mp_upload               ; the MOD engine's tables (modplay.s)

; ad_detect: A = 1 if Ultimate Audio answers, 0 if not (uii_audio_detect)
ad_detect:
    php
    sei
    ldx #6*32                   ; all channels stopped
    lda #0
add_stop:
    sta UA_BASE+UA_CTRL,x
    txa
    sec
    sbc #32
    tax
    lda #0
    bcs add_stop
    lda #$FF
    sta UA_BASE+UA_IRQ
    ldx #0                      ; status 0 for 256 reads
add_z:
    lda UA_BASE+UA_STATUS
    bne add_no
    dex
    bne add_z
    lda #0                      ; a silent looping 256-byte sample at
    sta UA_BASE+UA_VOL          ; REU 0, rate 1
    lda #$01
    sta UA_BASE+UA_START
    lda #0
    sta UA_BASE+UA_START+1
    sta UA_BASE+UA_START+2
    sta UA_BASE+UA_START+3
    sta UA_BASE+UA_RATE
    sta UA_BASE+UA_LEN
    lda #1
    sta UA_BASE+UA_RATE+1
    sta UA_BASE+UA_LEN+1
    lda #0
    sta UA_BASE+UA_LEN+2
    lda #5
    sta UA_BASE+UA_CTRL
    ldx #$80                    ; the status turns 1 ...
add_w:
    lda UA_BASE+UA_STATUS
    bne add_one
    dex
    bne add_w
add_one:
    lda UA_BASE+UA_STATUS       ; ... and stays 1
    cmp #1
    bne add_no
    dex
    bne add_one
    lda #0
    sta UA_BASE+UA_CTRL
    lda #$FF
    sta UA_BASE+UA_IRQ
    plp
    lda #1
    rts
add_no:
    lda #0
    sta UA_BASE+UA_CTRL
    plp
    lda #0
    rts

; ----------------------------------------------------------------------------
; cmd_sample
;   Summary: *SAMPLE LOAD n file [rate], *SAMPLE CLEAR, *SAMPLE (the
;            list).
;   Uses:    A, X, Y, fs*, mosTMP, mosNUM, MOSBUF.
cmd_sample:
    jsr ad_need
    lda #<sw_load
    ldx #>sw_load
    jsr s6_word
    bcc cs_clear
    jmp sa_load
cs_clear:
    lda #<sw_clear
    ldx #>sw_clear
    jsr s6_word
    bcc cs_list
    jsr s6_end
    jmp aud_init
cs_list:
    jsr s6_end
    jsr ad_dirget                  ; the directory -> MOSBUF
    ldx #0                      ; each sample: n, length, rate in Hz
csl_n:
    stx CL_X
    txa
    asl
    asl
    asl
    tay
    lda MOSBUF+3,y
    ora MOSBUF+4,y
    ora MOSBUF+5,y
    beq csl_next
    sty CL_Y
    lda CL_X                    ; "n  "
    clc
    adc #1
    jsr s6_dec8
    jsr s6_text
    dta '  ', 0
    ldy CL_Y                    ; the length (to 64K shown; 3 bytes)
    lda MOSBUF+3,y
    sta mosTMP
    lda MOSBUF+4,y
    sta mosTMP+1
    lda MOSBUF+5,y
    beq csl_len
    lda #$FF
    sta mosTMP
    sta mosTMP+1
csl_len:
    jsr s6_dec16
    jsr s6_text
    dta ' bytes  ', 0
    ldy CL_Y                    ; Hz = 6250000 / rate
    lda MOSBUF+6,y
    sta AD_N
    lda MOSBUF+7,y
    sta AD_N+1
    jsr ad_hz
    jsr s6_dec16
    jsr s6_text
    dta ' Hz', 13, 0
csl_next:
    ldx CL_X
    inx
    cpx #SA_MAX
    bcc csl_n
    rts
sw_load     dta 'LOAD', 0
sw_clear    dta 'CLEAR', 0

; ad_need: "Audio needs a 16 MB REU" / "No Ultimate Audio" unless both
ad_need:
    lda reu_banks+1
    bne adn_reu
    brk
    dta 189, 'Audio needs a 16 MB REU', 0
adn_reu:
    ldx #<AD_OK
    lda #>AD_OK
    jsr ad_rget
    bne adn_rts
    brk
    dta 189, 'No Ultimate Audio', 0
adn_rts:
    rts

; ----------------------------------------------------------------------------
; sa_load
;   Summary: *SAMPLE LOAD n file [rate]: the file into the sample area
;            as sample n (1-32): a WAV (8-bit mono; rate from its header,
;            the data made signed) or raw signed 8-bit at rate Hz (8000
;            when not given).
;   Function: rx_openin (its size), room checked, LOAD_REU into the area
;            at the free pointer (fs_reurest3 on the open file); a WAV's
;            header read back (MOSBUF), its data chunk found and made
;            signed (eor &80, a page at a time).
;   Uses:    A, X, Y, fs*, mosTMP, mosNUM, MOSBUF, SL_*.
SL          = $06E0             ; state (the top of BASIC's string buffer,
SL_N        = SL+0              ; free while a command works)
SL_RATE     = SL+1              ; 2: the given rate in Hz (0: none)
SL_AT       = SL+3              ; 3: where the file goes
SL_SIZE     = SL+6              ; 3: the file's size
SL_START    = SL+9              ; 3: the sample's start
SL_LEN      = SL+12             ; 3: its length
SL_UA       = SL+15             ; 2: its UA rate
CL_X        = SL+20             ; *SAMPLE's list: the sample
CL_Y        = SL+21             ; and its entry's offset
sa_load:
    jsr s6_need                 ; n
    lda mosNUM+1
    bne sl_badn
    lda mosNUM
    beq sl_badn
    cmp #SA_MAX+1
    bcc sl_num
sl_badn:
    brk
    dta 254, 'Samples 1-32', 0
sl_num:
    sta SL_N
    jsr s6_name                 ; the file
    lda fsPTR
    pha
    lda fsPTR+1
    pha
    lda fsLEN
    pha
    lda #0                      ; the rate, if given
    sta SL_RATE
    sta SL_RATE+1
    jsr s6_skipsp
    cmp #13
    beq sl_open
    jsr s6_need
    lda mosNUM
    sta SL_RATE
    lda mosNUM+1
    sta SL_RATE+1
    jsr s6_end
sl_open:
    pla
    sta fsLEN
    pla
    sta fsPTR+1
    pla
    sta fsPTR
    lda #0
    sta fsLEN+1
    farcall rx_openin, BANK_FS  ; fsTMP = the size (32 bits)
    lda fsTMP
    sta SL_SIZE
    lda fsTMP+1
    sta SL_SIZE+1
    lda fsTMP+2
    sta SL_SIZE+2
    jsr ad_hdr                  ; the free pointer
    lda MOSBUF+<AD_FREE
    sta SL_AT
    lda MOSBUF+<[AD_FREE+1]
    sta SL_AT+1
    lda MOSBUF+<[AD_FREE+2]
    sta SL_AT+2
    lda fsTMP+3                 ; room: free + size <= &F20000
    bne sl_room
    lda SL_AT
    clc
    adc SL_SIZE
    lda SL_AT+1
    adc SL_SIZE+1
    lda SL_AT+2
    adc SL_SIZE+2
    bcs sl_room
    cmp #AD_ENDBANK
    bcc sl_fits
    bne sl_room
    lda SL_AT                   ; (exactly &F20000: fits)
    clc
    adc SL_SIZE
    bne sl_room
    lda SL_AT+1
    adc SL_SIZE+1
    beq sl_fits
sl_room:
    farcall rx_close, BANK_FS
    brk
    dta 198, 'No room for samples (*SAMPLE CLEAR)', 0
sl_fits:
    lda SL_SIZE                 ; LOAD_REU: the whole file at SL_AT
    sta fsCNT
    lda SL_SIZE+1
    sta fsCNT+1
    lda SL_SIZE+2
    sta FR_LENH
    lda SL_AT
    sta fsTMP
    lda SL_AT+1
    sta fsTMP+1
    lda SL_AT+2
    sta fsTMP+2
    lda #0                      ; (an Ultimate drive's file)
    sta FR_ONREU
    farcall fs_reurest3, BANK_FS
    ldx #2                      ; raw: the whole file at the given rate
sl_raw:
    lda SL_AT,x
    sta SL_START,x
    lda SL_SIZE,x
    sta SL_LEN,x
    dex
    bpl sl_raw
    jsr sl_wav                  ; a WAV: its data, rate, made signed
    lda SL_RATE                 ; the UA rate: 6250000 / Hz (8000 if
    ora SL_RATE+1               ; none given)
    bne sl_hz
    lda #<8000
    sta SL_RATE
    lda #>8000
    sta SL_RATE+1
sl_hz:
    lda SL_RATE
    sta AD_N
    lda SL_RATE+1
    sta AD_N+1
    jsr ad_hz                   ; (mosTMP: 6250000 / AD_N)
    lda mosTMP
    sta SL_UA
    lda mosTMP+1
    sta SL_UA+1
    jsr ad_dirget                  ; the entry
    lda SL_N
    sec
    sbc #1
    asl
    asl
    asl
    tax
    ldy #0
sl_ent:
    lda SL_START,y              ; (start 3, length 3, rate 2: SL_START
    sta MOSBUF,x                ; .. SL_UA in a row)
    inx
    iny
    cpy #8
    bne sl_ent
    jsr ad_dirput
    jsr ad_hdr                  ; free += size
    lda SL_AT
    clc
    adc SL_SIZE
    sta MOSBUF+<AD_FREE
    lda SL_AT+1
    adc SL_SIZE+1
    sta MOSBUF+<[AD_FREE+1]
    lda SL_AT+2
    adc SL_SIZE+2
    sta MOSBUF+<[AD_FREE+2]
    jmp ad_hdrput

; sl_wav: a WAV at SL_AT ("RIFF", "WAVE"): SL_START, SL_LEN = its data
; chunk, SL_RATE its rate; 8-bit mono PCM only ("Not 8-bit mono WAV");
; the data made signed. Not a WAV: nothing.
sl_wav:
    lda SL_AT                   ; the first 256 bytes -> MOSBUF
    sta AD_T
    lda SL_AT+1
    sta AD_T+1
    lda SL_AT+2
    sta AD_T+2
    jsr ad_get256
    ldx #3
slw_riff:
    lda MOSBUF,x
    cmp slw_r,x
    bne slw_rts
    lda MOSBUF+8,x
    cmp slw_w,x
    bne slw_rts
    dex
    bpl slw_riff
    ldx #12                     ; the chunks: id (4), size (4 LE)
slw_chunk:
    cpx #248
    bcs slw_bad
    lda MOSBUF,x
    cmp #'f'
    beq slw_fmt
    cmp #'d'
    beq slw_data
slw_skip:
    lda MOSBUF+4,x              ; past it: 8 + size (even)
    clc
    adc #8
    sta AD_N
    lda MOSBUF+5,x
    adc #0
    ora MOSBUF+6,x
    ora MOSBUF+7,x
    bne slw_bad                 ; (a chunk over 255 bytes before data)
    lda AD_N
    lsr                         ; (odd: a pad byte)
    lda AD_N
    adc #0
    sta AD_N
    txa
    clc
    adc AD_N
    bcs slw_bad
    tax
    jmp slw_chunk
slw_rts:
    rts
slw_bad:
    brk
    dta 254, 'Not 8-bit mono WAV', 0
slw_fmt:
    lda MOSBUF+1,x              ; "fmt ": PCM (1), 1 channel, 8 bits
    cmp #'m'
    bne slw_skip
    lda MOSBUF+8,x
    cmp #1
    bne slw_bad
    lda MOSBUF+10,x
    cmp #1
    bne slw_bad
    lda MOSBUF+22,x
    cmp #8
    bne slw_bad
    lda SL_RATE                 ; its rate, unless one was given
    ora SL_RATE+1
    bne slw_skip
    lda MOSBUF+12,x
    sta SL_RATE
    lda MOSBUF+13,x
    sta SL_RATE+1
    jmp slw_skip
slw_data:
    lda MOSBUF+1,x              ; "data": its start and length
    cmp #'a'
    bne slw_skip
    txa
    clc
    adc #8
    adc SL_AT
    sta SL_START
    lda SL_AT+1
    adc #0
    sta SL_START+1
    lda SL_AT+2
    adc #0
    sta SL_START+2
    lda MOSBUF+4,x
    sta SL_LEN
    lda MOSBUF+5,x
    sta SL_LEN+1
    lda MOSBUF+6,x
    sta SL_LEN+2
    ; (fall through: made signed)

; sl_signed: SL_LEN bytes at SL_START: eor &80, a page at a time through
; MOSBUF (unsigned 8-bit WAV data -> signed)
sl_signed:
    lda SL_START
    sta AD_T
    lda SL_START+1
    sta AD_T+1
    lda SL_START+2
    sta AD_T+2
    lda SL_LEN                  ; AD_N = whole pages, mosARGS = the
    sta mosARGS                 ; last piece's length
    lda SL_LEN+1
    sta AD_N
    lda SL_LEN+2
    sta AD_N+1
sls_page:
    lda AD_N
    ora AD_N+1
    beq sls_tail
    jsr ad_get256
    ldx #0
sls_x:
    lda MOSBUF,x
    eor #$80
    sta MOSBUF,x
    inx
    bne sls_x
    jsr ad_put256
    inc AD_T+1
    bne sls_dec
    inc AD_T+2
sls_dec:
    lda AD_N
    bne sls_d1
    dec AD_N+1
sls_d1:
    dec AD_N
    jmp sls_page
sls_tail:
    ldx mosARGS                 ; the last part page
    beq sls_rts
    jsr ad_get256
    ldx #0
sls_t:
    lda MOSBUF,x
    eor #$80
    sta MOSBUF,x
    inx
    cpx mosARGS
    bne sls_t
    jmp ad_put256
sls_rts:
    rts
slw_r       dta 'RIFF'
slw_w       dta 'WAVE'

; ----------------------------------------------------------------------------
; sa_sound
;   Summary: SOUND 24+c, A, P, D (OSWORD 7 block at mosPTR): Ultimate
;            Audio channel c plays a sample (see the top). Looped: control
;            3 with the loop points 0 and the length (relative, as
;            ModPlayer_16k's); control bit 2 enables Ultimate Audio's
;            interrupt (measured 2026-10-17: unacknowledged it hangs the
;            machine; only ad_detect uses it, with interrupts off).
;   Uses:    A, X, Y, mosTMP, mosNUM, mosARGS, MOSBUF.
SS          = $06E0             ; state (as SL)
SS_CH       = SS+0              ; c * 32
SS_VOL      = SS+1
SS_ENT      = SS+2              ; 8: the sample's entry
SS_CTRL     = SS+10             ; 1 or 5
sa_sound:
    lda reu_banks+1             ; no 16 MB REU or no Ultimate Audio:
    beq ss_rts                  ; silent
    ldx #<AD_OK
    lda #>AD_OK
    jsr ad_rget
    beq ss_rts
    ldy #0                      ; c * 32
    lda (mosPTR),y
    sec
    sbc #24
    asl
    asl
    asl
    asl
    asl
    sta SS_CH
    ldy #3                      ; A (16 bits, signed)
    lda (mosPTR),y
    bmi ss_neg
    tax                         ; > 0: sample A low, level A high
    dey
    lda (mosPTR),y
    beq ss_stop
    cmp #SA_MAX+1
    bcs ss_rts
    sta mosARGS                 ; (the sample)
    lda #15
    cpx #0
    beq ss_lvl
    txa
    cmp #16
    bcc ss_lvl
    lda #15
ss_lvl:
    tax
    lda ss_vols,x
    sta SS_VOL
    lda SS_CH                   ; the channel's last sample = this one
    lsr
    lsr
    lsr
    lsr
    lsr
    clc
    adc #<AD_LAST
    tax
    lda mosARGS
    sta mosARGS+1
    lda #>AD_LAST
    jsr ad_rput
    jmp ss_play
ss_stop:
    ldx SS_CH                   ; 0: silence
    lda #0
    sta UA_BASE+UA_CTRL,x
ss_rts:
    rts
ss_neg:
    dey                         ; -15..-1: the last sample, that level
    lda (mosPTR),y
    eor #$FF
    clc
    adc #1
    cmp #16
    bcc ss_nl
    lda #15
ss_nl:
    tax
    lda ss_vols,x
    sta SS_VOL
    lda SS_CH
    lsr
    lsr
    lsr
    lsr
    lsr
    clc
    adc #<AD_LAST
    tax
    lda #>AD_LAST
    jsr ad_rget
    beq ss_rts
    sta mosARGS
ss_play:
    lda mosARGS                 ; the entry: REU AD_BANK:(n-1)*8, 8 bytes
    sec
    sbc #1
    asl
    asl
    asl
    sta AD_T
    lda #0
    sta AD_T+1
    lda #AD_BANK
    sta AD_T+2
    lda #8
    ldx #<SS_ENT
    ldy #>SS_ENT
    jsr ad_getn
    lda SS_ENT+3                ; no length: no sample
    ora SS_ENT+4
    ora SS_ENT+5
    beq ss_rts
    jsr ss_pitch                ; SS_ENT+6/+7 = the rate for P
    jsr ss_len                  ; SS_ENT+3.. = the length for D, SS_CTRL
    ldx SS_CH                   ; the registers (big-endian)
    lda #0
    sta UA_BASE+UA_CTRL,x
    lda SS_VOL
    sta UA_BASE+UA_VOL,x
    lda #$80
    sta UA_BASE+UA_PAN,x
    lda #$01
    sta UA_BASE+UA_START,x
    lda SS_ENT+2
    sta UA_BASE+UA_START+1,x
    lda SS_ENT+1
    sta UA_BASE+UA_START+2,x
    lda SS_ENT
    sta UA_BASE+UA_START+3,x
    lda SS_ENT+5
    sta UA_BASE+UA_LEN,x
    lda SS_ENT+4
    sta UA_BASE+UA_LEN+1,x
    lda SS_ENT+3
    sta UA_BASE+UA_LEN+2,x
    lda SS_ENT+7
    sta UA_BASE+UA_RATE,x
    lda SS_ENT+6
    sta UA_BASE+UA_RATE+1,x
    lda #0                      ; loop points: 0 and the length
    sta UA_BASE+UA_RPA,x
    sta UA_BASE+UA_RPA+1,x
    sta UA_BASE+UA_RPA+2,x
    lda SS_ENT+5
    sta UA_BASE+UA_RPB,x
    lda SS_ENT+4
    sta UA_BASE+UA_RPB+1,x
    lda SS_ENT+3
    sta UA_BASE+UA_RPB+2,x
    lda #$FF
    sta UA_BASE+UA_IRQ,x
    lda SS_CTRL
    sta UA_BASE+UA_CTRL,x
    rts
ss_vols     dta 0, 4, 8, 13, 17, 21, 25, 29, 34, 38, 42, 46, 50, 55, 59, 63

; ss_pitch: the rate for P: d = P - 53; rate = rate * 2^(-d/48) (higher
; P, a smaller rate value: a higher pitch). d = 48 o + r, r 0-47:
; rate * T(r) / 65536, then shifted by o (right for o > 0, left for o <
; 0, at most 65535). Uses A, X, Y, mosTMP, mosNUM.
ss_pitch:
    ldy #4                      ; P low (high byte ignored: 0-255)
    lda (mosPTR),y
    sec
    sbc #53
    sta AD_N                    ; d (signed, -53..202)
    lda #0
    sbc #0
    sta AD_N+1
    ldx #0                      ; o = 0; d >= 0: d -= 48 while >= 48
    lda AD_N+1
    bpl ssp_pos
ssp_neg:
    dex                         ; d < 0: o -= 1, d += 48 until >= 0
    lda AD_N
    clc
    adc #48
    sta AD_N
    bcc ssp_neg
    jmp ssp_mul
ssp_pos:
    lda AD_N
    cmp #48
    bcc ssp_mul
    sbc #48
    sta AD_N
    inx
    bne ssp_pos
ssp_mul:
    stx AD_N+1                  ; o
    lda AD_N                    ; T(r) -> mosTMP+2/+3; rate * T >> 16
    asl
    tax
    lda ss_tlo,x
    sta mosTMP+2
    lda ss_tlo+1,x
    sta mosTMP+3
    jsr ss_mul                  ; SS_ENT+6/+7 = rate * T >> 16
    lda AD_N+1                  ; the octaves
    beq ssp_rts
    bmi ssp_left
ssp_r:
    lsr SS_ENT+7
    ror SS_ENT+6
    dec AD_N+1
    bne ssp_r
    beq ssp_min
ssp_left:
    asl SS_ENT+6
    rol SS_ENT+7
    bcs ssp_max
    inc AD_N+1
    bne ssp_left
ssp_min:
    lda SS_ENT+6                ; at least 1
    ora SS_ENT+7
    bne ssp_rts
    inc SS_ENT+6
ssp_rts:
    rts
ssp_max:
    lda #$FF
    sta SS_ENT+6
    sta SS_ENT+7
    rts

; ss_mul: SS_ENT+6/+7 = (SS_ENT+6/+7) * (mosTMP+2/+3) >> 16. Uses A, X,
; mosTMP.
ss_mul:
    lda #0
    sta mosTMP
    sta mosTMP+1                ; the product's top 16 bits
    ldx #16
ssm_l:
    lsr mosTMP+3                ; multiplier bit
    ror mosTMP+2
    bcc ssm_n
    lda mosTMP                  ; + multiplicand (rate) at the top
    clc
    adc SS_ENT+6
    sta mosTMP
    lda mosTMP+1
    adc SS_ENT+7
    sta mosTMP+1
ssm_n:
    ror mosTMP+1                ; product >> 1 (its low half dropped)
    ror mosTMP
    dex
    bne ssm_l
    lda mosTMP
    sta SS_ENT+6
    lda mosTMP+1
    sta SS_ENT+7
    rts

; ss_len: D (1/20 s): 0 the whole sample, 255 looped (control 5), else
; length = min(length, D * 312500 / rate). Uses A, X, Y, mosTMP, mosNUM.
ss_len:
    lda #1
    sta SS_CTRL
    ldy #6
    lda (mosPTR),y
    beq ssl_rts
    cmp #255
    bne ssl_d
    lda #3
    sta SS_CTRL
ssl_rts:
    rts
ssl_d:
    sta AD_N                    ; mosTMP = D * 312500 (32 bits)
    lda #<312500
    sta mosTMP
    lda #>312500
    sta mosTMP+1
    lda #^312500
    sta mosTMP+2
    lda #0
    sta mosTMP+3
    jsr ad_mul8                 ; mosTMP *= AD_N
    lda SS_ENT+6                ; / rate
    sta AD_N
    lda SS_ENT+7
    sta AD_N+1
    jsr ad_div
    lda mosTMP+3                ; shorter than the sample?
    bne ssl_rts
    lda mosTMP
    cmp SS_ENT+3
    lda mosTMP+1
    sbc SS_ENT+4
    lda mosTMP+2
    sbc SS_ENT+5
    bcs ssl_rts
    lda mosTMP
    sta SS_ENT+3
    lda mosTMP+1
    sta SS_ENT+4
    lda mosTMP+2
    sta SS_ENT+5
    rts

; 65536 * 2^(-r/48), r = 0-47 (r = 0: 65535)
ss_tlo:
    dta a($FFFF), a($FC54), a($F8B6), a($F525), a($F1A2), a($EE2B)
    dta a($EAC1), a($E763), a($E412), a($E0CD), a($DD94), a($DA67)
    dta a($D745), a($D42F), a($D124), a($CE25), a($CB30), a($C846)
    dta a($C567), a($C293), a($BFC9), a($BD09), a($BA53), a($B7A7)
    dta a($B505), a($B26D), a($AFDE), a($AD58), a($AADC), a($A869)
    dta a($A5FF), a($A39E), a($A145), a($9EF5), a($9CAE), a($9A6F)
    dta a($9838), a($9609), a($93E3), a($91C4), a($8FAD), a($8D9E)
    dta a($8B96), a($8995), a($879C), a($85AB), a($83C0), a($81DD)

; ----------------------------------------------------------------------------
; Arithmetic. ad_hz: mosTMP/+1 = 6250000 / AD_N (Hz <-> UA rate, both
; ways). ad_mul8: mosTMP (32 bits) *= AD_N (8 bits). ad_div: mosTMP (32
; bits) /= AD_N (16 bits), the remainder dropped. Uses A, X, mosTMP,
; AD_N, mosARGS.
ad_hz:
    lda #<6250000
    sta mosTMP
    lda #>6250000
    sta mosTMP+1
    lda #^6250000
    sta mosTMP+2
    lda #0
    sta mosTMP+3
    lda AD_N                    ; (0: as 1)
    ora AD_N+1
    bne ad_div
    inc AD_N
ad_div:
    lda #0
    sta mosARGS                 ; remainder (16 bits)
    sta mosARGS+1
    ldx #32
add_l:
    asl mosTMP
    rol mosTMP+1
    rol mosTMP+2
    rol mosTMP+3
    rol mosARGS
    rol mosARGS+1
    lda mosARGS
    sec
    sbc AD_N
    tay
    lda mosARGS+1
    sbc AD_N+1
    bcc add_n
    sta mosARGS+1
    sty mosARGS
    inc mosTMP
add_n:
    dex
    bne add_l
    rts
ad_mul8:
    lda #0                      ; mosARGS..+2, AD_N+1: the multiplicand
    sta AD_N+1                  ; as it is shifted; the product built
    ldx #3                      ; in mosTMP: copy it out first
adm_cp:
    lda mosTMP,x
    pha
    lda #0
    sta mosTMP,x
    dex
    bpl adm_cp
    pla
    sta mosARGS
    pla
    sta mosARGS+1
    pla
    sta mosARGS+2
    pla                         ; (the top byte: 0 for D * 312500)
adm_l:
    lsr AD_N
    bcc adm_n
    lda mosTMP
    clc
    adc mosARGS
    sta mosTMP
    lda mosTMP+1
    adc mosARGS+1
    sta mosTMP+1
    lda mosTMP+2
    adc mosARGS+2
    sta mosTMP+2
    lda mosTMP+3
    adc AD_N+1
    sta mosTMP+3
adm_n:
    asl mosARGS
    rol mosARGS+1
    rol mosARGS+2
    rol AD_N+1
    lda AD_N
    bne adm_l
    rts

; ----------------------------------------------------------------------------
; REU transfers (interrupts off from the first register to the command:
; the sound interrupt uses the REU too). ad_hdr / ad_hdrput: the header
; page (&EE0100) <-> MOSBUF; ad_dirget / ad_dirput: the directory page
; (&EE0000). ad_get256 / ad_put256: the page at AD_T..+2 <-> MOSBUF.
; ad_getn: A bytes (0: 256) from AD_T..+2 to X/Y (low/high). ad_rget /
; ad_rput: the byte at AD_BANK:A:X -> A (Z set when 0), or mosARGS+1 ->
; there. Uses A, X, Y, AD_CMD.
AD_CMD      = mosARGS+2
ad_hdr:
    jsr ad_hp
ad_get256:
    lda #REU_TO_C64
    bne ad_pg
ad_put256:
    lda #REU_TO_REU
ad_pg:
    sta AD_CMD
    lda #0
    ldx #<MOSBUF
    ldy #>MOSBUF
ad_go:
    php
    sei
    stx REU_C64
    sty REU_C64+1
    sta REU_LEN
    ldx #0                      ; (0: 256)
    ora #0
    bne adg_l
    inx
adg_l:
    stx REU_LEN+1
    lda AD_T
    sta REU_ADDR
    lda AD_T+1
    sta REU_ADDR+1
    lda AD_T+2
    sta REU_BANK
    lda #0
    sta REU_CTRL
    lda AD_CMD
    sta REU_CMD
    plp
    rts
ad_hdrput:
    jsr ad_hp
    jmp ad_put256
ad_dirget:
    jsr ad_dp
    jmp ad_get256
ad_dirput:
    jsr ad_dp
    jmp ad_put256
ad_hp:
    lda #>AD_FREE
    .byte $2C
ad_dp:
    lda #>AD_DIR
    sta AD_T+1
    lda #0
    sta AD_T
    lda #AD_BANK
    sta AD_T+2
    rts
ad_getn:
    pha
    lda #REU_TO_C64
    sta AD_CMD
    pla
    jmp ad_go
ad_rget:
    pha
    lda #REU_TO_C64
    bne adr_go
ad_rput:
    pha
    lda mosARGS+1
    sta reu_tmp
    lda #REU_TO_REU
adr_go:
    sta AD_CMD
    pla
    php
    sei
    sta REU_ADDR+1
    stx REU_ADDR
    lda #AD_BANK
    sta REU_BANK
    lda #<reu_tmp
    sta REU_C64
    lda #>reu_tmp
    sta REU_C64+1
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda AD_CMD
    sta REU_CMD
    plp
    lda reu_tmp
    rts
