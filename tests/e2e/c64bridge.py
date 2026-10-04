"""Minimal MCP client for c64bridge (github.com/chrisgleissner/c64bridge).

Starts `npx -y c64bridge@latest` as a stdio MCP server with its own
environment (backend, Ultimate host, VICE arguments) and calls its grouped
tools. Python 3 standard library only.

One Bridge per target machine: C64_MODE=c64u with C64U_HOST for each
Ultimate, C64_MODE=vice with VICE_ARGS for the emulator.
"""
import json
import os
import re
import subprocess
import threading


class BridgeError(Exception):
    pass


class Bridge:
    def __init__(self, env, label, command=None, timeout=60):
        self.label = label
        self.timeout = timeout
        full_env = dict(os.environ)
        full_env.update(env)
        full_env.setdefault("LOG_LEVEL", "warn")
        cmd = command or ["npx", "-y", "c64bridge@latest"]
        self.proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=full_env, text=True, bufsize=1)
        self.stderr_lines = []
        threading.Thread(target=self._drain_stderr, daemon=True).start()
        self.next_id = 1
        self._request("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "u64-bbcbasic-e2e", "version": "0.1"},
        })
        self._notify("notifications/initialized", {})

    def _drain_stderr(self):
        for line in self.proc.stderr:
            self.stderr_lines.append(line.rstrip())
            del self.stderr_lines[:-200]

    def _send(self, msg):
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def _notify(self, method, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def _request(self, method, params):
        rid = self.next_id
        self.next_id += 1
        self._send({"jsonrpc": "2.0", "id": rid, "method": method,
                    "params": params})
        result = {}

        def reader():
            for line in self.proc.stdout:
                line = line.strip()
                if not line.startswith("{"):
                    continue
                msg = json.loads(line)
                if msg.get("id") == rid:
                    result["msg"] = msg
                    return

        t = threading.Thread(target=reader, daemon=True)
        t.start()
        t.join(self.timeout)
        if "msg" not in result:
            raise BridgeError("%s: no reply to %s (stderr: %s)" % (
                self.label, method, " | ".join(self.stderr_lines[-5:])))
        msg = result["msg"]
        if "error" in msg:
            raise BridgeError("%s: %s failed: %s" % (self.label, method,
                                                      msg["error"]))
        return msg["result"]

    def call_full(self, tool, **args):
        """Call a c64bridge tool; return (text, metadata) (raises on error)."""
        res = self._request("tools/call", {"name": tool, "arguments": args})
        text = "\n".join(c.get("text", "") for c in res.get("content", [])
                         if c.get("type") == "text")
        if res.get("isError"):
            raise BridgeError("%s: %s %s: %s" % (self.label, tool,
                                                  args.get("op"), text))
        return text, res.get("metadata") or {}

    def call(self, tool, **args):
        """Call a c64bridge tool; return its text content (raises on error)."""
        return self.call_full(tool, **args)[0]

    # --- convenience wrappers

    def read(self, address, length):
        """Read memory, return bytes."""
        text, meta = self.call_full("c64_memory", op="read",
                                    address="$%04X" % address, length=length)
        if "hexData" in meta:
            data = bytes.fromhex(meta["hexData"].lstrip("$"))
            if len(data) >= length:
                return data[:length]
        return parse_hex_dump(text, address, length)

    def write(self, address, data):
        self.call("c64_memory", op="write", address="$%04X" % address,
                  bytes=" ".join("%02X" % b for b in data))

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.terminate()
            self.proc.wait(5)
        except Exception:
            self.proc.kill()


def parse_hex_dump(text, address, length):
    """Extract `length` bytes from c64bridge's read output.

    Accepts a JSON payload with a hex string, or hex dump lines of the
    form '$C000: 01 02 ...'.
    """
    try:
        obj = json.loads(text)
        for key in ("hex", "bytes", "data"):
            if key in obj:
                val = obj[key]
                if isinstance(val, list):
                    return bytes(val[:length])
                return bytes.fromhex(re.sub(r"[^0-9A-Fa-f]", "", val))[:length]
    except (ValueError, TypeError):
        pass
    out = bytearray()
    for line in text.splitlines():
        m = re.match(r"\s*\$?([0-9A-Fa-f]{4})\s*[:|]\s*((?:[0-9A-Fa-f]{2}\s*)+)", line)
        if m:
            out += bytes.fromhex(m.group(2).replace(" ", "")[:32 * 2])
    if len(out) < length:
        raise BridgeError("could not parse memory dump: %r" % text[:300])
    return bytes(out[:length])
