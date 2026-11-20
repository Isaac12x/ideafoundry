import sqlite3
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
    embedded = []

    def passages(ts):
        embedded.extend(ts)
        return np.stack([fake_vec(t) for t in ts])

    monkeypatch.setattr(semantic, "embed_passages", passages)
    monkeypatch.setattr(semantic, "embed_query", fake_vec)
    c = TestClient(semantic.app)
    c.embedded = embedded
    c.enq = lambda *items: c.post("/enqueue", json={"items": [{"id": i, "sections": s} for i, s in items]})
    return c


def drain(client):
    while semantic.drain():
        pass


def hits(client, **kw):
    return [h["id"] for h in client.post("/search", json={"prefix": "u1:", **kw}).json()["hits"]]


def test_coalescing(client):
    assert client.enq(("u1:idea:1", ["old text"])).status_code == 202
    assert client.enq(("u1:idea:1", ["new apples text"])).json() == {"queued": 1}
    assert client.get("/health").json()["queued"] == 1
    drain(client)
    assert client.embedded == ["new apples text"]
    h = client.get("/health").json()
    assert (h["queued"], h["docs"], h["rebuilding"]) == (0, 1, False)
    assert hits(client, query="apples") == ["u1:idea:1"]


def test_chunk_reuse(client):
    a, b, c = "alpha " * 10, "beta " * 10, "gamma " * 10  # chunks are stripped
    CH = "beta changed " * 5
    client.enq(("u1:idea:1", [a, b, c]))
    drain(client)
    assert len(client.embedded) == 3
    client.embedded.clear()
    client.enq(("u1:idea:1", [a, CH, c]))
    drain(client)
    assert client.embedded == [CH.strip()]
    client.embedded.clear()
    client.enq(("u1:idea:1", [a, CH, c]))
    drain(client)
    assert client.embedded == []


def test_delete_and_prune(client):
    client.enq(("u1:idea:1", ["x one"]), ("u1:idea:2", ["x two"]), ("u1:note:3", ["x three"]), ("u2:idea:1", ["x four"]))
    drain(client)
    assert client.post("/prune", json={"prefix": "u1:", "keep": ["u1:idea:1"]}).json() == {"queued": 2}
    assert client.post("/prune", json={"prefix": "", "keep": []}).status_code == 422
    drain(client)
    assert client.get("/health").json()["docs"] == 2
    assert client.post("/delete", json={"ids": ["u2:idea:1"]}).status_code == 202
    client.enq(("u1:idea:1", []))  # empty sections = delete
    drain(client)
    assert client.get("/health").json()["docs"] == 0


def test_search_modes_and_types(client):
    client.enq(
        ("u1:idea:a", ["apples and oranges fruit salad"]),
        ("u1:note:b", ["fruit salad with apples"]),
        ("u1:todo:c", ["kernel scheduler linux"]),
        ("u2:idea:a", ["apples and oranges fruit salad"]),
    )
    drain(client)
    assert hits(client, query="apples fruit")[-1] == "u1:todo:c"
    assert hits(client, query="apples fruit", types=["note"]) == ["u1:note:b"]
    assert set(hits(client, query="apples fruit", types=["note", "todo"])) == {"u1:note:b", "u1:todo:c"}
    assert hits(client, id="u1:idea:a")[0] == "u1:note:b"
    assert hits(client, id="u1:idea:a", exclude=["u1:note:b"], k=1) == ["u1:todo:c"]
    assert hits(client, id="nope") == []
    assert client.post("/search", json={"prefix": "u1:"}).status_code == 400
    assert client.post("/search", json={"query": "x", "id": "y", "prefix": "u1:"}).status_code == 400


def test_search_during_worker_transaction(client):
    client.enq(("u1:idea:1", ["apples"]))
    drain(client)
    ctl = semantic.ctl()
    ix = semantic.idx("idx0")
    ctl.execute("BEGIN IMMEDIATE")
    ix.execute("BEGIN IMMEDIATE")
    ix.execute("INSERT INTO docs VALUES('u1:idea:zz','h')")
    assert hits(client, query="apples") == ["u1:idea:1"]  # WAL reader not blocked by open writers
    assert client.get("/health").json()["docs"] == 1
    ix.execute("ROLLBACK")
    ctl.execute("ROLLBACK")


def test_rebuild_swap(client):
    s1, s2 = "alpha " * 10, "beta " * 10
    client.enq(("u1:idea:1", [s1]), ("u1:idea:2", [s2]))
    drain(client)
    assert client.post("/rebuild/commit").status_code == 409
    assert client.post("/rebuild").json() == {"rebuilding": True, "started": True}
    assert client.get("/health").json()["rebuilding"] is True
    client.embedded.clear()
    client.enq(("u1:idea:1", [s1]), ("u1:idea:3", ["gamma " * 10]))  # sweep resend
    drain(client)
    assert client.embedded == ["gamma " * 9 + "gamma"]  # idea:1 chunk copied from live, not re-embedded
    assert "u1:idea:2" in hits(client, query="beta")  # live still serves old docs
    assert client.get("/health").json()["docs"] == 3  # ops applied to live too
    assert client.post("/rebuild/commit").json()["committed"] is True
    h = client.get("/health").json()
    assert (h["rebuilding"], h["docs"]) == (False, 2)
    assert set(hits(client, query="alpha gamma")) == {"u1:idea:1", "u1:idea:3"}
    # abort path
    client.post("/rebuild")
    client.post("/rebuild/abort")
    assert client.get("/health").json()["rebuilding"] is False and client.get("/health").json()["docs"] == 2


def test_model_change_embeds_fresh(client, monkeypatch):
    client.enq(("u1:idea:1", ["alpha " * 10]))
    drain(client)
    monkeypatch.setattr(semantic, "MODEL", "other")
    client.post("/rebuild")
    client.embedded.clear()
    client.enq(("u1:idea:1", ["alpha " * 10]))
    drain(client)
    assert client.embedded == ["alpha " * 9 + "alpha"]


def test_index_identity(client, monkeypatch):
    h = client.get("/health").json()
    assert h["index_id"] and h["index_model"] == semantic.MODEL
    assert client.get("/health").json()["index_id"] == h["index_id"]  # stable
    client.post("/rebuild")
    client.post("/rebuild/commit")
    h2 = client.get("/health").json()
    assert h2["index_id"] != h["index_id"]  # new live file after commit
    monkeypatch.setattr(semantic, "MODEL", "other")
    assert client.get("/health").json()["index_model"] != "other"  # live index still built with the old model


def test_poison_row_parked(client, monkeypatch):
    def boom(ts):
        raise RuntimeError("bad")

    monkeypatch.setattr(semantic, "embed_passages", boom)
    client.enq(("u1:idea:1", ["apples"]))
    for _ in range(semantic.MAX_ATTEMPTS + 2):
        semantic.drain()
    h = client.get("/health").json()
    assert (h["queued"], h["parked"]) == (0, 1)
    client.enq(("u1:idea:1", ["apples"]))  # re-enqueue revives it
    assert client.get("/health").json()["queued"] == 1


def test_chunking():
    ch = semantic.chunk("word " * 1000)
    assert 1 < len(ch) <= 64 and all(len(c) <= 1000 for c in ch)
    assert len(semantic.chunk("x" * 200000)) == 64
