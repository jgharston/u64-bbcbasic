    1 REM From the BBC BASIC (Z80) example programs by Richard T. Russell,
    2 REM as distributed with agon-bbc-basic (examples/sort.bbc),
    3 REM (C) 1984-2000 R.T. Russell, zlib licence (see ../LICENCE).
    4 REM Converted to text for U64 BBC BASIC (tools/bb4wtxt.py);
    5 REM the program itself is unchanged.
10 REM. SHELL SORT ON STRING ARRAYS
20 REM. (c) Richard Russell 1982, from an idea by Robin Tracy.
30 DIM sort 300
40 exterr=&209
50 FOR pass=0 TO 1
60 P%=sort
70 [OPT pass*2
80 LD A,(IX):DEC A:JP NZ,error
90 LD A,(IX+1):CP &81:JP NZ,error
100 LD L,(IX+2):LD H,(IX+3):LD (start),HL
110 DEC HL:LD D,(HL):DEC HL:LD E,(HL):DEC HL:LD A,(HL):DEC A:JP NZ,error
120 LD HL,(start):ADD HL,DE:ADD HL,DE:ADD HL,DE:ADD HL,DE:LD (end),HL
130 SRL D:RR E:LD HL,&FFFF:EX DE,HL
140 .rotate SRL D:RR E:OR A:SBC HL,DE:ADD HL,DE:JR C,rotate
150 EX DE,HL:ADD HL,HL:ADD HL,HL:LD (spacer),HL:EX DE,HL
160 .loop LD IY,(start):PUSH IY:ADD IY,DE:LD (check),IY:POP IX:LD (item),IX
170 .newlen LD A,(IX):CP (IY):JR C,short:LD A,(IY):.short LD B,A
180 OR A:JR Z,null:LD E,(IX+2):LD D,(IX+3):LD L,(IY+2):LD H,(IY+3)
190 .next LD A,(DE):CP (HL):JR C,ok:JR NZ,swap:INC DE:INC HL:DJNZ next
200 .null LD A,(IY):CP (IX):JR NC,ok
210 .swap PUSH IX:POP HL:PUSH IY:POP DE:LD B,4:.move
220 LD A,(DE):LD C,A:LD A,(HL):LD (DE),A:LD (HL),C:INC HL:INC DE:DJNZ move
230 LD DE,(check):PUSH IX:POP HL:OR A:SBC HL,DE:ADD HL,DE:JR C,ok
240 PUSH HL:POP IY:LD DE,(spacer):SBC HL,DE:PUSH HL:POP IX:JR newlen
250 .ok LD HL,(item):LD BC,4:ADD HL,BC:LD (item),HL
260 PUSH HL:POP IX:LD DE,(spacer):ADD HL,DE:PUSH HL:POP IY
270 LD DE,(end):SBC HL,DE:JR C,newlen:LD DE,(spacer):SRL D:LD A,E:RRA
280 AND &FC:LD E,A:OR D:LD (spacer),DE:JP NZ,loop:RET
290 .start DEFW 0:.end DEFW 0:.spacer DEFW 0:.check DEFW 0:.item DEFW 0
300 .error LD A,100:CALL exterr:]
310 $P%="Bad sort parameters"+CHR$0
320 NEXT pass
330 :
340 REM. Test program:
350 :
360 PRINT "Filling 1000 6-character strings..."
370 DIM A$(999)
380 FOR I=0 TO 999:A$(I)="PQRS"+CHR$(64+RND(26))+CHR$(64+RND(26)):NEXT
390 FOR I=0 TO 14:PRINT A$(I),;:NEXT:PRINT "etc..."
400 PRINT "Sorting the strings..."
410 CALL sort,A$(0) : REM. Call assembly language sort routine.
420 FOR I=0 TO 14:PRINT A$(I),;:NEXT:PRINT "etc..."
430 PRINT "Finished."
