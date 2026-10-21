10 REM SHOW3: speed: filled circles, then filled triangles, counted live
20 REM (*CIRCLE FILL and PLOT 85 in Upic Lite MODE 2, 8 s each)
30 MODE 2
40 *OFF
50 *FX 15,1
60 ON ERROR OSCLI "SONG STOP":OSCLI "MODSTOP":VDU 4:IF ERR=17 END ELSE REPORT:PRINT " at line ";ERL:END
70 PROCrace("circles",0)
80 PROCrace("triangles",1)
90 CHAIN "SHOW4"
100 END
110 :
200 REM As many shapes as fit in 8 s, the count shown as it goes
210 DEF PROCrace(A$,T%)
220   LOCAL N%,E%
230   CLG:N%=0
240   E%=TIME+800
250   REPEAT
260     GCOL 0,1+RND(15)
270     IF T%=0 PROCcircle ELSE PROCtriangle
280     N%=N%+1
290     IF (N% AND 15)=0 COLOUR 7:PRINT TAB(0,0);N%;" ";A$;" ";
300   UNTIL TIME>E% OR INKEY(0)<>-1
310   COLOUR 7:PRINT TAB(0,0);N%;" ";A$;" ";TAB(0,1);"in 8 seconds"
320   E%=INKEY(200)
330 ENDPROC
340 DEF PROCcircle
350   X%=RND(1280):Y%=RND(1024):R%=8+RND(40)
360   *CIRCLE FILL X%,Y%,R%
370 ENDPROC
380 DEF PROCtriangle
390   X%=RND(1280):Y%=RND(1024)
400   MOVE X%,Y%:MOVE X%+RND(240)-120,Y%+RND(240)-120
410   PLOT 85,X%+RND(240)-120,Y%+RND(240)-120
420 ENDPROC
