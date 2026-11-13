"""Tiny web server: serves public/index.html and a POST /api/chat endpoint."""

import os

from flask import Flask, jsonify, request

from rag import generate_response

app = Flask(__name__, static_folder="public", static_url_path="")


@app.get("/")
def home():
    return app.send_static_file("index.html")


@app.post("/api/chat")
def chat():
    query = (request.get_json(silent=True) or {}).get("query", "").strip()
    if not query:
        return jsonify({"error": "Query is required"}), 400
    try:
        return jsonify(generate_response(query))
    except Exception as e:
        app.logger.exception("RAG pipeline failed")
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    # start.sh picks a free port and passes it in PORT. debug stays off: it loads the
    # embedding model twice, leaves a reloader process behind, and exposes a debugger
    # on a node shared with other users.
    port = int(os.environ.get("PORT", 3001))
    print(f"RAG app running at http://localhost:{port}")
    app.run(host="127.0.0.1", port=port, debug=False)
