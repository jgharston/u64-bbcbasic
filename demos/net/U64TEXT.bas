10 REM U64TEXT: a Ceefax-style information service in MODE 7 (network demo)
20 REM 200 weather, 300 blog, 400 news, 500 ISS; docs/DESIGN_NETWORK.md 7
30 REM MODE here, at the top: BASIC refuses MODE inside a PROC or FN
40 MODE 7
50 PROCinit
60 ON ERROR PROCfailed:PROCrun:END
70 PROCrun
80 END
90 DEF PROCinit
100   DIM CB% 30,W$(15),D$(2),DT%(2),DH(2),DL(2),AL%(14),BD$(4)
110   DIM R$(4),RL$(4),RO$(4),LB% 40,SB% 255,TX%(11),TY%(11)
120   PROCjsoninit
130   P%=100:SP%=1:CAR%=FALSE:NC%=0:PN$=""
140   FW%=-100000:FE%=-100000:FB%=-100000:FI%=-100000
150   NB%=0:NN%=0:TN%=0:BY%=0
155   REM (set before any fetch: a failed one then shows "not available",
156   REM not "No such variable" in FNtemp or FNdeg)
157   CT=0:CC%=0:CW=0:ILAT=0:ILON=0
160   PROCwmo
170   PROCload
180 ENDPROC
190 REM The main loop: the page, then keys; the clock every second
200 DEF PROCrun
210   LOCAL K%
220   REPEAT
230     PROCpage(P%)
240     REPEAT
250       PROCheader
260       K%=INKEY(100)
270       IF CAR% AND TIME>NC% K%=32
280       IF P%=500 AND TIME-FI%>1000 PROCiss
290       IF K%>=48 AND K%<=57 PROCdigit(K%)
300     UNTIL K%=32 OR K%=13 OR K%=67 OR K%=99 OR K%=82 OR K%=114 OR K%=81 OR K%=113 OR K%=136 OR K%=137 OR LEN PN$=4
310     IF K%=32 P%=FNnext(P%):SP%=1
320     IF K%=137 SP%=SP%+1
330     IF K%=136 AND SP%>1 SP%=SP%-1
340     IF K%=67 OR K%=99 CAR%=NOT CAR%:NC%=TIME+1500
350     IF K%=82 OR K%=114 PROCforget(P%)
360     IF LEN PN$=4 P%=VAL MID$(PN$,2):PN$="":SP%=1
370   UNTIL K%=81 OR K%=113
380   CLS
390 ENDPROC
400 REM Typed digits: three make a page number (PN$ = "P" + digits)
410 DEF PROCdigit(K%)
420   IF PN$="" PN$="P"
430   PN$=PN$+CHR$K%
440 ENDPROC
450 REM SPACE: the next section, or the next article
460 DEF FNnext(P%)
470   IF CAR% NC%=TIME+1500
480   IF P%>300 AND P%<300+NB% THEN =P%+1
490   IF P%>400 AND P%<400+NN% THEN =P%+1
500   IF P%>=500 THEN =100
510 =(P% DIV 100+1)*100
520 DEF PROCforget(P%)
530   IF P% DIV 100=2 FW%=-100000
540   IF P% DIV 100=3 FB%=-100000
550   IF P% DIV 100=4 FE%=-100000
560   IF P%=500 FI%=-100000
570 ENDPROC
580 REM After an error: a message, then the next page
590 DEF PROCfailed
600   LOCAL K%
610   IF ERR=17 CLS:END
620   CLS:PROCheader
630   PROCtitle("Page "+STR$P%+": not available")
640   PRINT TAB(0,5);CHR$129;"The page could not be fetched:"
650   PRINT CHR$131;LEFT$(FNerror,38);" (line ";ERL;")"
660   PRINT:PRINT CHR$135;"Any key: the next page"
670   K%=INKEY(500)
680   P%=FNnext(P%)
690 ENDPROC
700 DEF FNerror
710   LOCAL A$
720   REPORT
730 =""
740 REM The pages
750 DEF PROCpage(N%)
760   CLS
770   PROCheader
780   OK%=TRUE
790   IF N%=100 PROCindex ELSE IF N%=200 PROCweather ELSE IF N%=201 PROCsettings ELSE OK%=FALSE
800   IF N%>=300 AND N%<=305 PROCblog(N%-300):OK%=TRUE
810   IF N%>=400 AND N%<=410 PROCnews(N%-400):OK%=TRUE
820   IF N%=500 PROCiss:OK%=TRUE
830   IF NOT OK% PROCnopage(N%)
840 ENDPROC
850 REM Row 0: page number, name, the Ultimate's clock (as Ceefax)
860 DEF PROCheader
870   LOCAL C$
880   C$=FNclock
890   PRINT TAB(0,0);CHR$135;"P";P%;CHR$131;"U64TEXT";CHR$134;" ";
900   PRINT TAB(15,0);CHR$135;LEFT$(PN$+"    ",4);
910   PRINT TAB(20,0);
920   IF CAR% PRINT CHR$130;"C"; ELSE PRINT "  ";
930   PRINT TAB(23,0);CHR$131;MID$(C$,1,3);" ";MID$(C$,5,6);CHR$135;MID$(C$,17,5);
940 ENDPROC
950 REM The clock as OSWORD 14 gives it: "Sat,10 Oct 2026.08:42:55"
960 DEF FNclock
970   ?CB%=0:A%=14:X%=CB% MOD 256:Y%=CB% DIV 256:CALL &C7F1
980   CB%?24=13
990 =$CB%
1000 REM A double height title on rows 2-3, cyan on a blue band
1010 DEF PROCtitle(T$)
1020   LOCAL R%
1030   FOR R%=2 TO 3
1040     PRINT TAB(0,R%);CHR$132;CHR$157;CHR$141;CHR$134;T$;
1050   NEXT
1060 ENDPROC
1070 DEF PROCindex
1080   PROCtitle("U64 BBC BASIC   INDEX")
1090   PRINT TAB(0,6);CHR$131;" 200  ";CHR$135;"Weather"
1100   PRINT CHR$131;" 201  ";CHR$135;"Weather: the place"
1110   PRINT CHR$131;" 300  ";CHR$135;"idreamtin8bits.com blog"
1120   PRINT CHR$131;" 400  ";CHR$135;"News: Ars Technica"
1130   PRINT CHR$131;" 500  ";CHR$135;"Where is the ISS?"
1140   PRINT
1150   PRINT CHR$130;"Type a page number, SPACE for the next"
1160   PRINT CHR$130;"page, cursor right/left for subpages,"
1170   PRINT CHR$130;"C carousel, R reload, Q quit."
1180   PRINT TAB(0,20);CHR$134;"On a Commodore 64 Ultimate: BBC BASIC,"
1190   PRINT CHR$134;"the Ultimate's network, plain HTTP."
1200   PRINT TAB(0,23);CHR$132;CHR$157;CHR$135;"Open-Meteo, Ars Technica, ISS";
1210   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"open-notify.org";
1220 ENDPROC
1230 DEF PROCnopage(N%)
1240   PROCtitle("Page "+STR$N%)
1250   PRINT TAB(0,6);CHR$129;"There is no page ";N%;"."
1260   PRINT CHR$135;"Index: 100"
1270 ENDPROC
1280 REM While a page loads: a line at the bottom with the K read
1290 DEF PROCbusy(T$)
1300   BY%=0
1310   PRINT TAB(0,24);CHR$131;CHR$157;CHR$132;"Loading ";T$;"...";
1320 ENDPROC
1330 DEF PROCtick
1340   PRINT TAB(31,24);CHR$132;STR$(BY% DIV 1024);"K";
1350 ENDPROC
1360 DEF PROCidle
1370   PRINT TAB(0,24);SPC(39);
1380 ENDPROC
1390 REM 200 Weather: Open-Meteo's forecast as CSV (decimals intact)
1400 DEF PROCweather
1410   PROCtitle("Weather  "+LEFT$(PLACE$,20))
1420   IF TIME-FW%>60000 PROCbusy("the weather"):PROCgetweather:PROCidle
1430   PRINT TAB(0,5);CHR$131;"Now";CHR$135;FNtemp(CT);CHR$134;W$(FNwmo(CC%))
1440   PRINT CHR$130;"Wind ";CHR$135;STR$INT(CW+.5);" km/h"
1450   PROCicon(FNwmo(CC%),30,5)
1460   PRINT TAB(0,10);CHR$132;CHR$157;CHR$135;"Day        Max   Min  ";
1470   FOR I%=0 TO 2
1480     PRINT TAB(0,12+I%*2);CHR$131;D$(I%);TAB(11,12+I%*2);CHR$135;FNtemp(DH(I%));FNtemp(DL(I%));CHR$134;LEFT$(W$(FNwmo(DT%(I%))),14)
1490   NEXT
1500   PRINT TAB(0,20);CHR$130;"At ";PLACE$
1510   PRINT CHR$130;"(";LAT$;", ";LON$;")  page 201: change"
1520   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"Weather data by Open-Meteo.com";
1530 ENDPROC
1540 DEF PROCgetweather
1550   LOCAL F%,L$,I%
1560   F%=OPENIN("http://api.open-meteo.com/v1/forecast?latitude="+LAT$+"&longitude="+LON$+"&current=temperature_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=3&format=csv")
1570   IF F%=0 ERROR 100,"No weather"
1580   L$=FNskipto(F%,"time,temperature")
1590   L$=FNline(F%)
1600   CT=VAL FNcsv(L$,2):CC%=VAL FNcsv(L$,3):CW=VAL FNcsv(L$,4)
1610   L$=FNskipto(F%,"time,weather_code")
1620   FOR I%=0 TO 2
1630     L$=FNline(F%)
1640     D$(I%)=FNday(FNcsv(L$,1)):DT%(I%)=VAL FNcsv(L$,2)
1650     DH(I%)=VAL FNcsv(L$,3):DL(I%)=VAL FNcsv(L$,4)
1660   NEXT
1670   CLOSE#F%
1680   FW%=TIME
1690 ENDPROC
1700 REM In tenths with whole numbers: STR$ of 8.6 may give 8.600000001
1710 DEF FNtemp(T)
1720   LOCAL N%,A$
1730   N%=INT(ABS(T)*10+.5):A$=STR$(N% DIV 10)+"."+STR$(N% MOD 10)
1740   IF T<0 AND N%>0 A$="-"+A$
1750 =RIGHT$("     "+A$,5)+"C "
1760 REM "2026-10-10" -> "Sat 10 Oct"
1770 DEF FNday(A$)
1780   LOCAL Y%,M%,D%,W%
1790   Y%=VAL LEFT$(A$,4):M%=VAL MID$(A$,6,2):D%=VAL MID$(A$,9,2)
1800   IF M%<3 M%=M%+12:Y%=Y%-1
1810   W%=(D%+(13*(M%+1)) DIV 5+Y%+Y% DIV 4-Y% DIV 100+Y% DIV 400) MOD 7
1820   IF M%>12 M%=M%-12
1830 =MID$("SatSunMonTueWedThuFri",W%*3+1,3)+" "+STR$D%+" "+MID$("JanFebMarAprMayJunJulAugSepOctNovDec",M%*3-2,3)
1840 REM The WMO weather code -> one of 8 kinds (W$() names, icons)
1850 DEF FNwmo(C%)
1860   IF C%=0 THEN =0
1870   IF C%<=2 THEN =1
1880   IF C%=3 THEN =2
1890   IF C%<=48 THEN =3
1900   IF C%<=67 OR (C%>=80 AND C%<=82) THEN =4
1910   IF C%<=77 OR C%=85 OR C%=86 THEN =5
1920 =6
1930 DEF PROCwmo
1940   RESTORE 1960
1950   FOR I%=0 TO 6:READ W$(I%):NEXT
1960   DATA Clear,Partly cloudy,Overcast,Fog,Rain,Snow,Thunderstorm
1970 ENDPROC
1980 REM A 4 x 3 mosaic icon for kind K% at column X%, row Y%
1990 DEF PROCicon(K%,X%,Y%)
2000   LOCAL R%,A$
2010   RESTORE 2070:IF K%>0 FOR R%=1 TO K%*4:READ A$:NEXT
2020   READ IC%
2030   FOR R%=0 TO 2
2040     READ A$:PRINT TAB(X%,Y%+R%);FNmosaic(A$);
2050   NEXT
2060 ENDPROC
2070 DATA 3,"  ##  "," #### ","  ##  "
2080 DATA 3,"  ## ##"," ##### ","       "
2090 DATA 7," #### ","######","      "
2100 DATA 7,"======","======","======"
2110 DATA 6," #### ","######"," / / /"
2120 DATA 7," #### ","######"," * * *"
2130 DATA 3," #### ","######","  //  "
2140 REM An icon row in colour IC%: # full block, = striped
2150 DEF FNmosaic(A$)
2160   LOCAL O$,I%,H$
2170   O$=CHR$(144+IC%)
2180   FOR I%=1 TO LEN A$
2190     H$=MID$(A$,I%,1)
2200     IF H$="#" O$=O$+CHR$255 ELSE IF H$="=" O$=O$+CHR$243 ELSE O$=O$+H$
2210   NEXT
2220 =O$
2230 REM 400 News: Ars Technica's RSS titles; 401-410 the text, 14 lines a page
2240 DEF PROCnews(G%)
2250   LOCAL I%
2260   IF TIME-FE%>60000 PROCbusy("the news"):PROCgetnews:PROCidle
2270   IF G%>0 PROCarticle(G%):ENDPROC
2280   PROCtitle("News   Ars Technica")
2290   FOR I%=0 TO NN%-1
2300     IF I%<NN% PRINT TAB(0,5+I%*2);CHR$131;STR$(401+I%);" ";CHR$135;FNshort(FNget(&4A000+I%*256),33)
2310   NEXT
2320   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"Source: arstechnica.com";
2330 ENDPROC
2340 DEF PROCarticle(G%)
2350   IF G%>NN% PROCnopage(400+G%):ENDPROC
2360   PROCtitle("News   Ars Technica")
2370   PROCwrap(FNget(&4A000+(G%-1)*256),5,1)
2380   PROCtext(G%-1,400+G%)
2390   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"Source: arstechnica.com";
2400 ENDPROC
2410 REM Text N% from the REU, subpage SP% (14 lines from row 9), page Q%
2420 DEF PROCtext(N%,Q%)
2430   LOCAL I%,M%,L%
2440   M%=(AL%(N%)+13) DIV 14:IF M%=0 M%=1
2450   IF SP%>M% SP%=1
2460   FOR I%=0 TO 13
2470     L%=(SP%-1)*14+I%
2480     IF L%<AL%(N%) OSCLI "SRREAD &"+STR$~LB%+" +40 &"+STR$~(FNbase(N%)+L%*40):PRINT TAB(1,9+I%);$LB%;
2490   NEXT
2500   PRINT TAB(0,23);CHR$130;STR$Q%;"/";STR$SP%;" of ";STR$M%;CHR$134;"cursor right: more";
2510 ENDPROC
2520 REM Texts' lines in the REU, 40 bytes each: news 0-9 at &40000 (4K,
2530 REM 56 lines), blog posts 10-14 at &50000 (16K, 400 lines)
2540 DEF FNbase(N%)
2550   IF N%<10 THEN =&40000+N%*&1000
2560 =&50000+(N%-10)*&4000
2570 REM Over TCP: the 76 KB feed is too big for the HTTP reader
2580 DEF PROCgetnews
2590   LOCAL F%,A$
2600   F%=OPENUP("TCP:feeds.arstechnica.com:80")
2610   IF F%=0 ERROR 100,"No news"
2620   PROCsend(F%,"GET /arstechnica/index HTTP/1.0"):PROCsend(F%,"Host: feeds.arstechnica.com"):PROCsend(F%,"")
2630   NN%=0
2640   A$=FNtag(F%):A$=FNtag(F%)
2650   REPEAT
2660     A$=FNtag(F%)
2670     IF A$<>"" PROCput256(A$,&4A000+NN%*256):PROCread(F%,NN%):NN%=NN%+1
2680   UNTIL NN%=10 OR EOF#F%
2690   CLOSE#F%
2700   FE%=TIME
2710 ENDPROC
2720 REM An article's text wrapped into the REU: &40000+N%*&1000, 40 a line
2730 DEF PROCread(F%,N%)
2740   LOCAL C%,E%
2750   AL%(N%)=0:AW$="":AT$="":AB%=TRUE
2760   IF NOT FNfind(F%,"<content:encoded>") ENDPROC
2770   REPEAT
2780     C%=BGET#F%:BY%=BY%+1:IF (BY% AND 511)=0 PROCtick
2790     IF C%=60 PROCtagin(F%,N%):C%=256
2800     IF C%=38 AW$=AW$+FNent(F%):C%=256
2810     IF C%>127 AND C%<256 AW$=AW$+FNutf(F%,C%):C%=256
2820     IF C%=93 E%=E%+1 ELSE IF C%=62 AND E%>1 C%=-1 ELSE IF C%<256 E%=0
2830     IF C%>32 AND C%<256 AND LEN AW$<38 AW$=AW$+CHR$C%
2840     IF C%>=0 AND C%<=32 PROCword(N%)
2850   UNTIL C%=-1 OR EOF#F% OR AL%(N%)>=56
2860   IF RIGHT$(AW$,2)="]]" AW$=LEFT$(AW$,LEN AW$-2)
2870   PROCword(N%):PROCemit(N%)
2880 ENDPROC
2890 REM A tag: paragraph and list ends break the line
2900 DEF PROCtagin(F%,N%)
2910   LOCAL C%,T$
2920   REPEAT
2930     C%=BGET#F%:IF LEN T$<2 T$=T$+CHR$C%
2940   UNTIL C%=62 OR EOF#F%
2950   IF T$="/p" OR T$="/h" OR T$="br" OR T$="li" OR T$="/l" PROCword(N%):PROCemit(N%)
2960   IF T$="/p" OR T$="/h" PROCblank(N%)
2970 ENDPROC
2980 REM The word AW$ onto the line AT$ (a full line goes to the REU first)
2990 DEF PROCword(N%)
3000   IF AW$="" ENDPROC
3010   IF LEN AT$+LEN AW$>37 PROCemit(N%)
3020   IF AT$<>"" AT$=AT$+" "
3030   AT$=AT$+AW$:AW$=""
3040 ENDPROC
3050 REM A line (or one empty line) to the REU
3060 DEF PROCemit(N%)
3070   IF AT$="" ENDPROC
3080   PROCput(N%):AB%=FALSE
3090 ENDPROC
3100 DEF PROCblank(N%)
3110   IF AB% ENDPROC
3120   AT$="":PROCput(N%):AB%=TRUE
3130 ENDPROC
3140 DEF PROCput(N%)
3150   IF AL%(N%)>=56-(N%>9)*344 ENDPROC
3160   $LB%=AT$
3170   OSCLI "SRWRITE &"+STR$~LB%+" +40 &"+STR$~(FNbase(N%)+AL%(N%)*40)
3180   AL%(N%)=AL%(N%)+1:AT$=""
3190 ENDPROC
3200 REM An HTML entity after & (up to ;): the few that occur as text
3210 DEF FNent(F%)
3220   LOCAL C%,A$
3230   REPEAT
3240     C%=BGET#F%:IF C%<>59 A$=A$+CHR$C%
3250   UNTIL C%=59 OR LEN A$>8 OR EOF#F%
3260   IF A$="amp" THEN ="&"
3270   IF A$="quot" OR A$="#8220" OR A$="#8221" THEN =CHR$34
3280   IF A$="lt" THEN ="<"
3290   IF A$="gt" THEN =">"
3300   IF A$="#8217" OR A$="#8216" OR A$="#039" OR A$="#39" THEN ="'"
3310   IF A$="#8211" OR A$="#8212" THEN ="-"
3320   IF A$="nbsp" OR A$="#160" THEN =" "
3330 =""
3340 REM UTF-8: quotes and dashes as ASCII, the rest left out
3350 DEF FNutf(F%,C%)
3360   LOCAL B%,D%
3370   IF C%<&C0 THEN =""
3380   IF C%<&E0 B%=BGET#F%:=""
3390   B%=BGET#F%:D%=BGET#F%
3400   IF C%>=&F0 B%=BGET#F%:=""
3410   IF C%<>&E2 THEN =""
3420   IF D%=&98 OR D%=&99 THEN ="'"
3430   IF D%=&9C OR D%=&9D THEN =CHR$34
3440   IF D%=&93 OR D%=&94 THEN ="-"
3450   IF D%=&A6 THEN ="..."
3460 =""
3470 REM Texts in the REU, 256 bytes each (the program's memory is short in
3480 REM MODE 7): news titles &4A000, blog titles &4C000, slugs &4D000
3490 DEF PROCput256(A$,R%)
3500   $SB%=A$:OSCLI "SRWRITE &"+STR$~SB%+" +256 &"+STR$~R%
3510 ENDPROC
3520 DEF FNget(R%)
3530   OSCLI "SRREAD &"+STR$~SB%+" +256 &"+STR$~R%
3540 =$SB%
3550 REM A$ cut to at most N% characters at a word, with ".." when cut
3560 DEF FNshort(A$,N%)
3570   LOCAL P%
3580   IF LEN A$<=N% THEN =A$
3590   A$=LEFT$(A$,N%-2)
3600   P%=LEN A$
3610   REPEAT P%=P%-1:UNTIL P%<N% DIV 2 OR MID$(A$,P%,1)=" "
3620   IF P%>=N% DIV 2 A$=LEFT$(A$,P%-1)
3630 =A$+".."
3640 REM A line to a TCP channel, CR LF at the end
3650 DEF PROCsend(F%,A$)
3660   LOCAL I%
3670   IF A$<>"" FOR I%=1 TO LEN A$:BPUT#F%,ASC MID$(A$,I%,1):NEXT
3680   BPUT#F%,13:BPUT#F%,10
3690 ENDPROC
3700 REM The next <title>'s text (in CDATA up to the first ])
3710 DEF FNtag(F%)
3720   LOCAL A$,C%,E%
3730   IF NOT FNfind(F%,"<title>") THEN =""
3740   C%=BGET#F%:E%=60
3750   IF C%=60 PROCskip(F%,8):C%=BGET#F%:E%=93
3760   REPEAT
3770     IF C%<>E% AND LEN A$<120 A$=A$+FNascii(C%)
3780     IF C%<>E% C%=BGET#F%
3790   UNTIL C%=E% OR EOF#F%
3800 =FNentities(A$)
3810 REM UTF-8: a lead byte (&E2: quotes, dashes) as ', the rest dropped
3820 DEF FNascii(C%)
3830   IF C%<128 THEN =CHR$C%
3840   IF C%=&E2 THEN ="'"
3850 =""
3860 DEF PROCskip(F%,N%)
3870   LOCAL I%,C%
3880   FOR I%=1 TO N%:C%=BGET#F%:NEXT
3890 ENDPROC
3900 REM Read the channel on until the text K$ has gone by
3910 DEF FNfind(F%,K$)
3920   LOCAL M%,C%
3930   M%=1
3940   REPEAT
3950     C%=BGET#F%:BY%=BY%+1:IF (BY% AND 511)=0 PROCtick
3960     IF C%=ASC MID$(K$,M%,1) M%=M%+1 ELSE IF C%=ASC K$ M%=2 ELSE M%=1
3970   UNTIL M%>LEN K$ OR EOF#F%
3980 =M%>LEN K$
3990 REM A$ word-wrapped in 38 columns from row R%, white or yellow
4000 DEF PROCwrap(A$,R%,Y%)
4010   LOCAL W$,L$,P%
4020   L$=""
4030   REPEAT
4040     P%=INSTR(A$+" "," ")
4050     W$=LEFT$(A$,P%-1):A$=MID$(A$,P%+1)
4060     IF LEN L$+LEN W$>37 PROCrow(L$,R%,Y%):R%=R%+1:L$=""
4070     IF L$<>"" L$=L$+" "
4080     L$=L$+W$
4090   UNTIL A$=""
4100   IF L$<>"" PROCrow(L$,R%,Y%)
4110 ENDPROC
4120 DEF PROCrow(L$,R%,Y%)
4130   IF R%<23 PRINT TAB(0,R%);CHR$(135-4*Y%);L$;
4140 ENDPROC
4150 DEF FNlines(A$)
4160 =(LEN A$+37) DIV 38
4170 REM HTML entities: &amp; &quot; &lt; &gt; &#39; &#039;
4180 DEF FNentities(A$)
4190   A$=FNswap(A$,"&amp;","&"):A$=FNswap(A$,"&quot;",CHR$34)
4200   A$=FNswap(A$,"&lt;","<"):A$=FNswap(A$,"&gt;",">")
4210 =FNswap(FNswap(A$,"&#039;","'"),"&#39;","'")
4220 DEF FNswap(A$,F$,T$)
4230   LOCAL P%
4240   REPEAT
4250     P%=INSTR(A$,F$):IF P% A$=LEFT$(A$,P%-1)+T$+MID$(A$,P%+LEN F$)
4260   UNTIL P%=0
4270 =A$
4280 REM 300 The blog (the BBS server's feed); 301-305 a post (G%: not A%,
4290 REM X%, Y%, which the OSWORD calls set)
4300 DEF PROCblog(G%)
4310   LOCAL I%,R%,T$
4320   IF TIME-FB%>60000 PROCbusy("the blog"):PROCgetblog:PROCidle
4330   PROCtitle("idreamtin8bits.com")
4340   IF G%>0 PROCpost(G%):ENDPROC
4350   R%=5
4360   FOR I%=0 TO NB%-1
4370     IF R%<22 AND I%<NB% T$=FNget(&4C000+I%*256):PRINT TAB(0,R%);CHR$131;STR$(301+I%);" ";CHR$130;BD$(I%):PROCwrap(T$,R%+1,0):R%=R%+FNlines(T$)+2
4380   NEXT
4390   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"bbs.idreamtin8bits.com/u64-feed.json";
4400 ENDPROC
4410 DEF PROCpost(G%)
4420   IF G%>NB% PROCnopage(300+G%):ENDPROC
4430   IF AL%(9+G%)=0 PROCbusy("the post"):PROCgetpost(G%):PROCidle
4440   PRINT TAB(0,5);CHR$130;BD$(G%-1)
4450   PROCwrap(FNget(&4C000+(G%-1)*256),6,1)
4460   PROCtext(9+G%,300+G%)
4470   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"bbs.idreamtin8bits.com/u64-feed";
4480 ENDPROC
4490 REM A post's text: u64-feed/<slug>.txt on the BBS server, wrapped there
4500 REM at 38 columns; over TCP (it can be longer than the HTTP reader takes)
4510 DEF PROCgetpost(G%)
4520   LOCAL F%,N%
4530   N%=9+G%:AL%(N%)=0
4540   F%=OPENUP("TCP:bbs.idreamtin8bits.com:80")
4550   IF F%=0 ERROR 100,"No post"
4560   PROCsend(F%,"GET /u64-feed/"+FNget(&4D000+(G%-1)*256)+".txt HTTP/1.0"):PROCsend(F%,"Host: bbs.idreamtin8bits.com"):PROCsend(F%,"")
4570   REPEAT AT$=FNline(F%):UNTIL AT$="" OR EOF#F%
4580   REPEAT
4590     AT$=FNline(F%):PROCput(N%)
4600   UNTIL EOF#F% OR AL%(N%)>=400
4610   CLOSE#F%
4620 ENDPROC
4630 DEF PROCgetblog
4640   LOCAL I%,P$
4650   OSCLI "JSON GET http://bbs.idreamtin8bits.com/u64-feed.json"
4660   NB%=FNjsoncount("blogs"):IF NB%>5 NB%=5
4670   FOR I%=0 TO NB%-1
4680     IF I%<NB% P$="blogs/%"+STR$I%+"/":PROCput256(FNjson(P$+"title"),&4C000+I%*256):BD$(I%)=FNday(FNjson(P$+"date")):AL%(10+I%)=0:PROCput256(FNjson(P$+"slug"),&4D000+I%*256)
4690   NEXT
4700   FB%=TIME
4710 ENDPROC
4720 REM 500 The ISS: Natural Earth map in mosaics, 10 degrees a cell; hold
4730 REM graphics keep it unbroken around the red ISS and yellow trail
4740 DEF PROCiss
4750   LOCAL R%
4760   IF TIME-FI%>1000 PROCbusy("the position"):PROCgetiss
4770   PROCtitle("Where is the ISS?")
4780   FOR R%=0 TO 15
4790     PRINT TAB(0,5+R%);FNmaprow(R%);
4800   NEXT
4810   PRINT TAB(0,22);CHR$131;"Lat ";FNdeg(ILAT);"  Lon ";FNdeg(ILON);"     "
4820   PRINT TAB(0,23);CHR$129;"ISS";CHR$135;"now  ";CHR$131;"before";CHR$135;"(every 10 s)"
4830   PROCidle:PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"open-notify.org";
4840 ENDPROC
4850 REM The position, and a new cell for the trail (the last 12)
4860 DEF PROCgetiss
4870   LOCAL X%,Y%,I%
4880   OSCLI "JSON GET http://api.open-notify.org/iss-now.json"
4890   ILAT=VAL FNjson("iss_position/latitude")
4900   ILON=VAL FNjson("iss_position/longitude")
4910   FI%=TIME
4920   X%=INT((ILON+180)/10):Y%=INT((80-ILAT)/10)
4930   IF X%>35 X%=35
4940   IF TN%>0 IF TX%(0)=X% AND TY%(0)=Y% ENDPROC
4950   IF TN%<12 TN%=TN%+1
4960   IF TN%>1 FOR I%=TN%-1 TO 1 STEP -1:TX%(I%)=TX%(I%-1):TY%(I%)=TY%(I%-1):NEXT
4970   REM (the IF: a FOR loop runs at least once)
4980   TX%(0)=X%:TY%(0)=Y%
4990 ENDPROC
5000 REM Map row R%, the trail and the ISS marked
5010 DEF FNmaprow(R%)
5020   LOCAL O$,A$,I%,B%
5030   RESTORE 5280
5040   IF R%>0 FOR I%=1 TO R%:READ A$:NEXT
5050   READ A$
5060   O$=CHR$148+CHR$157+CHR$158+CHR$146
5070   FOR I%=1 TO 36
5080     B%=ASC MID$(A$,I%,1)-48:O$=O$+CHR$(160+(B% AND 31)+(B% AND 32)*2)
5090   NEXT
5100   IF TN%=0 THEN =O$
5110   FOR I%=TN%-1 TO 0 STEP -1
5120     IF TY%(I%)=R% O$=FNmark(O$,TX%(I%)+4,147+2*(I%=0))
5130   NEXT
5140 =O$
5150 REM Mark column X% in graphics colour C% (145 red, 147 yellow): the
5160 REM code in the column before, green again after
5170 DEF FNmark(O$,X%,C%)
5180   O$=LEFT$(O$,X%-1)+CHR$C%+CHR$255+MID$(O$,X%+2)
5190   IF X%<39 IF ASC MID$(O$,X%+2,1)>159 O$=LEFT$(O$,X%+1)+CHR$146+MID$(O$,X%+3)
5200 =O$
5210 REM A position in tenths of a degree
5220 DEF FNdeg(D)
5230   LOCAL N%,A$
5240   N%=INT(ABS(D)*10+.5):A$=STR$(N% DIV 10)+"."+STR$(N% MOD 10)
5250   IF D<0 A$="-"+A$
5260 =A$
5270 REM The map: CHR$(48+bits) -> mosaic 160+(b AND 31)+(b AND 32)*2
5280 DATA "00000Xllooc3_ooo0003100HP`hnmd`Pd000"
5290 DATA "<^ooooooO?kE:o3840PnoolooooooooooooO"
5300 DATA "00303oooolom@0000ljgoooooooooooo@:10"
5310 DATA "00000Zooooo=10000boooog[ooooooo7E000"
5320 DATA "000002_ooo5000000kl@Coonoooooo3<0000"
5330 DATA "0000002_E2@00000Xooooooo;ooooO000000"
5340 DATA "00000002;5R00000^oooooO30Z1:o0D00000"
5350 DATA "0000000002ool0002?;oooO00000Dh100000"
5360 DATA "0000000000ooomD0000_oo0000001CA9d400"
5370 DATA "0000000000;ooo10000nooX0000000heD000"
5380 DATA "00000000000oo700000ZoE2000000ZoooD00"
5390 DATA "0000000000Xo70000000300000000:3;o10P"
5400 DATA "0000000000ZE000000000000000000002081"
5410 DATA "000000000024000000000000000000000000"
5420 DATA "00000000000H0000000000```0```````000"
5430 DATA "00``llllllN70@P`loooooooooooooooooG0"
5440 REM 201 The weather's place: Open-Meteo geocoding, or AUTO (ip-api.com)
5450 DEF PROCsettings
5460   LOCAL A$,N%,K%
5470   PROCtitle("Settings: the weather")
5480   PRINT TAB(0,5);CHR$131;"Now: ";CHR$135;LEFT$(PLACE$,28)
5490   PRINT TAB(0,7);CHR$130;"Type a place name, or AUTO for the"
5500   PRINT CHR$130;"place of this internet connection;"
5510   PRINT CHR$130;"RETURN alone keeps it."
5520   PRINT TAB(0,11);CHR$134;"Place? ";
5530   INPUT ""A$
5540   IF A$="" ENDPROC
5550   IF A$="AUTO" OR A$="auto" PROCbusy("the place"):PROCauto:PROCsave:PROCidle:FW%=-100000:PRINT TAB(0,13);CHR$130;"Saved: ";LEFT$(PLACE$,28):ENDPROC
5560   PROCbusy("places"):N%=FNgeocode(A$):PROCidle
5570   IF N%=0 PRINT TAB(0,13);CHR$129;"Not found: ";A$:ENDPROC
5580   FOR K%=0 TO N%-1
5590     PRINT TAB(0,13+K%);CHR$131;K%+1;CHR$135;LEFT$(R$(K%),30)
5600   NEXT
5610   PRINT TAB(0,13+N%+1);CHR$134;"Which (1-";N%;")? ";
5620   K%=GET-49
5630   IF K%<0 OR K%>=N% ENDPROC
5640   PLACE$=R$(K%):LAT$=RL$(K%):LON$=RO$(K%)
5650   PROCsave:FW%=-100000
5660   PRINT TAB(0,22);CHR$130;"Saved: ";LEFT$(PLACE$,28)
5670 ENDPROC
5680 REM Up to 5 places for name A$: R$() "name, CC", RL$() lat, RO$() lon
5690 DEF FNgeocode(A$)
5700   LOCAL F%,N%,V$
5710   REM (over TCP: the HTTP reader hangs on longer replies)
5720   F%=OPENUP("TCP:geocoding-api.open-meteo.com:80")
5730   IF F%=0 THEN =0
5740   PROCsend(F%,"GET /v1/search?count=5&name="+FNurl(A$)+" HTTP/1.0"):PROCsend(F%,"Host: geocoding-api.open-meteo.com"):PROCsend(F%,"")
5750   REPEAT
5760     V$=FNvalue(F%,"name")
5770     IF V$<>"" R$(N%)=V$:RL$(N%)=FNvalue(F%,"latitude"):RO$(N%)=FNvalue(F%,"longitude"):R$(N%)=R$(N%)+", "+FNvalue(F%,"country_code"):N%=N%+1
5780   UNTIL V$="" OR N%=5
5790   CLOSE#F%
5800 =N%
5810 DEF PROCauto
5820   LOCAL F%
5830   F%=OPENIN("http://ip-api.com/json/")
5840   IF F%=0 ERROR 100,"No place"
5850   PLACE$=FNvalue(F%,"country")
5860   PLACE$=FNvalue(F%,"city")+", "+PLACE$
5870   LAT$=FNvalue(F%,"lat"):LON$=FNvalue(F%,"lon")
5880   CLOSE#F%
5890 ENDPROC
5900 REM Raw JSON: the value after "key": ("" if none)
5910 DEF FNvalue(F%,K$)
5920   LOCAL C%,A$,Q%
5930   IF NOT FNfind(F%,CHR$34+K$+CHR$34+":") THEN =""
5940   C%=BGET#F%
5950   IF C%=34 Q%=TRUE:C%=BGET#F%
5960   REPEAT
5970     IF Q% AND C%=34 THEN C%=-1 ELSE IF NOT Q% AND (C%=44 OR C%=125) THEN C%=-1 ELSE A$=A$+CHR$C%:C%=BGET#F%
5980   UNTIL C%=-1 OR EOF#F% OR LEN A$>40
5990 =A$
6000 REM A name for a URL: spaces as %20
6010 DEF FNurl(A$)
6020   LOCAL P%
6030   REPEAT
6040     P%=INSTR(A$," ")
6050     IF P% A$=LEFT$(A$,P%-1)+"%20"+MID$(A$,P%+1)
6060   UNTIL P%=0
6070 =A$
6080 REM U64TEXT.CFG: place, latitude, longitude
6090 DEF PROCload
6100   LOCAL F%
6110   F%=OPENIN "U64TEXT.CFG"
6120   IF F%=0 PROCauto:PROCsave:ENDPROC
6130   INPUT#F%,PLACE$,LAT$,LON$
6140   CLOSE#F%
6150 ENDPROC
6160 DEF PROCsave
6170   LOCAL F%
6180   F%=OPENOUT "U64TEXT.CFG"
6190   PRINT#F%,PLACE$,LAT$,LON$
6200   CLOSE#F%
6210 ENDPROC
6220 REM Text helpers: lines of a channel, CSV fields
6230 DEF FNline(F%)
6240   LOCAL A$,C%
6250   REPEAT
6260     C%=BGET#F%:BY%=BY%+1:IF (BY% AND 511)=0 PROCtick
6270     IF C%>=32 AND LEN A$<200 A$=A$+CHR$C%
6280   UNTIL C%=10 OR EOF#F%
6290 =A$
6300 DEF FNskipto(F%,K$)
6310   LOCAL A$
6320   REPEAT A$=FNline(F%):UNTIL LEFT$(A$,LEN K$)=K$ OR EOF#F%
6330 =A$
6340 REM Field N% (from 1) of a comma-separated line
6350 DEF FNcsv(A$,N%)
6360   LOCAL I%,P%
6370   IF N%>1 FOR I%=2 TO N%:P%=INSTR(A$+",",","):A$=MID$(A$,P%+1):NEXT
6380   REM (a FOR loop runs at least once: hence the IF)
6390   P%=INSTR(A$+",",",")
6400 =LEFT$(A$,P%-1)
29990 REM demos/net/JSONLIB, merged (see there)
30000 DEF PROCjsoninit
30010   DIM JB% 8,JP% 255,JS% 255
30020 ENDPROC
30030 REM The value at P$ as text ("" if there is none)
30040 DEF FNjson(P$)
30050   PROCjsonask(P$)
30060   JS%?(JB%?7)=13
30070 =$JS%
30080 REM The value at P$ as a number
30090 DEF FNjsonnum(P$)
30100 =VAL FNjson(P$)
30110 REM The number of entries of the object or array at P$
30120 DEF FNjsoncount(P$)
30130   PROCjsonask(P$)
30140 =JB%?8
30150 REM The type at P$: 0 none 1 number 2 boolean 3 string 4 object 5 array
30160 DEF FNjsontype(P$)
30170   PROCjsonask(P$)
30180 =JB%?6
30190 DEF PROCjsonask(P$)
30200   $JP%=P$
30210   JB%?0=JP% MOD 256:JB%?1=JP% DIV 256:JB%?2=LEN P$
30220   JB%?3=JS% MOD 256:JB%?4=JS% DIV 256:JB%?5=255
30230   A%=&70:X%=JB% MOD 256:Y%=JB% DIV 256
30240   CALL &C7F1
30250 ENDPROC
