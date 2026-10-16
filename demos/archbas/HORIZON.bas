10 REM Event Horizon: Eric Schraf (QB64), Archimedes BASIC V by
20 REM Xander Mol (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here.
30 REM 16 shades of grey, exact; worked out per screen pixel (160 or
40 REM 384 across, 256 down) rather than per Archimedes pixel.
50 MODE M%
60 *OFF
70 IF M%=110 THEN W%=1536:N%=384 ELSE W%=1280:N%=160
80 PROCpalette
85 PROCtitle
90 PROCdraw
100 PROCend
110 CHAIN "SCHRAF"
120 END
130 DEF PROCpalette
140   LOCAL L%,G%
150   FOR L%=0 TO 15
160     G%=L%*16
170     *COLOUR L%,G%,G%,G%
180   NEXT
190 ENDPROC
200 DEF PROCdraw
210   LOCAL I%,J%,T%
220   T%=TIME+500
230   FOR I%=0 TO N%-1
240     FOR J%=0 TO 255
250       x=I%/N%:y=J%/256
260       IF x<>y THEN PROCpoint
270     NEXT
275     PROCprogress(I%+1,N%)
280     IF M%=110 AND TIME>T% THEN T%=TIME+500:OSCLI "UPIC SHOW 50"
290   NEXT
300 ENDPROC
310 DEF PROCpoint
320   GCOL 0,FNgrey DIV 16
330   X%=I%*W%/N%:Y%=J%*4
340   *POINT X%,Y%
350 ENDPROC
360 DEF FNgrey
370   LOCAL a,g
380   a=SQR((4*x-2)^2+(4*y-2)^2)-1
390   IF a=0 THEN =255
400   g=INT(30/ABS(a+.005/(x-y)))
410   IF g>255 THEN g=255
420   IF g<0 THEN g=0
430 =g
440 DEF PROCtitle
441   REM Full mode: the text screen shows while the picture is drawn
442   IF M%<>110 THEN ENDPROC
443   COLOUR 15:PRINT TAB(4,9);"Event Horizon";
444   PRINT TAB(4,10);"a look at the picture every 5 s";
445 ENDPROC
446 DEF PROCprogress(F%,G%)
447   REM Full mode: a bar growing to 32 cells as F% of G% is done, in
448   REM colour 15: bright in this demo's palette (the text screen's too)
449   LOCAL B%
450   IF M%<>110 THEN ENDPROC
451   B%=F%*32 DIV G%
452   PRINT TAB(4,12);:COLOUR 143:PRINT SPC(B%);
453   COLOUR 128:COLOUR 15:PRINT TAB(4,14);F%*100 DIV G%;"% drawn  ";
454 ENDPROC
455 DEF PROCend
456   REM Full mode: the finished picture until a key (GET shows it only
457   REM when it changed since the last look); the key is not kept
458   IF M%=110 THEN OSCLI "UPIC SHOW":OSCLI "FX 15,1" ELSE K%=GET
459 ENDPROC
