# U64 BBC BASIC: video plans (draft for review)

Five videos for the channel "I Dreamt In 8 Bits", one per group, made the
established way (`~/.claude/youtube_video_workflow.md`): picture captured
pixel-exact from the Ultimate 64's VIC stream with scripted key presses,
no REST probing while recording, palettes applied in post, Piper "Alba"
narration (or ElevenLabs), title and closing cards with the idi8b logo,
chapters, transcript, thumbnail. 1920x1080, 50 fps, picture at 4x.

Narration lines below are drafts: one line per scene, spelled for TTS
in the final `narration.json` ("U-pic", "sixty-four megahertz").

## Points to decide first

1. **The personal story (video 1)**: decided, Alba tells it in the third
   person; no recording of your own voice.
2. **Pictures of the other machines** (ZX Spectrum, Oric Atmos, C64,
   C128, BBC Micro) for the story: your own photos (your retro setup)
   are best; otherwise screenshots of their BASICs from emulators, which
   need no permission.
3. **Sound**: settled. The Ultimate's audio stream is recorded alongside
   the picture (tested: `streams/audio:start` to 239.0.1.65:11001,
   250 packets/s of 770 bytes, a 2-byte sequence number and 192 stereo
   16-bit samples at 47983 Hz; no gaps with the video stream running;
   the sample count is the audio's timeline). The level is low (peaks
   about -20 dBFS): loudnorm in post.
4. **VS Code**: settled, recorded here without help: the Linux VS Code of
   the extension's tests, driven by a script inside VS Code (open a file,
   type a program, Ctrl+F5 on the U64, a breakpoint, stepping), its window
   recorded with ffmpeg x11grab (tested: 1208x804, real frames). A clean
   profile with settings that skip the welcome/sign-in dialog and set the
   window title.
5. **Release**: all five at once. They are uploaded as Unlisted (links
   already final, so the release notes, README and posts can use them),
   in an Unlisted playlist "U64 BBC BASIC"; at the release everything is
   switched to Public. Claude delivers the files and texts to Downloads;
   the owner uploads.

## Video 1: "BBC BASIC on the Commodore 64 Ultimate" (introduction, about 5 min)

