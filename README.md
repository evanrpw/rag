## Quick start

1. Get a Slurm session with **at least 4 CPUs and 16 GB** (section 0).
2. First time only: `bash setup_rag.sh`
3. Put `.txt` / `.pdf` files in `data/`, then `bash start.sh ingest`
4. `bash start.sh` (web page) or `bash start.sh cli` (ask questions in the terminal)

Always run these with `bash`, from inside the `rag` folder, never with `source`.

## How it works

```
data/*.txt, *.pdf --ingest--> chunks + embeddings --> chroma_db/ (local vector database)

your question --> embed --> find the 3 closest chunks --> Llama answers from them --> web page or terminal
```

| File | What it does |
|------|--------------|
| `setup_rag.sh` | Run **once**: installs Python packages, downloads Ollama and the models |
| `start.sh` | Run **every time**: `bash start.sh` (web), `bash start.sh cli` (terminal), `bash start.sh ingest` (index documents) |
| `common.sh` | Shared setup used by the two scripts above. You never run it |
| `ingest.py` | Splits your documents into chunks and stores them in `chroma_db/` |
| `rag.py` | Retrieval and answer generation |
| `server.py` | The web server (serves `public/index.html` and `/api/chat`) |
<<<<<<< Updated upstream
| `cli.py` | Run headless, so you don't need to access browser |
=======
| `cli.py` | The terminal front end, started by `bash start.sh cli` |
>>>>>>> Stashed changes
| `.env` | Settings (created by the setup script from `.env.example`) |

## 0. Get a Slurm session (don't run on the login node)

Longleaf's rules: **research applications must not run on the login node.** The scripts
refuse to run there. **Ask for at least 4 CPUs and 16 GB of memory.** With fewer CPUs
answers take minutes. `start.sh` automatically uses however many CPUs your session has.

**Option A: Open OnDemand (easiest for viewing the web page)**
Log in at https://ondemand.rc.unc.edu/ and start a Longleaf Desktop session. **In the launch
form set CPUs to 4 or more and memory to 16 GB or more.** Open a terminal inside the desktop
and follow the steps below. You can open a web browser inside the same desktop, so no SSH
tunnel is needed. You may want to request a GPU session, or at least more CPU memory, to avoid running OOM.

**Option B: SSH + interactive session**
```bash
ssh <your-onyen>@longleaf.unc.edu          # off campus: connect to the UNC VPN first
srun -t 4:00:00 -p interact -n 1 --cpus-per-task=4 --mem=16g --pty /bin/bash
```
Your prompt will change to a compute node name. Run everything below in that shell.
The `interact` partition allows at most 8 hours. When the time runs out, the session ends and
the app stops, so just start a new one.

## 1. First-time setup (once)

1. Find your work folder. It is `/work/users/<x>/<y>/<your-onyen>` or, for newer accounts,
   `/hickory/users/<x>/<y>/<your-onyen>`. Check with:
   `ls -d /work/users/*/*/$USER /hickory/users/*/*/$USER 2>/dev/null`
2. Upload the project files to a folder named `rag` inside it.
3. In your Slurm session (section 0), run:
   ```bash
   cd <your work folder>/rag
   bash setup_rag.sh
   ```
   This takes **15-20 minutes** and downloads a few GB. It prints little while pip works, so
   be patient. Wait for `Setup complete!`. It is safe to re-run if something fails.

**About Python environments.** The project uses exactly one: `rag-venv`, next to the `rag`
folder. You never activate anything yourself, and a conda `(base)` or any other environment
active in your shell is ignored by these scripts. Don't create other environments for this
project. If `start.sh` says the environment is broken or missing, run
`bash setup_rag.sh --rebuild`. To clean up old attempts (check the names first):
`ls -d <your work folder>/*venv*` and delete extras with `rm -rf`.

## 2. Add your documents

Put `.txt` and `.pdf` files in the `data/` folder inside `rag/` (subfolders are fine), then build the database:

```bash
bash start.sh ingest
```

