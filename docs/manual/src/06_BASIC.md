# 6. BASIC

The language is BBC BASIC 3.10, unchanged. This chapter has the syntax
of every keyword, grouped by what it does; the keywords for files,
graphics and sound are in their own chapters (7, 8, 9). Keywords are
written in capitals; `A%`-`Z%` are the fast resident integer variables.

## 6.1 Variables and operators

@@help VARIABLES OPERATORS LET DIM

## 6.2 Working with programs

@@help AUTO LIST LISTO *LIST DELETE RENUMBER NEW OLD RUN CHAIN LOAD SAVE CLEAR END STOP REM *SEARCH *XREF *CRUNCH

## 6.3 Program flow

@@help IF THEN ELSE FOR TO STEP NEXT REPEAT UNTIL GOTO GOSUB RETURN ON

## 6.4 Procedures and functions

Structured programs use `DEF PROC` and `DEF FN` with `LOCAL` variables
instead of `GOSUB`; see the example programs in `demos/`.

@@help DEF PROC ENDPROC FN LOCAL

## 6.5 Errors

@@help ERRORS ERROR ERR ERL REPORT TRACE

## 6.6 Numbers

@@help ABS SGN INT MOD DIV SQR EXP LN LOG SIN COS TAN ASN ACS ATN DEG RAD PI RND AND OR EOR NOT TRUE FALSE *TABLE

## 6.7 Strings

@@help ASC CHR$ LEFT$ MID$ RIGHT$ LEN INSTR STR$ STRING$ VAL EVAL

## 6.8 Data in the program

@@help DATA READ RESTORE

## 6.9 Keyboard and text on the screen

@@help PRINT INPUT GET GET$ INKEY INKEY$ TAB SPC POS VPOS COUNT WIDTH CLS COLOUR *PETSCII *SEQ

## 6.10 Time

@@help TIME

## 6.11 Machine code

BBC BASIC has an assembler built in (`[` ... `]`). Zero page &70-&8F is
free for your own machine code, as on a BBC Micro; the MOS entry points
are in chapter 13.

@@help ASSEMBLER OPT CALL USR OSCLI
