   10 REM 'Fake' fractal fern
   20 REM Original QBASIC program published in PC Magazine
   30 REM BB4W version by David Williams
   40 REM From BBC BASIC for SDL 2.0's examples (examples/graphics/fern.bbc),
   50 REM (C) Richard T. Russell, zlib licence (see LICENCE in this folder).
   60 REM Altered for U64 BBC BASIC: BBCSDL's first line removed; MODE 8
   70 REM (a BB4W mode) is MODE 2; OFF is VDU 23,1; CASE ... WHEN (not in
   80 REM BBC BASIC 3.10) is four IF lines; GCOL 2 is GCOL 0,2; ends with a
   85 REM key, not WAIT.
   90 :
  100 MODE 2
  110 VDU 23,1,0;0;0;0;
  120 GCOL 0,2
  130 :
  140 x=0
  150 y=0
  160 :
  170 FOR i%=1 TO 80000
  180   r = RND(1)
  190   :
  200   IF r<=0.1 THEN A=0: B=0: C=0: D=0.16: E=0: F=0
  210   IF r>0.1 AND r<=0.86 THEN A=.85: B=.04: C=-.04: D=.85: E=0: F=1.6
  220   IF r>0.86 AND r<=0.93 THEN A=.2: B=-.26: C=.23: D=.22: E=0: F=1.6
  230   IF r>0.93 THEN A=-.15: B =.28: C=.26: D=.24: E=0: F=.44
  240   :
  250   newx=A*x+B*y+E
  260   newy=C*x+D*y+F
  270   x=newx
  280   y=newy
  290   MOVE 600+96*x, 32+96*y
  300   DRAW 600+96*x, 32+96*y
  310   :
  320 NEXT i%
  330 VDU 23,1,1;0;0;0;
  340 REPEAT UNTIL GET
