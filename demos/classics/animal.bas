    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/animal.bbc, with its
    3 REM ANIMAL.DAT), (C) 1984-2000 R.T. Russell, zlib licence (see LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 CLS:@%=10:WIDTH 0:PRINT TAB(15)"ANIMAL"
20 PRINT "Creative Computing Morristown New Jersey"''
30 REM by Nathan Teichholtz & Steve North
40 REM from an original idea by Arthur Luehrmann.
50 REM Modified by Chris Atkinson and Richard Russell.
60 :
70 ON ERROR IF ERR=17 THEN 830 ELSE PRINT:REPORT:PRINT" at line ";ERL:END
80 MAX=(HIMEM-TOP)/40
90 DIM A$(MAX)
100 PRINT "Play 'Guess the Animal'"
110 :
120 X=OPENIN("ANIMAL.DAT")
130 IF X<>0 PROCread ELSE FOR I=0 TO 3:READ A$(I):NEXT I
140 N=VAL(A$(0))
150 :
160 REM ***
170 REM MAIN CONTROL SECTION
180 REM ***
190 REPEAT
200 IF FNquery("Are you thinking of an animal ")="N" THEN 830
210 K=1
220 REPEAT
230 PROCquestion
240 UNTIL LEFT$(A$(K),2)<>"\Q"
250 A$=FNquery("Is it "+FNart(MID$(A$(K),3)))
260 IF A$="Y" THEN PRINT "Why not try another one?"'' ELSE PROCnew
270 UNTIL FALSE
280 ;
290 REM ***
300 REM NEW ANIMAL
310 REM ***
320 DEF PROCnew
330 INPUT "OK, I give up."'"Tell me what animal you were thinking"'"of ",V$
340 V$=FNstrip(FNconvlc(V$))
350 PRINT "Please tell me a question that would"'"distinguish ";
360 PRINT FNart(V$);" from ";FNart(MID$(A$(K),3))
370 INPUT X$:X$=FNcapital(X$)
380 IF RIGHT$(X$,1)="?" THEN X$=LEFT$(X$,LEN(X$)-1)
390 A$=FNquery("For "+FNart(V$)+" the answer would be ")
400 IF A$="Y" THEN B$="N"
410 IF A$="N" THEN B$="Y"
420 Z1=VAL(A$(0))
430 A$(0)=STR$(Z1+2)
440 A$(Z1)=A$(K)
450 A$(Z1+1)="\A"+V$
460 A$(K)="\Q"+X$+"\"+A$+STR$(Z1+1)+"\"+B$+STR$(Z1)+"\"
470 ENDPROC
480 ;
490 REM ***
500 REM PRINT QUESTIONS
510 REM ***
520 DEF PROCquestion
530 Q$=A$(K)
540 C$=FNquery(MID$(Q$,3,INSTR(Q$,"\",3)-3))
550 T$="\"+C$
560 X=INSTR(Q$,T$,3)
570 Y=INSTR(Q$,"\",X+1)
580 K=VAL(MID$(Q$,X+2,Y-X-2))
590 ENDPROC
600 ;
610 REM ***
620 REM READ DATA FILE
630 REM ***
640 DEF PROCread
650 PRINT "Just let me refresh my memory"
660 Z=0
670 REPEAT INPUT #X,A$(Z):Z=Z+1
680 UNTIL EOF#X OR Z=MAX+1 OR A$(Z-1)=""
690 CLOSE #X
700 ENDPROC
710 ;
720 REM ***
730 REM PRINT NAME OF ANIMAL
740 REM ***
750 DEF PROCprint
760 PRINT TAB(10*X);MID$(A$(I),3);
770 X=(X+1) MOD 4
780 ENDPROC
790 ;
800 REM ***
810 REM LIST CONTENTS
820 REM ***
830 ON ERROR OFF
840 PRINT ' "Animals I already know are:"
850 X=0:I=0
860 REPEAT I=I+1
870 IF LEFT$(A$(I),2)="\A" THEN PROCprint
880 UNTIL A$(I)="" OR I=MAX
890 PRINT ' "Room for ";INT((MAX-I)/3);" more."
900 IF FNquery("Do you want to save these on disk")<>"Y" THEN END
910 :
920 REM ***
930 REM DUMP FILE IF REQUESTED
940 REM ***
950 IF OPENIN"ANIMAL.DAT" THEN *ERA ANIMAL.DAT
960 X=OPENOUT"ANIMAL.DAT":Z=0:IF X=0 PRINT "Directory full":END
970 REPEAT PRINT# X,A$(Z):Z=Z+1
980 UNTIL A$(Z)="" OR Z=MAX+1
990 CLOSE# 0
1000 END
1010 ;
1020 DATA 4,\QDoes it fly\N2\Y3\,\Agoldfish,\Asparrow,
1030 ;
1040 REM. NOW THE FUNCTIONS
1050 ;
1060 DEF FNart(noun$):REM Indefinite article appender
1070 IF INSTR("AEIOUaeiou",LEFT$(noun$,1)) THEN ="an "+noun$ ELSE ="a "+noun$
1080 ;
1090 DEF FNstrip(name$):REM Article stripper
1100 name$=FNnospace(name$)
1110 LOCAL AT$,Z
1120 RESTORE 1170
1130 REPEAT Z=Z+1:READ AT$
1140 UNTIL AT$=LEFT$(name$,LEN(AT$)) OR Z=10
1150 IF Z<10 THEN name$=MID$(name$,1+LEN(AT$))
1160 =FNnospace(name$)
1170 DATA A ,AN ,THE ,a ,an ,the ,An ,The ,THe ,,
1180 ;
1190 DEF FNnospace(name$)
1200 name$=" "+name$
1210 REPEAT name$=MID$(name$,2)
1220 UNTIL LEFT$(name$,1)<>" "
1230 =name$
1240 ;
1250 DEF FNconvlc(name$)
1260 LOCAL L%,A%,B$
1270 FOR L%=1 TO LEN(name$)
1280 A%=ASC(MID$(name$,L%))
1290 IF A%<97 AND A%>64 THEN A%=A%+32
1300 B$=B$+CHR$(A%):NEXT L%
1310 =B$
1320 ;
1330 DEF FNcapital(name$)
1340 LOCAL A$
1350 name$=FNnospace(FNconvlc(name$))
1360 IF ASC(name$)<97 THEN =name$
1370 A$=CHR$(ASC(name$)-32)
1380 A$=A$+MID$(name$,2)
1390 =A$
1400 ;
1410 DEF FNquery(prompt$)
1420 LOCAL A$
1430 REPEAT
1440 PRINT prompt$;:INPUT A$:A$=LEFT$(FNcapital(A$),1)
1450 UNTIL A$="Y" OR A$="N"
1460 =A$
