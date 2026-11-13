#!/bin/bash
# First-time RAG setup for Longleaf / Hickory.
#   bash setup_rag.sh            set up (or finish setting up); finished parts are reused
#   bash setup_rag.sh --rebuild  throw away the Python environment and build it again
#
# There is exactly one Python environment ($WORK/rag-venv) and one container
# ($WORK/ollama.sif). To refresh the container, delete ollama.sif and re-run setup.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Instructors: pin this to the version you tested (e.g. docker://ollama/ollama:0.12.0)
OLLAMA_IMAGE=${OLLAMA_IMAGE:-docker://ollama/ollama:latest}
BASE_MODEL=llama3.2:3b
EMBED_MODEL=all-MiniLM-L6-v2
VENV="$WORK/rag-venv"

echo "Starting RAG setup in $RAG_DIR"
cd "$RAG_DIR" || fail "cannot enter $RAG_DIR"
[ -f requirements.txt ] || fail "requirements.txt not found in $RAG_DIR."

echo "1/5 Python environment (first time takes 15-20 minutes; pip output is quiet, so be patient)..."
load_modules default
echo "    Python: $(python --version 2>&1) at $(command -v python)"

if [ "$1" = "--rebuild" ]; then
  echo "    --rebuild: removing the old environment."
  rm -rf "$VENV"
fi
if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import sys' >/dev/null 2>&1; then
  echo "    Reusing the existing environment."
else
  [ -e "$VENV" ] && echo "    The existing environment is broken; rebuilding it."
  rm -rf "$VENV"
  python -m venv "$VENV" || fail "could not create the virtual environment."
fi

# Remember which Python module built the venv, so start.sh loads the very same one.
PYMOD=$(module -t list 2>&1 | grep -i '^python' | head -n 1)
[ -n "$PYMOD" ] && echo "$PYMOD" > "$VENV/.python-module"

activate_venv
pip install -q --no-cache-dir -r requirements.txt || fail "pip install failed."
python -c "import flask, rag, openai, pypdf, dotenv, sentence_transformers" \
  || fail "packages installed but could not be imported. Try: bash setup_rag.sh --rebuild"

echo "2/5 Embedding model (so the first 'ingest' needs no network)..."
python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('$EMBED_MODEL')" \
  || fail "could not download the embedding model."

echo "3/5 Ollama container..."
if [ -f "$OLLAMA_SIF" ]; then
  echo "    already downloaded, skipping."
else
  apptainer pull "$OLLAMA_SIF" "$OLLAMA_IMAGE" || fail "apptainer pull failed."
fi

echo "4/5 Language model $BASE_MODEL (about 2 GB; skipped if already downloaded)..."
export OLLAMA_HOST=127.0.0.1:$(pick_port 11500)
build_apptainer_cmd
"${APPT[@]}" ollama serve > ollama.log 2>&1 &
OLLAMA_PID=$!
cleanup() { pkill -P "$OLLAMA_PID" 2>/dev/null; kill "$OLLAMA_PID" 2>/dev/null; wait "$OLLAMA_PID" 2>/dev/null; }
trap cleanup EXIT
if ! wait_for_ollama "$OLLAMA_PID"; then
  echo "---- last lines of ollama.log ----"; tail -n 20 ollama.log
  fail "Ollama server did not start."
fi
"${APPT[@]}" ollama pull "$BASE_MODEL" || fail "model download failed."
cleanup
trap - EXIT

echo "5/5 Settings..."
if [ -f .env ]; then
  echo "    .env already exists, leaving it alone."
else
  cp .env.example .env || fail "could not copy .env.example."
fi
mkdir -p data

echo
echo "Setup complete! Next:"
echo "  1. Put .txt / .pdf files in $RAG_DIR/data/"
echo "  2. bash start.sh ingest"
echo "  3. bash start.sh        (web page)   or   bash start.sh cli   (terminal)"
