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
    ('eight SIDs', '8 SIDs'), ('U-pic', 'Upic'), ('sixty-four megahertz', '64 MHz'),
    ('mode one, two, four and five', 'MODE 1, 2, 4 and 5'), ('Mode seven', 'MODE 7'),
    ('Mode one ten', 'MODE 110'), ('four, sixteen, two and four colours', '4, 16, 2 and 4 colours'),
    ('hundreds of filled circles', 'hundreds of filled circles'), ('eight seconds', '8 seconds'),
    ('mode seven', 'MODE 7'), ('mode one ten', 'MODE 110'), ('one ten', '110'),
    ('three hundred and eighty-four by two hundred and fifty-six', '384 x 256'),
    ('two hundred and fifty-six', '256'), ('fifteen megabyte', '15 MB'),
    ('thirty-two sprites', '32 sprites'), ('Thirty-two sprites', '32 sprites'),
    ('star graphics commands', '* graphics commands'), ('slash R E U', '/REU'), ('star DIR', '*DIR'), ('star CAT', '*CAT'), ('star status', '*STATUS'),
    ('star NET TIME', '*NET TIME'), ('R E U', 'REU'), ('J. G. Harston', 'J.G. Harston'),
    ('Thirty-two', '32'), ('twenty-four', '24'), ('eight', '8'),
]


def written(text):
    """Whole words only: 'eight' must not turn 'height' into 'h8'."""
    for a, b in WRITTEN:
        pat = re.escape(a)
        if a[0].isalnum():
            pat = r'\b' + pat
        if a[-1].isalnum():
            pat = pat + r'\b'
        text = re.sub(pat, lambda m: b, text)
    return text
