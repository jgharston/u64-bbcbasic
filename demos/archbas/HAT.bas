10 REM Mathematical Hat: Eric Schraf (QB64), Archimedes BASIC V by
20 REM Xander Mol (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here.
30 REM The eight Archimedes colours (c 3-31 step 4, tints) exact;
40 REM a black line below each point hides what lies behind.
50 MODE M%
60 *OFF
70 IF M%=110 THEN W%=1536 ELSE W%=1280
75 PROCtable
80 PROCpalette
85 PROCtitle
90 PROCdraw
100 PROCend
110 CHAIN "SCHRAF"
120 END
130 DEF PROCpalette
140   LOCAL L%,T%
150   FOR L%=0 TO 7
160     T%=L% AND 3
170     R%=(12+T%)*17:G%=((L% AND 3)*4+T%)*17:B%=((L% DIV 4)*4+T%)*17
180     C%=L%+1
190     *COLOUR C%,R%,G%,B%
200   NEXT
210 ENDPROC
220 DEF PROCdraw
230   LOCAL Z%,I%,L%,T%,F%,G%
240   pi=3.1415926:xp=240:xr=1.5*pi:yp=90:xf=xr/xp
250   T%=TIME+500
260   FOR Z%=-yp TO yp
270     zt=Z%*xp/yp
280     L%=INT(0.5+SQR(xp*xp-zt*zt))
290     FOR I%=-L% TO L%
300       xt=SQR(I%*I%+zt*zt)*xf
310       F%=INT(xt*K+.5):G%=INT(3*xt*K+.5)
315       yy=(S%!(4*(F% AND Q%))+0.4*S%!(4*(G% AND Q%)))*Z*yp
320       Y%=INT(yy-Z%+256):X%=INT(I%+Z%+320)
330       PROCpoint
340     NEXT
345     PROCprogress(Z%+yp+1,2*yp+1)
350     IF M%=110 AND TIME>T% THEN T%=TIME+500:OSCLI "UPIC SHOW 50"
360   NEXT
370 ENDPROC
380 DEF PROCpoint
390   GCOL 0,1+(X%*X%+Y%*Y%) MOD 8
400   A%=X%*2*W%/1280:B%=Y%*2
410   *POINT A%,B%
420   GCOL 0,0
430   A%=(X%-1)*2*W%/1280:B%=(Y%-1)*2:D%=0
440   *LINE A%,B%,A%,D%
450 ENDPROC
460 DEF PROCtable
461   REM SIN and COS from *TABLE: 256 steps a turn in MODE 2 (1K: MODE 2
462   REM leaves under 5K), 1024 in MODE 110; COS is a quarter turn on (H%)
463   IF M%=110 THEN V%=1024 ELSE V%=256
464   DIM S% 4*V%-1
465   *TABLE SIN S% V%
466   Q%=V%-1:H%=V% DIV 4:K=V%/2/PI:Z=1/65536
467 ENDPROC
470 DEF PROCtitle
471   REM Full mode: the text screen shows while the picture is drawn
472   IF M%<>110 THEN ENDPROC
473   COLOUR 4:PRINT TAB(4,9);"Mathematical Hat";
474   PRINT TAB(4,10);"a look at the picture every 5 s";
475 ENDPROC
476 DEF PROCprogress(F%,G%)
477   REM Full mode: a bar growing to 32 cells as F% of G% is done, in
478   REM colour 4: bright in this demo's palette (the text screen's too)
479   LOCAL B%
480   IF M%<>110 THEN ENDPROC
481   B%=F%*32 DIV G%
482   PRINT TAB(4,12);:COLOUR 132:PRINT SPC(B%);
483   COLOUR 128:COLOUR 4:PRINT TAB(4,14);F%*100 DIV G%;"% drawn  ";
484 ENDPROC
485 DEF PROCend
486   REM Full mode: the finished picture until a key (GET shows it only
487   REM when it changed since the last look); the key is not kept
488   IF M%=110 THEN OSCLI "UPIC SHOW":OSCLI "FX 15,1" ELSE K%=GET
489 ENDPROC
