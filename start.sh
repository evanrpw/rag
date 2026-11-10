#!/bin/bash
# Launch the RAG app (Ollama backend + web interface).
# Run with:  bash start.sh      (do not 'source' this file)

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  echo "Please run this with:  bash start.sh   (not source)"
  return 1
fi

echo "Setting up Longleaf RAG environment..."

# Must run inside a Slurm session (srun or Open OnDemand), not on the login node
if [ -z "$SLURM_JOB_ID" ] && [ -z "$ALLOW_LOGIN_NODE" ]; then
  echo "Please don't run this on the login node. Start an interactive session first:"
  echo "  srun -t 4:00:00 -p interact -n 1 --cpus-per-task=4 --mem=16g --pty /bin/bash"
  echo "then run:  bash start.sh"
  echo "(Or use an Open OnDemand session.)"
  exit 1
fi

# Locate the folder that contains your rag/ project (/work/... or /hickory/users/...)
WORK=""
for d in /work/users/*/*/"$USER" /hickory/users/*/*/"$USER"; do
  if [ -d "$d/rag" ]; then WORK=$d; break; fi
done
if [ -z "$WORK" ]; then
  echo "Error: couldn't find a 'rag' folder. Looked in:"
  ls -d /work/users/*/*/"$USER" /hickory/users/*/*/"$USER" 2>/dev/null | sed 's/^/  /'
  exit 1
fi
export WORK

cd "$WORK/rag" || { echo "Error: $WORK/rag not found"; exit 1; }
[ -f "$WORK/ollama.sif" ] || { echo "Error: $WORK/ollama.sif missing. Run the setup script first."; exit 1; }

echo "Loading modules and environment..."
module purge
module load python apptainer || { echo "Error: could not load modules."; exit 1; }
source "$WORK/rag-venv/bin/activate" || { echo "Error: venv missing. Run the setup script first."; exit 1; }

export HF_HOME=$WORK/.cache/huggingface
export PIP_CACHE_DIR=$WORK/.cache/pip
export APPTAINER_CACHEDIR=$WORK/.cache/apptainer
export APPTAINER_TMPDIR=$WORK/.cache/apptainer/tmp
mkdir -p "$APPTAINER_TMPDIR"

# "bash start.sh ingest [--reset]" builds the vector database (no Ollama needed for this)
if [ "$1" = "ingest" ]; then
  shift
  python ingest.py "$@"
  exit $?
fi

export OLLAMA_SIF=$WORK/ollama.sif
export OLLAMA_MODELS=$WORK/ollama-models
mkdir -p "$OLLAMA_MODELS"

# Use port 11500 unless something (e.g. another student on this node) already has it
PORT=11500
if (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
  PORT=$(python -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  echo "Port 11500 is busy, using $PORT instead."
fi
export OLLAMA_HOST=127.0.0.1:$PORT
# rag.py reads this (via LOCAL_LLM_BASE_URL). Real environment variables take precedence
# over .env, so this always matches the port Ollama is actually using.
export LOCAL_LLM_BASE_URL="http://$OLLAMA_HOST/v1"

echo "Starting background Ollama server..."
apptainer exec --nv --bind "$WORK" \
  --env OLLAMA_HOST="$OLLAMA_HOST" \
  --env OLLAMA_MODELS="$OLLAMA_MODELS" \
  "$OLLAMA_SIF" ollama serve > ollama.log 2>&1 &
OLLAMA_PID=$!

# Always stop Ollama when this script exits (Ctrl+C, crash, or normal exit)
cleanup() {
  echo "Shutting down Ollama..."
  kill "$OLLAMA_PID" 2>/dev/null
  wait "$OLLAMA_PID" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM

echo "Waiting for backend to initialize..."
ready=0
for i in {1..60}; do
  if curl -s "http://$OLLAMA_HOST" >/dev/null 2>&1; then ready=1; break; fi
  kill -0 "$OLLAMA_PID" 2>/dev/null || break
  sleep 2
done
if [ "$ready" -ne 1 ]; then
  echo "Error: Ollama did not start. Last lines of ollama.log:"
  tail -n 20 ollama.log
  exit 1
fi

echo "Starting web interface (First question may take 60s to load)..."
python server.py