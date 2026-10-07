    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-weser1.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_WESER1
20 :
30 REM EXAMPLE OF WRITING A TO THE END OF A SERIAL CHARACTER DATA FILE
40 :
50 REM This program opens a file and sets PTR to the end before writing
60 REM more data to it.
70 :
80 REM A function is used to open the file.
90 :
100 :
110 phonenos=FN_openend("PHONENOS")
120 PRINT "File Name PHONENOS Opened as Channel ";phonenos
130 PRINT
140 REPEAT
150 INPUT "Name ? " name$
160 IF name$="" THEN PROC_end
170 INPUT "Phone Number ? " phone$
180 PRINT
190 PRINT#phonenos,name$,phone$
200 UNTIL FALSE
210 :
220 DEF PROC_end
230 CLOSE#phonenos
240 END
250 :
260 :
270 REM Open the file 'AT END'.
280 :
290 REM PTR is set to the last valid data byte+1 and the file number is
300 REM returned.  If the file does not already exist, it is still opened,
310 REM but PTR is left at 0.
320 :
330 DEF FN_openend(name$)
340 LOCAL fnum
350 fnum=OPENUP(name$)
360 IF fnum=0 THEN fnum=OPENOUT(name$): =fnum
370 PTR#fnum=(EXT#fnum)-128
380 REPEAT
390 last_PTR=PTR#fnum
400 INPUT#fnum,dummy$
410 UNTIL EOF#fnum AND dummy$=""
420 PTR#fnum=last_PTR
430 =fnum
