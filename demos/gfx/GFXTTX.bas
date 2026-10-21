10 REM GFXTTX: MODE 7, teletext as on the BBC: control codes 129-135
20 REM text colours, 145-151 mosaic graphics, 141 double height, 136
30 REM flashing, 157 new background, 158 hold graphics; the screen
40 REM memory at &7C00 can be written directly.
45 ON ERROR IF ERR=17 THEN CHAIN "GFXDEMO" ELSE VDU 4:REPORT:PRINT " at line ";ERL:END
50 MODE 7
60 *OFF
70 PRINT CHR$141;CHR$131;"  U64 BBC BASIC teletext"
80 PRINT CHR$141;CHR$131;"  U64 BBC BASIC teletext"
90 PRINT
100 FOR I%=1 TO 7
110   PRINT CHR$(128+I%);"Colour ";I%;CHR$(144+I%);STRING$(10,CHR$255)
120 NEXT
130 PRINT
140 PRINT CHR$132;CHR$157;CHR$135;"White on blue background  ";CHR$156
150 PRINT CHR$136;CHR$129;"Flashing red text"
160 PRINT CHR$145;CHR$158;"j";CHR$146;"j";CHR$147;"j";CHR$148;"j  (hold graphics)"
170 PROCmosaic
180 PRINT TAB(0,23);CHR$130;"Below: ?&7FC0... written directly"
190 ?&7FC0=146
200 FOR I%=&7FC1 TO &7FE7
210   ?I%=RND(64)+159
220 NEXT
230 K%=GET
240 CHAIN "GFXDEMO"
250 END
260 DEF PROCmosaic
270   LOCAL R%,C%
280   FOR R%=14 TO 19
290     PRINT TAB(0,R%);CHR$(145+(R% MOD 6));
300     FOR C%=1 TO 38
310       PRINT CHR$(160+((C%*7+R%*3) MOD 32));
320     NEXT
330   NEXT
340 ENDPROC
