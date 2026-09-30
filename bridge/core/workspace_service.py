import os
import subprocess
from pathlib import Path
from typing import List, Dict, Any, Optional

IGNORE_DIRS = {
    ".git", ".venv", "node_modules", "build", "dist",
    "__pycache__", ".pytest_cache", ".dart_tool", "DawnWebGPUCache", "GPUCache"
}

class WorkspaceService:
    def __init__(self, allowed_roots: Optional[List[str]] = None):
        roots = []
        if allowed_roots:
            for r in allowed_roots:
                if r:
                    p = Path(r)
                    if p.exists() and p not in roots:
                        roots.append(p)
        if not roots:
            home = Path.home()
            candidates = [
                Path.cwd(),
                home / "Projects",
                home / "Developer",
                home / "Desktop",
                home / "Documents",
                home
            ]
            for c in candidates:
                if c.exists() and c not in roots:
                    roots.append(c)
        self.allowed_roots = roots if roots else [Path.cwd()]
        self.active_root = self.allowed_roots[0]
        self._file_cache: Dict[str, Any] = {"root": None, "timestamp": 0.0, "entries": []}

    def set_active_root(self, path_str: str) -> bool:
        p = Path(path_str).resolve()
        if not p.exists() or not p.is_dir():
            return False
        if p not in self.allowed_roots:
            self.allowed_roots.append(p)
        self.active_root = p
        return True

    def list_roots(self) -> List[Dict[str, str]]:
        return [
            {
                "name": r.name or str(r),
                "path": str(r),
                "is_active": r.resolve() == self.active_root.resolve()
            }
            for r in self.allowed_roots
        ]

    def get_file_tree(self, max_depth: int = 4, current_path: Optional[Path] = None, current_depth: int = 0) -> List[Dict[str, Any]]:
        root = current_path or self.active_root
        if not root.exists() or current_depth > max_depth:
            return []

        items = []
        try:
            for entry in sorted(root.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower())):
                if entry.name in IGNORE_DIRS or entry.name.startswith("."):
                    continue

                node = {
                    "name": entry.name,
                    "path": str(entry),
                    "is_directory": entry.is_dir(),
                    "size": entry.stat().st_size if entry.is_file() else None,
                }
                if entry.is_dir() and current_depth < max_depth:
                    node["children"] = self.get_file_tree(
                        max_depth=max_depth,
                        current_path=entry,
                        current_depth=current_depth + 1
                    )
                items.append(node)
        except PermissionError:
            pass

        return items

    def search_files(self, query: str = "", limit: int = 50) -> List[Dict[str, Any]]:
        """
        Ultra-fast search for workspace files with 15-second TTL in-memory index.
        Returns list of { name, relative_path, absolute_path, extension, is_directory }
        """
        import time
        q = query.strip().lower()
        root = self.active_root.resolve()

        if not root.exists():
            return []

        now = time.time()
        # Invalidate if older than 15 seconds or root path changed
        if (
            self._file_cache.get("root") != root
            or now - self._file_cache.get("timestamp", 0) > 15.0
            or not self._file_cache.get("entries")
        ):
            all_entries = []

            def _scan_all(d: Path, depth: int):
                if depth > 6 or len(all_entries) >= 5000:
                    return
                try:
                    entries = sorted(d.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))
                except (PermissionError, OSError):
                    return

                for entry in entries:
                    if len(all_entries) >= 5000:
                        break
                    name = entry.name
                    if name in IGNORE_DIRS or (name.startswith(".") and name != ".gemini"):
                        continue

                    try:
                        rel_path = str(entry.relative_to(root)).replace("\\", "/")
                    except Exception:
                        rel_path = name

                    is_dir = entry.is_dir()
                    all_entries.append({
                        "name": name,
                        "name_lower": name.lower(),
                        "relative_path": rel_path,
                        "rel_path_lower": rel_path.lower(),
                        "absolute_path": str(entry).replace("\\", "/"),
                        "extension": "" if is_dir else entry.suffix.lower(),
                        "is_directory": is_dir
                    })

                    if is_dir:
                        _scan_all(entry, depth + 1)

            _scan_all(root, 0)
            self._file_cache = {
                "root": root,
                "timestamp": now,
                "entries": all_entries
            }

        # Filter from in-memory cache in sub-millisecond time
        cached_entries = self._file_cache.get("entries", [])
        matched = []
        for item in cached_entries:
            if not q or (q in item["name_lower"] or q in item["rel_path_lower"]):
                matched.append({
                    "name": item["name"],
                    "relative_path": item["relative_path"],
                    "absolute_path": item["absolute_path"],
                    "extension": item["extension"],
                    "is_directory": item["is_directory"]
                })
                if len(matched) >= limit:
                    break

        return matched

    def read_file(self, file_path: str) -> Dict[str, Any]:
        raw_path = file_path.strip()
        if raw_path.startswith("file://"):
            import urllib.parse
            raw_path = urllib.parse.unquote(urllib.parse.urlparse(raw_path).path)
            if raw_path.startswith("/") and len(raw_path) > 2 and raw_path[2] == ":":
                raw_path = raw_path[1:]

        p = Path(raw_path)
        if not p.is_absolute() or not p.exists():
            candidates = [
                self.active_root / raw_path,
                Path.cwd() / raw_path,
                Path.home() / raw_path,
            ]
            found = False
            for c in candidates:
                if c.exists() and c.is_file():
                    p = c
                    found = True
                    break
            
            # If still not found, search in Antigravity brain / artifacts directory
            if not found:
                brain_dir = Path.home() / ".gemini" / "antigravity" / "brain"
                if brain_dir.exists():
                    target_name = Path(raw_path).name
                    for candidate in brain_dir.rglob(f"*{target_name}*"):
                        if candidate.is_file():
                            p = candidate
                            found = True
                            break

        p = p.resolve()
        if not p.exists() or not p.is_file():
            raise FileNotFoundError(f"File not found: {file_path}")

        try:
            content = p.read_text(encoding="utf-8", errors="replace")
            return {
                "path": str(p),
                "name": p.name,
                "content": content,
                "size": len(content),
                "extension": p.suffix
            }
        except Exception as e:
            raise IOError(f"Could not read file {p}: {e}")

    def write_file(self, file_path: str, content: str) -> Dict[str, Any]:
        p = Path(file_path).resolve()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        return {
            "path": str(p),
            "status": "success",
            "bytes_written": len(content.encode("utf-8"))
        }

    def execute_command(self, command: str, timeout: int = 60) -> Dict[str, Any]:
        """Executes command in the active workspace directory."""
        try:
            result = subprocess.run(
                ["pwsh", "-NoProfile", "-Command", command],
                cwd=str(self.active_root),
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return {
                "command": command,
                "cwd": str(self.active_root),
                "exit_code": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "status": "completed" if result.returncode == 0 else "failed"
            }
        except subprocess.TimeoutExpired:
            return {
                "command": command,
                "exit_code": -1,
                "stdout": "",
                "stderr": f"Command timed out after {timeout} seconds",
                "status": "timeout"
            }
        except Exception as e:
            return {
                "command": command,
                "exit_code": -1,
                "stdout": "",
                "stderr": str(e),
                "status": "error"
            }
