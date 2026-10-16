10 REM Galaxy: Eric Schraf (QB64), Archimedes BASIC V by Xander Mol
20 REM (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here. Four
30 REM colours, exact; each star brightens what is there.
40 MODE M%
50 *OFF
60 IF M%=110 THEN W%=1536 ELSE W%=1280
70 *COLOUR 0,0,0,0
80 *COLOUR 1,255,0,0
90 *COLOUR 2,255,255,0
100 *COLOUR 3,255,255,255
105 PROCtable
107 PROCtitle
110 PROCdraw
120 PROCend
130 CHAIN "SCHRAF"
140 END
150 DEF PROCdraw
160   LOCAL N%,T%,F%,G%
170   T%=TIME+500
180   FOR N%=1 TO 50000
190     s=LOG(RND(1)):t=300*RND(1)
200     F%=INT(t*K+.5):p=3*s:G%=INT(p*K+.5)
205     u=60*s*S%!(4*(F% AND Q%))*Z:v=50*s*S%!(4*((F%+H%) AND Q%))*Z
210     c=S%!(4*((G%+H%) AND Q%))*Z:s2=S%!(4*(G% AND Q%))*Z
220     x=u*c+v*s2:y=-u*s2+v*c
230     z=80*EXP(-(x*x+y*y)/10)*(RND(1)-0.5)
240     y=y+z+INT(RND(40))+1
250     x=x+(-z*0.3*INT(RND(20)+1))
260     X%=4*INT(160+x*0.7+y*0.3):Y%=4*INT(120+x*0.1+y*0.4)
270     IF X%>=0 AND X%<1280 AND Y%>=0 AND Y%<1024 THEN PROCstar
275     IF N% MOD 500=0 THEN PROCprogress(N%,50000)
280     IF M%=110 AND TIME>T% THEN T%=TIME+500:OSCLI "UPIC SHOW 50"
290   NEXT
300 ENDPROC
310 DEF PROCstar
320   LOCAL C%
330   A%=X%*W%/1280:B%=1024-Y%
340   C%=POINT(A%,Y%)
350   IF C%<3 THEN C%=C%+1
360   GCOL 0,C%
370   *RECTANGLE FILL A%,B%,2
380 ENDPROC
390 DEF PROCtable
391   REM SIN and COS from *TABLE: 256 steps a turn in MODE 2 (1K: MODE 2
392   REM leaves under 5K), 1024 in MODE 110; COS is a quarter turn on (H%)
393   IF M%=110 THEN V%=1024 ELSE V%=256
394   DIM S% 4*V%-1
395   *TABLE SIN S% V%
396   Q%=V%-1:H%=V% DIV 4:K=V%/2/PI:Z=1/65536
397 ENDPROC
400 DEF PROCtitle
401   REM Full mode: the text screen shows while the picture is drawn
402   IF M%<>110 THEN ENDPROC
403   COLOUR 3:PRINT TAB(4,9);"Galaxy";
404   PRINT TAB(4,10);"a look at the picture every 5 s";
405 ENDPROC
406 DEF PROCprogress(F%,G%)
407   REM Full mode: a bar growing to 32 cells as F% of G% is done, in
408   REM colour 3: bright in this demo's palette (the text screen's too)
409   LOCAL B%
410   IF M%<>110 THEN ENDPROC
411   B%=F%*32 DIV G%
412   PRINT TAB(4,12);:COLOUR 131:PRINT SPC(B%);
413   COLOUR 128:COLOUR 3:PRINT TAB(4,14);F%*100 DIV G%;"% drawn  ";
414 ENDPROC
415 DEF PROCend
416   REM Full mode: the finished picture until a key (GET shows it only
417   REM when it changed since the last look); the key is not kept
418   IF M%=110 THEN OSCLI "UPIC SHOW":OSCLI "FX 15,1" ELSE K%=GET
419 ENDPROC
