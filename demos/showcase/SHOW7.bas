10 REM SHOW7: a plasma: each cell's colour from four SIN waves (the
20 REM *TABLE), then moved by cycling the palette
30 MODE 2
40 *OFF
45 *FX 15,1
47 ON ERROR OSCLI "SONG STOP":OSCLI "MODSTOP":VDU 4:IF ERR=17 END ELSE REPORT:PRINT " at line ";ERL:END
50 DIM S% 1023
60 *TABLE SIN S% 256
70 PROCdraw
80 PROCcycle(3000)
90 CHAIN "SHOW8"
100 END
110 :
200 REM Four waves: across, down, diagonal, and rings from the centre
205 REM (SQR); the sum (-4..4 x 65536) picks colour 1-15
210 DEF PROCdraw
220   LOCAL X%,Y%,C%,D%
230   FOR Y%=0 TO 31
240     FOR X%=0 TO 39
250       D%=SQR((X%-20)^2+(Y%-16)^2)*16
260       C%=S%!(4*(X%*6 AND 255))+S%!(4*(Y%*9 AND 255))
270       C%=C%+S%!(4*((X%+Y%)*4 AND 255))+S%!(4*(D% AND 255))
280       GCOL 0,1+(C%+262144)*14 DIV 524288
290       A%=X%*32:B%=Y%*32:*RECTANGLE FILL A%,B%,31,31
300     NEXT
310     IF INKEY(0)<>-1 THEN Y%=31
315   NEXT
316 ENDPROC
320 :
400 DEF PROCcycle(T%)
410   LOCAL E%,P%,L%,H%
420   E%=TIME+T%:P%=0
430   REPEAT
440     FOR L%=1 TO 15
450       H%=(L%*17+P%) MOD 255
460       VDU 19,L%,16,FNr(H%),FNr(H%+85),FNr(H%+170)
470     NEXT
480     P%=P%+5
490     H%=TIME+2:REPEAT UNTIL TIME>H%
500   UNTIL TIME>E% OR INKEY(0)<>-1
510 ENDPROC
520 :
600 DEF FNr(H%)
610   H%=H% MOD 255
620   IF H%<85 =H%*3
630   IF H%<170 =(170-H%)*3
640 =0
