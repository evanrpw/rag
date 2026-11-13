#!/bin/bash
# Launch the RAG app. Run with bash (not source):
#   bash start.sh                    web app
#   bash start.sh cli                ask questions in the terminal
#   bash start.sh ingest [--reset]   index the files in data/

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  echo "Please run this with:  bash start.sh   (not source)"
  return 1
fi

MODE=${1:-web}
case "$MODE" in
  web|cli|ingest) ;;
  *) echo "Usage: bash start.sh [web|cli|ingest [--reset]]"; exit 1 ;;
esac

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$RAG_DIR" || fail "cannot enter $RAG_DIR"
load_modules
activate_venv

# Indexing needs no Ollama.
if [ "$MODE" = "ingest" ]; then
  shift
  exec python ingest.py "$@"
fi

[ -f "$OLLAMA_SIF" ] || fail "$OLLAMA_SIF is missing. Run: bash setup_rag.sh"

# --- Match the model's thread count to this Slurm session ---
THREADS=${SLURM_CPUS_PER_TASK:-${SLURM_CPUS_ON_NODE:-4}}
export OMP_NUM_THREADS=$THREADS
if [ "$THREADS" -lt 4 ]; then
  echo "WARNING: this session has only $THREADS CPU(s); answers will be very slow."
  echo "         Restart your session with --cpus-per-task=4 (or more)."
fi

# --- Free ports, so a leftover process or another student never blocks you ---
export OLLAMA_HOST=127.0.0.1:$(pick_port 11500)
export LOCAL_LLM_BASE_URL="http://$OLLAMA_HOST/v1"   # real env vars override .env
if [ "$MODE" = "web" ]; then export PORT=$(pick_port 3001); fi

# Offline is safe here: 'ingest' already cached the embedding model, and it avoids
# long waits when a compute node cannot reach huggingface.co.
export HF_HUB_OFFLINE=1

echo "node=$(hostname) job=$SLURM_JOB_ID cpus=$THREADS mem=${SLURM_MEM_PER_NODE:-?}MB gpu=$([ -n "$NV" ] && echo yes || echo no) time_left=$(squeue -h -j "$SLURM_JOB_ID" -o %L 2>/dev/null)"

# --- Start Ollama ---
build_apptainer_cmd
echo "Starting Ollama..."
"${APPT[@]}" ollama serve > ollama.log 2>&1 &
OLLAMA_PID=$!

cleanup() {
  echo
  echo "Shutting down Ollama..."
  pkill -P "$OLLAMA_PID" 2>/dev/null
  kill "$OLLAMA_PID" 2>/dev/null
  wait "$OLLAMA_PID" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM

if ! wait_for_ollama "$OLLAMA_PID"; then
  echo "Ollama did not start. Last lines of ollama.log:"
  tail -n 20 ollama.log
  exit 1
fi

# --- Per-session model variant that uses exactly this session's CPU count ---
BASE_MODEL=${LOCAL_LLM_MODEL:-$(grep -E '^LOCAL_LLM_MODEL=' .env 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d "\"' \r")}
BASE_MODEL=${BASE_MODEL:-llama3.2:3b}
MODEL_RUN="rag-${BASE_MODEL//[:\/]/-}-t${THREADS}"
printf 'FROM %s\nPARAMETER num_thread %s\n' "$BASE_MODEL" "$THREADS" > "$RAG_DIR/.Modelfile.run"
if ! "${APPT[@]}" ollama create "$MODEL_RUN" -f "$RAG_DIR/.Modelfile.run" > create.log 2>&1; then
  cat create.log
  fail "could not prepare model '$BASE_MODEL'. Is it downloaded? (bash setup_rag.sh downloads llama3.2:3b)"
fi
export LOCAL_LLM_MODEL=$MODEL_RUN

# --- Warm-up: load the model now, with a timeout, so a problem shows up here ---
echo "Loading model $BASE_MODEL with $THREADS threads (first time can take a minute or two)..."
START=$(date +%s)
if ! curl -sS -f -m 300 -o /dev/null "http://$OLLAMA_HOST/api/generate" \
     -d "{\"model\":\"$MODEL_RUN\",\"prompt\":\"Say hi\",\"stream\":false,\"options\":{\"num_predict\":5}}"; then
  echo "The model did not respond within 5 minutes. Last lines of ollama.log:"
  tail -n 20 ollama.log
  echo "If you ask for help, copy the 'node=...' line above and these log lines."
  exit 1
fi
echo "Model ready in $(( $(date +%s) - START ))s."

# --- Run the front end ---
if [ "$MODE" = "cli" ]; then
  python cli.py
else
  echo
  echo "Web app: http://localhost:$PORT   (open it in the browser inside your OnDemand desktop)"
  echo "From your own laptop, run this there first, then open http://localhost:$PORT :"
  echo "  ssh -L $PORT:localhost:$PORT -J $USER@longleaf.unc.edu $USER@$(hostname -s)"
  echo "Press Ctrl+C to stop."
  echo
  python server.py
fi
