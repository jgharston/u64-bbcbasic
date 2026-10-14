; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- function keys (*KEY), bank 0
;
; *KEY n text: function key Fn (1-8, the C64's labels: F2, F4, F6, F8 are
; Shift+F1, F3, F5, F7) types the text, as on a BBC Micro. The texts are
; kept in the REU (bank 0, REU_KEYS + n * 64: length, up to 63 bytes of
; ASCII), the expansion's state in the RAM core (kx_*). Every key the MOS
; reads goes through key_avail / key_get (OSRDCH, INKEY, the line
; editor): an F-key with a text gives the text's characters one by one.
; F1 is the line editor's COPY while *KEY 1 is not set. With *EDIT C64
; the KERNAL's editor reads the keys itself: no expansion there.
;
; ----------------------------------------------------------------------------

REU_KEYS    = $3600             ; REU bank 0: keys 0-9, 64 bytes each
ck_hi       = mosTMP+2          ; *KEY: |! seen (bit 7 for the next one)
ck_cmd      = mosARGS           ; ck_dma: the REU command
KEY_MAX     = 63                ; characters per key

; ----------------------------------------------------------------------------
; key_init
;   Summary: no key texts at the cold start.
;   Function: the REU keeps its contents over a reset and holds anything
;            after power-on: the ten slots (REU_KEYS, 640 bytes) are set to
;            0 by one DMA from a 0 byte with the C64 address held still.
;   Input:   reu_banks.  Output: the slots empty.  Uses: A, reu_tmp.
key_init:
    lda reu_banks
    ora reu_banks+1
    beq ki_rts
    lda #0
    sta reu_tmp
    php                         ; (interrupts off while the REU is set up)
    sei
    sta REU_ADDR
    sta REU_BANK
    sta REU_LEN
    lda #>REU_KEYS
    sta REU_ADDR+1
    lda #>[10*64]
    sta REU_LEN+1
    lda #<[10*64]
    sta REU_LEN
    lda #<reu_tmp
    sta REU_C64
    lda #>reu_tmp
    sta REU_C64+1
    lda #$80                    ; the C64 address held
    sta REU_CTRL
    lda #REU_TO_REU
    sta REU_CMD
    lda #0
    sta REU_CTRL
    plp
ki_rts:
    rts

; ----------------------------------------------------------------------------
; key_avail
;   Summary: is there a key to read (typed, or an expansion going on)?
;   Input:   none.  Output: Z = 0 yes, Z = 1 no.  Uses: A.
key_avail:
    lda kx_n
    ora NDX
    rts

; ----------------------------------------------------------------------------
; key_get
;   Summary: the next key, as PETSCII (as K_GETIN gives it).
;   Function: an expansion going on gives its next character (ASCII to
;            PETSCII; CR and DELETE too; other control codes give 0, which
;            the readers ignore). Otherwise K_GETIN; an F-key whose *KEY
;            text is set starts that text instead.
;   Input:   none.
;   Output:  A = PETSCII code, 0 when there is none.  Uses: A, X, Y.
key_get:
    lda kx_n
    bne kg_next
    jsr K_GETIN
    jsr kg_esc
    cmp #$85
    bcc kg_rts
    cmp #$8D
    bcs kg_rts
    tax                         ; F1-F8: is its text set?
    lda kg_fnum-$85,x
    tay
    lda kx_def
    and kg_bits-1,y
    bne kg_start
    txa                         ; no: the code itself (F1: COPY)
kg_rts:
    rts
kg_start:
    sty kx_key
    lda #0
    sta kx_pos
    jsr kx_len                  ; its length from the REU
    sta kx_n
    beq kg_none
kg_next:
    jsr kx_char
    inc kx_pos
    dec kx_n
    cmp #13
    beq kg_rts
    cmp #127
    bne kg_conv
    lda #$14                    ; DELETE
    rts
kg_conv:
    tax
    bmi kg_none
    lda asc2pet,x
    rts
kg_none:
    lda #0
    rts

