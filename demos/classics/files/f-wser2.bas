    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-wser2.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_WSER2
20 :
30 REM EXAMPLE OF WRITING TO A MIXED NUMERIC/CHARACTER DATA FILE
40 :
50 REM This program opens a data file and writes numeric and character
60 REM data to it.  The use of OPENOUT ensures that, even if the file
70 REM existed before, it is cleared before being written to.
80 :
90 REM When the file is opened a dummy length is written as the first
100 REM record and when the file is closed this is changed to the final
110 REM value of PTR.  Functions are used to open and close the file. The
120 REM closing function returns the final value of PTR (the length of the
130 REM file).
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
330 PRINT "The final byte was written at ";FN_close(stats)
340 END
350 :
360 :
370 REM Open the file and write a dummy length (0) as the first record.
380 REM Return the file number.
390 :
400 DEF FN_open(name$)
410 LOCAL fnum
420 fnum=OPENOUT(name$)
430 PRINT#fnum,0
440 =fnum
450 :
460 :
470 REM Write the length of the file to the first record and then close
480 REM the file.  Return the length of the file.
490 :
500 DEF FN_close(fnum)
510 LOCAL EOFfnum
520 EOFfnum=PTR#fnum-1
530 PTR#fnum=0
540 PRINT#fnum,EOFfnum
550 CLOSE#fnum
560 =EOFfnum
570 :
580 :
590 REM Accept a name from the keyboard and make sure it consists only
600 REM of spaces and upper or lower case characters.  Leading spaces
610 REM are automatically ignored on input.
620 :
630 DEF FN_name
640 LOCAL name$,FLAG,n
650 REPEAT
660 FLAG=TRUE
670 INPUT "Name ? " name$
680 IF name$="" THEN 740
690 FOR I=1 TO LEN(name$)
700 n=ASC(MID$(name$,I,1))
710 IF NOT(n=32 OR n>64 AND n<91 OR n>96 AND n<123) THEN FLAG=TRUE
720 NEXT
730 IF NOT FLAG THEN PRINT "No funny characters please !!!"
740 UNTIL FLAG
750 =name$
760 :
770 :
780 REM Accept the age from the keyboard and round to one place of decimals.
790 REM Ages of 0 and less or 150 or more are considered to be in error.
800 :
810 DEF FN_age
820 LOCAL age
830 REPEAT
840 INPUT "What age ? " age
850 IF age<=0 OR age >=150 THEN PRINT "No impossible ages please !!!"
860 UNTIL age>0 AND age<150
870 =INT(age*10+.5)/10
880 :
890 :
900 REM Accept the height in centimeters from the keyboard and round to
910 REM an integer. Heights of 50 or less and 230 or more are considered
920 REM to be in error.
930 :
940 DEF FN_height
950 LOCAL height
960 REPEAT
970 INPUT "Height in centimeters ? " height
980 IF height<=50 OR height>=230 THEN PRINT "Verry funny !!!"
990 UNTIL height>50 AND height<230
1000 =INT(height+.5)
1010 :
1020 :
1030 REM Accept the sex from the keyboard.  Only words beginning with upper
1040 REM or lower case M or F are acceptable.  The returned string is
1050 REM truncated to 1 character.
1060 :
1070 DEF FN_sex
1080 LOCAL sex$,FLAG
1090 REPEAT
1100 FLAG=TRUE
1110 INPUT "Male or Female - M or F ? " sex$
1120 IF sex$<>"" THEN sex$=CHR$(ASC(MID$(sex$,1,1)) AND 95)
1130 IF sex$<>"M" AND sex$<>"F" THEN FLAG=FALSE
1140 IF NOT FLAG THEN PRINT "No more sex(es) please !!!"
1150 UNTIL FLAG
1160 =sex$
