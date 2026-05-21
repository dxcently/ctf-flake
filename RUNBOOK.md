# CTF Server Runbook (Ubuntu + Nix flake + Docker Compose)

A LAN-only CTF for a cybersecurity club: a CTFd scoreboard plus four
intentionally vulnerable challenge containers, kept on an isolated network so a
hacked challenge can't pivot into your real infrastructure.

This runbook builds the whole server from a fresh Ubuntu install. Each step says
**what** you install, **how**, and **why**.

---

## 0. Before you start — threat model in one paragraph

You are deliberately running exploitable software. The safety of the whole setup
rests on two things: (1) the vulnerable containers live on a Docker network
marked `internal: true`, so they have no route to the internet or your LAN's
other machines, and (2) the server itself sits on an isolated club VLAN/subnet,
not your main network. Treat this box as untrusted. Do not store anything
sensitive on it. Plan to wipe it after the event.

---

## 1. The host OS — Ubuntu Server 24.04 LTS

**What:** A minimal Ubuntu Server 24.04 LTS install on a dedicated machine or VM.
**Why:** LTS gets security updates; "dedicated" matters because of the threat
model above — never run this on a box that does anything else important.

Patch first thing:

```bash
sudo apt update && sudo apt upgrade -y
```

**Why:** You're about to host attack targets; the *host* itself must be current.

---

## 2. Docker Engine + Compose plugin

