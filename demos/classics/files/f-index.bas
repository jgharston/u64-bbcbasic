    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-index.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_INDEX
20 REM EXAMPLE OF AN INDEXED FILE
30 :
40 REM This is a simple address book filing system.  It will
50 REM accept names, telephone numbers and addresses and store
60 REM them in a file called ADDRESS.DTA.  The index is in
70 REM name order and is kept in a file called ADDRESS.NDX.
80 REM All the fields are character and the maximum length
90 REM of any field is 30.
100 :
110 :
120 PROC_initialise
130 PROC_open_files
140 REPEAT
150 CLS
160 PRINT TAB(5,3);"If you want to:-" '
170 PRINT TAB(10);"End This Session";TAB(55);"Type 0"
180 PRINT TAB(10);"Enter Data";TAB(55);"Type 1"
190 PRINT TAB(10);"Search For/Delete an Entry";TAB(55);"Type 2"
200 PRINT TAB(10);"List in Alphabetical Order";TAB(55);"Type 3"
210 PRINT TAB(10);"Reorganise the Data File and Index";TAB(55);"Type 4";
220 REPEAT
230 PRINT TAB(5,11);
240 PRINT "Please enter the appropriate number (0 to 4) ";
250 function$=GET$
260 PRINT clrline$;
270 UNTIL function$>"/" AND function$<"5"
280 function=VAL(function$)
290 PRINT TAB(54,function+5);"<====<<";
300 ON function GOSUB 410,670,790,1000 ELSE
310 UNTIL function=0
320 CLS
330 PROC_close_files
340 CLS
350 PRINT "Address Book Files Closed"''
360 END
370 :
380 :
390 REM ENTER DATA
400 :
410 flag=TRUE
420 temp$=""
430 i=1
440 REPEAT
450 REPEAT
460 PROC_get_data
470 IF length=maxrec OR data$(1)="" flag=FALSE:GOTO 540
480 IF data$(1)="+" OR data$(1)="-" PROC_message("Bad Data"):GOTO 540
490 i=FN_find_place(0,data$(1))
500 IF i>0 PROC_message("Duplicate Record")
510 PRINT '"Is this data correct ? ";
520 temp$=GET$
530 :
540 UNTIL NOT flag OR temp$="Y"
550 IF NOT flag THEN 610
560 PROC_put_index(i,data$(1),PTR#datanum)
570 FOR i=2 TO 7
580 PRINT#datanum,data$(i)
590 NEXT
600 :
610 UNTIL NOT flag
620 RETURN
630 :
640 :
650 REM SEARCH FOR AN ENTRY
660 :
670 i=1
680 REPEAT
690 PRINT TAB(0,11);cteol$;
700 INPUT "What name do you want to look for ",name$
710 IF name$="" THEN 730
720 IF name$<>""IF name$="DELETE" PROC_delete(i) ELSE i=FN_display(i,name$)
730 UNTIL name$=""
740 RETURN
750 :
760 :
770 REM LIST IN ALPHABETICAL ORDER
780 :
790 entry=1
800 PRINT curoff$;
810 REPEAT
820 CLS
830 line_count=0
840 REPEAT
850 PRINT TAB(0,line_count);
860 PROC_read_data(entry)
870 PROC_print_data
880 entry=entry+1
890 line_count=line_count+8
900 temp$=INKEY$(0)
910 UNTIL entry>length OR line_count>16 OR temp$<>""
920 PROC_message("Push any key to continue or E to end ")
930 UNTIL entry>length OR GET$="E"
940 PRINT curon$;
950 RETURN
960 :
970 :
980 REM REORGANISE THE DATA FILE AND INDEX
990 :
1000 entry=1
1010 PRINT TAB(0,13);"Reorganising the Data File and Index" '
1020 newdata=OPENOUT"ADDRESS.BAK"
1030 newindex=OPENOUT"NAME.BAK"
1040 IF newdata=0 OR newindex=0 PRINT "Disk Directory Full":END
1050 PRINT#newdata,0
1060 REPEAT
1070 PROC_read_data(entry)
1080 index(entry)=PTR#newdata
1090 FOR i=2 TO 7
1100 PRINT#newdata,data$(i)
1110 NEXT
1120 entry=entry+1
1130 UNTIL entry>length
1140 EOFnewdata=PTR#newdata-1
1150 PTR#newdata=0
1160 PRINT#newdata,EOFnewdata
1170 CLOSE#0
1180 PRINT "Re-naming the Data and Index Files" '
1190 *REN ADDRESS.$$$=ADDRESS.BAK
1200 *REN NAME.$$$=NAME.BAK
1210 *REN ADDRESS.BAK=ADDRESS.DTA
1220 *REN ADDRESS.DTA=ADDRESS.$$$
1230 *REN NAME.BAK=NAME.NDX
1240 *REN NAME.NDX=NAME.$$$
1250 indexnum=OPENUP "NAME.NDX"
1260 datanum=OPENUP "ADDRESS.DTA"
1270 INPUT#datanum,EOFdata
1280 PTR#datanum=EOFdata+1
1290 RETURN
1300 :
1310 :
1320 REM INITIALISE VARIABLES AND ARRAYS
1330 :
1340 :
1350 :
1360 DEF PROC_initialise
1370 esc$=CHR$(27)
1380 bell$=CHR$(7)
1390 cteol$=CHR$(5)
1400 cteos$=CHR$(4)
1410 return$=CHR$(13)
1420 clrline$=return$+cteol$
1430 curoff$=esc$+"D"
1440 curon$=esc$+"C"
1450 :
1460 REM The maximum record number, maxrec, is set/read in
1470 REM PROC_setup/PROC_read_index
1480 :
1490 DIM message$(7)
1500 FOR i=1 TO 7
1510 READ message$(i)
1520 NEXT
1530 DATA Name,Phone Number,Address,-- " --,-- " --,-- " --,Post Code
1540 :
1550 DIM data$(7)
1560 FOR i=1 TO 7
1570 data$(i)=STRING$(30," ")
1580 NEXT
1590 temp$=STRING$(255," ")
1600 temp$=""
1610 ENDPROC
1620 :
1630 :
1640 REM OPEN THE FILES
1650 :
1660 DEF PROC_open_files
1670 indexnum=OPENUP"NAME.NDX"
1680 datanum=OPENUP"ADDRESS.DTA"
1690 IF indexnum=0 OR datanum=0 PROC_setup ELSE PROC_read_index
1700 ENDPROC
1710 :
1720 :
1730 REM SET UP NEW INDEX AND DATA FILES
1740 :
1750 DEF PROC_setup
1760 CLS
1770 PRINT TAB(0,13);"Setting Up Address Book"
1780 maxrec=10
1790 indexnum=OPENOUT"NAME.NDX"
1800 datanum=OPENOUT"ADDRESS.DTA"
1810 IF indexnum=0 OR datanum=0 PRINT "Disk Directory Full":END
1820 PRINT#indexnum,0,maxrec
1830 PRINT#datanum,0
1840 DIM index$(maxrec+1),index(maxrec+1)
1850 length=0
1860 index$(0)=""
1870 index(0)=0
1880 index$(1)=CHR$(&FF)
1890 index(1)=0
1900 ENDPROC
1910 :
1920 :
1930 REM READ INDEX AND LENGTH OF DATA FILE
1940 :
1950 DEF PROC_read_index
1960 CLS
1970 INPUT#indexnum,EOFindex,maxrec
1980 DIM index$(maxrec+1), index(maxrec+1)
1990 index$(0)=""
2000 index(0)=0
2010 length=0
2020 REPEAT
2030 length=length+1
2040 INPUT#indexnum,index$(length),index(length)
2050 UNTIL PTR#indexnum>EOFindex
2060 index$(length+1)=CHR$(&FF)
2070 index(length+1)=0
2080 INPUT#datanum,EOFdata
2090 PTR#datanum=EOFdata+1
2100 ENDPROC
2110 :
2120 :
2130 REM WRITE INDEX, MAXREC AND NEW EOF POINTERS AND CLOSE FILES
2140 :
2150 DEF PROC_close_files
2160 EOFdata=PTR#datanum-1
2170 PTR#datanum=0
2180 PRINT#datanum,EOFdata
2190 PTR#indexnum=10
2200 FOR i=1 TO length
2210 PRINT#indexnum,index$(i),index(i)
2220 NEXT
2230 EOFindex=PTR#indexnum-1
2240 PTR#indexnum=0
2250 PRINT#indexnum,EOFindex,maxrec
2260 CLOSE#0
2270 ENDPROC
2280 :
2290 :
2300 REM WRITE A MESSAGE AT LINE 23
2310 :
2320 DEF PROC_message(line$)
2330 LOCAL x,y
2340 x=POS
2350 y=VPOS
2360 PRINT TAB(0,23);bell$;line$;
2370 PRINT TAB(x,y);
2380 ENDPROC
2390 :
2400 :
2410 REM GET INPUT DATA - LIMIT TO 30 CHAR
2420 :
2430 DEF PROC_get_data
2440 LOCAL i
2450 PRINT TAB(0,13);cteos$
2460 IF length=maxrec PROC_message("Address Book Full")
2470 FOR i=1 TO 7
2480 PRINT TAB(10);message$(i);TAB(25);
2490 INPUT temp$
2500 data$(i)=LEFT$(temp$,30)
2510 IF data$(1)="" i=7
2520 NEXT
2530 ENDPROC
2540 :
2550 :
2560 REM FIND AND DISPLAY THE REQUESTED DATA
2570 :
2580 DEF FN_display(i,name$)
2590 PRINT TAB(0,12);cteos$
2600 i=FN_find_place(i,name$)
2610 IF i<0 PROC_message("Name Not Known - Next Highest Given")
2620 PROC_read_data(i)
2630 PRINT
2640 PROC_print_data
2650 =i
2660 :
2670 :
2680 REM DELETE THE ENTRY FROM THE INDEX
2690 :
2700 DEF PROC_delete(i)
2710 INPUT "Are you SURE ",temp$
2720 PRINT TAB(0,VPOS-1);cteos$;
2730 IF temp$<>"YES" ENDPROC
2740 IF i<0 i=-i
2750 FOR i=i TO length
2760 index$(i)=index$(i+1)
2770 index(i)=index(i+1)
2780 NEXT
2790 length=length-1
2800 ENDPROC
2810 :
2820 :
2830 REM READ DATA FOR ENTRY i
2840 :
2850 DEF PROC_read_data(i)
2860 PTRdata=PTR#datanum
2870 IF i<0 i=-i
2880 PTR#datanum=index(i)
2890 data$(1)=index$(i)
2900 FOR i=2 TO 7
2910 INPUT#datanum,data$(i)
2920 NEXT
2930 PTR#datanum=PTRdata
2940 ENDPROC
2950 :
2960 :
2970 REM PRINT data$() ON VDU
2980 :
2990 DEF PROC_print_data
3000 LOCAL i
3010 FOR i=1 TO 7
3020 IF data$(i)<>"" PRINT TAB(10);message$(i);TAB(25);data$(i)
3030 IF data$(1)=CHR$(&FF) i=7
3040 NEXT
3050 ENDPROC
3060 :
3070 :
3080 REM PUT A NEW ENTRY IN INDEX AT POSITION i
3090 :
3100 DEF PROC_put_index(i,entry$,ptr)
3110 LOCAL j
3120 IF i<0 i=-i
3130 FOR j=length+1 TO i STEP -1
3140 index$(j+1)=index$(j)
3150 index(j+1)=index(j)
3160 NEXT
3170 index$(i)=entry$
3180 index(i)=ptr
3190 length=length+1
3200 ENDPROC
3210 :
3220 :
3230 REM FIND ENTRY IN INDEX OR PLACE TO PUT IT
3240 :
3250 DEF FN_find_place(i,entry$)
3260 LOCAL top,bottom
3270 IF i<0 i=-i
3280 IF entry$="+" AND i<length =i+1
3290 IF entry$="+" AND i=length =1
3300 IF entry$="-" AND i>1 =i-1 
3310 IF entry$="-" AND i=1 =length
3320 top=length+1
3330 bottom=0
3340 i=(top+1) DIV 2
3350 IF entry$<>index$(i) i=FN_search(entry$)
3360 REPEAT
3370 IF entry$=index$(i-1) i=i-1
3380 UNTIL entry$<>index$(i-1)
3390 IF entry$=index$(i) =i ELSE =-i
3400 :
3410 :
3420 REM DO THE SEARCHING FOR FN_find_place
3430 :
3440 DEF FN_search(entry$)
3450 REPEAT
3460 IF entry$>index$(i) bottom=i ELSE top=i
3470 i=(top+bottom+1) DIV 2:  REM round
3480 UNTIL entry$=index$(i) OR top=bottom+1
3490 =i
