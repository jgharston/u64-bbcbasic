10 REM Christmas Tree: original by Aurel Wizzard; Acorn Archimedes
20 REM version by Xander Mol with Google Gemini (github.com/xahmol/
30 REM ArchBAS), BBC BASIC 3.10 here with the U64's * commands.
40 REM Coordinates 640 x 480 with y down, as the original.
50 REM XMASTREE: the drawing, in mode M% (2 live, 110 full: XMAS's menu
60 REM sets it, kept over CHAIN); RUN/STOP (ESCAPE) goes back to the menu.
170 IF M%<>110 THEN M%=2
180 MODE M%
190 *OFF
200 ON ERROR PROCback
210 IF M%=110 THEN W%=1536 ELSE W%=1280
220 T%=TIME+500
230 PROCpalette
240 PROCstars
241 PROCtrunk
242 PROCleaves
243 PROCtext
244 PROCornaments
245 IF M%=110 THEN OSCLI "UPIC SHOW":OSCLI "FX 15,1"
246 IF M%=2 THEN GCOL 0,5:PROCprint(320,460,"Any key"):K%=GET
247 CHAIN "XMAS"
248 END
249 :
250 DEF PROCpalette
260   LOCAL L%,R%,G%,B%
270   FOR L%=1 TO 12
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
630     IF M%=110 THEN PROCpeek:PROCprogress(ht,39)
640   NEXT
650 ENDPROC
660 DEF PROCpeek
670   IF TIME>T% THEN T%=TIME+500:OSCLI "UPIC SHOW 50"
680 ENDPROC
690 DEF PROCtext
700   GCOL 0,5
705   REM MODE 2 is 20 characters wide: beside the tree, in short lines
710   IF M%=2 THEN PROCprint(320,150,"Merry"):PROCprint(320,180,"Christmas!"):PROCprint(320,250,"Happy"):PROCprint(320,280,"New Year!"):ENDPROC
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
980 REM 12 colours: 1-2 stars (the original sets 2 but draws in 1), 3
985 REM trunk, 4 leaves, 5 text, 6-12 the ornaments
990 DATA 220,220,110, 120,220,210, 130,100,0, 30,120,40, 200,220,200
1000 DATA 220,200,100, 250,100,100, 150,100,250, 80,150,255
1010 DATA 80,250,255, 200,150,255, 250,180,255
1020 DATA 190,100, 250,180, 175,165, 140,225, 270,245, 90,302, 295,302
1340 REM Full mode: a bar growing to 32 cells and the percentage, as in
1350 REM the Schraf demos (the text screen shows while the picture grows)
1360 DEF PROCprogress(F%,G%)
1370   LOCAL B%
1380   IF F%=1 THEN COLOUR 7:PRINT TAB(4,9);"Christmas tree";
1390   B%=F%*32 DIV G%
1400   PRINT TAB(4,12);:COLOUR 135:PRINT SPC(B%);
1410   COLOUR 128:COLOUR 7:PRINT TAB(4,14);F%*100 DIV G%;"% drawn  ";
1420 ENDPROC
1430 REM RUN/STOP (ESCAPE) while drawing: back to the menu
1440 DEF PROCback
1450   IF ERR<>17 THEN VDU 4:REPORT:PRINT " at line ";ERL:END
1460   CHAIN "XMAS"
1470 ENDPROC
