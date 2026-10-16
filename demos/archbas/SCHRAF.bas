10 REM Schraf Graphical BASIC demos for U64 BBC BASIC
20 REM Originals in QB64 by Eric Schraf (youtube.com/@Schraf),
30 REM Acorn Archimedes BASIC V version by Xander Mol (2025,
40 REM github.com/xahmol/ArchBAS), converted to BBC BASIC 3.10
50 REM with the U64's * graphics commands (2026).
60 REM M%: the mode chosen, 2 (live) or 110 (full); kept over CHAIN.
70 REM The menu in the style of the music demo (demos/music): L and F
80 REM choose the mode, a number starts a demo in it.
90 MODE 100
100 *OFF
110 IF M%<>110 THEN M%=2
120 REPEAT
130   PROCmenu
140   K$=GET$
150   IF K$="L" OR K$="l" THEN M%=2
160   IF K$="F" OR K$="f" THEN M%=110
170 UNTIL (K$>="1" AND K$<="5") OR K$="Q" OR K$="q"
180 IF K$="Q" OR K$="q" THEN PROCquit
190 CHAIN MID$("BUBBLE  FIELD   HAT     HORIZON GALAXY  ",VAL K$*8-7,8)
200 END
210 :
220 DEF PROCmenu
230   LOCAL N%,A$
240   CLS
250   PROChead("Schraf Graphical BASIC demos","by Eric Schraf; Archimedes: Xander Mol")
260   PRINT
270   RESTORE 520
280   FOR N%=1 TO 5
290     READ A$
300     COLOUR 6:PRINT " ";N%;"   ";:COLOUR 3:PRINT A$
310   NEXT
320   PRINT
330   PROCmode("L","live  MODE 2, drawn as you watch",M%=2)
340   PROCmode("F","full  MODE 110, a look every 5 s",M%=110)
350   PRINT
360   COLOUR 6:PRINT " Q   ";:COLOUR 3:PRINT "quit"
370   PRINT
380   PRINT " Choose: ";
390 ENDPROC
400 :
410 REM A mode line: the chosen one marked and in yellow, the other grey
420 DEF PROCmode(K$,A$,S%)
430   COLOUR 6:PRINT " ";K$;" ";
440   IF S% THEN COLOUR 7:PRINT "> ";:COLOUR 3 ELSE PRINT "  ";:COLOUR 12
450   PRINT A$
460 ENDPROC
470 :
480 DEF PROCquit
490   *ON
500   COLOUR 128:COLOUR 7:CLS
510   END
515 ENDPROC
520 DATA Bubble Universe, Field Lines, Mathematical Hat, Event Horizon, Galaxy
530 :
540 REM Header as in the music demo: a dark green bar with the title, a
550 REM light green one under it (COLOUR 128+n: text on a coloured bar)
560 DEF PROChead(A$,B$)
570   PRINT TAB(0,0);
580   COLOUR 130:PRINT LEFT$(" "+A$+STRING$(40," "),40);
590   COLOUR 141:PRINT LEFT$(" "+B$+STRING$(40," "),40);
600   COLOUR 128:COLOUR 3
610 ENDPROC
