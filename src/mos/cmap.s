; ----------------------------------------------------------------------------
;
; U64 BBC BASIC -- CharPad maps and fonts: *MAP, *FONT LOAD of CTM files
; (bank 8)
;
; CharPad's CTM project files (owner, 2026-10-15; formats from CharPad
; C64 3.69 Pro's help, "File Format - CTM (V6)" to "(V9)"): the character
; set becomes the font (*FONT LOAD, *MAP LOAD); *MAP LOAD also keeps the
; map in the REU, tiles expanded to characters, with each cell's colour
; (per project, per tile or per character), and *MAP DRAW copies any part
; of it to the C64 text screen; *MAP GET reads a cell into M%.
; docs/DESIGN_GRAPHICS.md 12.
;
; The file is first loaded whole into the REU's file scratch bank
; (fs_reuopen0/fs_reurest, bank 2: one LOAD_REU, or a copy from /REU) and
; read there. The map goes to the REU's last bank but one (cm_bank; the
; RAM disk ends below it, rd_resbank):
;   &0000  header: "MAP", width (2), height (2)
;   &0100  the colour of each character (256)
;   &0200  the saved page &0700 while a map loads
;   &1000  the characters, a row of width bytes per map row, no gaps
;   &8800  their colours, the same way
; at most 30720 cells, up to 65535 wide or high (owner, 2026-10-16).
;
; ----------------------------------------------------------------------------

    .local cmap

SCR_BANK    = $0A               ; REU: the file (gxr.GXR_SCR, transient)
MB_HDR      = $0000             ; the map bank
MB_CCOL     = $0100
MB_SAVE     = $0200
MB_CHARS    = $1000
MB_COLS     = $8800
MB_MAX      = $7800             ; cells

; *MAP, *MAP DRAW, *MAP GET ($0240-$0258: scratch shared with dfs.s and
; the toolkit, never at the same time)
DA          = $0240             ; 12: DRAW's six arguments, 16 bits each
DOFF        = $024C             ; DRAW: a part off the map or screen
DIDX        = $024D             ; DRAW: the argument's offset
HOW         = $0250             ; 2: the map's width, height (header)
HOH         = $0252             ; 2

; *MAP LOAD and *FONT LOAD of a CTM file: in BASIC's string buffer page
; (&0600, free between statements; a command given by OSCLI is read
; before the buffers are written)
ROWCOL      = $0600             ; 128: a run of colours
LV          = $0680             ; the variables, up to &06FE
RP          = LV+0              ; 2: the read position in the file
CHARPOS     = LV+2              ; 2: the character images
CSRC        = LV+4              ; 2: per-character colours
CSTR        = LV+6              ; their stride (0: none)
TILEPOS     = LV+7              ; 2: the tiles
TCOLPOS     = LV+9              ; 2: per-tile colours
TSTR        = LV+11             ; their stride (0: none)
MAPPOS      = LV+12             ; 2: the map cells
MW          = LV+14             ; 2: map width, height (cells)
MH          = LV+16             ; 2
TW          = LV+18             ; tile width, height (1 without tiles)
TH          = LV+19
OW          = LV+20             ; 2: the map's width, height in characters
OH          = LV+22             ; 2
METH        = LV+24             ; colour method (0 project, 1 tile, 2 char)
COLR        = LV+25             ; the project's character colour
NCH         = LV+26             ; characters (0: 256 or more)
RB          = LV+27             ; 2: the map row's cells
CP          = LV+29             ; 2: the next map cell
TA          = LV+31             ; 2: the next tile cell
CY          = LV+33             ; the row within the tiles
CYT         = LV+34             ; its offset: CY * TW
CX          = LV+35             ; the column within the tile
CH          = LV+36             ; the character
XX          = LV+37             ; 2: the column (characters)
YY          = LV+39             ; 2: the row
OP          = LV+41             ; 2: the output's position (cells)
NB          = LV+43             ; cells in the buffers
BG          = $06FF             ; the screen colour
ROWCHR      = MOSBUF            ; 128: a run of characters (also: header)
COLTAB      = $0700             ; the colour of each character (256; the
                                ; page saved and put back)
VER         = mosARGS           ; the file's version
BPX         = mosARGS+1         ; bytes per colour entry (CharPad 3)
TILES       = mosARGS+2         ; the file has tiles
TCOL        = mosARGS+1         ; the tile's colour (ct_map)
TMP         = mosTMP            ; 4: scratch, cm_mul16's product
MX          = mosNUM            ; 2: DRAW's map offset
M1          = mosARGS           ; 2: cm_mul16's factors (M1 destroyed)
M2          = fsBLK             ; 2
SC_BYTE     = uciHLEN           ; a byte read from the file (zero page)
CT_T        = fsCNT             ; 2: a tile's number
CT_TS       = fsCH              ; cells per tile
CT_P        = mosPTR2           ; 2: an address
BUFN        = 128               ; the run buffers' size

