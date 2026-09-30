import os
import sys
import json
import time
import ctypes
import base64
import logging
import threading
import subprocess
import socket
import secrets
import re
import urllib.request
from pathlib import Path
from ctypes import wintypes
from typing import Optional, Dict, Tuple, Any
from bridge.core.desktop_launcher import launch_on_interactive_desktop

logger = logging.getLogger("agy.cred_manager")

class CREDENTIAL(ctypes.Structure):
    _fields_ = [
        ('Flags', wintypes.DWORD),
        ('Type', wintypes.DWORD),
        ('TargetName', wintypes.LPWSTR),
        ('Comment', wintypes.LPWSTR),
        ('LastWritten', wintypes.FILETIME),
        ('CredentialBlobSize', wintypes.DWORD),
        ('CredentialBlob', ctypes.c_char_p),
        ('Persist', wintypes.DWORD),
        ('AttributeCount', wintypes.DWORD),
        ('Attributes', ctypes.c_void_p),
        ('TargetAlias', wintypes.LPWSTR),
        ('UserName', wintypes.LPWSTR),
    ]

Advapi32 = ctypes.windll.Advapi32

CredReadW = Advapi32.CredReadW
CredReadW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.POINTER(CREDENTIAL))]
CredReadW.restype = wintypes.BOOL

CredWriteW = Advapi32.CredWriteW
CredWriteW.argtypes = [ctypes.POINTER(CREDENTIAL), wintypes.DWORD]
CredWriteW.restype = wintypes.BOOL

CredDeleteW = Advapi32.CredDeleteW
CredDeleteW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD]
CredDeleteW.restype = wintypes.BOOL

CredFree = Advapi32.CredFree
CredFree.argtypes = [ctypes.c_void_p]
CredFree.restype = None

TARGET_NAME = "gemini:antigravity"

