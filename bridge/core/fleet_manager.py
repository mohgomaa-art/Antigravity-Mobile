import os
import sys
import json
import socket
import logging
import asyncio
import subprocess
import secrets
import time
import threading
import psutil
from pathlib import Path
from typing import Dict, List, Optional, Any
from pydantic import BaseModel, Field

from bridge.core.auth_vault import AuthVault
from bridge.core.desktop_launcher import launch_on_interactive_desktop
from bridge.core.cred_manager import cred_manager

logger = logging.getLogger("agy.fleet_manager")

class WorkerProfile(BaseModel):
    account_id: int
    alias: str
    email: Optional[str] = None
    port: int
    csrf_token: str
    profile_dir: str
    is_active: bool = False
    is_registered: bool = False
    rate_limited: bool = False
    pid: Optional[int] = None
    memory_mb: float = 0.0
    active_conversation_id: Optional[str] = None
    step_count: int = 0
    auth_type: str = "google_oauth"

class FleetManager:
    def __init__(
        self,
        count: int = 15,
        base_port: int = 53001,
        profiles_dir: Optional[str] = None,
        binary_path: Optional[str] = None
    ):
        self.count = count
        self.base_port = base_port
        
        default_dir = Path.home() / ".antigravity-fleet"
        self.profiles_dir = Path(profiles_dir) if profiles_dir else default_dir
        self.profiles_dir.mkdir(parents=True, exist_ok=True)
        
        from bridge.core.model_discovery import model_discovery
        resolved_bins = model_discovery.resolve_binary_paths()
        self.binary_path = Path(binary_path) if binary_path else resolved_bins["language_server"]
        self.gui_binary_path = resolved_bins["gui"]
        
        self.auth_vault = AuthVault(vault_dir=str(self.profiles_dir))
        self.workers: Dict[int, WorkerProfile] = {}
        self.processes: Dict[int, subprocess.Popen] = {}
        self._spawn_times: Dict[int, float] = {}
        self._spawn_lock = threading.Lock()
        self._init_profiles()

    def _init_profiles(self):
        """Initialize 15 profile configurations synced with AuthVault and credential manager."""
        for i in range(1, self.count + 1):
            pdir = self.profiles_dir / f"profile_{i:02d}"
            pdir.mkdir(parents=True, exist_ok=True)
            csrf_file = pdir / "csrf.token"
            if csrf_file.exists():
                csrf = csrf_file.read_text(encoding="utf-8").strip()
            else:
                csrf = secrets.token_hex(16)
                csrf_file.write_text(csrf, encoding="utf-8")
                
            # Sync actual credential from cred_manager slot store if available
            slot_cred = cred_manager.load_slot_credential(i)
            if slot_cred and slot_cred.get("email"):
                s_email = slot_cred["email"]
                vault_cred = self.auth_vault.get_credential(i)
                if not vault_cred or vault_cred.email != s_email or not vault_cred.is_authenticated:
                    self.auth_vault.set_credential(
                        account_id=i,
                        email=s_email,
                        token=f"agy_live_token_slot_{i:02d}_{secrets.token_hex(8)}",
                        auth_type="google_oauth",
                        alias=f"Worker-{i:02d}",
                        is_authenticated=True
                    )

            cred = self.auth_vault.get_credential(i)
            email = cred.email if cred else None
            is_reg = bool(cred and cred.is_authenticated) or (pdir / "antigravity_state.pbtxt").exists()
            alias = cred.alias if cred else f"Worker-{i:02d}"
            auth_type = cred.auth_type if cred else "google_oauth"

            self.workers[i] = WorkerProfile(
                account_id=i,
                alias=alias,
                email=email,
                port=self.base_port + (i - 1),
                csrf_token=csrf,
                profile_dir=str(pdir),
                is_active=False,
                is_registered=is_reg,
                auth_type=auth_type
            )

    def is_port_in_use(self, port: int) -> bool:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(0.02)
                return s.connect_ex(('127.0.0.1', port)) == 0
        except Exception:
            return False

    def _scan_running_antigravity_pids(self) -> Dict[int, int]:
        """Scans process table in a SINGLE pass for all active slot PIDs."""
        slot_pids: Dict[int, int] = {}
        try:
            for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
                try:
                    name = (proc.info.get('name') or '').lower()
                    if name == 'antigravity.exe':
                        cmd = proc.info.get('cmdline') or []
                        cmd_str = ' '.join(cmd)
                        if '--type=' not in cmd_str:
                            for i in range(1, self.count + 1):
                                if f"profile_{i:02d}" in cmd_str:
                                    slot_pids[i] = proc.pid
                                    break
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
        except Exception:
            pass
        return slot_pids

    def get_slot_antigravity_pid(self, account_id: int) -> Optional[int]:
        now = time.time()
        if not hasattr(self, '_cached_slot_pids') or (now - getattr(self, '_last_pid_scan_time', 0.0) > 2.0):
            self._cached_slot_pids = self._scan_running_antigravity_pids()
            self._last_pid_scan_time = now
        return self._cached_slot_pids.get(account_id)

    def get_worker(self, account_id: int) -> Optional[WorkerProfile]:
        self._sync_worker_state(account_id)
        return self.workers.get(account_id)

    def list_workers(self) -> List[WorkerProfile]:
        # Single pass scan of processes for all 15 workers simultaneously
        self._cached_slot_pids = self._scan_running_antigravity_pids()
        self._last_pid_scan_time = time.time()
        for account_id in list(self.workers.keys()):
            self._sync_worker_state(account_id)
        return list(self.workers.values())

    def is_pid_window_visible(self, target_pid: int) -> bool:
        """Checks if the process has a visible GUI window on the interactive desktop."""
        if sys.platform != "win32":
            return True
        try:
            import ctypes
            from ctypes import wintypes
            user32 = ctypes.windll.user32
            hdesk = user32.OpenDesktopW("default", 0, False, 0x0100)  # DESKTOP_ENUMERATE
            if not hdesk:
                return True
            found = False
            try:
                def enum_cb(hwnd, lparam):
                    nonlocal found
                    pid = wintypes.DWORD()
                    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                    if pid.value == target_pid and user32.IsWindowVisible(hwnd):
                        rect = wintypes.RECT()
                        user32.GetWindowRect(hwnd, ctypes.byref(rect))
                        if (rect.right - rect.left) > 100 and (rect.bottom - rect.top) > 100:
                            found = True
                            return False
                    return True

                WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
                user32.EnumDesktopWindows(hdesk, WNDENUMPROC(enum_cb), 0)
            finally:
                user32.CloseDesktop(hdesk)
            return found
        except Exception:
            return True

    def _sync_worker_state(self, account_id: int):
        worker = self.workers.get(account_id)
        if not worker:
            return
            
        cred = self.auth_vault.get_credential(account_id)
        if cred:
            worker.email = cred.email
            worker.alias = cred.alias
            worker.is_registered = cred.is_authenticated
            worker.auth_type = cred.auth_type

        # Check process lifecycle via actual running GUI Antigravity process
        running_pid = self.get_slot_antigravity_pid(account_id)
        if running_pid:
            # Check if GUI window was closed manually from the Antigravity window ('X')
            spawn_time = self._spawn_times.get(account_id, 0.0)
            elapsed = time.time() - spawn_time
            # After 8s post-spawn grace period, if window is closed, clean up orphaned subprocesses
            if elapsed >= 8.0 and not self.is_pid_window_visible(running_pid):
                logger.info(f"Slot #{account_id} GUI window was closed manually. Auto-terminating background helpers.")
                self.stop_worker(account_id)
                worker.is_active = False
                worker.pid = None
            else:
                worker.is_active = True
                worker.pid = running_pid
                worker.memory_mb = 125.0
        else:
            worker.is_active = False
            worker.pid = None

    def start_worker(self, account_id: int, spawn_process: bool = True) -> WorkerProfile:
        worker = self.workers.get(account_id)
        if not worker:
            raise ValueError(f"Worker #{account_id} not found")

        # If already running with visible window, return it
        existing_pid = self.get_slot_antigravity_pid(account_id)
        if existing_pid and self.is_pid_window_visible(existing_pid):
            worker.is_active = True
            worker.pid = existing_pid
            return worker

        pdir = Path(worker.profile_dir)
        pdir.mkdir(parents=True, exist_ok=True)

        if spawn_process and self.gui_binary_path.exists():
            # Synchronize spawning to prevent credential collisions in Windows Credential Manager
            with self._spawn_lock:
                slot_cred = cred_manager.load_slot_credential(account_id)
                if not slot_cred or not slot_cred.get("data") or not slot_cred.get("email"):
                    logger.warning(f"Slot #{account_id} is not authenticated. Aborting spawn to prevent wrong account usage.")
                    worker.is_active = False
                    return worker

                target_email = slot_cred.get("email")
                primary = cred_manager.read_system_credential()

                try:
                    logger.info(f"Injecting credential for Slot #{account_id} ({target_email}) into Windows Credential Manager")
                    cred_manager.write_system_credential(slot_cred["data"], username=slot_cred.get("username", "antigravity"))
                    time.sleep(0.5)

                    cmd = f'"{str(self.gui_binary_path)}" --user-data-dir="{str(pdir)}" --new-window'
                    pid = launch_on_interactive_desktop(cmd)
                    self._spawn_times[account_id] = time.time()
                    worker.is_active = True
                    worker.pid = pid
                    logger.info(f"Spawned Antigravity IDE GUI Window for Slot #{account_id} ({target_email}) (PID {pid})")

                    # Deterministic handshake: wait for Antigravity & its child language_server to consume credentials
                    ls_confirmed = False
                    slot_log_file = pdir / "logs" / "language_server.log"
                    for _ in range(30):  # Up to 15 seconds polling
                        time.sleep(0.5)
                        if slot_log_file.exists():
                            try:
                                log_txt = slot_log_file.read_text(encoding="utf-8", errors="ignore")
                                if "Successfully discovered Electron WS URL" in log_txt:
                                    ls_confirmed = True
                                    logger.info(f"Slot #{account_id} language_server successfully completed CDP handshake")
                                    time.sleep(2.0)
                                    break
                            except Exception:
                                pass
                        elif pid and psutil.pid_exists(pid):
                            try:
                                proc = psutil.Process(pid)
                                children = proc.children(recursive=True)
                                if any('language_server' in (c.name() or '').lower() for c in children):
                                    ls_confirmed = True
                            except Exception:
                                pass

                    if not ls_confirmed:
                        # Fallback sleep to guarantee Electron main process completed CredReadW
                        time.sleep(5.0)

                    logger.info(f"Slot #{account_id} startup handshake finished (language_server detected: {ls_confirmed})")
                except Exception as e:
                    logger.error(f"Failed to spawn Antigravity IDE window: {e}")
                    worker.is_active = False
                finally:
                    if primary:
                        cred_manager.write_system_credential(primary[0], username=primary[1])
                        logger.info(f"Safely restored primary IDE credential after Slot #{account_id} initialization")
        else:
            worker.is_active = True

        return worker

    def stop_worker(self, account_id: int) -> bool:
        self._spawn_times.pop(account_id, None)
        target = f"profile_{account_id:02d}"
        stopped = False

        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                name = proc.info.get('name') or ''
                if 'antigravity' in name.lower() or 'language_server' in name.lower():
                    cmd = proc.info.get('cmdline') or []
                    cmd_str = ' '.join(cmd)
                    if target in cmd_str:
                        proc.kill()
                        stopped = True
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass

        # Also free listening port if any
        port = self.base_port + (account_id - 1)
        try:
            out = subprocess.check_output(f"netstat -ano | findstr :{port}", shell=True, text=True)
            for line in out.strip().splitlines():
                parts = line.split()
                if len(parts) >= 5 and "LISTENING" in parts:
                    pid = int(parts[-1])
                    if pid > 0:
                        subprocess.run(f"taskkill /F /PID {pid}", shell=True, capture_output=True)
        except Exception:
            pass

        if account_id in self.workers:
            self.workers[account_id].is_active = False
            self.workers[account_id].pid = None
            logger.info(f"Stopped Antigravity Worker #{account_id}")

        return True

    def start_all(self, spawn_process: bool = True) -> List[WorkerProfile]:
        results = []
        for i in range(1, self.count + 1):
            cred = self.auth_vault.get_credential(i)
            if cred and cred.is_authenticated:
                results.append(self.start_worker(i, spawn_process=spawn_process))
        return results

    def stop_all(self) -> int:
        count = 0
        for i in range(1, self.count + 1):
            if self.stop_worker(i):
                count += 1
        return count

    def set_rate_limit(self, account_id: int, limited: bool = True):
        if account_id in self.workers:
            self.workers[account_id].rate_limited = limited
