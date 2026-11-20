"""Semantic index sidecar. One module, two roles from the same image:
API    `uvicorn app:app`     search + enqueue; never embeds documents (only the short query)
worker `python app.py worker`  drains the queue, embeds changed chunks only
Control db (queue + pointers) and index dbs are separate sqlite files in WAL mode, so search never
waits on the worker and /rebuild/commit is a pointer flip, not a file rename."""
import hashlib
import json
import os
import sqlite3
import sys
import time
import uuid

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

MODEL = os.environ.get("SEMANTIC_MODEL", "BAAI/bge-small-en-v1.5")
DB_PATH = os.environ.get("SEMANTIC_DB", "/data/semantic.sqlite3")
CHUNK, OVERLAP, MAX_CHUNKS = 1000, 200, 64
BATCH, IDLE = 64, 0.5
MAX_ATTEMPTS = 5  # a queue row failing this often is parked (kept, not retried) until it is re-enqueued

app = FastAPI(title="Idea Foundry Local Semantic Index", version="2.0.0")
_model = None

CTL_SCHEMA = (
    "CREATE TABLE IF NOT EXISTS queue(id TEXT PRIMARY KEY, op TEXT NOT NULL, payload TEXT, enqueued_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0);"
    "CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);"
)
IDX_SCHEMA = (
    "CREATE TABLE IF NOT EXISTS docs(id TEXT PRIMARY KEY, hash TEXT);"
    "CREATE TABLE IF NOT EXISTS chunks(doc_id TEXT, n INT, hash TEXT, vec BLOB);"
    "CREATE INDEX IF NOT EXISTS chunks_doc_id ON chunks(doc_id);"
    "CREATE INDEX IF NOT EXISTS chunks_hash ON chunks(hash);"
    "CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);"
)


def connect(path, schema, secure=False):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    c = sqlite3.connect(path, timeout=10, isolation_level=None)  # autocommit; explicit BEGIN below
    c.execute("PRAGMA busy_timeout=10000")
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA synchronous=NORMAL")
    if secure:  # the queue briefly holds section text; scrub freed pages
        c.execute("PRAGMA secure_delete=ON")
    c.executescript(schema)
    if secure:
        try:  # control db created before attempts existed
            c.execute("ALTER TABLE queue ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0")
        except sqlite3.OperationalError:
            pass
    return c


def ctl():
    return connect(DB_PATH + ".control", CTL_SCHEMA, secure=True)


def idx(name):
    c = connect(f"{DB_PATH}.{name}", IDX_SCHEMA)
    if c.execute("SELECT COUNT(*) FROM meta WHERE k IN ('model','id')").fetchone()[0] < 2:  # reads must never take the write lock
        c.execute("INSERT OR IGNORE INTO meta VALUES('model', ?)", (MODEL,))
        c.execute("INSERT OR IGNORE INTO meta VALUES('id', ?)", (uuid.uuid4().hex,))  # identity of this index file
    return c


def state(c):
    m = dict(c.execute("SELECT k, v FROM meta WHERE k IN ('active','shadow','gen')"))
    return m.get("active", "idx0"), m.get("shadow")


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


def sha(s):
    return hashlib.sha256(s.encode()).hexdigest()


def like_prefix(p):
    return p.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def doc_type(doc_id):
    p = doc_id.split(":", 2)
    return p[1] if len(p) > 2 else ""


# ---------------------------------------------------------------- worker

def known_vecs(srcs, hashes):
    """hash -> float32 blob from indexes embedded with the current model."""
    out = {}
    for name in srcs:
        c = idx(name)
        try:
            if c.execute("SELECT v FROM meta WHERE k='model'").fetchone()[0] != MODEL:
                continue
            for i in range(0, len(hashes), 500):
                part = hashes[i : i + 500]
                q = f"SELECT hash, vec FROM chunks WHERE hash IN ({','.join('?' * len(part))})"
                for h, v in c.execute(q, part):
                    out.setdefault(h, v)
        finally:
            c.close()
    return out


def write_doc(name, doc_id, rows, dhash):
    """rows: [(n, hash, vec)]; rows None = delete. One short transaction."""
    c = idx(name)
    try:
        c.execute("BEGIN IMMEDIATE")
        cur = c.execute("SELECT hash FROM docs WHERE id=?", (doc_id,)).fetchone()
        if rows is None or not cur or cur[0] != dhash:
            c.execute("DELETE FROM chunks WHERE doc_id=?", (doc_id,))
            c.execute("DELETE FROM docs WHERE id=?", (doc_id,))
            if rows is not None:
                c.execute("INSERT INTO docs VALUES(?,?)", (doc_id, dhash))
                c.executemany("INSERT INTO chunks VALUES(?,?,?,?)", [(doc_id, n, h, v) for n, h, v in rows])
        c.execute("COMMIT")
    finally:
        c.close()


