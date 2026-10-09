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