**What:** Docker Engine and the `docker compose` v2 plugin, from Docker's own apt
repo (not Ubuntu's older `docker.io` package).
**Why:** Compose is how the running services (CTFd, DB, cache, challenges) are
defined and isolated. We use Docker's official repo to get a current Engine with
the v2 compose plugin and timely security fixes.

```bash
# Install prerequisites for adding an apt repo over HTTPS
sudo apt install -y ca-certificates curl gnupg

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Verify
sudo docker run --rm hello-world
```

Optionally let your admin user run docker without sudo (log out/in after):

```bash
sudo usermod -aG docker $USER
```

**Why this matters for security:** members of the `docker` group effectively have
root on the host. Only add trusted admins, never the players.

---

## 3. Nix (the package manager, on top of Ubuntu)

**What:** The Nix package manager, installed via the Determinate Systems
installer (flakes enabled out of the box).
**Why:** Nix does *not* manage Ubuntu here. Its single job is to give every
challenge author a byte-identical toolchain (`gcc`, `gdb`, `pwntools`, `socat`)
via `nix develop`, so a pwn exploit that works on one laptop works on all of
them. The *running services* are Docker's job, not Nix's.

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

# Reload your shell, then verify flakes work
nix --version
nix flake --help >/dev/null && echo "flakes OK"
```

---

## 4. Get the project and generate secrets

```bash
git clone <your-repo-url> ctf-flake   # or copy this directory to the server
cd ctf-flake

# Generate strong random secrets into .env (CTFd SECRET_KEY, DB passwords)
./gen-secrets.sh
```

**Why:** CTFd signs session cookies with `SECRET_KEY`; weak or shared keys let
players forge admin sessions. The script pulls from `/dev/urandom` and writes
`.env` as mode 600. `.env` is gitignored — never commit it.

---

## 5. Build and launch the stack

```bash
# Enter the reproducible toolchain (optional but recommended for authoring)
nix develop

# Build the challenge images and start everything
docker compose build
docker compose up -d

# Confirm all containers are healthy
docker compose ps
```

Then open `http://<server-LAN-ip>:8000` from a machine on the same LAN and
complete CTFd's first-run admin setup (set a strong admin password).

Player-facing challenge endpoints:

| Challenge            | Type      | Reaches it at           |
|----------------------|-----------|-------------------------|
| web-cookie-monster   | web       | `http://<ip>:9001`      |
| pwn-stackoverflow    | pwn       | `nc <ip> 9002`          |
| crypto-xor           | crypto    | `http://<ip>:9003`      |
| forensics-hidden     | forensics | `http://<ip>:9004`      |

Add each as a challenge in the CTFd admin UI with its flag (flags are listed in
the challenge sources / `flag.txt`). Set point values and category there.

---

## 6. Verify isolation actually works (do not skip)

The `internal: true` network is the safety mechanism. Prove it:

```bash
# From inside a challenge container, outbound internet must FAIL.
docker compose exec crypto-xor sh -c \
  "wget -T3 -qO- http://example.com || echo 'BLOCKED (correct)'"
```

You want to see `BLOCKED (correct)`. If a challenge can reach the internet, stop
and fix the network config before letting anyone play — an exploited box with
internet access is a liability.

Also confirm the DB and cache are NOT published to the host:

```bash
# Should show only 8000 and 9001-9004, never 3306 or 6379.
sudo ss -tlnp | grep -E '3306|6379' && echo "EXPOSED — fix this" || echo "DB/cache private (correct)"
```

---

## 7. Host firewall (ufw)

**What:** `ufw` limiting inbound to SSH and the CTF ports, scoped to your club
subnet.
**Why:** Even on a LAN, narrow the surface. Replace `192.168.50.0/24` with your
actual club subnet.

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.50.0/24 to any port 22 proto tcp     # SSH
sudo ufw allow from 192.168.50.0/24 to any port 8000 proto tcp   # CTFd
sudo ufw allow from 192.168.50.0/24 to any port 9001:9005 proto tcp  # challenges
sudo ufw enable
sudo ufw status verbose
```

Note: Docker can bypass ufw by writing iptables rules directly. Because we only
publish the intended ports in compose and the challenge net is `internal`, the
exposure is limited to those ports — but for extra assurance keep this box on an
isolated VLAN regardless.

---

## 7a. SSH access — what it grants, and hardening

You've chosen to let **any club member on the LAN** SSH into this host. That's
reasonable for a club where members log in to practice, but understand what it
is: SSH gives a shell on the *host itself*, which is fundamentally more powerful
than attacking a challenge container. A member with host shell access can read
the challenge source (and thus the flags), see other members' files, and
restart or tamper with challenges. The challenge containers are a sandbox; the
host shell is **not**. So treat SSH access as a trust grant, and harden it:

```bash
# Edit /etc/ssh/sshd_config and set:
#   PasswordAuthentication no      # keys only — no brute-forceable passwords
#   PermitRootLogin no             # never SSH in as root
#   AllowUsers ctfadmin alice bob  # explicit allowlist of who may log in
sudo nano /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Then, crucially, keep members as **ordinary users**:

- Do **not** add players to the `docker` group — that group is root-equivalent
  on the host (it can mount the whole filesystem into a container). Only trusted
  admins go in `docker`.
- Do **not** give players `sudo`.
- Each member gets their own account with their own SSH public key
  (`~/.ssh/authorized_keys`), so access is per-person and revocable.

If later you want members to reach challenges remotely *without* a host shell,
the safer pattern is an SSH tunnel to the challenge ports
(`ssh -L 9001:localhost:9001 member@host`) rather than widening the firewall —
but for LAN-only that's optional.

---

## 8. Operating during the event

```bash
docker compose logs -f ctfd          # watch the scoreboard
docker compose restart <challenge>   # reset a misbehaving challenge instantly
docker compose down && docker compose up -d   # full clean restart
```

Because every challenge is `read_only` with `tmpfs` scratch space, restarting a
container returns it to a pristine state — handy if a player corrupts their own
session.

---

## 9. Teardown

```bash
docker compose down -v    # -v also removes the CTFd DB/uploads volumes
```

Then, per the threat model, wipe or reimage the host. Don't reuse this box for
anything trusted without a clean install.

---

## Adding your own challenges later

1. Create `challenges/<name>/` with a `Dockerfile` exposing one port.
2. Add a service to `docker-compose.yml` copying the hardening block
   (`read_only`, `tmpfs`, `mem_limit`, `pids_limit`, `cap_drop: ALL`,
   `no-new-privileges`, and `networks: [challenge_net]`).
3. `docker compose build <name> && docker compose up -d <name>`.
4. Register it in CTFd with its flag.

Keep every challenge on `challenge_net`. The moment one needs real network
access, that's a design smell — sandbox the dependency instead.
