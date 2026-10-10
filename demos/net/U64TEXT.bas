10 REM U64TEXT: a Ceefax-style information service in MODE 7 (network demo)
20 REM 200 weather, 300 blog, 400 news, 500 ISS; docs/DESIGN_NETWORK.md 7
30 :
40 REM MODE here, at the top: BASIC refuses MODE inside a PROC or FN
50 MODE 7
60 PROCinit
70 ON ERROR PROCfailed:PROCrun:END
80 PROCrun
90 END
100 :
110 DEF PROCinit
120   DIM CB% 30,W$(15),D$(2),DT%(2),DH(2),DL(2),AL%(9),BD$(4)
130   DIM R$(4),RL$(4),RO$(4),LB% 40,SB% 255,TX%(11),TY%(11)
140   PROCjsoninit
150   P%=100:SP%=1:CAR%=FALSE:NC%=0:PN$=""
160   FW%=-100000:FE%=-100000:FB%=-100000:FI%=-100000
170   NB%=0:NN%=0:TN%=0:BY%=0
180   PROCwmo
190   PROCload
200 ENDPROC
210 :
220 REM The main loop: the page, then keys; the clock every second
230 DEF PROCrun
240   LOCAL K%
250   REPEAT
260     PROCpage(P%)
270     REPEAT
280       PROCheader
290       K%=INKEY(100)
300       IF CAR% AND TIME>NC% K%=32
310       IF P%=500 AND TIME-FI%>1000 PROCiss
320       IF K%>=48 AND K%<=57 PROCdigit(K%)
330     UNTIL K%=32 OR K%=13 OR K%=67 OR K%=99 OR K%=82 OR K%=114 OR K%=81 OR K%=113 OR K%=136 OR K%=137 OR LEN PN$=4
340     IF K%=32 P%=FNnext(P%):SP%=1
350     IF K%=137 SP%=SP%+1
360     IF K%=136 AND SP%>1 SP%=SP%-1
370     IF K%=67 OR K%=99 CAR%=NOT CAR%:NC%=TIME+1500
380     IF K%=82 OR K%=114 PROCforget(P%)
390     IF LEN PN$=4 P%=VAL MID$(PN$,2):PN$="":SP%=1
400   UNTIL K%=81 OR K%=113
410   CLS
420 ENDPROC
430 :
440 REM Typed digits: three make a page number (PN$ = "P" + digits)
450 DEF PROCdigit(K%)
460   IF PN$="" PN$="P"
470   PN$=PN$+CHR$K%
480 ENDPROC
490 :
500 REM SPACE: the next section, or the next article
510 DEF FNnext(P%)
520   IF CAR% NC%=TIME+1500
530   IF P%>300 AND P%<300+NB% THEN =P%+1
540   IF P%>400 AND P%<400+NN% THEN =P%+1
550   IF P%>=500 THEN =100
560 =(P% DIV 100+1)*100
570 :
580 DEF PROCforget(P%)
590   IF P% DIV 100=2 FW%=-100000
600   IF P% DIV 100=3 FB%=-100000
610   IF P% DIV 100=4 FE%=-100000
620   IF P%=500 FI%=-100000
630 ENDPROC
640 :
650 REM After an error: a message, then the next page
660 DEF PROCfailed
670   LOCAL K%
680   IF ERR=17 CLS:END
690   CLS:PROCheader
700   PROCtitle("Page "+STR$P%+": not available")
710   PRINT TAB(0,5);CHR$129;"The page could not be fetched:"
720   PRINT CHR$131;LEFT$(FNerror,38);" (line ";ERL;")"
730   PRINT:PRINT CHR$135;"Any key: the next page"
740   K%=INKEY(500)
750   P%=FNnext(P%)
760 ENDPROC
770 :
780 DEF FNerror
790   LOCAL A$
800   REPORT
810 =""
820 :
830 REM ------------------------------------------------------------------
840 REM The pages
850 DEF PROCpage(N%)
860   CLS
870   PROCheader
880   OK%=TRUE
890   IF N%=100 PROCindex ELSE IF N%=200 PROCweather ELSE IF N%=201 PROCsettings ELSE OK%=FALSE
900   IF N%>=300 AND N%<=305 PROCblog(N%-300):OK%=TRUE
910   IF N%>=400 AND N%<=410 PROCnews(N%-400):OK%=TRUE
920   IF N%=500 PROCiss:OK%=TRUE
930   IF NOT OK% PROCnopage(N%)
940 ENDPROC
950 :
960 REM Row 0: page number, name, the Ultimate's clock (as Ceefax)
970 DEF PROCheader
980   LOCAL C$
990   C$=FNclock
1000   PRINT TAB(0,0);CHR$135;"P";P%;CHR$131;"U64TEXT";CHR$134;" ";
1010   PRINT TAB(15,0);CHR$135;LEFT$(PN$+"    ",4);
1020   PRINT TAB(20,0);
1030   IF CAR% PRINT CHR$130;"C"; ELSE PRINT "  ";
1040   PRINT TAB(23,0);CHR$131;MID$(C$,1,3);" ";MID$(C$,5,6);CHR$135;MID$(C$,17,5);
1050 ENDPROC
1060 :
1070 REM The clock as OSWORD 14 gives it: "Sat,10 Oct 2026.08:42:55"
1080 DEF FNclock
1090   ?CB%=0:A%=14:X%=CB% MOD 256:Y%=CB% DIV 256:CALL &C7F1
1100   CB%?24=13
1110 =$CB%
1120 :
1130 REM A double height title on rows 2-3, cyan on a blue band
1140 DEF PROCtitle(T$)
1150   LOCAL R%
1160   FOR R%=2 TO 3
1170     PRINT TAB(0,R%);CHR$132;CHR$157;CHR$141;CHR$134;T$;
1180   NEXT
1190 ENDPROC
1200 :
1210 DEF PROCindex
1220   PROCtitle("U64 BBC BASIC   INDEX")
1230   PRINT TAB(0,6);CHR$131;" 200  ";CHR$135;"Weather"
1240   PRINT CHR$131;" 201  ";CHR$135;"Weather: the place"
1250   PRINT CHR$131;" 300  ";CHR$135;"idreamtin8bits.com blog"
1260   PRINT CHR$131;" 400  ";CHR$135;"News: Ars Technica"
1270   PRINT CHR$131;" 500  ";CHR$135;"Where is the ISS?"
1280   PRINT
1290   PRINT CHR$130;"Type a page number, SPACE for the next"
1300   PRINT CHR$130;"page, cursor right/left for subpages,"
1310   PRINT CHR$130;"C carousel, R reload, Q quit."
1320   PRINT TAB(0,20);CHR$134;"On a Commodore 64 Ultimate: BBC BASIC,"
1330   PRINT CHR$134;"the Ultimate's network, plain HTTP."
1340   PRINT TAB(0,23);CHR$132;CHR$157;CHR$135;"Open-Meteo, Ars Technica, ISS";
1350   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"open-notify.org";
1360 ENDPROC
1370 :
1380 DEF PROCnopage(N%)
1390   PROCtitle("Page "+STR$N%)
1400   PRINT TAB(0,6);CHR$129;"There is no page ";N%;"."
1410   PRINT CHR$135;"Index: 100"
1420 ENDPROC
1430 :
1440 REM While a page loads: a line at the bottom with the K read
1450 DEF PROCbusy(T$)
1460   BY%=0
1470   PRINT TAB(0,24);CHR$131;CHR$157;CHR$132;"Loading ";T$;"...";
1480 ENDPROC
1490 DEF PROCtick
1500   PRINT TAB(31,24);CHR$132;STR$(BY% DIV 1024);"K";
1510 ENDPROC
1520 DEF PROCidle
1530   PRINT TAB(0,24);SPC(39);
1540 ENDPROC
1550 :
1560 REM ------------------------------------------------------------------
1570 REM 200 Weather: Open-Meteo's forecast as CSV (decimals intact)
1580 DEF PROCweather
1590   PROCtitle("Weather  "+LEFT$(PLACE$,20))
1600   IF TIME-FW%>60000 PROCbusy("the weather"):PROCgetweather:PROCidle
1610   PRINT TAB(0,5);CHR$131;"Now";CHR$135;FNtemp(CT);CHR$134;W$(FNwmo(CC%))
1620   PRINT CHR$130;"Wind ";CHR$135;STR$INT(CW+.5);" km/h"
1630   PROCicon(FNwmo(CC%),30,5)
1640   PRINT TAB(0,10);CHR$132;CHR$157;CHR$135;"Day        Max   Min  ";
1650   FOR I%=0 TO 2
1660     PRINT TAB(0,12+I%*2);CHR$131;D$(I%);TAB(11,12+I%*2);CHR$135;FNtemp(DH(I%));FNtemp(DL(I%));CHR$134;LEFT$(W$(FNwmo(DT%(I%))),14)
1670   NEXT
1680   PRINT TAB(0,20);CHR$130;"At ";PLACE$
1690   PRINT CHR$130;"(";LAT$;", ";LON$;")  page 201: change"
1700   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"Weather data by Open-Meteo.com";
1710 ENDPROC
1720 :
1730 DEF PROCgetweather
1740   LOCAL F%,L$,I%
1750   F%=OPENIN("http://api.open-meteo.com/v1/forecast?latitude="+LAT$+"&longitude="+LON$+"&current=temperature_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=3&format=csv")
1760   IF F%=0 ERROR 100,"No weather"
1770   L$=FNskipto(F%,"time,temperature")
1780   L$=FNline(F%)
1790   CT=VAL FNcsv(L$,2):CC%=VAL FNcsv(L$,3):CW=VAL FNcsv(L$,4)
1800   L$=FNskipto(F%,"time,weather_code")
1810   FOR I%=0 TO 2
1820     L$=FNline(F%)
1830     D$(I%)=FNday(FNcsv(L$,1)):DT%(I%)=VAL FNcsv(L$,2)
1840     DH(I%)=VAL FNcsv(L$,3):DL(I%)=VAL FNcsv(L$,4)
1850   NEXT
1860   CLOSE#F%
1870   FW%=TIME
1880 ENDPROC
1890 :
1900 REM In tenths with whole numbers: STR$ of 8.6 may give 8.600000001
1910 DEF FNtemp(T)
1920   LOCAL N%,A$
1930   N%=INT(ABS(T)*10+.5):A$=STR$(N% DIV 10)+"."+STR$(N% MOD 10)
1940   IF T<0 AND N%>0 A$="-"+A$
1950 =RIGHT$("     "+A$,5)+"C "
1960 :
1970 REM "2026-10-10" -> "Sat 10 Oct"
1980 DEF FNday(A$)
1990   LOCAL Y%,M%,D%,W%
2000   Y%=VAL LEFT$(A$,4):M%=VAL MID$(A$,6,2):D%=VAL MID$(A$,9,2)
2010   IF M%<3 M%=M%+12:Y%=Y%-1
2020   W%=(D%+(13*(M%+1)) DIV 5+Y%+Y% DIV 4-Y% DIV 100+Y% DIV 400) MOD 7
2030   IF M%>12 M%=M%-12
2040 =MID$("SatSunMonTueWedThuFri",W%*3+1,3)+" "+STR$D%+" "+MID$("JanFebMarAprMayJunJulAugSepOctNovDec",M%*3-2,3)
2050 :
2060 REM The WMO weather code -> one of 8 kinds (W$() names, icons)
2070 DEF FNwmo(C%)
2080   IF C%=0 THEN =0
2090   IF C%<=2 THEN =1
2100   IF C%=3 THEN =2
2110   IF C%<=48 THEN =3
2120   IF C%<=67 OR (C%>=80 AND C%<=82) THEN =4
2130   IF C%<=77 OR C%=85 OR C%=86 THEN =5
2140 =6
2150 :
2160 DEF PROCwmo
2170   RESTORE 2190
2180   FOR I%=0 TO 6:READ W$(I%):NEXT
2190   DATA Clear,Partly cloudy,Overcast,Fog,Rain,Snow,Thunderstorm
2200 ENDPROC
2210 :
2220 REM A 4 x 3 mosaic icon for kind K% at column X%, row Y%
2230 DEF PROCicon(K%,X%,Y%)
2240   LOCAL R%,A$
2250   RESTORE 2310:IF K%>0 FOR R%=1 TO K%*4:READ A$:NEXT
2260   READ IC%
2270   FOR R%=0 TO 2
2280     READ A$:PRINT TAB(X%,Y%+R%);FNmosaic(A$);
2290   NEXT
2300 ENDPROC
2310 DATA 3,"  ##  "," #### ","  ##  "
2320 DATA 3,"  ## ##"," ##### ","       "
2330 DATA 7," #### ","######","      "
2340 DATA 7,"======","======","======"
2350 DATA 6," #### ","######"," / / /"
2360 DATA 7," #### ","######"," * * *"
2370 DATA 3," #### ","######","  //  "
2380 :
2390 REM An icon row in colour IC%: # full block, = striped
2400 DEF FNmosaic(A$)
2410   LOCAL O$,I%,H$
2420   O$=CHR$(144+IC%)
2430   FOR I%=1 TO LEN A$
2440     H$=MID$(A$,I%,1)
2450     IF H$="#" O$=O$+CHR$255 ELSE IF H$="=" O$=O$+CHR$243 ELSE O$=O$+H$
2460   NEXT
2470 =O$
2480 :
2490 REM ------------------------------------------------------------------
2500 REM 400 News: Ars Technica's RSS titles; 401-410 the text, 14 lines a page
2510 DEF PROCnews(G%)
2520   LOCAL I%
2530   IF TIME-FE%>60000 PROCbusy("the news"):PROCgetnews:PROCidle
2540   IF G%>0 PROCarticle(G%):ENDPROC
2550   PROCtitle("News   Ars Technica")
2560   FOR I%=0 TO NN%-1
2570     IF I%<NN% PRINT TAB(0,5+I%*2);CHR$131;STR$(401+I%);" ";CHR$135;FNshort(FNget(&4A000+I%*256),33)
2580   NEXT
2590   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"Source: arstechnica.com";
2600 ENDPROC
2610 :
2620 DEF PROCarticle(G%)
2630   LOCAL I%,N%,L%
2640   IF G%>NN% PROCnopage(400+G%):ENDPROC
2650   PROCtitle("News   Ars Technica")
2660   PROCwrap(FNget(&4A000+(G%-1)*256),5,1)
2670   N%=(AL%(G%-1)+13) DIV 14:IF N%=0 N%=1
2680   IF SP%>N% SP%=1
2690   FOR I%=0 TO 13
2700     L%=(SP%-1)*14+I%
2710     IF L%<AL%(G%-1) OSCLI "SRREAD &"+STR$~LB%+" +40 &"+STR$~(&40000+(G%-1)*&1000+L%*40):PRINT TAB(1,9+I%);$LB%;
2720   NEXT
2730   PRINT TAB(0,23);CHR$130;STR$(400+G%);"/";STR$SP%;" of ";STR$N%;CHR$134;"cursor right: more";
2740   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"Source: arstechnica.com";
2750 ENDPROC
2760 :
2770 REM Over TCP: the 76 KB feed is too big for the HTTP reader
2780 DEF PROCgetnews
2790   LOCAL F%,A$
2800   F%=OPENUP("TCP:feeds.arstechnica.com:80")
2810   IF F%=0 ERROR 100,"No news"
2820   PROCsend(F%,"GET /arstechnica/index HTTP/1.0"):PROCsend(F%,"Host: feeds.arstechnica.com"):PROCsend(F%,"")
2830   NN%=0
2840   A$=FNtag(F%):A$=FNtag(F%)
2850   REPEAT
2860     A$=FNtag(F%)
2870     IF A$<>"" PROCput256(A$,&4A000+NN%*256):PROCread(F%,NN%):NN%=NN%+1
2880   UNTIL NN%=10 OR EOF#F%
2890   CLOSE#F%
2900   FE%=TIME
2910 ENDPROC
2920 :
2930 REM An article's text wrapped into the REU: &40000+N%*&1000, 40 a line
2940 DEF PROCread(F%,N%)
2950   LOCAL C%,E%
2960   AL%(N%)=0:AW$="":AT$="":AB%=TRUE
2970   IF NOT FNfind(F%,"<content:encoded>") ENDPROC
2980   REPEAT
2990     C%=BGET#F%:BY%=BY%+1:IF (BY% AND 511)=0 PROCtick
3000     IF C%=60 PROCtagin(F%,N%):C%=256
3010     IF C%=38 AW$=AW$+FNent(F%):C%=256
3020     IF C%>127 AND C%<256 AW$=AW$+FNutf(F%,C%):C%=256
3030     IF C%=93 E%=E%+1 ELSE IF C%=62 AND E%>1 C%=-1 ELSE IF C%<256 E%=0
3040     IF C%>32 AND C%<256 AND LEN AW$<38 AW$=AW$+CHR$C%
3050     IF C%>=0 AND C%<=32 PROCword(N%)
3060   UNTIL C%=-1 OR EOF#F% OR AL%(N%)>=56
3070   IF RIGHT$(AW$,2)="]]" AW$=LEFT$(AW$,LEN AW$-2)
3080   PROCword(N%):PROCemit(N%)
3090 ENDPROC
3100 :
3110 REM A tag: paragraph and list ends break the line
3120 DEF PROCtagin(F%,N%)
3130   LOCAL C%,T$
3140   REPEAT
3150     C%=BGET#F%:IF LEN T$<2 T$=T$+CHR$C%
3160   UNTIL C%=62 OR EOF#F%
3170   IF T$="/p" OR T$="/h" OR T$="br" OR T$="li" OR T$="/l" PROCword(N%):PROCemit(N%)
3180   IF T$="/p" OR T$="/h" PROCblank(N%)
3190 ENDPROC
3200 :
3210 REM The word AW$ onto the line AT$ (a full line goes to the REU first)
3220 DEF PROCword(N%)
3230   IF AW$="" ENDPROC
3240   IF LEN AT$+LEN AW$>37 PROCemit(N%)
3250   IF AT$<>"" AT$=AT$+" "
3260   AT$=AT$+AW$:AW$=""
3270 ENDPROC
3280 :
3290 REM A line (or one empty line) to the REU
3300 DEF PROCemit(N%)
3310   IF AT$="" ENDPROC
3320   PROCput(N%):AB%=FALSE
3330 ENDPROC
3340 DEF PROCblank(N%)
3350   IF AB% ENDPROC
3360   AT$="":PROCput(N%):AB%=TRUE
3370 ENDPROC
3380 DEF PROCput(N%)
3390   IF AL%(N%)>=56 ENDPROC
3400   $LB%=AT$
3410   OSCLI "SRWRITE &"+STR$~LB%+" +40 &"+STR$~(&40000+N%*&1000+AL%(N%)*40)
3420   AL%(N%)=AL%(N%)+1:AT$=""
3430 ENDPROC
3440 :
3450 REM An HTML entity after & (up to ;): the few that occur as text
3460 DEF FNent(F%)
3470   LOCAL C%,A$
3480   REPEAT
3490     C%=BGET#F%:IF C%<>59 A$=A$+CHR$C%
3500   UNTIL C%=59 OR LEN A$>8 OR EOF#F%
3510   IF A$="amp" THEN ="&"
3520   IF A$="quot" OR A$="#8220" OR A$="#8221" THEN =CHR$34
3530   IF A$="lt" THEN ="<"
3540   IF A$="gt" THEN =">"
3550   IF A$="#8217" OR A$="#8216" OR A$="#039" OR A$="#39" THEN ="'"
3560   IF A$="#8211" OR A$="#8212" THEN ="-"
3570   IF A$="nbsp" OR A$="#160" THEN =" "
3580 =""
3590 :
3600 REM UTF-8: quotes and dashes as ASCII, the rest left out
3610 DEF FNutf(F%,C%)
3620   LOCAL B%,D%
3630   IF C%<&C0 THEN =""
3640   IF C%<&E0 B%=BGET#F%:=""
3650   B%=BGET#F%:D%=BGET#F%
3660   IF C%>=&F0 B%=BGET#F%:=""
3670   IF C%<>&E2 THEN =""
3680   IF D%=&98 OR D%=&99 THEN ="'"
3690   IF D%=&9C OR D%=&9D THEN =CHR$34
3700   IF D%=&93 OR D%=&94 THEN ="-"
3710   IF D%=&A6 THEN ="..."
3720 =""
3730 :
3740 REM Texts in the REU, 256 bytes each (the program's memory is short in
3750 REM MODE 7): news titles &4A000, blog summaries &4B000, titles &4C000,
3760 REM addresses &4D000
3770 DEF PROCput256(A$,R%)
3780   $SB%=A$:OSCLI "SRWRITE &"+STR$~SB%+" +256 &"+STR$~R%
3790 ENDPROC
3800 DEF FNget(R%)
3810   OSCLI "SRREAD &"+STR$~SB%+" +256 &"+STR$~R%
3820 =$SB%
3830 :
3840 REM A$ cut to at most N% characters at a word, with ".." when cut
3850 DEF FNshort(A$,N%)
3860   LOCAL P%
3870   IF LEN A$<=N% THEN =A$
3880   A$=LEFT$(A$,N%-2)
3890   P%=LEN A$
3900   REPEAT P%=P%-1:UNTIL P%<N% DIV 2 OR MID$(A$,P%,1)=" "
3910   IF P%>=N% DIV 2 A$=LEFT$(A$,P%-1)
3920 =A$+".."
3930 :
3940 REM A line to a TCP channel, CR LF at the end
3950 DEF PROCsend(F%,A$)
3960   LOCAL I%
3970   IF A$<>"" FOR I%=1 TO LEN A$:BPUT#F%,ASC MID$(A$,I%,1):NEXT
3980   BPUT#F%,13:BPUT#F%,10
3990 ENDPROC
4000 :
4010 REM The next <title>'s text (in CDATA up to the first ])
4020 DEF FNtag(F%)
4030   LOCAL A$,C%,E%
4040   IF NOT FNfind(F%,"<title>") THEN =""
4050   C%=BGET#F%:E%=60
4060   IF C%=60 PROCskip(F%,8):C%=BGET#F%:E%=93
4070   REPEAT
4080     IF C%<>E% AND LEN A$<120 A$=A$+FNascii(C%)
4090     IF C%<>E% C%=BGET#F%
4100   UNTIL C%=E% OR EOF#F%
4110 =FNentities(A$)
4120 REM UTF-8: a lead byte (&E2: quotes, dashes) as ', the rest dropped
4130 DEF FNascii(C%)
4140   IF C%<128 THEN =CHR$C%
4150   IF C%=&E2 THEN ="'"
4160 =""
4170 DEF PROCskip(F%,N%)
4180   LOCAL I%,C%
4190   FOR I%=1 TO N%:C%=BGET#F%:NEXT
4200 ENDPROC
4210 :
4220 REM Read the channel on until the text K$ has gone by
4230 DEF FNfind(F%,K$)
4240   LOCAL M%,C%
4250   M%=1
4260   REPEAT
4270     C%=BGET#F%:BY%=BY%+1:IF (BY% AND 511)=0 PROCtick
4280     IF C%=ASC MID$(K$,M%,1) M%=M%+1 ELSE IF C%=ASC K$ M%=2 ELSE M%=1
4290   UNTIL M%>LEN K$ OR EOF#F%
4300 =M%>LEN K$
4310 :
4320 REM A$ word-wrapped in 38 columns from row R%, white or yellow
4330 DEF PROCwrap(A$,R%,Y%)
4340   LOCAL W$,L$,P%
4350   L$=""
4360   REPEAT
4370     P%=INSTR(A$+" "," ")
4380     W$=LEFT$(A$,P%-1):A$=MID$(A$,P%+1)
4390     IF LEN L$+LEN W$>37 PROCrow(L$,R%,Y%):R%=R%+1:L$=""
4400     IF L$<>"" L$=L$+" "
4410     L$=L$+W$
4420   UNTIL A$=""
4430   IF L$<>"" PROCrow(L$,R%,Y%)
4440 ENDPROC
4450 DEF PROCrow(L$,R%,Y%)
4460   IF R%<23 PRINT TAB(0,R%);CHR$(135-4*Y%);L$;
4470 ENDPROC
4480 DEF FNlines(A$)
4490 =(LEN A$+37) DIV 38
4500 :
4510 REM HTML entities: &amp; &quot; &lt; &gt; &#39; &#039;
4520 DEF FNentities(A$)
4530   A$=FNswap(A$,"&amp;","&"):A$=FNswap(A$,"&quot;",CHR$34)
4540   A$=FNswap(A$,"&lt;","<"):A$=FNswap(A$,"&gt;",">")
4550 =FNswap(FNswap(A$,"&#039;","'"),"&#39;","'")
4560 DEF FNswap(A$,F$,T$)
4570   LOCAL P%
4580   REPEAT
4590     P%=INSTR(A$,F$):IF P% A$=LEFT$(A$,P%-1)+T$+MID$(A$,P%+LEN F$)
4600   UNTIL P%=0
4610 =A$
4620 :
4630 REM ------------------------------------------------------------------
4640 REM 300 The blog (the BBS server's feed); 301-305 a post (G%: not A%,
4650 REM X%, Y%, which the OSWORD calls set)
4660 DEF PROCblog(G%)
4670   LOCAL I%,R%,T$
4680   IF TIME-FB%>60000 PROCbusy("the blog"):PROCgetblog:PROCidle
4690   PROCtitle("idreamtin8bits.com")
4700   IF G%>0 PROCpost(G%):ENDPROC
4710   R%=5
4720   FOR I%=0 TO NB%-1
4730     IF R%<22 AND I%<NB% T$=FNget(&4C000+I%*256):PRINT TAB(0,R%);CHR$131;STR$(301+I%);" ";CHR$130;BD$(I%):PROCwrap(T$,R%+1,0):R%=R%+FNlines(T$)+2
4740   NEXT
4750   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"bbs.idreamtin8bits.com/u64-feed.json";
4760 ENDPROC
4770 :
4780 DEF PROCpost(G%)
4790   LOCAL R%
4800   IF G%>NB% PROCnopage(300+G%):ENDPROC
4810   PRINT TAB(0,5);CHR$130;BD$(G%-1)
4820   PROCwrap(FNget(&4C000+(G%-1)*256),6,1)
4830   R%=7+FNlines(FNget(&4C000+(G%-1)*256))
4840   PROCwrap(FNget(&4B000+(G%-1)*256),R%,0)
4850   PRINT TAB(0,22);CHR$134;"Read it at idreamtin8bits.com/blog/"
4860   PRINT TAB(1,23);CHR$134;LEFT$(FNget(&4D000+(G%-1)*256),37);
4870   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"bbs.idreamtin8bits.com/u64-feed.json";
4880 ENDPROC
4890 :
4900 DEF PROCgetblog
4910   LOCAL I%,P$
4920   OSCLI "JSON GET http://bbs.idreamtin8bits.com/u64-feed.json"
4930   NB%=FNjsoncount("blogs"):IF NB%>5 NB%=5
4940   FOR I%=0 TO NB%-1
4950     IF I%<NB% P$="blogs/%"+STR$I%+"/":PROCput256(FNjson(P$+"title"),&4C000+I%*256):BD$(I%)=FNday(FNjson(P$+"date")):PROCput256(FNjson(P$+"summary"),&4B000+I%*256):PROCput256(FNjson(P$+"slug"),&4D000+I%*256)
4960   NEXT
4970   FB%=TIME
4980 ENDPROC
4990 :
5000 REM ------------------------------------------------------------------
5010 REM 500 The ISS: Natural Earth map in mosaics, 10 degrees a cell; hold
5020 REM graphics keep it unbroken around the red ISS and yellow trail
5030 DEF PROCiss
5040   LOCAL R%
5050   IF TIME-FI%>1000 PROCbusy("the position"):PROCgetiss
5060   PROCtitle("Where is the ISS?")
5070   FOR R%=0 TO 15
5080     PRINT TAB(0,5+R%);FNmaprow(R%);
5090   NEXT
5100   PRINT TAB(0,22);CHR$131;"Lat ";FNdeg(ILAT);"  Lon ";FNdeg(ILON);"     "
5110   PRINT TAB(0,23);CHR$129;"ISS";CHR$135;"now  ";CHR$131;"before";CHR$135;"(every 10 s)"
5120   PROCidle:PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"open-notify.org";
5130 ENDPROC
5140 :
5150 REM The position, and a new cell for the trail (the last 12)
5160 DEF PROCgetiss
5170   LOCAL X%,Y%,I%
5180   OSCLI "JSON GET http://api.open-notify.org/iss-now.json"
5190   ILAT=VAL FNjson("iss_position/latitude")
5200   ILON=VAL FNjson("iss_position/longitude")
5210   FI%=TIME
5220   X%=INT((ILON+180)/10):Y%=INT((80-ILAT)/10)
5230   IF X%>35 X%=35
5240   IF TN%>0 IF TX%(0)=X% AND TY%(0)=Y% ENDPROC
5250   IF TN%<12 TN%=TN%+1
5260   IF TN%>1 FOR I%=TN%-1 TO 1 STEP -1:TX%(I%)=TX%(I%-1):TY%(I%)=TY%(I%-1):NEXT
5270   REM (the IF: a FOR loop runs at least once)
5280   TX%(0)=X%:TY%(0)=Y%
5290 ENDPROC
5300 :
5310 REM Map row R%, the trail and the ISS marked
5320 DEF FNmaprow(R%)
5330   LOCAL O$,A$,I%,B%
5340   RESTORE 5620
5350   IF R%>0 FOR I%=1 TO R%:READ A$:NEXT
5360   READ A$
5370   O$=CHR$148+CHR$157+CHR$158+CHR$146
5380   FOR I%=1 TO 36
5390     B%=ASC MID$(A$,I%,1)-48:O$=O$+CHR$(160+(B% AND 31)+(B% AND 32)*2)
5400   NEXT
5410   IF TN%=0 THEN =O$
5420   FOR I%=TN%-1 TO 0 STEP -1
5430     IF TY%(I%)=R% O$=FNmark(O$,TX%(I%)+4,147+2*(I%=0))
5440   NEXT
5450 =O$
5460 :
5470 REM Mark column X% in graphics colour C% (145 red, 147 yellow): the
5480 REM code in the column before, green again after
5490 DEF FNmark(O$,X%,C%)
5500   O$=LEFT$(O$,X%-1)+CHR$C%+CHR$255+MID$(O$,X%+2)
5510   IF X%<39 IF ASC MID$(O$,X%+2,1)>159 O$=LEFT$(O$,X%+1)+CHR$146+MID$(O$,X%+3)
5520 =O$
5530 :
5540 REM A position in tenths of a degree
5550 DEF FNdeg(D)
5560   LOCAL N%,A$
5570   N%=INT(ABS(D)*10+.5):A$=STR$(N% DIV 10)+"."+STR$(N% MOD 10)
5580   IF D<0 A$="-"+A$
5590 =A$
5600 :
5610 REM The map: CHR$(48+bits) -> mosaic 160+(b AND 31)+(b AND 32)*2
5620 DATA "00000Xllooc3_ooo0003100HP`hnmd`Pd000"
5630 DATA "<^ooooooO?kE:o3840PnoolooooooooooooO"
5640 DATA "00303oooolom@0000ljgoooooooooooo@:10"
5650 DATA "00000Zooooo=10000boooog[ooooooo7E000"
5660 DATA "000002_ooo5000000kl@Coonoooooo3<0000"
5670 DATA "0000002_E2@00000Xooooooo;ooooO000000"
5680 DATA "00000002;5R00000^oooooO30Z1:o0D00000"
5690 DATA "0000000002ool0002?;oooO00000Dh100000"
5700 DATA "0000000000ooomD0000_oo0000001CA9d400"
5710 DATA "0000000000;ooo10000nooX0000000heD000"
5720 DATA "00000000000oo700000ZoE2000000ZoooD00"
5730 DATA "0000000000Xo70000000300000000:3;o10P"
5740 DATA "0000000000ZE000000000000000000002081"
5750 DATA "000000000024000000000000000000000000"
5760 DATA "00000000000H0000000000```0```````000"
5770 DATA "00``llllllN70@P`loooooooooooooooooG0"
5780 :
5790 REM ------------------------------------------------------------------
5800 REM 201 The weather's place: Open-Meteo geocoding, or AUTO (ip-api.com)
5810 DEF PROCsettings
5820   LOCAL A$,N%,K%
5830   PROCtitle("Settings: the weather")
5840   PRINT TAB(0,5);CHR$131;"Now: ";CHR$135;LEFT$(PLACE$,28)
5850   PRINT TAB(0,7);CHR$130;"Type a place name, or AUTO for the"
5860   PRINT CHR$130;"place of this internet connection;"
5870   PRINT CHR$130;"RETURN alone keeps it."
5880   PRINT TAB(0,11);CHR$134;"Place? ";
5890   INPUT ""A$
5900   IF A$="" ENDPROC
5910   IF A$="AUTO" OR A$="auto" PROCbusy("the place"):PROCauto:PROCsave:PROCidle:FW%=-100000:PRINT TAB(0,13);CHR$130;"Saved: ";LEFT$(PLACE$,28):ENDPROC
5920   PROCbusy("places"):N%=FNgeocode(A$):PROCidle
5930   IF N%=0 PRINT TAB(0,13);CHR$129;"Not found: ";A$:ENDPROC
5940   FOR K%=0 TO N%-1
5950     PRINT TAB(0,13+K%);CHR$131;K%+1;CHR$135;LEFT$(R$(K%),30)
5960   NEXT
5970   PRINT TAB(0,13+N%+1);CHR$134;"Which (1-";N%;")? ";
5980   K%=GET-49
5990   IF K%<0 OR K%>=N% ENDPROC
6000   PLACE$=R$(K%):LAT$=RL$(K%):LON$=RO$(K%)
6010   PROCsave:FW%=-100000
6020   PRINT TAB(0,22);CHR$130;"Saved: ";LEFT$(PLACE$,28)
6030 ENDPROC
6040 :
6050 REM Up to 5 places for name A$: R$() "name, CC", RL$() lat, RO$() lon
6060 DEF FNgeocode(A$)
6070   LOCAL F%,N%,V$
6080   REM (over TCP: the HTTP reader hangs on longer replies)
6090   F%=OPENUP("TCP:geocoding-api.open-meteo.com:80")
6100   IF F%=0 THEN =0
6110   PROCsend(F%,"GET /v1/search?count=5&name="+FNurl(A$)+" HTTP/1.0"):PROCsend(F%,"Host: geocoding-api.open-meteo.com"):PROCsend(F%,"")
6120   REPEAT
6130     V$=FNvalue(F%,"name")
6140     IF V$<>"" R$(N%)=V$:RL$(N%)=FNvalue(F%,"latitude"):RO$(N%)=FNvalue(F%,"longitude"):R$(N%)=R$(N%)+", "+FNvalue(F%,"country_code"):N%=N%+1
6150   UNTIL V$="" OR N%=5
6160   CLOSE#F%
6170 =N%
6180 :
6190 DEF PROCauto
6200   LOCAL F%
6210   F%=OPENIN("http://ip-api.com/json/")
6220   IF F%=0 ERROR 100,"No place"
6230   PLACE$=FNvalue(F%,"country")
6240   PLACE$=FNvalue(F%,"city")+", "+PLACE$
6250   LAT$=FNvalue(F%,"lat"):LON$=FNvalue(F%,"lon")
6260   CLOSE#F%
6270 ENDPROC
6280 :
6290 REM Raw JSON: the value after "key": ("" if none)
6300 DEF FNvalue(F%,K$)
6310   LOCAL C%,A$,Q%
6320   IF NOT FNfind(F%,CHR$34+K$+CHR$34+":") THEN =""
6330   C%=BGET#F%
6340   IF C%=34 Q%=TRUE:C%=BGET#F%
6350   REPEAT
6360     IF Q% AND C%=34 THEN C%=-1 ELSE IF NOT Q% AND (C%=44 OR C%=125) THEN C%=-1 ELSE A$=A$+CHR$C%:C%=BGET#F%
6370   UNTIL C%=-1 OR EOF#F% OR LEN A$>40
6380 =A$
6390 :
6400 REM A name for a URL: spaces as %20
6410 DEF FNurl(A$)
6420   LOCAL P%
6430   REPEAT
6440     P%=INSTR(A$," ")
6450     IF P% A$=LEFT$(A$,P%-1)+"%20"+MID$(A$,P%+1)
6460   UNTIL P%=0
6470 =A$
6480 :
6490 REM U64TEXT.CFG: place, latitude, longitude
6500 DEF PROCload
6510   LOCAL F%
6520   F%=OPENIN "U64TEXT.CFG"
6530   IF F%=0 PROCauto:PROCsave:ENDPROC
6540   INPUT#F%,PLACE$,LAT$,LON$
6550   CLOSE#F%
6560 ENDPROC
6570 DEF PROCsave
6580   LOCAL F%
6590   F%=OPENOUT "U64TEXT.CFG"
6600   PRINT#F%,PLACE$,LAT$,LON$
6610   CLOSE#F%
6620 ENDPROC
6630 :
6640 REM ------------------------------------------------------------------
6650 REM Text helpers: lines of a channel, CSV fields
6660 DEF FNline(F%)
6670   LOCAL A$,C%
6680   REPEAT
6690     C%=BGET#F%:BY%=BY%+1:IF (BY% AND 511)=0 PROCtick
6700     IF C%>=32 AND LEN A$<200 A$=A$+CHR$C%
6710   UNTIL C%=10 OR EOF#F%
6720 =A$
6730 :
6740 DEF FNskipto(F%,K$)
6750   LOCAL A$
6760   REPEAT A$=FNline(F%):UNTIL LEFT$(A$,LEN K$)=K$ OR EOF#F%
6770 =A$
6780 :
6790 REM Field N% (from 1) of a comma-separated line
6800 DEF FNcsv(A$,N%)
6810   LOCAL I%,P%
6820   IF N%>1 FOR I%=2 TO N%:P%=INSTR(A$+",",","):A$=MID$(A$,P%+1):NEXT
6830   REM (a FOR loop runs at least once: hence the IF)
6840   P%=INSTR(A$+",",",")
6850 =LEFT$(A$,P%-1)
6860 :
6870 :
29990 REM ------------------------------------------------------------------
30000 REM demos/net/JSONLIB, merged (see there)
30010 DEF PROCjsoninit
30020   DIM JB% 8,JP% 255,JS% 255
30030 ENDPROC
30040 :
30050 REM The value at P$ as text ("" if there is none)
30060 DEF FNjson(P$)
30070   PROCjsonask(P$)
30080   JS%?(JB%?7)=13
30090 =$JS%
30100 :
30110 REM The value at P$ as a number
30120 DEF FNjsonnum(P$)
30130 =VAL FNjson(P$)
30140 :
30150 REM The number of entries of the object or array at P$
30160 DEF FNjsoncount(P$)
30170   PROCjsonask(P$)
30180 =JB%?8
30190 :
30200 REM The type at P$: 0 none 1 number 2 boolean 3 string 4 object 5 array
30210 DEF FNjsontype(P$)
30220   PROCjsonask(P$)
30230 =JB%?6
30240 :
30250 DEF PROCjsonask(P$)
30260   $JP%=P$
30270   JB%?0=JP% MOD 256:JB%?1=JP% DIV 256:JB%?2=LEN P$
30280   JB%?3=JS% MOD 256:JB%?4=JS% DIV 256:JB%?5=255
30290   A%=&70:X%=JB% MOD 256:Y%=JB% DIV 256
30300   CALL &C7F1
30310 ENDPROC
