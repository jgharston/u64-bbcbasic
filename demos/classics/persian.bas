   10 REM PERSIAN
   20 REM From an original program by Acorn Computers
   30 REM (IBM version 23 Mar 86, modified 25 Sep 98).
   40 REM From BBC BASIC for SDL 2.0's examples (examples/graphics/persian.bbc),
   50 REM (C) Richard T. Russell, zlib licence (see LICENCE in this folder).
   60 REM Altered for U64 BBC BASIC: BBCSDL's first line (touch IDE) removed;
   70 REM MODE 18 (640x480, a BB4W mode) is MODE 2, the origin the BBC
   80 REM screen's centre (VDU 29,640;512;).
   90 :
  100 MODE 2
  110 VDU 29,640;512;
  120 REPEAT
  130 CLS
  140 J1%=0
  150 FOR K%=396 TO 240 STEP -40
  160 REPEATJ2%=RND(15):UNTILJ2%<>J1%
  170 J1%=J2%
  180 GCOL 3,J1%
  190 FOR I%=-K% TO K% STEP 4
  200 MOVE K%,I%
  210 DRAW -K%,-I%
  220 MOVE I%,-K%
  230 DRAW -I%,K%
  240 NEXT
  250 NEXT
  260 K% = INKEY(200)
  270 UNTIL FALSE
