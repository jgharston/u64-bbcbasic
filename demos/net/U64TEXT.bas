10 REM U64TEXT: a Ceefax-style information service in MODE 7
20 REM U64 BBC BASIC network demo (docs/DESIGN_NETWORK.md section 7):
30 REM weather (Open-Meteo), news (CNN RSS), the idreamtin8bits.com blog,
40 REM the ISS on a world map; all over plain HTTP through the Ultimate.
50 REM Keys: three digits choose a page, SPACE the next one, C carousel,
60 REM R reload, Q quit. Page 199: the weather's place (U64TEXT.CFG).
70 REM Firmware note: the Ultimate's JSON reader drops decimals, so
80 REM weather and places are read as text (CSV, or the raw JSON).
90 :
100 REM MODE here, at the top: BASIC refuses MODE inside a PROC or FN
105 MODE 7
110 PROCinit
115 ON ERROR PROCfailed:PROCrun:END
120 PROCrun
130 END
140 :
200 DEF PROCinit
210   DIM CB% 30,W$(15),D$(2),DT%(2),DH(2),DL(2),N$(9),B$(4),BD$(4),BS$(4)
220   DIM M$(15),R$(4),RL$(4),RO$(4)
240   PROCjsoninit
250   P%=100:CAR%=FALSE:NC%=0:PN$=""
260   FW%=-100000:FE%=-100000:FB%=-100000:FI%=-100000
270   PROCwmo:PROCmap
280   PROCload
290 ENDPROC
300 :
310 REM The main loop: the page, then keys; the clock every second
320 DEF PROCrun
330   LOCAL K%
340   REPEAT
350     PROCpage(P%)
360     REPEAT
370       PROCheader
380       K%=INKEY(100)
390       IF CAR% AND TIME>NC% K%=32
400       IF K%>=48 AND K%<=57 PROCdigit(K%)
410     UNTIL K%=32 OR K%=13 OR K%=67 OR K%=99 OR K%=82 OR K%=114 OR K%=81 OR K%=113 OR LEN PN$=4
420     IF K%=32 P%=FNnext(P%)
430     IF K%=67 OR K%=99 CAR%=NOT CAR%:NC%=TIME+1500
440     IF K%=82 OR K%=114 PROCforget(P%)
450     IF LEN PN$=4 P%=VAL MID$(PN$,2):PN$=""
460   UNTIL K%=81 OR K%=113
470   CLS
480 ENDPROC
490 :
500 REM Typed digits: three make a page number (PN$ = "P" + digits)
510 DEF PROCdigit(K%)
520   IF PN$="" PN$="P"
530   PN$=PN$+CHR$K%
540 ENDPROC
550 :
560 DEF FNnext(P%)
570   IF CAR% NC%=TIME+1500
580   IF P%>=104 THEN =100
590 =P%+1
600 :
610 DEF PROCforget(P%)
620   IF P%=101 FW%=-100000
630   IF P%=102 FE%=-100000
640   IF P%=103 FB%=-100000
650   IF P%=104 FI%=-100000
660 ENDPROC
670 :
700 REM After an error (no network, a server away): a message, a key
710 REM or 5 seconds, then the next page (the main loop starts again)
720 DEF PROCfailed
725   LOCAL K%
730   IF ERR=17 CLS:END
735   CLS:PROCheader
740   PROCtitle("Page "+STR$P%+": not available")
750   PRINT TAB(0,5);CHR$129;"The page could not be fetched:"
760   PRINT CHR$131;LEFT$(FNerror,38);" (line ";ERL;")"
770   PRINT:PRINT CHR$135;"Any key: the next page"
780   K%=INKEY(500)
790   P%=FNnext(P%)
795 ENDPROC
800 :
810 DEF FNerror
820   LOCAL A$
830   REPORT
840 =""
850 :
900 REM ------------------------------------------------------------------
910 REM The pages
920 DEF PROCpage(N%)
930   CLS
940   PROCheader
950   IF N%=100 PROCindex
960   IF N%=101 PROCweather
970   IF N%=102 PROCnews
980   IF N%=103 PROCblog
990   IF N%=104 PROCiss
1000   IF N%=199 PROCsettings
1010   IF N%<100 OR (N%>104 AND N%<>199) PROCnopage(N%)
1020 ENDPROC
1030 :
1040 REM Row 0: page number, name, the Ultimate's clock (as Ceefax)
1050 DEF PROCheader
1060   LOCAL C$
1070   C$=FNclock
1080   PRINT TAB(0,0);CHR$135;"P";P%;CHR$131;"U64TEXT";CHR$134;" ";
1090   PRINT TAB(15,0);CHR$135;LEFT$(PN$+"    ",4);
1100   PRINT TAB(20,0);
1110   IF CAR% PRINT CHR$130;"C"; ELSE PRINT "  ";
1120   PRINT TAB(23,0);CHR$131;MID$(C$,1,3);" ";MID$(C$,5,6);CHR$135;MID$(C$,17,5);
1130 ENDPROC
1140 :
1150 REM The clock as OSWORD 14 gives it: "Sat,10 Oct 2026.08:42:55"
1160 DEF FNclock
1170   ?CB%=0:A%=14:X%=CB% MOD 256:Y%=CB% DIV 256:CALL &C7F1
1180   CB%?24=13
1190 =$CB%
1200 :
1210 REM A double height title on rows 2-3, cyan on a blue band
1220 DEF PROCtitle(T$)
1230   LOCAL R%
1240   FOR R%=2 TO 3
1250     PRINT TAB(0,R%);CHR$132;CHR$157;CHR$141;CHR$134;T$;
1260   NEXT
1270 ENDPROC
1280 :
1300 DEF PROCindex
1310   PROCtitle("U64 BBC BASIC   INDEX")
1320   PRINT TAB(0,6);CHR$131;" 101  ";CHR$135;"Weather"
1330   PRINT CHR$131;" 102  ";CHR$135;"News headlines"
1340   PRINT CHR$131;" 103  ";CHR$135;"idreamtin8bits.com"
1350   PRINT CHR$131;" 104  ";CHR$135;"Where is the ISS?"
1360   PRINT CHR$131;" 199  ";CHR$135;"Settings: the weather's place"
1370   PRINT
1380   PRINT CHR$130;"Type a page number, SPACE for the next"
1390   PRINT CHR$130;"page, C for the carousel, R to reload,"
1400   PRINT CHR$130;"Q to quit."
1410   PRINT TAB(0,20);CHR$134;"On a Commodore 64 Ultimate: BBC BASIC,"
1420   PRINT CHR$134;"the Ultimate's network, plain HTTP."
1430   PRINT TAB(0,23);CHR$132;CHR$157;CHR$135;"Open-Meteo, Ars Technica, ISS";
1440   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"open-notify.org";
1450 ENDPROC
1460 :
1470 DEF PROCnopage(N%)
1480   PROCtitle("Page "+STR$N%)
1490   PRINT TAB(0,6);CHR$129;"There is no page ";N%;"."
1500   PRINT CHR$135;"Index: 100"
1510 ENDPROC
1520 :
2000 REM ------------------------------------------------------------------
2010 REM 101 Weather: Open-Meteo's forecast as CSV (decimals intact):
2020 REM a header line, then current (time, temp, code, wind), then 3
2030 REM daily lines (date, code, max, min)
2040 DEF PROCweather
2050   PROCtitle("Weather  "+LEFT$(PLACE$,20))
2060   IF TIME-FW%>60000 PROCgetweather
2070   PRINT TAB(0,5);CHR$131;"Now";CHR$135;FNtemp(CT);CHR$134;W$(FNwmo(CC%))
2080   PRINT CHR$130;"Wind ";CHR$135;STR$INT(CW+.5);" km/h"
2090   PROCicon(FNwmo(CC%),30,5)
2100   PRINT TAB(0,10);CHR$132;CHR$157;CHR$135;"Day        Max   Min  ";
2110   FOR I%=0 TO 2
2120     PRINT TAB(0,12+I%*2);CHR$131;D$(I%);TAB(11,12+I%*2);CHR$135;FNtemp(DH(I%));FNtemp(DL(I%));CHR$134;LEFT$(W$(FNwmo(DT%(I%))),14)
2130   NEXT
2140   PRINT TAB(0,20);CHR$130;"At ";PLACE$
2150   PRINT CHR$130;"(";LAT$;", ";LON$;")  page 199: change"
2160   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"Weather data by Open-Meteo.com";
2170 ENDPROC
2180 :
2190 DEF PROCgetweather
2200   LOCAL F%,L$,I%
2210   F%=OPENIN("http://api.open-meteo.com/v1/forecast?latitude="+LAT$+"&longitude="+LON$+"&current=temperature_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=3&format=csv")
2220   IF F%=0 ERROR 100,"No weather"
2230   L$=FNskipto(F%,"time,temperature")
2240   L$=FNline(F%)
2250   CT=VAL FNcsv(L$,2):CC%=VAL FNcsv(L$,3):CW=VAL FNcsv(L$,4)
2260   L$=FNskipto(F%,"time,weather_code")
2270   FOR I%=0 TO 2
2280     L$=FNline(F%)
2290     D$(I%)=FNday(FNcsv(L$,1)):DT%(I%)=VAL FNcsv(L$,2)
2300     DH(I%)=VAL FNcsv(L$,3):DL(I%)=VAL FNcsv(L$,4)
2310   NEXT
2320   CLOSE#F%
2330   FW%=TIME
2340 ENDPROC
2350 :
2355 REM In tenths with whole numbers: STR$ of 8.6 may give 8.600000001
2360 DEF FNtemp(T)
2370   LOCAL N%,A$
2380   N%=INT(ABS(T)*10+.5):A$=STR$(N% DIV 10)+"."+STR$(N% MOD 10)
2390   IF T<0 AND N%>0 A$="-"+A$
2400 =RIGHT$("     "+A$,5)+"C "
2410 :
2420 REM "2026-10-10" -> "Sat 10 Oct"
2430 DEF FNday(A$)
2440   LOCAL Y%,M%,D%,W%
2450   Y%=VAL LEFT$(A$,4):M%=VAL MID$(A$,6,2):D%=VAL MID$(A$,9,2)
2460   IF M%<3 M%=M%+12:Y%=Y%-1
2470   W%=(D%+(13*(M%+1)) DIV 5+Y%+Y% DIV 4-Y% DIV 100+Y% DIV 400) MOD 7
2480   IF M%>12 M%=M%-12
2490 =MID$("SatSunMonTueWedThuFri",W%*3+1,3)+" "+STR$D%+" "+MID$("JanFebMarAprMayJunJulAugSepOctNovDec",M%*3-2,3)
2500 :
2510 REM The WMO weather code -> one of 8 kinds (W$() names, icons)
2520 DEF FNwmo(C%)
2530   IF C%=0 THEN =0
2540   IF C%<=2 THEN =1
2550   IF C%=3 THEN =2
2560   IF C%<=48 THEN =3
2570   IF C%<=67 OR (C%>=80 AND C%<=82) THEN =4
2580   IF C%<=77 OR C%=85 OR C%=86 THEN =5
2590 =6
2600 :
2610 DEF PROCwmo
2620   RESTORE 2640
2630   FOR I%=0 TO 6:READ W$(I%):NEXT
2640   DATA Clear,Partly cloudy,Overcast,Fog,Rain,Snow,Thunderstorm
2650 ENDPROC
2660 :
2670 REM A 4 x 3 mosaic icon for kind K% at column X%, row Y%
2680 DEF PROCicon(K%,X%,Y%)
2690   LOCAL R%,A$
2700   RESTORE 2760:IF K%>0 FOR R%=1 TO K%*4:READ A$:NEXT
2710   READ IC%
2720   FOR R%=0 TO 2
2730     READ A$:PRINT TAB(X%,Y%+R%);FNmosaic(A$);
2740   NEXT
2750 ENDPROC
2760 DATA 3,"  ##  "," #### ","  ##  "
2770 DATA 3,"  ## ##"," ##### ","       "
2780 DATA 7," #### ","######","      "
2790 DATA 7,"======","======","======"
2800 DATA 6," #### ","######"," / / /"
2810 DATA 7," #### ","######"," * * *"
2820 DATA 3," #### ","######","  //  "
2830 :
2840 REM A row of an icon in graphics colour IC% (the DATA line's first
2850 REM item): # a full block, = a striped block, others as they are
2860 DEF FNmosaic(A$)
2870   LOCAL O$,I%,H$
2890   O$=CHR$(144+IC%)
2900   FOR I%=1 TO LEN A$
2910     H$=MID$(A$,I%,1)
2920     IF H$="#" O$=O$+CHR$255 ELSE IF H$="=" O$=O$+CHR$243 ELSE O$=O$+H$
2930   NEXT
2940 =O$
2950 :
3000 REM ------------------------------------------------------------------
3010 REM 102 News: the titles from Ars Technica's RSS feed (the first
3020 REM two are the feed's own; CNN's feed stopped in 2023)
3030 DEF PROCnews
3040   LOCAL I%,R%
3050   PROCtitle("News   Ars Technica")
3060   IF TIME-FE%>60000 PROCgetnews
3070   R%=5
3080   FOR I%=0 TO NN%-1
3090     IF R%<23 AND I%<NN% PROCwrap(N$(I%),R%,I% MOD 2):R%=R%+FNlines(N$(I%))+1
3100   NEXT
3110   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"Source: arstechnica.com";
3120 ENDPROC
3130 :
3135 REM Over a TCP channel, the request sent by hand: the feed is 76 KB,
3137 REM more than the Ultimate's HTTP reader keeps (it then gives none)
3140 DEF PROCgetnews
3150   LOCAL F%,A$
3160   F%=OPENUP("TCP:feeds.arstechnica.com:80")
3170   IF F%=0 ERROR 100,"No news"
3175   PROCsend(F%,"GET /arstechnica/index HTTP/1.0"):PROCsend(F%,"Host: feeds.arstechnica.com"):PROCsend(F%,"")
3180   NN%=0
3190   A$=FNtag(F%):A$=FNtag(F%)
3200   REPEAT
3210     A$=FNtag(F%)
3220     IF A$<>"" N$(NN%)=A$:NN%=NN%+1
3230   UNTIL NN%=10 OR EOF#F%
3240   CLOSE#F%
3250   FE%=TIME
3260 ENDPROC
3262 :
3264 REM A line to a TCP channel, CR LF at the end
3266 DEF PROCsend(F%,A$)
3268   LOCAL I%
3270   IF A$<>"" FOR I%=1 TO LEN A$:BPUT#F%,ASC MID$(A$,I%,1):NEXT
3272   BPUT#F%,13:BPUT#F%,10
3274 ENDPROC
3276 :
3280 REM The next <title>: its text (up to 120 characters); CNN wraps
3285 REM it as <![CDATA[...]]>: then up to the first ]
3290 DEF FNtag(F%)
3300   LOCAL A$,C%,E%
3310   IF NOT FNfind(F%,"<title>") THEN =""
3320   C%=BGET#F%:E%=60
3330   IF C%=60 PROCskip(F%,8):C%=BGET#F%:E%=93
3340   REPEAT
3350     IF C%<>E% AND LEN A$<120 A$=A$+FNascii(C%)
3360     IF C%<>E% C%=BGET#F%
3370   UNTIL C%=E% OR EOF#F%
3375 =FNentities(A$)
3376 REM UTF-8: a lead byte (&E2: quotes, dashes) as ', the rest dropped
3377 DEF FNascii(C%)
3378   IF C%<128 THEN =CHR$C%
3379   IF C%=&E2 THEN ="'"
3380 =""
3381 DEF PROCskip(F%,N%)
3382   LOCAL I%,C%
3383   FOR I%=1 TO N%:C%=BGET#F%:NEXT
3384 ENDPROC
3385 :
3390 REM Read the channel on until the text K$ has gone by
3400 DEF FNfind(F%,K$)
3410   LOCAL M%,C%
3420   M%=1
3430   REPEAT
3440     C%=BGET#F%
3450     IF C%=ASC MID$(K$,M%,1) M%=M%+1 ELSE IF C%=ASC K$ M%=2 ELSE M%=1
3460   UNTIL M%>LEN K$ OR EOF#F%
3470 =M%>LEN K$
3480 :
3490 REM Print A$ from row R% word-wrapped in 38 columns, in white or
3500 REM yellow (alternating, so headlines stand apart)
3510 DEF PROCwrap(A$,R%,Y%)
3520   LOCAL W$,L$,P%
3530   L$=""
3540   REPEAT
3550     P%=INSTR(A$+" "," ")
3560     W$=LEFT$(A$,P%-1):A$=MID$(A$,P%+1)
3570     IF LEN L$+LEN W$>37 PROCrow(L$,R%,Y%):R%=R%+1:L$=""
3580     IF L$<>"" L$=L$+" "
3590     L$=L$+W$
3600   UNTIL A$=""
3610   IF L$<>"" PROCrow(L$,R%,Y%)
3620 ENDPROC
3630 DEF PROCrow(L$,R%,Y%)
3640   IF R%<23 PRINT TAB(0,R%);CHR$(135-4*Y%);L$;
3650 ENDPROC
3660 DEF FNlines(A$)
3670 =(LEN A$+37) DIV 38
3680 :
3700 REM HTML entities: &amp; &quot; &lt; &gt; &#39; &#039;
3710 DEF FNentities(A$)
3720   A$=FNswap(A$,"&amp;","&"):A$=FNswap(A$,"&quot;",CHR$34)
3730   A$=FNswap(A$,"&lt;","<"):A$=FNswap(A$,"&gt;",">")
3740 =FNswap(FNswap(A$,"&#039;","'"),"&#39;","'")
3750 DEF FNswap(A$,F$,T$)
3760   LOCAL P%
3770   REPEAT
3780     P%=INSTR(A$,F$):IF P% A$=LEFT$(A$,P%-1)+T$+MID$(A$,P%+LEN F$)
3790   UNTIL P%=0
3800 =A$
3810 :
4000 REM ------------------------------------------------------------------
4010 REM 103 The blog: the slim feed on the BBS server (plain HTTP)
4020 DEF PROCblog
4030   LOCAL I%,R%
4040   PROCtitle("idreamtin8bits.com")
4050   IF TIME-FB%>60000 PROCgetblog
4060   R%=5
4070   FOR I%=0 TO NB%-1
4080     IF R%<22 AND I%<NB% PRINT TAB(0,R%);CHR$130;BD$(I%):PROCwrap(B$(I%),R%+1,1):R%=R%+FNlines(B$(I%))+2
4090   NEXT
4100   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"bbs.idreamtin8bits.com/u64-feed.json";
4110 ENDPROC
4120 :
4130 DEF PROCgetblog
4140   LOCAL I%
4150   OSCLI "JSON GET http://bbs.idreamtin8bits.com/u64-feed.json"
4160   NB%=FNjsoncount("blogs"):IF NB%>5 NB%=5
4170   FOR I%=0 TO NB%-1
4180     IF I%<NB% B$(I%)=FNjson("blogs/%"+STR$I%+"/title")
4190     IF I%<NB% BD$(I%)=FNday(FNjson("blogs/%"+STR$I%+"/date"))
4200   NEXT
4210   FB%=TIME
4220 ENDPROC
4230 :
5000 REM ------------------------------------------------------------------
5010 REM 104 The ISS on a world map (39 x 16 cells, 9.2 degrees each way;
5020 REM open-notify gives the position as strings: JSON is fine here)
5030 DEF PROCiss
5040   LOCAL R%,C%,X%,Y%
5050   PROCtitle("Where is the ISS?")
5060   IF TIME-FI%>1000 PROCgetiss
5070   FOR R%=0 TO 15
5080     PRINT TAB(0,5+R%);CHR$148;CHR$157;CHR$146;FNland(M$(R%));
5090   NEXT
5100   X%=INT((ILON+180)/9.231):Y%=INT((80-ILAT)/8.75)
5110   IF X%>=0 AND X%<=36 AND Y%>=0 AND Y%<=15 PRINT TAB(X%+2,5+Y%);CHR$136;CHR$145;CHR$255;
5120   PRINT TAB(0,22);CHR$131;"Lat ";ILAT;"  Lon ";ILON
5130   PRINT TAB(0,24);CHR$132;CHR$157;CHR$135;"open-notify.org, every 10 s: R";
5140 ENDPROC
5150 :
5160 DEF PROCgetiss
5170   OSCLI "JSON GET http://api.open-notify.org/iss-now.json"
5180   ILAT=VAL FNjson("iss_position/latitude")
5190   ILON=VAL FNjson("iss_position/longitude")
5200   FI%=TIME
5210 ENDPROC
5220 :
5230 REM A map row: # land (a full block), others sea (a space)
5240 DEF FNland(A$)
5250   LOCAL I%,O$
5260   FOR I%=1 TO LEN A$
5270     IF MID$(A$,I%,1)="#" O$=O$+CHR$255 ELSE O$=O$+" "
5280   NEXT
5290 =O$
5300 :
5310 DEF PROCmap
5320   LOCAL R%
5330   RESTORE 5360
5340   FOR R%=0 TO 15:READ M$(R%):NEXT
5350 ENDPROC
5360 DATA "  ######  ####      ##############   "
5370 DATA " ###############   ##################"
5380 DATA "   ###########    ################# #"
5390 DATA "    #########     ####  ##########   "
5400 DATA "     ######      ###########  ###    "
5410 DATA "      #####       ########   ##      "
5420 DATA "        ###      #########    #      "
5430 DATA "         ###      #######      ##    "
5440 DATA "          ####     #####       ## #  "
5450 DATA "          #####    ####         #### "
5460 DATA "           ####    ###          #####"
5470 DATA "           ###     ##          ##### "
5480 DATA "           ##                   ##   "
5490 DATA "           #                       # "
5500 DATA "                                     "
5510 DATA "      ###########################    "
5520 :
6000 REM ------------------------------------------------------------------
6010 REM 199 Settings: the weather's place. A name: Open-Meteo's
6020 REM geocoding lists matches (read as raw JSON for the decimals); or
6030 REM AUTO: the place of the Ultimate's internet address (ip-api.com)
6040 DEF PROCsettings
6050   LOCAL A$,N%,K%
6060   PROCtitle("Settings: the weather")
6070   PRINT TAB(0,5);CHR$131;"Now: ";CHR$135;LEFT$(PLACE$,28)
6080   PRINT TAB(0,7);CHR$130;"Type a place name, or AUTO for the"
6090   PRINT CHR$130;"place of this internet connection;"
6100   PRINT CHR$130;"RETURN alone keeps it."
6110   PRINT TAB(0,11);CHR$134;"Place? ";
6120   INPUT ""A$
6130   IF A$="" ENDPROC
6140   IF A$="AUTO" OR A$="auto" PROCauto:PROCsave:FW%=-100000:ENDPROC
6150   N%=FNgeocode(A$)
6160   IF N%=0 PRINT TAB(0,13);CHR$129;"Not found: ";A$:ENDPROC
6170   FOR K%=0 TO N%-1
6180     PRINT TAB(0,13+K%);CHR$131;K%+1;CHR$135;LEFT$(R$(K%),30)
6190   NEXT
6200   PRINT TAB(0,13+N%+1);CHR$134;"Which (1-";N%;")? ";
6210   K%=GET-49
6220   IF K%<0 OR K%>=N% ENDPROC
6230   PLACE$=R$(K%):LAT$=RL$(K%):LON$=RO$(K%)
6240   PROCsave:FW%=-100000
6250   PRINT TAB(0,22);CHR$130;"Saved: ";LEFT$(PLACE$,28)
6260 ENDPROC
6270 :
6280 REM Up to 5 places for name A$: R$() "name, CC", RL$() lat, RO$() lon
6290 DEF FNgeocode(A$)
6300   LOCAL F%,N%,V$
6305   REM (over TCP, by hand: the Ultimate's HTTP reader hangs on replies
6307   REM longer than one 896-byte block, which this one can be)
6310   F%=OPENUP("TCP:geocoding-api.open-meteo.com:80")
6320   IF F%=0 THEN =0
6325   PROCsend(F%,"GET /v1/search?count=5&name="+FNurl(A$)+" HTTP/1.0"):PROCsend(F%,"Host: geocoding-api.open-meteo.com"):PROCsend(F%,"")
6330   REPEAT
6340     V$=FNvalue(F%,"name")
6350     IF V$<>"" R$(N%)=V$:RL$(N%)=FNvalue(F%,"latitude"):RO$(N%)=FNvalue(F%,"longitude"):R$(N%)=R$(N%)+", "+FNvalue(F%,"country_code"):N%=N%+1
6360   UNTIL V$="" OR N%=5
6370   CLOSE#F%
6380 =N%
6390 :
6400 DEF PROCauto
6410   LOCAL F%
6420   F%=OPENIN("http://ip-api.com/json/")
6430   IF F%=0 ERROR 100,"No place"
6440   PLACE$=FNvalue(F%,"country")
6450   PLACE$=FNvalue(F%,"city")+", "+PLACE$
6460   LAT$=FNvalue(F%,"lat"):LON$=FNvalue(F%,"lon")
6470   CLOSE#F%
6480 ENDPROC
6490 :
6500 REM Raw JSON: the value after the next "key": (a string without its
6510 REM quotes, or a number as text); "" when the key does not come
6520 DEF FNvalue(F%,K$)
6530   LOCAL C%,A$,Q%
6540   IF NOT FNfind(F%,CHR$34+K$+CHR$34+":") THEN =""
6550   C%=BGET#F%
6560   IF C%=34 Q%=TRUE:C%=BGET#F%
6570   REPEAT
6580     IF Q% AND C%=34 THEN C%=-1 ELSE IF NOT Q% AND (C%=44 OR C%=125) THEN C%=-1 ELSE A$=A$+CHR$C%:C%=BGET#F%
6590   UNTIL C%=-1 OR EOF#F% OR LEN A$>40
6600 =A$
6610 :
6620 REM A name for a URL: spaces as %20
6630 DEF FNurl(A$)
6640   LOCAL P%
6650   REPEAT
6660     P%=INSTR(A$," ")
6670     IF P% A$=LEFT$(A$,P%-1)+"%20"+MID$(A$,P%+1)
6680   UNTIL P%=0
6690 =A$
6700 :
6710 REM U64TEXT.CFG: place, latitude, longitude (PRINT#/INPUT#); the
6720 REM first start: the place of the internet connection
6730 DEF PROCload
6740   LOCAL F%
6750   F%=OPENIN "U64TEXT.CFG"
6760   IF F%=0 PROCauto:PROCsave:ENDPROC
6770   INPUT#F%,PLACE$,LAT$,LON$
6780   CLOSE#F%
6790 ENDPROC
6800 DEF PROCsave
6810   LOCAL F%
6820   F%=OPENOUT "U64TEXT.CFG"
6830   PRINT#F%,PLACE$,LAT$,LON$
6840   CLOSE#F%
6850 ENDPROC
6860 :
7000 REM ------------------------------------------------------------------
7010 REM Text helpers: lines of a channel, CSV fields
7020 DEF FNline(F%)
7030   LOCAL A$,C%
7040   REPEAT
7050     C%=BGET#F%
7060     IF C%>=32 AND LEN A$<200 A$=A$+CHR$C%
7070   UNTIL C%=10 OR EOF#F%
7080 =A$
7090 :
7100 DEF FNskipto(F%,K$)
7110   LOCAL A$
7120   REPEAT A$=FNline(F%):UNTIL LEFT$(A$,LEN K$)=K$ OR EOF#F%
7130 =A$
7140 :
7150 REM Field N% (from 1) of a comma-separated line
7160 DEF FNcsv(A$,N%)
7170   LOCAL I%,P%
7180   IF N%>1 FOR I%=2 TO N%:P%=INSTR(A$+",",","):A$=MID$(A$,P%+1):NEXT
7190   REM (a FOR loop runs at least once: hence the IF)
7210   P%=INSTR(A$+",",",")
7220 =LEFT$(A$,P%-1)
7230 :
29990 :
29991 REM ------------------------------------------------------------------
29992 REM demos/net/JSONLIB (merged: BBC BASIC has no INSTALL/LIBRARY)
30000 REM JSONLIB: values of a JSON reply (*JSON GET) for programs
30010 REM Merge into a program, call PROCjsoninit once, then e.g.
30020 REM   OSCLI "JSON GET http://api.open-notify.org/iss-now.json"
30030 REM   PRINT FNjson("iss_position/latitude")
30040 REM Paths: "a/b" down objects, "%n" an array's element (from 0).
30050 REM OSWORD &70 (docs/DESIGN_NETWORK.md): path in, value out.
30060 DEF PROCjsoninit
30070   DIM JB% 8,JP% 255,JS% 255
30080 ENDPROC
30090 :
30100 REM The value at P$ as text ("" if there is none)
30110 DEF FNjson(P$)
30120   PROCjsonask(P$)
30130   JS%?(JB%?7)=13
30140 =$JS%
30150 :
30160 REM The value at P$ as a number
30170 DEF FNjsonnum(P$)
30180 =VAL FNjson(P$)
30190 :
30200 REM The number of entries of the object or array at P$
30210 DEF FNjsoncount(P$)
30220   PROCjsonask(P$)
30230 =JB%?8
30240 :
30250 REM The type at P$: 0 none, 1 number, 2 TRUE/FALSE, 3 string,
30260 REM 4 object, 5 array
30270 DEF FNjsontype(P$)
30280   PROCjsonask(P$)
30290 =JB%?6
30300 :
30310 DEF PROCjsonask(P$)
30320   $JP%=P$
30330   JB%?0=JP% MOD 256:JB%?1=JP% DIV 256:JB%?2=LEN P$
30340   JB%?3=JS% MOD 256:JB%?4=JS% DIV 256:JB%?5=255
30350   A%=&70:X%=JB% MOD 256:Y%=JB% DIV 256
30360   CALL &C7F1
30370 ENDPROC