def apply(doc_id, op, payload, at):
    """Apply one queued op to live (+ shadow when rebuilding), then drop the queue row if still unchanged."""
    sections = json.loads(payload)["sections"] if op == "upsert" else []
    pieces = [(sha(t), t) for s in sections for t in chunk(s)]
    hashes = [h for h, _ in pieces]
    dhash = sha("".join(hashes))
    while True:
        c = ctl()
        try:
            active, shadow = state(c)
            targets = [active] + ([shadow] if shadow else [])
            have = known_vecs(targets, list(dict.fromkeys(hashes))) if pieces else {}
            todo = {h: t for h, t in pieces if h not in have}
            if todo:
                vecs = embed_passages(list(todo.values()))
                have.update({h: np.asarray(v, dtype=np.float32).tobytes() for h, v in zip(todo, vecs)})
                print(f"embedded {len(todo)}/{len(hashes)} chunks for {doc_id}", flush=True)
            rows = [(n, h, have[h]) for n, h in enumerate(hashes)] if pieces else None
            c.execute("BEGIN IMMEDIATE")  # blocks /rebuild/commit|abort while we write
            if state(c) != (active, shadow):
                c.execute("ROLLBACK")
                continue
            for t in targets:
                write_doc(t, doc_id, rows, dhash)
            c.execute("DELETE FROM queue WHERE id=? AND enqueued_at=?", (doc_id, at))
            c.execute("COMMIT")
            return
        finally:
            c.close()


def drain(limit=BATCH):
    c = ctl()
    try:
        rows = c.execute("SELECT id, op, payload, enqueued_at FROM queue WHERE attempts < ? ORDER BY enqueued_at LIMIT ?", (MAX_ATTEMPTS, limit)).fetchall()
    finally:
        c.close()
    done = 0
    for doc_id, op, payload, at in rows:
        try:
            apply(doc_id, op, payload, at)
            done += 1
        except Exception as e:
            print(f"error {doc_id}: {e!r}", flush=True)
            c = ctl()
            try:
                c.execute("UPDATE queue SET attempts=attempts+1 WHERE id=? AND enqueued_at=?", (doc_id, at))
                row = c.execute("SELECT attempts FROM queue WHERE id=?", (doc_id,)).fetchone()
                if row and row[0] == MAX_ATTEMPTS:
                    print(f"parked {doc_id} after {MAX_ATTEMPTS} attempts", flush=True)
            finally:
                c.close()
    return done


def run_worker():
    while True:
        with open(DB_PATH + ".heartbeat", "w"):  # compose healthcheck: mtime
            pass
        if not drain():
            time.sleep(IDLE)


# ---------------------------------------------------------------- API

class Item(BaseModel):
    id: str = Field(min_length=1)
    sections: list[str] = []


class Enqueue(BaseModel):
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
    types: list[str] | None = None


def put(ops):
    """ops: [(id, op, payload|None)] -> upsert queue rows, latest wins (coalescing)."""
    base = time.time_ns()
    c = ctl()
    try:
        c.execute("BEGIN IMMEDIATE")
        c.executemany(
            "INSERT INTO queue(id, op, payload, enqueued_at) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET "
            "op=excluded.op, payload=excluded.payload, enqueued_at=excluded.enqueued_at, attempts=0",
            [(i, op, p, base + n) for n, (i, op, p) in enumerate(ops)],
        )
        c.execute("COMMIT")
    finally:
        c.close()
    return len(ops)


@app.get("/health")
def health():
    c = ctl()
    try:
        active, shadow = state(c)
        queued = c.execute("SELECT COUNT(*) FROM queue WHERE attempts < ?", (MAX_ATTEMPTS,)).fetchone()[0]
        parked = c.execute("SELECT COUNT(*) FROM queue WHERE attempts >= ?", (MAX_ATTEMPTS,)).fetchone()[0]
    finally:
        c.close()
    i = idx(active)
    try:
        docs = i.execute("SELECT COUNT(*) FROM docs").fetchone()[0]
        meta = dict(i.execute("SELECT k, v FROM meta"))
    finally:
        i.close()
    return {"status": "ok", "model": MODEL, "queued": queued, "parked": parked, "docs": docs, "rebuilding": shadow is not None,
            "index_id": meta.get("id"), "index_model": meta.get("model")}


