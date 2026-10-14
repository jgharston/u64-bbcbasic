#!/usr/bin/env python3
"""Apply an Ultimate .cfg file to a running device through the REST API.

Sets every item of every [store] (PUT /v1/configs/{category}/{item}
?value=...), as the firmware does when a cartridge with a .cfg of the
same name is started from its file browser; a cartridge uploaded through
the REST API (deploy, the E2E tests) gets no .cfg, so this puts the
settings in place. Not saved to flash. Owner's rule (2026-10-14): after
the U64 has been lent out, apply the full cfg before using it again.

Usage: applycfg.py FILE.cfg HOST [HOST ...]
"""
import sys
import urllib.parse
import urllib.request


def put(host, store, item, value):
    url = "http://%s/v1/configs/%s/%s?value=%s" % (
        host, urllib.parse.quote(store), urllib.parse.quote(item),
        urllib.parse.quote(value))
    req = urllib.request.Request(url, method="PUT")
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.status


def apply(cfg, host):
    errors = 0
    store = None
    for n, raw in enumerate(open(cfg, encoding="ascii"), 1):
        line = raw.rstrip("\r\n")
        if not line.strip():
            continue
        if line.startswith("["):
            store = line.strip("[]")
            continue
        item, _, value = line.partition("=")
        try:
            put(host, store, item, value)
        except Exception as e:
            print("%s:%d: %s: [%s] %s=%s: %s" % (cfg, n, host, store, item,
                                                 value, e))
            errors += 1
    return errors


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    errors = sum(apply(sys.argv[1], h) for h in sys.argv[2:])
    print("%d error(s)" % errors)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
