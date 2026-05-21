# Deliberately vulnerable: trusts a client-set "role" cookie with no signing.
# Lesson: never trust client-controlled state for authz. Fix = signed sessions.
from flask import Flask, request, make_response
app = Flask(__name__)
FLAG = "CTF{c00kies_are_n0t_cR3dentials}"

@app.route("/")
def index():
    role = request.cookies.get("role", "guest")
    if role == "admin":
        return f"Welcome, admin. Here is the flag: {FLAG}"
    resp = make_response(
        "<h1>Members area</h1><p>You are logged in as: %s</p>"
        "<p>Only admins can see the flag.</p>" % role)
    resp.set_cookie("role", "guest")
    return resp

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
