# ctf-flake

A LAN-only CTF for a cybersecurity club: a CTFd scoreboard plus five
intentionally vulnerable challenge containers, kept on an isolated network so a
hacked challenge can't pivot into your real infrastructure.

This is the single general guide: architecture, install, build/run, day-to-day
ops, and the reasoning behind the non-obvious commands. For challenge intent and
solutions see `CHALLENGES.md`; for the role-based tool shells see
`TEAM-TOOLKITS.md`.

---

## 1. The big picture

There are two halves to this system, and keeping them separate is the entire
safety design.

1. **The platform** — CTFd, a web scoreboard where players register, read
   challenge descriptions, and submit flags. Ordinary, trusted software.
2. **The challenges** — small programs that are *deliberately broken* so players
   can attack them and recover a hidden flag. Untrusted, exploitable software by
   design.

These two halves run on **separate Docker networks** so that breaking a
challenge can never touch the scoreboard, the internet, or your real network.

```
                    Host LAN (your club subnet)
                              │
        ┌─────────────────────┼───────────────────────────┐
        │ published ports     │                            │
        │  :8000 (CTFd)       │  :9001 :9002 :9003 :9004    │
        │                     │  :9005                       │
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
the internet or the rest of your LAN. Even a fully compromised challenge box
has nowhere to pivot to.

### Threat model in one paragraph

You are deliberately running exploitable software. The safety of the whole setup
rests on two things: (1) the vulnerable containers live on a Docker network
marked `internal: true`, and (2) the server itself sits on an isolated club
VLAN/subnet, not your main network. Treat this box as untrusted. Do not store
anything sensitive on it. Plan to wipe it after the event.

---

## 2. Components

| Service              | Role               | Reachable at                |
|----------------------|--------------------|-----------------------------|
| `ctfd`               | scoreboard         | `http://<host-ip>:8000`     |
| `db` / `cache`       | CTFd backend       | internal only (not exposed) |
| `web-cookie-monster` | web challenge      | `http://<host-ip>:9001`     |
| `pwn-stackoverflow`  | pwn challenge      | `nc <host-ip> 9002`         |
| `crypto-xor`         | crypto challenge   | `http://<host-ip>:9003`     |
| `forensics-hidden`   | forensics challenge| `http://<host-ip>:9004`     |
| `web-filevault`      | web challenge (LFI)| `http://<host-ip>:9005`     |

- **CTFd** (Flask/Python). Pinned to `3.8.2` (fixed a root-user issue in the
  stock compose file). Signs session cookies with `SECRET_KEY`, stores data in
  MariaDB, caches in Redis. Runs as its unprivileged user.
- **MariaDB** and **Redis** are on the `platform` network only and never
  published to the host — nothing outside CTFd can reach them.
- **Challenges** are built from `challenges/<name>/`, attach only to
  `challenge_net`, and are published on their own host port. Intentionally
  vulnerable; not meant to be secure. See `CHALLENGES.md` for what each teaches.

### Per-challenge hardening

Every challenge service carries this block. It limits the blast radius of an
exploited container — players can wreck their own session, never the host or
each other.

```yaml
read_only: true              # root filesystem is immutable
tmpfs: [ /tmp ]              # writable scratch that vanishes on restart
mem_limit: 256m              # can't eat all host RAM
pids_limit: 100              # can't fork-bomb the host
security_opt:
  - no-new-privileges:true   # process can't gain more privs than it started with
cap_drop:
  - ALL                      # drop every Linux capability (no raw sockets, etc.)
```

What each does and *why it matters here*:

- **`read_only: true`** — filesystem can't be modified. Code execution can't
  drop a persistent backdoor; restart wipes everything back to pristine.
- **`tmpfs: [ /tmp ]`** — programs still need somewhere to write. `tmpfs` is
  RAM-backed scratch that exists only while the container runs.
- **`mem_limit` / `pids_limit`** — hard caps so a runaway or malicious process
  can't starve the host of memory or process slots.
- **`no-new-privileges:true`** — blocks privilege-escalation tricks where a
  process would otherwise gain rights mid-execution (e.g. via setuid binaries).
- **`cap_drop: ALL`** — Linux "capabilities" are fine-grained root powers
  (binding low ports, raw network access, etc.). A challenge needs none.

Combined with `challenge_net`'s `internal: true`, the model is: *let players
fully own the inside of a challenge box, while ensuring that ownership buys them
nothing outside it.*

