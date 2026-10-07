   10 REM SINE
   20 REM Initial version from John A Coll, version 2 / 16 Nov 81
   30 REM From BBC BASIC for SDL 2.0's examples (examples/graphics/sine.bbc),
   40 REM (C) Richard T. Russell, zlib licence (see LICENCE in this folder).
   50 REM Altered for U64 BBC BASIC: BBCSDL's first line (touch IDE)
   60 REM removed; the closing WAIT loop is now REPEAT UNTIL GET.
   70 :
   80 MODE 1
   90 VDU 5
  100 GCOL 0,1
  110 VDU 19,1,3,0,0,0
  120 MOVE 16,600
  130 :
  140 FOR X=0 TO 315
  150 IF X<150 THEN MOVE 4*X+16,360
  160 PLOT 21,4*X+16,300*SIN(X/48)+360
  170 NEXT
  180 GCOL 0,2
  190 A$="SINE WAVES ARE FAR MORE INTERESTING....."
  200 :
  210 FOR X=1 TO 39
  220 MOVE X*1280/40,300*SIN(X/6)+472
  230 PRINT MID$(A$,X,1);
  240 NEXT
  250 :
  260 VDU 4
  270 REPEAT UNTIL GET
