10 REM SHOW1: a tunnel of filled circles, coloured by the palette
20 REM (VDU 19 with RGB, cycled: no redrawing needed)
30 MODE 2
40 *OFF
45 *FX 15,1
47 ON ERROR OSCLI "SONG STOP":OSCLI "MODSTOP":VDU 4:IF ERR=17 END ELSE REPORT:PRINT " at line ";ERL:END
50 PROCdraw
60 PROCcycle(1500)
70 CHAIN "SHOW2"
80 END
90 :
100 DEF PROCdraw
110   LOCAL R%,C%
120   GCOL 0,0:CLG
130   C%=1
140   FOR R%=600 TO 20 STEP -20
150     GCOL 0,C%
160     *CIRCLE FILL 640,512,R%
170     C%=C% MOD 15+1
180   NEXT
190 ENDPROC
200 :
300 REM Colours 1-15 run through a rainbow, one step every 3 cs
310 DEF PROCcycle(T%)
320   LOCAL E%,P%,L%,H%
330   E%=TIME+T%:P%=0
340   REPEAT
350     FOR L%=1 TO 15
360       H%=(L%*17+P%) MOD 255
370       VDU 19,L%,16,FNr(H%),FNr(H%+85),FNr(H%+170)
380     NEXT
390     P%=P%+6
400     H%=TIME+3:REPEAT UNTIL TIME>H%
410   UNTIL TIME>E% OR INKEY(0)<>-1
420 ENDPROC
430 :
500 REM A rainbow's channel: a triangle wave of the hue H% (0-254)
510 DEF FNr(H%)
520   H%=H% MOD 255
530   IF H%<85 =H%*3
540   IF H%<170 =(170-H%)*3
550 =0
