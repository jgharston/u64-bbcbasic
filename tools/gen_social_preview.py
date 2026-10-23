#!/usr/bin/env python3
"""
Generate the GitHub social preview image for U64 BBC BASIC.
Same layout as mandelbrot-upic's, heartbeat-demo's and the other idi8b
projects' screenshots/social-preview.png (after mandelbrot-upic's
tools/gen_social_preview.py).

Input:  screenshots/preview-shot.png (a frame from the VIC stream,
        tools/u64shot.py)
Output: screenshots/social-preview.png (1280x640)
"""

import os
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREEN_SHOT = os.path.join(REPO_ROOT, 'screenshots', 'preview-shot.png')
# the idi8b logo is cut from locifilemanager-v2's preview, a repository next
# to this one (FM_PREVIEW overrides)
FM_PREVIEW = os.environ.get('FM_PREVIEW', os.path.join(
    REPO_ROOT, '..', 'locifilemanager-v2', 'screenshots', 'social-preview.png'))
OUT_PATH = os.path.join(REPO_ROOT, 'screenshots', 'social-preview.png')
FONT_PATH = '/usr/share/fonts/truetype/ubuntu/UbuntuMono[wght].ttf'

W, H = 1280, 640
BG = (16, 16, 16)
C_CYAN = (16, 235, 235)
C_YELLOW = (235, 235, 16)
C_WHITE = (235, 235, 235)
C_GREEN = (15, 235, 16)

# Left panel: the screenshot with a green border; right panel from x 760
SHOT_X1, SHOT_Y1 = 32, 95
SHOT_X2, SHOT_Y2 = 727, 543
TEXT_X = 760
LOGO_FM = (768, 95, 1243, 275)          # the idi8b logo in the FM preview
TITLE_Y, VERS_Y, DESC_Y, URL_Y = 320, 390, 447, 593


def main():
    shot = Image.open(SCREEN_SHOT).convert('RGB')
    panel_w, panel_h = SHOT_X2 - SHOT_X1, SHOT_Y2 - SHOT_Y1
    # whole multiples where possible keep the C64 pixels sharp
    scale = min(panel_w / shot.width, panel_h / shot.height)
    new_w, new_h = int(shot.width * scale), int(shot.height * scale)
    shot = shot.resize((new_w, new_h), Image.NEAREST)
    off_x = SHOT_X1 + (panel_w - new_w) // 2
    off_y = SHOT_Y1 + (panel_h - new_h) // 2

    logo = Image.open(FM_PREVIEW).crop(LOGO_FM)
    ls = min((1260 - TEXT_X) / logo.width, 200 / logo.height)
    logo = logo.resize((int(logo.width * ls), int(logo.height * ls)), Image.LANCZOS)

    f_title = ImageFont.truetype(FONT_PATH, 46)
    f_vers = ImageFont.truetype(FONT_PATH, 40)
    f_desc = ImageFont.truetype(FONT_PATH, 26)
    f_url = ImageFont.truetype(FONT_PATH, 24)

    canvas = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(canvas)
    b = 4
    draw.rectangle([off_x - b, off_y - b, off_x + new_w + b, off_y + new_h + b],
                   outline=C_GREEN, width=b)
    canvas.paste(shot, (off_x, off_y))
    canvas.paste(logo, (TEXT_X, 80))
    draw.text((TEXT_X, TITLE_Y), "U64 BBC BASIC", font=f_title, fill=C_CYAN)
    draw.text((TEXT_X, VERS_Y), "v1.0.0", font=f_vers, fill=C_YELLOW)
    for i, line in enumerate(("BBC BASIC 3.10 as a",
                              "cartridge for the U64",
                              "and the C64 Ultimate")):
        draw.text((TEXT_X, DESC_Y + 34 * i), line, font=f_desc, fill=C_WHITE)
    draw.text((TEXT_X, URL_Y), "github.com/xahmol/u64-bbcbasic", font=f_url, fill=C_GREEN)
    canvas.save(OUT_PATH, 'PNG')
    print('Saved:', OUT_PATH)


if __name__ == '__main__':
    main()
