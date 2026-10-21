10 REM Field Lines: Eric Schraf (QB64), Archimedes BASIC V by
20 REM Xander Mol (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here.
30 REM The four Archimedes colours (c 3,7,11,15, tint 0-192) exact.
40 MODE M%
45 ON ERROR IF ERR=17 THEN CHAIN "SCHRAF" ELSE VDU 4:REPORT:PRINT " at line ";ERL:END
50 *OFF
60 IF M%=110 THEN W%=1536 ELSE W%=1280
65 PROCtable
70 PROCpalette
75 PROCtitle
80 PROCdraw
90 PROCend
100 CHAIN "SCHRAF"
110 END
120 DEF PROCpalette
130   LOCAL L%,R%,G%,B%
140   FOR L%=1 TO 4
150     READ R%,G%,B%
160     *COLOUR L%,R%,G%,B%
170   NEXT
180 ENDPROC
190 DEF PROCdraw
200   LOCAL I%,J%,T%,F%
210   pi=3.1415926:np=1024:n=180:m=30:k=0.02
220   T%=TIME+500
230   FOR I%=0 TO n
240     x=RND(1):y=RND(1)
250     FOR J%=0 TO m
260       sx=INT(np*x)+(1280-np)/2:sy=INT(np*y)
270       IF J%>0 THEN PROCseg
280       px=sx:py=sy
290       xx=2*x-1:yy=2*y-1
300       IF xx<>0 THEN an=ATN(yy/xx) ELSE an=pi/2*SGN(yy)
310       IF xx<0 THEN an=an+pi*SGN(yy)
320       F%=INT(6*pi*SQR(xx*xx+yy*yy)*K+.5)
325       an=an+4*pi/3+S%!(4*(F% AND Q%))*Z/4
330       F%=INT(an*K+.5):x=x+k*S%!(4*((F%+H%) AND Q%))*Z
335       y=y+k*S%!(4*(F% AND Q%))*Z
340       IF x<=0 OR x>=1 OR y<=0 OR y>=1 THEN J%=m
350     NEXT
355     PROCprogress(I%+1,n+1)
360     IF M%=110 AND TIME>T% THEN T%=TIME+500:OSCLI "UPIC SHOW 50"
370   NEXT
380 ENDPROC
390 DEF PROCseg
400   GCOL 0,1+(px*px+py*py) MOD 4
410   A%=px*W%/1280:B%=py:C%=sx*W%/1280:D%=sy
420   *LINE A%,B%,C%,D%
430 ENDPROC
431 DEF PROCtable
432   REM SIN and COS from *TABLE: 256 steps a turn in MODE 2 (1K: MODE 2
433   REM leaves under 5K), 1024 in MODE 110; COS is a quarter turn on (H%)
434   IF M%=110 THEN V%=1024 ELSE V%=256
435   DIM S% 4*V%-1
436   *TABLE SIN S% V%
437   Q%=V%-1:H%=V% DIV 4:K=V%/2/PI:Z=1/65536
438 ENDPROC
440 DATA 204,0,0, 221,85,17, 238,170,34, 255,255,51
450 DEF PROCtitle
451   REM Full mode: the text screen shows while the picture is drawn
452   IF M%<>110 THEN ENDPROC
453   COLOUR 4:PRINT TAB(4,9);"Field Lines";
454   PRINT TAB(4,10);"a look at the picture every 5 s";
455 ENDPROC
456 DEF PROCprogress(F%,G%)
457   REM Full mode: a bar growing to 32 cells as F% of G% is done, in
458   REM colour 4: bright in this demo's palette (the text screen's too)
459   LOCAL B%
460   IF M%<>110 THEN ENDPROC
461   B%=F%*32 DIV G%
462   PRINT TAB(4,12);:COLOUR 132:PRINT SPC(B%);
463   COLOUR 128:COLOUR 4:PRINT TAB(4,14);F%*100 DIV G%;"% drawn  ";
464 ENDPROC
465 DEF PROCend
466   REM Full mode: the finished picture until a key (GET shows it only
467   REM when it changed since the last look); the key is not kept
468   IF M%=110 THEN OSCLI "UPIC SHOW":OSCLI "FX 15,1" ELSE K%=GET
469 ENDPROC
