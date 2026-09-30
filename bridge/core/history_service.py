import difflib
import json
import re
import sqlite3
import time
import urllib.parse
import uuid
from datetime import datetime
from pathlib import Path, PurePath
from typing import List, Dict, Any, Optional

from bridge.core.cdp_client import cdp_client

CUSTOM_PROJECTS_FILE = Path.home() / ".antigravity-fleet" / "config" / "custom_projects.json"

def format_iso_time(iso_str: Optional[str]) -> str:
    if not iso_str:
        return ""
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        s = dt.strftime("%I:%M %p")
        return s.lstrip("0") if s.startswith("0") else s
    except Exception:
        return ""

def format_duration(start_iso: Optional[str], end_iso: Optional[str]) -> str:
    if not start_iso or not end_iso:
        return "Worked for 1m"
    try:
        dt1 = datetime.fromisoformat(start_iso.replace("Z", "+00:00"))
        dt2 = datetime.fromisoformat(end_iso.replace("Z", "+00:00"))
        diff = int((dt2 - dt1).total_seconds())
        if diff < 0:
            diff = 0
        if diff < 60:
            return f"Worked for {max(1, diff)}s"
        mins = max(1, diff // 60)
        return f"Worked for {mins}m"
    except Exception:
        return "Worked for 5m"

def format_thought_duration(start_iso: Optional[str], end_iso: Optional[str]) -> str:
    if not start_iso or not end_iso:
        return "Thought for a few seconds"
    try:
        dt1 = datetime.fromisoformat(start_iso.replace("Z", "+00:00"))
        dt2 = datetime.fromisoformat(end_iso.replace("Z", "+00:00"))
        diff = int((dt2 - dt1).total_seconds())
        if diff <= 0:
            return "Thought for a few seconds"
        if diff < 60:
            return f"Thought for {diff}s"
        mins = diff // 60
        secs = diff % 60
        if secs > 0:
            return f"Thought for {mins}m {secs}s"
        return f"Thought for {mins}m"
    except Exception:
        return "Thought for a few seconds"


def _compress_step_logs(raw_logs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    compressed = []
    pending_explored = []
    
    for item in raw_logs:
        itype = item.get("type")
        if itype in ("file_view", "analyzed_image", "explore_file"):
            fname = item.get("file") or item.get("image") or ""
            fpath = item.get("path") or fname
            if fname and not any(p.get("name") == fname for p in pending_explored):
                pending_explored.append({"name": fname, "path": fpath})
        else:
            if pending_explored:
                count = len(pending_explored)
                compressed.append({
                    "type": "explore_summary",
                    "title": f"Explored {count} files" if count > 1 else "Explored 1 file",
                    "count": count,
                    "files": list(pending_explored)
                })
                pending_explored.clear()
            compressed.append(item)
            
    if pending_explored:
        count = len(pending_explored)
        compressed.append({
            "type": "explore_summary",
            "title": f"Explored {count} files" if count > 1 else "Explored 1 file",
            "count": count,
            "files": list(pending_explored)
        })
    return compressed


def _normalize_questions(args: Any) -> List[Dict[str, Any]]:
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except Exception:
            args = {}
    if not isinstance(args, dict):
        if isinstance(args, list):
            return _normalize_questions({"questions": args})
        return []

    raw = args.get("questions")
    if raw is None and isinstance(args.get("question_data"), dict):
        raw = args["question_data"].get("questions") or args["question_data"].get("question")
    if raw is None and isinstance(args.get("arguments"), dict):
        raw = args["arguments"].get("questions") or args["arguments"].get("question")

    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except Exception:
            pass

    out = []
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, str):
                try:
                    item = json.loads(item)
                except Exception:
                    item = {"question": item, "options": []}
            if isinstance(item, dict):
                q_text = item.get("question") or item.get("prompt") or item.get("title") or item.get("text") or ""
                raw_opts = item.get("options") or item.get("choices") or item.get("items") or []
                if isinstance(raw_opts, str):
                    try:
                        raw_opts = json.loads(raw_opts)
                    except Exception:
                        raw_opts = [s.strip() for s in raw_opts.split(",") if s.strip()]
                clean_opts = []
                if isinstance(raw_opts, list):
                    for o in raw_opts:
                        if isinstance(o, dict):
                            clean_opts.append(str(o.get("text") or o.get("label") or o.get("title") or o.get("value") or o))
                        elif o is not None:
                            clean_opts.append(str(o))
                out.append({
                    "question": str(q_text),
                    "options": clean_opts,
                    "is_multi_select": bool(item.get("is_multi_select", False))
                })
    elif isinstance(raw, dict):
        return _normalize_questions({"questions": [raw]})

    # Fallback to single question at root of args
    if not out:
        single_q = args.get("question") or (args.get("question_data", {}).get("question") if isinstance(args.get("question_data"), dict) else None)
        if single_q:
            raw_opts = args.get("options") or (args.get("question_data", {}).get("options") if isinstance(args.get("question_data"), dict) else [])
            clean_opts = [str(o) for o in (raw_opts if isinstance(raw_opts, list) else [])]
            out.append({
                "question": str(single_q),
                "options": clean_opts,
                "is_multi_select": bool(args.get("is_multi_select", False))
            })

    return out


def clean_user_prompt(prompt: str) -> str:
    if not prompt:
        return ""
    # Strip injected autonomous execution directive
    if "<AUTONOMOUS_EXECUTION_DIRECTIVE>" in prompt:
        prompt = re.sub(r"<AUTONOMOUS_EXECUTION_DIRECTIVE>.*?</AUTONOMOUS_EXECUTION_DIRECTIVE>", "", prompt, flags=re.DOTALL).strip()
    # Strip injected additional metadata (e.g. uploaded images/files annotations)
    if "<ADDITIONAL_METADATA>" in prompt:
        prompt = re.sub(r"<ADDITIONAL_METADATA>.*?</ADDITIONAL_METADATA>", "", prompt, flags=re.DOTALL).strip()
    if "<SLASH_COMMAND:" in prompt:
        m = re.search(r"<SLASH_COMMAND:\s*(/[a-zA-Z0-9_\-]+)>", prompt)
        if m:
            cmd = m.group(1)
            content_match = re.search(r"(?:Request|Question|Task|Goal|Topic|Preference):\s*(.*)$", prompt, re.DOTALL | re.IGNORECASE)
            if content_match:
                extracted = content_match.group(1).strip()
                if extracted and not extracted.startswith("(No additional arguments"):
                    return f"{cmd} {extracted}"
            return cmd
    return prompt.strip()

def detect_language(filename: str) -> str:
    ext = PurePath(filename).suffix.lower()
    mapping = {
        ".py": "python",
        ".dart": "dart",
        ".ts": "typescript",
        ".tsx": "typescript",
        ".js": "javascript",
        ".jsx": "javascript",
        ".rs": "rust",
        ".go": "go",
        ".c": "c",
        ".cpp": "cpp",
        ".h": "c",
        ".hpp": "cpp",
        ".html": "html",
        ".htm": "html",
        ".css": "css",
        ".scss": "css",
        ".json": "json",
        ".yaml": "yaml",
        ".yml": "yaml",
        ".md": "markdown",
        ".bat": "shell",
        ".cmd": "shell",
        ".sh": "shell",
        ".ps1": "shell",
        ".sql": "sql",
        ".png": "image",
        ".jpg": "image",
        ".jpeg": "image",
        ".svg": "image",
    }
    return mapping.get(ext, "file")

def _clean_str(s: Any) -> Any:
    if not isinstance(s, str):
        return s
    return s.encode('utf-8', 'ignore').decode('utf-8', 'ignore')

def _sanitize_data(data: Any) -> Any:
    if isinstance(data, str):
        return _clean_str(data)
    elif isinstance(data, dict):
        return {_clean_str(k): _sanitize_data(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [_sanitize_data(x) for x in data]
    return data

class HistoryService:
    def __init__(self, gemini_base_dir: Optional[str] = None):
        default_dir = Path.home() / ".gemini" / "antigravity"
        self.base_dir = Path(gemini_base_dir) if gemini_base_dir else default_dir
        self.db_path = self.base_dir / "conversation_summaries.db"
        self.brain_dir = self.base_dir / "brain"
        self.active_cascade_projects: Dict[str, Dict[str, str]] = {}
        self.conversation_aliases: Dict[str, str] = {}
        self._steps_cache: Dict[str, Any] = {}
        self._init_custom_projects()

    def register_alias(self, alias_id: str, real_id: str):
        if alias_id and real_id:
            self.conversation_aliases[alias_id] = real_id
            self.conversation_aliases[real_id] = real_id

    def resolve_active_convo_id(self, convo_id: Optional[str] = None) -> str:
        """Resolves a temp, empty, or alias conversation ID to the true cascade UUID on disk."""
        if convo_id:
            if convo_id in self.conversation_aliases:
                return self.conversation_aliases[convo_id]
            direct_log = self.brain_dir / convo_id / ".system_generated" / "logs" / "transcript.jsonl"
            if direct_log.exists():
                return convo_id
            # If an explicit conversation ID is provided and is not 'active', 'new', 'default' or a generated temp id,
            # do not arbitrarily map it to an unrelated existing conversation!
            if convo_id not in ("active", "new", "default", "") and not convo_id.startswith("convo-"):
                return convo_id

        # Check conversation_summaries.db for latest active conversation
        if self.db_path and self.db_path.exists():
            try:
                conn = sqlite3.connect(str(self.db_path))
                c = conn.cursor()
                c.execute("SELECT conversation_id FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 1")
                row = c.fetchone()
                conn.close()
                if row and row[0]:
                    if convo_id:
                        self.conversation_aliases[convo_id] = row[0]
                    return row[0]
            except Exception:
                pass

        # Check newest directory in brain/
        try:
            if self.brain_dir.exists():
                dirs = [d for d in self.brain_dir.iterdir() if d.is_dir() and (d / ".system_generated" / "logs" / "transcript.jsonl").exists()]
                if dirs:
                    dirs.sort(key=lambda d: (d / ".system_generated" / "logs" / "transcript.jsonl").stat().st_mtime, reverse=True)
                    newest = dirs[0].name
                    if convo_id:
                        self.conversation_aliases[convo_id] = newest
                    return newest
        except Exception:
            pass

        return convo_id or "default"

    def register_active_cascade(self, cascade_id: str, project_name: str, workspace_path: str, project_id: Optional[str] = None):
        self.active_cascade_projects[cascade_id] = {
            "project_name": project_name,
            "workspace_path": workspace_path,
            "project_id": project_id or ""
        }
        self.conversation_aliases[cascade_id] = cascade_id
        if project_id and self.db_path.exists():
            try:
                conn = sqlite3.connect(str(self.db_path))
                c = conn.cursor()
                c.execute("UPDATE conversation_summaries SET project_id = ? WHERE conversation_id = ?", (project_id, cascade_id))
                conn.commit()
                conn.close()
            except Exception:
                pass

    def touch_conversation(self, conversation_id: str, title: Optional[str] = None, preview: Optional[str] = None, project_name: Optional[str] = None, workspace_path: Optional[str] = None):
        """Immediately update or insert conversation summary in SQLite to ensure recent chats order is always up-to-date."""
        try:
            if not self.db_path.exists():
                return
            conn = sqlite3.connect(str(self.db_path))
            c = conn.cursor()
            c.execute("SELECT conversation_id, title, preview FROM conversation_summaries WHERE conversation_id = ?", (conversation_id,))
            row = c.fetchone()
            if row:
                if title and title != "New Conversation":
                    c.execute("""
                        UPDATE conversation_summaries 
                        SET last_modified_time = datetime('now'), preview = COALESCE(?, preview), title = ?
                        WHERE conversation_id = ?
                    """, (preview, title, conversation_id))
                else:
                    c.execute("""
                        UPDATE conversation_summaries 
                        SET last_modified_time = datetime('now'), preview = COALESCE(?, preview)
                        WHERE conversation_id = ?
                    """, (preview, conversation_id))
            else:
                uris = json.dumps([f"file:///{str(workspace_path).replace(os.sep, '/')}" if workspace_path else ""])
                c.execute("""
                    INSERT OR REPLACE INTO conversation_summaries 
                    (conversation_id, title, preview, step_count, last_modified_time, workspace_uris, status, project_id)
                    VALUES (?, ?, ?, 1, datetime('now'), ?, 'done', '')
                """, (conversation_id, title or f"Conversation {conversation_id[:8]}", preview or "", uris))
            conn.commit()
            conn.close()

            # Also update in-memory active cascade if present
            if conversation_id in self.active_cascade_projects:
                if title and title != "New Conversation":
                    self.active_cascade_projects[conversation_id]["title"] = title
                if preview:
                    self.active_cascade_projects[conversation_id]["preview"] = preview
                self.active_cascade_projects[conversation_id]["last_modified"] = time.time()

            # Push live update to Antigravity Desktop IDE via CDP so desktop updates without restart
            try:
                cdp_client.sync_touch_conversation(conversation_id, prompt=preview or title or "")
            except Exception:
                pass
        except Exception:
            pass

    def _init_custom_projects(self):
        CUSTOM_PROJECTS_FILE.parent.mkdir(parents=True, exist_ok=True)
        if not CUSTOM_PROJECTS_FILE.exists():
            CUSTOM_PROJECTS_FILE.write_text(json.dumps({
                "added": [],
                "removed": []
            }, indent=2), encoding="utf-8")

    def _load_custom_config(self) -> Dict[str, Any]:
        try:
            if CUSTOM_PROJECTS_FILE.exists():
                with open(CUSTOM_PROJECTS_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
        except Exception:
            pass
        return {"added": [], "removed": []}

    def _save_custom_config(self, cfg: Dict[str, Any]):
        try:
            CUSTOM_PROJECTS_FILE.parent.mkdir(parents=True, exist_ok=True)
            with open(CUSTOM_PROJECTS_FILE, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2)
        except Exception:
            pass

    def add_custom_project(self, name: str, path: str) -> Dict[str, str]:
        clean_name = name.strip()
        clean_path = path.strip() if path else ""
        
        p = Path(clean_path)
        if not clean_path or not p.is_absolute():
            projects_dir = Path.home() / "AntigravityProjects"
            projects_dir.mkdir(parents=True, exist_ok=True)
            p = projects_dir / (clean_name or "project")
        
        p.mkdir(parents=True, exist_ok=True)
        resolved_path = str(p.resolve()).replace("\\", "/")

        # Register in Antigravity Desktop IDE via CDP
        created = cdp_client.create_project(clean_name, resolved_path)
        pid = created.get("id") if created else str(uuid.uuid4())

        cfg = self._load_custom_config()
        cfg["added"] = [item for item in cfg.get("added", []) if item.get("name") != clean_name]
        cfg.setdefault("added", []).append({
            "id": pid,
            "name": clean_name,
            "path": resolved_path
        })
        if clean_name in cfg.get("removed", []):
            cfg["removed"].remove(clean_name)
        self._save_custom_config(cfg)
        return {"id": pid, "name": clean_name, "path": resolved_path}

    def get_project_id_by_name(self, name: Optional[str], workspace_path: Optional[str] = None) -> Optional[str]:
        target_name = (name or "Workspace").strip()
        cfg = self._load_custom_config()
        for item in cfg.get("added", []):
            if item.get("name") == target_name and item.get("id"):
                return item["id"]
        
        fallback_path = workspace_path or str((Path.home() / "AntigravityProjects" / target_name).resolve()).replace("\\", "/")

        # Check live projects from Antigravity Desktop IDE via CDP
        try:
            live_projects = cdp_client.get_live_projects()
            for lp in live_projects:
                lp_name = lp.get("name") or ""
                if lp_name == target_name or target_name.lower() in lp_name.lower():
                    pid = lp.get("id")
                    if pid:
                        cfg["added"] = [item for item in cfg.get("added", []) if item.get("name") != target_name]
                        cfg.setdefault("added", []).append({
                            "id": pid,
                            "name": target_name,
                            "path": fallback_path
                        })
                        self._save_custom_config(cfg)
                        return pid
        except Exception:
            pass

        # Create project live in Antigravity
        created = self.add_custom_project(target_name, fallback_path)
        return created.get("id")

    def remove_project(self, name: str):
        cfg = self._load_custom_config()
        cfg["added"] = [p for p in cfg.get("added", []) if p.get("name") != name]
        if name not in cfg.get("removed", []):
            cfg.setdefault("removed", []).append(name)
        self._save_custom_config(cfg)

    def get_projects_grouped(self, active_convo_id: Optional[str] = None, active_project: Optional[str] = None) -> Dict[str, Any]:
        """Returns projects and their conversations matching Antigravity modern monochrome IDE structure."""
        custom_cfg = self._load_custom_config()
        removed_names = set(custom_cfg.get("removed", []))
        
        project_convos: Dict[str, List[Dict[str, Any]]] = {}
        project_paths: Dict[str, str] = {}
        project_ids: Dict[str, str] = {}
        id_to_name: Dict[str, str] = {}

        # 1. Seed with custom projects config
        for cp in custom_cfg.get("added", []):
            cname = cp.get("name")
            cid = cp.get("id")
            cpath = cp.get("path", "")
            if cname and cname not in removed_names:
                project_convos.setdefault(cname, [])
                project_paths[cname] = cpath
                if cid:
                    project_ids[cname] = cid
                    id_to_name[cid] = cname

        # 2. Query live projects from Antigravity Desktop IDE via CDP
        try:
            live_projects = cdp_client.get_live_projects()
            for lp in live_projects:
                lname = lp.get("name")
                lid = lp.get("id")
                luri = lp.get("uri", "")
                if lname and lname not in removed_names:
                    project_convos.setdefault(lname, [])
                    if lid:
                        project_ids[lname] = lid
                        id_to_name[lid] = lname
                    if luri and lname not in project_paths:
                        path_str = urllib.parse.unquote(urllib.parse.urlparse(luri).path)
                        if path_str.startswith("/") and ":" in path_str:
                            path_str = path_str[1:]
                        project_paths[lname] = path_str
        except Exception:
            pass

        # Determine dynamic default workspace
        try:
            from bridge.core.workspace_service import workspace_svc
            default_ws = str(workspace_svc.active_root) if (workspace_svc and workspace_svc.active_root) else str(Path.cwd())
        except Exception:
            default_ws = str(Path.cwd())
        default_name = PurePath(default_ws).name or "Workspace"

        # 3. Read SQLite summaries databases (search multiple candidate locations for worldwide compatibility)
        candidate_dbs = []
        if self.db_path and self.db_path not in candidate_dbs:
            candidate_dbs.append(self.db_path)
        for cand in [
            Path.home() / ".gemini" / "antigravity" / "conversation_summaries.db",
            Path.home() / ".antigravity" / "conversation_summaries.db",
            Path.home() / "AppData" / "Roaming" / "Antigravity" / "conversation_summaries.db",
            Path.home() / ".config" / "antigravity" / "conversation_summaries.db",
        ]:
            if cand not in candidate_dbs and cand.exists():
                candidate_dbs.append(cand)

        seen_convo_ids = set()
        for db in candidate_dbs:
            if not db.exists():
                continue
            try:
                conn = sqlite3.connect(str(db))
                c = conn.cursor()
                c.execute("""
                    SELECT conversation_id, title, preview, step_count, last_modified_time, workspace_uris, status, project_id 
                    FROM conversation_summaries 
                    ORDER BY last_modified_time DESC;
                """)
                rows = c.fetchall()
                conn.close()

                for cid, title, prev, steps, mtime, uris, status, pid in rows:
                    if cid in seen_convo_ids:
                        continue
                    seen_convo_ids.add(cid)

                    pname = None
                    ppath = default_ws

                    # Match by project_id first
                    if pid and pid in id_to_name:
                        pname = id_to_name[pid]
                        ppath = project_paths.get(pname, default_ws)
                    
                    # Fallback match by workspace URI
                    if not pname and uris and uris.strip():
                        try:
                            parsed = json.loads(uris)
                            if parsed:
                                u = parsed[0]
                                path_str = urllib.parse.unquote(urllib.parse.urlparse(u).path)
                                if path_str.startswith("/") and ":" in path_str:
                                    path_str = path_str[1:]
                                candidate = PurePath(path_str).name or default_name
                                pname = candidate
                                ppath = path_str
                        except Exception:
                            pass

                    if not pname:
                        pname = default_name

                    if pname in removed_names:
                        continue

                    # Register mapping bi-directionally so app_storage.json projectsOrder resolves
                    if pid and pid not in id_to_name:
                        id_to_name[pid] = pname
                    if pid and pname not in project_ids:
                        project_ids[pname] = pid

                    if pname not in project_convos:
                        project_convos[pname] = []
                        project_paths[pname] = ppath

                    project_convos[pname].append({
                        "id": cid,
                        "title": title or f"Conversation {cid[:8]}",
                        "preview": prev or "",
                        "step_count": steps or 0,
                        "status": status or "done",
                        "last_modified": mtime,
                        "has_unread": (status != "read"),
                        "is_active": (cid == active_convo_id)
                    })
            except Exception as e:
                logger.debug(f"Error reading DB {db}: {e}")

        # 4. Auto-discover local project folders on the user's host (ensures projects exist even with 0 conversations)
        scan_project_roots = []
        try:
            from bridge.core.workspace_service import workspace_svc
            if workspace_svc and workspace_svc.allowed_roots:
                for r in workspace_svc.allowed_roots:
                    p = Path(r)
                    if p.exists() and p.is_dir() and p not in scan_project_roots:
                        scan_project_roots.append(p)
        except Exception:
            pass

        extra_project_dirs = [
            Path.cwd() / "projects",
            Path.home() / "AntigravityProjects",
            Path.home() / "Projects",
            Path.home() / "Developer",
            Path.home() / "Documents" / "Projects",
        ]
        for ep in extra_project_dirs:
            if ep.exists() and ep.is_dir() and ep not in scan_project_roots:
                scan_project_roots.append(ep)

        for proot in scan_project_roots:
            try:
                for sub in proot.iterdir():
                    if sub.is_dir() and not sub.name.startswith((".", "_")):
                        if sub.name not in ("node_modules", "build", "dist", "target", "venv", ".venv", "__pycache__"):
                            if sub.name not in removed_names and sub.name not in project_convos:
                                project_convos[sub.name] = []
                                project_paths[sub.name] = str(sub.resolve()).replace("\\", "/")
            except Exception:
                pass

        # 5. Include active in-memory cascades
        for cid, meta in self.active_cascade_projects.items():
            p = meta.get("project_name") or default_name
            w = meta.get("workspace_path") or default_ws
            if p not in project_convos:
                project_convos[p] = []
                project_paths[p] = w
            if not any(c["id"] == cid for c in project_convos[p]):
                project_convos[p].insert(0, {
                    "id": cid,
                    "title": "New Conversation",
                    "preview": "Ready for prompt",
                    "step_count": 0,
                    "status": "idle",
                    "last_modified": time.time(),
                    "has_unread": False,
                    "is_active": (cid == active_convo_id)
                })

        # Resolve exact PC project ordering (live CDP sidebar order with app_storage.json fallback)
        pc_ordered_ids = []
        try:
            pc_ordered_ids = cdp_client.get_sidebar_project_order()
        except Exception:
            pass

        if not pc_ordered_ids:
            try:
                storage_paths = [
                    Path(appdata) / "Antigravity" / "app_storage.json" if appdata else Path("/nonexistent"),
                    Path.home() / "AppData" / "Roaming" / "Antigravity" / "app_storage.json",
                    Path.home() / "Library" / "Application Support" / "Antigravity" / "app_storage.json",
                    Path.home() / ".config" / "Antigravity" / "app_storage.json",
                    Path.home() / ".gemini" / "antigravity" / "app_storage.json"
                ]
                for sp in storage_paths:
                    if sp.exists():
                        d = json.loads(sp.read_text(encoding="utf-8"))
                        po = d.get("projectsOrder", [])
                        if isinstance(po, str):
                            po = json.loads(po)
                        lc = d.get("lastCreatedProjectId")
                        if lc and lc not in po:
                            po = [lc] + po
                        if po:
                            pc_ordered_ids = po
                            break
            except Exception:
                pass

        ordered_projects = []
        # 1. Projects in exact PC sidebar order
        for pid in pc_ordered_ids:
            pname = id_to_name.get(pid)
            if pname and pname in project_convos and pname not in ordered_projects and pname not in removed_names:
                ordered_projects.append(pname)

        # 2. Custom projects added by user not yet in PC order
        for cp in custom_cfg.get("added", []):
            cname = cp.get("name")
            if cname and cname in project_convos and cname not in ordered_projects and cname not in removed_names:
                ordered_projects.append(cname)

        # 3. Remaining discovered projects, maintaining most-recently-active order
        for p in project_convos.keys():
            if p not in ordered_projects and p not in removed_names:
                ordered_projects.append(p)

        if not ordered_projects:
            ordered_projects.append(default_name)
            project_convos.setdefault(default_name, [])
            project_paths.setdefault(default_name, default_ws)

        resolved_active_project = active_project if (active_project and active_project in project_convos) else ordered_projects[0]
        if not active_project and active_convo_id:
            for p in ordered_projects:
                if any(c["id"] == active_convo_id for c in project_convos.get(p, [])):
                    resolved_active_project = p
                    break

        target_convos = project_convos.get(resolved_active_project, [])
        if active_convo_id:
            if not any(c["id"] == active_convo_id for c in target_convos):
                meta = self.active_cascade_projects.get(active_convo_id, {})
                target_convos.insert(0, {
                    "id": active_convo_id,
                    "title": meta.get("title") or "New Conversation",
                    "preview": meta.get("preview") or "Ready for prompt",
                    "step_count": 0,
                    "status": "idle",
                    "last_modified": time.time(),
                    "has_unread": False,
                    "is_active": True
                })

        project_list = []
        for p in ordered_projects:
            convos = project_convos.get(p, [])
            if not active_convo_id and convos and p == resolved_active_project:
                active_convo_id = convos[0]["id"]

            for c in convos:
                c["is_active"] = (c["id"] == active_convo_id)

            project_list.append({
                "id": project_ids.get(p, ""),
                "name": p,
                "path": project_paths.get(p, ""),
                "is_expanded": (p == resolved_active_project),
                "total_conversations": len(convos),
                "conversations": convos[:10]
            })

        default_fallback_convo = active_convo_id or (target_convos[0]["id"] if target_convos else "new")

        return _sanitize_data({
            "active_project": resolved_active_project,
            "active_conversation_id": default_fallback_convo,
            "projects": project_list
        })

    def get_conversation_steps(self, conversation_id: str) -> Dict[str, Any]:
        """Parses transcript.jsonl into full multi-turn conversation history matching the Antigravity desktop IDE trail."""
        resolved_id = self.resolve_active_convo_id(conversation_id)
        log_file = self.brain_dir / resolved_id / ".system_generated" / "logs" / "transcript.jsonl"
        if not log_file.exists() and conversation_id != resolved_id:
            log_file = self.brain_dir / conversation_id / ".system_generated" / "logs" / "transcript.jsonl"
            if log_file.exists():
                resolved_id = conversation_id

        if not log_file.exists():
            return {
                "conversation_id": conversation_id,
                "resolved_conversation_id": resolved_id,
                "is_working": False,
                "turns": [],
                "user_prompt": "",
                "edited_files": [],
                "explored_files_count": 0,
                "tasks_count": 0,
                "commands_count": 0,
                "step_logs": [],
                "thinking": "",
                "final_content": ""
            }

        file_mtime = 0.0
        file_size = 0
        try:
            st = log_file.stat()
            file_mtime = st.st_mtime
            file_size = st.st_size
            cached = self._steps_cache.get(conversation_id)
            if cached and cached.get("mtime") == file_mtime and cached.get("size") == file_size:
                cdata = cached["data"]
                return {
                    **cdata,
                    "turns": [dict(t) for t in cdata.get("turns", [])]
                }
        except Exception:
            pass

        turns = []
        current_turn = None
        last_step_in_file = None
        file_contents: Dict[str, str] = {}
        running_tasks_map: Dict[str, Dict[str, Any]] = {}

        try:
            with open(log_file, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line_str = line.strip()
                    if not line_str:
                        continue
                    step = json.loads(line_str)
                    last_step_in_file = step
                    stype = step.get("type")

                    if stype == "USER_INPUT":
                        raw_c = step.get("content", "")
                        # Skip pure context summaries without user requests
                        if "<CONTEXT_SUMMARY>" in raw_c and "<USER_REQUEST>" not in raw_c:
                            continue

                        # Extract clean prompt from <USER_REQUEST>
                        if "<USER_REQUEST>" in raw_c:
                            parts = raw_c.split("<USER_REQUEST>")
                            if len(parts) > 1:
                                prompt = parts[1].split("</USER_REQUEST>")[0].strip()
                            else:
                                prompt = raw_c.strip()
                        else:
                            prompt = raw_c.strip()

                        prompt = clean_user_prompt(prompt)
                        if not prompt:
                            continue

                        step_time = step.get("created_at")

                        if current_turn:
                            file_aggregates = {}
                            for slog in current_turn.get("step_logs", []):
                                if slog.get("type") == "file_edit":
                                    fn = slog.get("file")
                                    fpath = slog.get("path")
                                    if fn:
                                        if fn not in file_aggregates:
                                            file_aggregates[fn] = {
                                                "name": fn,
                                                "path": fpath,
                                                "language": slog.get("language"),
                                                "additions": slog.get("additions", 0),
                                                "deletions": slog.get("deletions", 0)
                                            }
                                        else:
                                            file_aggregates[fn]["additions"] += slog.get("additions", 0)
                                            file_aggregates[fn]["deletions"] += slog.get("deletions", 0)
                            current_turn["edited_files"] = list(file_aggregates.values())
                            current_turn.pop("file_start_contents", None)
                            current_turn["explored_files_count"] = len(current_turn["explored_files"])
                            del current_turn["explored_files"]
                            current_turn["commands_count"] = len(current_turn["commands_run"])
                            del current_turn["commands_run"]
                            current_turn["worked_duration"] = format_duration(current_turn.get("start_time"), current_turn.get("last_time"))
                            current_turn["thought_duration"] = format_thought_duration(current_turn.get("start_time"), current_turn.get("thought_end_time") or current_turn.get("last_time"))
                            current_turn["step_logs"] = _compress_step_logs(current_turn["step_logs"][-100:])
                            turns.append(current_turn)

                        current_turn = {
                            "turn_id": len(turns) + 1,
                            "user_prompt": prompt,
                            "prompt_time": format_iso_time(step_time),
                            "start_time": step_time,
                            "last_time": step_time,
                            "worked_duration": "Worked for 1m",
                            "thought_duration": "Thought for a few seconds",
                            "thought_end_time": None,
                            "file_start_contents": dict(file_contents),
                            "edited_files": {},
                            "explored_files": set(),
                            "commands_run": [],
                            "step_logs": [],
                            "thinking": "",
                            "response": "",
                            "is_working": False,
                            "question_data": None
                        }

                    elif current_turn and stype == "PLANNER_RESPONSE":
                        if step.get("created_at"):
                            current_turn["last_time"] = step.get("created_at")
                        if step.get("thinking"):
                            current_turn["thinking"] = step.get("thinking")
                            current_turn["thought_end_time"] = step.get("created_at") or current_turn.get("last_time")
                        if step.get("content"):
                            current_turn["response"] = step.get("content")

                        for tc in step.get("tool_calls", []):
                            raw_name = str(tc.get("name", "")).strip()
                            name = raw_name.split(":")[-1]
                            args = tc.get("args", {})
                            if isinstance(args, str):
                                try:
                                    args = json.loads(args)
                                except Exception:
                                    args = {}

                            if name in ["replace_file_content", "write_to_file"]:
                                target = args.get("TargetFile") or args.get("TargetContent", "")
                                target_path = str(target).replace('"', '').replace('\\', '/')
                                fname = PurePath(target_path).name
                                if fname:
                                    lang = detect_language(fname)
                                    repl = str(args.get("ReplacementContent") or args.get("CodeContent", ""))
                                    targ = str(args.get("TargetContent", ""))
                                    if "\\n" in repl or "\\r\\n" in repl or '\\"' in repl:
                                        repl = repl.replace("\\r\\n", "\n").replace("\\n", "\n").replace('\\"', '"')
                                    if "\\n" in targ or "\\r\\n" in targ or '\\"' in targ:
                                        targ = targ.replace("\\r\\n", "\n").replace("\\n", "\n").replace('\\"', '"')

                                    if name == "write_to_file":
                                        if target_path in file_contents:
                                            prev_c = file_contents[target_path]
                                            diff = list(difflib.unified_diff(
                                                prev_c.splitlines(),
                                                repl.splitlines(),
                                                lineterm=""
                                            ))
                                            add_lines = sum(1 for l in diff if l.startswith('+') and not l.startswith('+++'))
                                            del_lines = sum(1 for l in diff if l.startswith('-') and not l.startswith('---'))
                                        else:
                                            add_lines = max(1, len(repl.splitlines())) if repl else 1
                                            del_lines = 0
                                        file_contents[target_path] = repl
                                    else:
                                        diff = list(difflib.unified_diff(
                                            targ.splitlines(),
                                            repl.splitlines(),
                                            lineterm=""
                                        ))
                                        add_lines = sum(1 for l in diff if l.startswith('+') and not l.startswith('+++'))
                                        del_lines = sum(1 for l in diff if l.startswith('-') and not l.startswith('---'))
                                        if target_path in file_contents and targ:
                                            file_contents[target_path] = file_contents[target_path].replace(targ, repl, 1)
                                        else:
                                            file_contents[target_path] = repl

                                    file_log_entry = {
                                        "type": "file_edit",
                                        "title": f"Edited {fname}",
                                        "file": fname,
                                        "path": target_path,
                                        "language": lang,
                                        "additions": add_lines,
                                        "deletions": del_lines
                                    }
                                    current_turn["step_logs"].append(file_log_entry)

                            elif name == "view_file":
                                fpath = str(args.get("AbsolutePath", "")).replace('"', '').replace('\\', '/')
                                fname = PurePath(fpath).name
                                if fname:
                                    current_turn["explored_files"].add(fname)
                                    current_turn["step_logs"].append({
                                        "type": "explore_file",
                                        "title": f"Explored {fname}",
                                        "file": fname,
                                        "path": fpath
                                    })

                            elif name == "run_command":
                                cmd = str(args.get("CommandLine", "")).strip().strip('"')
                                tool_action = str(args.get("toolAction", "")).strip().strip('"')
                                current_turn["commands_run"].append(cmd)
                                current_turn["step_logs"].append({
                                    "type": "command",
                                    "title": f"Ran {cmd[:45]}..." if len(cmd) > 45 else f"Ran {cmd}",
                                    "command": cmd,
                                    "action": tool_action,
                                    "output": ""
                                })

                            elif name == "manage_task":
                                act = args.get("Action", "")
                                current_turn["step_logs"].append({
                                    "type": "task_action",
                                    "title": f"Task Action: {act}",
                                    "action": act
                                })

                            elif name == "ask_question":
                                parsed_questions = _normalize_questions(args)
                                q_title = parsed_questions[0]["question"] if parsed_questions else "Clarification requested"
                                short_title = (q_title[:45] + "...") if len(q_title) > 45 else q_title
                                current_turn["step_logs"].append({
                                    "type": "ask_question",
                                    "title": f"Question: {short_title}",
                                    "questions": parsed_questions,
                                    "tool_summary": args.get("toolSummary", ""),
                                    "tool_action": args.get("toolAction", ""),
                                    "answered": False,
                                    "answer": ""
                                })
                                current_turn["question_data"] = {
                                    "questions": parsed_questions,
                                    "tool_summary": args.get("toolSummary", ""),
                                    "tool_action": args.get("toolAction", ""),
                                    "answered": False,
                                    "answer": ""
                                }

                    elif current_turn and stype == "GENERIC":
                        if step.get("created_at"):
                            current_turn["last_time"] = step.get("created_at")
                        content = step.get("content", "")

                        # Track background task status changes
                        if "Task id " in content and ("finished with result" in content or "was canceled" in content):
                            m_tid = re.search(r'Task id\s+"([^"]+)"', content)
                            if m_tid:
                                tid = m_tid.group(1)
                                running_tasks_map.pop(tid, None)
                                for k in list(running_tasks_map.keys()):
                                    if tid in k:
                                        running_tasks_map.pop(k, None)

                        if "Tool is running as a background task with task id:" in content:
                            m_tid = re.search(r'task id:\s*([^\s\n\r]+)', content)
                            m_log = re.search(r'Task logs are available at:\s*([^\s\n\r]+)', content)
                            if m_tid:
                                tid = m_tid.group(1).strip()
                                log_uri = m_log.group(1).strip() if m_log else ""
                                last_cmd = current_turn["commands_run"][-1] if current_turn.get("commands_run") else "Task"
                                running_tasks_map[tid] = {
                                    "id": tid,
                                    "command": last_cmd,
                                    "title": f"Ran {last_cmd[:40]}",
                                    "is_running": True,
                                    "is_daemon": True,
                                    "log_uri": log_uri
                                }

                        # If output was truncated to output.txt, read the full diff from disk
                        if "output.txt" in content and "The tool's output was truncated" in content:
                            m_path = re.search(r"file:///([^\s]+output\.txt)", content)
                            if m_path:
                                txt_path = m_path.group(1).replace("/", "\\")
                                try:
                                    with open(txt_path, "r", encoding="utf-8", errors="replace") as tf:
                                        content = tf.read()
                                except Exception:
                                    pass

                        # Parse diff block if present to update exact line counts
                        if "[diff_block_start]" in content and "[diff_block_end]" in content:
                            try:
                                m_file = re.search(r"The following changes were made by the \w+ tool to: ([^\n\r]+)", content)
                                target_file_in_diff = None
                                if m_file:
                                    raw_target = m_file.group(1).strip()
                                    if ". If relevant" in raw_target:
                                        raw_target = raw_target.split(". If relevant")[0]
                                    target_file_in_diff = PurePath(str(raw_target).strip().rstrip(".").replace("\\", "/")).name

                                diff_part = content.split("[diff_block_start]")[1].split("[diff_block_end]")[0]
                                diff_lines = diff_part.splitlines()
                                real_adds = sum(1 for l in diff_lines if l.startswith('+') and not l.startswith('+++'))
                                real_dels = sum(1 for l in diff_lines if l.startswith('-') and not l.startswith('---'))

                                # Find matching file_edit in step_logs
                                for slog in reversed(current_turn.get("step_logs", [])):
                                    if slog.get("type") == "file_edit":
                                        if not target_file_in_diff or slog.get("file") == target_file_in_diff:
                                            slog["additions"] = real_adds
                                            slog["deletions"] = real_dels
                                            break
                            except Exception as e:
                                logger.warning(f"Error parsing diff block: {e}")

                        # Attach command output if previous log was a command
                        for slog in reversed(current_turn.get("step_logs", [])):
                            if slog.get("type") == "command" and not slog.get("output"):
                                clean_out = content
                                if "Output:\n" in clean_out:
                                    clean_out = clean_out.split("Output:\n", 1)[1]
                                slog["output"] = clean_out.strip()
                                break
                        if "A1:" in content or "A2:" in content:
                            lines_c = [l.strip() for l in content.splitlines() if l.strip().startswith("A1:") or l.strip().startswith("A2:")]
                            if lines_c:
                                ans_str = " | ".join(lines_c)
                                if current_turn.get("question_data"):
                                    current_turn["question_data"]["answered"] = True
                                    current_turn["question_data"]["answer"] = ans_str
                                for slog in current_turn.get("step_logs", []):
                                    if slog.get("type") == "ask_question":
                                        slog["answered"] = True
                                        slog["answer"] = ans_str

            if current_turn:
                file_aggregates = {}
                for slog in current_turn.get("step_logs", []):
                    if slog.get("type") == "file_edit":
                        fn = slog.get("file")
                        fpath = slog.get("path")
                        if fn:
                            if fn not in file_aggregates:
                                file_aggregates[fn] = {
                                    "name": fn,
                                    "path": fpath,
                                    "language": slog.get("language"),
                                    "additions": slog.get("additions", 0),
                                    "deletions": slog.get("deletions", 0)
                                }
                            else:
                                file_aggregates[fn]["additions"] += slog.get("additions", 0)
                                file_aggregates[fn]["deletions"] += slog.get("deletions", 0)
                current_turn["edited_files"] = list(file_aggregates.values())
                current_turn.pop("file_start_contents", None)
                current_turn["explored_files_count"] = len(current_turn["explored_files"])
                del current_turn["explored_files"]
                current_turn["commands_count"] = len(current_turn["commands_run"])
                del current_turn["commands_run"]
                current_turn["worked_duration"] = format_duration(current_turn.get("start_time"), current_turn.get("last_time"))
                current_turn["thought_duration"] = format_thought_duration(current_turn.get("start_time"), current_turn.get("thought_end_time") or current_turn.get("last_time"))
                current_turn["step_logs"] = _compress_step_logs(current_turn["step_logs"][-100:])
                
                is_turn_working = False
                if last_step_in_file and log_file.exists():
                    try:
                        mtime_age = time.time() - log_file.stat().st_mtime
                    except Exception:
                        mtime_age = 0

                    st = last_step_in_file.get("type")
                    stat = last_step_in_file.get("status")
                    tc = last_step_in_file.get("tool_calls", [])
                    has_content = bool(last_step_in_file.get("content"))

                    # If file has not been touched in > 90 seconds, agent cannot be actively running
                    if mtime_age > 90:
                        is_turn_working = False
                    elif current_turn.get("question_data") and not current_turn["question_data"].get("answered"):
                        # Interactive question waiting for user input - NOT working!
                        is_turn_working = False
                    elif current_turn.get("response", "").strip() and not tc and stat in ("DONE", "ERROR", "CANCELLED") and mtime_age > 20:
                        # Turn already produced a final assistant response without pending tool calls and stabilized
                        is_turn_working = False
                    elif stat in ("RUNNING", "PENDING"):
                        is_turn_working = True
                    elif st == "USER_INPUT" and mtime_age <= 90:
                        is_turn_working = True
                    elif st == "GENERIC" and stat in ("RUNNING", "PENDING"):
                        is_turn_working = True
                    elif st == "GENERIC" and mtime_age <= 60:
                        # Tool step just finished moments ago, model may be executing next action
                        is_turn_working = True
                    elif st == "PLANNER_RESPONSE" and (tc or not has_content) and mtime_age <= 90:
                        # Tool execution in flight or thinking in progress
                        is_turn_working = True
                    elif tc:
                        # Unfulfilled tool calls in current turn
                        is_turn_working = True
                    else:
                        is_turn_working = False

                if current_turn.get("question_data") and not current_turn["question_data"].get("answered"):
                    current_turn["is_working"] = False
                    current_turn["status"] = "waiting_for_input"
                elif current_turn.get("response", "").strip() and not tc and stat in ("DONE", "ERROR", "CANCELLED") and mtime_age > 20:
                    current_turn["is_working"] = False
                else:
                    current_turn["is_working"] = is_turn_working
                turns.append(current_turn)

        except Exception as e:
            pass

        last = turns[-1] if turns else {
            "turn_id": 1,
            "user_prompt": "",
            "edited_files": [],
            "explored_files_count": 0,
            "commands_count": 0,
            "step_logs": [],
            "thinking": "",
            "response": "",
            "is_working": False
        }

        is_currently_working = bool(turns and turns[-1].get("is_working", False))

        active_tasks = self.get_running_tasks(conversation_id)
        if not active_tasks and resolved_id != conversation_id:
            active_tasks = self.get_running_tasks(resolved_id)
        if active_tasks:
            is_currently_working = True
            if turns:
                turns[-1]["is_working"] = True

        res = _sanitize_data({
            "conversation_id": conversation_id,
            "resolved_conversation_id": resolved_id,
            "is_working": is_currently_working,
            "turns": turns,
            "user_prompt": last["user_prompt"],
            "edited_files": last["edited_files"],
            "explored_files_count": last["explored_files_count"],
            "tasks_count": last.get("tasks_count", 0),
            "commands_count": last["commands_count"],
            "step_logs": last["step_logs"][-15:],
            "active_tasks": active_tasks,
            "running_tasks": active_tasks,
            "thinking": last["thinking"],
            "thought_duration": last.get("thought_duration") or "Thought for a few seconds",
            "final_content": last["response"]
        })

        if file_mtime > 0 and not is_currently_working and len(self._steps_cache) < 100:
            self._steps_cache[conversation_id] = {
                "mtime": file_mtime,
                "size": file_size,
                "data": res
            }

        return res

    async def list_conversations(self, limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
        convos = []
        custom_cfg = self._load_custom_config()
        id_to_name = {cp["id"]: cp["name"] for cp in custom_cfg.get("added", []) if cp.get("id")}
        default_pname = PurePath(str(Path.cwd())).name or "Workspace"

        if self.db_path.exists():
            try:
                conn = sqlite3.connect(str(self.db_path))
                c = conn.cursor()
                c.execute("""
                    SELECT conversation_id, title, preview, step_count, last_modified_time, workspace_uris, status, project_id 
                    FROM conversation_summaries 
                    ORDER BY last_modified_time DESC 
                    LIMIT ? OFFSET ?;
                """, (limit, offset))
                rows = c.fetchall()
                conn.close()

                for cid, title, prev, steps, mtime, uris, status, pid in rows:
                    pname = None
                    if pid and pid in id_to_name:
                        pname = id_to_name[pid]
                    if not pname and uris:
                        try:
                            parsed = json.loads(uris) if uris else []
                            if parsed:
                                u = parsed[0]
                                path_str = urllib.parse.unquote(urllib.parse.urlparse(u).path)
                                if path_str.startswith("/") and ":" in path_str:
                                    path_str = path_str[1:]
                                pname = PurePath(path_str).name or default_pname
                        except Exception:
                            pass
                    if not pname:
                        pname = default_pname

                    convos.append({
                        "id": cid,
                        "title": title or f"Conversation {cid[:8]}",
                        "preview": prev or "",
                        "project": pname,
                        "step_count": steps or 0,
                        "last_modified": mtime or "",
                        "status": status or "done"
                    })
            except Exception:
                pass

        # Merge in-memory active cascades at top if not already present
        existing_ids = {c["id"] for c in convos}
        for cid, meta in reversed(list(self.active_cascade_projects.items())):
            if cid not in existing_ids:
                convos.insert(0, {
                    "id": cid,
                    "title": meta.get("title") or "New Conversation",
                    "preview": meta.get("preview") or "Ready for prompt",
                    "project": meta.get("project_name") or default_pname,
                    "step_count": meta.get("step_count", 0),
                    "last_modified": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
                    "status": "idle"
                })

        return convos

    def get_running_tasks(self, conversation_id: str = "") -> List[Dict[str, Any]]:
        """Returns active background tasks directly from PC IDE via CDP."""
        try:
            cdp_tasks = cdp_client.get_running_tasks()
            if cdp_tasks:
                if conversation_id:
                    matched = [t for t in cdp_tasks if conversation_id in t.get("id", "")]
                    return matched
                return cdp_tasks
        except Exception:
            pass
        return []
