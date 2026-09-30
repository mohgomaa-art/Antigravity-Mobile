import pytest
from fastapi.testclient import TestClient
from bridge.server import app, PAIRING_TOKEN, active_execution_tasks, active_agent_runs

client = TestClient(app)

def test_tasks_running_empty_by_default():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    res = client.get("/api/tasks/running", headers=headers)
    assert res.status_code == 200
    data = res.json()
    assert "tasks" in data
    assert data["count"] == 0

def test_active_agent_runs_does_not_leak_into_tasks_running():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    # Simulate an active agent run
    active_agent_runs["test_run_1"] = {
        "id": "test_run_1",
        "conversation_id": "convo_test_123",
        "is_running": True
    }
    try:
        # /api/tasks/running must ONLY report real script/command tasks, NOT user prompt agent runs!
        res = client.get("/api/tasks/running", headers=headers)
        assert res.status_code == 200
        data = res.json()
        assert data["count"] == 0
        assert len(data["tasks"]) == 0

        # /api/conversations/{id}/steps must recognize the active run
        res_steps = client.get("/api/conversations/convo_test_123/steps", headers=headers)
        assert res_steps.status_code == 200
        assert res_steps.json()["is_working"] is True
    finally:
        active_agent_runs.pop("test_run_1", None)

def test_real_command_task_shows_in_running_tasks():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    # Simulate a real tool command task (e.g. flutter analyze, pytest)
    active_execution_tasks["cmd_call_99"] = {
        "id": "cmd_call_99",
        "command": "flutter test",
        "account_id": 1,
        "conversation_id": "convo_test_123",
        "is_running": True
    }
    try:
        res = client.get("/api/tasks/running", headers=headers)
        assert res.status_code == 200
        data = res.json()
        assert data["count"] == 1
        assert data["tasks"][0]["command"] == "flutter test"
    finally:
        active_execution_tasks.pop("cmd_call_99", None)

def test_tasks_do_not_leak_across_conversations():
    headers = {"X-Bridge-Token": PAIRING_TOKEN}
    # Simulate a task running in conversation A
    active_execution_tasks["cmd_convo_a"] = {
        "id": "cmd_convo_a",
        "command": "python test.py",
        "account_id": 1,
        "conversation_id": "convo_A",
        "is_running": True
    }
    try:
        # Steps for conversation A must show is_working = True and task in running_tasks
        res_a = client.get("/api/conversations/convo_A/steps", headers=headers)
        assert res_a.status_code == 200
        data_a = res_a.json()
        assert data_a["is_working"] is True
        assert len(data_a.get("running_tasks", [])) == 1

        # Steps for conversation B must NOT show the task or is_working = True
        res_b = client.get("/api/conversations/convo_B/steps", headers=headers)
        assert res_b.status_code == 200
        data_b = res_b.json()
        assert data_b["is_working"] is False
        assert len(data_b.get("running_tasks", [])) == 0

        # Querying running tasks for convo_B must return 0 tasks
        res_tasks_b = client.get("/api/tasks/running?conversation_id=convo_B", headers=headers)
        assert res_tasks_b.status_code == 200
        assert res_tasks_b.json()["count"] == 0
    finally:
        active_execution_tasks.pop("cmd_convo_a", None)
