# Design: network (Phase 5)

Status: decided 2026-10-09 (section 6).

## 1. What the Ultimate offers

The firmware's network target (UCI target 3, `network_target.cc`; the
library's `ultimate_network_lib`, UCILIB_MANUAL.md section 13):

| Command | |
|---|---|
| `$02` interface count, `$04` MAC address, `$05` IP address | the machine's own address |
| `$07` TCP connect `host`, `port` | a socket id; the firmware resolves names (DNS) |
| `$08` UDP "connect" `host`, `port` | a socket id for datagrams to/from that host |
| `$09` close, `$10` read up to n bytes, `$11` write | on a socket id |

Client sockets only: the listener commands are not in current firmware,
so the C64 cannot be a server. Reads do not block: they return what has
arrived (0 bytes: nothing yet; an error status: the connection ended).
Data is passed as it is (no PETSCII conversion), which suits BBC BASIC's
ASCII.

## 2. Proposal: sockets as files

On a BBC Micro, network filing systems (Econet, later the Master's
TCP/IP ROMs) made remote data look like files. Here the same:

- `OPENUP "TCP:host:port"` opens a TCP connection as a channel: `BPUT#`
  sends, `BGET#` receives (waits until a byte arrives; ESCAPE stops the
  wait), `EOF#` is TRUE when the other side has closed and everything is
  read, `EXT#` = bytes waiting (so a program can poll without waiting),
  `CLOSE#` closes. `OPENIN` the same, read-only.
