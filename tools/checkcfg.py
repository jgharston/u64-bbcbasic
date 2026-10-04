#!/usr/bin/env python3
"""Check an Ultimate .cfg file against a real device's settings.

Every [store] must be a config category of the device, every item must
exist there, and every value must be one of the item's allowed values
(REST GET /v1/configs/{category}/{item}). The firmware silently skips
lines it cannot apply, so a typo would otherwise go unnoticed.

Usage: checkcfg.py FILE.cfg HOST [HOST ...]
"""
import json
import sys
import urllib.parse
import urllib.request


def get(host, path):
    with urllib.request.urlopen("http://%s%s" % (host, path), timeout=10) as r:
        return json.load(r)


def check(cfg, host):
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
        path = "/v1/configs/%s/%s" % (urllib.parse.quote(store),
                                      urllib.parse.quote(item))
        try:
            info = get(host, path)[store][item]
        except Exception as e:
            print("%s:%d: %s: no item %r in [%s] (%s)" % (cfg, n, host, item,
                                                         store, e))
            errors += 1
            continue
        values = info.get("values")
        if values is not None and value not in values:
            print("%s:%d: %s: %r not in %s" % (cfg, n, host, value, values))
            errors += 1
    return errors


def main():
    cfg, hosts = sys.argv[1], sys.argv[2:]
    errors = sum(check(cfg, h) for h in hosts)
    print("%s: %s" % (cfg, "OK" if not errors else "%d error(s)" % errors))
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
