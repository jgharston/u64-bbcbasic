10 REM Schraf Graphical BASIC demos for U64 BBC BASIC
20 REM Originals in QB64 by Eric Schraf (youtube.com/@Schraf),
30 REM Acorn Archimedes BASIC V version by Xander Mol (2025,
40 REM github.com/xahmol/ArchBAS), converted to BBC BASIC 3.10
50 REM with the U64's * graphics commands (2026).
60 REM M%: the mode chosen, 2 (live) or 110 (full); kept over CHAIN.
70 MODE 100
80 *OFF
90 PRINT "Schraf Graphical BASIC demos"
100 PRINT "(Eric Schraf; Archimedes: Xander Mol)"
110 PRINT
120 PRINT "1: Bubble Universe"
130 PRINT "2: Field Lines"
140 PRINT "3: Mathematical Hat"
150 PRINT "4: Event Horizon"
160 PRINT "5: Galaxy"
170 PRINT "0: Quit"
180 PRINT
190 PRINT "Live: MODE 2, 160x256, drawn as you"
200 PRINT "      watch. Full: MODE 110, 384x256,"
210 PRINT "      a look every 5 seconds."
220 PRINT
230 REPEAT
240   K%=GET-48
250 UNTIL K%>=0 AND K%<=5
260 IF K%=0 THEN PROCquit
270 PRINT "L)ive or F)ull?"
280 REPEAT
290   L$=CHR$(GET AND &DF)
300 UNTIL L$="L" OR L$="F"
310 IF L$="L" THEN M%=2 ELSE M%=110
320 CHAIN MID$("BUBBLE  FIELD   HAT     HORIZON GALAXY  ",K%*8-7,8)
330 END
340 DEF PROCquit
350   *ON
360   END
370 ENDPROC
