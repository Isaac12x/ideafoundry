import zlib

import numpy as np
import pytest
from fastapi.testclient import TestClient

import app as semantic


def fake_vec(text):
    v = np.zeros(64, dtype=np.float32)
    for w in text.lower().split():
        v[zlib.crc32(w.encode()) % 64] += 1
    return v / max(np.linalg.norm(v), 1e-12)


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(semantic, "DB_PATH", str(tmp_path / "t.sqlite3"))
    monkeypatch.setattr(semantic, "_db", None)
    calls = []
    monkeypatch.setattr(semantic, "embed_passages", lambda ts: (calls.append(len(ts)), np.stack([fake_vec(t) for t in ts]))[1])
    monkeypatch.setattr(semantic, "embed_query", fake_vec)
    c = TestClient(semantic.app)
    c.calls = calls
    return c


def test_flow(client):
    assert client.get("/health").json()["status"] == "ok"
    items = [
        {"id": "u1:a", "text": "apples and oranges fruit salad"},
        {"id": "u1:b", "text": "fruit salad with apples"},
        {"id": "u1:c", "text": "kernel scheduler linux"},
        {"id": "u2:a", "text": "apples and oranges fruit salad"},
    ]
    assert client.post("/upsert", json={"items": items}).json() == {"embedded": 4, "skipped": 0}
    assert client.post("/upsert", json={"items": items[:2]}).json() == {"embedded": 0, "skipped": 2}

    hits = client.post("/search", json={"query": "apples fruit", "prefix": "u1:"}).json()["hits"]
    assert [h["id"] for h in hits][-1] == "u1:c" and all(h["id"].startswith("u1:") for h in hits)

    hits = client.post("/search", json={"id": "u1:a", "prefix": "u1:"}).json()["hits"]
    assert hits[0]["id"] == "u1:b" and "u1:a" not in [h["id"] for h in hits]
    assert client.post("/search", json={"id": "nope", "prefix": "u1:"}).json() == {"hits": []}
    hits = client.post("/search", json={"id": "u1:a", "prefix": "u1:", "exclude": ["u1:b"], "k": 1}).json()["hits"]
    assert [h["id"] for h in hits] == ["u1:c"]

    assert client.post("/search", json={"prefix": "u1:"}).status_code == 400
    assert client.post("/search", json={"query": "x", "id": "y", "prefix": "u1:"}).status_code == 400
    assert client.post("/search", json={"query": "x", "prefix": ""}).status_code == 422
    assert client.post("/prune", json={"prefix": "", "keep": []}).status_code == 422

    assert client.post("/prune", json={"prefix": "u1:", "keep": ["u1:a"]}).json() == {"deleted": 2}
    assert client.post("/upsert", json={"items": [{"id": "u1:a", "text": " "}]}).json() == {"embedded": 0, "skipped": 0}
    assert client.post("/delete", json={"ids": ["u2:a", "zzz"]}).json() == {"deleted": 1}
    assert client.post("/search", json={"query": "apples", "prefix": ""}).status_code == 422


def test_chunking():
    ch = semantic.chunk("word " * 1000)
    assert 1 < len(ch) <= 64 and all(len(c) <= 1000 for c in ch)
    assert len(semantic.chunk("x" * 200000)) == 64
