10 REM AUDIO: Ultimate Audio - MOD music and sample sound effects
20 REM U64 with 16 MB REU; run from its folder: *CD demos/audio
30 REM Music: 4ev.mod (Slice 1995), wildpersp.mod (Greg Tuby 1996)
40 REM Effects: Juhani Junkala, CC0 (OpenGameArt); see CREDITS.md
50 ON ERROR PROCerror:END
55 MODE 7
60 PROCinit
70 PROCscreen
80 REPEAT
90   K$=GET$
100   PROCkey(K$)
110 UNTIL K$="Q" OR K$="q"
120 *MODSTOP
130 SOUND 28,0,0,0:SOUND 29,0,0,0:SOUND 30,0,0,0
140 MODE 7
150 END
160 :
200 DEF PROCinit
210   LOCAL I%
220   DIM F$(8),N$(8),T$(2),M$(2)
230   RESTORE 900
240   FOR I%=1 TO 8
250     READ F$(I%),N$(I%)
260   NEXT
270   FOR I%=1 TO 2
280     READ M$(I%),T$(I%)
290   NEXT
310   PRINT "Loading the sound effects..."
320   *SAMPLE CLEAR
330   FOR I%=1 TO 8
340     OSCLI "SAMPLE LOAD "+STR$I%+" "+F$(I%)+".WAV"
350   NEXT
360   P%=53:V%=28:M%=0:A%=0
370 ENDPROC
380 :
400 DEF PROCscreen
410   LOCAL I%
420   CLS
430   PRINT CHR$141;CHR$132;CHR$157;CHR$131;"  ULTIMATE AUDIO";
440   PRINT TAB(0,1);CHR$141;CHR$132;CHR$157;CHR$131;"  ULTIMATE AUDIO"
450   PRINT CHR$134;"MOD music and sample effects from"
460   PRINT CHR$134;"the REU, while BASIC runs."
470   PRINT
480   PRINT CHR$130;"Music (Ultimate Audio channels 0-3)"
490   FOR I%=1 TO 2
500     PRINT CHR$135;" ";I%;CHR$131;T$(I%)
510   NEXT
520   PRINT CHR$135;" 0";CHR$131;"stop the music"
530   PRINT
540   PRINT CHR$130;"Effects (channels 4-6)"
550   FOR I%=1 TO 8
560     PRINT CHR$135;" ";CHR$(64+I%);CHR$131;N$(I%);
570     IF I% MOD 2=0 PRINT ELSE PRINT TAB(20);
580   NEXT
590   PRINT CHR$135;" + -";CHR$131;"effects' pitch"
600   PRINT CHR$135;" Q";CHR$131;"quit"
610   PROCstatus("")
620 ENDPROC
630 :
700 DEF PROCkey(K$)
710   LOCAL K%
720   K%=ASC K$ AND &DF
730   IF K$="1" OR K$="2" PROCmod(VAL K$)
740   IF K$="0" PROCstop
750   IF K%>=65 AND K%<=71 PROCfx(K%-64)
760   IF K%=72 PROCalarm
770   IF K$="+" AND P%<101 P%=P%+4:PROCstatus("")
780   IF K$="-" AND P%>5 P%=P%-4:PROCstatus("")
790 ENDPROC
800 :
900 DATA LASER,Laser,BOOM,Explosion,COIN,Coin,JUMP,Jump
910 DATA BLIP,Menu blip,POWERUP,Power-up,HIT,Hit,ALARM,Alarm (on/off)
920 DATA 4ev.mod,Forever Young (Slice),wildpersp.mod,Wild Perspective
930 :
1000 REM An effect on voice 28 or 29 (channels 4, 5: free while a MOD plays)
1010 DEF PROCfx(N%)
1020   SOUND V%,N%,P%,0
1030   V%=V%+1
1040   IF V%>29 V%=28
1050 ENDPROC
1060 :
1100 REM The alarm loops on voice 30 until H again
1110 DEF PROCalarm
1120   IF A% SOUND 30,0,0,0 ELSE SOUND 30,8,P%,255
1130   A%=NOT A%
1140   PROCstatus("")
1150 ENDPROC
1160 :
1200 DEF PROCmod(N%)
1210   PROCstatus("Loading "+M$(N%)+"...")
1220   OSCLI "MODPLAY "+M$(N%)
1230   M%=N%
1240   PROCstatus("")
1250 ENDPROC
1260 :
1300 DEF PROCstop
1310   *MODSTOP
1320   M%=0
1330   PROCstatus("")
1340 ENDPROC
1350 :
1400 DEF PROCstatus(S$)
1410   PRINT TAB(0,22);CHR$157;CHR$132;SPC(37);
1420   PRINT TAB(0,22);CHR$132;CHR$157;CHR$135;
1430   IF S$<>"" PRINT S$; ELSE PROCplaying
1440 ENDPROC
1450 :
1500 DEF PROCplaying
1510   IF M% PRINT "Playing: ";T$(M%); ELSE PRINT "No music";
1520   PRINT TAB(0,23);CHR$134;"Effects' pitch ";P%;"  ";
1530   IF A% PRINT CHR$129;"ALARM";SPC(5); ELSE PRINT SPC(10);
1540 ENDPROC
1550 :
1600 DEF PROCerror
1610   SOUND 28,0,0,0:SOUND 29,0,0,0:SOUND 30,0,0,0
1620   *MODSTOP
1630   PRINT
1640   REPORT:PRINT " (line ";ERL;")"
1650   PRINT "Needs a U64 with Ultimate Audio on, a 16 MB REU,"
1660   PRINT "and its folder: *CD demos/audio"
1670 ENDPROC
