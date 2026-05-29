# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A LAN-only CTF event stack: CTFd scoreboard + five intentionally-vulnerable challenge containers, wired together by `docker-compose.yml` and bootstrapped by a Nix flake. The challenges are **deliberately exploitable** — that is the product. Do not "fix" the vulns when editing.

## Commands

```bash
./gen-secrets.sh                            # writes .env (mode 600) — REQUIRED before first build
docker compose build                        # build all challenge images
docker compose build <svc>                  # iterate on one challenge
docker compose up -d                        # run the stack
docker compose ps                           # health check
docker compose logs -f <svc>                # follow logs
docker compose restart <svc>                # reset a challenge to pristine
docker compose down -v                      # full wipe incl. CTFd DB
```

Isolation smoke-test (must pass before an event — see BUILD-AND-RUN.md §4):

```bash
docker compose exec crypto-xor sh -c "wget -T3 -qO- http://example.com || echo 'BLOCKED (correct)'"
```

Nix shells (optional; only for authoring/team toolkits, not for running the stack):

```bash
nix develop                  # authoring (gcc, gdb, pwntools, docker-compose)
nix develop .#red            # offense toolkit
nix develop .#blue           # defense toolkit
nix develop .#player         # lean kit sized to these challenges
```

There is no test suite or linter. Verification is functional: rebuild the affected service, hit it on its host port (9001–9005), confirm the documented exploit still works.

## Architecture

Two Docker networks, and the split is the entire safety design:

- `platform` (bridge): CTFd + MariaDB + Redis. Only CTFd publishes a port (`:8000`). DB/cache are unpublished — reachable only from CTFd.
- `challenge_net` (bridge, **`internal: true`**): the five challenges. `internal: true` strips the default gateway, so a fully-compromised challenge container has no route to the internet or LAN. Players reach challenges only via the host ports Docker forwards (`9001`–`9005`).

If you touch `docker-compose.yml`, the `internal: true` on `challenge_net` is load-bearing. Don't remove it. Same for the per-challenge hardening block (`read_only`, `tmpfs`, `mem_limit`, `pids_limit`, `no-new-privileges`, `cap_drop: ALL`) — every challenge carries it for blast-radius containment.

### Flag injection

Two flags are **not in source** — they are baked at image build time from `.env` via Docker build-args:

- `pwn-stackoverflow` ← `PWN_FLAG` (build arg `FLAG`, written to `/home/ctf/flag.txt` in the Dockerfile)
- `web-filevault` ← `WEB_FLAG` (same pattern)

Implication: changing either flag requires `docker compose build <svc> && docker compose up -d <svc>` — `restart` alone won't pick it up. The other three challenges have their flag in the challenge's own source (`app.py` / `gen.py`).

### Nix vs Docker — what does what

- **Nix** (`flake.nix`) provides only the *authoring* and *team-tool* dev shells. It does **not** run, manage, or isolate any live service.
- **Docker Compose** runs everything and enforces all isolation (networks, read-only FS, caps, limits).

You can operate and edit challenges with Docker alone. The flake matters when the toolchain version (compiler, libc, pwntools) needs to be pinned — relevant to the pwn challenge especially, since exploit offsets depend on it.

### Per-challenge intent

| Service              | Port | Vuln class                                |
|----------------------|------|-------------------------------------------|
| web-cookie-monster   | 9001 | client-trusted `role` cookie              |
| pwn-stackoverflow    | 9002 | `gets()` overflow → return to `win()`     |
| crypto-xor           | 9003 | single-byte XOR (256-key brute force)     |
| forensics-hidden     | 9004 | data appended past PNG EOF                |
| web-filevault        | 9005 | path traversal / LFI via `?file=`         |

`pwn-stackoverflow` is compiled with `-fno-stack-protector -z execstack -no-pie` on purpose — the bug is the lesson, mitigations would obscure it. `socat ... fork` gives each TCP connection its own process so one player's crash can't affect others.

## Reference docs in-tree

Four guides — don't reintroduce more:

- `README.md` — general project doc: architecture, install from a fresh Ubuntu host, build/run, day-to-day ops, reasoning behind the non-obvious commands, troubleshooting.
- `CHALLENGES.md` — player-facing guide with progressive hints (Nudge → Push → Lean), no full solutions. Has a small organizer-only flag-location table at the end.
- `RED-TEAM.md` — offense kit (`nix develop .#red`): what's in it, when to reach for each tool, mapping to the five challenges.
- `BLUE-TEAM.md` — defense kit (`nix develop .#blue`): packet capture, IDS, forensics, container introspection.

The `default` (authoring) and `.#player` shells are defined in `flake.nix` and called out where relevant from those docs.