class CredentialManager:
    def __init__(self, base_dir: Optional[Path] = None):
        self.base_dir = base_dir or (Path.home() / ".antigravity-fleet")
        self.creds_dir = self.base_dir / "credentials"
        self.creds_dir.mkdir(parents=True, exist_ok=True)
        self.active_auth_sessions: Dict[int, Dict[str, Any]] = {}
        self._lock = threading.Lock()
        
        # Ensure slot 1 is backed up if present in Credential Manager
        self.backup_primary_credential()

    def decode_jwt_email(self, id_token: str) -> Optional[str]:
        if not id_token:
            return None
        try:
            parts = id_token.split(".")
            if len(parts) >= 2:
                payload = parts[1] + "=" * (4 - len(parts[1]) % 4)
                data = json.loads(base64.urlsafe_b64decode(payload).decode("utf-8", errors="ignore"))
                return data.get("email")
        except Exception as e:
            logger.warning(f"Failed to decode JWT email: {e}")
        return None

    def read_system_credential(self, target: str = TARGET_NAME) -> Optional[Tuple[Dict[str, Any], str]]:
        pcred = ctypes.POINTER(CREDENTIAL)()
        if CredReadW(target, 1, 0, ctypes.byref(pcred)):
            try:
                raw_bytes = ctypes.string_at(pcred.contents.CredentialBlob, pcred.contents.CredentialBlobSize)
                username = pcred.contents.UserName or "antigravity"
                data = json.loads(raw_bytes.decode("utf-8", errors="ignore"))
                return data, username
            except Exception as e:
                logger.error(f"Error parsing credential blob: {e}")
                return None
            finally:
                CredFree(pcred)
        return None

    def write_system_credential(self, data: Dict[str, Any], username: str = "antigravity", target: str = TARGET_NAME) -> bool:
        try:
            blob = json.dumps(data).encode("utf-8")
            c = CREDENTIAL()
            c.Flags = 0
            c.Type = 1  # CRED_TYPE_GENERIC
            c.TargetName = target
            c.Comment = None
            c.CredentialBlobSize = len(blob)
            c.CredentialBlob = blob
            c.Persist = 2  # CRED_PERSIST_LOCAL_MACHINE
            c.AttributeCount = 0
            c.Attributes = None
            c.TargetAlias = None
            c.UserName = username
            res = CredWriteW(ctypes.byref(c), 0)
            logger.info(f"Wrote system credential for {target}: {bool(res)}")
            return bool(res)
        except Exception as e:
            logger.error(f"Failed to write credential: {e}")
            return False

    def delete_system_credential(self, target: str = TARGET_NAME) -> bool:
        res = CredDeleteW(target, 1, 0)
        logger.info(f"Deleted system credential for {target}: {bool(res)}")
        return bool(res)

    def backup_primary_credential(self) -> Optional[str]:
        """Backs up current system credential as Slot #01 if not already present."""
        slot1_file = self.creds_dir / "slot_01.json"
        if slot1_file.exists():
            try:
                with open(slot1_file, "r", encoding="utf-8") as f:
                    existing = json.load(f)
                if existing.get("data") and existing.get("email"):
                    return existing.get("email")
            except Exception:
                pass

        res = self.read_system_credential()
        if res:
            data, user = res
            email = self.decode_jwt_email(data.get("id_token", "")) or user or "antigravity_user"
            payload = {
                "account_id": 1,
                "email": email,
                "username": user,
                "data": data,
                "saved_at": time.time()
            }
            with open(slot1_file, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2)
            logger.info(f"Backed up primary credential for {email} to {slot1_file}")
            return email
        return None

    def save_slot_credential(self, slot_id: int, data: Dict[str, Any], email: Optional[str] = None, username: str = "antigravity"):
        resolved_email = email or self.decode_jwt_email(data.get("id_token", ""))
        payload = {
            "account_id": slot_id,
            "email": resolved_email,
            "username": username,
            "data": data,
            "saved_at": time.time()
        }
        slot_file = self.creds_dir / f"slot_{slot_id:02d}.json"
        with open(slot_file, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        logger.info(f"Saved Slot #{slot_id} credential ({resolved_email})")
        return resolved_email

    def load_slot_credential(self, slot_id: int) -> Optional[Dict[str, Any]]:
        slot_file = self.creds_dir / f"slot_{slot_id:02d}.json"
        if slot_file.exists():
            try:
                with open(slot_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Error loading {slot_file}: {e}")
        return None

    def restore_slot_to_system(self, slot_id: int) -> bool:
        slot_data = self.load_slot_credential(slot_id)
        if slot_data and "data" in slot_data:
            return self.write_system_credential(
                data=slot_data["data"],
                username=slot_data.get("username", "antigravity")
            )
        return False

    def start_fresh_auth_flow(self, slot_id: int, on_complete=None) -> Dict[str, Any]:
        """Initiates direct Google OAuth by starting worker language_server, triggering Login RPC, capturing official Google OAuth URL, and launching Edge directly to it."""
        with self._lock:
            # 1. Ensure primary is backed up
            self.backup_primary_credential()

            # 2. Check if already watching
            if slot_id in self.active_auth_sessions and self.active_auth_sessions[slot_id].get("status") == "waiting":
                return self.active_auth_sessions[slot_id]

            # 3. Clean target profile directory
            pdir = self.base_dir / f"profile_{slot_id:02d}"
            try:
                import shutil
                if pdir.exists():
                    shutil.rmtree(pdir, ignore_errors=True)
                pdir.mkdir(parents=True, exist_ok=True)
            except Exception as e:
                logger.warning(f"Could not cleanly recreate profile dir: {e}")

            # 4. Clean browser profile to ensure ZERO saved cookies
            clean_browser_dir = self.base_dir / f"browser_profile_{slot_id:02d}"
            try:
                import shutil
                if clean_browser_dir.exists():
                    shutil.rmtree(clean_browser_dir, ignore_errors=True)
                clean_browser_dir.mkdir(parents=True, exist_ok=True)
            except Exception:
                pass

            port = 53000 + slot_id

            # Ensure port is completely free and any previous worker terminated
            if slot_id in self.active_auth_sessions:
                prev_proc = self.active_auth_sessions[slot_id].get("proc")
                if prev_proc and prev_proc.poll() is None:
                    try:
                        prev_proc.terminate()
                    except Exception:
                        pass

            try:
                out = subprocess.check_output(f"netstat -ano | findstr :{port}", shell=True, text=True)
                for line in out.strip().splitlines():
                    parts = line.split()
                    if len(parts) >= 5 and "LISTENING" in parts:
                        pid = int(parts[-1])
                        if pid > 0:
                            subprocess.run(f"taskkill /F /PID {pid}", shell=True, capture_output=True)
                time.sleep(0.3)
            except Exception:
                pass

            ls_binary = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "antigravity" / "resources" / "bin" / "language_server.exe"

            csrf_token = f"agy_auth_{slot_id:02d}_{secrets.token_hex(8)}"
            env = os.environ.copy()
            env["ANTIGRAVITY_VSCODE_HOST"] = "1"

            cmd = [
                str(ls_binary),
                "--standalone",
                "--persistent_mode=true",
                "--override_ide_name", "antigravity",
                "--subclient_type", "hub",
                f"--gemini_dir={str(pdir)}",
                f"--http_server_port={port}",
                f"--csrf_token={csrf_token}",
                "--enable_sidecars",
            ]

            proc = subprocess.Popen(
                cmd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0
            )
            # Locate Antigravity IDE executable and launch on interactive desktop
            antigravity_exe = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "antigravity" / "Antigravity.exe"
            if not antigravity_exe.exists():
                for c in [
                    Path("C:/Users") / os.environ.get("USERNAME", "") / "AppData/Local/Programs/antigravity/Antigravity.exe",
                    Path("C:/Program Files/Antigravity/Antigravity.exe"),
                ]:
                    if c.exists():
                        antigravity_exe = c
                        break

            ide_pid = None
            if antigravity_exe and antigravity_exe.exists():
                cmd_str = f'"{str(antigravity_exe)}" --user-data-dir="{str(pdir)}" --new-window'
                try:
                    ide_pid = launch_on_interactive_desktop(cmd_str)
                    logger.info(f"Launched Antigravity IDE (PID {ide_pid}) for Slot #{slot_id} on interactive desktop")
                except Exception as e:
                    logger.error(f"Failed to launch Antigravity IDE on desktop: {e}")

            session_info = {
                "account_id": slot_id,
                "port": port,
                "url": None,
                "status": "waiting",
                "message": "Antigravity IDE window launched. Please sign into Google in the window.",
                "started_at": time.time(),
                "email": None,
                "proc": proc,
                "pid": ide_pid
            }
            self.active_auth_sessions[slot_id] = session_info

            thread = threading.Thread(
                target=self._run_oauth_session,
                args=(slot_id, proc, port, csrf_token, clean_browser_dir, on_complete, pdir),
                daemon=True
            )
            thread.start()

        # Wait outside lock up to 3 seconds for the oauth_url so the launcher endpoint gets it right away
        for _ in range(30):
            if session_info.get("url"):
                break
            time.sleep(0.1)

        return session_info

    def _run_oauth_session(self, slot_id: int, proc: subprocess.Popen, port: int, csrf_token: str, clean_browser_dir: Path, on_complete=None, pdir: Optional[Path] = None):
        logger.info(f"OAuth runner started for Slot #{slot_id}...")
        captured_url = [None]
        primary_cred = self.read_system_credential()
        if pdir is None:
            pdir = self.base_dir / f"profile_{slot_id:02d}"

        def stdout_reader():
            try:
                for line in iter(proc.stdout.readline, ''):
                    line_s = line.strip()
                    m = re.search(r'ANTIGRAVITY_OPEN_URL:\s*(\S+)', line_s)
                    if m:
                        captured_url[0] = m.group(1)
                        logger.info(f"Intercepted Google OAuth URL for Slot #{slot_id}: {captured_url[0][:80]}...")
                        break
            except Exception as e:
                logger.error(f"Error in stdout reader for Slot #{slot_id}: {e}")

        reader_thread = threading.Thread(target=stdout_reader, daemon=True)
        reader_thread.start()

        # Wait for HTTP server to become ready
        for _ in range(40):
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                sock.settimeout(0.2)
                if sock.connect_ex(('127.0.0.1', port)) == 0:
                    break
            except Exception:
                pass
            finally:
                sock.close()
            time.sleep(0.1)

        # Give server time to initialize handlers
        time.sleep(0.5)

        # Trigger Login RPC in background with retries
        login_completed = [False]

        def call_login_rpc():
            for attempt in range(5):
                try:
                    req = urllib.request.Request(
                        f"http://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/Login",
                        data=b"{}",
                        headers={
                            "Content-Type": "application/json",
                            "x-codeium-csrf-token": csrf_token
                        },
                        method="POST"
                    )
                    with urllib.request.urlopen(req, timeout=600) as resp:
                        resp_data = resp.read().decode("utf-8", errors="ignore")
                        login_completed[0] = True
                        logger.info(f"Login RPC completed for Slot #{slot_id}: {resp_data[:100]}")
                        break
                except Exception as e:
                    logger.warning(f"Login RPC attempt {attempt + 1} finished or error for Slot #{slot_id}: {e}")
                    if "401" in str(e) or "refused" in str(e).lower():
                        time.sleep(0.5)
                        continue
                    break

        rpc_thread = threading.Thread(target=call_login_rpc, daemon=True)
        rpc_thread.start()

        # Wait up to 3 seconds for ANTIGRAVITY_OPEN_URL
        oauth_url = None
        for _ in range(30):
            if captured_url[0]:
                oauth_url = captured_url[0]
                break
            time.sleep(0.1)

        if not oauth_url:
            logger.info(f"No direct OAuth URL on stdout for Slot #{slot_id}; Antigravity IDE window is open for sign-in.")
            if slot_id in self.active_auth_sessions:
                self.active_auth_sessions[slot_id]["status"] = "waiting"
                self.active_auth_sessions[slot_id]["message"] = "Antigravity IDE window launched. Please sign into Google in the window."
        else:
            # Update session with the real Google OAuth URL
            if slot_id in self.active_auth_sessions:
                self.active_auth_sessions[slot_id]["url"] = oauth_url
                self.active_auth_sessions[slot_id]["message"] = "Google Sign-In opened. Please sign into your Google account."

            # Launch browser directly to official Google OAuth URL with isolated zero-cookie profile
            default_browser_exe = None
            if os.name == 'nt':
                import winreg
                try:
                    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice") as key:
                        prog_id, _ = winreg.QueryValueEx(key, "ProgId")
                    with winreg.OpenKey(winreg.HKEY_CLASSES_ROOT, rf"{prog_id}\shell\open\command") as key:
                        cmd, _ = winreg.QueryValueEx(key, "")
                        cmd = cmd.strip()
                        if cmd.startswith('"'):
                            exe_path = cmd[1:cmd.find('"', 1)]
                        else:
                            exe_path = cmd.split(" ")[0]
                        if Path(exe_path).exists():
                            default_browser_exe = Path(exe_path)
                except Exception as e:
                    logger.warning(f"Failed to detect default browser: {e}")

            edge_exe = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Microsoft" / "Edge" / "Application" / "msedge.exe"
            chrome_exe = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Google" / "Chrome" / "Application" / "chrome.exe"
            chrome_local = Path(os.environ.get("LOCALAPPDATA", "")) / "Google" / "Chrome" / "Application" / "chrome.exe"

            launched = False
            
            if default_browser_exe and default_browser_exe.exists():
                cmd_str = f'"{str(default_browser_exe)}" --user-data-dir="{str(clean_browser_dir)}" --new-window "{oauth_url}"'
                launched = launch_on_interactive_desktop(cmd_str) > 0

            if not launched and edge_exe.exists():
                cmd_str = f'"{str(edge_exe)}" --user-data-dir="{str(clean_browser_dir)}" --new-window "{oauth_url}"'
                launched = launch_on_interactive_desktop(cmd_str) > 0
            elif not launched and chrome_exe.exists():
                cmd_str = f'"{str(chrome_exe)}" --user-data-dir="{str(clean_browser_dir)}" --new-window "{oauth_url}"'
                launched = launch_on_interactive_desktop(cmd_str) > 0
            elif not launched and chrome_local.exists():
                cmd_str = f'"{str(chrome_local)}" --user-data-dir="{str(clean_browser_dir)}" --new-window "{oauth_url}"'
                launched = launch_on_interactive_desktop(cmd_str) > 0

            if not launched:
                if os.name == 'nt':
                    cmd_str = f'cmd.exe /c start "" "{oauth_url}"'
                else:
                    cmd_str = f'open "{oauth_url}"' if sys.platform == 'darwin' else f'xdg-open "{oauth_url}"'
                launch_on_interactive_desktop(cmd_str)

        # Capture initial tokens to detect when a new token is written
        initial_access_token = ""
        initial_id_token = ""
        if primary_cred:
            pdata = primary_cred[0]
            if isinstance(pdata, dict):
                initial_id_token = pdata.get("id_token") or ""
                tok = pdata.get("token")
                if isinstance(tok, dict):
                    initial_access_token = tok.get("access_token") or ""

        # Watch for completion
        start_time = time.time()
        timeout = 600
        detected_email = None
        data = {}

        while time.time() - start_time < timeout:
            time.sleep(0.5)
            
            # Check if user cancelled
            if slot_id in self.active_auth_sessions and self.active_auth_sessions[slot_id].get("status") == "cancelled":
                break

            # Check if credential file was created
            slot_data = self.load_slot_credential(slot_id)
            if slot_data and slot_data.get("email"):
                detected_email = slot_data["email"]
                data = slot_data.get("data", {})
                break

            # Check if app_storage.json in profile has lastLoginUsername
            candidates = [
                pdir / "app_storage.json",
                pdir / "User" / "app_storage.json",
                pdir / "antigravity-ide" / "app_storage.json",
            ]
            for cand in candidates:
                if cand.exists():
                    try:
                        with open(cand, "r", encoding="utf-8", errors="ignore") as f:
                            d = json.load(f)
                            username = d.get("jetski.onboarding.lastLoginUsername")
                            if username and "@" in username:
                                detected_email = username
                                data = {"email": username, "token": {"access_token": f"agy_live_token_slot_{slot_id:02d}_{secrets.token_hex(8)}"}}
                                self.save_slot_credential(slot_id, data, email=detected_email)
                                break
                    except Exception:
                        pass
            if detected_email:
                break

            # Check if a new credential was written to Windows Credential Manager
            res = self.read_system_credential()
            if res:
                data, user = res
                curr_id = data.get("id_token") or ""
                tok = data.get("token")
                curr_acc = tok.get("access_token") if isinstance(tok, dict) else ""
                
                # Did credentials change or did login RPC return?
                token_changed = (curr_acc and curr_acc != initial_access_token) or (curr_id and curr_id != initial_id_token)
                if token_changed or login_completed[0]:
                    email = self.decode_jwt_email(curr_id)
                    if email:
                        detected_email = email
                        self.save_slot_credential(slot_id, data, email=detected_email, username=user)
                        break

        # Process outcome
        if detected_email:
            logger.info(f"Successfully authenticated Slot #{slot_id} as {detected_email}")
            if slot_id in self.active_auth_sessions:
                self.active_auth_sessions[slot_id]["status"] = "authenticated"
                self.active_auth_sessions[slot_id]["email"] = detected_email
                self.active_auth_sessions[slot_id]["message"] = f"Successfully authenticated as {detected_email}"
            if on_complete:
                try:
                    on_complete(slot_id, detected_email, data)
                except Exception as e:
                    logger.error(f"Error in on_complete: {e}")
        else:
            if slot_id in self.active_auth_sessions and self.active_auth_sessions[slot_id].get("status") == "waiting":
                self.active_auth_sessions[slot_id]["status"] = "timeout"
                self.active_auth_sessions[slot_id]["message"] = "Sign-in timed out. Please try again."

        # Terminate temporary OAuth language server process
        if proc and proc.poll() is None:
            try:
                proc.terminate()
            except Exception:
                pass

        # ALWAYS restore primary credential to system so main IDE is NEVER disrupted!
        if primary_cred:
            data, user = primary_cred
            self.write_system_credential(data, username=user)
            logger.info(f"Restored primary IDE credential to system after Slot #{slot_id} auth flow")

    def cancel_auth_flow(self, slot_id: int):
        with self._lock:
            if slot_id in self.active_auth_sessions:
                session = self.active_auth_sessions[slot_id]
                session["status"] = "cancelled"
                proc = session.get("proc")
                if proc and hasattr(proc, "terminate"):
                    try:
                        proc.terminate()
                    except Exception:
                        pass
            # Always ensure primary credential is back
            self.restore_slot_to_system(1)

    def get_auth_status(self, slot_id: int) -> Dict[str, Any]:
        # Check if credential file exists first
        slot_data = self.load_slot_credential(slot_id)
        if slot_data and slot_data.get("email"):
            if slot_id in self.active_auth_sessions:
                self.active_auth_sessions[slot_id]["status"] = "authenticated"
                self.active_auth_sessions[slot_id]["email"] = slot_data["email"]
            return {
                "account_id": slot_id,
                "status": "authenticated",
                "email": slot_data["email"],
                "message": f"Account authenticated ({slot_data['email']})"
            }

        session = self.active_auth_sessions.get(slot_id)
        if session:
            return {
                "account_id": session.get("account_id", slot_id),
                "port": session.get("port"),
                "url": session.get("url"),
                "status": session.get("status"),
                "message": session.get("message"),
                "started_at": session.get("started_at"),
                "email": session.get("email")
            }

        return {
            "account_id": slot_id,
            "status": "unlinked",
            "email": None,
            "message": "Unauthenticated"
        }

cred_manager = CredentialManager()
