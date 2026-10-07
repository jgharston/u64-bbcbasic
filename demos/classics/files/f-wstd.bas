    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-wstd.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_WSTD
20 :
30 REM EXAMPLE OF WRITING A COMPATIBLE DATA FILE
40 :
50 REM This program opens a data file and writes numeric and character
60 REM data to it in a compatible format.  Numerics are changed to
70 REM strings before they are written and the data items are
80 REM separated by commas.  Each record is terminated by CR LF
90 REM and the file is terminated by a Control Z.
100 :
110 :
120 REM Functions are used to accept and validate the data before
130 REM writing it to the file.
140 :
150 :
160 record$=STRING$(100," "): REM Reserve room for the longest
170 name$=STRING$(20," ")     REM record necessary.  It saves
180 :                         REM on string space.
190 compat=OPENOUT("COMPAT")
200 PRINT "File Name COMPAT Opened as Channel ";compat
210 PRINT
220 REPEAT
230 name$=FN_name
240 IF name$="" THEN PROC_end
250 age=FN_age
260 height=FN_height
270 sex$=FN_sex
280 PRINT
290 record$=name$+","+STR$(age)+","+STR$(height)+","+sex$
300 PRINT#compat,record$
310 BPUT#compat,&0A
320 UNTIL FALSE
330 :
340 DEF PROC_end
350 BPUT#compat,&1A
360 CLOSE#compat
370 END
380 :
390 :
400 REM Accept a name from the keyboard and make sure it consists only
410 REM of spaces and upper or lower case characters.  Leading spaces
420 REM are automatically ignored on input.
430 :
440 DEF FN_name
450 LOCAL name$,FLAG,n
460 REPEAT
470 FLAG=TRUE
480 INPUT "Name ? " name$
490 IF name$="" THEN 550
500 FOR I=1 TO LEN(name$)
510 n=ASC(MID$(name$,I,1))
520 IF NOT(n=32 OR n>64 AND n<91 OR n>96 AND n<123) THEN FLAG=TRUE
530 NEXT
540 IF NOT FLAG THEN PRINT "No funny characters please !!!"
550 UNTIL FLAG
560 =name$
570 :
580 :
590 REM Accept the age from the keyboard and round to one place of decimals.
600 REM Ages of 0 and less or 150 or more are considered to be in error.
610 :
620 DEF FN_age
630 LOCAL age
640 REPEAT
650 INPUT "What age ? " age
660 IF age<=0 OR age >=150 THEN PRINT "No impossible ages please !!!"
670 UNTIL age>0 AND age<150
680 =INT(age*10+.5)/10
690 :
700 :
710 REM Accept the height in centimeters from the keyboard and round to
720 REM an integer. Heights of 50 or less and 230 or more are considered
730 REM to be in error.
740 :
750 DEF FN_height
760 LOCAL height
770 REPEAT
780 INPUT "Height in centimeters ? " height
790 IF height<=50 OR height>=230 THEN PRINT "Verry funny !!!"
800 UNTIL height>50 AND height<230
810 =INT(height+.5)
820 :
830 :
840 REM Accept the sex from the keyboard.  Only words beginning with upper
850 REM or lower case M or F are acceptable.  The returned string is
860 REM truncated to 1 character.
870 :
880 DEF FN_sex
890 LOCAL sex$,FLAG
900 REPEAT
910 FLAG=TRUE
920 INPUT "Male or Female - M or F ? " sex$
930 IF sex$<>"" THEN sex$=CHR$(ASC(MID$(sex$,1,1)) AND 95)
940 IF sex$<>"M" AND sex$<>"F" THEN FLAG=FALSE
950 IF NOT FLAG THEN PRINT "No more sex(es) please !!!"
960 UNTIL FLAG
970 =sex$
