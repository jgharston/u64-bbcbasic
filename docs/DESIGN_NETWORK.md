# Design: network

How U64 BBC BASIC uses the Ultimate's network: sockets as file channels,
HTTP requests through the MOS's own HTTP/1.0 client, JSON through the
firmware's HTTP target, and the U64TEXT demo. The commands are in
`*HELP NET` and `*HELP JSON`.

## 1. What the Ultimate offers

The firmware's network target (UCI target 3, `network_target.cc`; the
library's `ultimate_network_lib`, UCILIB_MANUAL.md section 13):

| Command | |
|---|---|
| `$02` interface count, `$04` MAC address, `$05` IP address | the machine's own address |
| `$07` TCP connect `host`, `port` | a socket id; the firmware resolves names (DNS) |
| `$08` UDP "connect" `host`, `port` | a socket id for datagrams to/from that host |
| `$09` close, `$10` read up to n bytes, `$11` write | on a socket id |

Client sockets only: the firmware has no listener commands, so the C64
cannot be a server. Reads do not block: they return what has arrived (0
bytes: nothing yet; an error status: the connection ended). Data is
passed as it is (no PETSCII conversion), which suits BBC BASIC's ASCII.

The firmware's HTTP target (`$06`, firmware 3.15+; ultimate-uci-oscar64
section 19) fetches a URL itself and parses JSON. Its limits (measured
on firmware 3.15a, section 6) make it the route for JSON only.

## 2. Sockets as files

On a BBC Micro, network filing systems (Econet, the Master's TCP/IP
ROMs) made remote data look like files. Here the same (`netchan.s`;
hooks in `fs.s`, `ch_open` bit 1):

- `OPENUP "TCP:host:port"` opens a TCP connection as a channel: `BPUT#`
  sends (a line goes out at its CR or LF), `BGET#` receives (waits until
  a byte arrives; ESCAPE stops the wait), `EOF#` is TRUE when the other
  side has closed and everything is read, `EXT#` = bytes waiting (so a
  program can poll without waiting), `CLOSE#` closes. `OPENIN` the same,
  read-only.
- `OPENUP "UDP:host:port"`: datagrams; `BPUT#` collects bytes, `PTR#c=0`
  sends them as one datagram (or `CLOSE#`); `BGET#` reads the current
  datagram.
- `OPENIN "http://host/path"`: a GET through the MOS's HTTP client
  (section 4), the reply in the REU's 16K buffer, read like a file.
- HTTPS is not possible: the firmware has no TLS.

**Buffers.** Reading one byte per UCI command would be slow. Each
network channel has a 256-byte receive buffer, filled by one read
command when empty, and a send buffer; they live in REU bank 0
(`$3100-$34FF`), moved a byte at a time by DMA (a 1-byte DMA is a few
register writes); the read itself goes UCI -> MOSBUF -> REU. Writes are
sent when 256 bytes are full, at a CR or LF, at `PTR#` = 0 or at
`CLOSE#`, so a line goes out as one packet.

**Channels.** The filing system has two channels (`&11`, `&12`), shared
by the Ultimate's files, the REU RAM disk (bit 0 of `ch_open`) and
sockets (bit 1): at most two open files and sockets together (more would
need 12 bytes of resident RAM per channel, and that page is full).

## 3. Commands

- `*NET`: IP address, netmask, gateway, MAC address.
- `*NET GET|POST|PUT|DELETE <url> [body] [file]`, `*NET HEADER`: HTTP
  requests (section 4).
- `*NET TIME [server]`: switches on the Ultimate's own SNTP client through
  "load config" (no NTP code in the MOS).
- `*NET RANDOM`: the drand beacon (JSON), 40 bits into RND's seed
  `&0D-&11`.
- `*JSON GET <url>`, `*JSON <path>`, `*JSON NEW`, `*JSON SET`, `*JSON POST`,
  OSWORD &70, and the BASIC library `demos/net/JSONLIB` (lines 30000+:
  BBC BASIC line numbers end at 32767) with `FNjson(path$)`,
  `FNjsonnum(path$)`, `FNjsoncount(path$)` (section 5).

