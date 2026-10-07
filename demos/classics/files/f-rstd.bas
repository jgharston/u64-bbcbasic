    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-rstd.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_RSTD
20 :
30 REM EXAMPLE OF READING A COMPATIBLE DATA FILE
40 :
50 REM This program opens a data file and reads numeric and character
60 REM data from it.  The data is read a byte at a time and the
70 REM appropriate action taken depending on whether it is a
80 REM character, a comma, or a control character.
90 :
100 :
110 compat=OPENUP("COMPAT")
120 PRINT "File Name COMPAT Opened as Channel ";compat
130 PRINT
140 REPEAT
150 name$=FN_read
160 PRINT "Name ";name$
170 age=VAL(FN_read)
180 PRINT "Age ";age
190 height=VAL(FN_read)
200 PRINT "Height in centimeters ";height
210 sex$=FN_read
220 IF sex$="M" THEN PRINT "Male" ELSE PRINT "Female"
230 PRINT
240 UNTIL FALSE
250 :
260 :
270 REM Read a data item from the file.  Treat commas and CRs as
280 REM data item terminators and Control Z as the file terminator.
290 REM Since we are not interested in reading a record at a time,
300 REM the record terminator CR LF is of no spacial interest to us.
310 :
320 DEF FN_read
330 LOCAL data$,byte$,byte
340 dat$=""
350 REPEAT
360 byte=BGET#compat
370 IF byte=&1A THEN CLOSE#compat: END
380 IF NOT(byte=&0A OR byte=&0D OR byte=&2C) THEN data$=data$+CHR$(byte)
390 UNTIL byte=&0D OR byte=&2C
400 =data$