; ----------------------------------------------------------------------------
; cmd_map
;   Summary: *MAP LOAD file | *MAP DRAW mx,my,w,h AT col,row | *MAP GET
;            mx,my | *MAP (what is loaded).
;   Input:   mosPTR/Y.  Output: per subcommand.  Uses: A, X, Y, fs*,
;            mosTMP, mosNUM, mosARGS, mosPTR2, MOSBUF, $0240-$0258,
;            $0600-$07FF.
cmd_map:
    jsr cm_need
    jsr bvc.s6_skipsp
    cmp #13
    bne cm_word
    jmp cm_info
cm_word:
    lda #<wm_load
    ldx #>wm_load
    jsr bvc.s6_word
    bcc cm_nload
    jmp cm_load
cm_nload:
    lda #<wm_draw
    ldx #>wm_draw
    jsr bvc.s6_word
    bcc cm_ndraw
    jmp cm_draw
cm_ndraw:
    lda #<wm_get
    ldx #>wm_get
    jsr bvc.s6_word
    bcc cm_syn
    jmp cm_get
cm_syn:
    jmp bvc.s6_syntax
wm_load     dta 'LOAD', 0
wm_draw     dta 'DRAW', 0
wm_get      dta 'GET', 0
wm_at       dta 'AT', 0

; cm_need: an REU ("Maps need an REU")
cm_need:
    jsr bvc.s6_hasreu
    bne cmn_rts
    brk
    dta 254, 'Maps need an REU', 0
cmn_rts:
    rts

; cm_bank: A = the map's REU bank (the last but one)
cm_bank:
    lda reu_banks+1
    bne cmb_16
    lda reu_banks
    sec
    sbc #2
    rts
cmb_16:
    lda #$FE
    rts

; ----------------------------------------------------------------------------
; cm_info: *MAP: "Map 120 x 50 characters" or "No map loaded"
cm_info:
    jsr cm_hdrget
    bcc cmi_have
    jsr bvc.s6_text
    dta 'No map loaded (*MAP LOAD)', 13, 0
    rts
cmi_have:
    jsr bvc.s6_text
    dta 'Map ', 0
    lda HOW
    ldx HOW+1
    jsr cm_dec
    jsr bvc.s6_text
    dta ' x ', 0
    lda HOH
    ldx HOH+1
    jsr cm_dec
    jsr bvc.s6_text
    dta ' characters', 13, 0
    rts

; cm_dec: A/X (low/high) in decimal (st_dec16, bank 2)
cm_dec:
    sta mosTMP
    stx mosTMP+1
    jmp bvc.s6_dec16

; cm_hdrget: the map bank's header -> HOW, HOH. C = 1 when there is none.
cm_hdrget:
    lda #<MB_HDR
    ldx #>MB_HDR
    ldy #7
    jsr cm_mbread               ; into ROWCHR
    lda ROWCHR
    cmp #'M'
    bne cmh_no
    lda ROWCHR+1
    cmp #'A'
    bne cmh_no
    lda ROWCHR+2
    cmp #'P'
    bne cmh_no
    ldx #3
cmh_c:
    lda ROWCHR+3,x
    sta HOW,x
    dex
    bpl cmh_c
    clc
    rts
cmh_no:
    sec
    rts

; cm_mul: TMP+2/+3 = A * X (8 x 8 bits).  Uses: A, X, TMP+2/+3.
cm_mul:
    sta TMP+2
    stx TMP+3
    lda #0
    ldx #8
    lsr TMP+2
cmu_l:
    bcc cmu_n
    clc
    adc TMP+3
cmu_n:
    ror
    ror TMP+2
    dex
    bne cmu_l
    sta TMP+3
    rts

; cm_mul16: TMP..TMP+3 = M1 * M2 (16 x 16 bits, a 32-bit product; M1
; is used up).  Uses: A, X, Y.
cm_mul16:
    lda #0
    sta TMP+2
    ldx #16
