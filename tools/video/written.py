"""Spoken forms in the narration (for Piper) -> written forms for the
YouTube transcript and subtitles."""
import re

WRITTEN = [
    ('U sixty-four', 'U64'), ('C sixty-four', 'C64'), ('Commodore sixty-four', 'Commodore 64'),
    ('Commodore one twenty-eight', 'Commodore 128'), ('Ultimate sixty-four', 'Ultimate 64'),
    ('TI ninety-nine four A', 'TI-99/4A'), ('nineteen eighty-four', '1984'),
    ('nineteen ninety-two', '1992'), ('BASIC version two', 'BASIC V2'), ('BASIC seven', 'BASIC 7.0'),
    ('three point ten', '3.10'), ('V S Code', 'VS Code'), ('Arch Bas', 'ArchBAS'),
    ('control F5', 'Ctrl+F5'), ('star help', '*HELP'), ('twenty-four voices', '24 voices'),
    ('eight SIDs', '8 SIDs'), ('R E U', 'REU'), ('U-pic', 'Upic'), ('sixty-four megahertz', '64 MHz'),
    ('mode seven', 'MODE 7'), ('mode one ten', 'MODE 110'), ('one ten', '110'),
    ('three hundred and eighty-four by two hundred and fifty-six', '384 x 256'),
    ('two hundred and fifty-six', '256'), ('fifteen megabyte', '15 MB'),
    ('thirty-two sprites', '32 sprites'), ('Thirty-two sprites', '32 sprites'),
    ('S.A.M.', 'S.A.M.'), ('J. G. Harston', 'J.G. Harston'),
]


def written(text):
    for a, b in WRITTEN:
        text = re.sub(re.escape(a), b, text)
    return text
