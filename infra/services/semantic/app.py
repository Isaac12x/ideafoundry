import hashlib
import os
import sqlite3
import threading

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

MODEL = os.environ.get("SEMANTIC_MODEL", "BAAI/bge-small-en-v1.5")
DB_PATH = os.environ.get("SEMANTIC_DB", "/data/semantic.sqlite3")
CHUNK, OVERLAP, MAX_CHUNKS = 1000, 200, 64

app = FastAPI(title="Idea Foundry Local Semantic Index", version="1.0.0")
_lock = threading.Lock()  # one writer/reader at a time; sqlite + one CPU model
_db = None
_model = None


def db():
    global _db
    if _db is None:
        os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)
        _db = sqlite3.connect(DB_PATH, check_same_thread=False)
        _db.executescript(
            "CREATE TABLE IF NOT EXISTS docs(id TEXT PRIMARY KEY, hash TEXT);"
            "CREATE TABLE IF NOT EXISTS chunks(doc_id TEXT, n INT, vec BLOB);"
            "CREATE INDEX IF NOT EXISTS chunks_doc_id ON chunks(doc_id);"
        )
    return _db


def _embedder():
    global _model
    if _model is None:
        from fastembed import TextEmbedding  # lazy: tests don't need it

        _model = TextEmbedding(MODEL)
    return _model


def _norm(a):
    a = np.asarray(a, dtype=np.float32)
    return a / np.maximum(np.linalg.norm(a, axis=-1, keepdims=True), 1e-12)


def embed_passages(texts):
    return _norm(list(_embedder().passage_embed(texts)))


def embed_query(text):
    return _norm(list(_embedder().query_embed(text)))[0]


def chunk(text):
    out, i, n = [], 0, len(text)
    while i < n and len(out) < MAX_CHUNKS:
        end = min(i + CHUNK, n)
        if end < n:  # prefer a whitespace boundary in the back half of the window
            ws = max(text.rfind(" ", i, end), text.rfind("\n", i, end))
            if ws > i + CHUNK // 2:
                end = ws
        piece = text[i:end].strip()
        if piece:
            out.append(piece)
        if end >= n:
            break
        i = max(end - OVERLAP, i + 1)
    return out


class Item(BaseModel):
    id: str = Field(min_length=1)
    text: str


class Upsert(BaseModel):
    items: list[Item]


class Delete(BaseModel):
    ids: list[str]


class Prune(BaseModel):
    prefix: str = Field(min_length=1)
    keep: list[str] = []


class Search(BaseModel):
    query: str | None = None
    id: str | None = None
    prefix: str = Field(min_length=1)
    k: int = Field(default=12, ge=1, le=200)
    exclude: list[str] = []


def _drop(c, ids):
    n = 0
    for i in ids:
        c.execute("DELETE FROM chunks WHERE doc_id=?", (i,))
        n += c.execute("DELETE FROM docs WHERE id=?", (i,)).rowcount
    return n


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL}


@app.post("/upsert")
def upsert(req: Upsert):
    embedded = skipped = 0
    with _lock:
        c = db()
        for it in req.items:
            if not it.text.strip():
                _drop(c, [it.id])
                continue
            h = hashlib.sha256(it.text.encode()).hexdigest()
            row = c.execute("SELECT hash FROM docs WHERE id=?", (it.id,)).fetchone()
            if row and row[0] == h:
                skipped += 1
                continue
            pieces = chunk(it.text)
            vecs = embed_passages(pieces) if pieces else []
            _drop(c, [it.id])
            c.execute("INSERT INTO docs(id, hash) VALUES(?,?)", (it.id, h))
            c.executemany(
                "INSERT INTO chunks(doc_id, n, vec) VALUES(?,?,?)",
                [(it.id, n, np.asarray(v, dtype=np.float32).tobytes()) for n, v in enumerate(vecs)],
            )
            embedded += 1
        c.commit()
    return {"embedded": embedded, "skipped": skipped}


@app.post("/delete")
def delete(req: Delete):
    with _lock:
        c = db()
        n = _drop(c, req.ids)
        c.commit()
    return {"deleted": n}


@app.post("/prune")
def prune(req: Prune):
    keep = set(req.keep)
    with _lock:
        c = db()
        # escape LIKE wildcards in the prefix
        esc = req.prefix.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        ids = [r[0] for r in c.execute("SELECT id FROM docs WHERE id LIKE ? ESCAPE '\\'", (esc + "%",))]
        n = _drop(c, [i for i in ids if i not in keep])
        c.commit()
    return {"deleted": n}


@app.post("/search")
def search(req: Search):
    if (req.query is None) == (req.id is None):
        raise HTTPException(400, "provide exactly one of query or id")
    with _lock:
        c = db()
        if req.id is not None:
            rows = c.execute("SELECT vec FROM chunks WHERE doc_id=?", (req.id,)).fetchall()
            if not rows:
                return {"hits": []}
            q = _norm(np.mean([np.frombuffer(r[0], dtype=np.float32) for r in rows], axis=0))
        else:
            if not req.query.strip():
                raise HTTPException(400, "empty query")
            q = embed_query(req.query)
        excluded = set(req.exclude)
        if req.id is not None:
            excluded.add(req.id)
        esc = req.prefix.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        rows = c.execute(
            "SELECT doc_id, vec FROM chunks WHERE doc_id LIKE ? ESCAPE '\\'", (esc + "%",)
        ).fetchall()
    # ponytail: brute-force numpy cosine over all chunks loaded per query; fine to ~100k chunks,
    # switch to sqlite-vec/HNSW beyond that.
    best = {}
    if rows:
        m = np.stack([np.frombuffer(r[1], dtype=np.float32) for r in rows])
        scores = m @ q
        for (doc_id, _), s in zip(rows, scores):
            if doc_id not in excluded and s > best.get(doc_id, -2.0):
                best[doc_id] = float(s)
    top = sorted(best.items(), key=lambda kv: -kv[1])[: req.k]
    return {"hits": [{"id": i, "score": s} for i, s in top]}
