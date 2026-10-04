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
FONT        = $C800             ; 2K character set (lower/upper + ASCII)

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

; MOS zero page: $52-$8F (BBC BASIC uses $00-$51, the KERNAL $90-$FF)
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
ramvars_end = inkey_t0+2
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