| # | Scene (picture) | Narration (draft) | Notes |
|---|---|---|---|
| 1 | Title card: idi8b logo, "U64 BBC BASIC", "BBC BASIC 3.10 for the Ultimate 64 and C64 Ultimate" | "This is U64 BBC BASIC: the BBC Micro's BASIC, on a Commodore 64 with an Ultimate." | |
| 2 | The story, part 1: the photo of Xander as a kid at the TI-99/4A with the ZX Spectrum beside it (slow zoom, about 6 s), then the Spectrum's and the Oric Atmos's BASIC screens | "Xander Mol, who made this, learned to program as a kid: on a Texas Instruments TI ninety-nine four A and a ZX Spectrum, and later an Oric Atmos. The Spectrum's and the Oric's BASICs were better than the Commodore sixty-four's BASIC version two, where almost everything was POKE and PEEK." | photo: build/video/photos/01-kid-ti99-spectrum.jpg (not in git); TI BASIC: ti99-basic-list.png, ti99-basic-run.png (Classic99); Spectrum: the magazine type-in he typed in, "On the Road" by Ges & Hilary Taylor, Sinclair User 33 (December 1984): zx-ontheroad-list.png (its BASIC, LIST 505 on the Spectrum ROM) and zx-ontheroad-game.png (Fuse); credit them in the description |
| 2b | The ZX Spectrum: first its manual, "ZX Spectrum BASIC programming" (the John Harris cover, then chapter 2 "Basic Programming Concepts" with 10 LET a=10 on a drawn TV screen; 1.5 s each), then the type-in: the cover of Sinclair User 33 (December 1984, 2 s), the three spreads with the listing (pages 126-131, 1.5 s each, a slow zoom into the code), then the same program on the Spectrum: its LIST screen and its game screen (2 s each) | "The Spectrum's own manual taught him the basics. Then programs came from magazines, typed in line by line: this one, On the Road, from Sinclair User in December nineteen eighty-four. Six pages of code." | manual pages: build/video/manual/zx-manual-*.png (credit "ZX Spectrum BASIC programming, Steven Vickers, ed. Robin Bradbeer, Sinclair Research 1983; cover illustration John Harris"); scans: build/video/magazine/ (from the World of Spectrum archive: credit "Sinclair User, December 1984, EMAP; scan: World of Spectrum archive" in the description) |
| 2c | The Oric Atmos: the manual (cover, title page "The ORIC ATMOS Manual, Ian Adamson, Pan Books 1984", the first lesson page with PRINT "MESSAGE" and ?SYNTAX ERROR; 1.5 s each, a slow zoom on the lesson), then his own Ludo in Oric BASIC: its listing on the Atmos and its title screen | "On the Oric Atmos, its manual taught him BASIC, one PRINT at a time. Years later he even brought his own board game, Ludo, to the Oric's BASIC." | manual pages: build/video/manual/ (from the Defence Force library scan; credit "The ORIC ATMOS Manual, Ian Adamson, Pan Books 1984; scan: defence-force.org"); screens: oric-ludo-list.png, oric-ludo-title.png (Phosphoric, Atmos ROM, from xahmol/ludo's LUDOMAIN.tap and LUDO.dsk) |
| 3 | The story, part 2: C64 BASIC v2 (`POKE 53280,0`), then his own C128 games of 1992, from the original disks: the title screens of Mens Erger Je Niet and Carrière (XAMA Software), then a BASIC 7.0 listing on the 80-column screen (`DO ... LOOP` with `GOSUB 15520`) | "Later came the Commodore one twenty-eight. In nineteen ninety-two he wrote board games in its BASIC seven: better, with DO and LOOP, but still jumping to line numbers, with two-letter variable names. Still not the BASIC he envied as a kid." | screens: build/video/screens/c128-mejn-title.png, c128-carriere-title.png, c128-mejn-list.png (VICE x128, 80 columns, from xahmol/ludo and xahmol/careers) |
| 4 | The story, part 3: the BBC Micro, a BBC BASIC listing with PROC, REPEAT, local variables, the built-in assembler | "That was BBC BASIC: procedures, real structure, graphics and sound commands, and an assembler built in. He never had one. So now there is one, for the Commodore sixty-four, together with everything the Ultimate can do." | |
| 4b | The Acorn Archimedes from the present-day setup photo (crop, 2 s), then Bubble Universe building up on the real Archimedes (build/video/clips/archimedes-bubble-30x.mp4, from the channel's own video GNqB7fsyGpY at 30x, 4.9 s, caption "Acorn Archimedes, real hardware, 30x speed"), then a hard cut to the same program on the U64 | "Years later he did get BBC BASIC, in its fifth version, on an Acorn Archimedes, where his ArchBAS project brought graphics programs to it. Now the circle closes: BBC BASIC on the Commodore sixty-four." | photo: build/video/photos/02-present-setup.jpg (not in git) |
| 5 | The Ultimate's file browser: start `u64bbc-tmb.crt`; the banner "U64 BBC BASIC 1.0.0 / BASIC 3.10 (C)1983 Acorn / CPU turbo (maximum)" | "It is a cartridge. The interpreter is the original BBC BASIC three point ten, unchanged, byte for byte. Around it sits a new operating system, written for the C64 and the Ultimate." | |
| 6 | Type a short structured program (DEF PROC, REPEAT, LOCAL), RUN | "Programs are real BBC BASIC: what you would type on a BBC Micro runs here." | typed by script, at a readable pace |
| 7 | A speed test: `TIME=0:FOR I%=1 TO 100000:NEXT:PRINT TIME` | "And fast: the Ultimate's turbo runs it twenty-five to thirty times faster than a BBC Micro." | |
| 8 | The line editor: history with cursor up, copy editing with CTRL+cursor and F1 | "Lines are edited the BBC way, with a history and copy editing." | |
| 9 | `*HELP PRINT`, `*HELP KEYWORDS` | "Help for every keyword and command is built in: star help." | |
| 10 | Teaser montage, 3 s each: a Upic picture, the 24-voice music bars, Invaders, the Ceefax pages, the file browser | "And then the Ultimate: its graphics, eight SIDs, Ultimate Audio, the REU, the network. More in the next videos." | music under it from the capture |
| 11 | VS Code: write a program, Ctrl+F5, output in VS Code, a breakpoint and the variables | "You can also write programs on your PC in VS Code, run them on the machine, and debug them there." | decision 4 |
| 12 | Closing card: GitHub URL, free and open source; credits: Sophie Wilson and Acorn, Ivo van Poorten (the annotated source), J.G. Harston | "U64 BBC BASIC is free. Find it on GitHub. Thanks to Sophie Wilson and Acorn for BBC BASIC, and to Ivo van Poorten and J. G. Harston, whose work made this possible." | |

Pacing of the story (scenes 2-4b, decided): about 70 s in all. The
Spectrum gets the full sequence (manual, magazine, its program); the
TI-99/4A and the Oric two or three images each; 1.5-3 s an image.

Thumbnail: the banner screen or a Upic picture, title "BBC BASIC on the C64".

## Video 2: graphics (about 6 min)

| # | Scene | Narration (draft) | Notes |
|---|---|---|---|
| 1 | Title card | "Graphics in U64 BBC BASIC." | |
| 2 | GFXDEMO menu, then GFXBBC: the BBC modes 0-7, MOVE, DRAW, PLOT, circles | "All the BBC Micro's screen modes are there, with BBC graphics coordinates." | |
| 3 | Upic Lite: MODE 2, a Schraf program (Bubble Universe) drawing | "On a sixty-four megahertz Ultimate the BBC modes are drawn as U-pic Lite: 256 lines with square pixels, as on a BBC. This is one of Eric Schraf's programs, which came here by way of ArchBAS on the Archimedes." | palette in post (the program's *COLOUR values); sped up with a caption "Eric Schraf, via ArchBAS (Archimedes)" |
| 4 | Teletext MODE 7 (GFXTTX): double height, mosaics | "Mode seven is teletext, with its mosaic graphics and double height." | teletext palette in post (BBC pure RGB) |
| 5 | The C64's own modes (GFXC64): hires and multicolour | "The Commodore's own modes are there as well." | default palette |
| 6 | Shapes and patterns: triangles, ellipses, ECF pattern fills, flood fill | "Every shape of the BBC Master and the graphics extension ROM: outlined, filled, or with patterns." | |
| 7 | Speed race (SHOW3): `*CIRCLE FILL`, triangles, counters | "The star graphics commands draw thousands of shapes a second." | |
| 8 | Upic full: the sunset (SHOW9) drawn, then shown | "Mode one ten is U-pic full: three hundred and eighty-four by two hundred and fifty-six, every pixel its own colour, kept in the R E U." | palette in post (SHOW9's *COLOUR values) |
| 9 | 3D cube, spirograph, plasma (SHOW5, SHOW8, SHOW7) | "Fast integer tables make rotating shapes and plasma possible in plain BASIC." | |
| 10 | Sprites: BALLS (32 multiplexed), then Invaders being played | "Thirty-two sprites, multiplexed, from BASIC. Enough for a game." | play scripted |
| 11 | The sprite editor `*SEDIT` | "With a sprite editor built in." | |
| 12 | A CharPad map scrolling (`*MAP`) | "CharPad maps load and scroll with one command." | needs a CharPad file we may show (CharPad's own examples: check licence) |
| 13 | PETSCII mode: the idi8b logo, typing with the graphics keys | "And for PETSCII art: a full PETSCII mode." | |
| 14 | Closing card | | |

## Video 3: sound and music (about 5 min)

| # | Scene | Narration (draft) | Notes |
|---|---|---|---|
| 1 | Title card | "Sound and music." | |
| 2 | BBC mode: a classic SOUND and ENVELOPE effect | "SOUND and ENVELOPE work as on a BBC Micro; in BBC mode they even sound like one." | audio capture (decision 3) |
| 3 | SID mode: `*INSTRUMENT`, a chord on three voices, then 24 voices (SID24) | "In SID mode, SOUND reaches all twenty-four voices of eight SIDs, with instruments." | |
| 4 | The music demo: Canon in D being built from SOUND commands (sped up), then played with the 24 bars | "The music demo builds each piece from BASIC, note by note, and the song tracker plays it in the background." | the build at 4x with a caption |
| 5 | The Entertainer or Ode to Joy, playing | | music, no narration |
| 6 | Ultimate Audio: the AUDIO demo's sample effects | "On the Ultimate sixty-four, Ultimate Audio plays samples..." | sample credits on screen (CREDITS.md) |
| 7 | A MOD playing (4ev or Wild Perspective) | "...and ProTracker MOD music, through a port of Freshness's ModPlayer." | credits of the MOD on screen |
| 8 | Speech: `*SAY` | "And with your own copy of S.A.M., it speaks." | only if you want SAM in the video |
| 9 | Closing card, credits for the music | | |

## Video 4: files, the Ultimate and the network (about 5 min)

| # | Scene | Narration (draft) | Notes |
|---|---|---|---|
| 1 | Title card | "Files, the Ultimate, and the network." | |
| 2 | `*CAT`, `*DIR`, LOAD and SAVE on the SD card | "Files live on the Ultimate's drives." | |
| 3 | The file browser (F1): folders, opening a program, a picture, a MOD | "F1 opens a file browser. Return opens a file by its type." | |
| 4 | Marking, copying and pasting a folder, deleting one | "It copies, moves and deletes, folders included." | |
| 5 | The /REU RAM disk: saving and loading at DMA speed | "The R E U becomes a fifteen megabyte RAM disk." | |
| 6 | `*MOUNT` a disk image, SoftIEC partitions, the drives | "Disk images and the drives are a command away." | |
| 7 | `*STATUS`, `*TIME`, `*NET TIME` | "The clock, the drives, the network: star status shows it all." | |
| 8 | `*NET GET` of a web page to the screen | "BASIC talks to the internet: HTTP requests..." | |
| 9 | U64TEXT: index, weather, a blog post, news, the ISS map | "...and here, a Ceefax-style service in mode seven: the weather, the blog, the news, and where the space station is." | live internet: record when the feeds answer; teletext palette in post |
| 10 | Closing card | | |

## Video 5: demos (about 5 min)

| # | Scene | Narration (draft) | Notes |
|---|---|---|---|
| 1 | Title card | "The demos." | |
| 2 | The showcase (SHOW), from the start, with its own music: SID Canon, then the MOD | | about 3.5 min; captions instead of narration; audio capture; palettes per scene in post |
| 3 | Montage: Schraf's programs, the Christmas tree, Hanoi, the fern | "And classics of BBC BASIC, unchanged." | |
| 4 | Closing card with all credits: Eric Schraf, the classics' authors, the music and samples | | |

## Production notes

- One recording script per video, adapted from the UBoot64 and
  Mandelbrot Upic examples; demos run from the SD card as deployed.
- Palettes in post: Upic Lite, Upic full and teletext set their own
  (from the demos' `*COLOUR` / `VDU 19` values); the VIC-II modes use the
  default palette.
  The take logs a scene event with the palette name before the command
  that changes the mode; the edit switches at the first cleared (one
  colour) frame after it (`palette_segments` in `tools/video/frames.py`),
  never at the event time: a stalled REST call delayed a typed RUN by
  17 s in the first video-1 take.
- Tools: `tools/video/rec.py` (video and audio stream capture, typing on
  the keyboard matrix, event log), `frames.py` (decoding, palettes),
  `v1_record.py` ... (one take script per video). Takes go to
  `build/video/takes/`.
- Each video: chapters from the edit's timeline, a transcript for the
  subtitles, two thumbnail variants, the description and tags, all
  delivered to Downloads. Links in the README and the release notes.
