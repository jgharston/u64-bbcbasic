    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-rand0.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_RAND0
20 :
30 REM VERY SIMPLE RANDOM ACCESS PROGRAM
40 :
50 REM This program maintains a random access file of names
60 REM and remarks.  Each name can be up to a maximum of 30
70 REM characters long and each remark up to 50 characters.
80 REM The first byte of the record is set non zero (in fact
90 REM &FF) if there is a record present.  This gives a
100 REM maximum record length of 1+31+51=83. (Don't forget
110 REM the CRs.)
120 :
130 :
140 @%=10
150 temp$=STRING$(50," ")
160 CLS
170 WIDTH 0
180 fnum=OPENUP "RANDZERO"
190 IF fnum=0 fnum=OPENOUT "RANDZERO"
200 IF fnum=0 PRINT "Directory Full":END
210 :
220 REPEAT
230 INPUT '"Enter record number: "ans$
240 IF ans$="0" CLOSE#fnum:CLS:END
250 IF ans$="" record=record+1 ELSE record=VAL(ans$)
260 PTR#fnum=FN_ptr(record)
270 PROC_display
280 INPUT '"Do you wish to change this record",ans$
290 PTR#fnum=FN_ptr(record)
300 IF FN_test(ans$) PROC_modify
310 UNTIL FALSE
320 END
330 :
340 :
350 DEF FN_test(A$) =LEFT$(A$,1)="Y" OR LEFT$(A$,1)="y"
360 :
370 DEF FN_ptr(record)=record*83
380 :
390 DEF PROC_display
400 PRINT '"Record number ";record'
410 flag=BGET#fnum
420 IF EOF#fnum OR flag=0 PRINT "Record not stored":ENDPROC
430 INPUT#fnum,name$,remark$
440 PRINT name$;"  ";remark$ '
450 ENDPROC
460 :
470 DEF PROC_modify
480 PRINT '"(Enter <RETURN> for no change)"'
490 INPUT "Name ",temp$
500 temp$=LEFT$(temp$,30)
510 IF temp$<>"" name$=temp$
520 INPUT "Remark ",temp$
530 temp$=LEFT$(temp$,50)
540 IF temp$<>"" remark$=temp$
550 INPUT '"Confirm update record",ans$
560 IF NOT FN_test(ans$) ENDPROC
570 BPUT#fnum,255
580 PRINT#fnum,name$,remark$
590 ENDPROC
