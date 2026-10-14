10 REM Christmas Tree: original by Aurel Wizzard; Acorn Archimedes
20 REM version by Xander Mol with Google Gemini (github.com/xahmol/
30 REM ArchBAS), BBC BASIC 3.10 here with the U64's * commands.
40 REM Coordinates 640 x 480 with y down, as the original.
50 PRINT "Christmas tree: L)ive (MODE 2) or F)ull (MODE 110)?"
60 REPEAT
70   L$=CHR$(GET AND &DF)
80 UNTIL L$="L" OR L$="F"
90 IF L$="L" THEN M%=2 ELSE M%=110
100 MODE M%
110 *OFF
120 IF M%=110 THEN W%=1536 ELSE W%=1280
125 T%=TIME+500
130 PROCpalette
140 PROCstars
150 PROCtrunk
160 PROCleaves
170 PROCtext
180 PROCornaments
190 GCOL 0,5:PROCprint(20,460,"SPACE: exit")
200 REPEAT
210 UNTIL GET=32
220 MODE 100
230 *ON
240 END
250 DEF PROCpalette
260   LOCAL L%,R%,G%,B%
270   FOR L%=1 TO 13
280     READ R%,G%,B%
290     *COLOUR L%,R%,G%,B%
300   NEXT
310 ENDPROC
320 DEF PROCstars
330   LOCAL x
340   FOR x=10 TO 396 STEP 4
350     GCOL 0,1
360     PROCprint(RND(600),RND(480),".")
370   NEXT
380 ENDPROC
390 DEF PROCtrunk
400   LOCAL a
410   GCOL 0,3
420   FOR a=-4 TO 3
430     PROCline(220+a,410,220,20)
440   NEXT
450 ENDPROC
460 DEF PROCleaves
470   LOCAL rad,tpy,ht,xs,xh,rise,aa,frad,x1,y1,x2,y2
480   GCOL 0,4
490   rad=160:tpy=370
500   FOR ht=1 TO 39
510     FOR xs=-100 TO 99 STEP 40
520       xh=xs/100:rise=RND(1)*0.93
530       PROCline(220,tpy,220+xh*rad,tpy-rise*rad)
540       FOR aa=1 TO 29
550         frad=RND(1)*0.9*rad
560         x1=220+xh*frad:y1=tpy-rise*frad
570         x2=220+xh*(frad+rad/5)
580         y2=tpy-rise*frad+(-rise+(RND(1)*0.9-0.456))*(rad/5)
590         PROCline(x1,y1,x2,y2)
600       NEXT
610     NEXT
620     rad=rad-4:tpy=tpy-9
630     IF M%=110 THEN PROCpeek
640   NEXT
650 ENDPROC
660 DEF PROCpeek
670   IF TIME>T% THEN T%=TIME+500:OSCLI "UPIC SHOW 50"
680 ENDPROC
690 DEF PROCtext
700   GCOL 0,5
710   IF M%=2 THEN PROCprint(150,40,"Merry Christmas!"):PROCprint(150,80,"Happy New Year!"):ENDPROC
720   PROCprint(300,40," * * * Merry Christmas ! * * * ")
730   PROCprint(300,80," * * * Happy New Year ! * * * ")
740 ENDPROC
750 DEF PROCornaments
760   LOCAL I%,x,y
770   FOR I%=6 TO 12
780     READ x,y
790     GCOL 0,I%
800     PROCball(x,y)
810   NEXT
820 ENDPROC
830 DEF PROCball(x,y)
840   LOCAL R%
850   A%=x*2*W%/1280:B%=(480-y)*2
860   FOR R%=12 TO 4 STEP -4
870     *CIRCLE A%,B%,R%
880   NEXT
890 ENDPROC
900 DEF PROCline(x1,y1,x2,y2)
910   A%=x1*2*W%/1280:B%=(480-y1)*2:C%=x2*2*W%/1280:D%=(480-y2)*2
920   *LINE A%,B%,C%,D%
930 ENDPROC
940 DEF PROCprint(x,y,t$)
950   MOVE x*2*W%/1280,(480-y)*2
960   VDU 5:PRINT t$;:VDU 4
970 ENDPROC
980 REM 1-2 stars (the original sets 2 but draws in 1), 3 trunk, 4 leaves, 5 text, 6-12 the ornaments
990 DATA 220,220,110, 120,220,210, 130,100,0, 30,120,40, 200,220,200
1000 DATA 220,200,100, 250,100,100, 150,100,250, 80,150,255
1010 DATA 80,250,255, 200,150,255, 250,180,255
1020 DATA 190,100, 250,180, 175,165, 140,225, 270,245, 90,302, 295,302
