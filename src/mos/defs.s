; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- MOS definitions shared by every bank
;
; Memory map and design: docs/ARCHITECTURE.md.
;
; ----------------------------------------------------------------------------

; Cartridge type (one of these is defined on the MADS command line)
;   CART_EF  : EasyFlash subtype 1 (VICE, fallback; UCI at $DE1C, no UA)
;   CART_TMB : Protovision TwoMegabyter, CRT type 87 (UCI, REU, UA, turbo)

    .if .def CART_EF
UCI_BASE    = $DE1C             ; EasyFlash makes the firmware move UCI
CART_MODE16 = $87               ; $DE02: 16K mode + LED
CART_OFF    = $04               ; $DE02: cartridge off
    .elseif .def CART_TMB
UCI_BASE    = $DF1C
CART_MODE16 = $00               ; $DE02: standard 16K mode
CART_OFF    = $03               ; $DE02: cartridge disabled
    .else
    .error "Define CART_EF or CART_TMB"
    .endif

CART_BANK   = $DE00             ; bank register (both types)
CART_CTRL   = $DE02             ; mode register (both types)

BANK_MOS    = 0                 ; boot + MOS core + help reader
BANK_BASIC  = 1                 ; BBC BASIC 3.10 language ROM (copy source)
BANK_FS     = 2                 ; UCI driver, filing system, Ultimate commands
BANK_GFX    = 3                 ; graphics: modes, palettes, Upic Lite (gxbank.s)
BANK_UL     = 4                 ; Upic Lite RAM images (ulbank.s)
BANK_RD     = 5                 ; the REU RAM disk (reudisk.s)
BANK_SND    = 6                 ; sound: engine images, commands (sndbank.s)
BANK_NET    = 7                 ; network (netbank.s)
BANK_UP     = 8                 ; Upic full: *UPIC, MODE 110/111 (upbank.s)
BANK_TOOLS  = 9                 ; tools: *EDIT, Acorn, DFS, toolkit (toolbank.s)
BANK_AUD    = 10                ; Ultimate Audio: samples, MOD (audbank.s)
BANK_HELP   = 11                ; first help bank: index + texts (tools/genhelp.py)
BANK_RAM    = $FF               ; cartridge off: BASIC runs from its RAM
                                ; copy at $8000-$BFFF. The Ultimate 64 runs
                                ; cartridge ROM fetches at 1 MHz, RAM at
                                ; turbo speed (measured)
CPU_ROMS    = $37               ; $01: BASIC, KERNAL, I/O (cartridge visible)
CPU_RAMBAS  = $36               ; $01: RAM at $A000-$BFFF, KERNAL, I/O

; ----------------------------------------------------------------------------
; RAM layout

SCREEN      = $C000             ; text screen (VIC bank 3)
RESIDENT    = $C400             ; resident MOS, $C400-$C7FF
OSPAGE      = $C700             ; BBC MOS entry points at $C7CE-$C7FF
FONT        = $F000             ; 2K character set (lower/upper + ASCII), under the KERNAL
CORE        = $C800             ; VDU core in RAM, 2K (core.s)
ENGINE      = $D000             ; drawing engine, 4K under I/O (gfx.s)
BITMAP      = $E000             ; VIC-II bitmap in the bitmap modes
TTXBUF      = $7C00             ; MODE 7 screen memory (teletext codes)
MOSBUF      = $0800             ; 256: scratch for * commands (below PAGE)
SOUNDRAM    = $0900             ; sound engine image: code, queues, voice state
SNDSHR      = $1C60             ; 160: what both sound images share
OSHWM       = $1D00             ; PAGE: above the sound engine (DESIGN_SOUND.md 4)
OSHWM_NONE  = $0900             ; lowest PAGE with *SOUND NONE
gzp         = $FB               ; engine pointer (C64 user zero page)
GX_MODE     = 0                 ; engine entries (gfx.s jump table)
GX_VDU      = 3
GX_CHAR     = 6
GX_PET      = 9
GX_CURSOR   = 12
GX_POINT    = 15
GX_MATRIX   = 18
GX_TODEV    = 21
GX_LINE     = 24
GX_RECT     = 27
GX_PSET     = 30
GX_POINTDEV = 33
MR_RX2      = 0                 ; 48-bit slots in m48 (core), gxshape.s
MR_RY2      = 6
MR_TRX2     = 12
MR_TRY2     = 18
MR_PX       = 24
MR_PY       = 30
MR_P        = 36
MR_T        = 42
MR_T2       = 48
MR_A        = 54
MR_B        = 60
; arc variables (gxshape.s sh_arc): in m48's slots 0-53, which only the
; ellipse uses (sh_hypot needs MR_A, MR_B)
sha_sx      = m48+0
sha_sy      = m48+2
sha_vx      = m48+4             ; (sha_vy must follow: sas_ok, X = 2)
sha_vy      = m48+6
sha_a0      = m48+8
sha_a1      = m48+9
sha_i       = m48+10
sha_sg      = m48+11
sha_best    = m48+12
sha_bd      = m48+13
sha_dot     = m48+15
sha_bx      = m48+17
sha_by      = m48+18
sha_ma      = m48+19
sha_mb      = m48+20
sha_mr      = m48+21
sha_ms      = m48+23
sha_save    = m48+24            ; 16 bytes: slots during a triangle
REU_FONT_BANK = 0               ; REU system area (DESIGN_GRAPHICS.md 6)
REU_FONT    = $0000             ; 2K: font in ASCII order (bitmap modes)
REU_VICFONT = $0800             ; 2K: the text-mode font, for MODE changes
REU_DEFFONT = $1000             ; 2K: the start-up text font (*FONT DEFAULT)
REU_INST    = $2000             ; 4K: 64 instruments x 64 bytes (sound)
REU_ENV     = $3000             ; 208: the 16 BBC envelopes (ENVELOPE)
REU_SONGBANK = 1                ; the song (DESIGN_TRACKER.md): header,
REU_HEAD    = $0000             ; 256: header
REU_ORDER   = $0100             ; 256: order list (pattern numbers)
REU_ROWS    = $0200             ; 256: rows per pattern (1-64)
REU_PATBANK = 2                 ; patterns from $020000, $1200 each:
PAT_MAX     = 28                ; up to $03F7FF (banks 2 and 3)

LANGROM     = $8000             ; language ROM entry (A=1: start)

; BBC MOS RAM vectors, at the same addresses as on the BBC Micro. The
; C64 BASIC input buffer at $0200-$0258 is free without C64 BASIC.
USERV       = $0200
BRKV        = $0202
IRQ1V       = $0204
IRQ2V       = $0206
CLIV        = $0208
BYTEV       = $020A
WORDV       = $020C
WRCHV       = $020E
RDCHV       = $0210
FILEV       = $0212
ARGSV       = $0214
BGETV       = $0216
BPUTV       = $0218
GBPBV       = $021A
FINDV       = $021C
FSCV        = $021E
NVECTORS    = 16

; BBC zero page used by the MOS interface (as in BBC BASIC's C64 target)
FAULT       = $FD               ; pointer to the last error block
ESCFLG      = $FF               ; bit 7 set: Escape pending

; MOS zero page: $52-$6F. BBC BASIC uses $00-$51, the KERNAL $90-$FF;
; $70-$8F stays free for users' machine code, as &70-&8F on a BBC Micro.
; Foreground only: interrupt handlers never use it.
zpMOS       = $52
mosPTR      = zpMOS+0           ; general pointer (2)
mosPTR2     = zpMOS+2           ; second pointer (2)
mosTMP      = zpMOS+4           ; scratch (4)
mosCNT      = zpMOS+8           ; line input count
mosMAX      = zpMOS+9           ; line input maximum
mosMIN      = zpMOS+10          ; line input lowest accepted char
mosHIGH     = zpMOS+11          ; line input highest accepted char
mosNUM      = zpMOS+12          ; *command number parsing (2)
mosARGS     = zpMOS+14          ; *FX arguments (3)

; Filing system and UCI zero page (bank 2)
fsPTR       = $63               ; 2: filename / data pointer
fsLEN       = $65               ; 2: length
fsCNT       = $67               ; 2: byte counter
fsADDR      = $69               ; 2: memory address for transfers
fsTGT       = $6B               ; UCI target of the current file operation
fsCH        = $6C               ; channel index 0/1
uciHLEN     = $6D               ; UCI command header length
fsBLK       = $6E               ; 2: OSFILE parameter block
    .if fsBLK+1 > $6F
    .error "MOS zero page overflows into the user area $70-$8F"
    .endif

; ----------------------------------------------------------------------------
; C64 KERNAL

K_IOINIT    = $FDA3
K_RAMTAS    = $FD50
K_RESTOR    = $FD15
K_CINT      = $FF5B
K_CHRIN     = $FFCF
K_CHROUT    = $FFD2
K_GETIN     = $FFE4
K_PLOT      = $FFF0
K_IRQ_EXIT  = $EA31             ; standard IRQ handler (jiffy, keyboard)
K_KEYDECODE = $EAE0             ; KEYLOG continuation: decode via ($F5)
K_SETCURSOR = $EA13             ; put char A, colour X at cursor
K_KEYTAB_C  = $EC03             ; Commodore-key table
K_KEYTAB_CT = $EC78             ; Ctrl table

KBUF        = $0277             ; keyboard buffer (10 bytes)
RVS         = $C7               ; KERNAL: reverse video on (cleared at CR)
NDX         = $C6               ; keys in buffer
STKEY       = $91               ; $7F while RUN/STOP is held
BLNSW       = $CC               ; 0: cursor blinks
BLNON       = $CF               ; cursor currently shown
GDBLN       = $CE               ; character under the cursor
GDCOL       = $0287             ; colour under the cursor
QTSW        = $D4               ; quote mode
INSRT       = $D8               ; insert count
COLOR       = $0286             ; text colour
HIBASE      = $0288             ; screen page for the editor
SHFLAG      = $028D             ; shift/C=/ctrl state
KEYLOG      = $028F             ; keyboard decode vector
MODE        = $0291             ; $80: no shift+C= charset switch
CINV        = $0314             ; IRQ vector
CBINV       = $0316             ; BRK vector
NMINV       = $0318             ; NMI vector
KTABPTR     = $F5               ; current keyboard decode table

; ----------------------------------------------------------------------------
; Ultimate 64 turbo (docs: lib ultimate-uci-oscar64 TURBOCONTROL_MANUAL.md)

U64_TURBO   = $D031             ; bits 0-3 speed index, bit 7 no badlines
U64_TURBOEN = $D030             ; "Turbo Enable Bit" firmware mode
TURBO_MAX   = $8F               ; index 15 (hardware maximum), no badlines


; ----------------------------------------------------------------------------
; MOS RAM variables in the cassette buffer $033C-$03FB (not copied from ROM)

kt_unshift  = $033C             ; 65: keyboard table, CAPS LOCK swapped
kt_shift    = kt_unshift+65     ; 65: shifted table
curbank     = kt_shift+65       ; cartridge bank currently selected
tramp_tgt   = curbank+1         ; 2: trampoline target
tramp_bank  = tramp_tgt+2       ; trampoline target bank
tr_a        = tramp_bank+1      ; trampoline A
tr_p        = tr_a+1            ; trampoline P
mostime     = tr_p+1            ; 5: BBC TIME, centiseconds
timefrac    = mostime+5         ; 60 -> 100 Hz step index
stopheld    = timefrac+1        ; RUN/STOP seen in the previous IRQ
escdis      = stopheld+1        ; *FX 229: escape key disabled
inlinein    = escdis+1          ; inside OSWORD 0 (RUN/STOP ends the line)
nmi_icr     = inlinein+1        ; CIA2 interrupt flags at NMI
curson      = nmi_icr+1         ; VDU 23,1: cursor enabled
vduq        = curson+1          ; VDU parameter bytes still expected
vducmd      = vduq+1            ; VDU code waiting for parameters
vduidx      = vducmd+1          ; parameters received
vdubuf      = vduidx+1          ; VDUBUFLEN: VDU parameters
wr_a        = vdubuf+9          ; OSWRCH register save
wr_x        = wr_a+1
wr_y        = wr_x+1
rd_x        = wr_y+1            ; OSRDCH register save
rd_y        = rd_x+1
by_a        = rd_y+1            ; OSBYTE register save
by_x        = by_a+1
by_y        = by_x+1
turbo_state = by_y+1            ; 0 none, 1 enable bit, 2 U64 registers
inkey_t0    = turbo_state+1     ; 2: INKEY start time
dbg_state   = inkey_t0+2        ; TRACE parser: 0 idle, 1 after '['
dbg_len     = dbg_state+1       ; digits seen
dbg_num     = dbg_len+1         ; 2: line number being read
dbg_skipsp  = dbg_num+2         ; 1: swallow the space after ']'
aw_start_y  = dbg_skipsp+1      ; arg_word: start of the word in the line
aw_i        = aw_start_y+1      ; arg_word: index into the word
aw_c        = aw_i+1            ; arg_word: character being compared
cwd_dv      = aw_c+1            ; clock: divisor
cwd_ql      = cwd_dv+1          ; clock: quotient (2)
cwd_qh      = cwd_ql+1
cwd_rem     = cwd_qh+1          ; clock: remainder
cwd_n       = cwd_rem+1         ; 2: clock: dividend
uf_off      = cwd_n+2           ; uci_finish: status position in errbuf+1
uf_end      = uf_off+1          ; uci_finish: end of the status
eng_kind    = uf_end+1          ; engine at $D000: 0 VIC-II, 1 Upic Lite, 2 teletext
pal_ok      = eng_kind+1        ; 1: the Ultimate takes palette commands
shadow      = pal_ok+1          ; 1: the next MODE is a shadow mode (*SHADOW)
mode_shadow = shadow+1          ; 1: the current mode is a shadow mode
tbgon       = mode_shadow+1     ; text mode: COLOUR 128+n set (reverse video)
ttfg        = tbgon+1           ; text mode: C64 colour of COLOUR n
ramvars_end = ttfg+1
UP_STUB     = $E000             ; Upic full (MODE 110/111): the engine's
US_RD       = UP_STUB+0         ; REU and console stub (upstub.s), with
US_WR       = UP_STUB+3         ; text on the VIC-II screen $E000-$EFFF
US_FILL     = UP_STUB+6         ; is free
US_GET      = UP_STUB+9
US_PUT      = UP_STUB+12
US_SCROLL   = UP_STUB+15
US_CLROW    = UP_STUB+18
US_FILLALL  = UP_STUB+21
UP_BUF      = $E200             ; a column segment (256 bytes)
US_N        = $E3FE             ; stub: bytes to move (0 = 256)
US_BYTE     = $E3FF             ; stub: the byte read, written or filled
UP_DIRTY    = $0335             ; Upic full: bit 0 drawn since the last
                                ; show (the stub sets it), bit 7 *UPIC
                                ; AUTO OFF (0 at the MOS's cold start)
FONT46      = $033B             ; 1: the 4x6 font is in the REU font
                                ; (VIC-II MODE 1, gxbank.s fnt46)
f46_c1      = MOSBUF+$F8        ; fnt46's moves: commands, REU addresses,
f46_c2      = MOSBUF+$F9        ; the chunk (MOSBUF+0-$FF carries the data:
f46_a1      = MOSBUF+$FA        ; these are past its last 248-byte chunk)
f46_a2      = MOSBUF+$FB
f46_h1      = MOSBUF+$FC
f46_h2      = MOSBUF+$FD
f46_n       = MOSBUF+$FE
up_kind     = $0336             ; Upic full's show (upic.s): its kind,
up_lim      = $0337             ; time limit (2, frames), key mode and how
up_norel    = $0339             ; it ended (RAM: bank 8 is ROM; $0336-
up_bykey    = $033A             ; $033B: unused by the KERNAL)
UP_SIG      = $0334             ; Upic full ($0334-$0335: unused by the
                                ; KERNAL; not $03FE/F: the JSON handles):
                                ; UP_SHOWING while a picture
UP_SHOWING  = $55               ; shows (the mailbox is swapped out then);
UP_ENDSHOW  = $AA               ; a host writes UP_ENDSHOW to end it as a
                                ; key does (upic.s, u64remote endshow)
snd_8sid    = $03FD             ; the 8SID layout was loaded (*SID SETUP):
                                ; the SID list is set, not probed ($03FC-
                                ; $03FF: free on the C64; RAMTAS clears it;
                                ; $03FE/F: the JSON handles, netcmd.s)
    .if ramvars_end > $03FC
    .error "MOS RAM variables overflow the cassette buffer"
    .endif

; Error blocks raised outside BASIC's RAM copy are copied here, because
; BASIC reads the message through FAULT after the MOS bank is unmapped.
; $02A7-$02FF is unused by the KERNAL; unlike page 1 it cannot collide
; with the machine stack while BASIC's error handler runs.
errbuf      = $02A7
ERRMAX      = 56                ; number, message (54), terminator
; The rest of $02A7-$02FF (cleared by RAMTAS at the cold start): MOS
; variables (the resident area is full).
osfblk      = errbuf+ERRMAX     ; 18: OSFILE block for *LOAD/*SAVE
ch_ptr      = osfblk+18         ; 8: per channel: PTR#, 32 bits
reu_tmp     = ch_ptr+8          ; REU byte transfers
reu_save0   = reu_tmp+1
reu_saveS   = reu_save0+1
iec_dev     = reu_saveS+1       ; serial-bus device for the IEC helpers
softiec_dev = iec_dev+1         ; SoftIEC drive's device number (0: unknown)
caps_ofs    = softiec_dev+1     ; CAPS LOCK: 0 on, 8 off (irq_keylog)
rd_ok       = caps_ofs+1        ; there is an REU RAM disk (reudisk.s)
    .if rd_ok >= $0300
    .error "Page 2 MOS variables overflow"
    .endif
; $0220-$0258: the C64 BASIC input buffer after the BBC vectors (free:
; neither the KERNAL nor BBC BASIC uses it). DFS commands (dfs.s).
DF_EXEC     = $0220             ; *EXEC's channel (0: none)
DF_EXCR     = $0221             ; *EXEC: the last byte was CR (a LF after
                                ; it is skipped)
DF_SPCH     = $0222             ; *SPOOL's channel (0: none)
DF_SPLEN    = $0223             ; 2: bytes spooled (in the REU)
DF_SPBANK   = $0225             ; the REU bank spooled into (its last)
DF_BYTE     = $0226             ; a byte for the REU transfers
DF_STUB     = $0228             ; *SPOOL's WRCHV stub (code, to $0258)
LSTSHF      = $028E             ; KERNAL: shift keys at the last scan
VDUBUFLEN   = 9                 ; longest VDU parameter list (VDU 23)

; ----------------------------------------------------------------------------
; farcall target, bank
;   Summary: call a routine in another cartridge bank (through tramp).
;   Input:   A, X, Y, C, V = the routine's arguments.
;   Output:  A, X, Y, P as the routine left them.
;   Uses:    tr_a, tramp_tgt, tramp_bank.

farcall .macro target, bank
    sta tr_a
    lda #<:target
    sta tramp_tgt
    lda #>:target
    sta tramp_tgt+1
    lda #:bank
    sta tramp_bank
    lda tr_a
    jsr tramp
    .endm

; ----------------------------------------------------------------------------
; Remote mailbox (docs/REMOTE_DEV.md): fixed address in the resident page,
; reachable by the Ultimate's REST/DMA memory access. The host writes the
; data first and MB_HSEQ last; the MOS answers by copying it to MB_CSEQ.

MBOX        = $C6E0
MB_MAGIC    = MBOX+0            ; 4: "BBCR"
MB_VERSION  = MBOX+4            ; protocol version (1)
MB_HSEQ     = MBOX+5            ; host -> C64 request sequence number
MB_CSEQ     = MBOX+6            ; C64 -> host: last request handled
MB_REQ      = MBOX+7            ; request: 1 line, 3 capture, 4 program
MB_STATUS   = MBOX+8            ; 0 idle, 1 waiting for a line, 2 running,
                                ; 3 paused (debugger)
MB_LINENO   = MBOX+9            ; 2: line about to run (debug mode)
MB_DEBUG    = MBOX+11           ; debug flags: bit 0 on, bit 1 step
MB_RINGW    = MBOX+12           ; output ring: write index (C64)
MB_RINGR    = MBOX+13           ; output ring: read index (host)
MB_CAPTURE  = MBOX+14           ; 1: OSWRCH output also goes to the ring
MB_LINELEN  = MBOX+15           ; length of MB_LINE
MB_PROG     = MBOX+16           ; 1: a program was written to PAGE
MB_PROMPT   = MBOX+17           ; page of the line buffer while waiting:
                                ; &07 BASIC prompt/AUTO, &06 INPUT
MB_ERRNUM   = MBOX+18           ; number of the last error (ERR)
MB_ERRCNT   = MBOX+19           ; counts errors (host sees new ones)
MB_LINE     = MBOX+20           ; 74: line text / request data
MB_LINEMAX  = 74
MB_BREAK    = MBOX+94           ; 16: 8 breakpoint line numbers, 0 = free
MB_RING     = MBOX+110          ; 128: output ring
MB_RINGMASK = $7F
MB_END      = MBOX+238

REQ_LINE    = 1
REQ_DEBUG   = 2                 ; data: 1 continue, 2 step, 3 stop
REQ_CAPTURE = 3
REQ_PROGRAM = 4

; ----------------------------------------------------------------------------
; Sound (sound.s, DESIGN_SOUND.md): engine entry points in RAM, the data
; both images share, constants for the engine and its commands.

zpTXTP      = $18               ; BASIC's PAGE (high byte)

SNDV_INIT    = SOUNDRAM+0        ; reset the voices
SNDV_IRQ     = SOUNDRAM+3        ; from the interrupt
SNDV_PUT     = SOUNDRAM+6        ; queue s_qbuf on voice X (C = 1: full)
SNDV_ADVAL   = SOUNDRAM+9        ; X = voice: X = free queue bytes
SNDV_STOP    = SOUNDRAM+12       ; silence, empty the queues
SNDV_BELL    = SOUNDRAM+15       ; VDU 7
SNDV_FLUSH   = SOUNDRAM+18       ; voice X: queue emptied, sound off
SNDV_IMG     = SOUNDRAM+21       ; which image: 0 BBC, 1 SID

NV          = 24                ; voices (8 SIDs x 3)
QLEN        = 3                 ; queued notes per voice (MOS 1.20: 15 bytes)
IHDR        = 53                ; instrument bytes copied at note-on (to the
                                ; table speed; the tables stay in the REU)
QF_SYNC     = $0F               ; queue flags: start with S other voices,
QF_HOLD     = $10               ; hold,
QF_TIE      = $20               ; change the playing note (SID mode)

s_mode      = SNDSHR+0          ; 0 SID mode, 1 BBC mode
s_off       = SNDSHR+1          ; *SOUND OFF
s_nsid      = SNDSHR+2          ; SIDs found
s_sidlo     = SNDSHR+3          ; 8: SID base addresses
s_sidhi     = SNDSHR+11         ; 8
s_f17       = SNDSHR+19         ; 8: filter routing / resonance per SID
s_f18       = SNDSHR+27         ; 8: filter mode / volume per SID
s_qbuf      = SNDSHR+35         ; 5: the note to queue (SNDV_PUT)
ftab_lo     = SNDSHR+40         ; 48: the octave of middle C in quarter
ftab_hi     = SNDSHR+88         ; 48: semitones (PAL or NTSC)
ntab_lo     = SNDSHR+136        ; 6: BBC noise frequencies
ntab_hi     = SNDSHR+142        ; 6
t_rec       = SNDSHR+148        ; *SONG RECORD on (sndcmd.s)
s_qlvl      = SNDSHR+149        ; SID mode: the queued note's level (0: the
                                ; instrument's own; SND_PUT)
s_dirty     = SNDSHR+150        ; SID image's work bytes (room in its own
s_vlo       = SNDSHR+151        ; area is short): s_mod: the pitch moved;
s_vhi       = SNDSHR+152        ; s_pitch: pitch with arpeggio, vibrato
s_frac      = SNDSHR+153
s_qlo       = SNDSHR+154
s_qhi       = SNDSHR+155
s_f0lo      = SNDSHR+156
s_f0hi      = SNDSHR+157
s_vsign     = SNDSHR+158
s_tmpx      = SNDSHR+159
SNDSHR_END  = SNDSHR+160
    .if SNDSHR_END > OSHWM
    .error "Shared sound data overflows PAGE"
    .endif
