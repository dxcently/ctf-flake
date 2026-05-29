# Build a "vacation photo" with the flag appended after the image's real EOF.
# Players use `binwalk`, `strings`, or a hex editor to recover it.
#
# We construct a *valid* 1x1 RGB PNG from scratch (stdlib only — struct + zlib)
# rather than shipping a hand-typed hex blob; CRCs are computed, so the image
# actually renders. That preserves the lesson: the file IS a real PNG to a
# viewer, and the trick is the bytes sitting past its real EOF.
import struct, zlib

flag = b"CTF{d4ta_after_3OF_is_a_classic_hiding_sp0t}"

def chunk(ctype: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + ctype + data +
            struct.pack(">I", zlib.crc32(ctype + data) & 0xffffffff))

sig  = b"\x89PNG\r\n\x1a\n"
ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
# One scanline: filter byte 0, then one RGB pixel (3 bytes), zlib-compressed.
idat = chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00"))
iend = chunk(b"IEND", b"")

with open("vacation.png", "wb") as f:
    f.write(sig + ihdr + idat + iend)
    f.write(b"\n# nothing to see here\n")
    f.write(flag)
