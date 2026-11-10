#!/bin/bash
# First-time RAG setup for Longleaf / Hickory.
# Run with:  bash setup_rag.sh   (or: source setup_rag.sh)

# Exit helper that works whether the script is sourced or executed
die() { echo "Error: $*" >&2; return 1 2>/dev/null || exit 1; }

echo "Starting First-Time RAG Setup..."

# ---------------------------------------------------------------
# 0. Slurm check + locate your project folder (/work/... or /hickory/users/...)
# ---------------------------------------------------------------
if [ -z "$SLURM_JOB_ID" ] && [ -z "$ALLOW_LOGIN_NODE" ]; then
  echo "This script is heavy and must not run on the login node."
  echo "Start an interactive session first, then re-run this script:"
  echo "  srun -t 2:00:00 -p interact -n 1 --cpus-per-task=4 --mem=16g --pty /bin/bash"
  echo "(Or use an Open OnDemand session.)"
  die "not inside a Slurm session"
fi

WORK=""
for d in /work/users/*/*/"$USER" /hickory/users/*/*/"$USER"; do
  if [ -d "$d/rag" ]; then WORK=$d; break; fi
done
if [ -z "$WORK" ]; then
  echo "Couldn't find a 'rag' folder. Looked in:"
  ls -d /work/users/*/*/"$USER" /hickory/users/*/*/"$USER" 2>/dev/null | sed 's/^/  /'
  die "Upload the project files to a folder named 'rag' inside one of the paths above."
fi
export WORK
echo "Using work directory: $WORK"

cd "$WORK/rag" || die "Please upload the project files to $WORK/rag first."
[ -f requirements.txt ] || die "requirements.txt not found in $WORK/rag."

# ---------------------------------------------------------------
# 1. Cache locations (keep everything out of the small home quota)
# ---------------------------------------------------------------
export HF_HOME=$WORK/.cache/huggingface
export PIP_CACHE_DIR=$WORK/.cache/pip
export APPTAINER_CACHEDIR=$WORK/.cache/apptainer
export APPTAINER_TMPDIR=$WORK/.cache/apptainer/tmp
mkdir -p "$HF_HOME" "$PIP_CACHE_DIR" "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR"

# ---------------------------------------------------------------
# 2. Python environment
# ---------------------------------------------------------------
echo "1. Building Python Environment (This may take 15-20 minutes)..."
module purge
module load python apptainer || die "could not load python/apptainer modules."

python -m venv "$WORK/rag-venv" || die "could not create virtual environment."
source "$WORK/rag-venv/bin/activate"

pip install -v --no-cache-dir -r requirements.txt || die "pip install failed."

# ---------------------------------------------------------------
# 3. Ollama container
# ---------------------------------------------------------------
echo "2. Downloading Ollama Server Container..."
apptainer pull "$WORK/ollama.sif" docker://ollama/ollama || die "apptainer pull failed."

# ---------------------------------------------------------------
# 4. Start Ollama and pull the model
# ---------------------------------------------------------------
echo "3. Starting backend to download the LLM..."
export OLLAMA_MODELS=$WORK/ollama-models
export OLLAMA_HOST=127.0.0.1:11500
export OLLAMA_SIF=$WORK/ollama.sif
mkdir -p "$OLLAMA_MODELS"

run_ollama() {
  apptainer exec --nv --bind "$WORK" \
    --env OLLAMA_HOST="$OLLAMA_HOST" \
    --env OLLAMA_MODELS="$OLLAMA_MODELS" \
    "$OLLAMA_SIF" ollama "$@"
}

run_ollama serve > ollama.log 2>&1 &
OLLAMA_PID=$!

# Wait up to ~2 minutes for the server to come up
ready=0
for i in {1..60}; do
  if curl -s "http://$OLLAMA_HOST" >/dev/null 2>&1; then ready=1; break; fi
  # stop waiting early if the server process already died
  kill -0 "$OLLAMA_PID" 2>/dev/null || break
  sleep 2
done
if [ "$ready" -ne 1 ]; then
  echo "---- last lines of ollama.log ----"
  tail -n 20 ollama.log
  kill "$OLLAMA_PID" 2>/dev/null
  die "Ollama server did not start."
fi

echo "4. Downloading Llama 3.2 Model (2GB)..."
run_ollama pull llama3.2:3b || {
  kill "$OLLAMA_PID" 2>/dev/null
  die "model download failed."
}

# Stop the temporary server so it doesn't keep running on the login node
kill "$OLLAMA_PID" 2>/dev/null
wait "$OLLAMA_PID" 2>/dev/null

# ---------------------------------------------------------------
# 5. Config
# ---------------------------------------------------------------
echo "5. Configuring environment variables..."
if [ -f .env ]; then
  echo "   .env already exists, leaving it alone."
else
  cp .env.example .env || die "could not copy .env.example (is it uploaded?)."
fi

echo
echo "Setup Complete!"
echo "To initialize the vector database, run:"
echo "  source $WORK/rag-venv/bin/activate"
echo "  cd $WORK/rag"
echo "  python ingest.py"