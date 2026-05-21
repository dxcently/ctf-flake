# Deliberately vulnerable: a "document viewer" that builds a file path directly
# from a user-supplied query parameter with no sanitization. This is a classic
# Local File Inclusion / path traversal bug.
#
# Intended path: GET /view?file=welcome.txt  -> reads docs/welcome.txt
# Exploit:       GET /view?file=../secret/flag.txt  -> escapes the docs dir
#
# Lesson: never build a filesystem path from raw user input. Real fixes:
# validate against an allowlist, strip path separators, or resolve and confirm
# the final path stays within the intended directory.
import os
from flask import Flask, request

app = Flask(__name__)
DOCS_DIR = "docs"

# Seed a couple of legitimate documents at startup (writable tmpfs at runtime).
os.makedirs(DOCS_DIR, exist_ok=True)
with open(os.path.join(DOCS_DIR, "welcome.txt"), "w") as f:
    f.write("Welcome to FileVault. Use ?file=welcome.txt to read a document.")
with open(os.path.join(DOCS_DIR, "notes.txt"), "w") as f:
    f.write("Meeting notes: remember to sanitize user input. (We forgot.)")

@app.route("/")
def index():
    return ("<h1>FileVault document viewer</h1>"
            "<p>Read a document: <code>/view?file=welcome.txt</code></p>"
            "<ul><li><a href='/view?file=welcome.txt'>welcome.txt</a></li>"
            "<li><a href='/view?file=notes.txt'>notes.txt</a></li></ul>")

@app.route("/view")
def view():
    name = request.args.get("file", "welcome.txt")
    # THE BUG: path is built straight from user input, no validation.
    path = os.path.join(DOCS_DIR, name)
    try:
        with open(path, "r") as fh:
            return "<pre>" + fh.read() + "</pre>"
    except Exception as e:
        return f"<pre>Could not read {name}: {e}</pre>", 404

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
