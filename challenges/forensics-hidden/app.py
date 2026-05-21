from flask import Flask, send_file
app = Flask(__name__)

@app.route("/")
def index():
    return ("<h1>Recovered evidence</h1>"
            "<p>This image was pulled from a suspect's drive. "
            "Forensics says the file is 'bigger than it looks.'</p>"
            "<p><a href='/vacation.png'>Download vacation.png</a></p>")

@app.route("/vacation.png")
def img():
    return send_file("vacation.png", mimetype="image/png")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
