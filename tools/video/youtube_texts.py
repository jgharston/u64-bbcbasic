"""YouTube texts (title, description, chapters, tags) for videos 2-5, with
the channel's title form "Ultimate 64: ..." (owner, 2026-10-23; at most
100 characters, YouTube's limit), and
the chapters from each edit's OUT.chapters.txt. Video 1's text was
written by hand (build/video/deliver/v1-youtube.txt).

  python3 tools/video/youtube_texts.py 2 3 4 5   -> build/video/deliver/vN-youtube.txt
"""
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
VID = os.path.join(ROOT, 'build', 'video')

FOOT = """*Links*
• Download (free, GPLv3), manual and source: https://github.com/xahmol/u64-bbcbasic
• Releases: https://github.com/xahmol/u64-bbcbasic/releases
• Blog: https://www.idreamtin8bits.com/

*Requirements*
An Ultimate 64 / Elite / Elite II or C64 Ultimate with firmware 3.15 or newer, a 16 MB REU and the Command Interface (the TwoMegabyter cartridge image switches them on).

_Narration: Piper text-to-speech, voice "Alba" (en_GB-alba-medium), from a University of Edinburgh speech dataset (https://datashare.ed.ac.uk/handle/10283/3270), licensed CC BY 4.0._
"""
TAGS = ("Commodore 64, C64, BBC BASIC, BBC Micro, Acorn, Ultimate 64, C64 Ultimate, Ultimate 64 Elite, "
        "retro computing, 8-bit, 6502, ")
COMMON = ("*U64 BBC BASIC* is BBC BASIC 3.10 for the Commodore 64 with an Ultimate 64 or C64 Ultimate: the "
          "original interpreter, unchanged, with a new BBC-style operating system for the C64 and the "
          "Ultimate. Everything on the C64 in this video was captured from the video and audio streams of "
          "an Ultimate 64 Elite, on real hardware.")
BASE_THANKS = ["Sophie Wilson and Acorn Computers, for BBC BASIC",
               "Ivo van Poorten, for the annotated BBC BASIC source"]
ULT = "Gideon Zweijtzer, for the Ultimate devices"

