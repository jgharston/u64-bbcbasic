10 REM PETSCII: the PETSCII mode of U64 BBC BASIC (*PETSCII, *SEQ)
20 REM In PETSCII mode bytes go to the screen as on a C64: colour codes,
30 REM reverse, cursor and case codes act, the C64's own characters show,
40 REM and GET gives PETSCII codes. *ASCII (or MODE, or an error) ends it.
50 REM The logo: IDI8B.seq, the IDreamtIn8Bits logo by Xander Mol.
60 MODE 100
70 *PETSCII
80 PRINT CHR$147;CHR$5;"PETSCII MODE ON U64 BBC BASIC"
90 PRINT
100 PROCcolours
110 PROCbox(4,6,32,5)
120 PROCsuits
130 PROCpad
140 *SEQ IDI8B.SEQ LOWER
150 *ASCII
160 PRINT "Back in ASCII mode."
170 END
180 :
190 REM The 16 colours: each code, then a reverse space in it
200 DEF PROCcolours
210   LOCAL I%,C%
220   RESTORE 290
230   FOR I%=1 TO 16
240     READ C%
250     PRINT CHR$C%;CHR$18;"  ";CHR$146;
260   NEXT
270   PRINT CHR$5
280 ENDPROC
290 DATA 144,5,28,159,156,30,31,158,129,149,150,151,152,153,154,155
300 :
310 REM A box of PETSCII lines at column X%, row Y%, W% wide, H% high
320 DEF PROCbox(X%,Y%,W%,H%)
330   LOCAL I%
340   PROCat(X%,Y%):PRINT CHR$158;CHR$176;STRING$(W%-2,CHR$192);CHR$174;
350   FOR I%=1 TO H%-2
360     PROCat(X%,Y%+I%):PRINT CHR$221;SPC(W%-2);CHR$221;
370   NEXT
380   PROCat(X%,Y%+H%-1):PRINT CHR$173;STRING$(W%-2,CHR$192);CHR$189;
390   PROCat(X%+3,Y%+2):PRINT CHR$5;"DRAWN WITH PETSCII LINES";
400 ENDPROC
410 :
420 REM The cursor to column X%, row Y%: HOME, then down and right
430 DEF PROCat(X%,Y%)
440   PRINT CHR$19;STRING$(Y%,CHR$17);STRING$(X%,CHR$29);
450 ENDPROC
460 :
470 DEF PROCsuits
480   PROCat(4,12)
490   PRINT CHR$28;CHR$211;" ";CHR$218;" ";CHR$5;CHR$193;" ";CHR$216;
500   PRINT "  THE CARD SUITS"
510 ENDPROC
520 :
530 REM Type to draw: GET gives PETSCII, so the C= and SHIFT graphics
540 REM keys, the colour keys (CTRL/C= with 1-8) and the cursor keys work
550 REM as on a C64; F1 ends
560 DEF PROCpad
570   LOCAL K%
580   PROCat(0,15)
590   PRINT CHR$5;"TYPE TO DRAW: C= AND SHIFT GRAPHICS,"
600   PRINT "CTRL OR C= WITH 1-8 COLOURS. F1: LOGO."
610   PRINT
620   REPEAT
630     K%=GET
640     IF K%<>133 THEN PRINT CHR$K%;
650   UNTIL K%=133
660 ENDPROC
