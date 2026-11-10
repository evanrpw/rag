"""Tiny web server: serves public/index.html and a POST /api/chat endpoint."""

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
        return jsonify({"error": f"Failed to process query: {e}"}), 500


if __name__ == "__main__":
    print("RAG app running at http://localhost:3001")
    app.run(port=3001, debug=True)
