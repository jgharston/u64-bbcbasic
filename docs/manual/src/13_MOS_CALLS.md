# 13. MOS calls

The MOS entry points have the BBC's low bytes in page &C7 (`OSWRCH` is
&C7EE where a BBC has &FFEE); the RAM vectors are at &0200 as on the
BBC. Programs call them with `CALL` or `USR` (A%, X%, Y% are passed in
the registers).

@@help MOS OSBYTE OSWORD *FX *ADVAL
