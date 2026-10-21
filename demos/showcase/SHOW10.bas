10 REM SHOW10: credits, while the MOD plays; then the end
20 MODE 7
25 *FX 15,1
27 ON ERROR OSCLI "SONG STOP":OSCLI "MODSTOP":VDU 4:IF ERR=17 END ELSE REPORT:PRINT " at line ";ERL:END
30 RESTORE 500
40 REPEAT
50   READ A$
60   IF A$<>"*" PROCline(A$)
70 UNTIL A$="*" OR INKEY(0)<>-1
80 K%=INKEY(800)
90 *MODSTOP
100 PRINT:PRINT CHR$131;"The end. CHAIN ";CHR$34;"SHOW";CHR$34;" to see it again."
110 END
120 :
200 DEF PROCline(A$)
210   LOCAL C%
220   C%=VAL LEFT$(A$,1)
230   IF C%=9 PRINT CHR$141;CHR$131;MID$(A$,2):PRINT CHR$141;CHR$131;MID$(A$,2) ELSE PRINT CHR$(128+C%);MID$(A$,2)
240   K%=INKEY(150)
250 ENDPROC
260 :
500 DATA 9U64 BBC BASIC,4,"6BBC BASIC 3.10: Sophie Wilson, Acorn"
510 DATA 6the C64 port: Ivo van Poorten,4,2MOS and demos: Xander Mol (idi8b)
520 DATA 4,3Music,7SID: the song tracker on 8 SIDs,"7MOD: Wild Perspective, Greg Tuby"
530 DATA 7MOD player: ModPlayer_16k by Freshness,4,3Graphics,7Bubble Universe: Eric Schraf
540 DATA "7Upic: Aleksi Eeben, C. Gleissner",7Effects: Juhani Junkala (CC0)
550 DATA 4,9Thanks for watching,*