; kg_esc: *FX 220 (acorn.s): a typed key that is the escape character
; (other than 27) sets ESCAPE instead.  Input: A = PETSCII.  Output: A
; (0: none).  Uses: A, X.
kg_esc:
    tax
    beq kge_rts
    lda acorn.ac_fx220
    beq kge_none
    lda pet2asc,x
    eor #27
    cmp acorn.ac_fx220
    beq kge_esc
kge_none:
    txa
kge_rts:
    rts
kge_esc:
    lda #$80
    sta ESCFLG
    lda #0
    rts

; F-key codes $85-$8C (F1, F3, F5, F7, F2, F4, F6, F8) -> key number
kg_fnum:
    dta 1, 3, 5, 7, 2, 4, 6, 8
; key number 1-8 -> its bit in kx_def
kg_bits:
    dta 1, 2, 4, 8, 16, 32, 64, 128

; kx_len / kx_char: byte 0 (the length) / byte 1 + kx_pos of key kx_key's
; slot in the REU.  Output: A.  Uses: A, X, Y.
kx_len:
    ldy #0
    beq kx_byte
kx_char:
    ldy kx_pos
    iny
kx_byte:
    lda kx_key                  ; REU_KEYS + key * 64 + Y
    lsr
    lsr
    sta mosTMP+1
    lda kx_key
    and #3
    lsr
    ror
    ror
    sta mosTMP                  ; (key AND 3) * 64
    tya
    clc
    adc mosTMP
    php                         ; (interrupts off while the REU is set up:
    sei                         ; the sound interrupt uses it too)
    sta REU_ADDR
    lda mosTMP+1
    adc #>REU_KEYS
    sta REU_ADDR+1
    lda #<[mosTMP+2]
    sta REU_C64
    lda #>[mosTMP+2]
    sta REU_C64+1
    lda #1
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_BANK
    sta REU_CTRL
    lda #REU_TO_C64
    sta REU_CMD
    plp
    lda mosTMP+2
    rts

; ----------------------------------------------------------------------------
; cmd_key
;   Summary: *KEY n text: set function key n (0-9; on the keyboard 1-8);
;            *KEY n alone clears it; *KEY alone lists the keys set.
;   Function: the text as the BBC's GSTRANS reads it: "..." optional,
;            |M CR, |A-|Z and |@ |[ |\ |] |^ |_ control codes, |? 127,
;            || |, |" ", |! the next character + 128. Stored in the REU
;            (length, text), kx_def updated; an expansion of that key
;            going on stops.
;   Input:   mosPTR/Y = rest of the command line.
;   Output:  the key; "Bad key" for n > 9, "Needs an REU" without one,
;            "Key too long" past 63 characters.
;   Uses:    A, X, Y, MOSBUF, mosTMP, mosNUM, kx_*.
cmd_key:
    lda reu_banks
    ora reu_banks+1
    bne ck_reu
    brk
    dta 254, 'Needs an REU', 0
ck_reu:
    jsr cli_byte
    bcc ck_n
    jmp ck_list
ck_n:
    cmp #10
    bcc ck_ok
    brk
    dta 251, 'Bad key', 0
ck_ok:
    sta kx_key
    lda #0
    sta kx_n                    ; (an expansion going on stops)
    sta mosTMP+3                ; quoted (bit 6)
    sta ck_hi                   ; |! (bit 7 for the next character)
    ldx #0                      ; MOSBUF+1.. the text
    jsr cli_skipsp
    cmp #','                    ; (*KEY 1,text as some BBC programs write)
    bne ck_q
    iny
    jsr cli_skipsp
ck_q:
    cmp #'"'
    bne ck_char
    iny
    sec                         ; quoted: up to the closing "
    ror mosTMP+3
    lsr mosTMP+3                ; (bit 6: quoted)
ck_char:
    lda (mosPTR),y
    cmp #13
    beq ck_end
    iny
    cmp #'"'
    bne ck_bar
    bit mosTMP+3
    bvs ck_end                  ; the closing quote
