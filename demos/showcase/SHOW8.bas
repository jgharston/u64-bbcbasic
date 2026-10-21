10 REM SHOW8: spirographs: a point on a circle turning on a circle,
20 REM joined with *LINE in 3 colours (Upic Lite MODE 1, SIN *TABLE:
25 REM 256 steps, 1K: MODE 1 leaves 4K)
30 MODE 1
40 *OFF
50 *FX 15,1
60 ON ERROR OSCLI "SONG STOP":OSCLI "MODSTOP":VDU 4:IF ERR=17 END ELSE REPORT:PRINT " at line ";ERL:END
70 DIM S% 1023
80 *TABLE SIN S% 256
90 RESTORE 300
100 FOR K%=1 TO 6
110   READ M%,R%
120   PROCdraw(M%,R%)
130   IF INKEY(250)<>-1 THEN K%=6
140 NEXT
150 CHAIN "SHOW9"
160 END
170 :
200 REM M%: how fast the small circle turns, R%: its radius
210 DEF PROCdraw(M%,R%)
220   LOCAL I%,A%,B%,C%,D%,J%
230   CLG
240   A%=640+(450-R%)+R%:B%=512
250   FOR I%=0 TO 255
260     J%=I%*M% AND 255
270     C%=640+((450-R%)*S%!(4*((I%+64) AND 255))+R%*S%!(4*((J%+64) AND 255))) DIV 65536
280     D%=512+((450-R%)*S%!(4*I%)+R%*S%!(4*J%)) DIV 65536
290     GCOL 0,1+(I% DIV 32) MOD 3:*LINE A%,B%,C%,D%
291     A%=C%:B%=D%
292     IF INKEY(0)<>-1 THEN I%=255
293   NEXT
294 ENDPROC
300 DATA 5,150,-7,120,9,200,-11,90,4,220,-5,60
