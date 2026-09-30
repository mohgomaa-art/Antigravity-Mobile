import asyncio
import json
import logging
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional
import websockets

logger = logging.getLogger("agy.cdp_client")

class AntigravityCdpClient:
    """
    Direct Chrome DevTools Protocol (CDP) client connecting to the active
    Google Antigravity Desktop IDE Electron instance.
    Enables instant project creation, Redux state inspection, and sidebar synchronization.
    """

    def __init__(self, app_data_dir: Optional[Path] = None):
        if not app_data_dir:
            import os
            appdata = os.environ.get("APPDATA")
            candidates = [
                Path(appdata) / "Antigravity" if appdata else Path("/nonexistent"),
                Path.home() / "AppData" / "Roaming" / "Antigravity",
                Path.home() / "Library" / "Application Support" / "Antigravity",
                Path.home() / ".config" / "Antigravity",
            ]
            chosen = candidates[0]
            for c in candidates:
                if c.exists():
                    chosen = c
                    break
            self.app_data_dir = chosen
        else:
            self.app_data_dir = app_data_dir
        self.dev_tools_port_file = self.app_data_dir / "DevToolsActivePort"
        self._cached_port: Optional[int] = None

    def get_cdp_port(self) -> Optional[int]:
        """Resolves the live random CDP port from DevToolsActivePort."""
        if self.dev_tools_port_file.exists():
            try:
                lines = [l.strip() for l in self.dev_tools_port_file.read_text(encoding="utf-8").splitlines() if l.strip()]
                if lines and lines[0].isdigit():
                    self._cached_port = int(lines[0])
                    return self._cached_port
            except Exception as e:
                logger.debug(f"Failed to read DevToolsActivePort: {e}")
        return self._cached_port

    def get_websocket_debugger_url(self) -> Optional[str]:
        port = self.get_cdp_port()
        if not port:
            return None
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{port}/json")
            with urllib.request.urlopen(req, timeout=3) as resp:
                targets = json.loads(resp.read().decode("utf-8"))
                for target in targets:
                    if target.get("type") == "page" or "webSocketDebuggerUrl" in target:
                        return target.get("webSocketDebuggerUrl")
        except Exception as e:
            logger.debug(f"Error fetching CDP target list: {e}")
        return None

    async def _evaluate_async(self, expression: str, await_promise: bool = False, timeout: float = 5.0) -> Any:
        ws_url = self.get_websocket_debugger_url()
        if not ws_url:
            raise ConnectionError("Antigravity Desktop IDE CDP websocket is not available")

        async with websockets.connect(ws_url, open_timeout=timeout) as ws:
            payload = {
                "id": 1,
                "method": "Runtime.evaluate",
                "params": {
                    "expression": expression,
                    "returnByValue": True,
                    "awaitPromise": await_promise
                }
            }
            await ws.send(json.dumps(payload))
            msg = await asyncio.wait_for(ws.recv(), timeout=timeout)
            res = json.loads(msg)
            result = res.get("result", {})
            if "exceptionDetails" in result:
                err = result["exceptionDetails"].get("text", "Unknown CDP JS exception")
                raise RuntimeError(f"CDP evaluation error: {err}")
            return result.get("result", {}).get("value")

    def evaluate(self, expression: str, await_promise: bool = False, timeout: float = 5.0) -> Any:
        """Safely runs a JS evaluation in Antigravity Desktop IDE across sync or async contexts."""
        import concurrent.futures
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                return pool.submit(asyncio.run, self._evaluate_async(expression, await_promise=await_promise, timeout=timeout)).result()
        except Exception as e:
            logger.warning(f"CDP evaluate failed: {e}")
            return None

    def get_live_projects(self) -> List[Dict[str, Any]]:
        """Queries all projects registered in Antigravity Desktop IDE via PMF."""
        expr = """
        (() => {
            try {
                let pmf = window.__PMF;
                if (!pmf) {
                    const rootEl = document.querySelector('#root') || document.querySelector('body > div');
                    const fiberKey = Object.keys(rootEl || {}).find(k => k.startsWith('__reactFiber') || k.startsWith('__reactContainer'));
                    let fiber = rootEl ? rootEl[fiberKey] : null;
                    let visited = 0;
                    function search(node) {
                        if (!node || visited > 20000 || pmf) return;
                        visited++;
                        let ctx = node.memoizedProps?.value;
                        if (ctx && typeof ctx === 'object' && ctx.projectManagementFeature) {
                            pmf = ctx.projectManagementFeature;
                        }
                        if (node.child) search(node.child);
                        if (node.sibling) search(node.sibling);
                    }
                    search(fiber);
                    if (pmf) window.__PMF = pmf;
                }
                if (!pmf) return null;
                const list = pmf.projectsStateProvider.getState() || [];
                return list.map(item => {
                    const p = item.project;
                    if (!p || !p.id) return null;
                    const res = p.projectResources?.resources || [];
                    let uri = '';
                    if (res.length > 0) {
                        const r = res[0];
                        uri = r.type?.case === 'folderUri' ? r.type.value : (r.type?.value?.folderUri || '');
                    }
                    return {
                        id: p.id,
                        name: p.name,
                        uri: uri
                    };
                }).filter(Boolean);
            } catch(e) {
                return null;
            }
        })()
        """
        res = self.evaluate(expr, await_promise=False)
        return res if isinstance(res, list) else []

    def get_sidebar_project_order(self) -> List[str]:
        """Queries the exact visual project order rendered in the Antigravity Desktop sidebar."""
        expr = """
        (() => {
            try {
                const rootEl = document.querySelector('#root') || document.querySelector('body > div');
                const fiberKey = Object.keys(rootEl || {}).find(k => k.startsWith('__reactFiber') || k.startsWith('__reactContainer'));
                let fiber = rootEl ? rootEl[fiberKey] : null;
                let visited = 0;
                let headerIds = [];
                function search(node) {
                    if (!node || visited > 50000 || headerIds.length > 0) return;
                    visited++;
                    const p = node.memoizedProps;
                    if (p && Array.isArray(p.items) && p.items.length > 10) {
                        const sample = p.items.map(x => (typeof x === 'object' && x ? x.id : x));
                        const headers = sample.filter(s => typeof s === 'string' && s.startsWith('header-')).map(s => s.replace('header-', ''));
                        if (headers.length > 0) {
                            headerIds = headers;
                            return;
                        }
                    }
                    if (node.child) search(node.child);
                    if (node.sibling) search(node.sibling);
                }
                search(fiber);
                return headerIds;
            } catch(e) {
                return [];
            }
        })()
        """
        res = self.evaluate(expr, await_promise=False, timeout=4.0)
        return res if isinstance(res, list) else []

    def create_project(self, name: str, folder_path: str, project_id: Optional[str] = None) -> Optional[Dict[str, str]]:
        """
        Creates a new genuine project in Antigravity Desktop IDE using PMF.
        Registers the project, updates projectsOrder in app_storage.json,
        and causes the project to immediately appear in the desktop sidebar.
        """
        clean_name = name.strip()
        p = Path(folder_path)
        p.mkdir(parents=True, exist_ok=True)
        resolved_path = str(p.resolve()).replace("\\", "/")
        
        # Build file URI
        if len(resolved_path) > 1 and resolved_path[1] == ":":
            drive = resolved_path[0].lower()
            rest = resolved_path[2:]
            file_uri = f"file:///{drive}%3A{rest}"
        else:
            file_uri = f"file:///{resolved_path.lstrip('/')}"

        pid = project_id or str(uuid.uuid4())

        expr = f"""
        (async () => {{
            try {{
                let pmf = window.__PMF;
                if (!pmf) {{
                    const rootEl = document.querySelector('#root') || document.querySelector('body > div');
                    const fiberKey = Object.keys(rootEl || {{}}).find(k => k.startsWith('__reactFiber') || k.startsWith('__reactContainer'));
                    let fiber = rootEl ? rootEl[fiberKey] : null;
                    let visited = 0;
                    function search(node) {{
                        if (!node || visited > 20000 || pmf) return;
                        visited++;
                        let ctx = node.memoizedProps?.value;
                        if (ctx && typeof ctx === 'object' && ctx.projectManagementFeature) {{
                            pmf = ctx.projectManagementFeature;
                        }}
                        if (node.child) search(node.child);
                        if (node.sibling) search(node.sibling);
                    }}
                    search(fiber);
                    if (pmf) window.__PMF = pmf;
                }}
                if (!pmf) return {{ success: false, error: 'PMF not found' }};

                const projObj = {{
                    id: '{pid}',
                    name: '{clean_name}',
                    projectResources: {{
                        resources: [
                            {{
                                type: {{
                                    case: 'folderUri',
                                    value: '{file_uri}'
                                }}
                            }}
                        ]
                    }},
                    isWorkspaceOnly: false
                }};

                await pmf.createProject(projObj);
                return {{ success: true, id: '{pid}' }};
            }} catch(e) {{
                return {{ success: false, error: e.message }};
            }}
        }})()
        """
        res = self.evaluate(expr, await_promise=True, timeout=8.0)
        logger.info(f"CDP create_project result for '{clean_name}': {res}")

        # Update app_storage.json projectsOrder
        storage_file = self.app_data_dir / "app_storage.json"
        if storage_file.exists():
            try:
                storage_data = json.loads(storage_file.read_text(encoding="utf-8"))
                order = storage_data.get("projectsOrder", [])
                if isinstance(order, str):
                    order = json.loads(order)
                if pid not in order:
                    order.insert(0, pid)
                    storage_data["projectsOrder"] = json.dumps(order) if isinstance(storage_data.get("projectsOrder"), str) else order
                    storage_data["lastCreatedProjectId"] = pid
                    storage_data["new-convo-last-selected-project"] = pid
                    storage_file.write_text(json.dumps(storage_data, indent=2), encoding="utf-8")
            except Exception as e:
                logger.debug(f"Failed to update app_storage.json: {e}")

        # Trigger project update event across desktop UI
        self.sync_project_change()

        return {
            "id": pid,
            "name": clean_name,
            "path": resolved_path,
            "uri": file_uri
        }

    def sync_project_change(self) -> bool:
        """Notifies Antigravity Desktop IDE of project changes to refresh the project list immediately."""
        expr = """
        (() => {
            try {
                if (window.__PMF?._onDidAnyProjectChange?.fire) {
                    window.__PMF._onDidAnyProjectChange.fire();
                }
                if (window.__TSR_ROUTER__?.invalidate) {
                    window.__TSR_ROUTER__.invalidate();
                }
                return true;
            } catch(e) {
                return false;
            }
        })()
        """
        try:
            return bool(self.evaluate(expr, await_promise=False, timeout=3.0))
        except Exception:
            return False

    def sync_new_conversation(
        self,
        cascade_id: str,
        title: str,
        workspace_path: Optional[str] = None,
        project_id: Optional[str] = None
    ) -> bool:
        """Pushes a new conversation directly into Antigravity Desktop IDE Redux store so it appears in PC sidebar immediately."""
        clean_cid = cascade_id.strip()
        safe_title = json.dumps(title.strip() if title else "New Conversation")
        pid_str = json.dumps(project_id or "")

        resolved_path = str(workspace_path or Path.cwd()).replace("\\", "/")
        if len(resolved_path) > 1 and resolved_path[1] == ":":
            drive = resolved_path[0].lower()
            rest = resolved_path[2:]
            file_uri = f"file:///{drive}%3A{rest}"
        else:
            file_uri = f"file:///{resolved_path.lstrip('/')}"
        uri_str = json.dumps(file_uri)

        expr = f"""
        (() => {{
            try {{
                let tsp = window.__TSP;
                if (!tsp) {{
                    const rootEl = document.querySelector('#root') || document.querySelector('body > div');
                    const fiberKey = Object.keys(rootEl || {{}}).find(k => k.startsWith('__reactFiber') || k.startsWith('__reactContainer'));
                    let fiber = rootEl ? rootEl[fiberKey] : null;
                    let visited = 0;
                    function search(node) {{
                        if (!node || visited > 20000 || tsp) return;
                        visited++;
                        if (node.memoizedProps?.value?.trajectorySummariesProvider) {{
                            tsp = node.memoizedProps.value.trajectorySummariesProvider;
                        }}
                        if (node.child) search(node.child);
                        if (node.sibling) search(node.sibling);
                    }}
                    search(fiber);
                    if (tsp) window.__TSP = tsp;
                }}
                if (tsp && typeof tsp.pushUpdate === 'function') {{
                    tsp.pushUpdate({{
                        type: 'create',
                        cascadeId: '{clean_cid}',
                        initialText: {safe_title},
                        workspaceUris: [{uri_str}],
                        createdAt: new Date(),
                        projectId: {pid_str},
                        envId: ''
                    }});
                }}
                if (window.__TSR_ROUTER__?.invalidate) {{
                    window.__TSR_ROUTER__.invalidate();
                }}
                return true;
            }} catch(e) {{
                return false;
            }}
        }})()
        """
        try:
            res = self.evaluate(expr, await_promise=False, timeout=4.0)
            logger.info(f"CDP sync_new_conversation for '{clean_cid}': {res}")
            return bool(res)
        except Exception as e:
            logger.debug(f"CDP sync_new_conversation failed: {e}")
            return False

    def sync_touch_conversation(self, cascade_id: str, prompt: str = "") -> bool:
        """Pushes an active update into Antigravity Desktop IDE Redux store so conversation timestamp and summary update live."""
        clean_cid = cascade_id.strip()
        safe_prompt = json.dumps(prompt[:80].strip() if prompt else "")

        expr = f"""
        (() => {{
            try {{
                let tsp = window.__TSP;
                if (!tsp) {{
                    const rootEl = document.querySelector('#root') || document.querySelector('body > div');
                    const fiberKey = Object.keys(rootEl || {{}}).find(k => k.startsWith('__reactFiber') || k.startsWith('__reactContainer'));
                    let fiber = rootEl ? rootEl[fiberKey] : null;
                    let visited = 0;
                    function search(node) {{
                        if (!node || visited > 20000 || tsp) return;
                        visited++;
                        if (node.memoizedProps?.value?.trajectorySummariesProvider) {{
                            tsp = node.memoizedProps.value.trajectorySummariesProvider;
                        }}
                        if (node.child) search(node.child);
                        if (node.sibling) search(node.sibling);
                    }}
                    search(fiber);
                    if (tsp) window.__TSP = tsp;
                }}
                if (tsp && typeof tsp.pushUpdate === 'function') {{
                    tsp.pushUpdate({{
                        type: 'updateLastUserPromptTime',
                        cascadeId: '{clean_cid}',
                        time: new Date()
                    }});
                    const optPrompt = {safe_prompt};
                    if (optPrompt) {{
                        tsp.pushUpdate({{
                            type: 'updateOptimisticSummary',
                            cascadeId: '{clean_cid}',
                            optimisticSummaryText: optPrompt
                        }});
                    }}
                }}
                if (window.__TSR_ROUTER__?.invalidate) {{
                    window.__TSR_ROUTER__.invalidate();
                }}
                return true;
            }} catch(e) {{
                return false;
            }}
        }})()
        """
        try:
            res = self.evaluate(expr, await_promise=False, timeout=4.0)
            return bool(res)
        except Exception as e:
            logger.debug(f"CDP sync_touch_conversation failed: {e}")
            return False

    def get_running_tasks(self) -> List[Dict[str, Any]]:
        """Queries running tasks from Antigravity PC IDE's React components."""
        expr = """
        (() => {
            try {
                const el = Array.from(document.querySelectorAll('*')).find(e => e.innerText && /^\\d+\\s+tasks?\\s+running$/i.test(e.innerText.trim()));
                let tasks = null;
                if (el) {
                    const key = Object.keys(el).find(k => k.startsWith('__reactFiber'));
                    let fiber = el[key];
                    while (fiber) {
                        if (fiber.memoizedProps && fiber.memoizedProps.tasks) {
                            tasks = fiber.memoizedProps.tasks;
                            break;
                        }
                        fiber = fiber.return;
                    }
                }
                if (!tasks) {
                    const all = Array.from(document.querySelectorAll('*'));
                    for (const e of all) {
                        const k = Object.keys(e).find(k => k.startsWith('__reactFiber'));
                        if (k && e[k]?.memoizedProps?.tasks?.length) {
                            tasks = e[k].memoizedProps.tasks;
                            break;
                        }
                    }
                }
                if (!tasks || !Array.isArray(tasks)) return [];
                return tasks.map(item => {
                    const snap = item.taskSnapshot || {};
                    const details = item.taskDetails || {};
                    return {
                        id: snap.taskId || details.id || '',
                        command: snap.description || details.description || '',
                        title: snap.toolSummary || details.title || '',
                        is_running: true,
                        is_daemon: Boolean(snap.isDaemon ?? details.isDaemon),
                        log_uri: snap.logUri || details.logUri || ''
                    };
                });
            } catch(e) {
                return [];
            }
        })()
        """
        try:
            res = self.evaluate(expr, await_promise=False, timeout=3.0)
            if isinstance(res, list):
                return res
            return []
        except Exception as e:
            logger.debug(f"CDP get_running_tasks failed: {e}")
            return []

cdp_client = AntigravityCdpClient()

