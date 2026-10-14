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
110 PROCdraw
120 K%=GET
130 CHAIN "SCHRAF"
140 END
150 DEF PROCdraw
160   LOCAL N%,T%
170   T%=TIME+500
180   FOR N%=1 TO 50000
190     s=LOG(RND(1)):t=300*RND(1)
200     u=60*s*SIN(t):v=50*s*COS(t)
210     p=3*s:c=COS(p):s2=SIN(p)
220     x=u*c+v*s2:y=-u*s2+v*c
230     z=80*EXP(-(x*x+y*y)/10)*(RND(1)-0.5)
240     y=y+z+INT(RND(40))+1
250     x=x+(-z*0.3*INT(RND(20)+1))
260     X%=4*INT(160+x*0.7+y*0.3):Y%=4*INT(120+x*0.1+y*0.4)
270     IF X%>=0 AND X%<1280 AND Y%>=0 AND Y%<1024 THEN PROCstar
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
