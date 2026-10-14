10 REM GFXDEMO: a tour of U64 BBC BASIC's screen modes and graphics
20 REM commands. Each part is its own program (CHAIN); they return
30 REM here. Keys: any key goes on, ESCAPE stops.
40 MODE 100
50 *OFF
60 PRINT "U64 BBC BASIC graphics tour"
70 PRINT
80 PRINT "1: BBC modes 1, 2, 4, 5 (a test card)"
90 PRINT "2: C64 modes 100, 103, 104"
100 PRINT "3: MODE 7, teletext"
110 PRINT "4: Upic full, MODE 110 and 111"
120 PRINT "5: Sprites"
130 PRINT "0: Quit"
140 REPEAT
150   K%=GET-48
160 UNTIL K%>=0 AND K%<=5
170 IF K%=0 THEN PROCquit
180 CHAIN MID$("GFXBBC  GFXC64  GFXTTX  GFXUPIC GFXSPR  ",K%*8-7,8)
190 END
200 DEF PROCquit
210   *ON
220   END
230 ENDPROC