@app.post("/enqueue", status_code=202)
def enqueue(req: Enqueue):
    ops = []
    for it in req.items:
        secs = [s for s in it.sections if s.strip()]
        ops.append((it.id, "upsert", json.dumps({"sections": secs})) if secs else (it.id, "delete", None))
    return {"queued": put(ops)}


@app.post("/delete", status_code=202)
def delete(req: Delete):
    return {"queued": put([(i, "delete", None) for i in req.ids])}


@app.post("/prune", status_code=202)
def prune(req: Prune):
    # Resolved at enqueue time against indexed docs (live + shadow) -> plain delete ops, so a doc
    # upserted after the prune is never caught by a stale keep list.
    keep = set(req.keep)
    c = ctl()
    try:
        active, shadow = state(c)
    finally:
        c.close()
    ids = set()
    for name in [active] + ([shadow] if shadow else []):
        i = idx(name)
        try:
            ids |= {r[0] for r in i.execute("SELECT id FROM docs WHERE id LIKE ? ESCAPE '\\'", (like_prefix(req.prefix),))}
        finally:
            i.close()
    return {"queued": put([(d, "delete", None) for d in ids if d not in keep])}


@app.post("/search")
def search(req: Search):
    if (req.query is None) == (req.id is None):
        raise HTTPException(400, "provide exactly one of query or id")
    if req.query is not None and not req.query.strip():
        raise HTTPException(400, "empty query")
    cc = ctl()
    try:
        active, _ = state(cc)
    finally:
        cc.close()
    c = idx(active)
    try:
        if req.id is not None:
            vs = c.execute("SELECT vec FROM chunks WHERE doc_id=?", (req.id,)).fetchall()
            if not vs:
                return {"hits": []}
            q = _norm(np.mean([np.frombuffer(r[0], dtype=np.float32) for r in vs], axis=0))
        else:
            q = embed_query(req.query)
        rows = c.execute("SELECT doc_id, vec FROM chunks WHERE doc_id LIKE ? ESCAPE '\\'", (like_prefix(req.prefix),)).fetchall()
    finally:
        c.close()
    excluded = set(req.exclude) | ({req.id} if req.id else set())
    types = set(req.types) if req.types else None
    # ponytail: brute-force numpy cosine over all chunks loaded per query; fine to ~100k chunks,
    # switch to sqlite-vec/HNSW beyond that.
    best = {}
    if rows:
        scores = np.stack([np.frombuffer(r[1], dtype=np.float32) for r in rows]) @ q
        for (doc_id, _), s in zip(rows, scores):
            if doc_id in excluded or (types and doc_type(doc_id) not in types):
                continue
            if s > best.get(doc_id, -2.0):
                best[doc_id] = float(s)
    top = sorted(best.items(), key=lambda kv: -kv[1])[: req.k]
    return {"hits": [{"id": i, "score": s} for i, s in top]}


def _drop_files(name):
    for suf in ("", "-wal", "-shm"):
        try:
            os.remove(f"{DB_PATH}.{name}{suf}")
        except FileNotFoundError:
            pass


def _flip(commit):
    c = ctl()
    try:
        c.execute("BEGIN IMMEDIATE")
        active, shadow = state(c)
        if not shadow:
            c.execute("ROLLBACK")
            raise HTTPException(409, "not rebuilding")
        c.execute("DELETE FROM meta WHERE k='shadow'")
        if commit:
            c.execute("INSERT OR REPLACE INTO meta VALUES('active', ?)", (shadow,))
        c.execute("COMMIT")
    finally:
        c.close()
    _drop_files(active if commit else shadow)
    return active, shadow


@app.post("/rebuild")
def rebuild():
    c = ctl()
    try:
        c.execute("BEGIN IMMEDIATE")
        active, shadow = state(c)
        if shadow:
            c.execute("ROLLBACK")
            return {"rebuilding": True, "started": False}
        gen = int(dict(c.execute("SELECT k, v FROM meta")).get("gen", 0)) + 1
        c.execute("INSERT OR REPLACE INTO meta VALUES('gen', ?)", (str(gen),))
        c.execute("INSERT OR REPLACE INTO meta VALUES('shadow', ?)", (f"idx{gen}",))
        c.execute("COMMIT")
    finally:
        c.close()
    idx(f"idx{gen}").close()
    return {"rebuilding": True, "started": True}


@app.post("/rebuild/commit")
def rebuild_commit():
    _flip(True)
    return {"rebuilding": False, "committed": True}


@app.post("/rebuild/abort")
def rebuild_abort():
    _flip(False)
    return {"rebuilding": False, "aborted": True}


if __name__ == "__main__":
    if sys.argv[1:] == ["worker"]:
        run_worker()
    else:
        sys.exit("usage: python app.py worker")
