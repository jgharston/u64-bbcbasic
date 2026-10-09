; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- resident MOS, runs from RAM at $C400-$C7FF
;
; Copied from cartridge bank 0 at cold start. Holds everything that must
; work whichever cartridge bank is mapped: the BBC MOS entry points, the
; bank-switching trampoline behind the RAM vectors, and the IRQ, BRK, NMI
; and keyboard-decode handlers. Header conventions: see mos.s.
;
; Interrupt safety: irq_main, irq_brk, irq_nmi and irq_keylog use only
; A, X, Y (saved by the KERNAL or by the handler) and MOS RAM variables
; that the foreground reads with interrupts off. They never use the MOS
; zero page ($52-$5F) or the trampoline variables, so an interrupt in the
; middle of a MOS call cannot corrupt it.
;
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; tramp
;   Summary: call a MOS routine in any cartridge bank from any memory
;            configuration.
;   Function: saves the caller's bank on the stack, maps tramp_bank, calls
;            the routine, maps the caller's bank back. Re-entrant (a MOS
;            routine may call OSWRCH etc. again): each level keeps its own
;            bank on the stack, and tramp_tgt/tramp_bank are only read
;            before the call.
;   Input:   tramp_tgt = routine, tramp_bank = its bank; A, X, Y, C, V =
;            the routine's arguments.
;   Output:  A, X, Y and P as the routine left them.
;   Uses:    tr_a, tr_p, curbank; 3 bytes of stack plus the routine's.

tramp:
    sta tr_a
    lda curbank
    pha
    lda tramp_bank
    jsr map_bank
    lda tr_a
    jsr tramp_jmp
    php
    sta tr_a
    pla
    sta tr_p
    pla
    jsr map_bank
    lda tr_p
    pha
    lda tr_a
    plp
    rts

tramp_jmp:
    jmp (tramp_tgt)

; v_cli .. v_find (macro vstub)
;   Summary: default targets of the BBC RAM vectors at $0200: call the
;            matching MOS routine in its bank through tramp.
;   Input:   A, X, Y, C, V as for the MOS call (lda/sta leave C and V
;            alone; the final lda restores N and Z for A).
;   Output:  as the MOS routine.
;   Uses:    tr_a, tramp_tgt, tramp_bank.

vstub .macro target, bank
    sta tr_a
    lda #<:target
    sta tramp_tgt
    lda #>:target
    sta tramp_tgt+1
    lda #:bank
    sta tramp_bank
    lda tr_a
    jmp tramp
    .endm

v_cli   vstub mos_cli, BANK_MOS
v_byte  vstub mos_byte, BANK_MOS
v_word  vstub mos_word, BANK_MOS
v_wrch  vstub mos_wrch, BANK_MOS
v_rdch  vstub mos_rdch, BANK_MOS
v_file  vstub fs_file, BANK_FS
v_args  vstub fs_args, BANK_FS
v_bget  vstub fs_bget, BANK_FS
v_bput  vstub fs_bput, BANK_FS
v_gbpb  vstub fs_gbpb, BANK_FS
v_find  vstub fs_find, BANK_FS

; ----------------------------------------------------------------------------
; bank_peek
;   Summary: read one byte from another cartridge bank (help texts).
;   Input:   X = bank, mosPTR/Y = address in $8000-$BFFF.
;   Output:  A = byte. X and Y preserved; the caller's bank is mapped back.
;   Uses:    flags; 1 byte of stack.

bank_peek:
    lda curbank
    pha
    txa
    jsr map_bank
    lda (mosPTR),y
    sta tr_p
    pla
    jsr map_bank
    lda tr_p
    rts

; ----------------------------------------------------------------------------
; map_bank
;   Summary: show a cartridge bank at $8000-$BFFF, or switch the cartridge
;            off so the RAM copy of BASIC is visible there.
;   Input:   A = bank number, or BANK_RAM.
;   Output:  curbank = A. X and Y preserved; A and flags changed.
;   Notes:   runs from RAM; the cartridge bank is set before it is mapped.

