10 REM Christmas Tree: original by Aurel Wizzard; Acorn Archimedes
20 REM version by Xander Mol with Google Gemini (github.com/xahmol/
30 REM ArchBAS), BBC BASIC 3.10 here with the U64's * commands.
40 REM XMAS: the menu (in the Schraf menu's style); the drawing is
50 REM XMASTREE (MODE 2 leaves 4K: menu and tree as one did not fit).
70 MODE 100
80 *OFF
90 IF M%<>110 THEN M%=2
100 REPEAT
110   PROCmenu
120   K$=GET$
130   IF K$="L" OR K$="l" THEN M%=2
140   IF K$="F" OR K$="f" THEN M%=110
150 UNTIL K$=" " OR K$="Q" OR K$="q"
160 IF K$<>" " THEN *ON
170 IF K$<>" " THEN COLOUR 128:COLOUR 7:CLS:END
180 CHAIN "XMASTREE"
190 END
1100 REM The menu: the mode chosen marked, as in demos/archbas/SCHRAF
1110 DEF PROCmenu
1120   CLS
1130   PROChead("Christmas tree","Aurel Wizzard; Archimedes: Xander Mol")
1140   PRINT
1150   PROCmode("L","live  MODE 2, drawn as you watch",M%=2)
1160   PROCmode("F","full  MODE 110, a look every 5 s",M%=110)
1170   PRINT
1180   COLOUR 6:PRINT " SPACE ";:COLOUR 3:PRINT "start"
1190   COLOUR 6:PRINT " Q     ";:COLOUR 3:PRINT "quit"
1200   PRINT
1210   PRINT " Choose: ";
1220 ENDPROC
1230 DEF PROCmode(K$,A$,S%)
1240   COLOUR 6:PRINT " ";K$;" ";
1250   IF S% THEN COLOUR 7:PRINT "> ";:COLOUR 3 ELSE PRINT "  ";:COLOUR 12
1260   PRINT A$
1270 ENDPROC
1280 DEF PROChead(A$,B$)
1290   PRINT TAB(0,0);
1300   COLOUR 130:PRINT LEFT$(" "+A$+STRING$(40," "),40);
1310   COLOUR 141:PRINT LEFT$(" "+B$+STRING$(40," "),40);
1320   COLOUR 128:COLOUR 3
1330 ENDPROC
