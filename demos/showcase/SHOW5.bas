10 REM SHOW5: a rotating cube: 8 corners turned with SIN from *TABLE,
20 REM 12 edges drawn and taken away again with EOR (GCOL 3)
30 MODE 1
40 *OFF
50 *FX 15,1
60 ON ERROR OSCLI "SONG STOP":OSCLI "MODSTOP":VDU 4:IF ERR=17 END ELSE REPORT:PRINT " at line ";ERL:END
70 DIM S% 1023,P%(7),Q%(7),U%(7),V%(7),E%(23)
80 *TABLE SIN S% 256
90 RESTORE 500
100 FOR I%=0 TO 23:READ E%(I%):NEXT
110 COLOUR 3:PRINT TAB(12,1);"3D, in BASIC"
120 PROCspin(1500)
130 CHAIN "SHOW6"
140 END
150 :
200 DEF PROCspin(T%)
210   LOCAL A%,B%,F%,E
220   E=TIME+T%:A%=0:B%=0:F%=FALSE
230   GCOL 3,2
240   REPEAT
250     PROCcorners(A%,B%)
260     IF F% PROCedges(TRUE)
270     PROCedges(FALSE)
280     FOR I%=0 TO 7:U%(I%)=P%(I%):V%(I%)=Q%(I%):NEXT
290     F%=TRUE:A%=A%+3:B%=B%+2
300     W%=TIME+2:REPEAT UNTIL TIME>W%
310   UNTIL TIME>E OR INKEY(0)<>-1
320 ENDPROC
330 :
340 REM The corners (+-256 each way) turned A% about y, B% about x,
350 REM then in perspective: P%(), Q%() screen positions
360 DEF PROCcorners(A%,B%)
370   LOCAL I%,X%,Y%,Z%,C%,G%,D%,T%,R%,W%
380   C%=S%!(4*((A%+64) AND 255)):G%=S%!(4*(A% AND 255))
390   D%=S%!(4*((B%+64) AND 255)):T%=S%!(4*(B% AND 255))
400   FOR I%=0 TO 7
410     X%=256-512*(I% AND 1):Y%=256-256*(I% AND 2):Z%=256-128*(I% AND 4)
420     R%=(X%*C%-Z%*G%) DIV 65536:Z%=(X%*G%+Z%*C%) DIV 65536
430     W%=(Y%*D%-Z%*T%) DIV 65536:Z%=(Y%*T%+Z%*D%) DIV 65536
440     P%(I%)=640+R%*900 DIV (Z%+1100):Q%(I%)=512+W%*900 DIV (Z%+1100)
450   NEXT
460 ENDPROC
465 REM The 12 edges: old positions (U%, V%) when O%, else new (P%, Q%)
466 REM (BBC BASIC 3.10 has no array parameters)
470 DEF PROCedges(O%)
480   LOCAL I%,A%,B%,C%,D%,J%,K%
490   FOR I%=0 TO 22 STEP 2
491     J%=E%(I%):K%=E%(I%+1)
492     IF O% A%=U%(J%):B%=V%(J%):C%=U%(K%):D%=V%(K%) ELSE A%=P%(J%):B%=Q%(J%):C%=P%(K%):D%=Q%(K%)
493     *LINE A%,B%,C%,D%
494   NEXT
495 ENDPROC
500 DATA 0,1,2,3,4,5,6,7,0,2,1,3,4,6,5,7,0,4,1,5,2,6,3,7
