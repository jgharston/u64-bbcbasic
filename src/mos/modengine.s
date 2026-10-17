; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- the MOD engine image (RAM &0900, 1.0.0 item 8a, step 2):
; a ProTracker MOD on Ultimate Audio channels 0-3
;
; Ported to MADS from ModPlayer_16k by Freshness (6510nl), CSDb release
; 131522 (https://csdb.dk/release/?id=131522, KickAssembler source, 2014;
; no licence statement; port and credit: owner, 2026-10-17). Taken over,
; translated mechanically (tools: a KickAssembler-to-MADS script; the
; macros and anonymous labels expanded): the play routine (module.asm:
; playmodule, loaddivision, nextdivision, setpattern), buffer.asm,
; fx.asm, periodfix.asm (fixperiod), math.asm, audio.asm (fastplay,
; resetaudio), reu_routines.asm (reu_loadfix16). Changed for the MOS:
;   - a sound engine image: the entry table of sound.s (SNDV_*), image 2;
;     *MODPLAY (modplay.s, bank 10) copies it in, loads the module's
;     header into its tables, then starts it (mi_start);
;   - the variables are RAM, not zero page, but the two indirect pointers
;     (bufferptr, chanptr: &FB-&FE, saved and restored by the interrupt);
;     the order table is in RAM (setpattern), the module at MP_BANK:0000
;     in the REU (loaddivision);
;   - the note and finetune tables (Tools/notelookupgls.bin,
;     finetune.bin) are in the REU (getnote, getrate fetch a byte each);
;   - the timer for PAL and NTSC at run time (KERNAL's &02A6); the MOS
;     interrupt runs at the tick rate while a MOD plays (owner: as the
;     source), and keeps TIME right (mi_time);
;   - no screen, keyboard, REU detection, new-module detection.
; The jump tables and the channel buffers are page-aligned as in the
; original (the indirect jump's low byte, bufferptr's low byte).
;
; ----------------------------------------------------------------------------

MP_BANK     = $F2               ; the module: REU &F20000 (sample.s's area)
MP_TABLES   = $EE0200           ; the note table (1024), finetune (1152)
MP_NOTE     = MP_TABLES
MP_FTLO     = MP_TABLES+$400
MP_FTHI     = MP_TABLES+$400+576

maxsamplesz = 31
defbpm      = 125
deftick     = 6
namesz      = 20
singlesz    = 30
songsz      = 134
maxslideperiod = 856
minslideperiod = 113
fpperiodratio = 57740           ; floor(32768 * 2 * 6250000 / 7093789.2)
JMP_IND     = $6C
bufferptr   = $FB               ; (saved by the interrupt; the graphics
chanptr     = $FD               ; engine's gzp is &FB)

audch1      = $DF20
audch2      = $DF40
audch3      = $DF60
audch4      = $DF80
audch5      = $DFA0
audch6      = $DFC0
audch7      = $DFE0
audctr      = $00
audvol      = $01
audpan      = $02
audsms      = $04
audsml      = $09
audrat      = $0E
audrpa      = $11
audrpb      = $15
audirq      = $1F

sftcmdoff   = $20
sftsmpoff   = $21
sfttfxoff   = $22
sfttxdoff   = $23
sftnrtoff   = $24
sftortoff   = $26
sftnotoff   = $28
sftlntoff   = $29
sftnntoff   = $2A
sfttx2off   = $2B
sftvbaoff   = $2C
sftvbsoff   = $2D
sftvbpoff   = $2E
sftvbwoff   = $2F
sfttraoff   = $30
sfttrsoff   = $31
sfttrpoff   = $32
sfttrwoff   = $33
sftlppoff   = $34
sftlpcoff   = $35
sfttkcoff   = $36
sfttksoff   = $37
sftbkcoff   = $38
sftstsoff   = $39
sftarcoff   = $3A
sftvoloff   = $3B
sftlvloff   = $3C
sftpanoff   = $3D
sftflgoff   = $3F
flagvolume  = 1
flagpanning = 2
flagrate    = 4
flagrepeat  = 8
flagnewsmp  = 16
flagvibrato = 32

; ----------------------------------------------------------------------------
; The entry table (sound.s's SNDV_*), then mi_start at +22
    jmp mi_stop                 ; +0  SNDV_INIT: silent
    jmp mi_irq                  ; +3  SNDV_IRQ: a tick
    jmp mi_put                  ; +6  SNDV_PUT: SID notes are dropped
    jmp mi_adval                ; +9  SNDV_ADVAL
    jmp mi_stop                 ; +12 SNDV_STOP: silent, the timer back
    jmp mi_rts                  ; +15 SNDV_BELL: none
    jmp mi_rts                  ; +18 SNDV_FLUSH
    dta 2                       ; +21 SNDV_IMG: 2, the MOD engine
    jmp mi_start                ; +22 start (modplay.s, after the tables)

; mi_put: C = 0 (taken: a SID note while a MOD plays is dropped)
mi_put:
    clc
mi_rts:
    rts
; mi_adval: X = 3 (free places: nothing waits)
mi_adval:
    ldx #3
    rts

; ----------------------------------------------------------------------------
; mi_irq
;   Summary: one tick of the player (the MOS interrupt runs at the tick
;            rate while a MOD plays).
;   Function: &FB-&FE saved (the graphics engine's pointer), playmodule,
;            &FB-&FE back, TIME kept right (mi_time).
;   Uses:    A, X, Y (the interrupt saved them).
mi_irq:
    lda mp_on
    beq mi_rts
    lda bufferptr
    pha
    lda bufferptr+1
    pha
    lda chanptr
    pha
    lda chanptr+1
    pha
    lda #>buffers
    sta bufferptr+1
    lda #>division
    sta chanptr+1
    jsr playmodule
    jsr mi_time
    pla
    sta chanptr+1
    pla
    sta chanptr
    pla
    sta bufferptr+1
    pla
    sta bufferptr
    rts

; mi_time: TIME: the resident interrupt adds 1, 2, 2 cs in turn (60 Hz);
; at the tick rate (BPM * 2 / 5 Hz) a tick is 250 / BPM cs: timefrac set
; so that it adds 2 each time, and mp_tstep (250 / BPM - 2, 8.8 fixed,
; signed) gathered in mp_tacc; whole centiseconds go to mostime.
mi_time:
    lda #2
    sta timefrac
    lda mp_tacc
    clc
    adc mp_tstep
    sta mp_tacc
    lda mp_tacc+1
    adc mp_tstep+1
    sta mp_tacc+1
    beq mt_rts                  ; no whole cs yet
    ldx #$FF                    ; the sign extension
    ora #0
    bmi mt_neg
    inx
mt_neg:
    stx mt_ext
    clc                         ; mostime += mp_tacc+1 (signed)
    adc mostime
    sta mostime
    ldx #1
mt_add:
    lda mostime,x
    adc mt_ext
    sta mostime,x
    inx
    cpx #5
    bne mt_add
    lda #0
    sta mp_tacc+1
mt_rts:
    rts

; ----------------------------------------------------------------------------
; mi_start
;   Summary: start the module whose tables modplay.s has filled (nsamples,
;            songlenght, mp_order, the sample tables): initvar's part,
;            the timer at 125 BPM (at the first tick), playing.
;   Uses:    A, X, Y.
mi_start:
    php
    sei
    lda #0
    sta mp_on
    sta patternindex
    sta curdivision
    sta skipdivision
    sta patdelay
    sta mp_tacc
    sta mp_tacc+1
    lda #1
    sta curtick
    sta changetimer
    sta monomode
    lda #>buffers
    sta bufferptr+1
    jsr clearbuffers
    lda #$30                    ; the main volume (as the original)
    sta mainvolume
    lda #$00                    ; panning: 1, 2 left, 3, 4 right (the
    sta buffer1+sftpanoff       ; original's values)
    sta buffer2+sftpanoff
    lda #$0F
    sta buffer3+sftpanoff
    sta buffer4+sftpanoff
    lda #$01
    sta buffer1+sftflgoff
    sta buffer2+sftflgoff
    sta buffer3+sftflgoff
    sta buffer4+sftflgoff
    lda #deftick
    sta newspeed
    lda #defbpm
    sta bpm
    jsr calctimer
    sta timer
    stx timer+1
    lda #JMP_IND
    sta fxjump
    lda #<fxtablet0
    sta fxjump+1
    lda #>fxtablet0
    sta fxjump+2
    ldy #0                      ; the first pattern
    jsr setpattern
    jsr resetaudio
    lda #1
    sta mp_on
    plp
    rts

; ----------------------------------------------------------------------------
; mi_stop: silent (channels 0-3 stopped), the KERNAL's 60 Hz timer back
; (&4025 PAL, &4295 NTSC: KERNAL &02A6)
mi_stop:
    php
    sei
    lda #0
    sta mp_on
    sta audch1+audctr
    sta audch2+audctr
    sta audch3+audctr
    sta audch4+audctr
    ldx #<$4295
    ldy #>$4295
    lda $02A6
    beq ms_ntsc
    ldx #<$4025
    ldy #>$4025
ms_ntsc:
    stx $DC04
    sty $DC05
    plp
    rts

; settimer (timerirq.asm, ModPlayer_16k): the CIA timer for the tick rate
; (timer - 1), and the new ticks per division
settimer:
    php
    sec
    lda timer
    sbc #$01
    sta $DC04
    lda timer+1
    sbc #$00
    sta $DC05
    lda newspeed
    sta tickperdiv
    plp
    rts

; calctimer (periodfix.asm): A/X = the CIA timer for bpm: 2.5 x the CIA
; clock / BPM (PAL 2463120, NTSC 2556818: chosen at run time); also
; mp_tstep = 64000 / BPM - 512 (TIME's correction, mi_time)
calctimer:
    lda bpm
    sta DIVISOR
    lda #0
    sta DIVISOR+1
    lda #<64000
    sta DIVIDEND
    lda #>64000
    sta DIVIDEND+1
    lda #0
    sta DIVIDEND+2
    jsr divide24x16
    lda DIVIDEND
    sec
    sbc #<512
    sta mp_tstep
    lda DIVIDEND+1
    sbc #>512
    sta mp_tstep+1
    lda bpm
    sta DIVISOR
    lda #<2463120
    sta DIVIDEND
    lda #>2463120
    sta DIVIDEND+1
    lda #^2463120
    sta DIVIDEND+2
    lda $02A6
    bne ct_pal
    lda #<2556818
    sta DIVIDEND
    lda #>2556818
    sta DIVIDEND+1
    lda #^2556818
    sta DIVIDEND+2
ct_pal:
    jsr divide24x16
    lda DIVIDEND
    ldx DIVIDEND+1
    rts

; getnote (periodfix.asm, the table in the REU): A/X = the period (high,
; low): A = its note (1-36), 0 when it is not one (the table's bit 7).
; Keeps Y.
getnote:
    and #$03
    clc
    adc #>MP_NOTE
    sta REU_ADDR+1
    stx REU_ADDR
    lda #^MP_NOTE
    jsr mi_reu1
    bpl gn_rts
    lda #0
gn_rts:
    rts

; getrate (periodfix.asm, the tables in the REU): X = note (1-36), A =
; finetune (0-15): A/X = the period (high, low) of finetune row A.
; Keeps Y.
getrate:
    sty SPARE+2
    ldy #36                     ; offset = finetune * 36 + note - 1
    dex
    jsr mul8x8
    txa
    clc
    adc PRODUCT
    sta mi_off
    lda PRODUCT+1
    adc #0
    sta mi_off+1
    lda mi_off                  ; the high byte
    clc
    adc #<MP_FTHI
    sta REU_ADDR
    lda mi_off+1
    adc #>MP_FTHI
    sta REU_ADDR+1
    lda #^MP_FTHI
    jsr mi_reu1
    pha
    lda mi_off                  ; the low byte
    clc
    adc #<MP_FTLO
    sta REU_ADDR
    lda mi_off+1
    adc #>MP_FTLO
    sta REU_ADDR+1
    lda #^MP_FTLO
    jsr mi_reu1
    tax
    pla
    ldy SPARE+2
    rts

; mi_reu1: A = the byte at REU bank A, REU_ADDR as set (the interrupt
; uses the REU freely: foreground transfers are set up with interrupts
; off). Z/N from it.
mi_reu1:
    sta REU_BANK
    lda #<mi_byte
    sta REU_C64
    lda #>mi_byte
    sta REU_C64+1
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    lda mi_byte
    rts

; ---- ModPlayer_16k: module.asm (play routine) ----
 ; Main player code
 ; ****************
playmodule:
    jsr fastplay ; Move play buffer to Audio Module registers
    dec curtick
    bne skipnote
    lsr changetimer
    bcc notimerchg
    jsr settimer ; If needed change timer
notimerchg:
    lda tickperdiv ; Reset tick counter
    sta curtick
    lda patdelay
    bne pmdelay
    jsr loaddivision ; Load division from REU
    jsr playdivision ; Parse data and 'play' onto buffer
    jsr tickfx ; Compute FX
    jsr nextdivision ; Move to next division
    jsr	finalcheck ; Adjust values for this machine (volume/frequency)
    rts
skipnote:
    jsr tickfx ; Compute FX
skipfx:
    jsr	finalcheck ; Adjust values for this machine (volume/frequency)
    rts
pmdelay: ; Needed for effect EE
    dec patdelay
    jmp skipfx

 ; Load single division
 ; ********************
loaddivision:
    lda #$00
    sta temp2
    lda curpattern
    sta temp
    lda curdivision
    asl
    asl
    asl
    rol temp
    rol temp2
    asl
    rol temp
    rol temp2
    adc patternptr
    tax
    lda temp
    adc patternptr+1
    tay
    lda temp2
    adc #MP_BANK                ; (the module at MP_BANK:0000; U64 BBC BASIC)
    jsr reu_loadfix16
    rts

 ; Move to next division
 ; *********************
nextdivision:
    ldx curdivision
    lsr skipdivision
    bcs ndskip
    inx
    cpx #$40
    bcc ndskip
    ldy patternindex
    iny
    jsr setpattern
    lda #$00
    sta bufferptr ; Reset loop
    ldy #<buffer1+sftlpcoff
    sta (bufferptr),y
    ldy #<buffer2+sftlpcoff
    sta (bufferptr),y
    ldy #<buffer3+sftlpcoff
    sta (bufferptr),y
    ldy #<buffer4+sftlpcoff
    sta (bufferptr),y
    ldx #$00
ndskip:
    stx curdivision
    rts


 ; Set pattern
 ; ***********
setpattern:
    cpy songlenght
    bcc module_a11
    ldy #$00
module_a11:
    sty patternindex
    lda mp_order,y              ; (the order table in RAM; U64 BBC BASIC)
    sta curpattern
    rts

 ; Print info about playing status
 ; *******************************

; ---- buffer.asm ----
 ; Buffered mod player
 ; *******************

 ; Parse channels
 ; **************
playdivision:
    lda #<buffer1 ; Voice 1
    sta bufferptr
    lda #<division
    sta chanptr
    jsr playchannel
    lda #<buffer2 ; Voice 2
    sta bufferptr
    lda #<division+4
    sta chanptr
    jsr playchannel
    lda #<buffer3 ; Voice 3
    sta bufferptr
    lda #<division+8
    sta chanptr
    jsr playchannel
    lda #<buffer4 ; Voice 4
    sta bufferptr
    lda #<division+12
    sta chanptr
    jmp playchannel


 ; Play generic channel
 ; ********************
 ; Play mod on buffer
playchannel:
 ; Load data from channel
    ldx #$0f
    ldy #0 ; Byte 0
    lda (chanptr),y
    sax temp4 ; Rate HI
    and #$f0
    sta temp2
    ldy #1 ; Byte 1
    lda (chanptr),y
    sta temp3 ; Rate LO
    ldy #2 ; Byte 2
    lda (chanptr),y
    sax temp
    lsr
    lsr
    lsr
    lsr
    ora temp2
    sta	temp5 ; Sample number
    ldy #3 ; Byte 3
    lda (chanptr),y
    ldy #sfttxdoff ; FX data
    sta (bufferptr),y
    lda temp
    ldy #sfttfxoff ; FX number
    sta (bufferptr),y
    lda temp4
    ldx temp3
    jsr getnote ; Translate period to note (logaritmic to linear)
    ldy #sftnotoff ; Save note
    sta (bufferptr),y

 ; Check sample data

    lax temp5
    bne buffer_a0
    jmp nonewsample
buffer_a0:
    ldy #sftsmpoff ; New sample to be played: fill
    sta (bufferptr),y
    dex ; registers according to sample data
    lda #$01 ; Memory position
    ldy #audsms
    sta (bufferptr),y
    lda sampleptrh,x
    ldy #audsms+1
    sta (bufferptr),y
    lda sampleptrm,x
    ldy #audsms+2
    sta (bufferptr),y
    lda sampleptrl,x
    ldy #audsms+3
    sta (bufferptr),y
    lda samplelenh,x ; Lenght
    ldy #audsml
    sta (bufferptr),y
    lda samplelenm,x
    ldy #audsml+1
    sta (bufferptr),y
    lda samplelenl,x
    ldy #audsml+2
    sta (bufferptr),y
    lda samplerep,x
    beq norep
    ldy #sftcmdoff ; Enable ** REPEAT **
    lda (bufferptr),y
    ora #flagrepeat
    ldy #sftcmdoff
    sta (bufferptr),y
    lda samplerepah,x ; Repeat position A
    ldy #audrpa
    sta (bufferptr),y
    lda samplerepam,x
    ldy #audrpa+1
    sta (bufferptr),y
    lda samplerepal,x
    ldy #audrpa+2
    sta (bufferptr),y
    lda samplerepbh,x
    ldy #audrpb ; Repeat position B
    sta (bufferptr),y
    lda samplerepbm,x
    ldy #audrpb+1
    sta (bufferptr),y
    lda samplerepbl,x
    ldy #audrpb+2
    sta (bufferptr),y

    lda #$02
norep:
    ora #$01
    ldy #audctr
    sta (bufferptr),y
    ldy #sftcmdoff ; Enable ** NEW SAMPLE ** & ** VOLUME ** & ** PANNING **
    lda (bufferptr),y
    ora #[flagvolume|flagpanning]
    ldy #sftcmdoff
    sta (bufferptr),y
    lda samplevol,x ; Set vol
    ldy #sftvoloff
    sta (bufferptr),y
    ldy #sftpanoff
    lda (bufferptr),y
    ldy #audpan
    sta (bufferptr),y
nonewsample:

 ; Check rate data

    ldy #sftnotoff
    lda (bufferptr),y
    beq buffer_a1
    ldy #sftlntoff
    sta (bufferptr),y
    ldy #sftsmpoff
    lax (bufferptr),y
    dex
    lda samplerep,x
    beq ratenorep
    ldy #sftcmdoff ; Enable ** SAMPLE RATE **
    lda (bufferptr),y
    ora #flagrepeat
    ldy #sftcmdoff
    sta (bufferptr),y
ratenorep:
    ldy #sftcmdoff ; Enable ** SAMPLE RATE **
    lda (bufferptr),y
    ora #flagnewsmp|flagrate
    ldy #sftcmdoff
    sta (bufferptr),y
    ldy #sftnrtoff ; Save old rate value
    lda (bufferptr),y
    ldy #sftortoff
    sta (bufferptr),y
    ldy #sftnrtoff+1
    lda (bufferptr),y
    ldy #sftortoff+1
    sta (bufferptr),y
    ldy #sftnotoff
    lda (bufferptr),y
    sta temp
    lda sampleft,x ; A = Finetune
    ldx temp ; X = note
    jsr getrate ; Get rate from note & finetune
    ldy #sftnrtoff+1
    sta (bufferptr),y
    txa
    ldy #sftnrtoff ; Save new rate value
    sta (bufferptr),y
    jsr checkwaves ; Check/update tremolo & vibrato positions
    lda #$01
buffer_a1:
    ldy #sftnntoff ; New note!
    sta (bufferptr),y

    rts


 ; Reset vibrato/tremolo position if needed
 ; ****************************************
checkwaves:
    ldy #sftvbwoff ; Fix vibrato position
    lda (bufferptr),y
    and #$08
    bne buffer_a2
    ldy #sftvbpoff
    sta (bufferptr),y
buffer_a2:
    ldy #sfttrwoff ; Fix tremolo position
    lda (bufferptr),y
    and #$08
    bne buffer_a3
    ldy #sfttrpoff
    sta (bufferptr),y
buffer_a3:
    rts


 ; Clear buffers routine
 ; *********************
clearbuffers:
    ldx #$40-1
    lda #$00
buffer_a4:
    sta buffer1,x
    sta buffer2,x
    sta buffer3,x
    sta buffer4,x
    dex
    bpl buffer_a4
    rts

 ; Final check (pre-play)
 ; **********************
finalcheck:
    lda #<buffer1 ; Voice 1
    sta bufferptr
    jsr channelfinalcheck
    lda #<buffer2 ; Voice 2
    sta bufferptr
    jsr channelfinalcheck
    lda #<buffer3 ; Voice 3
    sta bufferptr
    jsr channelfinalcheck
    lda #<buffer4 ; Voice 4
    sta bufferptr
    jsr channelfinalcheck
    rts

 ; Final check
 ; ***********
channelfinalcheck:
    ldy #sftcmdoff
    lda (bufferptr),y
    and #flagrate ; If sample updated
    beq buffer_a5
    ldy #sftnrtoff
    lax (bufferptr),y
    ldy #sftnrtoff+1
    lda (bufferptr),y
    tay
    jsr fixperiod ; Translate amiga period to audio module period
    lda PRODUCT+2
    ldy #audrat+1
    sta (bufferptr),y
    lda PRODUCT+3
    ldy #audrat
    sta (bufferptr),y
    jmp buffer_a5

buffer_a5:
    ldy #sftcmdoff
    lda (bufferptr),y
    and #flagvibrato ; If doing vibrato
    beq buffer_a6
    ldy #sftcmdoff
    lda (bufferptr),y
    eor #flagvibrato|flagrate
    ldy #sftcmdoff ; Just update rate
    sta (bufferptr),y
    jmp buffer_a6

buffer_a6:
    ldy #sftcmdoff
    lda (bufferptr),y
    and #flagvolume ; If volume updated
    beq buffer_a7
    ldy #sftvoloff ; Adapt channel volume to main volume value
    lda (bufferptr),y
    tay
    lda mainvolume
    asl
    asl
    jsr mul8x8
    lda PRODUCT+1
    ldy #audvol
    sta (bufferptr),y
buffer_a7:
    ldy #sftflgoff ; Check if active
    lda (bufferptr),y
    and #$01
    bne buffer_a8
    lda #$00
    ldy #audvol
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagvolume ; If volume updated
    ldy #sftcmdoff
    sta (bufferptr),y
buffer_a8:
    lda monomode
    lsr
    bcs buffer_a9
    ldy #sftcmdoff
    lda (bufferptr),y
    and #[$ff-flagpanning]
    ldy #sftcmdoff
    sta (bufferptr),y
buffer_a9:
    rts



; ---- fx.asm ----
 ; *******************
 ; Main FX sub routine
 ; *******************

tickfx:
    lda #<buffer1
    sta bufferptr
    jsr channelfx
    lda #<buffer2
    sta bufferptr
    jsr channelfx
    lda #<buffer3
    sta bufferptr
    jsr channelfx
    lda #<buffer4
    sta bufferptr
    jmp channelfx


 ; Parse single FX
 ; ***************
channelfx:
    ldy #sfttfxoff ; FX number
    lda (bufferptr),y
    cmp #$0e
    bne fx_a0
    ldy #sfttxdoff ; Special case "E"
    lda (bufferptr),y
    tax
    and #$0f
    ldy #sfttxdoff
    sta (bufferptr),y
    txa
    lsr
    lsr
    lsr
    lsr
    ora #$10
    ldy #sfttfxoff
    sta (bufferptr),y
fx_a0:
    asl
    adc #<fxtablet0 ; First tick jump table
    ldx curtick
    cpx tickperdiv
    beq fx_a1
    adc #<[fxtabletn-fxtablet0] ; Tick n jump table
fx_a1:
    sta fxjump+1
    ldy #sfttxdoff ; FX data
    lda (bufferptr),y
    jsr fxjump
    lda #$00
    ldy #sftnntoff ; Reset note played flag
    sta (bufferptr),y
    rts


 ; ****************
 ; ** FX SECTION **
 ; ****************


 ; FX not implemented
 ; ******************
fxnotimplemented:
    rts


 ; 00 - Arpeggio
 ; *************
 ; Tick 0 & n
fx0arpeggio: ; Tick 0
    beq noarp ; Arpeggio?
    lda #$03
    ldy #sftarcoff ; Set counter
    sta (bufferptr),y
fx_a2:
    ldy #sftsmpoff
    lax (bufferptr),y
    dex
    ldy #sftlntoff
    lda (bufferptr),y
    sta temp
    lda sampleft,x ; A = Finetune
    ldx temp ; X = note
    jsr getrate ; Get rate from note & finetune
    ldy #sftnrtoff+1
    sta (bufferptr),y
    txa
    ldy #sftnrtoff ; Save new rate value
    sta (bufferptr),y
    ldy #sftcmdoff ; Enable ** SAMPLE RATE **
    lda (bufferptr),y
    ora #flagrate
    ldy #sftcmdoff
    sta (bufferptr),y
    rts
noarp:
    ldy #sftarcoff ; Last arpeggio still active? if so reset!
    lda (bufferptr),y
    cmp #$02
    lda #$00
    ldy #sftarcoff ; Reset counter
    sta (bufferptr),y
    bcs arprate
    rts

fxnarpeggio: ; Tick n
    ldy #sftarcoff ; Get counter
    lax (bufferptr),y
    bne fx_a3
    rts
fx_a3:
    ldy #sfttxdoff ; Get data
    lda (bufferptr),y
    cpx #$03
    bne fx_a4
    lsr ; Play displacement 1
    lsr
    lsr
    lsr
fx_a4:
    cpx #$02
    bne fx_a5
    and #$0f ; Play displacement 2
fx_a5:
    cpx #$01
    bne fx_a6
    lda #$00 ; No displacement
fx_a6:
    dex
    bne fx_a7
    ldx #$03
arprate:
    clc
    ldy #sftlntoff ; Add note offset
    adc (bufferptr),y
    sta temp
    txa
    ldy #sftarcoff ; Update counter
    sta (bufferptr),y
    ldy #sftsmpoff ; Fix period
    lax (bufferptr),y
    dex
    lda sampleft,x
    ldx temp
    jsr getrate
    ldy #sftnrtoff+1
    sta (bufferptr),y
    txa
    ldy #sftnrtoff ; Save new rate value
    sta (bufferptr),y
    ldy #sftcmdoff ; Enable ** SAMPLE RATE **
    lda (bufferptr),y
    ora #flagrate
    ldy #sftcmdoff
    sta (bufferptr),y
    rts


 ; 01 - Slide UP
 ; *************
 ; Tick n only
fxnslideup: ; Tick n
    tay
    lda #>minslideperiod
    ldx #<minslideperiod
    jmp slidetomin


 ; 02 - Slide DOWN
 ; ***************
 ; Tick n only
fxnslidedown: ; Tick n
    tay
    lda #>maxslideperiod
    ldx #<maxslideperiod
    jmp slidetomax


 ; 03 - Slide to note
 ; ******************
 ; Tick 0 & n
fx0slidetonote: ; Tick 0
    beq fx_a7 ; Update speed only if !=0
    ldy #sftstsoff
    sta (bufferptr),y
fx_a7:
    ldy #sftnntoff ; Check if note played
    lda (bufferptr),y
    beq fx_a8
    ldy #sftnrtoff ; If so exchange last note with current
    lda (bufferptr),y
    tax
    ldy #sftortoff
    lda (bufferptr),y
    ldy #sftnrtoff
    sta (bufferptr),y
 ; :structsave(bufferptr,sftglsoff)	// Missing Glissando!
    txa
    ldy #sftortoff
    sta (bufferptr),y
    ldy #sftnrtoff+1
    lda (bufferptr),y
    tax
    ldy #sftortoff+1
    lda (bufferptr),y
    ldy #sftnrtoff+1
    sta (bufferptr),y
 ; :structsave(bufferptr,sftglsoff+1)	// Missing Glissando!
    txa
    ldy #sftortoff+1
    sta (bufferptr),y
fx_a8:
    ldy #sftcmdoff ; Don't start new sample
    lda (bufferptr),y
    and #[$ff-flagnewsmp]
    ldy #sftcmdoff
    sta (bufferptr),y
    rts

fxnslidetonote: ; Tick n
    ldy #sftflgoff ; Glissando mode?
    lda (bufferptr),y
    and #$02
    sec
    bne glissandofx
normalfx03:
    ldy #sftnrtoff ; Old
    lda (bufferptr),y
    ldy #sftortoff ; New
    sbc (bufferptr),y
    sta temp3
    ldy #sftnrtoff+1 ; Old
    lda (bufferptr),y
    ldy #sftortoff+1 ; New
    sbc (bufferptr),y
    ora temp3
    bne	fxstndoit
    rts
fxstndoit:
    ldy #sftstsoff
    lda (bufferptr),y
    sta temp
    ldy #sftortoff
    lax (bufferptr),y
    ldy #sftortoff+1
    lda (bufferptr),y
    ldy temp
    bcc	fx_a9
    jmp slidetomin
fx_a9:
    jmp slidetomax

glissandofx:

    rts


 ; 04 - Vibrato
 ; ************
 ; Tick 0 & n
fx0vibrato: ; Tick 0
    pha
    and #$0f
    beq fx_a10 ; Update amplitude if !=0
    ldy #sftvbaoff
    sta (bufferptr),y
fx_a10:
    pla
    lsr
    lsr
    lsr
    lsr
    beq checkvibretr ; Update speed if !=0
    ldy #sftvbsoff
    sta (bufferptr),y
checkvibretr:
    ldy #sftnntoff ; Check if note played
    lda (bufferptr),y
    beq fx_a11
    ldy #sftvbwoff ; Get waveform
    lda (bufferptr),y
    cmp #$04
    bcs fx_a11
    lda #$00
    ldy #sftvbpoff
    sta (bufferptr),y
fx_a11:
    rts

fxnvibrato: ; Tick n
    ldy #sftvbwoff ; Get table pointer from waveform
    lda (bufferptr),y
    lsr
    ror
    ror
    arr #$c0
    sta temp ; temp = (vbwoff<<5) & 01100000
    ldy #sftvbpoff ; Add position
    lda (bufferptr),y
    and #$1f
    ora temp
    tax ; <pointer> -> delta
    ldy #sftvbpoff ; Update vibrato position (Carry=0 because ARR)
    lda (bufferptr),y
    sta temp
    ldy #sftvbsoff
    adc (bufferptr),y
    cmp #$40
    bcc fx_a12 ; Back to -31 if overflow
    sbc #$40
fx_a12:
    ldy #sftvbpoff ; OK -> Updated
    sta (bufferptr),y
    ldy #sftvbaoff ; Load amplitude
    lda (bufferptr),y
    tay
    lda fxwaveforms,x ; Load table value
    jsr mul8x8 ; Multiply
    asl PRODUCT
    rol ; ACC = (amp*[value])>>7
    ldx #$20
    cpx temp ; Add or subtract value based on current position
    bcs	fx_a13
    ldy #sftnrtoff ; Add value
    adc (bufferptr),y
    tax
    ldy #sftnrtoff+1
    lda (bufferptr),y
    adc #$00
    jmp tfvset
fx_a13:
    sta temp ; Subtract value
    ldy #sftnrtoff
    lda (bufferptr),y
    sbc temp
    tax
    ldy #sftnrtoff+1
    lda (bufferptr),y
    sbc #$00
tfvset:
    tay
    jsr fixperiod ; Translate amiga period to audio module period
    lda PRODUCT+2
    ldy #audrat+1
    sta (bufferptr),y
    lda PRODUCT+3
    ldy #audrat
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagvibrato ; Special case for vibrato (skip freq fixing)
    ldy #sftcmdoff
    sta (bufferptr),y
    rts

 ; 05 - Slide to note + Volume slide
 ; *********************************
 ; Tick 0 & n
fx0notvolslide: ; Tick 0
    tay
    and #$0f
    bne  fxvstndec
    tya
    lsr
    lsr
    lsr
    lsr
    bne fxvstninc
    rts
fxvstninc:
    ldy #sfttx2off
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    and #[$ff-flagnewsmp]
    ldy #sftcmdoff
    sta (bufferptr),y
    rts
fxvstndec:
    eor #$ff
    clc
    adc #$01
    jmp fxvstninc

fxnnotvolslide: ; Tick n
    pha
    ldy #sfttx2off
    lda (bufferptr),y
    jsr fxnvolumeslide
    pla
    jmp fxnslidetonote


 ; 06 - Vibrato + Volume slide
 ; ***************************
 ; Tick 0 & n
fx0volslidevib: ; Tick 0
    tay
    and #$0f
    bne  fxvsvdec
    tya
    lsr
    lsr
    lsr
    lsr
    bne fxvsvinc
    jmp checkvibretr
fxvsvdec:
    eor #$ff
    clc
    adc #$01
fxvsvinc:
    ldy #sfttx2off
    sta (bufferptr),y
    jmp checkvibretr

fxnvolslidevib: ; Tick n
    pha
    ldy #sfttx2off
    lda (bufferptr),y
    jsr fxnvolumeslide
    pla
    jmp fxnvibrato


 ; 07 - Tremolo
 ; ************
 ; Tick 0 & n
fx0tremolo: ; Tick 0
    pha
    and #$0f
    beq fx_a14
    ldy #sfttraoff
    sta (bufferptr),y
fx_a14:
    pla
    lsr
    lsr
    lsr
    lsr
    beq fx_a15
    ldy #sfttrsoff
    sta (bufferptr),y
fx_a15:
    ldy #sftnntoff ; Check if note played
    lda (bufferptr),y
    beq fx_a16
    ldy #sfttrwoff ; Get waveform
    lda (bufferptr),y
    cmp #$04
    bcs fx_a16
    lda #$00
    ldy #sfttrpoff
    sta (bufferptr),y
fx_a16:
    rts

fxntremolo: ; Tick n
    ldy #sfttrwoff ; Get waveform
    lda (bufferptr),y
    lsr
    ror
    ror
    arr #$c0
    sta temp ; temp = (trwoff<<5) & 01100000
    ldy #sfttrpoff ; Add position
    ora (bufferptr),y
    and #$1f
    ora temp
    tax ; <pointer> -> delta
    ldy #sfttrpoff ; Update tremolo position (Carry=0 because ARR)
    lda (bufferptr),y
    sta temp
    ldy #sfttrsoff
    adc (bufferptr),y
    cmp #$40
    bcc fx_a17 ; Back to -31 if overflow
    sbc #$40
fx_a17:
    ldy #sfttrpoff ; OK -> Updated
    sta (bufferptr),y
    ldy #sfttraoff ; Load amplitude
    lda (bufferptr),y
    tay
    lda fxwaveforms,x ; Load table value
    jsr mul8x8 ; Multiply
    asl PRODUCT
    rol
    asl PRODUCT
    rol ; ACC = (amp*[value])>>6
    ldx #$20
    cpx temp ; Add or subtract value based on current position
    bcs	fx_a18
    ldy #sftlvloff ; Add value
    adc (bufferptr),y
    jmp tfvsetvol
fx_a18:
    sta temp ; Subtract value
    ldy #sftlvloff
    lda (bufferptr),y
    sbc temp
tfvsetvol:
    bpl fx_a19
    lda #$00
fx_a19:
    cmp #$41
    bcc fx_a20
    lda #$40
fx_a20:
    ldy #sftvoloff
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagvolume
    ldy #sftcmdoff
    sta (bufferptr),y
    rts


 ; 08 - Panning
 ; ************
 ; Tick 0
fx0setpanning: ; Tick 0
    lsr
    lsr
    lsr
    lsr
    ldy #audpan
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagpanning
    ldy #sftcmdoff
    sta (bufferptr),y
    rts


 ; 09 - Sample offset
 ; ******************
 ; Tick 0
fx0sampleoffset: ; Tick 0
    sta temp
    sec
    ldy #audsml+1
    lda (bufferptr),y
    sbc temp
    tax
    ldy #audsml
    lda (bufferptr),y
    sbc #$00
    bmi fx_a21 ; Value over sample lenght
    ldy #audsml
    sta (bufferptr),y
    txa
    ldy #audsml+1
    sta (bufferptr),y
    clc
    ldy #audsms+2
    lda (bufferptr),y
    adc temp
    ldy #audsms+2
    sta (bufferptr),y
    ldy #audsms+1
    lda (bufferptr),y
    adc #$00
    ldy #audsms+1
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagnewsmp
    ldy #sftcmdoff
    sta (bufferptr),y
fx_a21:
    rts


 ; 0A - Volume slide
 ; *****************
 ; Tick 0 & n
fx0volumeslide: ; Tick 0
    tay
    and #$0f
    bne  fxvsdec
    tya
    lsr
    lsr
    lsr
    lsr
    bne fxvsinc
    rts
fxvsinc:
    ldy #sfttxdoff
    sta (bufferptr),y
    rts
fxvsdec:
    eor #$ff
    clc
    adc #$01
    ldy #sfttxdoff
    sta (bufferptr),y
    rts

fxnvolumeslide: ; Tick n
    clc
    ldy #sftvoloff
    adc (bufferptr),y
    bpl fx_a22
    lda #$00
fx_a22:
    cmp #$41
    bcc fx_a23
    lda #$40
fx_a23:
    ldy #sftvoloff
    sta (bufferptr),y
    ldy #sftlvloff
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagvolume
    ldy #sftcmdoff
    sta (bufferptr),y
    rts


 ; 0B - Jump pattern
 ; *****************
 ; Tick 0
fx0jumppattern: ; Tick 0
    tay
    jsr setpattern
    sta skipdivision
    lda #$00
    sta curdivision
    lda #$01
    sta skipdivision
    rts


 ; 0C - Set volume
 ; ***************
 ; Tick 0
fx0setvolume: ; Tick 0
    ldy #sftvoloff
    sta (bufferptr),y
    ldy #sftlvloff
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagvolume
    ldy #sftcmdoff
    sta (bufferptr),y
    rts


 ; 0D - Pattern break
 ; ******************
 ; Tick 0
fx0patternbreak: ; Tick 0
    tax
    and #$0f
    sta temp
    txa
    lsr
    lsr
    lsr
    lsr
    tax
    lda mul10,x
    clc
    adc temp
    sta curdivision
    ldy patternindex
    iny
    jsr setpattern
    lda #$01
    sta skipdivision
    rts


 ; 0F - Change speed
 ; *****************
 ; Tick 0
fx0changespeed: ; Tick 0
    bne fx_a24
    rts
fx_a24:
    ldx #$01
    stx changetimer
    cmp #$21
    bcs fx_a25
    sta newspeed
    rts
fx_a25:
    sta bpm
    jsr calctimer
    sta timer
    stx timer+1
    rts


 ; Extended "E" FXs
 ; ****************

 ; E1 - Fine slide up
 ; ******************
 ; Tick 0
efx0fineslideup = fxnslideup


 ; E2 - Fine slide down
 ; ********************
 ; Tick 0
efx0fineslidedown = fxnslidedown


 ; E3 - Set glissando mode
 ; ***********************
 ; Tick 0
efxsetglissando:
    asl
    sta temp
    ldy #sftflgoff
    lda (bufferptr),y
    and #$ff-$02
    ora temp
    ldy #sftflgoff
    sta (bufferptr),y
    rts

 ; E4 - Set vibrato waveform
 ; *************************
 ; Tick 0
efx0setvibwave: ; Tick 0
    and #$07
    ldy #sftvbwoff
    sta (bufferptr),y
    rts


 ; E5 - Set fine tune
 ; ******************
 ; Tick 0
efx0setfinetune: ; Tick 0
    pha
    ldy #sftsmpoff ; Get sample number...
    lda (bufferptr),y
    tax
    pla
    sta sampleft-1,x ; ...for finetune
    rts


 ; E6 - Loop pattern
 ; *****************
 ; Tick 0
efx0loop: ; Tick 0
    bne fx_a26
    lda curdivision
    ldy #sftlppoff
    sta (bufferptr),y
    rts
fx_a26:
    ldy #sftlpcoff
    cmp (bufferptr),y
    bne fx_a27
    lda #$00
    ldy #sftlpcoff
    sta (bufferptr),y
    rts
fx_a27:
    ldy #sftlpcoff
    lda (bufferptr),y
    adc #$00
    ldy #sftlpcoff
    sta (bufferptr),y
    ldy #sftlppoff
    lda (bufferptr),y
    sta curdivision
    lda #$01
    sta skipdivision
    rts


 ; E7 - Set tremolo waveform
 ; *************************
 ; Tick 0
efxsettrmwave: ; Tick 0
    and #$07
    ldy #sfttrwoff
    sta (bufferptr),y
    rts


 ; E9 - Retrigger sample
 ; *********************
 ; Tick 0
efx0noteretrigger: ; Tick 0
    ldy #sfttksoff
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ldy #sftbkcoff
    sta (bufferptr),y
    lda #$00
    ldy #sfttkcoff
    sta (bufferptr),y
    jmp efxnnoteretrigger

efxnnoteretrigger: ; Tick 1
    ldy #sfttkcoff
    lda (bufferptr),y
    ldy #sfttksoff
    cmp (bufferptr),y
    bcs fx_a28
    adc #$01
    ldy #sfttkcoff
    sta (bufferptr),y
    rts
fx_a28:
    ldy #sftbkcoff
    lda (bufferptr),y
    ldy #sftcmdoff
    sta (bufferptr),y
    lda #$00
    ldy #sfttkcoff
    sta (bufferptr),y
    rts


 ; EA - Fine slide volume up
 ; *************************
 ; Tick 0
efx0volslideup = fxnvolumeslide ; Tick 0


 ; EB - Fine slide volume down
 ; ***************************
 ; Tick 0
efx0volslidedown: ; Tick 0
    eor #$ff
    clc
    adc #$01
    jmp fxnvolumeslide


 ; EC - Cut note after x ticks
 ; ***************************
 ; Tick 0
efx0cutnote: ; Tick 0
    ldy #sfttksoff
    sta (bufferptr),y
    lda #$00
    ldy #sfttkcoff
    sta (bufferptr),y
    jmp efxncutnote

efxncutnote: ; Tick 1
    ldy #sfttkcoff
    lda (bufferptr),y
    ldy #sfttksoff
    cmp (bufferptr),y
    bcs fx_a29
    adc #$01
    ldy #sfttkcoff
    sta (bufferptr),y
    rts
fx_a29:
    bne fx_a30
    lda #$00
    ldy #sftvoloff
    lda (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagvolume
    ldy #sftcmdoff
    sta (bufferptr),y
fx_a30:
    rts


 ; ED - Start note after x ticks
 ; *****************************
 ; Tick 0
efx0startnote: ; Tick 0
    ldy #sfttksoff
    sta (bufferptr),y
    ldy #sftcmdoff
    lda (bufferptr),y
    ldy #sftbkcoff
    sta (bufferptr),y
    lda #$00
    ldy #sfttkcoff
    sta (bufferptr),y
    ldy #sftcmdoff
    sta (bufferptr),y
    jmp efxnstartnote

efxnstartnote: ; Tick 1
    ldy #sfttkcoff
    lda (bufferptr),y
    ldy #sfttksoff
    cmp (bufferptr),y
    bne fx_a31
    tax
    ldy #sftbkcoff
    lda (bufferptr),y
    ldy #sftcmdoff
    sta (bufferptr),y
    txa
fx_a31:
    clc
    adc #$01
    ldy #sfttkcoff
    sta (bufferptr),y
    rts


 ; EE - Delay pattern
 ; ******************
 ; Tick 0
efx0delaypattern: ; Tick 0
    sta patdelay
    rts


 ; FX related functions
 ; ********************

 ; Slide to MAX
 ; ************
 ; >A,<X: MAX val
 ; Y: Add val
slidetomax:
    sty temp ; Save value to be added
    sta temp2 ; Save HI byte bound value
    stx temp3 ; Save LO byte bound value
    sec
    txa ; Perform (Bound - CurrentValue)...
    ldy #sftnrtoff
    sbc (bufferptr),y
    tax
    lda temp2
    ldy #sftnrtoff+1
    sbc (bufferptr),y
    sta temp4
    bcc	stlimitreached ; If <0 limit reached
    txa ; Check if (Bound - CurrentValue)<AddValue
    cmp temp
    lda temp4
    sbc #$00
    bcc stlimitreached ; If so limit reached
    clc ; Ok, the addvalue can be added safely
    ldy #sftnrtoff
    lda (bufferptr),y
    adc temp
    ldy #sftnrtoff
    sta (bufferptr),y
    tax
    ldy #sftnrtoff+1
    lda (bufferptr),y
    adc #$00
    ldy #sftnrtoff+1
    sta (bufferptr),y
    tay
stsavevalue:
    ldy #sftcmdoff
    lda (bufferptr),y
    ora #flagrate
    ldy #sftcmdoff
    sta (bufferptr),y
    rts
stlimitreached:
    lda temp3
    ldy #sftnrtoff
    sta (bufferptr),y
    tax
    lda temp2
    ldy #sftnrtoff+1
    sta (bufferptr),y
    tay
    bcc stsavevalue


 ; Slide to MIN
 ; ************
 ; >A,<X: MIN val
 ; Y: Sub val
slidetomin:
    sty temp ; Save value to be subtracted
    sta temp2 ; Save HI byte bound value
    stx temp3 ; Save LO byte bound value
    sec ; Perform (CurrentValue - Bound)...
    ldy #sftnrtoff
    lda (bufferptr),y
    sbc temp3
    tax
    ldy #sftnrtoff+1
    lda (bufferptr),y
    sbc temp2
    sta temp4
    bcc	stlimitreached ; If <0 limit reached
    txa ; Check if (CurrentValue - Bound)<AddValue
    cmp temp
    lda temp4
    sbc #$00
    bcc stlimitreached ; If so limit reached
    ldy #sftnrtoff ; Ok, the subvalue can be subtracted safely
    lda (bufferptr),y
    sbc temp
    ldy #sftnrtoff
    sta (bufferptr),y
    tax
    ldy #sftnrtoff+1
    lda (bufferptr),y
    sbc #$00
    ldy #sftnrtoff+1
    sta (bufferptr),y
    tay
    jmp stsavevalue


 ; Exchange glissando note with current
 ; ************************************
xchgglissando:

    rts


 ; Tick FX jump table
 ; ******************
    :[[*+$7F]/$80*$80-*] dta 0      ; (page-aligned 128: one indirect jump table page)
fxtablet0: ; First tick
    dta <fx0arpeggio,>fx0arpeggio ; 0 - OK - Arpeggio
    dta <fxnotimplemented,>fxnotimplemented ; 1 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 2 - OK
    dta <fx0slidetonote,>fx0slidetonote ; 3 - OK - Slide to note
    dta <fx0vibrato,>fx0vibrato ; 4 - OK - Vibrato
    dta <fx0notvolslide,>fx0notvolslide ; 5 - OK - Slide to note + Volume slide
    dta <fx0volslidevib,>fx0volslidevib ; 6 - OK - Vibrato + Volume slide
    dta <fx0tremolo,>fx0tremolo ; 7 - OK - Tremolo
    dta <fx0setpanning,>fx0setpanning ; 8 - OK - Panning
    dta <fx0sampleoffset,>fx0sampleoffset ; 9 - OK - Sample offset
    dta <fx0volumeslide,>fx0volumeslide ; a - OK - Volume slide
    dta <fx0jumppattern,>fx0jumppattern ; b - OK - Jump pattern
    dta <fx0setvolume,>fx0setvolume ; c - OK - Set volume
    dta <fx0patternbreak,>fx0patternbreak ; d - OK - Pattern break
    dta <fxnotimplemented,>fxnotimplemented ; e - OK
    dta <fx0changespeed,>fx0changespeed ; f - OK - Set speed
 ; Extended (E) fx
    dta <fxnotimplemented,>fxnotimplemented ; 0 - Not supported (Hardware filtering)
    dta <efx0fineslideup,>efx0fineslideup ; 1 - OK - Fine portamento up
    dta <efx0fineslidedown,>efx0fineslidedown ; 2 - OK - Fine portamento down
    dta <efxsetglissando,>efxsetglissando ; 3 - OK - Set glissando mode
    dta <efx0setvibwave,>efx0setvibwave ; 4 - OK - Set vibrato waveform
    dta <efx0setfinetune,>efx0setfinetune ; 5 - OK - Set fine tune
    dta <efx0loop,>efx0loop ; 6 - OK - Loop pattern
    dta <efxsettrmwave,>efxsettrmwave ; 7 - OK - Set tremolo waveform
    dta <fxnotimplemented,>fxnotimplemented ; 8 - Not supported (there's 8xx)
    dta <efx0noteretrigger,>efx0noteretrigger ; 9 - OK - Note retrigger
    dta <efx0volslideup,>efx0volslideup ; a - OK - Fine volume slide up
    dta <efx0volslidedown,>efx0volslidedown ; b - OK - Fine volume slide down
    dta <efx0cutnote,>efx0cutnote ; c - OK - Cut note after n tick
    dta <efx0startnote,>efx0startnote ; d - Ok - Start note after n tick
    dta <efx0delaypattern,>efx0delaypattern ; e - OK - Delay pattern
    dta <fxnotimplemented,>fxnotimplemented ; f - Not supported (Invert sample)
fxtabletn: ; Ticks after first
    dta <fxnarpeggio,>fxnarpeggio ; 0 - OK - Arpeggio
    dta <fxnslideup,>fxnslideup ; 1 - OK - Portamento up
    dta <fxnslidedown,>fxnslidedown ; 2 - OK - Portamento down
    dta <fxnslidetonote,>fxnslidetonote ; 3 - OK - Slide to note
    dta <fxnvibrato,>fxnvibrato ; 4 - OK - Vibrato
    dta <fxnnotvolslide,>fxnnotvolslide ; 5 - OK - Slide to note + Volume slide
    dta <fxnvolslidevib,>fxnvolslidevib ; 6 - OK - Vibrato + Volume slide
    dta <fxntremolo,>fxntremolo ; 7 - OK - Tremolo
    dta <fxnotimplemented,>fxnotimplemented ; 8 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 9 - OK
    dta <fxnvolumeslide,>fxnvolumeslide ; a - OK - Volume slide
    dta <fxnotimplemented,>fxnotimplemented ; b - OK
    dta <fxnotimplemented,>fxnotimplemented ; c - OK
    dta <fxnotimplemented,>fxnotimplemented ; d - OK
    dta <fxnotimplemented,>fxnotimplemented ; e - OK
    dta <fxnotimplemented,>fxnotimplemented ; f - OK
 ; Extended (E) fx
    dta <fxnotimplemented,>fxnotimplemented ; 0 - Not supported (Hardware filtering)
    dta <fxnotimplemented,>fxnotimplemented ; 1 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 2 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 3 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 4 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 5 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 6 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 7 - OK
    dta <fxnotimplemented,>fxnotimplemented ; 8 - Not supported (there's 8xx)
    dta <efxnnoteretrigger,>efxnnoteretrigger ; 9 - OK  - Note retrigger
    dta <fxnotimplemented,>fxnotimplemented ; a - OK
    dta <fxnotimplemented,>fxnotimplemented ; b - OK
    dta <efxncutnote,>efxncutnote ; c - OK  - Cut note after n tick
    dta <efxnstartnote,>efxnstartnote ; d - OK  - Start note after n tick
    dta <fxnotimplemented,>fxnotimplemented ; e - OK
    dta <fxnotimplemented,>fxnotimplemented ; f - Not supported (Invert sample)

mul10:
    dta 0, 10, 20, 30, 40, 50, 60, 70, 80, 90



; ---- periodfix.asm (fixperiod) ----
 ; Get real period (amiga period)x(periodratio) in fixed point
 ; ***********************************************************
 ; IN: <X,>Y => Period to transform
fixperiod:
    stx ARG2
    sty ARG2+1
    lda #<fpperiodratio
    sta ARG1
    lda #>fpperiodratio
    sta ARG1+1
    sec ; Compute FT +1 - +7
    jmp mult16x16 ; Results in PRODUCT+2,+3



; ---- math.asm ----
 ; Description: Unsigned multiplication routines

fpprecbits = 15 ; Fixed point precision bits

 ; Multiply functions
 ; ******************

 ; Generic 8x8 => 16 multiplier
 ; *****************************
 ; IN: A = Multiplier
 ; Y = Multiplier
 ; OUT: A = Hi byte of product
 ; PRODUCT (2 bytes)
 ; Clobbered: -
mul8x8:
    sty SPARE ; 3 Save first multiplier
    lsr ; 2
    sta PRODUCT ; 3 counter (shift based)
    lda #$00 ; 2 Product Hi = 0
    ldy #$08 ; 2 - 13
loop:
    bcc math_a0 ; 2/3
    clc ; 2
    adc SPARE ; 3
math_a0:
    ror ; 2
    ror PRODUCT ; 5
    dey ; 2
    bne loop ; 2/3 - WORST: 19*7+18 => 143 / BEST: 15*7+14 => 119
    sta PRODUCT+1 ; 3
    ldy SPARE ; 3
    rts ; 6 - 10 => WORST: 175 / BEST: 145


 ; Input: 16-bit unsigned value in ARG1
 ; 16-bit unsigned value in ARG2

 ; Output: 32-bit unsigned value in PRODUCT

 ; Clobbered: PRODUCT, X, A, C

 ; Allocation setup: ARG1,ARG2 and PRODUCT preferably on Zero-page.
mult16x16:
    sty SPARE
    lda ARG2
    sta PRODUCT+2
    lda ARG2+1
    sta PRODUCT+3
    lda #$00
    sta PRODUCT+1
    ldx #$10
m16loop:
    asl ; 2
    rol PRODUCT+1 ; 5
    rol PRODUCT+2 ; 5
    rol PRODUCT+3 ; 5
    bcc math_a1 ; 2/3
    clc ; 2
    adc ARG1 ; 3
    tay ; 2
    lda PRODUCT+1 ; 3
    adc ARG1+1 ; 3
    sta PRODUCT+1 ; 3
    tya ; 2
    bcc math_a1 ; 2/3
    inc PRODUCT+2 ; 5
    bne math_a1 ; 2/3
    inc PRODUCT+3 ; 5
math_a1: ; 2
    dex
    bne m16loop ; 3	- 37
    asl
    rol PRODUCT+1
    rol PRODUCT+2
    rol PRODUCT+3
    sta PRODUCT
savey:
    ldy SPARE
    rts


 ; 24bit/16bit slow division (taken from codebase)
 ; ***********************************************
divide24x16:
    lda #0 ; preset remainder to 0
    sta SPARE
    sta SPARE+1
    ldx #24 ; repeat for each bit: ...
divloop:
    asl DIVIDEND ; dividend lb & hb*2, msb -> Carry
    rol DIVIDEND+1
    rol DIVIDEND+2
    rol SPARE ; remainder lb & hb * 2 + msb from carry
    rol SPARE+1
    lda SPARE
    sec
    sbc DIVISOR ; substract divisor to see if it fits in
    tay ; lb result -> Y, for we may need it later
    lda SPARE+1
    sbc DIVISOR+1
    bcc skip ; if carry=0 then divisor didn't fit in yet

    sta SPARE+1 ; else save substraction result as new remainder,
    sty SPARE
    inc DIVIDEND ; and INCrement result cause divisor fit in 1 times
skip:
    dex
    bne divloop
    rts


; ---- audio.asm (fastplay, resetaudio) ----
; fastplay (audio.asm, ModPlayer_16k): the play buffers to the Ultimate
; Audio registers, for the flags set; then the flags cleared. A loop over
; the 4 channels here (the original is unrolled: 600 bytes).
fastplay:
    ldx #0                      ; X: the buffer, Y: the channel
    ldy #0
fp_ch:
    lda buffers+sftcmdoff,x
    lsr
    bcc fp_nv
    pha                         ; volume
    lda buffers+audvol,x
    sta audch1+audvol,y
    pla
fp_nv:
    lsr
    bcc fp_np
    pha                         ; panning
    lda buffers+audpan,x
    sta audch1+audpan,y
    pla
fp_np:
    lsr
    bcc fp_nr
    pha                         ; rate
    lda buffers+audrat,x
    sta audch1+audrat,y
    lda buffers+audrat+1,x
    sta audch1+audrat+1,y
    pla
fp_nr:
    lsr
    bcc fp_nl
    pha                         ; repeat points
    lda buffers+audrpa,x
    sta audch1+audrpa,y
    lda buffers+audrpa+1,x
    sta audch1+audrpa+1,y
    lda buffers+audrpa+2,x
    sta audch1+audrpa+2,y
    lda buffers+audrpb,x
    sta audch1+audrpb,y
    lda buffers+audrpb+1,x
    sta audch1+audrpb+1,y
    lda buffers+audrpb+2,x
    sta audch1+audrpb+2,y
    pla
fp_nl:
    lsr
    bcc fp_next
    lda buffers+audsms,x        ; a new sample: start, length, control
    sta audch1+audsms,y
    lda buffers+audsms+1,x
    sta audch1+audsms+1,y
    lda buffers+audsms+2,x
    sta audch1+audsms+2,y
    lda buffers+audsms+3,x
    sta audch1+audsms+3,y
    lda buffers+audsml,x
    sta audch1+audsml,y
    lda buffers+audsml+1,x
    sta audch1+audsml+1,y
    lda buffers+audsml+2,x
    sta audch1+audsml+2,y
    lda #$00
    sta audch1+audctr,y
    lda buffers+audctr,x
    sta audch1+audctr,y
fp_next:
    lda #0
    sta buffers+sftcmdoff,x
    tya
    clc
    adc #$20
    tay
    txa
    clc
    adc #$40
    tax
    beq fp_rts
    jmp fp_ch
fp_rts:
    rts

 ; Reset Audio Module
 ; ******************
resetaudio:
    lda #$00
    ldx #$1e
audio_a0:
    sta audch1,x
    sta audch2,x
    sta audch3,x
    sta audch4,x
    sta audch5,x
    sta audch6,x
    sta audch7,x
    dex
    bpl audio_a0
    rts

 ; Detect 1541U2 audio module
 ; **************************
 ; OUT: C=0 (not detected)
 ; C=1 A=version

; ---- reu_routines.asm (reu_loadfix16) ----
 ; Reu load 16 bytes (Fixed lenght)
 ; ********************************
 ; IN: Y/Acc/X - REU address
reu_loadfix16:                  ; (the MOS's REU register names)
    stx REU_ADDR
    sty REU_ADDR+1
    sta REU_BANK
    lda #$10
    sta REU_LEN
    lda #$00
    sta REU_LEN+1
    lda #<division
    sta REU_C64
    lda #>division
    sta REU_C64+1
    lda #$00
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    rts

; fxwaveforms (module.asm): vibrato and tremolo waves, 32 each: sine
; (ProTracker's), ramp, square, random (the original fills it with
; random() at assembly time; a fixed set here)
    :[[*+$7F]/$80*$80-*] dta 0
fxwaveforms:
    dta 0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253
    dta 255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24
    dta 255, 247, 239, 231, 223, 215, 207, 199, 191, 183, 175, 167, 159, 151, 143, 135
    dta 127, 119, 111, 103, 95, 87, 79, 71, 63, 55, 47, 39, 31, 23, 15, 7
    dta 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    dta 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    dta 125, 16, 192, 209, 227, 239, 76, 61, 141, 160, 220, 165, 38, 238, 108, 82
    dta 126, 217, 238, 31, 137, 140, 76, 194, 120, 172, 146, 12, 22, 179, 223, 227

; ----------------------------------------------------------------------------
; Variables (RAM in the image; the original's zero page, varbase)
temp        dta 0
temp2       dta 0
temp3       dta 0
temp4       dta 0
temp5       dta 0
patternptr  dta 0, 0            ; the patterns' offset in the module
nsamples    dta 0
songlenght  dta 0
mainvolume  dta 0
monomode    dta 0
PRODUCT     dta 0, 0, 0, 0
ARG1        dta 0, 0
ARG2        dta 0, 0
DIVISOR     dta 0, 0
DIVIDEND    dta 0, 0, 0
SPARE       dta 0, 0, 0
patdelay    dta 0
patternsnumber dta 0
curpattern  dta 0
patternindex dta 0
curdivision dta 0
curtick     dta 0
skipdivision dta 0
timer       dta 0, 0
changetimer dta 0
newspeed    dta 0
tickperdiv  dta 0
bpm         dta 0
fxjump      dta 0, 0, 0         ; jmp (table): its low byte is set
mp_on       dta 0               ; 1: playing
mp_tacc     dta 0, 0            ; TIME's correction (8.8)
mp_tstep    dta 0, 0
mt_ext      dta 0
mi_off      dta 0, 0
mi_byte     dta 0
mp_order    :128 dta 0          ; the order table (modplay.s)
division    :16 dta 0           ; the row being played (16 bytes)
sampleptrl  :32 dta 0           ; per sample: start (3), length (3),
sampleptrm  :32 dta 0           ; loop start and end (3 + 3, relative),
sampleptrh  :32 dta 0           ; looped, volume, finetune
samplelenl  :32 dta 0
samplelenm  :32 dta 0
samplelenh  :32 dta 0
samplerepal :32 dta 0
samplerepam :32 dta 0
samplerepah :32 dta 0
samplerepbl :32 dta 0
samplerepbm :32 dta 0
samplerepbh :32 dta 0
samplerep   :32 dta 0
samplevol   :32 dta 0
sampleft    :32 dta 0
    :[[*+$FF]/$100*$100-*] dta 0  ; (page-aligned: bufferptr's low byte)
buffers:
buffer1     = buffers+$00
buffer2     = buffers+$40
buffer3     = buffers+$80
buffer4     = buffers+$C0
    :256 dta 0
mi_end:
