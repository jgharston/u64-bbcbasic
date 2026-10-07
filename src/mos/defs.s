; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- MOS definitions shared by every bank
;
; Memory map and design: docs/PLAN.md section 4, docs/ARCHITECTURE.md.
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
BANK_HELP   = 3                 ; first help bank: index + texts (tools/genhelp.py)
BANK_RAM    = $FF               ; cartridge off: BASIC runs from its RAM
                                ; copy at $8000-$BFFF. The Ultimate 64 runs
                                ; cartridge ROM fetches at 1 MHz, RAM at
                                ; turbo speed (measured, docs/PLAN.md)
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
gzp         = $FB               ; engine pointer (C64 user zero page)
GX_MODE     = 0                 ; engine entries (gfx.s jump table)
GX_VDU      = 3
GX_CHAR     = 6
GX_PET      = 9
GX_CURSOR   = 12
GX_POINT    = 15
GX_MATRIX   = 18
REU_FONT_BANK = 0               ; REU system area (DESIGN_GRAPHICS.md 6)
REU_FONT    = $0000             ; 2K: font in ASCII order (bitmap modes)
REU_VICFONT = $0800             ; 2K: the text-mode font, for MODE changes

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
ramvars_end = uf_end+1
    .if ramvars_end > $03FC
    .error "MOS RAM variables overflow the cassette buffer"
    .endif

; Error blocks raised outside BASIC's RAM copy are copied here, because
; BASIC reads the message through FAULT after the MOS bank is unmapped.
; $02A7-$02FF is unused by the KERNAL; unlike page 1 it cannot collide
; with the machine stack while BASIC's error handler runs.
errbuf      = $02A7
ERRMAX      = $0300-errbuf      ; 89 bytes: number, message, terminator
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
