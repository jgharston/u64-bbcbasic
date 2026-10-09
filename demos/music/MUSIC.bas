10 REM MUSIC: U64 BBC BASIC music demo
20 REM Builds each piece as a song with SOUND (*SONG RECORD), then plays
30 REM it in the background on 24 voices of 8 SIDs (*SONG PLAY) and
40 REM shows the voices from ADVAL(-29-v). Design: docs/DESIGN_MUSICDEMO.md.
50 REM Note files (.mml, one block per bar, blank line between blocks;
60 REM "v: notes" per voice):
70 REM   C D E F G A B (# + sharp, - flat), R rest, digits = length
80 REM   (1 2 4 8 16 32, . dotted), & tie to the next note, O4 octave,
90 REM   < > octave down/up, L8 default length, I5 instrument, V12 loudness
95 REM   header lines: #TITLE, #COMPOSER, #TEMPO bpm, #VOICES n,
97 REM   #INSTRUMENT n parts (as *INSTRUMENT)
100 ON ERROR PROCerror
110 DIM V$(23),P%(23),T%(23),O%(23),L%(23),I%(23),A%(23),U%(23),H%(23),K%(23)
120 REM MODE here, at the top: BASIC refuses MODE while its stack is in
125 REM use (inside a PROC or FN: Bad MODE); later screens use CLS.
127 REM MODE 100 is the C64 text screen (40 x 25).
128 MODE 100
129 PROCblocks
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
530     IF NOT Q% PROCpiece(N%)
540   NEXT
545   Q%=FALSE
550 ENDPROC
560 :
600 DEF PROCpiece(N%)
610   LOCAL F$,I%
620   RESTORE 2000
630   FOR I%=1 TO N%
640     READ F$
650   NEXT
660   F$=FNword(F$)
670   PROCbuild(F$+".mml")
680   PROCplay
690 ENDPROC
695 :
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
1000 REM Build the song from a note file: header lines set it up, every
1005 REM note becomes a SOUND that *SONG RECORD writes into the song; a
1007 REM duration is in rows (8 rows per beat: 32 for a whole note)
1010 DEF PROCbuild(N$)
1020   LOCAL F%,L$,V%,B%
1030   *SOUND SID
1040   *SOUND STOP
1050   F%=OPENIN(N$)
1060   IF F%=0 PRINT "No file ";N$:ENDPROC
1070   CLS:PROCframe
1080   TEMPO=120:E%=0
1090   FOR V%=0 TO 23
1100     T%(V%)=0:O%(V%)=4:L%(V%)=4:I%(V%)=1:A%(V%)=0:U%(V%)=0
1110     H%(V%)=-1:V$(V%)="":P%(V%)=1:K%(V%)=FALSE
1120   NEXT
1130   REPEAT
1140     L$=FNblock(F%)
1150     IF L$<>"" PROCheader(L$)
1160     PROCmerge
1165     B%=B%+1
1170     COLOUR 3:PRINT TAB(3,23);"Building the song: bar ";B%;"   ";
1180   UNTIL EOF#F% AND FNempty
1190   CLOSE#F%
1200   *SONG RECORD OFF
1210 ENDPROC
1220 :
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
1600 REM Header lines: #TEMPO starts a new song (title from #TITLE)
1610 DEF PROCheader(L$)
1620   LOCAL K$,A$,V%
1630   K$=FNword(L$)
1640   A$=MID$(L$,LEN K$+2)
1650   IF K$="#TITLE" T$=A$
1660   IF K$="#COMPOSER" PROChead(T$,A$)
1670   IF K$="#TEMPO" TEMPO=VAL A$:PROCnew
1680   IF K$="#VOICES" FOR V%=0 TO VAL A$-1:U%(V%)=1:NEXT
1690   IF K$="#INSTRUMENT" OSCLI "INSTRUMENT "+A$:PROCshow("*INSTRUMENT "+A$)
1700 ENDPROC
1710 :
1720 DEF PROCnew
1730   OSCLI "SONG NEW "+STR$TEMPO+" 8"
1740   OSCLI "SONG TITLE "+T$
1750   *SONG RECORD
1760   PROCshow("*SONG NEW "+STR$TEMPO+" 8: *SONG RECORD")
1770 ENDPROC
1780 :
1800 REM All notes of the block, voice by voice (each voice has its own
1810 REM place in the song); voices that have played get rests to the end
1820 DEF PROCmerge
1830   LOCAL V%,E
1840   FOR V%=0 TO 23
1850     IF V$(V%)<>"" PROCvoice(V%)
1860   NEXT
1870   FOR V%=0 TO 23
1880     IF T%(V%)>E% E%=T%(V%)
1890   NEXT
1900   FOR V%=0 TO 23
1910     IF U%(V%) AND T%(V%)<E% PROCsound(V%,0,0,E%-T%(V%),0)
1920   NEXT
1930 ENDPROC
1940 :
1950 DEF PROCvoice(V%)
1960   REPEAT
1970     PROCnote(V%)
1980   UNTIL V$(V%)=""
1990 ENDPROC
1995 :
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
3020   LOCAL C$,N%,D%,S%,T%
3030   REPEAT
3040     C$=FNch(V%)
3050     IF C$="O" O%(V%)=FNnum(V%,4)
3060     IF C$="<" O%(V%)=O%(V%)-1
3070     IF C$=">" O%(V%)=O%(V%)+1
3080     IF C$="L" L%(V%)=FNnum(V%,4)
3090     IF C$="I" I%(V%)=FNnum(V%,1):A%(V%)=0
3100     IF C$="V" A%(V%)=FNnum(V%,15)
3110     N%=INSTR("C D EF G A BR",C$)
3120   UNTIL N%>0 OR C$=""
3130   IF C$="" ENDPROC
3140   S%=0
3150   C$=MID$(V$(V%),P%(V%),1)
3160   IF C$="#" OR C$="+" S%=1:P%(V%)=P%(V%)+1
3170   IF C$="-" S%=-1:P%(V%)=P%(V%)+1
3180   D%=32 DIV FNnum(V%,L%(V%))
3190   IF MID$(V$(V%),P%(V%),1)="." D%=D%*3 DIV 2:P%(V%)=P%(V%)+1
3200   T%=K%(V%):K%(V%)=FALSE
3210   IF MID$(V$(V%),P%(V%),1)="&" P%(V%)=P%(V%)+1:K%(V%)=TRUE
3220   IF N%=13 PROCsound(V%,0,0,D%,0):ENDPROC
3230   PROCsound(V%,FNamp(V%),53+4*(12*(O%(V%)-4)+N%-1+S%),D%,T%)
3240 ENDPROC
3250 :
3300 REM One SOUND: with *SONG RECORD it goes into the song at the voice's
3310 REM place, D% rows long (&4000: tied to the note before it)
3320 DEF PROCsound(V%,A%,P%,D%,F%)
3330   IF D%<1 ENDPROC
3340   SOUND V%-(F%<>0)*&4000,A%,P%,D%
3350   T%(V%)=T%(V%)+D%
3360   IF RND(16)=1 PROCshow("SOUND "+STR$V%+","+STR$A%+","+STR$P%+","+STR$D%)
3370 ENDPROC
3380 :
3390 REM Amplitude in SID mode: instrument + 256 * level (V1-V15)
3400 DEF FNamp(V%)
3410   IF A%(V%) THEN =I%(V%)+256*A%(V%)
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
3600 REM A number from voice V%'s text, or D% if there is none
3610 DEF FNnum(V%,D%)
3620   LOCAL N%,C%
3630   C%=ASC(MID$(V$(V%),P%(V%),1)+" ")
3640   IF C%<48 OR C%>57 THEN =D%
3650   REPEAT
3660     N%=N%*10+C%-48
3670     P%(V%)=P%(V%)+1
3680     C%=ASC(MID$(V$(V%),P%(V%),1)+" ")
3690   UNTIL C%<48 OR C%>57
3700 =N%
3710 :
3800 REM Play the song: *SONG PLAY, then draw the voices until it ends
3810 REM (E% rows of 6000/(TEMPO*8) centiseconds) or a key is pressed
3820 DEF PROCplay
3830   LOCAL T0%,D%,K%
3840   *SONG PLAY
3850   PROCshow("*SONG PLAY")
3860   COLOUR 3:PRINT TAB(3,23);"Playing: any key stops, Q quits   ";
3870   T0%=TIME:D%=E%*6000/(TEMPO*8)+60:K%=-1
3880   REPEAT
3890     PROCdraw
3900     K%=INKEY(0)
3910   UNTIL TIME-T0%>D% OR K%>=0
3920   *SONG STOP
3930   IF K%=ASC"Q" OR K%=ASC"q" Q%=TRUE
3940 ENDPROC
3950 :
4000 REM A bar chart: one bar per voice, as high as the note it plays
4010 REM (ADVAL(-29-v): the song's note, 49 = middle C), in eighths of a
4015 REM row (characters made with VDU 23, as PETSCII's partial blocks).
4017 REM UltiSID 1's SIDs (0, 2, 4, 6) on the left in cyan: the left
4018 REM speaker; UltiSID 2's on the right.
4020 DEF PROCdraw
4030   LOCAL V%,H%
4050   FOR V%=0 TO 23
4060     H%=ADVAL(-29-V%)
4100     IF H% H%=(H%-16)*2:IF H%<1 H%=1
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
4340 :
4400 DEF FNempty
4410   LOCAL V%,E%
4420   E%=TRUE
4430   FOR V%=0 TO 23
4440     IF V$(V%)<>"" E%=FALSE
4450   NEXT
4460 =E%
4470 :
4600 DEF PROCerror
4610   *SOUND STOP
4612   *SONG RECORD OFF
4615   *FONT DEFAULT
4620   CLS
4630   REPORT:PRINT " at line ";ERL
4640   END
4650 ENDPROC
4660 :
4800 REM The command just given, on the line under the chart
4810 DEF PROCshow(A$)
4820   COLOUR 6:PRINT TAB(0,20);LEFT$(" "+A$+STRING$(39," "),39);
4830 ENDPROC
4840 :
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
5200 REM The chart's frame: SID numbers, the stereo sides
5210 DEF PROCframe
5220   LOCAL S%
5230   FOR S%=0 TO 7
5240     COLOUR 13-7*(S% MOD 2)
5250     PRINT TAB(FNcol(S%*3)+1,19);S%;
5260   NEXT
5270   COLOUR 13:PRINT TAB(3,21);"UltiSID 1: left";
5280   COLOUR 6:PRINT TAB(21,21);"UltiSID 2: right";
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
