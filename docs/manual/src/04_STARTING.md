# 4. Starting

## 4.1 A first program

```
>10 FOR I%=1 TO 10
>20   PRINT I%, I%*I%
>30 NEXT
>RUN
```

Lines with a number go into the program; lines without run at once.
`LIST` shows the program, `NEW` clears it. How lines are typed and
edited: chapter 5.

## 4.2 Saving and loading

Programs are saved in the current directory of the Ultimate's file
system (chapter 7):

```
*DIR /SD/myprogs
SAVE "SQUARES"
LOAD "SQUARES"
CHAIN "SQUARES"
```

## 4.3 The keyboard

@@help KEYBOARD

## 4.4 Help

@@help *HELP
