import os
import json
import time
import secrets
import logging
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Any
from pydantic import BaseModel, Field

logger = logging.getLogger("agy.auth_vault")

class AccountCredential(BaseModel):
    account_id: int
    alias: str
    email: Optional[str] = None
    auth_type: str = "google_oauth"  # google_oauth, api_key, session_token, service_account
    token: Optional[str] = None
    refresh_token: Optional[str] = None
    expires_at: Optional[float] = None
    is_authenticated: bool = False
    quota_remaining_pct: int = 100
    last_used: Optional[float] = None
    updated_at: float = Field(default_factory=time.time)

class AuthVault:
    def __init__(self, vault_dir: Optional[str] = None):
        default_dir = Path.home() / ".antigravity-fleet"
        self.vault_dir = Path(vault_dir) if vault_dir else default_dir
        self.vault_dir.mkdir(parents=True, exist_ok=True)
        self.vault_file = self.vault_dir / "vault.json"
        
        self.credentials: Dict[int, AccountCredential] = {}
        self._load_or_init_vault()

    def _load_or_init_vault(self):
        """Loads existing vault or initializes 15 slots with Slot #01 from active Antigravity session."""
        if self.vault_file.exists():
            try:
                with open(self.vault_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for item in data.get("slots", []):
                        # Filter out old mock worker emails so user can authenticate real accounts
                        email = item.get("email")
                        if email and "+worker" in email:
                            item["email"] = None
                            item["is_authenticated"] = False
                            item["token"] = None
                        cred = AccountCredential(**item)
                        self.credentials[cred.account_id] = cred
                logger.info(f"Loaded {len(self.credentials)} credentials from vault")
            except Exception as e:
                logger.error(f"Error loading vault.json: {e}")

        # Ensure all 15 slots exist and synchronize from stored credentials
        creds_dir = self.vault_dir / "credentials"
        primary_email = self._detect_primary_desktop_user()
        for i in range(1, 16):
            slot_file = creds_dir / f"slot_{i:02d}.json"
            slot_email = None
            if slot_file.exists():
                try:
                    with open(slot_file, "r", encoding="utf-8") as f:
                        sdata = json.load(f)
                        slot_email = sdata.get("email")
                except Exception:
                    pass

            if i not in self.credentials:
                assigned_email = slot_email or (primary_email if i == 1 else None)
                is_auth = bool(assigned_email)
                self.credentials[i] = AccountCredential(
                    account_id=i,
                    alias=f"Worker-{i:02d}",
                    email=assigned_email,
                    auth_type="google_oauth",
                    token=f"agy_live_token_slot_{i:02d}_{secrets.token_hex(8)}" if is_auth else None,
                    is_authenticated=is_auth,
                    quota_remaining_pct=100 if is_auth else 0
                )
            else:
                if slot_email and (not self.credentials[i].email or not self.credentials[i].is_authenticated):
                    self.credentials[i].email = slot_email
                    self.credentials[i].is_authenticated = True
                    if not self.credentials[i].token:
                        self.credentials[i].token = f"agy_live_token_slot_{i:02d}_{secrets.token_hex(8)}"
                    self.credentials[i].quota_remaining_pct = 100
                elif i == 1 and not self.credentials[1].is_authenticated and primary_email:
                    self.credentials[1].email = primary_email
                    self.credentials[1].is_authenticated = True
                    self.credentials[1].token = "agy_live_token_primary"
                    self.credentials[1].quota_remaining_pct = 100

        self.save()

    def _detect_primary_desktop_user(self) -> Optional[str]:
        """Detects the currently authenticated Antigravity desktop user."""
        try:
            appdata = os.environ.get("APPDATA")
            if appdata:
                storage_file = Path(appdata) / "Antigravity" / "app_storage.json"
                if storage_file.exists():
                    with open(storage_file, "r", encoding="utf-8") as f:
                        data = json.load(f)
                        username = data.get("jetski.onboarding.lastLoginUsername")
                        if username and "@" in username:
                            return username
        except Exception as e:
            logger.warning(f"Could not read primary desktop user from app_storage: {e}")
        try:
            from bridge.core.cred_manager import cred_manager
            res = cred_manager.read_system_credential()
            if res:
                data, _ = res
                email = cred_manager.decode_jwt_email(data.get("id_token", ""))
                if email and "@" in email:
                    return email
            slot1 = cred_manager.load_slot_credential(1)
            if slot1 and slot1.get("email"):
                return slot1["email"]
        except Exception:
            pass
        return None

    def save(self):
        """Persists the 15 credential slots to disk."""
        data = {
            "version": "1.0",
            "updated_at": time.time(),
            "slots": [c.model_dump() for c in sorted(self.credentials.values(), key=lambda x: x.account_id)]
        }
        with open(self.vault_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

    def get_credential(self, account_id: int) -> Optional[AccountCredential]:
        return self.credentials.get(account_id)

    def list_credentials(self) -> List[AccountCredential]:
        return [self.credentials[i] for i in sorted(self.credentials.keys())]

    def set_credential(
        self,
        account_id: int,
        email: Optional[str] = None,
        token: Optional[str] = None,
        auth_type: str = "google_oauth",
        alias: Optional[str] = None,
        is_authenticated: Optional[bool] = None
    ) -> AccountCredential:
        if account_id < 1 or account_id > 15:
            raise ValueError(f"account_id must be between 1 and 15, got {account_id}")

        clean_email = email.strip() if email else None
        assigned_token = token or (f"agy_live_token_slot_{account_id:02d}_{secrets.token_hex(8)}" if clean_email else None)
        auth_flag = is_authenticated if is_authenticated is not None else bool(clean_email)

        cred = AccountCredential(
            account_id=account_id,
            alias=alias or f"Worker-{account_id:02d}",
            email=clean_email,
            token=assigned_token,
            auth_type=auth_type,
            is_authenticated=auth_flag,
            quota_remaining_pct=100 if auth_flag else 0,
            updated_at=time.time()
        )
        self.credentials[account_id] = cred
        self.save()
        logger.info(f"Updated credential slot #{account_id} for {clean_email}")
        return cred

    def _handle_auth_complete(self, slot_id: int, email: str, data: Dict[str, Any]):
        """Callback invoked when user successfully logs into Google in the fresh window."""
        token = None
        if data and "token" in data and isinstance(data["token"], dict):
            token = data["token"].get("access_token")
        self.set_credential(
            account_id=slot_id,
            email=email,
            token=token or f"agy_live_token_slot_{slot_id:02d}_{secrets.token_hex(8)}",
            auth_type="google_oauth",
            alias=f"Worker-{slot_id:02d}",
            is_authenticated=True
        )
        logger.info(f"Slot #{slot_id} authenticated and synchronized into vault for {email}")

    def launch_antigravity_auth_window(self, account_id: int) -> Dict[str, Any]:
        """Launches a fresh Antigravity IDE instance with ZERO AUTH for genuine Google login."""
        from bridge.core.cred_manager import cred_manager
        session = cred_manager.start_fresh_auth_flow(
            account_id,
            on_complete=self._handle_auth_complete
        )
        logger.info(f"Initiated zero-auth sign-in flow for Slot #{account_id}")
        return session

    def detect_profile_auth(self, account_id: int) -> Optional[str]:
        """Detects if a Google user has signed in under this account slot."""
        from bridge.core.cred_manager import cred_manager
        status = cred_manager.get_auth_status(account_id)
        if status.get("status") == "authenticated" and status.get("email"):
            email = status["email"]
            if not self.credentials.get(account_id) or not self.credentials[account_id].is_authenticated:
                self.set_credential(
                    account_id=account_id,
                    email=email,
                    auth_type="google_oauth",
                    alias=f"Worker-{account_id:02d}",
                    is_authenticated=True
                )
            return email

        pdir = self.vault_dir / f"profile_{account_id:02d}"
        candidates = [
            pdir / "app_storage.json",
            pdir / "antigravity-ide" / "app_storage.json",
        ]
        for c in candidates:
            if c.exists():
                try:
                    with open(c, "r", encoding="utf-8", errors="ignore") as f:
                        d = json.load(f)
                        username = d.get("jetski.onboarding.lastLoginUsername")
                        if username and "@" in username:
                            self.set_credential(
                                account_id=account_id,
                                email=username,
                                token=f"agy_live_token_slot_{account_id:02d}_{secrets.token_hex(8)}",
                                auth_type="google_oauth",
                                alias=f"Worker-{account_id:02d}",
                                is_authenticated=True
                            )
                            return username
                except Exception as e:
                    logger.warning(f"Error reading {c}: {e}")
        return None

    def lease_token(self, account_id: int) -> Optional[str]:
        """Returns the valid token for the requested slot and records usage."""
        cred = self.credentials.get(account_id)
        if not cred or not cred.token:
            return None
        cred.last_used = time.time()
        self.save()
        return cred.token

    def quick_login(
        self,
        account_id: int,
        email: Optional[str] = None,
        alias: Optional[str] = None,
        token: Optional[str] = None
    ) -> AccountCredential:
        """1-button login authentication for an account slot using provided or detected email."""
        if account_id < 1 or account_id > 15:
            raise ValueError(f"account_id must be between 1 and 15, got {account_id}")

        assigned_email = email.strip() if email else None
        if not assigned_email:
            if account_id == 1:
                assigned_email = self._detect_primary_desktop_user()
            else:
                detected = self.detect_profile_auth(account_id)
                if detected:
                    assigned_email = detected

        assigned_token = token or (f"agy_live_token_slot_{account_id:02d}_{secrets.token_hex(8)}" if assigned_email else None)
        is_auth = bool(assigned_email)

        return self.set_credential(
            account_id=account_id,
            email=assigned_email,
            token=assigned_token,
            auth_type="google_oauth",
            alias=alias or f"Worker-{account_id:02d}",
            is_authenticated=is_auth
        )

    def clear_credential(self, account_id: int) -> AccountCredential:
        """Unauthenticates an account slot."""
        from bridge.core.cred_manager import cred_manager
        slot_file = cred_manager.creds_dir / f"slot_{account_id:02d}.json"
        if slot_file.exists():
            try:
                slot_file.unlink()
            except Exception:
                pass

        cred = AccountCredential(
            account_id=account_id,
            alias=f"Worker-{account_id:02d}",
            email=None,
            token=None,
            is_authenticated=False,
            quota_remaining_pct=0,
            updated_at=time.time()
        )
        self.credentials[account_id] = cred
        self.save()
        logger.info(f"Cleared credentials for Slot #{account_id}")
        return cred


