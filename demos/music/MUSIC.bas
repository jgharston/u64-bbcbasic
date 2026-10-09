10 REM MUSIC: U64 BBC BASIC music demo player
20 REM Plays .mml note files on the 24 voices of 8 SIDs
30 REM Design: docs/DESIGN_MUSICDEMO.md. Notation (one block per bar,
40 REM blank line between blocks; "v: notes" per voice):
50 REM   C D E F G A B (# + sharp, - flat), R rest, digits = length
60 REM   (1 2 4 8 16 32, . dotted), & tie to the next note, O4 octave,
70 REM   < > octave down/up, L8 default length, I5 instrument, V12 loudness
80 REM   header lines: #TITLE, #COMPOSER, #TEMPO bpm, #VOICES n
90 :
100 ON ERROR PROCerror
110 DIM V$(23),P%(23),T(23),O%(23),L(23),I%(23),A%(23),U%(23)
120 DIM R1(23,3),R2(23,3),R3%(23,3),R4%(23,3),K%(23),H%(23),N$(16)
125 REM MODE here, at the top: BASIC refuses MODE while its stack is in
126 REM use (inside a PROC or FN: Bad MODE); later screens use CLS.
127 REM MODE 100 is the C64 text screen (40 x 25).
128 MODE 100
129 PROCnames:PROCblocks
130 PROCmenu
140 END
150 :
200 DEF PROCmenu
210   LOCAL F$,N%
220   REPEAT
230     CLS
240     PROChead("U64 BBC BASIC: music","24 voices on 8 SIDs, in stereo")
280     PRINT
290     RESTORE 2000
300     FOR N%=1 TO 8
310       READ F$
320       COLOUR 6:PRINT " ";N%;" ";:COLOUR 3:PRINT FNtitle(F$)
330     NEXT
340     PRINT
350     COLOUR 6:PRINT " A ";:COLOUR 3:PRINT "all, in order"
360     COLOUR 6:PRINT " Q ";:COLOUR 3:PRINT "quit"
370     PRINT
380     PRINT " Choose: ";
390     F$=GET$
400     IF F$="A" OR F$="a" PROCall
410     IF F$>="1" AND F$<="8" PROCpiece(VAL F$)
420   UNTIL F$="Q" OR F$="q"
430   *FONT DEFAULT
435   COLOUR 128:COLOUR 7:CLS
436   REM (BASIC prints its prompt where the cursor is, as on a BBC)
440 ENDPROC
450 :
500 DEF PROCall
510   LOCAL N%
520   FOR N%=1 TO 8
530     PROCpiece(N%)
540   NEXT
550 ENDPROC
560 :
600 DEF PROCpiece(N%)
610   LOCAL F$,I%
620   RESTORE 2000
630   FOR I%=1 TO N%
640     READ F$
650   NEXT
660   F$=FNword(F$)
670   PROCplay(F$+".mml")
680 ENDPROC
690 :
700 REM The file name is the first word of a menu line, the title the rest
710 DEF FNword(A$)
720   =LEFT$(A$,INSTR(A$+" "," ")-1)
730 :
740 DEF FNtitle(A$)
750   A$=MID$(A$,INSTR(A$+" "," "))
760   REPEAT
770     IF LEFT$(A$,1)=" " A$=MID$(A$,2)
780   UNTIL LEFT$(A$,1)<>" "
790 =A$
795 :
1000 REM Play one note file
1010 DEF PROCplay(N$)
1020   LOCAL F%,L$,E,NOW,V%,NV%,TEMPO
1030   *SOUND SID
1040   *SOUND STOP
1050   F%=OPENIN(N$)
1060   IF F%=0 PRINT "No file ";N$:ENDPROC
1070   CLS:PROCframe
1080   NV%=24:TEMPO=120
1090   FOR V%=0 TO 23
1100     T(V%)=0:O%(V%)=4:L(V%)=4:I%(V%)=1:A%(V%)=0:U%(V%)=0
1110     K%(V%)=0:H%(V%)=-1:V$(V%)=""
1120     R1(V%,0)=-1:R1(V%,1)=-1:R1(V%,2)=-1:R1(V%,3)=-1
1130   NEXT
1140   W=4800/TEMPO
1150   T0%=TIME
1160   REPEAT
1170     L$=FNblock(F%)
1180     IF L$<>"" PROCheader(L$)
1190     PROCmerge
1200   UNTIL EOF#F% AND FNempty
1210   CLOSE#F%
1220   REPEAT PROCdraw:UNTIL FNquiet
1230 ENDPROC
1240 :
1300 REM Read one block: voice lines into V$(); a header line ends the
1310 REM block early and is returned (a FN cannot return from inside a
1315 REM REPEAT). Ends at a blank line or the end of the file.
1320 DEF FNblock(F%)
1330   LOCAL L$,V%,C%,H$
1340   REPEAT
1350     L$=FNline(F%)
1360     IF LEFT$(L$,1)="#" H$=L$
1370     C%=INSTR(L$,":")
1380     IF C%>0 AND LEFT$(L$,1)<>";" AND H$="" V%=VAL L$:V$(V%)=V$(V%)+MID$(L$,C%+1)+" ":U%(V%)=1
1390   UNTIL L$="" OR EOF#F% OR H$<>""
1400 =H$
1410 :
1500 DEF FNline(F%)
1510   LOCAL C%,A$
1520   IF EOF#F% THEN =""
1530   REPEAT
1540     C%=BGET#F%
1550     IF C%>=32 A$=A$+CHR$C%
1560   UNTIL C%=10 OR EOF#F%
1570 =A$
1580 :
1600 DEF PROCheader(L$)
1610   LOCAL K$,A$,V%
1620   K$=FNword(L$)
1630   A$=MID$(L$,LEN K$+2)
1640   IF K$="#TITLE" T$=A$
1650   IF K$="#COMPOSER" PROChead(T$,A$)
1660   IF K$="#TEMPO" TEMPO=VAL A$:W=4800/TEMPO
1665   IF K$="#VOICES" FOR V%=0 TO VAL A$-1:U%(V%)=1:NEXT
1670 ENDPROC
1680 :
1700 REM Give the next note to the voice furthest behind, until the
1710 REM block is done; voices that have played get rests to the end
1720 DEF PROCmerge
1730   LOCAL V%,B%,M,E
1740   REPEAT
1750     M=1E9:B%=-1
1760     FOR V%=0 TO 23
1770       IF V$(V%)<>"" IF T(V%)<M M=T(V%):B%=V%
1780     NEXT
1790     IF B%>=0 PROCahead(T(B%),B%):PROCnote(B%)
1800   UNTIL B%<0
1810   E=0
1820   FOR V%=0 TO 23
1830     IF T(V%)>E E=T(V%)
1840   NEXT
1850   FOR V%=0 TO 23
1860     IF U%(V%) AND T(V%)<E PROCsound(V%,0,0,E-T(V%),0)
1870   NEXT
1880 ENDPROC
1890 :
1900 REM Wait (and draw) until the time X is less than a second ahead
1905 REM and voice V% has room in its queue (ADVAL: 4 bytes per note), so
1907 REM SOUND never waits; no drawing when the note can go at once
1910 DEF PROCahead(X,V%)
1915   LOCAL D%
1920   REPEAT
1925     D%=X>=(TIME-T0%)/5+20 OR ADVAL(-5-V%)<4
1926     IF D% PROCdraw
1928   UNTIL NOT D%
1930 ENDPROC
1940 :
2000 DATA greenslv Greensleeves (trad.)
2010 DATA scarboro Scarborough Fair (trad.)
2020 DATA entertnr The Entertainer (Joplin)
2030 DATA nachtmus Eine kleine Nachtmusik
2040 DATA canon    Canon in D (Pachelbel)
2050 DATA toccata  Toccata in D minor (Bach)
2060 DATA odetojoy Ode to Joy (Beethoven)
2070 DATA maplelf  Maple Leaf Rag (Joplin)
2080 :
3000 REM One note (or rest) of voice V%, after any commands before it
3010 DEF PROCnote(V%)
3020   LOCAL C$,N%,D,S%,T%
3030   REPEAT
3040     C$=FNch(V%)
3050     IF C$="O" O%(V%)=FNnum(V%,4)
3060     IF C$="<" O%(V%)=O%(V%)-1
3070     IF C$=">" O%(V%)=O%(V%)+1
3080     IF C$="L" L(V%)=FNnum(V%,4)
3090     IF C$="I" I%(V%)=FNnum(V%,1):A%(V%)=0
3100     IF C$="V" A%(V%)=FNnum(V%,15)
3110     N%=INSTR("C D EF G A BR",C$)
3120   UNTIL N%>0 OR C$=""
3130   IF C$="" ENDPROC
3140   S%=0
3150   C$=MID$(V$(V%),P%(V%),1)
3160   IF C$="#" OR C$="+" S%=1:P%(V%)=P%(V%)+1
3170   IF C$="-" S%=-1:P%(V%)=P%(V%)+1
3180   D=W/FNnum(V%,L(V%))
3190   IF MID$(V$(V%),P%(V%),1)="." D=D*1.5:P%(V%)=P%(V%)+1
3200   T%=0
3210   IF MID$(V$(V%),P%(V%),1)="&" T%=&4000:P%(V%)=P%(V%)+1
3220   IF N%=13 PROCsound(V%,0,0,D,0):ENDPROC
3230   PROCsound(V%,FNamp(V%),53+4*(12*(O%(V%)-4)+N%-1+S%),D,T%)
3240 ENDPROC
3250 :
3300 REM Queue a note: time rounded so voices never drift apart
3310 DEF PROCsound(V%,A%,P%,D,F%)
3320   LOCAL D%,K%
3330   D%=INT(T(V%)+D+.5)-INT(T(V%)+.5)
3340   IF D%>0 SOUND V%+F%,A%,P%,D%
3350   K%=K%(V%):R1(V%,K%)=T(V%):R2(V%,K%)=T(V%)+D:R3%(V%,K%)=P%*-(A%<>0)
3355   R4%(V%,K%)=I%(V%)
3360   K%(V%)=(K%+1) AND 3
3370   T(V%)=T(V%)+D
3380 ENDPROC
3390 :
3400 DEF FNamp(V%)
3410   IF A%(V%) THEN =-A%(V%)
3420 =I%(V%)
3430 :
3500 REM Next non-space character of voice V%'s text ("" at the end)
3510 DEF FNch(V%)
3520   LOCAL C$
3530   REPEAT
3540     C$=MID$(V$(V%),P%(V%),1)
3550     P%(V%)=P%(V%)+1
3560   UNTIL C$<>" "
3570   IF C$="" V$(V%)="":P%(V%)=1
3580 =C$
3590 :
3600 REM A number from voice V%'s text, or D if there is none
3610 DEF FNnum(V%,D)
3620   LOCAL N%,C%
3630   C%=ASC(MID$(V$(V%),P%(V%),1)+" ")
3640   IF C%<48 OR C%>57 THEN =D
3650   REPEAT
3660     N%=N%*10+C%-48
3670     P%(V%)=P%(V%)+1
3680     C%=ASC(MID$(V$(V%),P%(V%),1)+" ")
3690   UNTIL C%<48 OR C%>57
3700 =N%
3710 :
4000 REM A bar chart: one bar per voice, as high as its pitch while a
4010 REM note sounds, in eighths of a row (characters made with VDU 23,
4015 REM as PETSCII's partial blocks). UltiSID 1's SIDs (0, 2, 4, 6) on
4017 REM the left in cyan: the left speaker; UltiSID 2's on the right.
4020 DEF PROCdraw
4030   LOCAL V%,H%,N,K%
4040   N=(TIME-T0%)/5
4050   FOR V%=0 TO 23
4060     H%=0
4070     FOR K%=0 TO 3
4080       IF R1(V%,K%)<=N AND N<R2(V%,K%) H%=R3%(V%,K%)
4090     NEXT
4100     IF H% H%=(H%+70)/2:IF H%<1 H%=1
4105     IF H%>136 H%=136
4110     IF H%<>H%(V%) PROCbar(V%,H%)
4120   NEXT
4130 ENDPROC
4140 :
4200 REM Bar of voice V%, H% eighths high (0-136: rows 2-18)
4210 DEF PROCbar(V%,H%)
4220   LOCAL X%,R%,F%
4230   X%=FNcol(V%)
4240   COLOUR 13-7*((V% DIV 3) MOD 2)
4250   F%=H% DIV 8
4260   FOR R%=0 TO 16
4270     PRINT TAB(X%,18-R%);
4280     IF R%<F% PRINT MID$(B$,8,1);
4290     IF R%=F% IF H% MOD 8 PRINT MID$(B$,H% MOD 8,1);
4300     IF R%>F% OR (R%=F% AND H% MOD 8=0) PRINT " ";
4310   NEXT
4320   H%(V%)=H%
4330 ENDPROC
4335 :
4336 REM Column of voice V%: left half SIDs 0, 2, 4, 6, right half 1, 3,
4337 REM 5, 7; three voices side by side, a space between SIDs
4338 DEF FNcol(V%)
4339   =3+((V% DIV 3) MOD 2)*18+((V% DIV 3) DIV 2)*4+V% MOD 3
4340 REM Note name of BBC pitch P% (53 = middle C, C4)
4350 DEF FNnote(P%)
4360   LOCAL S%,A$
4370   S%=(P%-53) DIV 4+48
4375   A$=MID$("C C#D D#E F F#G G#A A#B ",(S% MOD 12)*2+1,2)
4380   IF RIGHT$(A$,1)=" " A$=LEFT$(A$,1)
4385   =A$+STR$(S% DIV 12)
4390 :
4400 DEF FNempty
4410   LOCAL V%,E%
4420   E%=TRUE
4430   FOR V%=0 TO 23
4440     IF V$(V%)<>"" E%=FALSE
4450   NEXT
4460 =E%
4470 :
4500 DEF FNquiet
4510   LOCAL V%,Q%
4520   Q%=TRUE
4530   FOR V%=0 TO 23
4540     IF ADVAL(-5-V%)<15 Q%=FALSE
4550   NEXT
4560 =Q%
4570 :
4600 DEF PROCerror
4610   *SOUND STOP
4615   *FONT DEFAULT
4620   CLS
4630   REPORT:PRINT " at line ";ERL
4640   END
4650 ENDPROC
4660 :
4900 REM The default instruments' names (1-16)
4910 DEF PROCnames
4920   LOCAL I%
4930   RESTORE 4970
4940   FOR I%=1 TO 16:READ N$(I%):NEXT
4950   N$(0)=N$(16)
4960 ENDPROC
4970 DATA SQUARE,PIANO,ORGAN,STRINGS,BRASS,LEAD,BASS,FLUTE
4980 DATA PLUCK,BELL,KICK,SNARE,HIHAT,PAD,ARP,SYNC
4990 :
5000 REM Eight characters as PETSCII's bottom blocks, 1/8 to 8/8 high
5010 REM (6 pixels wide: a gap between bars); B$ holds them in order
5020 DEF PROCblocks
5030   LOCAL K%,R%,C%
5040   B$=""
5050   RESTORE 5120
5060   FOR K%=1 TO 8
5070     READ C%
5080     B$=B$+CHR$C%
5090     VDU 23,C%:FOR R%=1 TO 8:VDU -(R%>8-K%)*&7E:NEXT
5100   NEXT
5110 ENDPROC
5120 DATA 96,92,94,95,123,124,125,126
5130 :
5200 REM The chart's frame: title row, SID numbers, the stereo sides
5210 DEF PROCframe
5220   LOCAL S%
5230   FOR S%=0 TO 7
5240     COLOUR 13-7*(S% MOD 2)
5250     PRINT TAB(FNcol(S%*3)+1,19);S%;
5260   NEXT
5270   COLOUR 13:PRINT TAB(3,21);"UltiSID 1: left";
5280   COLOUR 6:PRINT TAB(21,21);"UltiSID 2: right";
5290   COLOUR 3:PRINT TAB(3,23);"24 voices on 8 SIDs";
5300 ENDPROC
5310 :
5400 REM Header as in the author's other programs: a dark green bar with
5410 REM the title, a light green one under it (COLOUR 128+n: text on a
5420 REM coloured bar), then yellow text
5430 DEF PROChead(A$,B$)
5440   PRINT TAB(0,0);
5450   COLOUR 130:PRINT LEFT$(" "+A$+STRING$(40," "),40);
5460   COLOUR 141:PRINT LEFT$(" "+B$+STRING$(40," "),40);
5470   COLOUR 128:COLOUR 3
5480 ENDPROC