map_bank:
    sta curbank
    cmp #BANK_RAM
    beq map_ram
    lda #CPU_ROMS
    sta $01
    lda curbank
    sta CART_BANK
    lda #CART_MODE16
    sta CART_CTRL
    rts
map_ram:
    lda #CART_OFF
    sta CART_CTRL
    lda #CPU_RAMBAS
    sta $01
    rts

; ----------------------------------------------------------------------------
; copy_basic
;   Summary: copy BBC BASIC from cartridge bank 1 to the RAM underneath
;            ($8000-$BFFF). Reading shows the ROM, writing reaches the RAM.
;   Input:   called from bank 0 (cold start).
;   Output:  bank 0 mapped again. A, X, Y changed; uses mosPTR.

copy_basic:
    lda #BANK_BASIC
    jsr map_bank
    lda #<LANGROM
    sta mosPTR
    lda #>LANGROM
    sta mosPTR+1
    ldx #$40                    ; 64 pages = 16K
    ldy #0
cb_loop:
    lda (mosPTR),y
    sta (mosPTR),y
    iny
    bne cb_loop
    inc mosPTR+1
    dex
    bne cb_loop
    lda #BANK_MOS
    jmp map_bank

; ----------------------------------------------------------------------------
; enter_lang
;   Summary: start the language (BBC BASIC) from its RAM copy.
;   Input:   none.  Output: does not return.

enter_lang:
    lda #BANK_RAM
    jsr map_bank
    lda #1                      ; BBC language entry
    jmp LANGROM

; ----------------------------------------------------------------------------
; irq_main (via $0314)
;   Summary: MOS part of the 60 Hz KERNAL interrupt.
;   Function: BBC TIME at 100 Hz: adds 1, 2, 2 centiseconds in turn
;            (5 per 3 interrupts). The CIA timer behind it keeps real time
;            at turbo speed (measured: 99-100 per second on both U64s).
;            RUN/STOP is ESCAPE: on the key-down edge it sets ESCFLG and,
;            during OSWORD 0, types RETURN to end the line (if the
;            keyboard buffer has room).
;   Input:   STKEY (RUN/STOP state from the previous interrupt).
;   Output:  mostime, timefrac, stopheld, ESCFLG, keyboard buffer.
;   Uses:    A, X (pushed by the KERNAL). Continues into the KERNAL's own
;            handler (jiffy clock, cursor, keyboard scan).

irq_main:
    ldx timefrac
    lda timestep,x
    clc
    adc mostime
    sta mostime
    bcc irq_tdone
    inc mostime+1
    bne irq_tdone
    inc mostime+2
    bne irq_tdone
    inc mostime+3
    bne irq_tdone
    inc mostime+4
irq_tdone:
    dex
    bpl irq_tstep
    ldx #2
irq_tstep:
    stx timefrac