- `OPENUP "UDP:host:port"`: datagrams; `BPUT#` collects bytes, `PTR#c=0`
  sends them as one datagram (or CLOSE#); `BGET#` reads the current
  datagram.
- `OPENIN "http://host/path"` (and `HTTP:`): an HTTP/1.0 GET; the MOS
  sends the request, skips the response headers, and the channel reads
  the body. `EXT#` = Content-Length if given. Status other than 2xx:
  the OPENIN gives 0 (as a missing file) and `*NET` shows the status.
  HTTPS is not possible (no TLS in the firmware).
- Strings: BBC BASIC has no `INPUT#` for lines from an ASCII stream (it
  reads its own format), so a MOS helper: `*NET` ... or a small library
  `FNline(c)` in the demos reading to LF.

Commands:

| Command | |
|---|---|
| `*NET` | IP address, MAC, the open sockets |
| `*NET GET <url> <file>` | download to a file (also /REU), with progress |
| `*NET TIME [server]` | the clock from an NTP server (UDP), as UBoot64's sync |
| `*NET RANDOM` | a seed from the internet for RND (PLAN.md section 21) |

## 3. Buffers

Bytes come from the firmware in blocks; reading one byte per UCI command
would be slow (a command per byte). Each network channel gets a
256-byte receive buffer, filled by one read command when empty. RAM is
scarce (`&0800-&1CFF` is MOSBUF and the sound engine): the buffers live
in the REU (bank 0, `$3100-$32FF` for two channels), copied by DMA a
byte at a time (cheap: a DMA of 1 byte is a few register writes); the
read itself goes UCI -> MOSBUF -> REU. Writes are collected the same way
and sent when 256 bytes are full, on `PTR#` = 0 / a CR / CLOSE#, so a
line goes out as one packet.

Without an REU: one 256-byte buffer below HIMEM? Or simply one UCI
command per byte (slow but correct). Proposal: per byte without REU.

## 4. Channels

The filing system has two channels (`&11`, `&12`), shared by the
Ultimate's files and the REU RAM disk (bit 0 of `ch_open`). Sockets
would use the same two (bit 1: network), so at most two of all open
files and sockets at a time; more needs RAM in the resident page (12
bytes per channel), which is full. Proposal: keep two.

## 5. Decisions needed (owner)

1. Sockets as file channels (`OPENUP "TCP:host:port"`, BGET#/BPUT#) as
   proposed, or only `*NET` commands and OSWORD calls?
   Recommended: as files (BBC style, no new syntax).
2. HTTP built in (`OPENIN "http://..."`, `*NET GET`) or left to
   programs (a TCP channel and a BASIC library)?
   Recommended: built in for GET (it is what most programs want).
3. Which extras first: `*NET TIME`, `*NET RANDOM`, `*NET GET`?
   Recommended: `*NET` and `*NET GET` first, then TIME, then RANDOM.
4. Demo: a small BASIC program that reads a web page or a text API
   (weather, a quote, the ISS position) and shows it in MODE 7.

## 6. Decisions (owner, 2026-10-09)

| Question | Decision |
|---|---|
| Programming model | Sockets as file channels: `OPENUP "TCP:host:port"`, `OPENUP "UDP:host:port"`, BGET#/BPUT#/EOF#/EXT#/CLOSE# |
| HTTP | Built in for GET: `OPENIN "http://..."`, `*NET GET <url> <file>`; no HTTPS |
| Extras | All four: `*NET` and `*NET GET` first, `*NET RANDOM`, `*NET TIME`, and a network demo program |
| Receive buffers | In the REU (bank 0), one UCI read per 256 bytes; without an REU one UCI read per byte |
| JSON (owner, later) | Through the firmware's HTTP target ($06, firmware 3.15+; ultimate-uci-oscar64 section 19): `*JSON GET <url>` fetches and keeps the parsed reply, `*JSON <path>` prints a value (paths as `user/name`, `list%2/id`); programs use an OSWORD (path in, value out in a DIM'd block) wrapped in a small BASIC library: `FNjson(path$)`, `FNjsonnum`, `FNjsoncount` |
| HTTP route (owner, later) | `*NET GET` and `OPENIN "http://..."` also go through the firmware's HTTP target (raw exchange), not the MOS over TCP; the library's HTTP functions are untested on hardware: results go back to the library repository (manual section 20) |

## 7. Demo: a widgets app (owner, 2026-10-09)

Proposal: **U64TEXT**, a Ceefax-style dashboard in MODE 7 (teletext
colours, mosaic graphics, double height), page numbers as on BBC
Ceefax, a carousel mode that cycles the pages, refresh every few
minutes. Sources checked 2026-10-09 (plain HTTP, no key):

| Page | Source | Over HTTP |
|---|---|---|
| 100 index, clock | the Ultimate's clock (OSWORD 14) | - |
| 101 weather | Open-Meteo `http://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&current=..&daily=..` (JSON, ~0.5 KB); the place from `http://ip-api.com/json/` (city, lat, lon from the IP) unless set | yes |
| 102 news | CNN `http://rss.cnn.com/rss/edition.rss` (RSS/XML, 130 KB: headlines scanned from `<title>` in the stream, not JSON); the JSON news APIs (Hacker News, Guardian, NOS, BBC) are HTTPS only | yes (RSS) |
| 103 idreamtin8bits.com | `https://www.idreamtin8bits.com/api/c64-feed.json` (blogs: title, slug, date, body; 450 KB with the bodies) | no: Amplify/CloudFront redirects HTTP to HTTPS; bbs.idreamtin8bits.com has no port 80 |
| 104 ISS | `http://api.open-notify.org/iss-now.json`, a world map in mosaics | yes |

Unknown: whether the firmware's HTTP target can do HTTPS (to test on
the U64 first; it would open the blog feed and the JSON news APIs).

Decided (owner, 2026-10-09): Ceefax style (U64TEXT, MODE 7); news from
CNN's RSS over HTTP (headlines from `<title>`); the blog through a slim
plain-HTTP mirror on the BBS server (bbs.idreamtin8bits.com:
`u64-feed.json`, the latest posts' title, date and a short summary,
refreshed from c64-feed.json by a cron job; work in the
idreamtin8bits-bbs project) unless the firmware turns out to do HTTPS.

Weather location (owner, 2026-10-09): configurable by the user. A
settings page (199): type a place name, U64TEXT asks Open-Meteo's
geocoding (`http://geocoding-api.open-meteo.com/v1/search?name=..&count=5`,
plain HTTP, JSON: name, country, admin1, latitude, longitude, timezone)
and lists the matches to choose from (several towns share a name), or
enter latitude and longitude directly; "auto" uses the IP's place
(ip-api.com). The choice (name, latitude, longitude, timezone, units)
is saved in a settings file next to the program (`U64TEXT.CFG`) and
read at start-up.

## 8. Findings on the U64 (firmware 3.15a, 2026-10-10)

- The HTTP target has no TLS (plain sockets in `http_request.cc`): https
  URLs cannot work; the blog needs the plain-HTTP mirror.
- A reply's body is collected in a 16 KB buffer; more is dropped
  ("buffer full"). Chunked replies are decoded by the firmware.
