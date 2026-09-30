import pytest
import tempfile
from bridge.core.fleet_manager import FleetManager
from bridge.core.account_router import AccountRouter, RoutingMode

def test_router_single_account():
    with tempfile.TemporaryDirectory() as tmpdir:
        fm = FleetManager(count=5, base_port=53001, profiles_dir=tmpdir)
        router = AccountRouter(fm, default_mode=RoutingMode.SINGLE_ACCOUNT)

        # Default route without requested account
        targets = router.resolve_target_accounts()
        assert len(targets) == 1
        assert targets[0].account_id == 1

        # Explicit account requested
        targets = router.resolve_target_accounts(requested_account_id=4)
        assert len(targets) == 1
        assert targets[0].account_id == 4

def test_router_round_robin_pool():
    with tempfile.TemporaryDirectory() as tmpdir:
        fm = FleetManager(count=3, base_port=53001, profiles_dir=tmpdir)
        router = AccountRouter(fm, default_mode=RoutingMode.ROUND_ROBIN_POOL)

        t1 = router.resolve_target_accounts()
        t2 = router.resolve_target_accounts()
        t3 = router.resolve_target_accounts()
        t4 = router.resolve_target_accounts()

        assert [t1[0].account_id, t2[0].account_id, t3[0].account_id, t4[0].account_id] == [1, 2, 3, 1]

def test_router_swarm_mode():
    with tempfile.TemporaryDirectory() as tmpdir:
        fm = FleetManager(count=15, base_port=53001, profiles_dir=tmpdir)
        router = AccountRouter(fm, default_mode=RoutingMode.SWARM_PARALLEL)

        targets = router.resolve_target_accounts()
        assert len(targets) == 15
        assert [w.account_id for w in targets] == list(range(1, 16))