VIDEOS = {
    2: ("Ultimate 64: U64 BBC BASIC - Graphics: BBC modes, Upic, sprites and PETSCII on the Commodore 64",
        "Part 2 of 5: graphics.",
        ["All BBC graphics modes with BBC coordinates; on a 64 MHz Ultimate drawn as Upic Lite (256 lines, square pixels)",
         "Every shape of the BBC Master and the Graphics Extension ROM: outlines, fills, pattern fills",
         "The C64's own modes (text, hires, multicolour) and MODE 7 teletext",
         "The * graphics commands at speed: filled circles and triangles counted live",
         "Upic full (MODE 110): 384 x 256, 16 colours of its own, kept in the REU",
         "Fast integer tables: a rotating cube, a palette-cycled plasma, spirographs",
         "32 multiplexed sprites, a small Invaders game, and the built-in sprite editor *SEDIT",
         "CharPad maps with *MAP (with a map made for this video) and the PETSCII mode"],
        BASE_THANKS + ["Eric Schraf, for Bubble Universe and his other graphical BASIC programs",
                       "Aleksi Eeben and Christian Gleissner, for the Upic technique", ULT],
        "graphics, Upic, sprites, PETSCII, CharPad, teletext, MODE 7", "#Commodore64 #BBCBASIC #Ultimate64"),
    3: ("Ultimate 64: U64 BBC BASIC - Sound and music: BBC SOUND, 24 SID voices, MODs and samples",
        "Part 3 of 5: sound and music.",
        ["SOUND and ENVELOPE as on a BBC Micro; in BBC mode (*SOUND BBC) they sound like one",
         "SID mode: SOUND on all 24 voices of 8 UltiSIDs, with instruments (*INSTRUMENT)",
         "The music demo: Canon in D built from SOUND commands under the song tracker, then played on 24 voices",
         "Ultimate Audio: ProTracker MODs from the REU (a port of ModPlayer_16k) and sample effects over them",
         "Speech with *SAY: S.A.M. (1982, Don't Ask Software) is not included; it needs your own copy"],
        BASE_THANKS + ["Freshness, for ModPlayer_16k",
                       "Slice (Forever Young, 1995) and Greg Tuby (Wild Perspective, 1996), for the MODs",
                       "Juhani Junkala, for the sound effects (CC0, OpenGameArt)",
                       "Gideon Zweijtzer, for the Ultimate devices and UltiSID"],
        "SID, UltiSID, 8 SID, MOD, ProTracker, chiptune, Ultimate Audio, SAM speech", "#Commodore64 #SID #BBCBASIC"),
    4: ("Ultimate 64: U64 BBC BASIC - Files, the Ultimate and the network: file browser, RAM disk, HTTP",
        "Part 4 of 5: files, the Ultimate and the network.",
        ["Files on the Ultimate's drives: *DIR, *CAT, SAVE, LOAD",
         "The file browser (F1): folders, copying and deleting folders, RETURN opens a file by its type",
         "/REU: the REU as a 15 MB RAM disk",
         "*MOUNT for disk images, *STATUS, the clock from the internet (*NET TIME)",
         "HTTP from BASIC: *NET GET to the screen",
         "U64TEXT: a Ceefax-style service in MODE 7, written in BBC BASIC: weather, the blog, a post, the ISS position, the news"],
        BASE_THANKS + ["Open-Meteo, open-notify.org and Ars Technica, for the data shown", ULT],
        "file browser, REU, RAM disk, network, HTTP, teletext, Ceefax, MODE 7", "#Commodore64 #BBCBASIC #Ultimate64"),
    5: ("Ultimate 64: U64 BBC BASIC - The demos: showcase, Eric Schraf's graphics, BBC BASIC classics",
        "Part 5 of 5: the demos.",
        ["The showcase: a timed show in BBC BASIC with its own music, first on 8 SIDs, then a MOD on Ultimate Audio: "
         "a palette-cycled tunnel, Bubble Universe, a speed race, 32 sprites, a 3D cube, a plasma, spirographs and a Upic full picture",
         "Eric Schraf's graphical BASIC programs (via ArchBAS on the Acorn Archimedes) and Aurel Wizzard's Christmas tree, drawn live",
         "Classics of BBC BASIC, unchanged or nearly so: the Towers of Hanoi, a fern, Persian patterns, polygons, a sine wave"],
        BASE_THANKS + ["Eric Schraf and Aurel Wizzard, for their graphical BASIC programs",
                       "Richard T. Russell, John A. Coll, Acorn Computers and David Williams, for the classics (zlib licence, via BBC BASIC for SDL)",
                       "Greg Tuby and Slice, for the MODs; Freshness, for ModPlayer_16k", ULT],
        "demo, demoscene, showcase, Bubble Universe, Eric Schraf, ArchBAS, fractal, plasma", "#Commodore64 #BBCBASIC #demoscene"),
}


def write(n):
    title, part, shown, thanks, tags, hashtags = VIDEOS[n]
    chapters = open(os.path.join(VID, 'v%d.mp4.chapters.txt' % n)).read().strip()
    text = ("TITLE\n%s\n\nDESCRIPTION\n%s\n\n%s\n\n*In this video*\n%s\n\n*Thanks*\n%s\n\n*Chapters*\n%s\n\n"
            "%s\n%s\n\nTAGS\n%s%s\n") % (
        title, COMMON, part, '\n'.join('• ' + x for x in shown), '\n'.join('• ' + x for x in thanks),
        chapters, FOOT, hashtags, TAGS, tags)
    out = os.path.join(VID, 'deliver', 'v%d-youtube.txt' % n)
    open(out, 'w').write(text)
    print('written', out)


if __name__ == '__main__':
    for a in sys.argv[1:]:
        write(int(a))