ck_bar:
    cmp #'|'
    bne ck_put
    lda (mosPTR),y
    cmp #13
    beq ck_end
    iny
    jsr ck_gs
    bcs ck_char                 ; |! : no character yet
ck_put:
    ora ck_hi                   ; (|! before it: + 128)
    pha
    lda #0
    sta ck_hi
    pla
    cpx #KEY_MAX
    bcc ck_store
    brk
    dta 253, 'Key too long', 0
ck_store:
    sta MOSBUF+1,x
    inx
    bne ck_char
ck_end:
    stx MOSBUF                  ; the length
    ldy kx_key
    lda kg_bits-1,y             ; kx_def bit (keys 1-8)
    cpy #1
    bcc ck_write
    cpy #9
    bcs ck_write
    ora kx_def
    cpx #0
    bne ck_def
    eor kg_bits-1,y             ; (cleared)
ck_def:
    sta kx_def
ck_write:
    lda #REU_TO_REU
    jmp ck_dma

; ck_gs: the character after |: A in, the code out with C = 0, or C = 1
; for |! (sets ck_hi).  Uses: A.
ck_gs:
    cmp #'!'
    bne ckg_q
    lda #$80
    sta ck_hi
    sec
    rts
ckg_q:
    cmp #'?'
    bne ckg_bar
    lda #127
    clc
    rts
ckg_bar:
    cmp #'|'
    beq ckg_same
    cmp #'"'
    beq ckg_same
    cmp #'@'                    ; @ A-Z [ \ ] ^ _ (and lower case): 0-31
    bcc ckg_same
    and #$1F
ckg_same:
    clc
    rts


; ck_dma: MOSBUF (64 bytes) to or from key kx_key's slot (A = command).
; Uses: A, mosTMP, ck_cmd.
ck_dma:
    sta ck_cmd
    lda kx_key                  ; REU_KEYS + key * 64
    lsr
    lsr
    clc
    adc #>REU_KEYS
    sta mosTMP+1
    lda kx_key
    and #3
    lsr
    ror
    ror
    php                         ; (interrupts off: see kx_byte)
    sei
    sta REU_ADDR
    lda mosTMP+1
    sta REU_ADDR+1
    lda #<MOSBUF
    sta REU_C64
    lda #>MOSBUF
    sta REU_C64+1
    lda #64
    sta REU_LEN
    lda #0
    sta REU_LEN+1
    sta REU_BANK
    sta REU_CTRL
    lda ck_cmd
    sta REU_CMD
    plp
    rts

; ck_list: *KEY alone: "*KEY n text" for each key set (control codes as
; |X, codes over 127 with |!).
ck_list:
    lda #0
    sta kx_key
ckl_key:
    lda #REU_TO_C64
    jsr ck_dma
    ldx MOSBUF
    beq ckl_next
    cpx #KEY_MAX+1
    bcs ckl_next                ; (an REU never written)
    ldx #0
ckl_head:
    lda ckl_text,x
    beq ckl_num
    jsr OSWRCH
    inx
    bne ckl_head
ckl_num:
    lda kx_key
    ora #'0'
    jsr OSWRCH
    lda #' '
    jsr OSWRCH
    ldx #0
ckl_char:
    lda MOSBUF+1,x
    bpl ckl_lo
    pha
    lda #'|'
    jsr OSWRCH
    lda #'!'
    jsr OSWRCH
    pla
    and #$7F
ckl_lo:
    cmp #32
    bcs ckl_print
    pha
    lda #'|'
    jsr OSWRCH
    pla
    ora #$40
ckl_print:
    cmp #'|'
    bne ckl_out
    jsr OSWRCH                  ; (| as ||)
ckl_out:
    jsr OSWRCH
    inx
    cpx MOSBUF
    bcc ckl_char
    jsr OSNEWL
ckl_next:
    inc kx_key
    lda kx_key
    cmp #10
    bcc ckl_key
    rts
ckl_text:
    dta '*KEY ', 0
