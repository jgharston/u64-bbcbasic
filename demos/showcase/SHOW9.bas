10 REM SHOW9: Upic full (MODE 110): a sunset in 16 colours of its own,
20 REM drawn into the picture in the REU, then shown: 384 x 256, every
30 REM pixel its own colour
40 MODE 110
50 *OFF
55 *FX 15,1
60 ON ERROR OSCLI "SONG STOP":OSCLI "MODSTOP":VDU 4:IF ERR=17 END ELSE REPORT:PRINT " at line ";ERL:END
70 PRINT "Upic full: drawing a sunset in the REU..."
80 PROCpalette
90 PROCsky
100 PROCsun
110 PROCsea
120 PROChills
130 PROCtell
140 *UPIC SHOW 600
150 CHAIN "SHOW10"
160 END
170 :
180 REM Why the music pauses: the viewer races the beam with every cycle
185 DEF PROCtell
186   LOCAL T%
187   PRINT '"Done. Upic full: 384 x 256 pixels,"
188   PRINT "each one its own colour."
189   PRINT '"To show it, the CPU spends every cycle"
190   PRINT "racing the beam: no time is left for"
191   PRINT "the music, so it pauses while the"
192   PRINT "picture is up, and then goes on."
193   T%=TIME+900:REPEAT UNTIL TIME>T% OR INKEY(0)<>-1
194 ENDPROC
195 :
200 REM 1-8 sky from deep blue to orange, 9 sun, 10-12 sea, 13 hills
210 DEF PROCpalette
220   LOCAL L%,R%,G%,B%
230   RESTORE 600
240   FOR L%=1 TO 13
250     READ R%,G%,B%
260     *COLOUR L%,R%,G%,B%
270   NEXT
280 ENDPROC
290 DEF PROCsky
300   LOCAL I%,Y%
310   FOR I%=1 TO 8
320     GCOL 0,9-I%:Y%=1024-I%*64
330     *RECTANGLE FILL 0,Y%,1535,64
340   NEXT
350 ENDPROC
360 DEF PROCsun
370   GCOL 0,9:*CIRCLE FILL 768,560,150
380 ENDPROC
390 REM The sea under the horizon (y 512), stripes and the sun's path
400 DEF PROCsea
410   LOCAL Y%,W%
420   FOR Y%=0 TO 480 STEP 32
430     GCOL 0,10+(Y% DIV 32) MOD 3
440     *RECTANGLE FILL 0,Y%,1535,31
450     W%=40+Y% DIV 3:GCOL 0,9
460     A%=768-W%:*RECTANGLE FILL A%,Y%,W%,8
470     A%=768+W% DIV 3:C%=W% DIV 2:*RECTANGLE FILL A%,Y%,C%,8
480   NEXT
490 ENDPROC
500 DEF PROChills
510   GCOL 0,13
520   MOVE 0,512:MOVE 0,700:PLOT 85,360,512
530   MOVE 200,512:MOVE 420,640:PLOT 85,600,512
540   MOVE 1535,512:MOVE 1535,760:PLOT 85,1100,512
550   MOVE 1300,512:MOVE 1120,610:PLOT 85,950,512
560 ENDPROC
600 DATA 20,20,80, 40,30,110, 70,40,130, 110,50,140, 160,60,130
610 DATA 210,80,110, 240,110,80, 255,150,60, 255,230,120
620 DATA 40,60,120, 30,50,100, 60,80,140, 15,15,30
