## How it works

```
data/*.txt, *.pdf --ingest.py--> chunks + embeddings --> chroma_db/ (local vector database)

your question --> embed --> find the 3 closest chunks --> Llama answers from them --> web page
```

| File | What it does |
|------|--------------|
| `setup_rag.sh` | Run **once**: installs Python packages, downloads Ollama and the model |
| `start.sh` | Run **every time**: starts Ollama and the web app (also builds the database) |
| `ingest.py` | Splits your documents into chunks and stores them in `chroma_db/` |
| `rag.py` | Retrieval and answer generation |
| `server.py` | The web server (serves `public/index.html` and `/api/chat`) |
| `cli.py` | Run headless, so you don't need to access browser |
| `.env` | Settings (created by the setup script from `.env.example`) |

## 0. Don't run this on the login node

Longleaf's rules: **research applications must not run on the login node.** Both scripts
refuse to run there. You need a Slurm session first. Pick one of these:

**Option A: Open OnDemand (easiest for viewing the web page)**
Log in at https://ondemand.rc.unc.edu/ and start a Longleaf Desktop session. Open a terminal
inside it and follow the steps below. You can open a web browser inside the same desktop,
so no SSH tunnel is needed. You may want to request a GPU session, or at least more CPU memory, to avoid running OOM.

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
3. In your Slurm session (section 0), go to that folder and run:
   ```bash
   cd <your work folder>/rag
   bash setup_rag.sh
   ```
   This takes **15-20 minutes** and downloads a few GB. Wait for `Setup Complete!`.
   It is safe to re-run if something fails.

## 2. Add your documents

Put `.txt` and `.pdf` files in the `data/` folder inside `rag/` (subfolders are fine), then build the database:

```bash
bash start.sh ingest
```

- Run it again any time you add or change files. Unchanged files are skipped.
- To wipe the database and start fresh: `bash start.sh ingest --reset`
- Scanned PDFs (images of text) won't work. The PDF must contain real, selectable text.
- The first run downloads a small embedding model, which can take a minute.

## 3. Start the app (every time)

Start a Slurm session (section 0), then:

```bash
cd <your work folder>/rag
bash start.sh
```

Wait for `Starting web interface`, then open **http://localhost:3001**.
The first question can take about 60 seconds while the model loads. Later ones are faster.

Press **Ctrl+C** to stop. This shuts down Ollama too.

Run it with `bash start.sh`, not `source start.sh`.

### Opening the page

- **OnDemand desktop:** open a browser inside the desktop and go to http://localhost:3001.
- **SSH:** the app is on a compute node, not on the login node or your laptop, so you need a
  tunnel to that node. Run `hostname` in your Slurm session to get the node name, then on
  **your own computer** run:
  ```bash
  ssh -L 3001:localhost:3001 -J <your-onyen>@longleaf.unc.edu <your-onyen>@<node-name>
  ```
  and browse to http://localhost:3001. If this is refused, use the OnDemand option instead.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Please don't run this on the login node` | Start a Slurm session first (section 0) |
| `couldn't find a 'rag' folder` | The `rag` folder must be directly inside your work folder. The script lists where it looked |
| Answer is always "I don't know based on the provided documents." | Run `bash start.sh ingest`. The database is probably empty or your question doesn't match the documents |
| Answers seem to ignore a document you added | Re-run `bash start.sh ingest` and check it printed your file's name |
| `Address already in use` on port 3001 | Someone else is using that port on this node. Stop your old run, or ask your instructor |
| Slow answers | Normal on CPU. A 3B model takes a while per answer; keep questions focused |
| Session ended and the app disappeared | Slurm sessions have a time limit. Start a new session and run `bash start.sh` again |
| Disk quota errors | Make sure everything lives in your work folder, not your home directory |

## Settings (optional)

Edit `.env` in the `rag` folder:

- `LOCAL_LLM_MODEL`: the Ollama model name (default `llama3.2:3b`). Other models must be downloaded first.
- `LOCAL_EMBEDDING_MODEL`: the embedding model. **If you change it, re-run `bash start.sh ingest`.**
  Each embedding model gets its own collection in the database.
- Chunk size is set at the top of `ingest.py`. Changing it re-ingests every file on the next run.
- The Ollama address is set automatically by `start.sh`, so you don't need to edit it.