- Run it again any time you add, change or delete files. Unchanged files are skipped, and
  files you deleted from `data/` are removed from the database.
- To wipe the database and start fresh: `bash start.sh ingest --reset`
- Scanned PDFs (images of text) won't work. The PDF must contain real, selectable text; the
  script warns you if it finds none.
- The last line tells you how many chunks and files are in the database.

## 3. Start the app (every time)

Start a Slurm session (section 0), then:

```bash
cd <your work folder>/rag
bash start.sh          # web page
bash start.sh cli      # or: ask questions in the terminal, no browser needed
```

`start.sh` prints a line starting `node=...` with your session's facts, loads the model
(**up to a minute or two the first time**), and then tells you the address to open. Later
questions take roughly 5-20 seconds.

Press **Ctrl+C** to stop. This shuts down Ollama too.

### Opening the page

The port is usually 3001, but `start.sh` picks another free one if needed. **Use the address it prints.**

- **OnDemand desktop:** open a browser inside the desktop and go to the printed address.
- **SSH:** the app is on a compute node, not on your laptop, so you need a tunnel.
  `start.sh` prints the exact command with your node name filled in. Run it on
  **your own computer**, then browse to the address it shows. If it is refused, use the
  OnDemand option instead.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `This must not run on the login node` | Start a Slurm session first (section 0) |
| `WARNING: this session has only N CPU(s)` | Restart your session with 4 or more CPUs. In OnDemand set CPUs in the launch form |
| `Python environment missing` / `ollama.sif is missing` | Run `bash setup_rag.sh` |
| `Python environment is broken` / `libpython ... cannot open shared object file` | Run `bash setup_rag.sh --rebuild` |
| `could not prepare model` | The model isn't downloaded. Re-run `bash setup_rag.sh` |
| Answer is always "I don't know based on the provided documents." | Run `bash start.sh ingest`. The database is probably empty or your question doesn't match the documents |
| Answers seem to ignore a document you added | Re-run `bash start.sh ingest` and check it printed your file's name |
| Page says "Error: No answer from the model..." | `start.sh` must still be running in this same session. If it is, the model is overloaded; check `ollama.log` |
| Page can't reach the server / tunnel errors (`Connection refused`) | `start.sh` isn't running on the node in your tunnel command. Start it, then use the tunnel command it prints |
| "The model did not respond within 5 minutes" | Check the CPU count in the `node=...` line and the `ollama.log` lines it printed |
| Slow answers | Normal on CPU. Keep questions focused; more CPUs in your session help |
| Session ended and the app disappeared | Slurm sessions have a time limit. Start a new session and run `bash start.sh` again |
| Disk quota errors | Make sure `rag` lives in your work folder, not your home directory |
| Anything else | Send your instructor the `node=...` line and the last 20 lines of `ollama.log` |

## Settings (optional)

Edit `.env` in the `rag` folder:

- `LOCAL_LLM_MODEL`: the Ollama model name (default `llama3.2:3b`). Other models must be downloaded first.
- `LOCAL_EMBEDDING_MODEL`: the embedding model. **If you change it, run `bash start.sh ingest`**
  (it downloads the new model and re-indexes). Each embedding model gets its own collection.
- Chunk size is set at the top of `ingest.py`. Changing it re-ingests every file on the next run.
- The Ollama address and port are set automatically by `start.sh`.

## For instructors

- **Pin versions** so every student gets what you tested. After a working setup, run
  `pip freeze > requirements.txt` in the venv (large because of PyTorch, but exact), and pin
  the Ollama container by setting `OLLAMA_IMAGE=docker://ollama/ollama:<version>` when running
  `setup_rag.sh`, or by editing the default at the top of that file.
- `start.sh` creates a small per-session model named like `rag-llama3.2-3b-t4` whose thread
  count equals the Slurm allocation. The weights are shared, so it costs almost no disk.
- Ollama stays loaded for 4 hours of idle time, so questions after a pause aren't slow.
