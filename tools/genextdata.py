#!/usr/bin/env python3
"""Generate the VS Code extension's data files from the project sources.

  tokens.json    keyword table (keyword, token, flags) in interpreter
                 order, read from ivop/bbc-basic basic.s via bbctok.py
  help.json      *HELP entries: names, kind (keyword/command/topic) and
                 text, from src/help/help.txt via genhelp.py
  fixtures.json  tokeniser test cases: program text and the image the
                 Python tokeniser (verified against BBC BASIC by the E2E
                 test remote_tokeniser) produces

Usage: genextdata.py OUTDIR
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tests", "e2e"))
import bbctok  # noqa: E402
from genhelp import parse, format_text  # noqa: E402

FIXTURES = [
    # the lines of the E2E tokeniser test, verified on the real interpreter
    "\n".join([
        '10 REM tokeniser test: "quotes" & REM text ~ stays',
        '20 TIME=0:PRINT TIME:PTR#X=PTR#X+1:HIMEM=HIMEM',
        '30 IF A%>1 THEN 10 ELSE GOTO 20',
        '40 ON X GOSUB 10,20,30:RESTORE 40',
        '50 DEF PROCtest(A,B$):LOCAL I%:ENDPROC',
        '60 DEF FNsq(X)=X*X:PRINT FNsq(3);~&FF00',
        '70 DATA 1,"TWO",THREE PRINT',
        '80 *CAT',
        '90 A$=STRING$(3,"*")+MID$("HELLO",2,3):P.LEFT$(A$,2)',
        '100 FOR I%=1 TO 10 STEP 2:NEXT:REPEAT UNTIL TRUE',
        '110 COLOUR 1:VDU 7,8;:X=GET:Y=INKEY(10):Z$=GET$',
        '120 CLOSE#0:BPUT#C,65:CALL &C7EE:Q=USR(&C7E0)',
        '130 PRINTTAB(2,3)"X";SPC(4):CLS:CLG',
        '140 TRACE ON:TRACE OFF:TRACE 100:ENDPROC:END',
        '150 GOTO 32767:GOTO 40000',
        '160 a=1:prints=2:PRINTA:TIMER=3:PROCabc',
    ]),
    "10 FOR I%=1 TO 3\n20 PRINT \"LINE \";I%\n30 NEXT\n40 PRINT 1/0\n",
    "10 INPUT \"NAME\";N$\n20 PRINT \"HI \";N$\n",
    "  5 MODE 7:LISTO 7\n 10 [OPT 2:LDA #65:JSR &C7EE:RTS:]\n 20 ENVELOPE 1,2,3,4,5,6,7,8,9,10,11,12,13,14\n",
]


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "tokens.json"), "w") as f:
        json.dump([{"keyword": k, "token": t, "flags": fl} for k, t, fl in bbctok.TOKENS],
                  f, indent=0)

    src = os.path.join(ROOT, "src", "help", "help.txt")
    entries = []
    for names, lines, _ in parse(src):
        main_name = names[0]
        if main_name in ("KEYWORDS", "COMMANDS", "TOPICS"):
            continue
        first = next((l for _, l in lines if l.strip()), "")
        kind = ("command" if main_name.startswith("*") else
                "keyword" if first.startswith("  ") and main_name != "HELP" else "topic")
        entries.append({"names": names, "kind": kind,
                        "text": "\n".join(format_text(src, lines))})
    with open(os.path.join(out, "help.json"), "w") as f:
        json.dump(entries, f, indent=0)

    fixtures = [{"text": t, "image": bbctok.tokenise_program(t).hex()} for t in FIXTURES]
    with open(os.path.join(out, "fixtures.json"), "w") as f:
        json.dump(fixtures, f, indent=1)
    print("extension data: %d tokens, %d help entries, %d fixtures"
          % (len(bbctok.TOKENS), len(entries), len(fixtures)))


if __name__ == "__main__":
    main()
