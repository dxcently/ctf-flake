# Build a "vacation photo" with the flag appended after the image's real EOF.
# Players use `binwalk`, `strings`, or a hex editor to recover it.
flag = b"CTF{d4ta_after_3OF_is_a_classic_hiding_sp0t}"
# Minimal valid 1x1 PNG.
png = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108020000009077"
    "53de0000000c4944415408d763f8cfc0f01f0005000601a4a4 b1 8e0000000049454e44ae426082"
    .replace(" ", ""))
with open("vacation.png", "wb") as f:
    f.write(png)
    f.write(b"\n# nothing to see here\n")
    f.write(flag)
