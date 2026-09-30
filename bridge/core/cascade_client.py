import json
import logging
import re
import urllib.request
import urllib.error
from pathlib import Path
from typing import Optional, Tuple, Dict, Any, List
import psutil

logger = logging.getLogger("agy.cascade_client")

class AntigravityCascadeClient:
    """
    Direct Connect-protocol RPC client communicating with the active
    Google Antigravity LanguageServerService daemon.
    Enables live conversation creation, message injection, and real-time execution
    without restarting Antigravity.
    """

    def __init__(self):
        self._cached_port: Optional[int] = None
        self._cached_csrf: Optional[str] = None

    @staticmethod
    def _is_valid_http_port(port: int, csrf: Optional[str] = None) -> bool:
        try:
            url = f"http://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/StartCascade"
            headers = {
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1",
            }
            if csrf:
                headers["x-codeium-csrf-token"] = csrf
            req = urllib.request.Request(url, data=b"{}", headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                return True
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="ignore")
            if "HTTPS server" in body:
                return False
            return True
        except Exception:
            return False

    def get_connection(self, force_refresh: bool = False) -> Tuple[Optional[int], Optional[str]]:
        """Resolves the live random HTTP port and CSRF token of language_server.exe."""
        if not force_refresh and self._cached_port and self._cached_csrf:
            return self._cached_port, self._cached_csrf

        csrf_token = None
        target_proc = None
        for proc in psutil.process_iter(['name', 'cmdline']):
            try:
                if (proc.info.get('name') or '').lower() == 'language_server.exe':
                    cmdline = ' '.join(proc.info.get('cmdline') or [])
                    m = re.search(r'--csrf_token\s+([a-f0-9-]+)', cmdline)
                    if m:
                        csrf_token = m.group(1)
                        target_proc = proc
                        break
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass

        ls_port = None
        # Primary: inspect language_server.log specifically for the explicit HTTP port
        log_path = Path.home() / "AppData" / "Roaming" / "Antigravity" / "logs" / "language_server.log"
        if log_path.exists():
            try:
                with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
                    for line in reversed(f.readlines()):
                        m = re.search(r'Language server listening on random port at (\d+) for HTTP\b', line)
                        if m:
                            candidate = int(m.group(1))
                            if self._is_valid_http_port(candidate, csrf_token):
                                ls_port = candidate
                                break
            except Exception as ex:
                logger.debug(f"Error reading language server log for port: {ex}")

        # Secondary: scan all listening TCP ports directly on language_server.exe process
        if not ls_port and target_proc:
            try:
                for conn in target_proc.net_connections(kind='tcp'):
                    if conn.status == 'LISTEN' and conn.laddr:
                        candidate = conn.laddr.port
                        if self._is_valid_http_port(candidate, csrf_token):
                            ls_port = candidate
                            break
            except Exception as ex:
                logger.debug(f"Direct net_connections check failed: {ex}")

        if ls_port and csrf_token:
            self._cached_port = ls_port
            self._cached_csrf = csrf_token
            logger.info(f"Connected to Antigravity Language Server on HTTP port {ls_port}")
            return ls_port, csrf_token

        return None, None

    def start_cascade(
        self,
        workspace_path: Optional[str] = None,
        model_proto: str = "MODEL_PLACEHOLDER_M318",
        project_id: Optional[str] = None
    ) -> Optional[str]:
        """
        Creates a new genuine Cascade conversation inside Antigravity via StartCascade RPC.
        When project_id is provided, automatically binds the conversation to the project in Antigravity Desktop IDE.
        Returns the genuine UUID conversation ID or None on failure.
        """
        port, csrf = self.get_connection()
        if not port or not csrf:
            port, csrf = self.get_connection(force_refresh=True)
            if not port or not csrf:
                logger.error("Cannot start cascade: Language Server is not running")
                return None

        url = f"http://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/StartCascade"
        headers = {
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "x-codeium-csrf-token": csrf
        }

        ws_uris = []
        if workspace_path:
            clean_path = str(workspace_path).replace("\\", "/")
            if not clean_path.startswith("file:///"):
                ws_uris.append(f"file:///{clean_path.lstrip('/')}")
            else:
                ws_uris.append(clean_path)
        else:
            default_p = Path.cwd().resolve()
            clean_p = str(default_p).replace("\\", "/")
            ws_uris.append(f"file:///{clean_p.lstrip('/')}")

        payload_dict = {
            "source": "CORTEX_TRAJECTORY_SOURCE_INTERACTIVE_CASCADE",
            "requested_model": model_proto
        }
        if project_id:
            payload_dict["project_env_config"] = {
                "project_id": project_id,
                "default_project_environment": {}
            }
        else:
            payload_dict["workspace_uris"] = ws_uris

        payload = json.dumps(payload_dict).encode("utf-8")

        try:
            req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                cid = data.get("cascadeId")
                logger.info(f"Successfully started Cascade conversation: {cid}")
                return cid
        except urllib.error.HTTPError as e:
            self._cached_port = None
            self._cached_csrf = None
            err_body = e.read().decode("utf-8", errors="replace")
            logger.error(f"StartCascade failed: HTTP {e.code} - {err_body}")
        except Exception as e:
            self._cached_port = None
            self._cached_csrf = None
            logger.error(f"StartCascade network error: {e}")

        return None

    def send_user_message(
        self,
        cascade_id: str,
        prompt: str,
        model_proto: str = "MODEL_PLACEHOLDER_M318"
    ) -> bool:
        """
        Sends a prompt turn into a Cascade conversation via SendUserCascadeMessage RPC.
        Triggers instant live agent execution in Antigravity.
        """
        port, csrf = self.get_connection()
        if not port or not csrf:
            port, csrf = self.get_connection(force_refresh=True)
            if not port or not csrf:
                logger.error("Cannot send message: Language Server not reachable")
                return False

        url = f"http://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/SendUserCascadeMessage"
        headers = {
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "x-codeium-csrf-token": csrf
        }

        payload = json.dumps({
            "cascade_id": cascade_id,
            "items": [{"text": prompt}],
            "cascade_config": {
                "planner_config": {
                    "plan_model": model_proto
                }
            }
        }).encode("utf-8")

        try:
            req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=10) as resp:
                if resp.status == 200:
                    logger.info(f"Dispatched message to cascade {cascade_id} with model {model_proto}")
                    return True
        except urllib.error.HTTPError as e:
            self._cached_port = None
            self._cached_csrf = None
            err_body = e.read().decode("utf-8", errors="replace")
            logger.error(f"SendUserCascadeMessage failed: HTTP {e.code} - {err_body}")
        except Exception as e:
            self._cached_port = None
            self._cached_csrf = None
            logger.error(f"SendUserCascadeMessage error: {e}")

        return False
