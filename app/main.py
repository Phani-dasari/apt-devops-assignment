from flask import Flask

app = Flask(_name_)

@app.route("/")
def index():
    return "Hello from Apt DevOps assignment!", 200

@app.route("/health")
def health():
    return "ok", 200

if _name_ == "_main_":
    app.run(host="0.0.0.0", port=8080)
