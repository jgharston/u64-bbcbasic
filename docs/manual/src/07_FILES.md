# 7. Files

Files live on the Ultimate's drives (SD card, USB sticks, its RAM disk
`/Temp`) and, with an REU, on the MOS's own RAM disk `/REU`. Paths are
the Ultimate's: `/SD/games/elite`, or relative to the current directory
(`*DIR`).

## 7.1 The filing system

@@help FILES /REU

## 7.2 Directories and files

@@help *BROWSE *CAT *DIR *PWD *MKDIR *DELETE *RENAME *COPY *TYPE *LOAD *SAVE *INFO *ACCESS *DUMP *RUN *SPOOL *EXEC *BUILD

## 7.3 Files from programs: channels

Two files can be open at the same time. `OPENIN` reads, `OPENOUT`
creates, `OPENUP` reads and writes; all return a channel number (0 when
the file cannot be opened).

@@help OPENIN OPENOUT OPENUP BGET# BPUT# PRINT# INPUT# PTR# EXT# EOF# CLOSE#

## 7.4 Data in the REU

Programs can keep data in the REU, from &40000 up (the MOS uses the
first 256K):

@@help *SRWRITE *SRREAD *REULOAD *REU
