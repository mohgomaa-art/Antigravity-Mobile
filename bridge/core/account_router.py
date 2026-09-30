import logging
from enum import Enum
from typing import List, Optional, Dict
from bridge.core.fleet_manager import FleetManager, WorkerProfile

logger = logging.getLogger("agy.router")

class RoutingMode(str, Enum):
    SINGLE_ACCOUNT = "single_account"
    ROUND_ROBIN_POOL = "round_robin_pool"
    SWARM_PARALLEL = "swarm_parallel"

class AccountRouter:
    def __init__(self, fleet_manager: FleetManager, default_mode: RoutingMode = RoutingMode.SINGLE_ACCOUNT):
        self.fleet = fleet_manager
        self.mode = default_mode
        self._round_robin_index = 0
        self.pinned_accounts: Dict[str, int] = {} # conversation_id -> account_id

    def set_mode(self, mode: RoutingMode):
        self.mode = mode
        logger.info(f"Routing mode changed to: {self.mode}")

    def pin_conversation(self, conversation_id: str, account_id: int):
        self.pinned_accounts[conversation_id] = account_id

    def resolve(self, account_id: Optional[int] = None) -> Optional[WorkerProfile]:
        targets = self.resolve_target_accounts(requested_account_id=account_id)
        return targets[0] if targets else self.fleet.get_worker(1)

    def resolve_target_accounts(
        self,
        conversation_id: Optional[str] = None,
        requested_account_id: Optional[int] = None
    ) -> List[WorkerProfile]:
        """Resolves which worker profile(s) should process the incoming message."""
        if self.mode == RoutingMode.SWARM_PARALLEL:
            # Swarm mode targets all active, non-rate-limited accounts
            available = [w for w in self.fleet.list_workers() if not w.rate_limited]
            return available if available else self.fleet.list_workers()

        # If user explicitly requested an account ID, honor it
        if requested_account_id is not None:
            w = self.fleet.get_worker(requested_account_id)
            if w:
                return [w]

        # Check if conversation is pinned
        if conversation_id and conversation_id in self.pinned_accounts:
            target_id = self.pinned_accounts[conversation_id]
            w = self.fleet.get_worker(target_id)
            if w:
                return [w]

        if self.mode == RoutingMode.ROUND_ROBIN_POOL:
            workers = [w for w in self.fleet.list_workers() if not w.rate_limited]
            if not workers:
                workers = self.fleet.list_workers()
            selected = workers[self._round_robin_index % len(workers)]
            self._round_robin_index = (self._round_robin_index + 1) % len(workers)
            if conversation_id:
                self.pinned_accounts[conversation_id] = selected.account_id
            return [selected]

        # Default: Account 1
        default_w = self.fleet.get_worker(1)
        return [default_w] if default_w else []
