# Red Team Guide

The offense kit. A reproducible, pinned tool environment for attacking the
club's own CTF targets. For the running stack and challenge ports see
`README.md`; for player-level challenge guidance see `CHALLENGES.md`; for the
defense kit see `BLUE-TEAM.md`.

> **Authorized use only.** These are dual-use security tools. Pointing `nmap`,
> `sqlmap`, `hashcat`, or `metasploit` at systems you don't own or lack written
> permission to test can be illegal. In this project they exist to attack the
> club's own CTF targets (ports 9001–9005 on the CTF host) and nothing else.
> Staying in scope is your responsibility.

---

## 1. How to connect

### 1.1 Reach the CTF host

Ask an organizer for the host's LAN address — typically something like
`192.168.50.x`. The host publishes only these ports to your subnet:

| Port  | Service             | How you use it          |
|-------|---------------------|-------------------------|
| 8000  | CTFd scoreboard     | Browser                 |
| 9001  | web-cookie-monster  | `curl`, browser, Burp   |
| 9002  | pwn-stackoverflow   | `nc <host> 9002`        |
| 9003  | crypto-xor          | `curl`, browser         |
| 9004  | forensics-hidden    | `curl`, browser         |
| 9005  | web-filevault       | `curl`, browser         |

You can attack any of those directly from your workstation — no shell on the
host required.

### 1.2 SSH to the host (only if you need a host shell)

You probably don't. Attacking happens from your laptop. SSH onto the host is
for organizers, not players. If an organizer has given you an account:

```bash
ssh <user>@<host>
```

Then `cd ctf-flake` to reach the repo. See README §3.8 for what SSH access
grants and why it's locked down (it's strictly more powerful than attacking a
challenge — keys only, no root, no `docker` group for non-admins).

### 1.3 Enter the red shell

Two ways to use the offense kit:

**On your own workstation** (recommended for GUI tools like Burp and Ghidra).
Requires Nix installed locally. Clone the repo, then:

```bash
nix develop .#red
```

First entry pulls a large closure (Ghidra, Burp, Metasploit, Wireshark — each
substantial). Plan for it before a session, not during. Subsequent entries are
instant from the Nix store. Leave the shell and the tools are gone.

**On the CTF host via SSH** (CLI tools only — the host is headless). Same
command, run from inside the repo.

There is also a leaner `nix develop .#player` shell sized to exactly these
five challenges. Use it when you don't need the full arsenal.

### 1.4 Pivoting GUI tools to remote services (SSH tunnel)

If a service isn't published to your LAN but you want to hit it with a GUI
tool on your workstation, forward the port over SSH:

```bash
ssh -L 9001:localhost:9001 <user>@<host>
# Now http://localhost:9001 on your workstation = port 9001 on the host.
```

For LAN-published challenges (9001–9005) this is unnecessary — connect
straight to the host's IP.

---

## 2. What's in the kit, and when to reach for what

### Recon and scanning

`nmap`, `masscan`, `rustscan`

- **`nmap`** — the workhorse. Service version detection, NSE scripts, OS
  fingerprinting. Default to `nmap -sV -sC <ip>` for a CTF target.
- **`masscan`** — when you have a wide IP range and need it scanned fast.
  Single-port sweeps at millions of packets/sec. Overkill for one host.
- **`rustscan`** — fast port discovery that hands the open ports off to nmap
  for deep probing. Useful when nmap's default port range is too slow.

In this CTF you already know the ports (9001–9005). Recon matters most for
confirming what services answer and what versions they self-report.

### Web testing

`ffuf`, `gobuster`, `nikto`, `sqlmap`, `burpsuite`, `whatweb`

- **`ffuf` / `gobuster`** — directory and parameter fuzzers. Feed them a
  wordlist; they hammer the target looking for hidden endpoints, file names,
  or query parameters. `ffuf` is the modern pick; `gobuster` is the long-time
  workhorse.
- **`nikto`** — opinionated vulnerability scanner for web servers. Noisy but
  fast first pass.
- **`sqlmap`** — automates SQL injection discovery and exploitation. Point it
  at a parameter you suspect.
- **`burpsuite`** — interactive HTTP proxy. Intercept, modify, replay
  requests. The standard for hands-on web testing. GUI — needs a desktop.
- **`whatweb`** — quick technology fingerprinting (server, framework,
  versions).

For this CTF, the web challenges (`web-cookie-monster`, `web-filevault`) are
small and the bugs are visible from a single curl. Burp is overkill but
instructive if you've never used it. `ffuf` is useful for the path-traversal
challenge if you want to fuzz directory depth.