### Where Nix fits (and where it doesn't)

The project is named `ctf-flake` because it ships a Nix flake (`flake.nix`), but
Nix's role is small.

**What Nix does:** provides a reproducible *authoring* environment. `nix
develop` pins the exact versions of the build/exploit tools — `gcc`, `gdb`,
`pwntools`, `socat`, `binutils` — so everyone gets a byte-identical toolchain.
That matters most for pwn/reversing challenges where compiler and libc affect
whether an exploit's offsets line up. It also extends to **role-based toolkits**
(`.#red`, `.#blue`, `.#player`) — same reproducibility, applied to operator
tools. See `TEAM-TOOLKITS.md`.

**What Nix does not do:** it does not run, manage, or isolate any live service.
On this Ubuntu host, Nix is *not* managing the operating system (that would be
NixOS, a different thing). CTFd, the database, the cache, and the challenges
are all started and isolated by **Docker Compose**. Network isolation,
read-only filesystems, the firewall: none of that is Nix's doing.

| Stage              | Tool responsible | Shows up in this doc?  |
|--------------------|------------------|------------------------|
| Authoring/building challenges | Nix (`nix develop`) | §3.3 |
| Running services   | Docker Compose   | throughout              |
| Isolating services | Docker networks + host firewall | §1, §2, §3.6 |

---

## 3. Install from a fresh Ubuntu host

If you already have Docker + (optionally) Nix on a host with this repo checked
out, skip to §4.

### 3.1 Host OS — Ubuntu Server 24.04 LTS

A minimal Ubuntu Server 24.04 LTS install on a dedicated machine or VM. LTS gets
security updates; "dedicated" matters because of the threat model — never run
this on a box that does anything else important.

```bash
sudo apt update && sudo apt upgrade -y
```

### 3.2 Docker Engine + Compose plugin

From Docker's own apt repo (not Ubuntu's older `docker.io`). Compose v2 is how
the running services are defined and isolated.

```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo docker run --rm hello-world
```

Optionally let your admin user run docker without sudo (log out/in after):

```bash
sudo usermod -aG docker $USER
```

Members of the `docker` group effectively have root on the host. Only add
trusted admins, never the players.

### 3.3 Nix (optional, for authoring + team shells)

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install
nix --version
nix flake --help >/dev/null && echo "flakes OK"
```

### 3.4 Project + secrets

```bash
git clone <your-repo-url> ctf-flake
cd ctf-flake
./gen-secrets.sh
```

`gen-secrets.sh` writes `.env` (mode 600) with `CTFD_SECRET_KEY`, DB passwords,
and `PWN_FLAG` / `WEB_FLAG`. Why this matters: CTFd signs session cookies with
`SECRET_KEY`; a weak or shared key would let players forge admin sessions —
exactly the bug `web-cookie-monster` teaches, but for real. `.env` is
gitignored; never commit it. If you'd rather set values by hand, copy
`.env.example` to `.env` and edit.

> The pwn and filevault challenge flags are **injected at build time** from
> `PWN_FLAG` / `WEB_FLAG` (via Docker build-args), not stored in tracked files.
> To change either flag, edit `.env` and rebuild that challenge — `restart`
> alone won't pick it up.

### 3.5 Build + launch

```bash
nix develop                  # optional; pinned authoring toolchain
docker compose build
docker compose up -d
docker compose ps
```

Open `http://<server-LAN-ip>:8000`, complete CTFd's one-time admin setup, then
add each challenge in the admin UI with its flag, category, and points. Flag
locations are listed in `CHALLENGES.md` §3.

Build a single challenge while iterating:

```bash
docker compose build pwn-stackoverflow
docker compose build pwn-stackoverflow && docker compose up -d pwn-stackoverflow
```

### 3.6 Verify isolation BEFORE anyone plays

Non-negotiable. Confirm a challenge cannot reach the internet:

```bash
docker compose exec crypto-xor sh -c \
  "wget -T3 -qO- http://example.com || echo 'BLOCKED (correct)'"
```

You want `BLOCKED (correct)`. If you see web content, stop and fix the network
config before the event.

Confirm the database/cache aren't exposed to the host:

```bash
sudo ss -tlnp | grep -E '3306|6379' && echo "EXPOSED — fix" || echo "private (correct)"
```

### 3.7 Host firewall (ufw)

