10 REM GFXUPIC: Upic full, 384x256 in 16 colours (MODE 110; MODE 111
20 REM 288 wide for 48 MHz Ultimates). Text stays on the console; the
30 REM picture shows with *UPIC SHOW (n: for n centiseconds) and by
40 REM itself in GET and when the program ends.
45 ON ERROR IF ERR=17 THEN CHAIN "GFXDEMO" ELSE VDU 4:REPORT:PRINT " at line ";ERL:END
50 MODE 110
60 *OFF
70 PRINT "MODE 110: drawing a 16-colour picture."
80 PROCpalette
90 PROCbars
100 PRINT "A first look for one second..."
110 *UPIC SHOW 100
120 PROCcircles
130 PRINT "Done: press a key to see it, again to go on."
140 K%=GET
150 MODE 111
160 *OFF
170 PRINT "MODE 111: 288 wide, the 48 MHz layout."
180 PROCpalette
190 PROCcircles
200 K%=GET
210 CHAIN "GFXDEMO"
220 END
230 DEF PROCpalette
240   LOCAL L%,R%,G%,B%
250   FOR L%=0 TO 15
260     R%=L%*17:G%=255-L%*12:B%=128+L%*8
270     *COLOUR L%,R%,G%,B%
280   NEXT
290 ENDPROC
300 DEF PROCbars
310   LOCAL L%
320   FOR L%=0 TO 15
330     GCOL 0,L%:A%=L%*96
340     *RECTANGLE FILL A%,0,96,1023
350   NEXT
360 ENDPROC
370 DEF PROCcircles
380   LOCAL L%
390   FOR L%=15 TO 1 STEP -1
400     GCOL 0,L%:R%=L%*30
410     *CIRCLE FILL 768,512,R%
420   NEXT
430   GCOL 0,0
440   MOVE 600,520:VDU 5:PRINT "Upic full";:VDU 4
450 ENDPROC