c16_l:
    lsr M1+1
    ror M1
    bcc c16_n
    tay                         ; (A: the product's top byte)
    clc
    lda TMP+2
    adc M2
    sta TMP+2
    tya
    adc M2+1
c16_n:
    ror
    ror TMP+2
    ror TMP+1
    ror TMP
    dex
    bne c16_l
    sta TMP+3
    rts

; cm_mbread: Y bytes (1-255) of the map bank at A/X (low/high) into ROWCHR
cm_mbread:
    sta fsTMP
    stx fsTMP+1
    sty fsLEN
    jsr cm_bank
    sta fsTMP+2
    lda #<ROWCHR
    ldx #>ROWCHR
    jmp cm_dmain

; ----------------------------------------------------------------------------
; cm_get: *MAP GET mx,my: M% = the character there (0 outside the map)
cm_get:
    jsr bvc.bv_arg
    lda mosNUM
    pha
    lda mosNUM+1
    pha
    jsr bvc.bv_arg
    jsr bvc.s6_end
    pla
    sta DA+1                    ; x
    pla
    sta DA
    lda mosNUM                  ; y
    sta DA+2
    lda mosNUM+1
    sta DA+3
    jsr cm_hdrget
    bcs cmg_zero
    lda DA                      ; inside the map? (x < width, y < height)
    cmp HOW
    lda DA+1
    sbc HOW+1
    bcs cmg_zero
    lda DA+2
    cmp HOH
    lda DA+3
    sbc HOH+1
    bcs cmg_zero
    jsr cm_cell                 ; MX = y * width + x
    lda MX
    ldx MX+1
    ldy #1
    jsr cm_chread
    lda ROWCHR
    jmp cmg_set
cmg_zero:
    lda #0
cmg_set:
    sta VARL_M                  ; M% (a resident integer)
    lda #0
    sta VARL_M+1
    sta VARL_M+2
    sta VARL_M+3
    rts
VARL_M      = $0400 + 4 * ('M' - '@')

; cm_cell: MX = DA+2/+3 (y) * HOW + DA/+1 (x): a cell's offset (inside
; the map: under 30720).  Uses: A, X, Y, TMP, M1, M2.
cm_cell:
    lda DA+2
    sta M1
    lda DA+3
    sta M1+1
    lda HOW
    sta M2
    lda HOW+1
    sta M2+1
    jsr cm_mul16
    lda TMP
    clc
    adc DA
    sta MX
    lda TMP+1
    adc DA+1
    sta MX+1
    rts

; cm_chread: Y bytes of the characters at offset A/X into ROWCHR
cm_chread:
    pha
    txa
    clc
    adc #>MB_CHARS
    tax
    pla
    jmp cm_mbread

; ----------------------------------------------------------------------------
; cm_draw: *MAP DRAW mx,my,w,h AT col,row: that part of the map on the
; text screen, clipped to the map and the screen, characters and colours
; by DMA straight into the screen and colour RAM. Text modes only.
; Arguments are numbers or A%-Z% (bvcmd.s), 16 bits; mx, my from 0 to
; the map's size; w, h over 255 count as 255; a part off the map or the
; screen (or a negative col, row) draws nothing.
cm_draw:
    lda #0
    sta DOFF
    ldx #0
cmdr_a:
    stx DIDX
    cpx #8
    bne cmdr_n
    lda #<wm_at                 ; AT before col, row
    ldx #>wm_at
    jsr bvc.s6_word
    bcs cmdr_n
    jmp bvc.s6_syntax
