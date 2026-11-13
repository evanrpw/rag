"""Load .txt / .pdf files from data/ into the local ChromaDB.

Usage:
    python ingest.py            # add new files, update changed files, skip unchanged files,
                                # and forget files you deleted from data/
    python ingest.py --reset    # wipe this embedding model's collection first, then ingest

Updates are crash-safe: a changed file's chunks are overwritten in place (upsert) and only
then are leftover chunks removed, so a crash never leaves a file with zero chunks.
Re-running after a crash finishes the job.
"""

import hashlib
import os
import sys

import pypdf

from rag import collection, embed

EMBEDDING_BATCH = 16  # chunks sent per embedding call
CHUNK_SIZE = 1000
OVERLAP = 200


def extract_text(path):
    if path.lower().endswith(".txt"):
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    reader = pypdf.PdfReader(path)
    return "\n".join(page.extract_text() or "" for page in reader.pages)


def get_chunks(text, chunk_size=CHUNK_SIZE, overlap=OVERLAP):
    chunks, start = [], 0
    while start < len(text):
        chunks.append(text[start : start + chunk_size].strip())
        if start + chunk_size >= len(text):
            break
        start += chunk_size - overlap
    return [c for c in chunks if c]


def fingerprint(text):
    # Includes the chunk settings, so changing CHUNK_SIZE / OVERLAP re-ingests every file.
    return hashlib.sha256(f"{CHUNK_SIZE}:{OVERLAP}\n{text}".encode("utf-8")).hexdigest()


def ingest_file(path, source):
    text = extract_text(path)
    if not text.strip():
        print(f"  -> {source}: WARNING no text found (scanned PDF?). Nothing to search.")
    file_hash = fingerprint(text)

    # What is already stored for this file?
    old = collection.get(where={"source": source}, include=["metadatas"])
    old_ids = set(old["ids"])

    # Skip only if every stored chunk is from this exact file version AND none are missing
    # (chunk_count catches a previous run that crashed halfway).
    if old_ids and all(
        m.get("file_hash") == file_hash and m.get("chunk_count") == len(old_ids)
        for m in old["metadatas"]
    ):
        print(f"  -> {source}: unchanged, skipped.")
        return

    chunks = get_chunks(text)
    ids = [f"{source}::{i}" for i in range(len(chunks))]

    # Upsert: same ids are overwritten in place, new ids are added. No delete-first window.
    for start in range(0, len(chunks), EMBEDDING_BATCH):
        batch = chunks[start : start + EMBEDDING_BATCH]
        collection.upsert(
            ids=ids[start : start + len(batch)],
            documents=batch,
            embeddings=embed(batch),
            metadatas=[
                {
                    "source": source,
                    "chunkIndex": start + i,
                    "file_hash": file_hash,
                    "chunk_count": len(chunks),
                }
                for i in range(len(batch))
            ],
        )

    # Only now remove leftovers (e.g. the file got shorter, or is now empty).
    stale = list(old_ids - set(ids))
    if stale:
        collection.delete(ids=stale)

    print(f"  -> {source}: {len(chunks)} chunk(s) stored, {len(stale)} stale removed.")


def forget_deleted(seen_sources):
    """Remove chunks whose file is no longer in data/, so deleted files stop answering."""
    stored = collection.get(include=["metadatas"])
    gone_ids, gone_sources = [], set()
    for chunk_id, meta in zip(stored["ids"], stored["metadatas"]):
        if meta.get("source") not in seen_sources:
            gone_ids.append(chunk_id)
            gone_sources.add(meta.get("source"))
    if gone_ids:
        collection.delete(ids=gone_ids)
        for s in sorted(gone_sources):
            print(f"Removed deleted file from the database: {s}")


def ingest_directory(directory="data"):
    if not os.path.exists(directory):
        print(f"Directory '{directory}' not found. Create it and add .txt or .pdf files.")
        return None
    seen = set()
    for root, _, files in os.walk(directory):
        for name in sorted(files):
            if name.lower().endswith((".txt", ".pdf")):
                path = os.path.join(root, name)
                rel_path = os.path.relpath(path, directory)
                seen.add(rel_path)  # counted even if it fails, so old chunks are kept
                print(f"Processing: {rel_path}")
                try:
                    ingest_file(path, rel_path)
                except Exception as e:
                    print(f"  -> {rel_path}: FAILED ({e}). Skipped; fix the file and re-run.")
    forget_deleted(seen)
    return seen


if __name__ == "__main__":
    if "--reset" in sys.argv:
        existing_ids = collection.get()["ids"]
        if existing_ids:
            collection.delete(ids=existing_ids)
        print(f"Cleared {len(existing_ids)} existing chunk(s) via --reset.")
    files = ingest_directory()
    if files is not None:
        print(f"\nIngestion complete! Database now holds {collection.count()} chunk(s) from {len(files)} file(s).")
        if not files:
            print("No .txt or .pdf files found in data/. Add some and re-run.")
