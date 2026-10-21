10 REM SHOW: U64 BBC BASIC showcase, part 0: title, the music starts
20 REM A timed show in parts (CHAIN): the music plays on in the
30 REM background. Any key skips a part. Run from its folder:
40 REM *CD demos/showcase, then CHAIN "SHOW".
50 ON ERROR PROCerror:END
60 MODE 100
70 *OFF
75 *FX 15,1
80 *SONG STOP
90 *MODSTOP
100 *SONG LOAD SHOW.SNG
110 *SONG PLAY
120 *PETSCII
125 PRINT CHR$14;
130 PROCseq("../petscii/IDI8B.seq")
140 K%=FNwait(500)
150 *ASCII
160 CLS
170 PROCcentre(10,"U64 BBC BASIC")
180 PROCcentre(12,"BBC BASIC 3.10 on the Ultimate 64")
190 PROCcentre(14,"with a BBC-style MOS in 6502")
200 K%=FNwait(400)
210 CHAIN "SHOW1"
220 END
230 :
300 REM A PETSCII file printed as it is (*PETSCII: bytes as on a C64)
310 DEF PROCseq(F$)
320   LOCAL F%
330   F%=OPENIN F$
340   IF F%=0 ENDPROC
350   REPEAT
360     VDU BGET#F%
370   UNTIL EOF#F%
380   CLOSE#F%
390 ENDPROC
400 :
500 DEF PROCcentre(Y%,A$)
510   PRINT TAB((40-LEN A$) DIV 2,Y%);A$;
520 ENDPROC
530 :
600 REM Waits T% cs; TRUE if a key ended it (the key is taken)
610 DEF FNwait(T%)
620   LOCAL E%,K%
630   E%=TIME+T%
640   REPEAT
650     K%=INKEY(0)
660   UNTIL K%<>-1 OR TIME>E%
670 =K%<>-1
680 :
700 REM RUN/STOP or an error: the music stops, ASCII again
710 DEF PROCerror
720   *SONG STOP
730   *MODSTOP
740   *ASCII
750   *ON
760   IF ERR<>17 THEN REPORT:PRINT " (line ";ERL;")"
770 ENDPROC