cmdr_n:
    jsr bvc.bv_arg              ; (Y: the line's position, kept)
    ldx DIDX
    lda mosNUM
    sta DA,x
    lda mosNUM+1
    sta DA+1,x
    inx
    inx
    cpx #12
    bcc cmdr_a
    jsr bvc.s6_end
    lda vtype                   ; the text screen only
    beq cmdr_text
    brk
    dta 254, '*MAP DRAW: text modes only', 0
cmdr_text:
    jsr cm_hdrget
    bcc cmdr_have
    brk
    dta 254, 'No map loaded', 0
cmdr_have:
    lda DA+9                    ; col, row: 0-39, 0-24
    ora DA+11
    bne cmdr_rts
    lda DA+5                    ; w, h over 255: 255
    beq cmdr_w255
    lda #255
    sta DA+4
cmdr_w255:
    lda DA+7
    beq cmdr_h255
    lda #255
    sta DA+6
cmdr_h255:
    lda HOW                     ; w = min(w, width - mx, 40 - col)
    sec
    sbc DA
    tax
    lda HOW+1
    sbc DA+1
    bcc cmdr_rts                ; (mx past the map)
    bne cmdr_w0                 ; (256 or more left: w stays)
    txa
    beq cmdr_rts
    cmp DA+4
    bcs cmdr_w0
    sta DA+4
cmdr_w0:
    lda #40
    sec
    sbc DA+8
    bcc cmdr_rts
    beq cmdr_rts
    cmp DA+4
    bcs cmdr_w1
    sta DA+4
cmdr_w1:
    lda HOH                     ; h = min(h, height - my, 25 - row)
    sec
    sbc DA+2
    tax
    lda HOH+1
    sbc DA+3
    bcc cmdr_rts
    bne cmdr_h0
    txa
    beq cmdr_rts
    cmp DA+6
    bcs cmdr_h0
    sta DA+6
cmdr_h0:
    lda #25
    sec
    sbc DA+10
    bcc cmdr_rts
    beq cmdr_rts
    cmp DA+6
    bcs cmdr_h1
    sta DA+6
cmdr_h1:
    lda DA+4
    beq cmdr_rts
    lda DA+6
    bne cmdr_rows
cmdr_rts:
    rts
cmdr_rows:
    jsr cm_cell                 ; MX: the map offset of the first cell
    lda DA+10                   ; the screen offset: row * 40 + col
    ldx #40
    jsr cm_mul
    lda TMP+2
    clc
    adc DA+8
    sta TMP
    lda TMP+3
    adc #0
    sta TMP+1
    jsr cm_beam                 ; (no tearing: ahead of the beam)
cmdr_row:
    lda TMP                     ; characters: map -> screen
    sta fsADDR
    lda TMP+1
    clc
    adc HIBASE
    sta fsADDR+1
    lda MX
    sta fsTMP
    lda MX+1
    clc
    adc #>MB_CHARS
    sta fsTMP+1
    jsr cm_bank
    sta fsTMP+2
    lda DA+4
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #REU_TO_C64
    jsr cm_dma
    lda TMP                     ; colours: map -> colour RAM
    sta fsADDR
    lda TMP+1
    clc
    adc #>$D800
    sta fsADDR+1
    lda MX+1
    clc
    adc #>MB_COLS
    sta fsTMP+1
    lda #REU_TO_C64
    jsr cm_dma
    lda MX                      ; next row
    clc
    adc HOW
    sta MX
    lda MX+1
    adc HOW+1
    sta MX+1
    lda TMP
    clc
    adc #40
    sta TMP
    bcc cmdr_s
    inc TMP+1
cmdr_s:
    dec DA+6
    bne cmdr_row
    rts

; cm_beam: wait until the copy can stay ahead of the beam (2026-10-16:
; scrolling tore): the VIC-II's raster in the bottom border, the vertical
; blank or the top border's first lines (0-31, 251-311) is fine, as the
; rows go top first at about 6 lines each and the beam needs 8 a row from
; line 51; in between, wait for line 251. The copy then never shows half
; old, half new, and programs need no *FX 19.  Uses: A.
cm_beam:
    lda $D011                   ; line 256 or more: go
    bmi cbm_rts
    lda $D012
    cmp #32
    bcc cbm_rts
    cmp #251
    bcc cm_beam
cbm_rts:
    rts

; ----------------------------------------------------------------------------
; cm_load
;   Summary: *MAP LOAD file: a CharPad CTM file (versions 6-9): its
;            character set as the font, its map (tiles expanded) with each
;            cell's colour into the map bank, its screen colour to $D021.
;   Function: the file into the scratch bank (ct_file), its header and
;            blocks read in order (ct_parse), the font (ct_font), the
;            colour of each character (ct_colours), the map (ct_map).
;   Input:   mosPTR/Y.  Output: the map bank, the font.  Uses: everything
;            of cmd_map.
cm_load:
    jsr bvc.s6_name             ; fsPTR/fsLEN, Y past it
    jsr bvc.s6_end
    farcall rd_spoolok, BANK_RD ; the RAM disk must end below the map bank
    bcc cml_room
    brk
    dta 254, 'RAM disk uses the last 128K', 0
cml_room:
    jsr ct_file
    jsr ct_parse
    jsr cm_blank                ; (the old screen in the new font: hidden)
    jsr ct_font
    lda #REU_TO_REU             ; page &0700 aside (BASIC still reads the
    jsr cm_save7                ; command's line there afterwards)
    jsr ct_colours
    jsr ct_map
    lda #REU_TO_C64
    jsr cm_save7
    lda BG                      ; the screen colour
    sta $D021
    jmp cm_unblank

; cm_blank / cm_unblank: the text screen off / on (VIC-II $D011 bit 4)
; while *MAP LOAD changes the font (2026-10-16: the screen's spaces showed
; as the new set's character 32 during the load); not in the bitmap
; modes.  Uses: A.
cm_blank:
    lda vtype
    bne cmbl_rts
    php
    sei                         ; (the sprite multiplexer writes $D011)
    lda $D011
    and #$EF
    sta $D011
    plp
cmbl_rts:
    rts
cm_unblank:
    lda vtype
    bne cmbl_rts
    php
    sei
    lda $D011
    ora #$10
    sta $D011
    plp
    rts

; cm_save7: page &0700 to (A = REU_TO_REU) or from (REU_TO_C64) MB_SAVE
cm_save7:
    pha
    lda #<MB_SAVE
    sta fsTMP
    lda #>MB_SAVE
    sta fsTMP+1
    jsr cm_bank
    sta fsTMP+2
    lda #0
    sta fsLEN
    lda #1
    sta fsLEN+1
    lda #<COLTAB
    sta fsADDR
    lda #>COLTAB
    sta fsADDR+1
    pla
    jmp cm_dma

; ct_fontfile (*FONT LOAD, font.s): fsPTR/fsLEN = the name: a CTM file's
; character set as the font, C = 0; C = 1 if it is no CTM file (or there
; is no REU: then the other formats only)
ct_fontfile:
    jsr bvc.s6_hasreu
    beq ctff_no
    jsr ct_load
    bcs ctff_rts
    jsr ct_parse
    jsr ct_font
    clc
ctff_rts:
    rts
ctff_no:
    sec
    rts

; ct_file: ct_load, "Not a CharPad file" unless it is one
ct_file:
    jsr ct_load
    bcs ctf_bad
    rts
ctf_bad:
    brk
    dta 254, 'Not a CharPad file (CTM 6-9)', 0

; ct_load: the file at fsPTR/fsLEN whole into the scratch bank (at most
; 64K), its header into ROWCHR, VER; C = 1 unless it starts "CTM" with
; version 6-9
ct_load:
    farcall fs_reuopen0, BANK_FS
    lda #0
    sta fsTMP
    sta fsTMP+1
    lda #SCR_BANK
    sta fsTMP+2
    lda #$FF
    sta fsCNT
    sta fsCNT+1
    farcall fs_reurest, BANK_FS
    lda #0
    sta RP
    sta RP+1
    ldy #20                     ; the header (at most 20 bytes)
    jsr ct_take
    lda ROWCHR
    cmp #'C'
    bne ctl_no
    lda ROWCHR+1
    cmp #'T'
    bne ctl_no
    lda ROWCHR+2
    cmp #'M'
    bne ctl_no
    lda ROWCHR+3
    cmp #82                     ; (82: an early number for version 8)
    bne ctf_v
    lda #8
ctf_v:
    sta VER
    cmp #6
    bcc ctl_no
    cmp #10                     ; (C = 1 from 10)
    rts
ctl_no:
    sec
    rts

; ct_take: Y bytes (1-255) of the file at RP into ROWCHR, RP on
ct_take:
    sty fsLEN
    lda RP
    sta fsTMP
    lda RP+1
    sta fsTMP+1
    lda #SCR_BANK
    sta fsTMP+2
    tya
    clc
    adc RP
    sta RP
    bcc ctt_n
    inc RP+1
ctt_n:
    lda #<ROWCHR
    ldx #>ROWCHR
; cm_dmain: fsLEN (low byte; high 0) bytes from the REU at fsTMP/+1/+2
; to A/X
cm_dmain:
    sta fsADDR
    stx fsADDR+1
    lda #0
    sta fsLEN+1
    lda #REU_TO_C64
; cm_dma: the transfer fsADDR <-> fsTMP/+1/+2, fsLEN; command A
; (interrupts off while the REU is set up: the sound interrupt uses it)
cm_dma:
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

; ct_at: A = the file's byte at A/X (low/high).  Uses: A, X, fs*.
ct_at:
    sta fsTMP
    stx fsTMP+1
    lda #SCR_BANK
    sta fsTMP+2
    lda #1
    sta fsLEN
    lda #<SC_BYTE
    ldx #>SC_BYTE
    jsr cm_dmain
    lda SC_BYTE
    rts

; ct_at16: A/X = the 16-bit value at A/X in the file (one transfer of 2)
ct_at16:
    sta fsTMP
    stx fsTMP+1
    lda #SCR_BANK
    sta fsTMP+2
    lda #2
    sta fsLEN
    lda #<CT_P
    ldx #>CT_P
    jsr cm_dmain
    lda CT_P
    ldx CT_P+1
    rts

; ct_byte / ct_word: the next byte (A) / 16-bit word (A/X) at RP
ct_byte:
    lda RP
    ldx RP+1
    jsr ct_at
    inc RP
    bne ctb_r
    inc RP+1
ctb_r:
    rts
ct_word:
    lda RP
    ldx RP+1
    jsr ct_at16
    pha
    lda RP
    clc
    adc #2
    sta RP
    bcc ctw_r
    inc RP+1
ctw_r:
    pla
    rts
; ct_skip: RP += A/X
ct_skip:
    clc
    adc RP
    sta RP
    txa
    adc RP+1
    sta RP+1
    rts
; ct_mark: RP past a block marker (2 bytes)
ct_mark:
    lda #2
    ldx #0
    beq ct_skip
; ct_skipn: RP += TMP+2/+3 * Y (a count times an entry size, Y 1-255)
ct_skipn:
    lda TMP+2
    ldx TMP+3
    jsr ct_skip
    dey
    bne ct_skipn
    rts

; ----------------------------------------------------------------------------
; ct_parse
;   Summary: the header and the blocks in their order (the help's
;            "written order"): characters, attributes / materials, the
;            per-character colours (V8/V9), tiles, their colours, tags,
;            names, the map; the positions and sizes into the variables.
;   Input:   ROWCHR = the header (ct_file), VER.
ct_parse:
    ldx VER
    lda ctp_hlen-6,x            ; past the header
    sta RP
    lda #0
    sta RP+1
    sta CSTR                    ; (no per-character / per-tile colours)
    sta TSTR
    lda ctp_bg-6,x              ; the screen colour
    tay
    lda ROWCHR,y
    and #15
    sta BG
    lda ctp_chr-6,x             ; the project's character colour
    tay
    lda ROWCHR,y
    and #15
    sta COLR
    lda ctp_meth-6,x
    tay
    lda ROWCHR,y
    sta METH
    lda ctp_flg-6,x
    tay
    lda ROWCHR,y
    and ctp_tsm-6,x
    sta TILES
    lda #1                      ; colour entry size, CharPad 3 (V8/V9):
    sta BPX                     ; text 1, bitmap HR 2, bitmap MC 3
    cpx #8
    bcc ctp_chars
    lda ROWCHR+4                ; (DISP_MODE)
    cmp #3
    bcc ctp_chars
    sbc #1
    sta BPX
ctp_chars:
    jsr ct_mark                 ; block: characters
    jsr ct_word                 ; count - 1
    clc
    adc #1
    sta TMP+2                   ; the count
    sta NCH                     ; (0: 256 or more)
    txa
    adc #0
    sta TMP+3
    beq ctp_n
    lda #0
    sta NCH
ctp_n:
    lda RP
    sta CHARPOS
    lda RP+1
    sta CHARPOS+1
    ldy #8                      ; the images: count * 8
    jsr ct_skipn
    jsr ct_mark                 ; block: attributes (V6/V7: the colour in
    lda VER                     ; the low nybble) / materials (V8/V9)
    cmp #8
    bcs ctp_mat
    lda METH
    cmp #2
    bne ctp_mat
    lda RP
    sta CSRC
    lda RP+1
    sta CSRC+1
    lda #1
    sta CSTR
ctp_mat:
    ldy #1
    jsr ct_skipn
    lda VER                     ; V8/V9, per character: its own block
    cmp #8
    bcc ctp_tiles
    lda METH
    cmp #2
    bne ctp_tiles
    jsr ct_mark
    lda RP
    sta CSRC
    lda RP+1
    sta CSRC+1
    lda BPX
    sta CSTR
    tay
    jsr ct_skipn
ctp_tiles:
    lda #1
    sta TW
    sta TH
    lda TILES
    bne ctp_tl
    jmp ctp_map
ctp_tl:
    jsr ct_mark                 ; block: tiles
    jsr ct_word                 ; count - 1 -> TMP+2/+3 = the count
    clc
    adc #1
    sta TMP+2
    txa
    adc #0
    sta TMP+3
    jsr ct_byte
    sta TW
    jsr ct_byte
    sta TH
    lda RP
    sta TILEPOS
    lda RP+1
    sta TILEPOS+1
    lda TW                      ; count * w * h * 2
    ldx TH
    jsr cm_mul                  ; (over the count: read again)
    lda TMP+3                   ; at most 127 cells a tile (the cell
    bne ctp_tbig                ; offsets stay 8-bit)
    lda TMP+2
    beq ctp_tbig
    asl
    bcs ctp_tbig
    tay
    jsr ctp_count
    jsr ct_skipn
    lda METH                    ; per tile: their colours
    cmp #1
    bne ctp_tags
    jsr ct_mark
    lda RP
    sta TCOLPOS
    lda RP+1
    sta TCOLPOS+1
    lda #1
    ldx VER
    cpx #8
    bcc ctp_ts1
    lda BPX
ctp_ts1:
    sta TSTR
    tay
    jsr ct_skipn
ctp_tags:
    jsr ct_mark                 ; tags: one byte each
    ldy #1
    jsr ct_skipn
    jsr ct_mark                 ; names: count strings, each 0-ended
ctp_name:
    lda TMP+2
    ora TMP+3
    beq ctp_map
ctp_nb:
    jsr ct_byte
    cmp #0
    bne ctp_nb
    lda TMP+2
    bne ctp_nd
    dec TMP+3
ctp_nd:
    dec TMP+2
    jmp ctp_name
ctp_map:
    jsr ct_mark                 ; block: the map
    jsr ct_word
    sta MW
    stx MW+1
    jsr ct_word
    sta MH
    stx MH+1
    lda RP
    sta MAPPOS
    lda RP+1
    sta MAPPOS+1
    rts
ctp_tbig:
    brk
    dta 254, 'Tiles too big (127 characters)', 0
; ctp_count: TMP+2/+3 = the tile count (from the tile block's start:
; TILEPOS - 4 holds count - 1)
ctp_count:
    tya
    pha
    lda TILEPOS
    sec
    sbc #4
    pha
    lda TILEPOS+1
    sbc #0
    tax
    pla
    jsr ct_at16
    clc
    adc #1
    sta TMP+2
    txa
    adc #0
    sta TMP+3
    pla
    tay
    rts

; per version 6-9: header length, offsets of the screen colour, the
; character colour, the colour method, the flags; the flags' tiles bit
ctp_hlen    dta 10, 12, 14, 19
ctp_bg      dta 4, 4, 7, 12
ctp_chr     dta 7, 8, 11, 16
ctp_meth    dta 8, 9, 5, 5
ctp_flg     dta 9, 11, 6, 6
ctp_tsm     dta 2, 1, 1, 1

; ----------------------------------------------------------------------------
; ct_font: the first 256 characters (or all there are) as the font: each
; image through glyph into bank 2's fo_put (fo_ctmglyph), then the
; ASCII-order font rebuilt (fo_mkascii)
ct_font:
    lda #0
    sta TMP                     ; the character
ctfo_l:
    lda TMP
    ldx NCH
    beq ctfo_go                 ; (256 or more)
    cmp NCH
    bcs ctfo_done
ctfo_go:
    lda #0                      ; CHARPOS + c * 8 -> glyph
    sta TMP+1
    lda TMP
    asl
    rol TMP+1
    asl
    rol TMP+1
    asl
    rol TMP+1
    clc
    adc CHARPOS
    sta fsTMP
    lda TMP+1
    adc CHARPOS+1
    sta fsTMP+1
    lda #SCR_BANK
    sta fsTMP+2
    lda #8
    sta fsLEN
    lda #<glyph
    ldx #>glyph
    jsr cm_dmain
    lda TMP
    farcall put_scr, BANK_FS
    inc TMP
    bne ctfo_l
ctfo_done:
    farcall fo_mkascii, BANK_FS
    rts

; ----------------------------------------------------------------------------
; ct_colours: the colour of each character into COLTAB and the map bank:
; per character from its block (V8/V9) or attributes (V6/V7), else (and
; beyond the characters there are) the project's colour
ct_colours:
    ldx #0
ctc_l:
    stx TMP
    lda COLR
    ldy CSTR
    beq ctc_put                 ; (none per character)
    ldy NCH
    beq ctc_rd                  ; (256 or more)
    cpx NCH
    bcs ctc_put
ctc_rd:
    txa                         ; CSRC + c * stride
    ldx CSTR
    jsr cm_mul
    lda TMP+2
    clc
    adc CSRC
    pha
    lda TMP+3
    adc CSRC+1
    tax
    pla
    jsr ct_at
ctc_put:
    and #15
    ldx TMP
    sta COLTAB,x
    inx
    bne ctc_l
    lda #<MB_CCOL               ; COLTAB -> the map bank (256)
    sta fsTMP
    lda #>MB_CCOL
    sta fsTMP+1
    jsr cm_bank
    sta fsTMP+2
    lda #0
    sta fsLEN
    lda #1
    sta fsLEN+1
    lda #<COLTAB
    sta fsADDR
    lda #>COLTAB
    sta fsADDR+1
    lda #REU_TO_REU
    jmp cm_dma

; ----------------------------------------------------------------------------
; ct_map
;   Summary: the map, tiles expanded, into the map bank: the characters
;            (each cell's low byte) and their colours (per tile: the
;            tile's; else COLTAB's), as one run of cells (rows follow each
;            other without gaps) through 128-cell buffers; the header last.
;   Function: OW = MW * TW, OH = MH * TH, each 1-65535, OW * OH at most
;            MB_MAX ("Map too big"). ESCAPE stops.
ct_map:
    lda MW                      ; the size in characters
    sta M1
    lda MW+1
    sta M1+1
    lda TW
    sta M2
    lda #0
    sta M2+1
    jsr cm_mul16
    lda TMP+2
    bne ctm_big
    lda TMP
    sta OW
    lda TMP+1
    sta OW+1
    ora OW
    beq ctm_big
    lda MH
    sta M1
    lda MH+1
    sta M1+1
    lda TH
    sta M2
    jsr cm_mul16
    lda TMP+2
    bne ctm_big
    lda TMP
    sta OH
    sta M1
    lda TMP+1
    sta OH+1
    sta M1+1
    ora OH
    beq ctm_big
    lda OW                      ; cells: at most MB_MAX
    sta M2
    lda OW+1
    sta M2+1
    jsr cm_mul16
    lda TMP+2
    ora TMP+3
    bne ctm_big
    lda TMP
    cmp #<[MB_MAX+1]
    lda TMP+1
    sbc #>[MB_MAX+1]
    bcc ctm_ok
ctm_big:
    lda #REU_TO_C64             ; (page &0700 back, the screen on first)
    jsr cm_save7
    jsr cm_unblank
    brk
    dta 254, 'Map too big (30720 characters)', 0
ctm_ok:
    lda TW                      ; cells per tile
    ldx TH
    jsr cm_mul
    lda TMP+2
    sta CT_TS
    lda MAPPOS                  ; the first map row
    sta RB
    lda MAPPOS+1
    sta RB+1
    lda #0
    sta CY
    sta YY
    sta YY+1
    sta OP
    sta OP+1
    sta NB
ctm_row:
    lda CY                      ; the offset of the tile row: cy * TW
    ldx TW
    jsr cm_mul
    lda TMP+2
    sta CYT
    lda RB
    sta CP
    lda RB+1
    sta CP+1
    lda #0
    sta XX
    sta XX+1
    sta CX
ctm_cell:
    lda TILES
    bne ctm_t
    lda CP                      ; no tiles: the cell's low byte
    ldx CP+1
    jsr ct_at
    sta CH
    jsr ctm_cp2
    ldy CH
    ldx COLTAB,y
    jmp ctm_put
ctm_t:
    lda CX                      ; a new tile: its row's address
    bne ctm_tr
    jsr ctm_tile
ctm_tr:
    lda TA                      ; the character: the tile cell's low byte
    ldx TA+1
    jsr ct_at
    sta CH
    lda TA
    clc
    adc #2
    sta TA
    bcc ctm_ta
    inc TA+1
ctm_ta:
    inc CX
    lda CX
    cmp TW
    bcc ctm_cx
    lda #0
    sta CX
ctm_cx:
    ldx TCOL                    ; per tile: the tile's colour
    lda TSTR
    bne ctm_put
    ldy CH                      ; else the character's
    ldx COLTAB,y
ctm_put:
    lda CH
    ldy NB
    sta ROWCHR,y
    txa
    sta ROWCOL,y
    iny
    sty NB
    cpy #BUFN
    bcc ctm_nx
    jsr ctm_flush
ctm_nx:
    inc XX
    bne ctm_x
    inc XX+1
ctm_x:
    lda XX
    cmp OW
    lda XX+1
    sbc OW+1
    bcs ctm_rowend
    jmp ctm_cell
ctm_rowend:
    bit ESCFLG
    bpl ctm_noesc
    jmp ctm_esc
ctm_noesc:
    inc CY                      ; the next row of the tiles, or of the map
    lda CY
    cmp TH
    bcc ctm_ny
    lda #0
    sta CY
    lda MW                      ; RB += MW * 2
    asl
    tax
    lda MW+1
    rol
    tay
    txa
    clc
    adc RB
    sta RB
    tya
    adc RB+1
    sta RB+1
ctm_ny:
    inc YY
    bne ctm_y
    inc YY+1
ctm_y:
    lda YY
    cmp OH
    lda YY+1
    sbc OH+1
    bcs ctm_hdr
    jmp ctm_row
ctm_hdr:
    jsr ctm_flush               ; the rest
    lda #'M'                    ; the header last (a broken load: none)
    sta ROWCHR
    lda #'A'
    sta ROWCHR+1
    lda #'P'
    sta ROWCHR+2
    lda OW
    sta ROWCHR+3
    lda OW+1
    sta ROWCHR+4
    lda OH
    sta ROWCHR+5
    lda OH+1
    sta ROWCHR+6
    lda #<MB_HDR
    sta fsTMP
    lda #>MB_HDR
    sta fsTMP+1
    jsr cm_bank
    sta fsTMP+2
    lda #7
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda #<ROWCHR
    sta fsADDR
    lda #>ROWCHR
    sta fsADDR+1
    lda #REU_TO_REU
    jmp cm_dma

; ctm_flush: the NB cells in the buffers to the map bank at OP (both
; planes); OP += NB, NB = 0.  Uses: A, X, fs*.
ctm_flush:
    lda NB
    beq ctf_rts
    sta fsLEN
    lda #0
    sta fsLEN+1
    lda OP
    sta fsTMP
    lda OP+1
    clc
    adc #>MB_CHARS
    sta fsTMP+1
    jsr cm_bank
    sta fsTMP+2
    lda #<ROWCHR
    sta fsADDR
    lda #>ROWCHR
    sta fsADDR+1
    lda #REU_TO_REU
    jsr cm_dma
    lda OP+1
    clc
    adc #>MB_COLS
    sta fsTMP+1
    lda #<ROWCOL
    sta fsADDR
    lda #>ROWCOL
    sta fsADDR+1
    lda #REU_TO_REU
    jsr cm_dma
    lda OP
    clc
    adc NB
    sta OP
    bcc ctf_z
    inc OP+1
ctf_z:
    lda #0
    sta NB
ctf_rts:
    rts
ctm_esc:
    lda #REU_TO_C64
    jsr cm_save7
    jsr cm_unblank
    lda #$7E
    jsr OSBYTE
    brk
    dta 17, 'Escape', 0

; ctm_cp2: CP += 2 (the next map cell)
ctm_cp2:
    lda CP
    clc
    adc #2
    sta CP
    bcc ccp_r
    inc CP+1
ccp_r:
    rts

; ctm_tile: the map cell at CP is a tile (CP += 2): TA = the address of
; its row cy (TILEPOS + (tile * TS + cy * TW) * 2), TCOL = its colour
; (per tile).  Uses: A, X, TMP, CT_T.
ctm_tile:
    lda CP
    ldx CP+1
    jsr ct_at16
    sta CT_T
    stx CT_T+1
    jsr ctm_cp2
    lda CT_T+1                  ; tile * TS (16 bits)
    ldx CT_TS
    jsr cm_mul
    lda TMP+2
    sta TA+1
    lda CT_T
    ldx CT_TS
    jsr cm_mul
    lda TMP+2
    clc
    adc CYT
    sta TA
    lda TMP+3
    adc TA+1
    sta TA+1
    asl TA                      ; * 2 + TILEPOS
    rol TA+1
    lda TA
    clc
    adc TILEPOS
    sta TA
    lda TA+1
    adc TILEPOS+1
    sta TA+1
    lda TSTR
    beq ctt_rts
    lda CT_T+1                  ; TCOLPOS + tile * TSTR (TSTR 1-3)
    ldx TSTR
    jsr cm_mul
    lda TMP+2
    sta TCOL
    lda CT_T
    ldx TSTR
    jsr cm_mul
    lda TMP+2
    clc
    adc TCOLPOS
    pha
    lda TMP+3
    adc TCOLPOS+1
    clc
    adc TCOL
    tax
    pla
    jsr ct_at
    and #15
    sta TCOL
ctt_rts:
    rts

    .endl
