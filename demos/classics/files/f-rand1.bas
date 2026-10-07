    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-rand1.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_RAND1
20 REM SIMPLE DATABASE PROGRAM
30 REM Written by R T Russell  Jan 1983
40 :
50 REM This is a simple database program.  You are asked for
60 REM the name of the file you wish to use.  If the file
70 REM does not already exist, you are asked to specify the
80 REM number and format of the records.  If the file does
90 REM already exist, the file specification is read from
100 REM the file.
110 :
120 :
130 @%=10
140 CLS
150 WIDTH 0
160 INPUT '"Enter the filename of the data file: "filename$
170 fnum=OPENUP(filename$)
180 IF fnum=0 PROC_setup ELSE PROC_readgen
190 base=PTR#fnum:PRINT
200 :
210 REPEAT
220 INPUT '"Enter record number: "ans$
230 IF ans$="0" CLOSE#fnum:CLS:END
240 IF ans$="" record=record+1 ELSE record=VAL(ans$)
250 PTR#fnum=FN_ptr(record)
260 PROC_display
270 INPUT '"Do you wish to change this record",ans$
280 PTR#fnum=FN_ptr(record)
290 IF FN_test(ans$) PROC_modify
300 UNTIL FALSE
310 END
320 :
330 DEF FN_test(A$) =LEFT$(A$,1)="Y" OR LEFT$(A$,1)="y"
340 :
350 DEF FN_ptr(record)=base+record*length
360 :
370 DEF PROC_setup
380 PRINT "New file."
390 fnum=OPENOUT(filename$)
400 IF fnum=0 PRINT "Sorry, disk directory full.":END
410 INPUT "Enter number of fields per record: "fields
420 DIM title$(fields),size(fields),A$(fields)
430 FOR field=1 TO fields
440 PRINT '"Enter title of field number ";field;": ";
450 INPUT ""title$(field)
460 PRINT
470 REPEAT
480 INPUT "Maximum size of field (characters)",size(field)
490 UNTIL size(field)>0 AND size(field)<256
500 NEXT field
510 length=1
520 PRINT#fnum,fields
530 FOR field=1 TO fields
540 PRINT#fnum,title$(field),size(field)
550 length=length+size(field)+1
560 NEXT field
570 ENDPROC
580 :
590 DEF PROC_readgen
600 length=1
610 INPUT#fnum,fields
620 DIM title$(fields),size(fields),A$(fields)
630 FOR field=1 TO fields
640 INPUT#fnum,title$(field),size(field)
650 length=length+size(field)+1
660 NEXT field
670 ENDPROC
680 :
690 DEF PROC_display
700 PRINT '"Record number ";record'
710 flag=BGET#fnum
720 IF EOF#fnum OR flag=0 PRINT "Record not stored":ENDPROC
730 FOR field=1 TO fields
740 INPUT#fnum,A$(field)
750 PRINT title$(field);" ";A$(field)
760 NEXT field
770 ENDPROC
780 :
790 DEF PROC_modify
800 PRINT '"(Enter <RETURN> for no change)"'
810 FOR field=1 TO fields
820 REPEAT
830 PRINT title$(field);" ";
840 INPUT LINE ""A$
850 IF A$="" PRINT CHR$(11)title$(field);" ";A$(field)
860 UNTIL LEN(A$)<=size(field)
870 IF A$<>"" A$(field)=A$
880 NEXT field
890 INPUT '"Confirm update record",ans$
900 IF NOT FN_test(ans$) ENDPROC
910 BPUT#fnum,255
920 FOR field=1 TO fields
930 PRINT#fnum,A$(field)
940 NEXT field
950 ENDPROC
