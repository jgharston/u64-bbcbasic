10 REM Field Lines: Eric Schraf (QB64), Archimedes BASIC V by
20 REM Xander Mol (github.com/xahmol/ArchBAS), BBC BASIC 3.10 here.
30 REM The four Archimedes colours (c 3,7,11,15, tint 0-192) exact.
40 MODE M%
50 *OFF
60 IF M%=110 THEN W%=1536 ELSE W%=1280
70 PROCpalette
80 PROCdraw
90 K%=GET
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
200   LOCAL I%,J%,T%
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
320       an=an+4*pi/3+SIN(6*pi*SQR(xx*xx+yy*yy))/4
330       x=x+k*COS(an):y=y+k*SIN(an)
340       IF x<=0 OR x>=1 OR y<=0 OR y>=1 THEN J%=m
350     NEXT
360     IF M%=110 AND TIME>T% THEN T%=TIME+500:OSCLI "UPIC SHOW 50"
370   NEXT
380 ENDPROC
390 DEF PROCseg
400   GCOL 0,1+(px*px+py*py) MOD 4
410   A%=px*W%/1280:B%=py:C%=sx*W%/1280:D%=sy
420   *LINE A%,B%,C%,D%
430 ENDPROC
440 DATA 204,0,0, 221,85,17, 238,170,34, 255,255,51
