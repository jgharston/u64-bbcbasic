10 REM Mathematical Hat: Eric Schraf (QB64), Archimedes BASIC V by
20 REM Xander Mol (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here.
30 REM The eight Archimedes colours (c 3-31 step 4, tints) exact;
40 REM a black line below each point hides what lies behind.
50 MODE M%
60 *OFF
70 IF M%=110 THEN W%=1536 ELSE W%=1280
80 PROCpalette
90 PROCdraw
100 K%=GET
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
230   LOCAL Z%,I%,L%,T%
240   pi=3.1415926:xp=240:xr=1.5*pi:yp=90:xf=xr/xp
250   T%=TIME+500
260   FOR Z%=-yp TO yp
270     zt=Z%*xp/yp
280     L%=INT(0.5+SQR(xp*xp-zt*zt))
290     FOR I%=-L% TO L%
300       xt=SQR(I%*I%+zt*zt)*xf
310       yy=(SIN(xt)+0.4*SIN(3*xt))*yp
320       Y%=INT(yy-Z%+256):X%=INT(I%+Z%+320)
330       PROCpoint
340     NEXT
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
