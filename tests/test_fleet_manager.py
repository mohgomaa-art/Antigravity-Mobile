import pytest
import tempfile
from pathlib import Path
from bridge.core.fleet_manager import FleetManager

def test_fleet_manager_initialization():
    with tempfile.TemporaryDirectory() as tmpdir:
        fm = FleetManager(count=15, base_port=53001, profiles_dir=tmpdir)
        workers = fm.list_workers()
        
        assert len(workers) == 15
        assert workers[0].account_id == 1
        assert workers[0].port == 53001
        assert workers[14].account_id == 15
        assert workers[14].port == 53015

        # Check profiles directory creation
        p1 = Path(tmpdir) / "profile_01"
        assert p1.exists()
        assert (p1 / "csrf.token").exists()

def test_fleet_worker_start_stop_emulated():
    with tempfile.TemporaryDirectory() as tmpdir:
        # non-existent binary to test emulated lifecycle
        fm = FleetManager(count=3, base_port=54000, profiles_dir=tmpdir, binary_path="nonexistent.exe")
        w1 = fm.start_worker(1, spawn_process=False)
        assert w1.is_active is True

        fm.stop_worker(1)
        assert w1.is_active is False

def test_fleet_rate_limit_flag():
    with tempfile.TemporaryDirectory() as tmpdir:
        fm = FleetManager(count=3, base_port=54000, profiles_dir=tmpdir)
        fm.set_rate_limit(2, True)
        assert fm.get_worker(2).rate_limited is True
        fm.set_rate_limit(2, False)
        assert fm.get_worker(2).rate_limited is False
