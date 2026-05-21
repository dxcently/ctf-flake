# Team Toolkit Shells (Nix)

The flake provides ready-made, version-pinned tool environments so anyone can
drop into a complete kit with one command — no installing, no version drift, no
polluting their own machine. Leave the shell and the tools are gone.

## Entering a shell

```bash
nix develop          # authoring (build/test challenges) — the default
nix develop .#red    # RED TEAM: offense toolkit
nix develop .#blue   # BLUE TEAM: defense toolkit
nix develop .#player # lean offense kit sized to these four challenges
```

Each shell prints a banner listing its tools and an authorized-use reminder.

## What's in each

**`default` (authoring)** — `docker-compose`, `python3` + `pwntools` /
`requests` / `pycryptodome`, `gcc`, `gdb`, `binutils`, `socat`. For *building
and testing* challenges.

**`red` (offense)**
- Recon/scanning: `nmap`, `masscan`, `rustscan`
- Web: `ffuf`, `gobuster`, `nikto`, `sqlmap`, `burpsuite`, `whatweb`
- Exploitation: `metasploit` (`msfconsole`)
- Cracking: `hashcat`, `john`, `hydra`
- Reversing/pwn: `ghidra-bin`, `radare2`, `gdb`, `pwntools`
- Wordlists: `seclists`, `wordlists`
- Pivoting: `netcat`, `socat`, `proxychains-ng`

**`blue` (defense)**
- Capture/analysis: `wireshark`, `tshark`, `tcpdump`, `ngrep`, `iftop`
- Detection/IDS: `suricata`, `zeek`, `yara`
- Forensics: `binwalk`, `foremost`, `sleuthkit`, `exiftool`
- Stack introspection: `dive` (image layers), `docker-compose`

**`player`** — `nmap`, `curl`, `ffuf`, `gobuster`, `sqlmap`, `python3` +
`pwntools`/`pycryptodome`, `gdb`, `radare2`, `binwalk`, `exiftool`, `netcat`,
`socat`. Just enough to solve the four sample challenges.

## Authorized use — read this

Every shell carries the same banner because it matters: these are **dual-use
security tools**. Pointing `nmap`, `sqlmap`, `hashcat`, or `metasploit` at
systems you don't own or lack written permission to test can be illegal. In this
project they exist to attack **the club's own CTF targets** (ports 9001–9004 on
the CTF host) and nothing else. Staying in scope is each user's responsibility.

## Caveats worth knowing

- **First entry is slow and large.** The `red` and `blue` shells pull big
  closures — Ghidra, Burp, Wireshark, Metasploit, Zeek are each substantial.
  The first `nix develop .#red` may download for a while and consume several GB
  in the Nix store. Subsequent entries are instant (it's cached). Plan for this
  before a session rather than during it.
- **`allowUnfree`.** A few tools (e.g. Burp Suite Community) are marked unfree in
  nixpkgs, so the flake sets `config.allowUnfree = true`. That's scoped to this
  flake only and doesn't change your global Nix config.
- **GUI tools need a display.** Ghidra, Wireshark, and Burp are graphical. On a
  headless server they won't open a window; run them from a workstation that has
  `nix`, or use the CLI equivalents (`tshark` for Wireshark, `radare2` for
  Ghidra) on the server.
- **Verified names, not a live eval here.** The package names were checked
  against current nixpkgs, but the flake's first *evaluation* happens on your
  machine. If a package was renamed in your nixpkgs pin, `nix develop` will tell
  you exactly which one; swap the name and re-run. To validate everything up
  front: `nix flake check`.
- **`blue` tools like `suricata`/`zeek` are full IDS/Zeek installs**, heavier
  than a club may need. If you only want packet analysis, you can trim the
  `blueTeamTools` list in `flake.nix` to just `wireshark`/`tshark`/`tcpdump`.

## Adding or trimming tools

The shells are composed from named lists near the top of `flake.nix`
(`redTeamTools`, `blueTeamTools`, etc.). To add a tool, drop its nixpkgs
attribute name into the right list and re-enter the shell. To find a name:

```bash
nix search nixpkgs <toolname>
```