irq_keys:                       ; (Upic Lite's frame interrupt joins here)
    lda snd_on                  ; sound (sound.s): durations, envelopes
    beq irq_nosnd               ; (none under *SOUND NONE)
    jsr SNDV_IRQ
irq_nosnd:
    lda STKEY               ; $7F while RUN/STOP is held (last UDTIM)
    cmp #$7F
    bne irq_nostop
    lda stopheld
    bne irq_done
    inc stopheld
    lda escdis
    bne irq_done
    lda #$80
    sta ESCFLG
    lda inlinein
    beq irq_done
    ldx NDX                 ; finish the line being typed
    cpx #10
    bcs irq_done
    lda #13
    sta KBUF,x
    inc NDX
    bne irq_done
irq_nostop:
    lda #0
    sta stopheld
irq_done:
    jmp K_IRQ_EXIT

timestep:
    dta 1, 2, 2

; ----------------------------------------------------------------------------
; irq_brk (via $0316, and from irq_nmi)
;   Summary: BBC error handling: point FAULT at the error block and enter
;            the language's error handler through BRKV.
;   Function: FAULT = BRK address + 1 (from the stacked PC). An error
;            raised while a cartridge bank is mapped is copied to errbuf
;            (at most ERRMAX bytes, always terminated) and the RAM copy of
;            BASIC is mapped back, because BASIC reads the message through
;            FAULT afterwards. The stack is left as it is: BASIC's error
;            handler resets it, discarding the frames of the failed call.
;   Input:   stack: Y, X, A, P, PCL, PCH (as pushed by the KERNAL).
;   Output:  FAULT, errbuf, MB_ERRNUM/MB_ERRCNT (remote mailbox); jumps
;            to (BRKV) with interrupts on.
;   Uses:    A, Y.

irq_brk:
    cld
    tsx
    lda $0105,x
    sec
    sbc #1
    sta FAULT
    lda $0106,x
    sbc #0
    sta FAULT+1
    lda curbank
    cmp #BANK_RAM
    beq brk_go
    ldy #0
    lda (FAULT),y           ; error number (may be 0)
    sta errbuf
brk_copy:
    iny
    cpy #ERRMAX-1
    bcs brk_trunc
    lda (FAULT),y
    sta errbuf,y
    bne brk_copy
    beq brk_copied
brk_trunc:
    lda #0
    sta errbuf,y
brk_copied:
    lda #<errbuf
    sta FAULT
    lda #>errbuf
    sta FAULT+1
    lda #BANK_RAM
    jsr map_bank
brk_go:
    ldy #0                      ; remote mailbox: report the error
    lda (FAULT),y
    sta MB_ERRNUM
    inc MB_ERRCNT
    cli
    jmp (BRKV)

; ----------------------------------------------------------------------------
; irq_nmi (via $0318, after the KERNAL's SEI)
;   Summary: NMI: RESTORE key and CIA 2; rescue a BRK hidden by an NMI.
;   Function: on the NMOS 6502 an NMI arriving during a BRK takes over the
;            BRK, which then never reaches the IRQ/BRK vector. The pushed
;            P has the B flag set in that case, and the BRK is handled
;            here (ivop/bbc-basic README; the stack layout matches the
;            KERNAL's). RESTORE (no CIA 2 source) sets ESCAPE for now.
;   Input:   stack: P, PCL, PCH.
;   Output:  ESCFLG; CIA 2 interrupt acknowledged.
;   Uses:    A, X, Y (saved and restored), nmi_icr.

irq_nmi:
    pha
    txa
    pha
    tya
    pha
    lda $DD0D               ; acknowledge CIA 2
    sta nmi_icr
    tsx
    lda $0104,x
    and #$10
    bne irq_brk          ; the stack is laid out as for BRK
    lda nmi_icr
    bmi nmi_done            ; CIA 2 source: nothing to do yet
    lda escdis
    bne nmi_done
    lda #$80
    sta ESCFLG
nmi_done:
    pla
    tay
    pla
    tax
    pla
    rti

; ----------------------------------------------------------------------------
; irq_keylog (via $028F, from the KERNAL keyboard scan in the IRQ)
;   Summary: choose the keyboard decode table.
;   Function: the KERNAL's own logic ($EB48) without the Shift+C= charset
;            switch, using the RAM tables with CAPS LOCK swapped in
;            (keyboard_init) for unshifted and shifted keys.
;   Input:   SHFLAG (1 Shift, 2 C=, 4 Ctrl).
;   Output:  KTABPTR; continues in the KERNAL decoder.
;   Uses:    A, X (the KERNAL scan's own registers).

irq_keylog:
    lda SHFLAG
    asl
    cmp #8
    bcc irq_keytab
    lda #6
irq_keytab:
    tax
    lda keytabs,x
    sta KTABPTR
    lda keytabs+1,x
    sta KTABPTR+1
    jmp K_KEYDECODE

keytabs:
    dta a(kt_unshift), a(kt_shift), a(K_KEYTAB_C), a(K_KEYTAB_CT)

; ----------------------------------------------------------------------------
; raise_errbuf
;   Summary: raise the BBC error block that is already in errbuf (built by
;            the UCI code from an Ultimate status message).
;   Function: like irq_brk after its copy: FAULT = errbuf, the RAM copy of
;            BASIC mapped, then BASIC's error handler through BRKV, which
;            resets the stack (no frames are leaked).
;   Input:   errbuf = error number, message, 0.
;   Output:  does not return.

raise_errbuf:
    lda #<errbuf
    sta FAULT
    lda #>errbuf
    sta FAULT+1
    lda #BANK_RAM
    jsr map_bank
    jmp brk_go                  ; report to the mailbox, enter BRKV

res_code_end:

; ----------------------------------------------------------------------------
; Resident MOS RAM: copied from ROM as zeros, so it starts cleared.
; Filing system state (bank 2, foreground only).

ch_open     dta 0, 0            ; per channel: 0 closed, else OSFIND mode
ch_ptr      dta 0,0,0,0, 0,0,0,0    ; per channel: PTR#, 32 bits
ch_ext      dta 0,0,0,0, 0,0,0,0    ; per channel: EXT#, 32 bits
uci_ok      dta 0               ; 1: Ultimate command interface found
uciHDR      dta 0,0,0,0,0,0,0,0 ; UCI command header (target, command, args)
fsTMP       dta 0,0,0,0         ; scratch
fsMODE      dta 0               ; OSFIND / OSFILE call in progress
fsSX        dta 0               ; caller's X during a filing system call
fsSY        dta 0               ; caller's Y
reu_banks   dta 0, 0            ; REU size in 64K banks (0: none)
reu_tmp     dta 0               ; REU byte transfers
reu_save0   dta 0
reu_saveS   dta 0
rd_ok       dta 0               ; there is an REU RAM disk (reudisk.s)
reu_cwd     dta 0               ; /REU is the current directory
rd_chent    dta 0, 0            ; per channel on /REU: its entry
snd_on      dta 0               ; a sound engine image is in RAM (not NONE)
iec_dev     dta 0               ; serial-bus device for the IEC helpers
softiec_dev dta 0               ; SoftIEC drive's device number (0: unknown)
osfblk      dta 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; OSFILE block for *LOAD/*SAVE

res_data_end:
    .if res_data_end > MBOX
    .error "Resident MOS overflows into the remote mailbox"
    .endif

; ----------------------------------------------------------------------------
; Remote mailbox at MBOX (layout in defs.s, protocol in docs/REMOTE_DEV.md)

    :[MBOX-*] dta 0
    dta 'BBCR', 1               ; magic, protocol version
    :[MB_END-*] dta 0
    .if MB_END > OSPAGE+$CE
    .error "Remote mailbox overflows into the entry points"
    .endif

; ----------------------------------------------------------------------------
; BBC MOS entry points, same low bytes as $FFCE-$FFF9 on the BBC Micro.
; Each jumps through its RAM vector at $0200 (a program may redirect it);
; OSASCI/OSNEWL/OSWRCR follow the BBC's: CR becomes LF + CR.

    :[OSPAGE+$CE-*] dta 0

OSFIND  jmp (FINDV)             ; $C7CE
OSGBPB  jmp (GBPBV)             ; $C7D1
OSBPUT  jmp (BPUTV)             ; $C7D4
OSBGET  jmp (BGETV)             ; $C7D7
OSARGS  jmp (ARGSV)             ; $C7DA
OSFILE  jmp (FILEV)             ; $C7DD
OSRDCH  jmp (RDCHV)             ; $C7E0
OSASCI  cmp #13                 ; $C7E3
        bne OSWRCH
OSNEWL  lda #10                 ; $C7E7
        jsr OSWRCH
OSWRCR  lda #13                 ; $C7EC
OSWRCH  jmp (WRCHV)             ; $C7EE
OSWORD  jmp (WORDV)             ; $C7F1
OSBYTE  jmp (BYTEV)             ; $C7F4
OSCLI   jmp (CLIV)              ; $C7F7

    .if OSWRCH != OSPAGE+$EE || OSCLI != OSPAGE+$F7
    .error "MOS entry points misplaced"
    .endif

    :[RESIDENT+$400-*] dta 0
