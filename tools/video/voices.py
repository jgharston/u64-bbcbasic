"""Piper "Alba" voice clips for a narration file (one WAV per line).

  python3 tools/video/voices.py tools/video/v2_narration.json build/video/v2voice
"""
import json
import os
import subprocess
import sys
import wave

PIPER = os.path.expanduser('~/.local/share/venvs/piper/bin/piper')
VOICE = os.path.expanduser('~/.local/share/piper-voices/en_GB-alba-medium.onnx')


def main(narration, out):
    os.makedirs(out, exist_ok=True)
    total = 0
    for key, text in json.load(open(narration)).items():
        wav = os.path.join(out, key + '.wav')
        subprocess.run([PIPER, '-m', VOICE, '--length-scale', '1.05', '-f', wav],
                       input=text.encode(), capture_output=True, check=True)
        w = wave.open(wav)
        d = w.getnframes() / w.getframerate()
        total += d
        print('%-10s %5.1f' % (key, d))
    print('total %.1f s' % total)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