### Exploitation framework

`metasploit` (`msfconsole`)

The classic offensive framework. Modules for scanning, exploitation, payload
generation, post-exploitation. Heavyweight; not needed for the sample
challenges, but included so you can practice the workflow against your own
targets.

### Password and hash cracking

`hashcat`, `john`, `hydra`

- **`hashcat`** — GPU-accelerated hash cracker. Modes for every common hash
  format. Pair with `seclists` wordlists.
- **`john`** (John the Ripper) — CPU cracker, batteries-included for many
  format auto-detection cases.
- **`hydra`** — network login brute-forcer (SSH, HTTP forms, etc.). Use
  carefully and only against authorized targets.

None of the included challenges hand you a hash to crack — these are here for
the broader toolkit.

### Reverse engineering and pwn

`ghidra-bin`, `radare2`, `gdb`, `pwntools`

- **`ghidra-bin`** — NSA's reverse engineering suite. Decompiler, disassembler,
  scripting. GUI — needs a desktop.
- **`radare2`** — terminal-first RE framework. Steep learning curve, powerful.
  CLI, runs on the headless server.
- **`gdb`** — the debugger. Use with the `pwndbg` or `gef` plugins for a
  modern UI (not included by default — add to the flake if you want).
- **`pwntools`** — Python library for writing exploit scripts. `from pwn
  import *` gives you `remote`, `process`, `p64`, `recvuntil`, etc.

Reach for these on `pwn-stackoverflow`. The challenge is compiled deliberately
soft (no canary, no PIE, no ASLR concern) — the lesson is the bug, not the
mitigations.

### Wordlists

`seclists`, `wordlists`

- **`seclists`** — Daniel Miessler's curated lists: passwords, usernames,
  fuzzing payloads, web paths. The de-facto standard. Find them under the
  Nix store; once in the shell, locate with `find $(nix eval --raw
  nixpkgs#seclists) -type d -maxdepth 2`.
- **`wordlists`** — additional collections (rockyou and friends).

Feed these to `ffuf`/`gobuster`/`hashcat`/`hydra`.

### Pivoting and helpers

`netcat-gnu`, `socat`, `proxychains-ng`

- **`netcat` (`nc`)** — Swiss Army knife. Connect, listen, bind-and-execute.
  For the pwn challenge: `nc <host> 9002` to interact by hand.
- **`socat`** — like nc but with bidirectional, scriptable plumbing. Useful
  for setting up local relays or testing socket programs.
- **`proxychains-ng`** — route arbitrary tools through SOCKS/HTTP proxies.
  Relevant once you have a foothold and want to pivot.

---

## 3. Mapping tools to the included challenges

If you want a fast hands-on path through the five sample challenges with the
red kit:

| Challenge            | First-pass tool          | If you go further                 |
|----------------------|--------------------------|-----------------------------------|
| `web-cookie-monster` | `curl` (or Burp)         | dev-tools cookie editor           |
| `pwn-stackoverflow`  | `nc` to feel it out      | `gdb` + `pwntools` for the script |
| `crypto-xor`         | `curl` + a python REPL   | `pwntools` for protocol scaffolding |
| `forensics-hidden`   | `curl` + `strings`       | `binwalk` (also in blue kit)      |
| `web-filevault`      | `curl`                   | `ffuf` to fuzz depth of traversal |

For the hints and progressive nudges on each, see `CHALLENGES.md`.

---

## 4. Caveats

- **First entry is slow and large.** The shell pulls several GB on first use.
  Plan ahead.
- **`allowUnfree`.** A few tools (e.g. Burp Suite Community) are marked unfree
  in nixpkgs, so the flake sets `config.allowUnfree = true`. Scoped to this
  flake only; doesn't change your global Nix config.
- **GUI tools need a display.** Ghidra, Wireshark, Burp are graphical. On a
  headless server they won't open a window. Run them from a workstation that
  has `nix`, or use the CLI equivalents (`radare2` for Ghidra, `tshark` for
  Wireshark) on the server.
- **Verified names, not a live eval here.** Package names were checked against
  current nixpkgs, but the flake's first evaluation happens on your machine.
  If a package was renamed in your nixpkgs pin, `nix develop .#red` will tell
  you exactly which one; swap the name and re-run. To validate up front: `nix
  flake check`.

---

## 5. Adding or trimming tools

The shells are composed from named lists near the top of `flake.nix`
(`redTeamTools`, etc.). Drop a package's nixpkgs attribute name into the right
list and re-enter the shell. To find a name:

```bash
nix search nixpkgs <toolname>
```
