import os
import sys
import re
import time
import shutil
import logging
import threading
import subprocess
from pathlib import Path
from typing import Optional, Dict, Any

logger = logging.getLogger("agy.tunnel")

class TunnelManager:
    """
    Manages Cloudflare Quick Tunnel to provide worldwide, remote access
    to the Antigravity Fleet Station from anywhere outside the local LAN
    (cellular 5G/4G, school, work, coffee shops) with zero port forwarding.
    """

    def __init__(self, target_port: int = 8765):
        try:
            self.target_port = int(os.environ.get("AGY_PORT", target_port))
        except Exception:
            self.target_port = target_port
        self.public_url: Optional[str] = None
        self._process: Optional[subprocess.Popen] = None
        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._error: Optional[str] = None
        self._lock = threading.Lock()

    def _find_cloudflared_binary(self) -> Optional[str]:
        """Locates the cloudflared executable."""
        bin_name = "cloudflared.exe" if os.name == "nt" else "cloudflared"
        exe_dir = Path(sys.executable).resolve().parent
        prog_files = Path(os.environ.get("ProgramFiles", "C:\\Program Files"))
        prog_files_x86 = Path(os.environ.get("ProgramFiles(x86)", "C:\\Program Files (x86)"))
        local_app = Path(os.environ.get("LOCALAPPDATA", ""))

        candidates = [
            # PyInstaller one-folder internal directory
            exe_dir / "_internal" / bin_name,
            exe_dir / bin_name,
            exe_dir / "tools" / bin_name,
            # In parent folder / tools
            exe_dir.parent / "tools" / bin_name,
            exe_dir.parent / bin_name,
            # Relative to workspace dist/antigravity_bridge/ -> tools/
            exe_dir.parent.parent / "tools" / bin_name,
            # Installed Program Files location
            prog_files / "Antigravity Fleet Station" / "tools" / bin_name,
            prog_files / "Antigravity Fleet Station" / "bridge" / bin_name,
            prog_files_x86 / "Antigravity Fleet Station" / "tools" / bin_name,
            prog_files_x86 / "Antigravity Fleet Station" / "bridge" / bin_name,
            local_app / "Programs" / "Antigravity Fleet Station" / "tools" / bin_name,
            local_app / "Programs" / "Antigravity Fleet Station" / "bridge" / bin_name,
            # Source file relative
            Path(__file__).resolve().parent.parent.parent / "tools" / bin_name,
            # User profile tools
            Path.home() / ".antigravity-fleet" / "tools" / bin_name,
        ]
        if hasattr(sys, '_MEIPASS'):
            candidates.insert(0, Path(sys._MEIPASS) / bin_name)
        for c in candidates:
            if c.exists() and c.is_file():
                return str(c)

        # Check system PATH
        path_binary = shutil.which("cloudflared") or shutil.which("cloudflared.exe")
        if path_binary:
            return path_binary

        return None

    def start(self) -> bool:
        """Starts the cloudflared quick tunnel daemon in background."""
        with self._lock:
            if self._running and self._process and self._process.poll() is None:
                return True

            binary = self._find_cloudflared_binary()
            if not binary:
                self._error = "cloudflared.exe not found on system"
                logger.warning(self._error)
                return False

            cmd = [
                binary,
                "tunnel",
                "--url", f"http://127.0.0.1:{self.target_port}",
                "--no-autoupdate",
                "--protocol", "http2",
                "--metrics", "127.0.0.1:0",
                "--management-diagnostics=false"
            ]

            creationflags = 0
            if sys.platform == "win32":
                creationflags = subprocess.CREATE_NO_WINDOW

            try:
                self._process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,
                    text=True,
                    bufsize=1,
                    creationflags=creationflags
                )
                self._running = True
                self._error = None

                self._thread = threading.Thread(target=self._monitor_output, daemon=True)
                self._thread.start()
                logger.info(f"Started Cloudflare Worldwide Tunnel process (PID {self._process.pid})")
                return True
            except Exception as e:
                self._error = str(e)
                self._running = False
                logger.error(f"Failed to spawn Cloudflare Tunnel: {e}")
                return False

    def _monitor_output(self):
        """Monitors stdout (merged stderr) to capture the generated https://*.trycloudflare.com URL."""
        if not self._process or not self._process.stdout:
            return

        url_pattern = re.compile(r'https://([a-zA-Z0-9-]+)\.trycloudflare\.com')
        try:
            for line in iter(self._process.stdout.readline, ''):
                if not line:
                    break
                line_str = line.strip()
                if "trycloudflare.com" in line_str:
                    match = url_pattern.search(line_str)
                    if match:
                        subdomain = match.group(1).lower()
                        # Ignore Cloudflare's own internal endpoints (e.g. api.trycloudflare.com)
                        if subdomain in ("api", "update", "pkg", "staging", "admin", "www", "dash"):
                            continue
                        found_url = match.group(0)
                        if self.public_url != found_url:
                            self.public_url = found_url
                            self._error = None
                            logger.info(f"Antigravity Worldwide Remote URL established: {self.public_url}")
                elif "ERR" in line_str or "failed to" in line_str.lower():
                    self._error = line_str
                    logger.warning(f"cloudflared reported error: {line_str}")

            ret = self._process.poll()
            if ret is not None and ret != 0:
                self._error = f"cloudflared exited with status {ret}"
                logger.warning(self._error)
        except Exception as e:
            self._error = str(e)
            logger.debug(f"Tunnel monitor exception: {e}")
        finally:
            with self._lock:
                self._running = False

    def stop(self):
        """Stops the tunnel process and ensures cloudflared is killed."""
        with self._lock:
            self._running = False
            if self._process:
                pid = self._process.pid
                try:
                    self._process.terminate()
                    self._process.kill()
                except Exception:
                    pass
                if sys.platform == "win32" and pid:
                    try:
                        subprocess.run(f"taskkill /F /T /PID {pid}", shell=True, capture_output=True)
                    except Exception:
                        pass
                self._process = None
            self.public_url = None
            logger.info("Cloudflare Worldwide Tunnel stopped")

    def get_public_url(self) -> Optional[str]:
        return self.public_url

    def get_status(self) -> Dict[str, Any]:
        return {
            "is_running": self._running and self._process is not None and self._process.poll() is None,
            "public_url": self.public_url,
            "target_port": self.target_port,
            "error": self._error,
            "binary_found": bool(self._find_cloudflared_binary())
        }

tunnel_mgr = TunnelManager()
import atexit
atexit.register(tunnel_mgr.stop)
