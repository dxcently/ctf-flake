# Challenges — a player's guide

Five challenges, five different ways software fails. Each section explains
what you're looking at, what skill the challenge teaches, and a ladder of
hints — softest first. **Read only as far down the ladder as you need.** The
goal is to learn the technique, not to be handed the answer.

For tools, see `RED-TEAM.md` (offense) or pick the lighter `nix develop
.#player` shell which is sized to exactly these five challenges. For the
running stack and ports, see `README.md`.

> **Flag format.** All flags look like `CTF{...}`. When you find one, paste
> it into the CTFd scoreboard at `:8000`.

---

## How to use this guide

For each challenge:

1. **What you see** — the scenario, as it appears to a player. No spoilers.
2. **The skill area** — what general class of bug or technique this teaches.
3. **Hints** — three levels:
   - **Hint 1 — *Nudge*.** Just a direction to look in.
   - **Hint 2 — *Push*.** Names the technique or tool.
   - **Hint 3 — *Lean*.** Close to the answer; stops short of the keystrokes.

If you're still stuck after Hint 3, talk to an organizer.

---

## 1. web-cookie-monster (port 9001)

### What you see

A small "Members area" web page. It says you're logged in as **`guest`** and
that only admins can see the flag. There's no login form. No "become admin"
button. Just a flat page.

Open it in a browser at `http://<host>:9001` or grab it with `curl`.

### The skill area

