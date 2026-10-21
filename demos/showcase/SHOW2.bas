10 REM SHOW2: Bubble Universe (Eric Schraf; ArchBAS by Xander Mol),
20 REM smaller, with SIN from *TABLE (256 steps: MODE 2 has 4K)
30 MODE 2
40 *OFF
45 *FX 15,1
47 ON ERROR OSCLI "SONG STOP":OSCLI "MODSTOP":VDU 4:IF ERR=17 END ELSE REPORT:PRINT " at line ";ERL:END
50 DIM S% 1023
60 *TABLE SIN S% 256
70 PROCdraw(2000)
80 K%=INKEY(300)
90 CHAIN "SHOW3"
100 END
110 :
200 DEF PROCdraw(T%)
210   LOCAL I%,J%,F%,G%,E%,K,Z,r,t,x,u,v
220   K=128/PI:Z=1/65536:r=2*PI/235:t=RND(4):x=0:u=0:v=0
230   E%=TIME+T%
240   GCOL 0,0:CLG
250   FOR I%=0 TO 59
260     FOR J%=0 TO 149
270       F%=INT((I%+v)*K+.5):G%=INT((r*I%+x)*K+.5)
280       u=(S%!(4*(F% AND 255))+S%!(4*(G% AND 255)))*Z
290       v=(S%!(4*((F%+64) AND 255))+S%!(4*((G%+64) AND 255)))*Z
300       x=u+t
310       GCOL 0,1+(I%*2+J% DIV 10) MOD 15
320       X%=640+256*u:Y%=512+256*v:*POINT X%,Y%
330     NEXT
340     IF TIME>E% OR INKEY(0)<>-1 THEN I%=59
350   NEXT
360 ENDPROC
