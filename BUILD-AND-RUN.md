# Build & Run Guide

The practical "type these commands to get the CTF running" reference. For the
full server-from-scratch setup (OS, Docker install, firewall) see `RUNBOOK.md`;
for how everything works internally see `DOCUMENTATION.md`; for the team tool
shells see `TEAM-TOOLKITS.md`. This document is the day-to-day build/operate
loop.

---

## 0. Prerequisites (assumed already done — see RUNBOOK.md)

- Ubuntu host with Docker Engine + the `docker compose` v2 plugin installed.
- Nix installed (only needed for the dev/team shells, not for running the stack).
- This project copied to the server (`ctf-flake/`).

Quick check that the tooling is present:

```bash
docker --version
docker compose version
nix --version          # only if you'll use the dev/team shells
```

---

## 1. First-time setup

### 1.1 Generate secrets and flags

```bash
cd ctf-flake
./gen-secrets.sh
```

This writes a `.env` (mode 600) containing CTFd's `SECRET_KEY`, the database
passwords, and `PWN_FLAG`. **Why this matters:** these values must be strong and
must stay out of version control. `.env` is gitignored. If you'd rather set
values by hand, copy `.env.example` to `.env` and edit.

> **Note on flags:** the pwn challenge's flag is injected at *build time* from
> `PWN_FLAG` in `.env` (via a Docker build-arg), not stored in a tracked file.
> This is the fix for the earlier `"flag.txt": not found` build error — there's
> no loose flag file for `.gitignore` to strip in transit anymore. To change the
> pwn flag, edit `PWN_FLAG` in `.env` and rebuild that challenge.

### 1.2 (Optional) enter the authoring shell

```bash
nix develop
```

Gives you the pinned build/test toolchain (gcc, gdb, pwntools, docker-compose,
etc.). Optional for just running the stack; useful when editing challenges.

---

## 2. Build the images

```bash
docker compose build
```

This reads each challenge's `Dockerfile` and produces a runnable **image** per
service (CTFd is pulled pre-built; the four challenges are built locally). The
pwn build receives `FLAG=$PWN_FLAG` as a build argument, so make sure `.env`
exists *before* building.

Build a single challenge (faster while iterating on one):

```bash
docker compose build pwn-stackoverflow
```

If you change a flag in `.env`, rebuild that challenge so the new flag is baked
in:

```bash
docker compose build pwn-stackoverflow && docker compose up -d pwn-stackoverflow
```

---

## 3. Run the stack

```bash
docker compose up -d        # -d = detached (runs in the background)
docker compose ps           # confirm everything is "running"/"healthy"
```

Services and where they land:

| Service              | Role               | Reachable at                |
|----------------------|--------------------|-----------------------------|
| ctfd                 | scoreboard         | `http://<host-ip>:8000`     |
| db / cache           | CTFd backend       | internal only (not exposed) |
| web-cookie-monster   | web challenge      | `http://<host-ip>:9001`     |
| pwn-stackoverflow    | pwn challenge      | `nc <host-ip> 9002`         |
| crypto-xor           | crypto challenge   | `http://<host-ip>:9003`     |
| forensics-hidden     | forensics challenge| `http://<host-ip>:9004`     |

Open `http://<host-ip>:8000`, complete CTFd's one-time admin setup, then add
each challenge in the admin UI with its flag, category, and points. (Flags: pwn
is whatever you set in `PWN_FLAG`; the others are in each challenge's source —
see `DOCUMENTATION.md` §8.)

---

## 4. Verify isolation BEFORE anyone plays

Non-negotiable safety check — confirm a challenge cannot reach the internet:

```bash
docker compose exec crypto-xor sh -c \
  "wget -T3 -qO- http://example.com || echo 'BLOCKED (correct)'"
```

You want `BLOCKED (correct)`. The challenges sit on a Docker network marked
`internal: true`, so a compromised box has no route out. If you see web content
instead, stop and fix the network config before the event.

Also confirm the database/cache aren't exposed to the host:

```bash
sudo ss -tlnp | grep -E '3306|6379' && echo "EXPOSED - fix" || echo "private (correct)"
```

---

## 5. Day-to-day operations

```bash
docker compose logs -f ctfd                 # follow scoreboard logs live
docker compose logs --tail=50 pwn-stackoverflow
docker compose restart crypto-xor           # reset one challenge to pristine
docker compose stop / start <service>       # pause / resume a service
docker compose up -d --build <service>      # rebuild + relaunch in one step
```

Because each challenge runs `read_only` with `tmpfs` scratch, a `restart`
returns it to a clean state — handy if a player corrupts their own session.

---

## 6. Team tool shells (during the event)

Players and organizers can drop into a pinned toolkit with one command:

```bash
nix develop .#player    # lean offense kit for these four challenges
nix develop .#red       # full red-team toolkit
nix develop .#blue      # blue-team / defense toolkit
```

GUI tools (Ghidra, Wireshark, Burp) need a desktop — run those from a
workstation, not the headless server. First entry downloads a lot; it's cached
after. Details and caveats in `TEAM-TOOLKITS.md`.

---

## 7. Updating / rebuilding cleanly

```bash
# Pull a newer CTFd image (change the tag in docker-compose.yml first)
docker compose pull ctfd
docker compose up -d ctfd

# Rebuild everything from scratch (no layer cache)
docker compose build --no-cache
docker compose up -d
```

---

## 8. Teardown

```bash
docker compose down          # stop + remove containers, KEEP data volumes
docker compose down -v       # also delete volumes (wipes CTFd DB + uploads)
```

Per the threat model in `RUNBOOK.md`, reimage or wipe the host after the event
rather than reusing this box for anything trusted.

---

## 9. Troubleshooting quick table

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `"flag.txt": not found` on build | old loose-file flag stripped by `.gitignore` | now fixed via build-arg; ensure `.env` has `PWN_FLAG` and rebuild |
| `docker compose build` can't read `$PWN_FLAG` | no `.env` present | run `./gen-secrets.sh` or copy `.env.example` to `.env` |
| CTFd won't start, DB errors | DB password mismatch | ensure `.env` `MYSQL_*` values are consistent; `down -v` then up to reset |
| Challenge reachable but can hit internet | isolation broken | confirm `challenge_net` has `internal: true`; recreate network |
| Port already in use | another service on 8000/9001-9004 | change the host port mapping in `docker-compose.yml` |
| `nix develop .#red` very slow first time | large tool closures downloading | expected once; cached after. See TEAM-TOOLKITS.md |
| GUI tool won't open on server | headless host, no display | run from a workstation; use CLI equivalents on the server |
