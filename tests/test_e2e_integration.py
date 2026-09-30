import pytest
from fastapi.testclient import TestClient
from bridge.server import app, PAIRING_TOKEN

client = TestClient(app)

def test_e2e_unauthorized_access():
    res = client.get("/api/fleet/status")
    assert res.status_code == 401

def test_e2e_fleet_status():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    res = client.get("/api/fleet/status", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert data["total_accounts"] == 15
    assert len(data["workers"]) == 15
    assert data["workers"][0]["account_id"] == 1
    assert data["workers"][14]["account_id"] == 15

def test_e2e_fleet_mode_switch():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    res = client.post("/api/fleet/mode", headers=headers, json={"mode": "swarm_parallel"})
    assert res.status_code == 200
    assert res.json()["mode"] == "swarm_parallel"

    # Switch back to single_account
    res = client.post("/api/fleet/mode", headers=headers, json={"mode": "single_account"})
    assert res.status_code == 200
    assert res.json()["mode"] == "single_account"

def test_e2e_workspaces():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    res = client.get("/api/workspaces", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert "roots" in data
    assert len(data["roots"]) >= 1

def test_e2e_skills():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    res = client.get("/api/skills", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert "skills" in data
    assert "slash_commands" in data
    assert len(data["slash_commands"]) >= 5

def test_e2e_chat_dispatch():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    res = client.post(
        "/api/chat/send",
        headers=headers,
        json={"prompt": "Hello Antigravity from Flutter", "account_id": 1}
    )
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "dispatched"
    assert data["targeted_accounts"] == [1]

def test_e2e_pairing_qr_code():
    res = client.get("/api/pairing/qr")
    assert res.status_code == 200
    assert res.headers["content-type"] == "image/png"
    assert len(res.content) > 100
