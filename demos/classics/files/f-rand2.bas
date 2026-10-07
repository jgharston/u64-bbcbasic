    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-rand2.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_RAND2
20 :
30 REM Written by Doug Mounter - Jan 82
40 :
50 REM EXAMPLE OF A RANDOM ACCESS FILE
60 :
70 REM This is a simple inventory program.  It uses the
80 REM item's part number as the key and stores:
90 REM   The item description  - character max length 30
100 REM   The quantity in stock - numeric
110 REM   The re-order level    - numeric
120 REM   The unit price        - numeric
130 REM In addition, the first byte of the record is used
140 REM as a valid data flag.  Set to 0 if empty, D if the
150 REM record has been deleted or V if the record is
160 REM valid.
170 REM This gives a MAX record length of 47 bytes
180 REM (Don't forget the CR after the string)
190 :
200 :
210 PROC_initialise
220 inventry=FN_open("B:INVENTRY")
230 REPEAT
240 CLS
250 PRINT TAB(5,3);"If you want to:-"'
260 PRINT TAB(10);"End This Session";TAB(55);"Type 0"
270 PRINT TAB(10);"Amend or Create an Entry";TAB(55);"Type 1"
280 PRINT TAB(10);"Display the Inventory for One Part";TAB(55);"Type 2"
290 PRINT TAB(10);"Change the Stock Level of One Part";TAB(55);"Type 3"
300 PRINT TAB(10);"Display All Items Below Reorder Level";TAB(55);"Type 4"
310 PRINT TAB(10);"Recover a Previously Deleted Item";TAB(55);"Type 5"
320 PRINT TAB(10);"List Deleted Items";TAB(55);"Type 6"
330 PRINT TAB(10);"Set Up a New Inventory";TAB(55);"Type 9"
340 REPEAT
350 PRINT TAB(5,15);bell$;
360 PRINT "Please enter the appropriate number (0 to 6 or 9) ";
370 function$=GET$
380 UNTIL function$>"/" AND function$<"8" OR function$="9"
390 function=VAL(function$)
400 ON function GOSUB 500,670,810,1100,1350,1540,1770,1790,1840 ELSE
410 UNTIL function=0
420 CLS
430 PRINT "Inventory File Closed" ''
440 CLOSE#inventry
450 END
460 :
470 :
480 REM AMEND/CREATE AN ENTRY
490 :
500 REPEAT
510 CLS
520 PRINT "AMEND/CREATE"
530 partno=FN_getpartno
540 flag=FN_getrec(partno,ASC"V")
550 PROC_display(flag)
560 PRINT'"Do you wish to ";
570 IF flag PRINT "change this entry ? "; ELSE PRINT "enter data ? ";
580 IF GET$<>"N" flag=FN_amend(partno):PRINT cteos$
590 PROC_write(partno,flag,type)
600 PRINT bell$;"Do you wish to amend/create another record ? ";
610 UNTIL GET$="N"
620 RETURN
630 :
640 :
650 REM DISPLAY AN ENTRY
660 :
670 REPEAT
680 CLS
690 PRINT "DISPLAY"
700 partno=FN_getpartno
710 flag=FN_getrec(partno,ASC"V")
720 PROC_display(flag)
730 PRINT '
740 PRINT "Do you wish to view another record ? ";
750 UNTIL GET$="N"
760 RETURN
770 :
780 :
790 REM CHANGE THE STOCK LEVEL FOR ONE PART
800 :
810 REPEAT
820 CLS
830 PRINT "CHANGE STOCK"
840 partno=FN_getpartno
850 flag=FN_getrec(partno,ASC"V")
860 REPEAT
870 PROC_display(flag)
880 PRINT cteos$;
890 REPEAT
900 PRINT TAB(0,12);cteol$;
910 INPUT "What is the stock change ? " temp$
920 change=VAL(temp$)
930 UNTIL INT(change)=change AND stock+change>=0
940 IF temp$="" flag=FALSE:GOTO 1000
950 stock=stock+change
960 PROC_display(flag)
970 PRINT'"Is this correct ? ";
980 temp$=GET$
990 :
1000 UNTIL NOT flag OR temp$="Y"
1010 PROC_write(partno,flag,ASC"V")
1020 PRINT return$;bell$;
1030 PRINT "Do you want to update any more stock levels ? ";
1040 UNTIL GET$="N"
1050 RETURN
1060 :
1070 :
1080 REM DISPLAY ITEMS BELOW REORDER LEVEL
1090 :
1100 partno=1
1110 REPEAT
1120 CLS
1130 PRINT "ITEMS BELOW REORDER LEVEL"'
1140 line_count=2
1150 REPEAT
1160 flag=FN_getrec(partno,ASC"V")
1170 IF NOT (flag AND stock<reord) THEN 1230
1180 PRINT "Part Number ";partno
1190 PRINT desc$;"  Stock ";stock;"  Reorder Level ";reord
1200 PRINT
1210 line_count=line_count+3
1220 :
1230 partno=partno+1
1240 temp$=INKEY$(0)
1250 UNTIL partno>maxpartno OR line_count>20 OR temp$<>""
1260 PRINT TAB(0,23);bell$;"Push any key to continue or E to end ";
1270 temp$=GET$
1280 UNTIL partno>maxpartno OR temp$="E"
1290 partno=0
1300 RETURN
1310 :
1320 :
1330 REM RECOVER A DELETED ENTRY
1340 :
1350 REPEAT
1360 CLS
1370 PRINT "RECOVER DELETED RECORDS"
1380 partno=FN_getpartno
1390 flag=FN_getrec(partno,ASC"D")
1400 PROC_display(flag)
1410 PRINT
1420 IF NOT flag THEN 1470
1430 PRINT "If you wish to recover this entry type Y ";
1440 temp$=GET$
1450 IF temp$="Y" PROC_write(partno,flag,ASC"V")
1460 :
1470 PRINT return$;bell$;"Do you wish to recover another record ? ";
1480 UNTIL GET$="N"
1490 RETURN
1500 :
1510 :
1520 REM LIST DELETED ENTRIES
1530 :
1540 partno=1
1550 REPEAT
1560 CLS
1570 PRINT "DELETED ITEMS"'
1580 line_count=2
1590 REPEAT
1600 flag=FN_getrec(partno,ASC"D")
1610 IF NOT flag THEN 1660
1620 PRINT "Part Number ";partno
1630 PRINT "Description ";desc$'
1640 line_count=line_count+3
1650 :
1660 partno=partno+1
1670 temp$=INKEY$(0)
1680 UNTIL partno>maxpartno OR line_count>20 OR temp$<>""
1690 PRINT TAB(0,23);bell$;"Push any key to continue or E to end ";
1700 UNTIL partno>maxpartno OR GET$="E"
1710 partno=0
1720 RETURN
1730 :
1740 :
1750 REM DUMMMY RETURNES FOR INVALID FUNCTION NUMBERS
1760 :
1770 RETURN
1780 :
1790 RETURN
1800 :
1810 :
1820 REM REINITIALISE THE INVENTORY DATA FILE
1830 :
1840 CLS
1850 PRINT TAB(0,3);bell$;"Are you sure you want to set up a new inventory?"
1860 PRINT "You will DESTROY ALL THE DATA YOU HAVE ACCUMULATED so far."
1870 PRINT '"It would be safer to use a new disk in drive B and start a new"
1880 PRINT "inventory file."'
1890 PRINT "If you are SURE you want to do it, enter YES"
1900 PRINT "If you want to start a new inventory file, enter NEW"
1910 INPUT "Otherwise, just hit return ",temp$
1920 IF temp$="YES" PROC_setup(inventry)
1930 IF temp$="NEW" function=0
1940 RETURN
1950 :
1960 :
1970 REM INITIALISE ALL THE VARIOUS PRESETS ETC
1980 :
1990 DEF PROC_initialise
2000 bell$=CHR$(7)
2010 return$=CHR$(13)
2020 cteol$=CHR$(5)
2030 cteos$=CHR$(4)
2040 clrline$=return$+cteol$
2050 rec_length=47
2060 partno=0
2070 desc$=STRING$(30," ")
2080 temp$=STRING$(40," ")
2090 WIDTH 0
2100 ENDPROC
2110 :
2120 :
2130 REM OPEN THE FILE AND RETURN THE FILE NUMBER
2140 :
2150 REM If the file already exists, the largest permitted
2160 REM part number is read into maxpartno.
2170 REM If it is a new file, file initialisation is carried
2180 REM out and the largest permitted part number is
2190 REM written as the first record.
2200 :
2210 DEF FN_open(name$)
2220 fnum=OPENUP(name$)
2230 IF fnum>0 INPUT#fnum,maxpartno: =fnum
2240 fnum=OPENOUT(name$)
2250 IF fnum=0 PRINT "Disk Directory Full."!!:END
2260 CLS
2270 PROC_setup(fnum)
2280 =fnum
2290 :
2300 REM SET UP THE FILE
2310 :
2320 REM Ask for the maximum part number required, write
2330 REM it as the first record and then write 0 in to
2340 REM the first byte of every record.
2350 :
2360 DEF PROC_setup(fnum)
2370 REPEAT
2380 PRINT TAB(0,12);cteos$;bell$;
2390 INPUT "What is the highest part number required (Max 5000) ",maxpartno
2400 UNTIL maxpartno>0 AND maxpartno<5000 AND INT(maxpartno)=maxpartno
2410 PTR#fnum=0
2420 PRINT#fnum,maxpartno
2430 FOR partno=1 TO maxpartno
2440 PTR#fnum=FN_ptr(partno)
2450 BPUT#fnum,0
2460 NEXT
2470 partno=0
2480 ENDPROC
2490 :
2500 :
2510 REM GET AND RETURN THE REQUIRED PART NUMBER
2520 :
2530 DEF FN_getpartno
2540 REPEAT
2550 PRINT TAB(0,5);cteos$;bell$;
2560 PRINT "Enter a Part Number Between 1 and ";maxpartno '
2570 IF partno=maxpartno THEN 2610
2580 PRINT "The Next Part Number is ";partno+1;
2590 PRINT "  Just hit RETURN to get this"'
2600 :
2610 INPUT "What is the Part Number You Want ",partno$
2620 IF partno$<>"" partno=VAL(partno$):GOTO 2650
2630 IF partno=maxpartno partno=0 ELSE partno=partno+1
2640 :
2650 PRINT TAB(35,9);partno;cteol$ '
2660 UNTIL partno>0 AND partno<maxpartno+1 AND INT(partno)=partno
2670 =partno
2680 :
2690 :
2700 REM GET THE RECORD FOR THE PART NUMBER
2710 :
2720 REM Return TRUE if the record exists and FALSE if not
2730 REM If the record does not exist, load desc$ with "No Record"
2740 REM The remainder of the record is set to 0
2750 :
2760 DEF FN_getrec(partno,type)
2770 stock=0
2780 reord=0
2790 price=0
2800 PTR#inventry=FN_ptr(partno)
2810 test=BGET#inventry
2820 IF test=0 desc$="No Record": =FALSE
2830 IF test=type THEN 2870
2840 IF type=86 desc$="Record Deleted" ELSE desc$="Record Exists"
2850 =FALSE
2860 :
2870 INPUT#inventry,desc$
2880 INPUT#inventry,stock,reord,price
2890 =TRUE
2900 :
2910 :
2920 REM CALCULATE THE VALUE OF PTR FOR THIS RECORD
2930 :
2940 DEF FN_ptr(partno)=partno*rec_length+5-rec_length
2950 :
2960 :
2970 REM AMEND THE RECORD
2980 :
2990 DEF FN_amend(partno)
3000 PRINT clrline$;TAB(0,4);
3010 PRINT "Please Complete the Details for Part Number ";partno
3020 PRINT "Just hit Return to leave the entry as it is"'
3030 flag=FALSE
3040 type=ASC"V"
3050 INPUT "Description - Max 30 Chars " temp$
3060 IF temp$="DELETE" type=ASC"D": =TRUE
3070 temp$=LEFT$(temp$,30)
3080 IF temp$<>"" desc$=temp$:flag=TRUE
3090 IF desc$="No Record" OR desc$="Record Deleted" =FALSE
3100 INPUT "Current Stock Level        " temp$
3110 IF temp$<>"" stock=VAL(temp$):flag=TRUE
3120 INPUT "Reorder Level              " temp$
3130 IF temp$<>"" reord=VAL(temp$):flag=TRUE
3140 INPUT "Unit Price                 " temp$
3150 IF temp$<>"" price=VAL(temp$):flag=TRUE
3160 =flag
3170 :
3180 :
3190 REM WRITE THE RECORD
3200 :
3210 DEF PROC_write(partno,flag,type)
3220 IF NOT flag ENDPROC
3230 PTR#inventry=FN_ptr(partno)
3240 BPUT#inventry,type
3250 PRINT#inventry,desc$,stock,reord,price
3260 ENDPROC
3270 :
3280 :
3290 REM DISPLAY THE RECORD DETAILS
3300 :
3310 DEF PROC_display(flag)
3320 PRINT TAB(0,5);cteos$;
3330 PRINT "Part Number                ";partno'
3340 PRINT "Description                ";desc$
3350 IF NOT flag ENDPROC
3360 PRINT "Current Stock Level        ";stock
3370 PRINT "Reorder Level              ";reord
3380 PRINT "Unit Price                 ";price
3390 ENDPROC