**Web authorization, and the difference between *authentication* (who you
say you are) and *authorization* (what you're allowed to do).** Real apps
prove "who" with a server-signed token. This one... does something simpler.

### Hints

**Nudge.** The page mentions a role. Roles are usually stored *somewhere*.
Where might a small web app keep "who is this visitor and what role do they
have" between requests, without a database or login?

**Push.** Open your browser's dev-tools and look at the **Application →
Cookies** panel for this site. Or with curl: `curl -v http://<host>:9001`
and look at the response headers. What's the server sending you? What
happens if you send back something different?

**Lean.** The server is *trusting* a value the client controls. The only
check is `if role == "admin"`. You don't need to break crypto, guess a
password, or find a hidden endpoint. You just need to tell the server you
*are* the admin. The mechanism is one HTTP header on the request, with one
specific value.

### The lesson

Authorization that trusts client-controlled state is no authorization at
all. Real apps sign session data server-side (e.g. Flask's `session`,
Rails' encrypted cookies) so the server can detect tampering.

---

## 2. pwn-stackoverflow (port 9002)

### What you see

A network service. Connect with `nc <host> 9002`. It asks:

```
Tell me about yourself:
```

You type something, hit enter, and it greets you back. There's nothing else
on the surface — no menu, no commands.

### The skill area

**Memory corruption, specifically a stack buffer overflow.** This is the
canonical introductory binary exploitation challenge. You'll learn how the
stack is laid out at runtime and how unchecked input lets you steer
execution.

### Hints

**Nudge.** The program reads your input into a fixed-size space in memory.
What happens if you give it more input than that space holds? Try sending
progressively longer strings. Watch what the server does.

**Push.** Long input crashes the program. That crash is the loud version of
a much more useful bug: you can overwrite memory *past* the input buffer.
On a 64-bit Linux system, what sits right after a local stack buffer? (Two
things. The second one is what makes this challenge solvable.) You'll want
the binary itself in front of you — `objdump -d` is your friend. Look for a
function the program *defines but never calls*.

**Lean.** The buffer is 64 bytes. After it on the stack sits the saved base
pointer (8 bytes) and then the saved **return address** — the place the
program will jump to when the current function ends. If you can overwrite
that return address with the address of a more interesting function (look
for one whose name suggests it's helpful), the program will jump there when
it finishes reading your input. The binary is built without ASLR
(`-no-pie`) and without stack canaries, so the address is fixed and the
overflow isn't blocked. You'll need to send exactly the right number of
padding bytes, then the address in little-endian 64-bit form. `pwntools` is
purpose-built for this — `from pwn import *` gives you `remote()`,
`p64()`, and friends.

### The lesson

Unbounded input + a writable stack = an attacker chooses where the program
goes next. Modern mitigations (stack canaries, ASLR, non-executable stack)
make this harder; here they're deliberately off so the bug is the lesson,
not the bypass.

---

## 3. crypto-xor (port 9003)

### What you see

A web page titled "Intercepted transmission" with a long hex string and a
note: *"We sniffed this hex off the wire. The key is a single byte."*

### The skill area

**Cryptography keyspace, and why "obfuscation" isn't encryption.** The
algorithm itself (XOR) is fine — it's the *key size* that's the problem.

### Hints

**Nudge.** The note tells you the key is one byte. How many distinct values
fit in one byte? Could you... try them all?

**Push.** XOR has a useful property: applying the same key twice cancels
out. So if you XOR the ciphertext with the right key, you get the plaintext
back. With only 256 possible keys, you can iterate through all of them and
print whichever result *looks like* the flag.

**Lean.** You know the flag format starts with `CTF{`. Loop key `k` from 0
to 255, XOR each byte of the ciphertext with `k`, and check whether the
result starts with `CTF{`. The one that does is the plaintext. Five lines of
Python.

### The lesson

A cipher is only as strong as its keyspace. 256 keys is "instantly
brute-forceable" — it isn't encryption, it's coding. Real symmetric crypto
uses 128- or 256-bit keys for a reason.

---

## 4. forensics-hidden (port 9004)

### What you see

A page titled "Recovered evidence" with a download link to `vacation.png`
and a hint: *"Forensics says the file is 'bigger than it looks.'"*

Download the file. It opens in any image viewer and shows a 1-pixel image.
That's it. Or is it?

### The skill area

**File format forensics.** Programs that read structured files often stop
at the structure's declared end and ignore whatever follows. That blind
spot is a classic hiding place.

### Hints

**Nudge.** An image viewer is one way to look at a file. It's not the only
way. Most files have a *defined* end — but the file on disk doesn't have to
stop there. What's the size of the file on disk, vs. how much data does the
image itself actually contain?

**Push.** A PNG file has a clear structural end marker (the `IEND` chunk).
Anything after that marker is, as far as the PNG spec is concerned,
garbage — but it's still bytes sitting in the file. Tools that read raw
bytes instead of parsing the image will see it. Two suggestions: `strings`
and `binwalk`.

**Lean.** Run `strings vacation.png | grep CTF` and read the output. If
you'd rather see the structure, `binwalk vacation.png` reports the
identified chunks and any trailing data.

### The lesson

"Looks like an image" ≠ "contains only an image." When investigating a
suspicious file, never trust the renderer — inspect raw bytes.

---

## 5. web-filevault (port 9005)

### What you see

A small "FileVault document viewer" web app. It lists two text documents
(`welcome.txt`, `notes.txt`) and lets you read each via a link like
`/view?file=welcome.txt`. It returns the file's contents inside a `<pre>`
block.

### The skill area

**Path traversal, also called Local File Inclusion (LFI).** When an app
builds a filesystem path out of user input without sanitizing, you can
escape the directory the developer intended you to read from.

### Hints

**Nudge.** The URL parameter `file=` tells the server which document to
read. The server is presumably looking in some directory for it. What if
you asked it for a file that *isn't* in that directory? How might you write
a filename that refers to *up one directory* on a Unix filesystem?

**Push.** Filesystems understand `..` as "parent directory." If the app
joins `docs/` + your input directly, then `../something` escapes `docs/`
into the parent directory. Try fetching files that obviously shouldn't be
in `docs/` — start with files you know exist on a Linux box
(`/etc/hostname` reached via enough `../`, for example) to confirm the bug,
then look for something flag-shaped.

**Lean.** The flag file is named `flag.txt`, and it lives one level above
the `docs/` directory the app reads from. So a single `../` in the
parameter is enough to escape, followed by the relative path to the flag.
You may need to guess the directory name the flag sits in — "secret" is a
reasonable first guess. If one `../` isn't enough, the app might be
running from a deeper working directory; try more.

### The lesson

Never build a filesystem path from raw user input. Real fixes: validate
against an allowlist of permitted filenames; strip `..` and path
separators; or resolve the final path with `realpath`/`os.path.realpath`
and confirm it stays inside the intended directory.

---

## Tools you might want

The lightweight player shell has everything used above:

```bash
nix develop .#player
```

That gives you `curl`, `python3` + `pwntools` + `pycryptodome`, `gdb`,
`radare2`, `binwalk`, `exiftool`, `nc`, and `socat`. Enough for all five.

For the heavier offensive toolbox (Burp, Ghidra, Metasploit, etc.) see
`RED-TEAM.md`.

---

## Organizer setup (skip if you're a player)

Each challenge needs to be registered in CTFd with its flag. Where each
flag lives:

| Challenge            | Flag location                              |
|----------------------|--------------------------------------------|
| web-cookie-monster   | `app.py`, `FLAG = ...`                     |
| pwn-stackoverflow    | `PWN_FLAG` in `.env` (build-arg injected)  |
| crypto-xor           | `app.py`, `FLAG = ...`                     |
| forensics-hidden     | `gen.py`, appended to `vacation.png`       |
| web-filevault        | `WEB_FLAG` in `.env` (build-arg injected)  |

Copy each into CTFd's admin UI when you create the challenge entry. Players
never have repo access; they only see the running services on ports
9001–9005.