The code is in cartridge bank 7 (`netbank.s`: everything inside `.local
net`, with its own copies of the helpers, `bankhelp.s`, and of the UCI
driver, because bank 2's driver reads payloads from the mapped bank).

## 4. The MOS's HTTP/1.0 client

`nethttp.s` speaks HTTP/1.0 over the network target's TCP socket:

- Request: `VERB path HTTP/1.0`, `Host:`, `Connection: close`, the
  `*NET HEADER` lines, `Content-Length:` with a body, an empty line, the
  body (a "string" from the command line or a file up to 64K, sent a page
  at a time). HTTP/1.0 keeps servers from sending chunked replies.
- Reply: `NET_READ` of 254 bytes at a time into MOSBUF (the count and the
  data then fill it exactly). The status line and the headers are parsed
  byte by byte (`Content-Length` honoured, else the end is the server
  closing); 30 s without data: error 223 "Timeout".
- Sinks: a file (streamed, no size limit: 60 KB in about 6 s), the
  screen, or the 16K REU buffer (`OPENIN "http://..."`).
- A status of 400 or more stops at the headers and raises error 223
  ("HTTP 404 Not Found"; 220 is the MOS's "Syntax"); OSBYTE &65 returns
  the last code. The code, the status line, a socket an error left open
  (closed by the next request) and the header lines live in REU bank 0
  `$3C80-$3FFF` (docs/ARCHITECTURE.md 7).
- State during a request: `&06E0-&06FF`, the top of BASIC's string
  buffer (no RAM is free elsewhere); a command line in page 6 must end
  before it ("Line too long").

## 5. JSON

`*JSON GET` and `*JSON POST` use the firmware's HTTP target and its JSON
parser; `*JSON NEW`/`SET` build the request body there (`jsonbody.s`),
and `*NET HEADER`'s lines are added to its header handle (HEADER_ADD
`$13`). A path goes down the reply with `/` and picks an array's element
with `%n` (`user/name`, `list%2/id`). Programs use OSWORD &70: path in,
value out in a DIM'd block, with the type and an object's or array's
count.

- A query for an object or array answers with its type and count and
  can then stream without end; the MOS reads the type and count, then
  aborts the command (CTRL bit 2) and waits for the interface to be idle;
  `uci_finish`'s drain stops on ESCAPE.
- The 16 header slots can run out ("507 NO HEADER SLOT"; they survive a
  reset of the C64 alone): start-up frees all handles (FREE_ALL), and a
  507 on a header create is answered with FREE_ALL and a second try.

## 6. Firmware 3.15a findings

Why plain HTTP goes through the MOS's own client, and what programs
should know:

- The HTTP target has no TLS (plain sockets in `http_request.cc`): https
  URLs cannot work.
- A reply's body is collected in a 16 KB buffer; a longer reply comes
  back empty (not its first 16 KB). Raw exchange (`$32`) replies longer
  than one command-interface block (896 bytes) are unreliable (a hang or
  "400 BAD COMMAND").
- The raw exchange gives no status at all, neither before nor after the
  first packet's acknowledgement: a 404 page arrives like any reply. The
  JSON exchange (`$31`) reports "200 OK" for a valid JSON reply and "400
  NO VALID JSON" for anything else, so a 404 or 500 cannot be seen there
  either.
- A query for a path that is not there: "400 bad format: element ... not
  found".
- JSON numbers are read with `strtol` (`software/api/json.cc`): the
  decimals are dropped (12.7 -> 12, 52.09 -> 52) and `null` gives 0.
  Programs that need decimals read the reply as text (`OPENIN
  "http://..."`); Open-Meteo's forecast also answers as CSV
  (`&format=csv`), its geocoding only as JSON.
- A BBC BASIC FOR loop runs at least once: `FOR I%=1 TO LEN A$` with an
  empty A$ sends `ASC ""` (-1, a byte 255) over a socket.

## 7. Demo: U64TEXT

`demos/net/U64TEXT.bas`: a Ceefax-style service in MODE 7 (teletext
colours, mosaic graphics, double height), one hundred per section,
articles as pages with Ceefax subpages:

| Page | Contents |
|---|---|
| 100 | index |
| 200, 201 | weather from Open-Meteo (`http://api.open-meteo.com/v1/forecast?...`, CSV); the weather's place: a name through Open-Meteo's geocoding (`http://geocoding-api.open-meteo.com/v1/search?name=..&count=5`, JSON over TCP; several towns share a name: a list to choose from), or AUTO from the IP (`http://ip-api.com/json/`); saved in `U64TEXT.CFG` next to the program |
| 300, 301-305 | the idreamtin8bits blog's latest posts from the plain-HTTP mirror on the BBS server (the blog itself is https only): the list from `http://bbs.idreamtin8bits.com/u64-feed.json` (`*JSON GET`), a post's date, title and whole text in subpages from `http://bbs.idreamtin8bits.com/u64-feed/<slug>.txt` (each post's text wrapped at 38 columns, ASCII, at most 400 lines; read over TCP into the REU, &50000 + post * &4000) |
| 400, 401-410 | Ars Technica's headlines (`http://feeds.arstechnica.com/arstechnica/index`, RSS over a TCP channel with a hand-written HTTP/1.0 request, titles taken as they stream in: the feed is larger than 16 KB); an article: the feed's text (`content:encoded`, the start of the article), HTML tags and entities removed, UTF-8 quotes and dashes as ASCII, word-wrapped into 38-column lines kept in the REU (`*SRWRITE`, &40000 + article * &1000 + line * 40, at most 56 lines), 14 lines a subpage: cursor right/left |
| 500 | the ISS (`http://api.open-notify.org/iss-now.json`): a Natural Earth land map (public domain; `demos/net/mkworld.py` makes the DATA) in teletext mosaics, 36 x 16 cells of 10 x 10 degrees (2 x 3 blocks: 72 x 48 points); hold graphics (158) keep the map unbroken where a colour code takes a cell; the ISS a red block, the cells it was in a yellow trail (the last 12); the page reloads every 10 s |

SPACE goes to the next section, inside the blog and the news to the next
post or article. While a page loads, the bottom row says so and counts
the kilobytes read (the TCP readers); `*JSON GET` is one call, so there
only the line shows. The program is 19.9 KB (MODE 7 leaves 24.3 KB from
PAGE to HIMEM): the indentation is dropped when it is tokenised
(`tools/bbctok.py`), and the comments are short; this section has the
details.
