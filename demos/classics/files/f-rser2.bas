    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-rser2.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_RSER2
20 :
30 REM EXAMPLE OF READING FROM A SERIAL MIXED NUMERIC/CHARACTER DATA FILE
40 :
50 REM This program opens a data file and reads numeric and character data
60 REM from it.
70 :
80 REM When the file is opened its length is read from the first
90 REM record and used to determine when the end of the data has been
100 REM reached.  A procedure is used to open the file; it sets both the
110 REM file number and the length of the file.  In effect it is a
120 REM function returning 2 values.
130 :
140 :
150 PROC_open("STATS"):    REM Sets both file_num and length
160 stats=file_num
170 EOFstats=EOFfnum
180 PRINT "File Name STATS Opened as Channel ";stats
190 PRINT
200 REPEAT
210 INPUT#stats,name$,age,height,sex$
220 PRINT "Name ";name$
230 PRINT "Age ";age
240 PRINT "Height in centimeters ";height
250 IF sex$="M" THEN PRINT "Male" ELSE PRINT "Female"
260 PRINT
270 UNTIL PTR#stats>EOFstats
280 :
290 DEF PROC_end
300 CLOSE#stats
310 END
320 :
330 :
340 REM Open the file and read its length from the first record.
350 REM Set the file number (stats) and the position of the last valid
360 REM data byte in the file (eof) - ie its length-1.
370 :
380 DEF PROC_open(name$)
390 file_num=OPENUP(name$)
400 INPUT#file_num,EOFfnum
410 ENDPROC
