# Blue Team Guide

The defense kit. A reproducible, pinned tool environment for watching the
running CTF stack, analyzing traffic, and doing forensics on artifacts left
behind. For the running stack and challenge ports see `README.md`; for
player-level challenge guidance see `CHALLENGES.md`; for the offense kit see
`RED-TEAM.md`.

> **Authorized use only.** Packet capture, IDS, and forensic tools can lift
> data off systems they touch. In this project they're aimed at the club's own
> CTF host and the traffic it sees — nothing else. Don't sniff networks you
> don't own.

---

## 1. How to connect

### 1.1 SSH to the CTF host (you'll need it)

Most blue work happens *on* the host. Packet capture needs root and a real
NIC; container introspection (`dive`, `docker inspect`) needs access to the
local Docker daemon. So unlike a red player attacking from a laptop, you
typically want a shell on the box.

```bash
ssh <user>@<host>
cd ctf-flake
```

See README §3.8 for the SSH hardening setup (keys only, no root, no `docker`
group for non-admins). If you don't have an account on the host, you're
not the person responsible for defense — talk to an organizer.

### 1.2 Enter the blue shell

```bash
nix develop .#blue
```

First entry pulls a large closure — Suricata, Zeek, Wireshark, RE tooling.
Subsequent entries are instant from the Nix store. Leave the shell and the
tools are gone.

You can also run the blue shell on your own workstation if you've copied
artifacts off the host (pcaps, suspect files) for offline analysis. The GUI
tools (Wireshark) only render on a desktop anyway.

### 1.3 Capture on the host, analyze on your workstation

The natural pattern: capture on the host (where the traffic actually is),
analyze on your workstation (where the GUI lives). Two ways:

**Capture-then-copy:**

```bash
# on the host
sudo tcpdump -i any -w /tmp/event.pcap 'tcp portrange 9001-9005'
# on your workstation
scp <user>@<host>:/tmp/event.pcap .
wireshark event.pcap
```

**Live-stream over SSH** (no file on disk):

```bash
ssh <user>@<host> "sudo tcpdump -i any -U -w - 'tcp portrange 9001-9005'" \
  | wireshark -k -i -
```

The `-w -` tells tcpdump to write to stdout; the `wireshark -k -i -` reads a
live capture from stdin. Useful for incident-style live monitoring.

### 1.4 Inspect the running stack

For container introspection from inside the blue shell on the host:

```bash
docker compose ps                # what's actually running
docker compose logs -f <chal>    # follow live logs
dive <image-name>                # explore a chal image layer-by-layer
docker stats                     # live CPU/mem/net per container
```

---

## 2. What's in the kit, and when to reach for what

### Packet capture and analysis

`wireshark`, `tshark`, `tcpdump`, `ngrep`, `iftop`

- **`tcpdump`** — the baseline. Capture packets to a `.pcap`. Read filters
  use BPF syntax (`tcp port 9001`, `host 10.0.0.5`).
- **`tshark`** — Wireshark's CLI. Same dissectors as the GUI, scriptable,
  fits on a headless server. `tshark -r capture.pcap -Y 'http.request'`.
- **`wireshark`** — GUI for interactive packet diving. Filter, follow-stream,
  protocol decode. Needs a desktop.
- **`ngrep`** — grep across packet payloads. Useful for "show me every
  request containing `flag`."
- **`iftop`** — live per-host bandwidth view. Spot the player who's
  hammering the box.

For this CTF, the natural use is watching what players send to challenge
ports — useful for diagnosing whether a challenge is being attacked correctly
or whether someone is hitting it with the wrong protocol.

```bash
# Capture all challenge traffic for later analysis.
sudo tcpdump -i any -w event.pcap 'tcp portrange 9001-9005'
```

### Intrusion detection and traffic analysis

`suricata`, `zeek`, `yara`

- **`suricata`** — signature-based IDS/IPS. Rule-driven; uses the same rule
  language as Snort. Heavy install; overkill for a small CTF but useful for
  practicing rule writing.
- **`zeek`** (formerly Bro) — behavioral network monitor. Produces structured
  logs (`conn.log`, `http.log`, `files.log`) from live traffic or a pcap.
  Better than Suricata for "what happened" forensics; rules-style detection is
  weaker.
- **`yara`** — pattern matching on files. Write a rule, scan binaries or
  memory dumps for matches. Useful when you have a sample and want to know
  what family it belongs to.

For one-off pcap forensics, Zeek is usually the right starting point:

```bash
zeek -r event.pcap
# Now you have conn.log, http.log, etc. in the current directory.
```

### Host and file forensics

`binwalk`, `foremost`, `sleuthkit`, `exiftool`

- **`binwalk`** — scan a file for embedded data and signatures. The first
  tool to reach for on anything that "looks like one thing but might be more"
  — perfect for the `forensics-hidden` challenge.
- **`foremost`** — file carving. Recover deleted files from disk images or
  arbitrary blobs by signature.
- **`sleuthkit`** — disk forensics suite (`fls`, `icat`, etc.). For real
  disk images, not so much for this CTF.
- **`exiftool`** — read/write metadata from images, PDFs, office documents.
  Often the first move on a suspicious-looking image.

### Integrity and hashing

`openssl`

`sha256sum` is in coreutils (already in `baseTools`). `openssl` gives you
more: HMAC, alternate digests, certificate inspection. Use for verifying that
artifacts haven't been tampered with.

### Container introspection

`dive`, `docker-compose`

- **`dive`** — interactive image-layer explorer. See what each layer adds to
  an image. Useful when reviewing a challenge image: did the author leak
  build-time secrets into a layer?
- **`docker-compose`** — drive the running stack from inside the blue shell
  if you don't want to leave it.

```bash
# Inspect what's actually in the pwn challenge image.
dive ctf-flake-pwn-stackoverflow
```

---

## 3. Mapping tools to the running stack

Common blue-team moves against this CTF:

| Goal                                  | Tool                                          |
|---------------------------------------|-----------------------------------------------|
| See who's hitting the challenges      | `tcpdump` on the host interface, filtered by challenge port |
| Audit what's actually in a chal image | `dive <image>`                                |
| Verify isolation is working           | `docker compose exec <chal> wget …` (see README §3.6) |
| Reconstruct an attack session         | `tshark -r capture.pcap` then filter by player IP |
| Recover the flag from `vacation.png`  | `binwalk vacation.png` or `exiftool`           |
| Spot a runaway/abusive container      | `docker stats`, `iftop`                       |

---

## 4. Caveats

- **First entry is slow and large.** Suricata and Zeek each pull substantial
  closures. Plan ahead.
- **`suricata` / `zeek` are full IDS installs**, heavier than a small club
  may need. If you only want packet analysis, trim `blueTeamTools` in
  `flake.nix` down to `wireshark`/`tshark`/`tcpdump` and re-enter.
- **GUI tools need a display.** Wireshark needs a desktop. On the headless
  server, use `tshark`.
- **Capturing on `docker0` vs. `any`.** Docker traffic between host ports and
  containers traverses bridge interfaces. `tcpdump -i any` is the safe default
  on the host; on the challenge containers themselves you generally can't
  install packet tools (read-only FS, dropped caps).
- **Verified names, not a live eval here.** Same caveat as the red kit — if
  nixpkgs renamed something on your pin, `nix develop .#blue` will tell you;
  swap the name and re-run.

---

## 5. Adding or trimming tools

Edit the `blueTeamTools` list near the top of `flake.nix`. To find a
package's nixpkgs attribute name:

```bash
nix search nixpkgs <toolname>
```
