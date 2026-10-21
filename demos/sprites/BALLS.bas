10 REM BALLS: 32 multiplexed sprites (*SPRITE, OSWORD &71)
20 REM Four bands of 8 balls, one above the other: a ball stays in its
30 REM band, so never more than 8 share a raster line (the VIC-II's
40 REM limit) and the multiplexer shows all 32 without flicker.
50 *SPRITE ON
60 MODE 100
65 ON ERROR PROCend
70 PROCshape
80 PROCsetup
90 PRINT TAB(5,0);"32 sprites on 8: RUN/STOP ends"
100 REPEAT
110   PROCmove
120 UNTIL FALSE
130 END
140 DEF PROCshape
150   LOCAL S$
160   S$="00FF0003FFC007FFE01FFFF81FFFF83FFFFC7FFFFE7FFFFE7FFFFE7FFFFEFFF"
170   S$=S$+"FFF7FFFFE7FFFFE7FFFFE7FFFFE3FFFFC1FFFF81FFFF807FFE003FFC000FF00"
180   OSCLI "SPRITE DEFINE 0 "+S$
190 ENDPROC
200 DEF PROCsetup
210   REM band N% DIV 8: bottom edges from L% to H% (a ball is 108 high,
220   REM a band 256: 18 units, 3 raster lines, between the bands)
230   DIM X%(31),Y%(31),U%(31),V%(31),L%(31),H%(31),B% 10
240   FOR N%=0 TO 31
250     L%(N%)=(N% DIV 8)*256+8:H%(N%)=L%(N%)+130
260     X%(N%)=RND(1180):Y%(N%)=L%(N%)+RND(130)
270     U%(N%)=RND(17)-9:V%(N%)=RND(9)-5
280     IF V%(N%)=0 THEN V%(N%)=3
290     B%?0=N%:B%?1=3:B%?6=1+((N% DIV 8)*4+N% MOD 4) MOD 15:PROCword
300   NEXT
310 ENDPROC
320 DEF PROCmove
330   LOCAL T%
340   T%=TIME
350   FOR N%=0 TO 31
360     X%(N%)=X%(N%)+U%(N%):Y%(N%)=Y%(N%)+V%(N%)
370     IF X%(N%)<0 THEN X%(N%)=0:U%(N%)=ABS U%(N%)
380     IF X%(N%)>1180 THEN X%(N%)=1180:U%(N%)=-ABS U%(N%)
390     IF Y%(N%)<L%(N%) THEN Y%(N%)=L%(N%):V%(N%)=ABS V%(N%)
400     IF Y%(N%)>H%(N%) THEN Y%(N%)=H%(N%):V%(N%)=-ABS V%(N%)
410     B%?0=N%:B%?1=1:B%!2=X%(N%):B%!4=Y%(N%):PROCword
420   NEXT
430   REPEAT UNTIL TIME>T%
440 ENDPROC
450 DEF PROCword
460   A%=&71:X%=B% MOD 256:Y%=B% DIV 256:CALL &C7F1
470 ENDPROC
480 REM RUN/STOP (ESCAPE) ends it: the sprites off first (they stay on
490 REM over the prompt otherwise)
500 DEF PROCend
510   *SPRITE OFF
520   IF ERR<>17 THEN REPORT:PRINT " at line ";ERL
530   END
540 ENDPROC

