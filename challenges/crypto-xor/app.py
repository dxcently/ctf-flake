# Serves a single-byte-XOR ciphertext. Players brute-force 256 keys.
# Lesson: tiny keyspaces fall instantly; this is a classic intro crypto chall.
from flask import Flask
app = Flask(__name__)
FLAG = b"CTF{xor_is_n0t_encryption_if_key_is_one_byte}"
KEY = 0x42
CT = bytes(b ^ KEY for b in FLAG).hex()

@app.route("/")
def index():
    return ("<h1>Intercepted transmission</h1>"
            "<p>We sniffed this hex off the wire. The key is a single byte.</p>"
            f"<pre>{CT}</pre>")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
