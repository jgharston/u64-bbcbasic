#!/usr/bin/env python3
"""MCP server: U64 BBC BASIC for AI coding agents.

Exposes the remote mailbox (docs/REMOTE_DEV.md, tools/u64remote.py) and the
*HELP reference as Model Context Protocol tools over stdio, so an agent
can write BBC BASIC, run it on a real Ultimate 64, read output and errors,
answer INPUT, stop runaway programs and look up the dialect.

Configure in an MCP client, e.g. this repository's .mcp.json:
  {"mcpServers": {"u64bbc": {"command": "python3",
                             "args": ["tools/u64mcp.py"]}}}
The machine is U64_HOST, else ULTIP1 from .env; every tool also takes
"host". Python 3 standard library only.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bbctok  # noqa: E402
import u64remote  # noqa: E402
from genhelp import parse, format_text  # noqa: E402

ROOT = u64remote.ROOT
HELP_SRC = os.path.join(ROOT, "src", "help", "help.txt")

HOST_PROP = {"host": {"type": "string",
                      "description": "Ultimate IP address (default: U64_HOST / .env ULTIP1)"}}
TIMEOUT_PROP = {"timeout": {"type": "number", "description": "seconds to wait (default 30)"}}

TOOLS = [
    {"name": "bbc_run",
     "description": "Send a BBC BASIC program (text with line numbers) to the "
                    "U64 and RUN it. Returns output, error (number, message, "
                    "line) and state: 'prompt' (finished), 'input' (waiting "
                    "for INPUT: answer with bbc_input) or 'timeout' (still "
                    "running: bbc_stop).",
     "inputSchema": {"type": "object", "required": ["program"],
                     "properties": dict(program={"type": "string"}, **TIMEOUT_PROP, **HOST_PROP)}},
    {"name": "bbc_load",
     "description": "Send a program without running it (like LOAD).",
     "inputSchema": {"type": "object", "required": ["program"],
                     "properties": dict(program={"type": "string"}, **HOST_PROP)}},
    {"name": "bbc_exec",
     "description": "Type lines at the BBC BASIC prompt (immediate commands "
                    "such as PRINT, RUN, LIST, *CAT, or numbered lines to edit "
                    "the program). Returns output, error and state.",
     "inputSchema": {"type": "object", "required": ["lines"],
                     "properties": dict(lines={"type": "array", "items": {"type": "string"}},
                                        **TIMEOUT_PROP, **HOST_PROP)}},
    {"name": "bbc_input",
     "description": "Answer an INPUT statement of a running program.",
     "inputSchema": {"type": "object", "required": ["text"],
                     "properties": dict(text={"type": "string"}, **TIMEOUT_PROP, **HOST_PROP)}},
    {"name": "bbc_stop",
     "description": "Press ESCAPE: stop the running program.",
     "inputSchema": {"type": "object", "properties": dict(**HOST_PROP)}},
    {"name": "bbc_status",
     "description": "State of the machine: prompt, input, running; last error.",
     "inputSchema": {"type": "object", "properties": dict(**HOST_PROP)}},
    {"name": "bbc_screen",
     "description": "The 40x25 text screen as lines of text.",
     "inputSchema": {"type": "object", "properties": dict(**HOST_PROP)}},
    {"name": "bbc_list",
     "description": "The program in memory, as text.",
     "inputSchema": {"type": "object", "properties": dict(**HOST_PROP)}},
    {"name": "bbc_check",
     "description": "Tokenise a program on the host without a machine: finds "
                    "missing/descending line numbers and over-long lines, and "
                    "returns the program as BBC BASIC would LIST it (shows "
                    "which words became keywords).",
     "inputSchema": {"type": "object", "required": ["program"],
                     "properties": {"program": {"type": "string"}}}},
    {"name": "bbc_help",
     "description": "The *HELP reference of this BASIC (no machine needed): a "
                    "keyword (PRINT), a * command (*CAT), a topic (FILES, "
                    "MEMORY, LIMITS, KEYBOARD, ERRORS, MOS, VDUCODES) or "
                    "KEYWORDS / COMMANDS / TOPICS for lists. Read LIMITS "
                    "before writing programs: this is BBC BASIC 3.10 on a C64.",
     "inputSchema": {"type": "object", "required": ["subject"],
                     "properties": {"subject": {"type": "string"}}}},
]


def help_text(subject):
    subject = subject.strip().upper()
    entries = parse(HELP_SRC)
    for names, lines, _ in entries:
        if subject in names:
            if names[0] in ("KEYWORDS", "COMMANDS", "TOPICS"):
                return "\n".join(sorted(n for ns, _, _ in entries for n in ns
                                        if n not in ("KEYWORDS", "COMMANDS", "TOPICS")))
            return "\n".join(format_text(HELP_SRC, lines))
    near = sorted(n for ns, _, _ in entries for n in ns if n.startswith(subject))
    return "No help on %s.%s" % (subject, " Entries: " + ", ".join(near) if near else "")


def call(name, args):
    if name == "bbc_help":
        return {"text": help_text(args["subject"])}
    if name == "bbc_check":
        try:
            image = bbctok.tokenise_program(args["program"])
            return {"ok": True, "bytes": len(image), "listing": bbctok.detokenise(image)}
        except ValueError as e:
            return {"ok": False, "error": str(e)}
    host = args.get("host") or os.environ.get("U64_HOST") or u64remote.default_host()
    if not host:
        return {"ok": False, "error": {"message": "no host: set U64_HOST or ULTIP1 in .env"}}
    r = u64remote.Remote(host, os.environ.get("ULTIMATE_PASSWORD"))
    timeout = float(args.get("timeout", 30))
    if name == "bbc_run":
        return r.send_program(args["program"], run=True, timeout=timeout)
    if name == "bbc_load":
        return r.send_program(args["program"], run=False)
    if name == "bbc_exec":
        return r.run_lines(args["lines"], timeout=timeout)
    if name == "bbc_input":
        return r.run_lines([args["text"]], timeout=timeout)
    if name == "bbc_stop":
        r.stop()
        return {"ok": True}
    if name == "bbc_status":
        return r.state()
    if name == "bbc_screen":
        return {"screen": [x.rstrip() for x in r.screen()]}
    if name == "bbc_list":
        return {"program": r.program_text()}
    raise KeyError(name)


def reply(rid, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": rid}
    if error:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        method, rid = msg.get("method"), msg.get("id")
        if rid is None:
            continue                            # notification
        if method == "initialize":
            reply(rid, {"protocolVersion": msg["params"].get("protocolVersion", "2025-06-18"),
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "u64bbc", "version": "0.1.0"},
                        "instructions": "BBC BASIC 3.10 on an Ultimate 64. Use "
                                        "bbc_help LIMITS and bbc_help KEYWORDS first; "
                                        "bbc_check before bbc_run."})
        elif method == "tools/list":
            reply(rid, {"tools": TOOLS})
        elif method == "tools/call":
            name = msg["params"]["name"]
            args = msg["params"].get("arguments") or {}
            try:
                result = call(name, args)
                is_error = result.get("ok") is False
            except (u64remote.RemoteError, TimeoutError, ValueError, KeyError) as e:
                result, is_error = {"ok": False, "error": {"message": str(e)}}, True
            reply(rid, {"content": [{"type": "text", "text": json.dumps(result, indent=1)}],
                        "isError": is_error})
        elif method == "ping":
            reply(rid, {})
        else:
            reply(rid, error={"code": -32601, "message": "unknown method " + str(method)})


if __name__ == "__main__":
    main()
