#!/usr/bin/env python3
"""Install U64 BBC BASIC on an Ultimate: /<DRIVE>/idi8b/u64bbcbasic/.

The cartridges (.crt) with their .cfg files at the top, the demos below
demos/, one folder per group (music, net, sound, classics, ...): every
.bas source tokenised into a BBC BASIC program file (the name in
capitals without .bas, as on a BBC: LOAD "MUSIC", CHAIN "U64TEXT"), the
other files of a demo folder as they are (the music's .mml note files,
the classics' LICENCE and README). Tools and Python scripts are left out.

    tools/deploy.py --host 192.168.1.148 --drive SD [--dry-run] FILE...

FILE: the cartridge and .cfg files. The tree is staged in
build/deploy/ first, then sent over FTP (folders created as needed).
"""
import argparse
import ftplib
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bbctok  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
INSTALL = "idi8b/u64bbcbasic"
SKIP_EXT = (".py", ".pyc")


def stage(files, out):
    """build/deploy: the files at the top, demos/ tokenised"""
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    for f in files:
        shutil.copy(f, out)
    demos = os.path.join(ROOT, "demos")
    for dirpath, dirnames, filenames in os.walk(demos):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith((".", "__")))
        rel = os.path.relpath(dirpath, demos)
        target = os.path.join(out, "demos", rel) if rel != "." else os.path.join(out, "demos")
        for name in sorted(filenames):
            src = os.path.join(dirpath, name)
            if name.startswith(".") or name.endswith(SKIP_EXT):
                continue
            os.makedirs(target, exist_ok=True)
            if name.lower().endswith(".bas"):
                image = bbctok.tokenise_program(open(src, encoding="latin-1").read())
                with open(os.path.join(target, name[:-4].upper()), "wb") as f:
                    f.write(image)
            else:
                shutil.copy(src, target)


def upload(host, drive, out, password=""):
    """the staged tree to /drive/INSTALL/ over FTP"""
    ftp = ftplib.FTP(host, timeout=30)
    ftp.login("anonymous", password)
    base = "/%s/%s" % (drive, INSTALL)
    count = 0
    for dirpath, dirnames, filenames in os.walk(out):
        dirnames.sort()
        rel = os.path.relpath(dirpath, out)
        remote = base if rel == "." else base + "/" + rel.replace(os.sep, "/")
        path = ""
        for part in remote.strip("/").split("/"):       # mkdir -p
            path += "/" + part
            try:
                ftp.mkd(path)
            except ftplib.error_perm:
                pass
        for name in sorted(filenames):
            with open(os.path.join(dirpath, name), "rb") as f:
                ftp.storbinary("STOR %s/%s" % (remote, name), f)
            count += 1
    ftp.quit()
    print("%s: %d files to %s/" % (host, count, base))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--host", required=True)
    ap.add_argument("--drive", default="USB0", help="SD, USB0, USB1, ... (default USB0)")
    ap.add_argument("--dry-run", action="store_true", help="only stage build/deploy")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    out = os.path.join(ROOT, "build", "deploy")
    stage(a.files, out)
    if a.dry_run:
        print("staged in %s" % out)
        return
    upload(a.host, a.drive, out, os.environ.get("ULTIMATE_PASSWORD", ""))


if __name__ == "__main__":
    sys.exit(main())
