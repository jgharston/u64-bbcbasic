    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-rser1.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_RSER
20 :
30 REM EXAMPLE OF READING A SERIAL CHARACTER FILE
40 :
50 REM This program opens a previously written serial file and reads it.
60 :
70 :
80 phonenos=OPENUP "PHONENOS"
90 PRINT "File Name PHONENOS Opened as Channel ";phonenos
100 PRINT
110 REPEAT
120 INPUT#phonenos,name$,phone$
130 IF EOF#phonenos THEN PROC_end
140 PRINT name$,phone$
150 UNTIL FALSE
160 :
170 DEF PROC_end
180 CLOSE#phonenos
190 END
