    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/sortreal.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM. SHELL SORT ON REAL NUMERIC ARRAYS
20 REM. (c) Richard Russell 1984, from an idea by Robin Tracy.
30 DIM sort 300
40 exterr=&209
50 FOR pass=0 TO 1
60 P%=sort
70 [OPT pass*2
80 LD A,(IX):DEC A:JP NZ,error
90 LD A,(IX+1):CP 5:JP NZ,error
100 LD L,(IX+2):LD H,(IX+3):LD (start),HL
110 DEC HL:LD D,(HL):DEC HL:LD E,(HL):DEC HL:LD A,(HL):DEC A:JP NZ,error
120 ;
130 LD HL,(start):ADD HL,DE:ADD HL,DE:ADD HL,DE:ADD HL,DE:ADD HL,DE
140 LD (end),HL:SRL D:RR E:LD HL,&FFFF:EX DE,HL:.rotate SRL D:RR E
150 OR A:SBC HL,DE:ADD HL,DE:JR C,rotate:.loop LD (space),DE
160 LD H,D:LD L,E:ADD HL,HL:ADD HL,HL:ADD HL,DE:LD (spacer),HL:EX DE,HL
170 LD IY,(start):PUSH IY:ADD IY,DE:LD (check),IY:POP IX:LD (item),IX
180 ;
190 .newlen
200 EXX:LD L,(IX):LD H,(IX+1):EXX:LD L,(IX+2):LD H,(IX+3):LD C,(IX+4)
210 EXX:LD E,(IY):LD D,(IY+1):EXX:LD E,(IY+2):LD D,(IY+3):LD B,(IY+4)
220 CALL fcp:JR C,ok
230 ;
240 .swap PUSH IX:POP HL:PUSH IY:POP DE:LD B,5:.move
250 LD A,(DE):LD C,A:LD A,(HL):LD (DE),A:LD (HL),C:INC HL:INC DE:DJNZ move
260 LD DE,(check):PUSH IX:POP HL:OR A:SBC HL,DE:ADD HL,DE:JR C,ok
270 PUSH HL:POP IY:LD DE,(spacer):SBC HL,DE:PUSH HL:POP IX:JR newlen
280 ;
290 .ok LD HL,(item):LD BC,5:ADD HL,BC:LD (item),HL
300 PUSH HL:POP IX:LD DE,(spacer):ADD HL,DE:PUSH HL:POP IY
310 LD DE,(end):SBC HL,DE:JR C,newlen:LD DE,(space):SRL D:RR E
320 LD A,D:OR E:JP NZ,loop:RET
330 ;
340 .fcp LD A,H:XOR D:LD A,H:RLA:RET M:JR NC,fcp0:CALL fcp0:CCF:RET
350 .fcp0 LD A,C:CP B:RET NZ:SBC HL,DE:RET NZ:EXX:SBC HL,DE:EXX:RET
360 ;
370 .start DEFW 0:.end DEFW 0:.spacer DEFW 0:.check DEFW 0:.item DEFW 0
380 .space DEFW 0:.error LD A,100:CALL exterr:]
390 $P%="Bad sort parameters"+CHR$0
400 NEXT pass
410 :
420 REM. Test program:
430 :
440 @%=20
450 PRINT "Filling 1000 real numbers..."
460 DIM A(999)
470 FOR I=0 TO 999:A(I)=(0.5-RND(1))*10^(10-RND(20)):NEXT
480 FOR I=0 TO 14:PRINT A(I);:NEXT:PRINT "  etc..."
490 PRINT "Sorting the numbers..."
500 CALL sort,A(0) : REM. Call assembly language sort routine.
510 FOR I=0 TO 14:PRINT A(I);:NEXT:PRINT "  etc..."
520 PRINT "Finished."
530 @%=&90A
