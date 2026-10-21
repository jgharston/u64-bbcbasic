10 REM GFXDEMO: a tour of U64 BBC BASIC's screen modes and graphics
20 REM commands. Each part is its own program (CHAIN); they return
30 REM here. Keys: any key goes on; RUN/STOP comes back to this menu.
40 REM The menu in the style of the Schraf and music demos.
50 MODE 100
60 *OFF
70 PROCmenu
80 REPEAT
90   K%=GET-48
100 UNTIL K%>=0 AND K%<=5
110 IF K%=0 THEN PROCquit
120 CHAIN MID$("GFXBBC  GFXC64  GFXTTX  GFXUPIC GFXSPR  ",K%*8-7,8)
130 END
140 :
200 DEF PROCmenu
210   LOCAL N%,A$
220   CLS
230   PROChead("U64 BBC BASIC: graphics tour","screen modes and graphics commands")
240   PRINT
250   RESTORE 400
260   FOR N%=1 TO 5
270     READ A$
280     COLOUR 6:PRINT " ";N%;"   ";:COLOUR 3:PRINT A$
290   NEXT
300   PRINT
310   COLOUR 6:PRINT " 0   ";:COLOUR 3:PRINT "quit"
320   PRINT
330   PRINT " Choose: ";
340 ENDPROC
350 :
400 DATA "BBC modes 1, 2, 4, 5 (a test card)","C64 modes 100, 103, 104"
410 DATA "MODE 7, teletext","Upic full, MODE 110 and 111","Sprites"
420 :
500 REM Header as in the music demo: a dark green bar with the title, a
510 REM light green one under it (COLOUR 128+n: text on a coloured bar)
520 DEF PROChead(A$,B$)
530   PRINT TAB(0,0);
540   COLOUR 130:PRINT LEFT$(" "+A$+STRING$(40," "),40);
550   COLOUR 141:PRINT LEFT$(" "+B$+STRING$(40," "),40);
560   COLOUR 128:COLOUR 3
570 ENDPROC
580 :
600 DEF PROCquit
610   *ON
620   COLOUR 128:COLOUR 7:CLS
630   END
640 ENDPROC
