10 REM Bubble Universe: Eric Schraf (QB64), Archimedes BASIC V by
20 REM Xander Mol (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here.
30 REM 256 Archimedes colours (GCOL c TINT t) to a 16-colour palette:
40 REM T%(c*4+t) is the nearest entry, worked out once.
50 MODE M%
60 *OFF
70 PROCsetup
80 PROCdraw
90 K%=GET
100 CHAIN "SCHRAF"
110 END
120 DEF PROCsetup
130   LOCAL L%,R%,G%,B%,C%,D%,E%
140   DIM T%(255),P%(47)
150   FOR L%=0 TO 15
160     READ R%,G%,B%
170     *COLOUR L%,R%,G%,B%
180     P%(L%*3)=R%:P%(L%*3+1)=G%:P%(L%*3+2)=B%
190   NEXT
200   FOR C%=0 TO 255
210     E%=C% MOD 4:D%=C% DIV 4
220     R%=((D% AND 3)*4+E%)*17
230     G%=((D% DIV 4 AND 3)*4+E%)*17
240     B%=((D% DIV 16 AND 3)*4+E%)*17
250     T%(C%)=FNnearest(R%,G%,B%)
260   NEXT
270 ENDPROC
280 DEF FNnearest(R%,G%,B%)
290   LOCAL L%,N%,D%,E%
300   E%=999
310   FOR L%=0 TO 15
320     D%=ABS(P%(L%*3)-R%)+ABS(P%(L%*3+1)-G%)+ABS(P%(L%*3+2)-B%)
330     IF D%<E% THEN E%=D%:N%=L%
340   NEXT
350 =N%
360 DEF PROCdraw
370   LOCAL I%,J%,W%,P%
380   REM the Archimedes' 1280 units fill the width: 1536 in MODE 110
390   IF M%=110 THEN W%=1536 ELSE W%=1280
400   pi=4*TAN(1):r=2*pi/235:t=RND(4):x=0:u=0:v=0
410   P%=TIME+500
420   FOR I%=0 TO 249
430     FOR J%=0 TO 249
440       u=SIN(I%+v)+SIN(r*I%+x)
450       v=COS(I%+v)+COS(r*I%+x)
460       x=u+t
470       X%=W%/2+W%/5*u:Y%=512+256*v
480       GCOL 0,T%((I%*3) MOD 64*4+(J%*3) MOD 4)
490       *POINT X%,Y%
500     NEXT
510     IF M%=110 AND TIME>P% THEN P%=TIME+500:OSCLI "UPIC SHOW 50"
520   NEXT
530 ENDPROC
540 DATA 0,0,0, 255,0,0, 0,255,0, 255,255,0, 0,0,255, 255,0,255
550 DATA 0,255,255, 255,255,255, 255,128,0, 128,0,255, 0,128,255
560 DATA 255,0,128, 128,255,0, 0,255,128, 128,128,128, 64,64,64
