    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/f-wser1.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM F_WSER
20 :
30 REM EXAMPLE OF WRITING TO A SERIAL CHARACTER DATA FILE
40 :
50 REM This program openes a data file and writes serial character data
60 REM to it.  The use of OPENOUT ensures that, eaven if the file
70 REM existed before, it is cleared before being written to.
80 :
90 :
100 phonenos=OPENOUT "PHONENOS"
110 PRINT "File Name PHONENOS Opened as Channel ";phonenos
120 PRINT
130 REPEAT
140 INPUT "Name ? " name$
150 IF name$="" THEN PROC_end
155 INPUT "Phone Number ? " phone$
160 PRINT
170 PRINT#phonenos,name$,phone$
180 UNTIL FALSE
190 :
200 DEF PROC_end
210 CLOSE#phonenos
220 END
