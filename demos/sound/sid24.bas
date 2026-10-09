10 REM SID24: all 24 voices of 8 SIDs (UltiSID 8SID layout, see u64bbc.cfg)
20 REM Writes the SID registers directly until SID mode SOUND exists.
30 DIM S%(7),N%(23)
40 PROCinit
50 PROCcascade
60 PROCwait(300)
70 PROCrelease
80 PROCwait(150)
90 PROCshimmer(4)
100 PROCrelease
110 PROCwait(150)
120 PROCrun
130 PROCrelease
140 PRINT "Done."
150 END
160 :
200 DEF PROCinit
210   LOCAL I%
220   RESTORE 900
230   FOR I%=0 TO 7
240     READ S%(I%)
250     ?(S%(I%)+24)=15
260   NEXT
270   FOR I%=0 TO 23
280     READ N%(I%)
290   NEXT
300   PRINT "24 voices on 8 SIDs"
310 ENDPROC
320 :
400 REM Voice V%: note N% semitones above C2, waveform W%, gate on
410 DEF PROCvoice(V%,N%,W%)
420   LOCAL B%,F%
430   B%=S%(V% DIV 3)+7*(V% MOD 3)
440   F%=65.406*2^(N%/12)*17.0284
450   ?B%=F% AND 255
460   B%?1=F% DIV 256
470   B%?2=0
480   B%?3=8
490   B%?5=&09
500   B%?6=&A8
510   B%?4=W%
520   B%?4=W%+1
530 ENDPROC
540 :
600 DEF PROCwait(C%)
610   LOCAL T%
620   T%=TIME
630   REPEAT UNTIL TIME>=T%+C%
640 ENDPROC
650 :
700 REM Voices enter one by one: SID n plays triangle, saw or pulse
710 DEF PROCcascade
720   LOCAL V%
730   PRINT "Cascade"
740   FOR V%=0 TO 23
750     PROCvoice(V%,N%(V%),FNwave(V% DIV 3))
760     PROCwait(15)
770   NEXT
780 ENDPROC
790 :
800 DEF FNwave(S%)
810   =&10*2^(S% MOD 3)
820 :
900 DATA &D400,&D420,&D480,&D4A0,&D500,&D520,&D580,&D5A0
910 DATA 0,7,12,16,19,23,24,26,28,31,35,36
920 DATA 38,40,43,47,48,50,52,55,59,60,62,64
930 :
1000 DEF PROCrelease
1010   LOCAL V%,B%
1020   FOR V%=0 TO 23
1030     B%=S%(V% DIV 3)+7*(V% MOD 3)
1040     B%?4=FNwave(V% DIV 3)
1050   NEXT
1060 ENDPROC
1070 :
1100 REM All voices retriggered in turn, fast
1110 DEF PROCshimmer(L%)
1120   LOCAL I%,V%
1130   PRINT "Shimmer"
1140   FOR I%=1 TO L%
1150     FOR V%=0 TO 23
1160       PROCvoice(V%,N%(V%),FNwave(V% DIV 3))
1170       PROCwait(4)
1180     NEXT
1190   NEXT
1200 ENDPROC
1210 :
1300 REM A run up and down, each note on the next SID
1310 DEF PROCrun
1320   LOCAL I%,V%
1330   PRINT "Run"
1340   FOR I%=0 TO 47
1350     V%=(I% MOD 8)*3+(I% DIV 8) MOD 3
1360     PROCvoice(V%,N%(ABS(23-ABS(I%-23)) MOD 24),&40)
1370     PROCwait(8)
1380   NEXT
1390   PROCwait(100)
1400 ENDPROC