Even on a LAN, narrow the surface. Replace `192.168.50.0/24` with your actual
club subnet.

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.50.0/24 to any port 22 proto tcp           # SSH
sudo ufw allow from 192.168.50.0/24 to any port 8000 proto tcp         # CTFd
sudo ufw allow from 192.168.50.0/24 to any port 9001:9005 proto tcp    # challenges
sudo ufw enable
sudo ufw status verbose
```

Docker can bypass ufw by writing iptables rules directly. Because we only
publish the intended ports in compose and the challenge net is `internal`,
exposure is limited to those ports — but keep this box on an isolated VLAN
regardless.

### 3.8 SSH access — what it grants, and hardening

Letting any club member SSH into this host is reasonable for a club where
members log in to practice, but understand what it is: SSH gives a shell on the
*host itself*, which is fundamentally more powerful than attacking a challenge
container. A member with host shell access can read the challenge source (and
thus the flags), see other members' files, and tamper with challenges. The
challenge containers are a sandbox; the host shell is **not**.

```bash
# Edit /etc/ssh/sshd_config and set:
#   PasswordAuthentication no      # keys only
#   PermitRootLogin no
#   AllowUsers ctfadmin alice bob  # explicit allowlist
sudo nano /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Keep members as ordinary users:

- Do **not** add players to the `docker` group — root-equivalent on the host.
- Do **not** give players `sudo`.
- Each member gets their own account and SSH public key, so access is
  per-person and revocable.

If later you want members to reach challenges remotely *without* a host shell,
the safer pattern is an SSH tunnel to the challenge ports
(`ssh -L 9001:localhost:9001 member@host`).

---

## 4. Day-to-day operations

```bash
docker compose logs -f ctfd                 # follow scoreboard logs live
docker compose logs --tail=50 pwn-stackoverflow
docker compose restart crypto-xor           # reset one challenge to pristine
docker compose stop / start <service>       # pause / resume
docker compose up -d --build <service>      # rebuild + relaunch in one step
```

Because each challenge runs `read_only` with `tmpfs` scratch, a `restart`
returns it to a clean state — handy if a player corrupts their own session.

### Team tool shells during the event

```bash
nix develop .#player    # lean offense kit for these five challenges
nix develop .#red       # full red-team toolkit
nix develop .#blue      # blue-team / defense toolkit
```

GUI tools (Ghidra, Wireshark, Burp) need a desktop — run those from a
workstation, not the headless server. First entry downloads a lot; cached after.
See `TEAM-TOOLKITS.md`.

### Updating / rebuilding cleanly

```bash
docker compose pull ctfd                    # after changing the tag in compose
docker compose up -d ctfd

docker compose build --no-cache             # rebuild everything from scratch
docker compose up -d
```

### Teardown

```bash
docker compose down          # stop + remove containers, KEEP data volumes
docker compose down -v       # also delete volumes (wipes CTFd DB + uploads)
```

Per the threat model, reimage or wipe the host after the event rather than
reusing this box for anything trusted.

---

## 5. Why the cryptic lines are written the way they are

The lines in this codebase that look opaque, with the reasoning.

### `nix develop`

Reads `flake.nix`, resolves the exact pinned versions of the authoring tools
from the flake's lockfile, and drops you into a shell where those tools are on
your `PATH`. Leave the shell and they're gone — nothing is installed globally.
Optional: only matters when *building* challenges, not when running the stack.

### The pwn compile line

```bash
gcc -fno-stack-protector -z execstack -no-pie -o vuln vuln.c
```

- **`-fno-stack-protector`** — turns OFF the stack canary, a guard value the
  compiler normally places before the return address to detect overflows. We
  disable it so the overflow works and the *bug* is the lesson, not bypassing
  mitigations.
- **`-z execstack`** — marks the stack executable. Not needed for the
  win()-redirect solution but keeps the binary friendly to classic shellcode
  approaches for learners who go further.
- **`-no-pie`** — disables Position-Independent Executable. With PIE off, the
  program loads at a fixed address every run, so `win()` is at the same address
  each time and you don't have to defeat address randomization.
- **`-o vuln`** — names the output file.

### The socat service line

```bash
socat -T60 TCP-LISTEN:9999,reuseaddr,fork EXEC:/home/ctf/vuln,stderr
```

`socat` bridges a TCP socket to a program's stdin/stdout, turning a local
program into a network service.
- **`-T60`** — idle timeout; drop a connection after 60s of inactivity.
- **`TCP-LISTEN:9999`** — listen for TCP connections on port 9999.
- **`reuseaddr`** — lets the listener rebind the port immediately after
  restart.
