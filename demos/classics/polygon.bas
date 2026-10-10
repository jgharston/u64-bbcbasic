   10 REM POLYGON
   20 REM From an original program by John A Coll
   30 REM (IBM version 23 Mar 86, modified 26 Sep 98).
   40 REM From BBC BASIC for SDL 2.0's examples (examples/graphics/polygon.bbc),
   50 REM (C) Richard T. Russell, zlib licence (see LICENCE in this folder).
   60 REM Altered for U64 BBC BASIC: BBCSDL's first line (touch IDE) removed;
   70 REM MODE 18 (640x480, a BB4W mode) is MODE 2.
   80 :
   90 MODE 2
  100 DIM X(10)
  110 DIM Y(10)
  120 :
  130 REPEAT
  140 xorigin=RND(1279)
  150 yorigin=RND(1023)
  160 Radius=RND(300)+50
  170 VDU 29,xorigin;yorigin;
  180 sides=RND(8)+2
  190 MOVE Radius,0
  200 MOVE 10,10
  210 :
  220 C=RND(16)-1:GCOL 0,C
  230 FOR SIDE=1 TO sides
  240 angle=(SIDE-1)*2*PI/sides
  250 X(SIDE)=Radius*COS(angle)
  260 Y(SIDE)=Radius*SIN(angle)
  270 MOVE 0,0
  280 PLOT 85,X(SIDE),Y(SIDE)
  290 NEXT SIDE
  300 MOVE 0,0
  310 PLOT 85,Radius,0
  320 :
  330 REPEAT D=RND(16)-1:UNTIL (D AND3)<>(C AND3):GCOL 0,D
  340 FOR SIDE=1 TO sides
  350 FOR Line=SIDE TO sides
  360 MOVE X(SIDE), Y(SIDE)
  370 DRAW X(Line), Y(Line)
  380 NEXT Line
  390 NEXT SIDE
  400 K% = INKEY(30)
  410 UNTIL FALSE
