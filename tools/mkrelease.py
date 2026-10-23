#!/usr/bin/env python3
"""Build the release ZIP: build/u64-bbcbasic-<version>.zip.

  tools/mkrelease.py VERSION

Contents (the folder u64-bbcbasic-<version>/ in the ZIP):
  u64bbcbasic/        the cartridges, their .cfg files and the demos
                      (tokenised), staged by tools/deploy.py exactly as
                      `make deploy` installs them: copy this folder to
                      /<drive>/idi8b/ on the Ultimate
  demos-source/       the demos as BBC BASIC source (.bas)
  U64_BBC_BASIC_MANUAL.pdf   the user manual (make docs)
  INSTALL.txt, README.md, CHANGELOG.md, NOTICE.md, LICENSE
The cartridges and the PDF must be built first (make release does this).
"""
import os
import shutil
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import deploy  # noqa: E402

INSTALL = """U64 BBC BASIC {version}: installation

1. Copy the folder "u64bbcbasic" to the folder "idi8b" on a drive of your
   Ultimate 64 / C64 Ultimate (make "idi8b" if it does not exist), for
   example /SD/idi8b/u64bbcbasic/ or /USB0/idi8b/u64bbcbasic/. The demos'
   paths in the README and the manual assume this place.
2. In the Ultimate's file browser, start u64bbc-tmb.crt (firmware 3.15 or
   newer). Its .cfg file next to it switches on the Command Interface, the
   REU (16 MB), Ultimate Audio, the turbo registers and 8 UltiSIDs, for
   this session only.
3. Try the showcase:  *DIR /SD/idi8b/u64bbcbasic/demos/showcase
                      CHAIN "SHOW"
   (or press F1 on an empty line and pick a program in the file browser).

u64bbc-ef.crt is an EasyFlash version for VICE and as a fallback (no
Ultimate Audio). The manual is U64_BBC_BASIC_MANUAL.pdf; *HELP on the
machine covers every keyword and command. Source, issues and the videos:
https://github.com/xahmol/u64-bbcbasic
"""


def main(version):
    build = os.path.join(ROOT, "build")
    name = "u64-bbcbasic-" + version
    out = os.path.join(build, "release", name)
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    crts = [os.path.join(build, "u64bbc-%s.%s" % (k, e)) for k in ("tmb", "ef") for e in ("crt", "cfg")]
    pdf = os.path.join(build, "U64_BBC_BASIC_MANUAL.pdf")
    for f in crts + [pdf]:
        if not os.path.exists(f):
            sys.exit("missing %s: run make release" % f)
    deploy.stage(crts, os.path.join(out, "u64bbcbasic"))
    demos = os.path.join(ROOT, "demos")
    for dirpath, dirnames, filenames in os.walk(demos):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith((".", "__")))
        for f in sorted(filenames):
            if f.lower().endswith(".bas"):
                target = os.path.join(out, "demos-source", os.path.relpath(dirpath, demos))
                os.makedirs(target, exist_ok=True)
                shutil.copy(os.path.join(dirpath, f), target)
    shutil.copy(pdf, out)
    for f in ("README.md", "CHANGELOG.md", "NOTICE.md", "LICENSE"):
        shutil.copy(os.path.join(ROOT, f), out)
    with open(os.path.join(out, "INSTALL.txt"), "w", newline="\r\n") as f:
        f.write(INSTALL.format(version=version))
    zpath = os.path.join(build, name + ".zip")
    count = 0
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, dirnames, filenames in os.walk(out):
            dirnames.sort()
            for f in sorted(filenames):
                p = os.path.join(dirpath, f)
                z.write(p, os.path.relpath(p, os.path.dirname(out)))
                count += 1
    print("%s: %d files, %d KB" % (zpath, count, os.path.getsize(zpath) // 1024))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
