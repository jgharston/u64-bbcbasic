    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-weser2.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_WESER2
20 :
30 REM EXAMPLE OF WRITING AT THE END OF A SERIAL MIXED NUMERIC/CHARACTER
40 REM DATA FILE
50 :
60 REM This program opens a data file, sets PTR to its end and then writes
70 REM numeric and character data  to it.
80 :
90 REM If the file is being opened for the first time, a dummy length is
100 REM written as the first record.  When the file is closed the first
110 REM record is changed to the value of PTR.  Functions are used to
120 REM open and close the file.  The closing function returns the final
130 REM value of PTR (the length of the file).
140 :
150 REM Functions are also used to accept and validate the data before
160 REM writing it to the file.
170 :
180 :
190 stats=FN_open("STATS")
200 PRINT "File Name STATS Opened as Channel ";stats
210 PRINT
220 REPEAT
230 name$=FN_name
240 IF name$="" THEN PROC_end
250 age=FN_age
260 height=FN_height
270 sex$=FN_sex
280 PRINT
290 PRINT#stats,name$,age,height,sex$
300 UNTIL FALSE
310 :
320 DEF PROC_end
330 PRINT "The last byte was written at ";FN_close(stats)
340 END
350 :
360 :
370 REM Open the file and, if it exists, set PTR to the end and return
380 REM the file number.  If it does not exist, open it, write a dummy
390 REM length as the first record and return the file number.
400 :
410 DEF FN_open(name$)
420 LOCAL fnum,ptr
430 fnum=OPENUP(name$)
440 IF fnum>0 THEN INPUT#fnum,EOFfnum:PTR#fnum=EOFfnum: =fnum
450 fnum=OPENOUT(name$)
460 PRINT#fnum,0
470 =fnum
480 :
490 :
500 REM Write the length of the file to the first record and then close
510 REM the file.  Return the length of the file.
520 :
530 DEF FN_close(fnum)
540 LOCAL EOFfnum
550 EOFfnum=PTR#fnum-1
560 PTR#fnum=0
570 PRINT#fnum,EOFfnum
580 CLOSE#fnum
590 =EOFfnum
600 :
610 :
620 REM Accept a name from the keyboard and make sure it consists only
630 REM of spaces and upper or lower case characters.  Leading spaces
640 REM are automatically ignored on input.
650 :
660 DEF FN_name
670 LOCAL name$,FLAG,n
680 REPEAT
690 FLAG=TRUE
700 INPUT "Name ? " name$
710 IF name$="" THEN 770
720 FOR I=1 TO LEN(name$)
730 n=ASC(MID$(name$,I,1))
740 IF NOT(n=32 OR n>64 AND n<91 OR n>96 AND n<123) THEN FLAG=TRUE
750 NEXT
760 IF NOT FLAG THEN PRINT "No funny characters please !!!"
770 UNTIL FLAG
780 =name$
790 :
800 :
810 REM Accept the age from the keyboard and round to one place of decimals.
820 REM Ages of 0 and less or 150 or more are considered to be in error.
830 :
840 DEF FN_age
850 LOCAL age
860 REPEAT
870 INPUT "What age ? " age
880 IF age<=0 OR age >=150 THEN PRINT "No impossible ages please !!!"
890 UNTIL age>0 AND age<150
900 =INT(age*10+.5)/10
910 :
920 :
930 REM Accept the height in centimeters from the keyboard and round to
940 REM an integer. Heights of 50 or less and 230 or more are considered
950 REM to be in error.
960 :
970 DEF FN_height
980 LOCAL height
990 REPEAT
1000 INPUT "Height in centimeters ? " height
1010 IF height<=50 OR height>=230 THEN PRINT "Verry funny !!!"
1020 UNTIL height>50 AND height<230
1030 =INT(height+.5)
1040 :
1050 :
1060 REM Accept the sex from the keyboard.  Only words beginning with upper
1070 REM or lower case M or F are acceptable.  The returned string is
1080 REM truncated to 1 character.
1090 :
1100 DEF FN_sex
1110 LOCAL sex$,FLAG
1120 REPEAT
1130 FLAG=TRUE
1140 INPUT "Male or Female - M or F ? " sex$
1150 IF sex$<>"" THEN sex$=CHR$(ASC(MID$(sex$,1,1)) AND 95)
1160 IF sex$<>"M" AND sex$<>"F" THEN FLAG=FALSE
1170 IF NOT FLAG THEN PRINT "No more sex(es) please !!!"
1180 UNTIL FLAG
1190 =sex$