- **`fork`** — **the important one.** For each incoming connection, fork a
  brand new child process. Every player gets their own fresh instance of
  `vuln`; one player crashing or popping a shell can't affect anyone else.
- **`EXEC:/home/ctf/vuln,stderr`** — run that binary and wire its stderr to the
  socket too (so error output is visible to the player).

### Dockerfile multi-stage build

```dockerfile
FROM debian:bookworm-slim AS build
... compile vuln ...
FROM debian:bookworm-slim
COPY --from=build /src/vuln /home/ctf/vuln
```

Two `FROM` lines = a multi-stage build. The first stage installs `gcc` and
compiles the binary. The second starts clean and copies only the finished
binary out with `COPY --from=build`. The shipped image contains the binary and
`socat` but not the compiler or source — smaller, and less for a player who
escapes to rummage through.

### The chmod lines

```dockerfile
RUN chmod 0444 /home/ctf/flag.txt && chmod 0555 /home/ctf/vuln
```

Octal Unix permissions, three digits = owner / group / others:
- **`0444`** = read-only for everyone (`r--r--r--`). Flag readable by the
  running program, not modifiable.
- **`0555`** = read + execute, no write (`r-xr-xr-x`). Binary runnable, not
  alterable.

### The secret generator

```bash
head -c 64 /dev/urandom | base64 | tr -d '\n'
```

- **`/dev/urandom`** — kernel's cryptographically-secure random source.
- **`head -c 64`** — take exactly 64 random bytes.
- **`base64`** — encode raw bytes as safe printable text.
- **`tr -d '\n'`** — strip newlines so the value sits on one line in `.env`.

### The isolation verification

```bash
docker compose exec crypto-xor sh -c \
  "wget -T3 -qO- http://example.com || echo 'BLOCKED (correct)'"
```

- **`docker compose exec crypto-xor sh -c "..."`** — run a shell command
  *inside* the already-running `crypto-xor` container.
- **`wget -T3 -qO-`** — try to fetch a URL: `-T3` 3-second timeout, `-q` quiet,
  `-O-` write to stdout.
- **`|| echo 'BLOCKED (correct)'`** — `||` runs the right side only if the left
  side **fails**. The challenge network is `internal`, so the fetch should
  fail. If you instead see page content, the isolation is broken.

### The firewall scoping

```bash
sudo ufw allow from 192.168.50.0/24 to any port 8000 proto tcp
```

- **`from 192.168.50.0/24`** — only allow connections originating from that
  subnet (your club LAN). `/24` is CIDR notation for "the first 24 bits are
  the network," i.e. `192.168.50.0`–`192.168.50.255`.
- **`to any port 8000 proto tcp`** — to any local address, TCP port 8000
  (CTFd).

Scoping `from` a subnet means even if the box were somehow reachable elsewhere,
only your club network can connect.

---

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `"flag.txt": not found` on build | old loose-file flag stripped by `.gitignore` | now fixed via build-arg; ensure `.env` has `PWN_FLAG`/`WEB_FLAG` and rebuild |
| `docker compose build` can't read `$PWN_FLAG` | no `.env` present | run `./gen-secrets.sh` or copy `.env.example` to `.env` |
| CTFd won't start, DB errors | DB password mismatch | ensure `.env` `MYSQL_*` values are consistent; `down -v` then up to reset |
| Challenge reachable but can hit internet | isolation broken | confirm `challenge_net` has `internal: true`; recreate network |
| Port already in use | another service on 8000/9001-9005 | change the host port mapping in `docker-compose.yml` |
| `nix develop .#red` very slow first time | large tool closures downloading | expected once; cached after. See `TEAM-TOOLKITS.md` |
| GUI tool won't open on server | headless host, no display | run from a workstation; use CLI equivalents on the server |

---

## 7. Adding your own challenges

1. Create `challenges/<name>/` with a `Dockerfile` exposing one port.
2. Add a service to `docker-compose.yml` copying the hardening block
   (`read_only`, `tmpfs`, `mem_limit`, `pids_limit`, `cap_drop: ALL`,
   `no-new-privileges`, and `networks: [challenge_net]`).
3. `docker compose build <name> && docker compose up -d <name>`.
4. Register it in CTFd with its flag.

Keep every challenge on `challenge_net`. The moment one needs real network
access, that's a design smell — sandbox the dependency instead.
