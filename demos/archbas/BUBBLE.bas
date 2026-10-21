10 REM Bubble Universe: Eric Schraf (QB64), Archimedes BASIC V by
20 REM Xander Mol (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here.
30 REM Few comments: MODE 2 leaves 4K, REM lines take room (see
40 REM docs/manual 08_GRAPHICS for Upic Lite and *TABLE).
50 MODE M%
55 ON ERROR IF ERR=17 THEN CHAIN "SCHRAF" ELSE VDU 4:REPORT:PRINT " at line ";ERL:END
60 *OFF
65 PROCtable
70 PROCsetup
75 PROCtitle
80 PROCdraw
90 PROCend
100 CHAIN "SCHRAF"
110 END
120 DEF PROCsetup
130   LOCAL L%,R%,G%,B%,C%,D%,E%
140   DIM O% 255,U% 47
150   FOR L%=0 TO 15
160     READ R%,G%,B%
170     *COLOUR L%,R%,G%,B%
180     U%?(L%*3)=R%:U%?(L%*3+1)=G%:U%?(L%*3+2)=B%
190   NEXT
200   FOR C%=0 TO 255
210     E%=C% MOD 4:D%=C% DIV 4
220     R%=((D% AND 3)*4+E%)*17
230     G%=((D% DIV 4 AND 3)*4+E%)*17
240     B%=((D% DIV 16 AND 3)*4+E%)*17
250     O%?C%=FNnearest(R%,G%,B%)
260   NEXT
270 ENDPROC
280 DEF FNnearest(R%,G%,B%)
290   LOCAL L%,N%,D%,E%
300   E%=999
310   FOR L%=0 TO 15
320     D%=ABS(U%?(L%*3)-R%)+ABS(U%?(L%*3+1)-G%)+ABS(U%?(L%*3+2)-B%)
330     IF D%<E% THEN E%=D%:N%=L%
340   NEXT
350 =N%
360 DEF PROCdraw
370   LOCAL I%,J%,W%,P%,F%,G%
390   IF M%=110 THEN W%=1536 ELSE W%=1280
400   pi=4*TAN(1):r=2*pi/235:t=RND(4):x=0:u=0:v=0
410   P%=TIME+500
420   FOR I%=0 TO 249
430     FOR J%=0 TO 249
440       F%=INT((I%+v)*K+.5):G%=INT((r*I%+x)*K+.5)
445       u=(S%!(4*(F% AND Q%))+S%!(4*(G% AND Q%)))*Z
450       v=(S%!(4*((F%+H%) AND Q%))+S%!(4*((G%+H%) AND Q%)))*Z
460       x=u+t
470       X%=W%/2+W%/5*u:Y%=512+256*v
480       GCOL 0,O%?((I%*3) MOD 64*4+(J%*3) MOD 4)
490       *POINT X%,Y%
500     NEXT
505     PROCprogress(I%+1,250)
510     IF M%=110 AND TIME>P% THEN P%=TIME+500:OSCLI "UPIC SHOW 50"
520   NEXT
530 ENDPROC
531 DEF PROCtable
534   IF M%=110 THEN V%=1024 ELSE V%=256
535   DIM S% 4*V%-1
536   *TABLE SIN S% V%
537   Q%=V%-1:H%=V% DIV 4:K=V%/2/PI:Z=1/65536
538 ENDPROC
540 DATA 0,0,0, 255,0,0, 0,255,0, 255,255,0, 0,0,255, 255,0,255
550 DATA 0,255,255, 255,255,255, 255,128,0, 128,0,255, 0,128,255
560 DATA 255,0,128, 128,255,0, 0,255,128, 128,128,128, 64,64,64
570 DEF PROCtitle
572   IF M%<>110 THEN ENDPROC
573   COLOUR 7:PRINT TAB(4,9);"Bubble Universe";
574   PRINT TAB(4,10);"a look at the picture every 5 s";
575 ENDPROC
576 DEF PROCprogress(F%,G%)
579   LOCAL B%
580   IF M%<>110 THEN ENDPROC
581   B%=F%*32 DIV G%
582   PRINT TAB(4,12);:COLOUR 135:PRINT SPC(B%);
583   COLOUR 128:COLOUR 7:PRINT TAB(4,14);F%*100 DIV G%;"% drawn  ";
584 ENDPROC
585 DEF PROCend
588   IF M%=110 THEN OSCLI "UPIC SHOW":OSCLI "FX 15,1" ELSE K%=GET
589 ENDPROC
