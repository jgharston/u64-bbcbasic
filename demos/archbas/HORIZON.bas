10 REM Event Horizon: Eric Schraf (QB64), Archimedes BASIC V by
20 REM Xander Mol (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here.
30 REM 16 shades of grey, exact; worked out per screen pixel (160 or
40 REM 384 across, 256 down) rather than per Archimedes pixel.
50 MODE M%
60 *OFF
70 IF M%=110 THEN W%=1536:N%=384 ELSE W%=1280:N%=160
80 PROCpalette
90 PROCdraw
100 K%=GET
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