- After a raw exchange (`$32`) the status is empty, also for a 404: the
  library manual's "the status holds the server's response line" is not
  what the firmware does. `*NET GET` cannot tell an error page from a
  reply. The JSON exchange (`$31`) reports errors (a non-JSON reply:
  "400 NO VALID JSON").
- A query for a path that is not there: "400 bad format: element ...
  not found" (the manual says 404).
- JSON numbers are read with `strtol` (`software/api/json.cc`): the
  decimals are dropped (12.7 -> 12, 52.09 -> 52) and `null` gives 0.
  Programs that need decimals read the reply as text (`OPENIN
  "http://..."`); Open-Meteo's forecast also answers as CSV
  (`&format=csv`), its geocoding only as JSON.
- A JSON query for an object or array (`*JSON blogs`) answers with its
  type and count and then may stream without end (seen on the 3.3 KB
  blog feed: the interface stays in data-available state; 14 KB read
  without an end). U64TEXT hung there. `json_query` reads the type and
  count, then aborts the command (CTRL bit 2) and waits for the
  interface to be idle; `uci_finish`'s drain stops on ESCAPE
  (2026-10-10).
- Header create, raw and JSON exchange, body query and the frees work as
  the library describes otherwise. To be reported to ultimate-uci-oscar64
  (manual section 19 and the test table, section 20).

## 9. As built (2026-10-10)

Cartridge bank 7 (`netbank.s`: everything inside `.local net`, with its
own copies of the helpers, `bankhelp.s`, and of the UCI driver, because
bank 2's read payloads from the mapped bank); the help moved to banks
8+.

- `*NET` (address, netmask, gateway), `*NET GET <url> <file>`, `*NET
  TIME [server]` (switches on the Ultimate's own SNTP client through
  "load config"; no NTP code in the MOS), `*NET RANDOM` (drand beacon,
  JSON, 40 bits into RND's seed `&0D-&11`).
- `*JSON GET <url>`, `*JSON <path>`, OSWORD &70, `demos/net/JSONLIB`
  (lines 30000+: BBC BASIC line numbers end at 32767).
- Channels (`netchan.s`; hooks in `fs.s`, `ch_open` bit 1): `OPENIN
  "http://..."` (the reply in the REU buffer, read as a file),
  `OPENUP "TCP:host:port"` / `"UDP:host:port"`; receive and send
  buffers in REU bank 0 (`$3100`, `$3300`); a TCP line goes out at CR or
  LF, `PTR#c=0` sends a UDP datagram. Tested: an HTTP request by hand
  over TCP to example.com, an NTP query over UDP.
- REU bank 0 now: `$3100-$34FF` socket buffers, `$4000-$7FFF` the HTTP
  reply buffer.
- A BBC BASIC FOR loop runs at least once: `FOR I%=1 TO LEN A$` with an
  empty A$ sends `ASC ""` (-1, a byte 255) -- the first TCP test
  program's mistake, worth a line in the manual.

U64TEXT on the U64 (2026-10-10): CNN's `edition.rss` still answers but
stopped in 2023 (the newest items are from April 2023); the news page
uses Ars Technica's feed instead (`http://feeds.arstechnica.com/arstechnica/index`,
plain HTTP, current). Both feeds are larger than 16 KB: the firmware's
HTTP target then returns an empty body (not the first 16 KB), so the
page reads the feed over a TCP channel with a hand-written HTTP/1.0
request, taking the titles as they stream in.

More firmware 3.15a findings with U64TEXT (2026-10-10):

- Raw exchange replies longer than one command-interface block (896
  bytes) were unreliable: the geocoding reply (1.7 KB) hung the C64 in
  one try and gave "400 BAD COMMAND" for the exchange in another (from
  BASIC poking the registers); replies over 16 KB come back empty. Small
  replies (weather CSV, ISS, example.com) work. U64TEXT reads anything
  larger over a TCP channel with a hand-written HTTP/1.0 request. The
  MOS now checks ESCAPE in its reply loop and aborts the command after
  16 KB, so such a reply cannot hang the machine.
- The 16 header slots can run out ("507 NO HEADER SLOT"; they survive a
  reset of the C64 alone): start-up frees all handles (FREE_ALL), and a
  507 on a header create is answered with FREE_ALL and a second try.
- A bug of the MOS on the way: nc_open kept the channel index in the
  byte where http_fetch keeps the header handle; OPENIN "http://..." then
  used the handle as the channel (it worked while the handle was 0).
