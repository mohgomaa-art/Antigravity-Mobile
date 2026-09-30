import io
import os
import sys
import re
import json
import logging
import asyncio
import socket
import time
from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple
import mimetypes
import urllib.parse

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends, Header, Query, UploadFile, File, Form, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, JSONResponse, FileResponse
from pydantic import BaseModel
import qrcode

from bridge.core.fleet_manager import FleetManager
from bridge.core.account_router import AccountRouter, RoutingMode
from bridge.core.stream_hub import StreamHub
from bridge.core.workspace_service import WorkspaceService
from bridge.core.skills_service import SkillsService
from bridge.core.history_service import HistoryService, _normalize_questions
from bridge.core.command_processor import CommandProcessor
from bridge.core.cascade_client import AntigravityCascadeClient
from bridge.core.cdp_client import cdp_client
from bridge.core.tunnel_manager import tunnel_mgr

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("agy.server")

# Load configuration with dynamic unique token generation
USER_CONFIG_PATH = Path.home() / ".antigravity-fleet" / "config" / "fleet_config.json"
CONFIG_PATH = Path(__file__).parent / "config" / "fleet_config.json"
config = {}
target_cfg_file = USER_CONFIG_PATH

if USER_CONFIG_PATH.exists():
    try:
        with open(USER_CONFIG_PATH, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception:
        pass

if not config and CONFIG_PATH.exists():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception:
        pass

raw_token = config.get("gateway", {}).get("pairing_token")
if not raw_token or raw_token == "agy_sec_fleet_7f3b89a24d014e2898c6":
    import secrets
    raw_token = f"agy_fleet_{secrets.token_urlsafe(16)}"
    config.setdefault("gateway", {})["pairing_token"] = raw_token
    try:
        target_cfg_file.parent.mkdir(parents=True, exist_ok=True)
        with open(target_cfg_file, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2)
        logger.info(f"Generated new unique station pairing token: {raw_token}")
    except Exception as e:
        logger.warning(f"Could not persist generated pairing token: {e}")

PAIRING_TOKEN = raw_token
REQUIRE_AUTH = config.get("gateway", {}).get("require_auth", True)

# Initialize core services
fleet_mgr = FleetManager(
    count=config.get("fleet", {}).get("total_accounts", 15),
    base_port=config.get("fleet", {}).get("base_port", 53001),
    profiles_dir=config.get("fleet", {}).get("profiles_dir"),
    binary_path=config.get("fleet", {}).get("binary_path")
)
router = AccountRouter(fleet_mgr, default_mode=RoutingMode.SINGLE_ACCOUNT)
stream_hub = StreamHub()
workspace_svc = WorkspaceService(allowed_roots=config.get("workspaces", {}).get("allowed_roots"))
skills_svc = SkillsService(workspace_path=str(workspace_svc.active_root))
command_proc = CommandProcessor(skills_svc=skills_svc)
history_svc = HistoryService()
cascade_client = AntigravityCascadeClient()

app = FastAPI(title="Antigravity Mobile Fleet Bridge", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def verify_token(
    request: Request,
    x_bridge_token: Optional[str] = Header(None),
    token: Optional[str] = Query(None),
    authorization: Optional[str] = Header(None)
):
    if not REQUIRE_AUTH:
        return True

    # Local desktop loopback (the Windows Fleet Station app on the same machine) is always trusted
    client_host = request.client.host if request.client else ""
    if client_host in ("127.0.0.1", "::1", "localhost"):
        return True

    req_token = x_bridge_token or token
    if not req_token and authorization:
        parts = authorization.split()
        if len(parts) == 2 and parts[0].lower() == "bearer":
            req_token = parts[1]
    if req_token != PAIRING_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid or missing pairing token")
    return True

# --- API Models ---
class ChatRequest(BaseModel):
    prompt: str
    conversation_id: Optional[str] = None
    account_id: Optional[int] = None
    model: Optional[str] = "flash"
    workspace_path: Optional[str] = None
    project_name: Optional[str] = None
    attachments: Optional[List[Dict[str, Any]]] = None

class SkillCreateRequest(BaseModel):
    name: str
    description: str
    instructions: str
    source: Optional[str] = "global"

class SkillUpdateRequest(BaseModel):
    description: str
    instructions: str

class ChatSteerRequest(BaseModel):
    prompt: str
    conversation_id: str
    account_id: Optional[int] = None

class ChatQueueRequest(BaseModel):
    prompt: str
    conversation_id: str
    account_id: Optional[int] = None
    model: Optional[str] = "flash"

class ModelSwitchRequest(BaseModel):
    model: str
    account_id: Optional[int] = None
    conversation_id: Optional[str] = None

class ModeRequest(BaseModel):
    mode: RoutingMode

class ApprovalResponse(BaseModel):
    call_id: str
    approved: bool

class FileWriteRequest(BaseModel):
    path: str
    content: str

class CommandRequest(BaseModel):
    command: str
    timeout: Optional[int] = 60

class ProjectAddRequest(BaseModel):
    name: str
    path: str

class ProjectRemoveRequest(BaseModel):
    name: str

class AuthTokenRequest(BaseModel):
    account_id: int
    email: str
    token: str
    auth_type: Optional[str] = "google_oauth"
    alias: Optional[str] = None

class QuickLoginRequest(BaseModel):
    account_id: int
    email: Optional[str] = None
    alias: Optional[str] = None
    token: Optional[str] = None

class BatchLoginRequest(BaseModel):
    base_email: Optional[str] = None

class BatchWorkerRequest(BaseModel):
    account_ids: List[int]

class SaveAccountRequest(BaseModel):
    account_id: int
    email: str
    alias: Optional[str] = None
    token: Optional[str] = None

class NewConversationRequest(BaseModel):
    workspace_path: Optional[str] = None
    model: Optional[str] = "flash"
    account_id: Optional[int] = None
    project_name: Optional[str] = None


# --- Health Check Endpoints (Zero-Auth, Instant Response) ---
@app.get("/health")
@app.get("/api/health")
@app.get("/api/fleet/health")
async def health_check():
    gw_port = config.get("gateway", {}).get("port", int(os.environ.get("AGY_PORT", 8765)))
    return {"status": "ok", "app": "AntigravityFleetStation", "port": gw_port}

# --- Fleet Endpoints ---
@app.get("/api/fleet/status")
def get_fleet_status(_: bool = Depends(verify_token)):
    try:
        fleet_mgr._init_profiles()
    except Exception:
        pass
    return {
        "mode": router.mode,
        "total_accounts": fleet_mgr.count,
        "workers": fleet_mgr.list_workers()
    }

@app.post("/api/fleet/mode")
def set_fleet_mode(req: ModeRequest, _: bool = Depends(verify_token)):
    router.set_mode(req.mode)
    return {"status": "success", "mode": router.mode}

@app.post("/api/fleet/worker/{account_id}/start")
@app.post("/api/fleet/spawn/{account_id}")
def start_worker(account_id: int, _: bool = Depends(verify_token)):
    w = fleet_mgr.start_worker(account_id, spawn_process=True)
    return {"status": "spawned", "worker": w}

@app.post("/api/fleet/worker/{account_id}/stop")
@app.post("/api/fleet/kill/{account_id}")
def stop_worker(account_id: int, _: bool = Depends(verify_token)):
    success = fleet_mgr.stop_worker(account_id)
    return {"status": "stopped" if success else "not_running"}

@app.post("/api/fleet/spawn_all")
def spawn_all_endpoint(_: bool = Depends(verify_token)):
    workers = fleet_mgr.start_all(spawn_process=True)
    return {"status": "spawned_all", "count": len(workers), "workers": workers}

@app.post("/api/fleet/kill_all")
def kill_all_endpoint(_: bool = Depends(verify_token)):
    count = fleet_mgr.stop_all()
    return {"status": "killed_all", "count": count}

@app.get("/api/fleet/auth_status")
def get_auth_status(_: bool = Depends(verify_token)):
    return {
        "slots": fleet_mgr.auth_vault.list_credentials()
    }

@app.post("/api/fleet/auth_token")
def set_auth_token(req: AuthTokenRequest, _: bool = Depends(verify_token)):
    cred = fleet_mgr.auth_vault.set_credential(
        account_id=req.account_id,
        email=req.email,
        token=req.token,
        auth_type=req.auth_type or "google_oauth",
        alias=req.alias
    )
    fleet_mgr._init_profiles()
    return {"status": "success", "credential": cred}

@app.post("/api/fleet/auth/login/{account_id}")
def quick_login_endpoint(account_id: int, req: Optional[QuickLoginRequest] = None, _: bool = Depends(verify_token)):
    email = req.email if req else None
    alias = req.alias if req else None
    token = req.token if req else None
    cred = fleet_mgr.auth_vault.quick_login(account_id, email=email, alias=alias, token=token)
    fleet_mgr._init_profiles()
    return {"status": "success", "credential": cred}

@app.post("/api/fleet/auth/batch_login")
def batch_login_endpoint(req: Optional[BatchLoginRequest] = None, _: bool = Depends(verify_token)):
    base_email = req.base_email if req else None
    creds = fleet_mgr.auth_vault.batch_quick_login(base_email=base_email)
    fleet_mgr._init_profiles()
    return {"status": "success", "count": len(creds), "credentials": creds}

@app.post("/api/fleet/auth/clear/{account_id}")
def clear_auth_endpoint(account_id: int, _: bool = Depends(verify_token)):
    cred = fleet_mgr.auth_vault.clear_credential(account_id)
    fleet_mgr._init_profiles()
    return {"status": "cleared", "credential": cred}

@app.post("/api/fleet/auth/launch_oauth/{account_id}")
def launch_oauth_endpoint(account_id: int, _: bool = Depends(verify_token)):
    session = fleet_mgr.auth_vault.launch_antigravity_auth_window(account_id)
    url = session.get("url") if isinstance(session, dict) else None
    clean_session = {
        "account_id": session.get("account_id"),
        "port": session.get("port"),
        "url": session.get("url"),
        "status": session.get("status"),
        "message": session.get("message"),
        "started_at": session.get("started_at"),
        "email": session.get("email"),
    } if isinstance(session, dict) else None
    return {
        "status": "launched",
        "account_id": account_id,
        "session": clean_session,
        "url": url,
        "port": session.get("port") if isinstance(session, dict) else 53000 + account_id,
        "message": "Google Sign-In window launched with ZERO saved cookies. Complete sign-in in browser."
    }

@app.get("/api/fleet/auth/status/{account_id}")
def auth_status_endpoint(account_id: int, _: bool = Depends(verify_token)):
    from bridge.core.cred_manager import cred_manager
    status = cred_manager.get_auth_status(account_id)
    if status.get("status") == "authenticated" and status.get("email"):
        fleet_mgr.auth_vault.detect_profile_auth(account_id)
        fleet_mgr._init_profiles()
    return status

@app.post("/api/fleet/auth/cancel/{account_id}")
def cancel_auth_endpoint(account_id: int, _: bool = Depends(verify_token)):
    from bridge.core.cred_manager import cred_manager
    cred_manager.cancel_auth_flow(account_id)
    return {"status": "cancelled", "account_id": account_id}

@app.post("/api/fleet/auth/detect/{account_id}")
def detect_auth_endpoint(account_id: int, _: bool = Depends(verify_token)):
    email = fleet_mgr.auth_vault.detect_profile_auth(account_id)
    fleet_mgr._init_profiles()
    return {"status": "detected" if email else "not_found", "email": email, "account_id": account_id}

@app.post("/api/fleet/auth/save_account")
def save_account_endpoint(req: SaveAccountRequest, _: bool = Depends(verify_token)):
    cred = fleet_mgr.auth_vault.set_credential(
        account_id=req.account_id,
        email=req.email,
        alias=req.alias,
        token=req.token,
        is_authenticated=True
    )
    from bridge.core.cred_manager import cred_manager
    cred_manager.save_slot_credential(req.account_id, {"email": req.email, "token": req.token or ""}, email=req.email)
    cred_manager.restore_slot_to_system(1)
    fleet_mgr._init_profiles()
    return {"status": "saved", "credential": cred}

@app.post("/api/fleet/spawn_multiple")
def spawn_multiple_endpoint(req: BatchWorkerRequest, _: bool = Depends(verify_token)):
    spawned = []
    for aid in req.account_ids:
        try:
            w = fleet_mgr.start_worker(aid, spawn_process=True)
            spawned.append(w)
        except Exception as e:
            logger.warning(f"Error spawning worker {aid}: {e}")
    return {"status": "success", "count": len(spawned), "workers": spawned}

@app.post("/api/fleet/kill_multiple")
def kill_multiple_endpoint(req: BatchWorkerRequest, _: bool = Depends(verify_token)):
    killed = []
    for aid in req.account_ids:
        if fleet_mgr.stop_worker(aid):
            killed.append(aid)
    return {"status": "success", "count": len(killed), "account_ids": killed}


from bridge.core.model_discovery import model_discovery
from bridge.core.proto_util import update_pbtxt_field

LANGUAGE_SERVER_EXE = str(model_discovery.resolve_binary_paths()["language_server"])
BRAIN_DIR = Path.home() / ".gemini" / "antigravity" / "brain"

# Dynamic Execution Tasks Registry & Conversation Message Queues
active_execution_tasks: Dict[str, Dict[str, Any]] = {}
active_agent_runs: Dict[str, Dict[str, Any]] = {}
active_subprocesses: List[asyncio.subprocess.Process] = []
conversation_message_queues: Dict[str, List[Dict[str, Any]]] = {}
recent_dispatched_prompts: Dict[str, float] = {}

def update_antigravity_model_state(profile_dir: Optional[Path], proto_model: str):
    targets = [
        Path.home() / ".gemini" / "antigravity" / "antigravity_state.pbtxt",
    ]
    if profile_dir:
        targets.append(profile_dir / "antigravity_state.pbtxt")
        targets.append(profile_dir / "antigravity-ide" / "antigravity_state.pbtxt")

    for target in targets:
        if target.exists():
            update_pbtxt_field(target, "last_selected_agent_model", proto_model)

async def execute_real_antigravity_agent(
    prompt: str,
    convo_id: Optional[str],
    worker,
    model: str = "flash",
    workspace_path: Optional[str] = None,
    project_name: Optional[str] = None,
    attachments: Optional[List[Dict[str, Any]]] = None
):
    real_convo_id = convo_id
    run_id = f"run_{int(asyncio.get_event_loop().time() * 1000)}"
    active_agent_runs[run_id] = {
        "id": run_id,
        "account_id": worker.account_id,
        "conversation_id": real_convo_id or "new",
        "is_running": True,
        "start_time": time.time()
    }

    # Resolve model tier and protobuf representation
    tier, proto_model = model_discovery.resolve_model(model)
    pdir = Path(worker.profile_dir) if worker and hasattr(worker, "profile_dir") else None
    update_antigravity_model_state(pdir, proto_model)

    # Emit initial thought
    await stream_hub.emit_thought(
        account_id=worker.account_id,
        conversation_id=convo_id or "new",
        thought=f"Engaging Antigravity Agent [{worker.alias}] with model '{model}' [{tier.upper()}]..."
    )

    try:
        is_new = not real_convo_id or real_convo_id.startswith("convo-") or real_convo_id == "new"
        if is_new:
            ws_root = workspace_path or (str(workspace_svc.active_root) if (workspace_svc and workspace_svc.active_root) else str(Path.cwd()))
            new_id = cascade_client.start_cascade(workspace_path=ws_root, model_proto=proto_model)
            if new_id:
                real_convo_id = new_id
                active_agent_runs[run_id]["conversation_id"] = real_convo_id
                target_project = project_name or (Path(ws_root).name if Path(ws_root).name else "Workspace")
                history_svc.register_active_cascade(real_convo_id, target_project, ws_root)
                if convo_id and convo_id in conversation_message_queues:
                    conversation_message_queues[real_convo_id] = conversation_message_queues.pop(convo_id)
                await stream_hub.broadcast({
                    "type": "conversation_created",
                    "temp_id": convo_id or "new",
                    "conversation_id": real_convo_id
                })
                logger.info(f"Spawned new Antigravity Cascade {real_convo_id} for project '{target_project}'")
            else:
                logger.error("Failed to start new cascade via LanguageServer RPC")
                await stream_hub.emit_token(
                    account_id=worker.account_id,
                    conversation_id=convo_id or "error",
                    token="Failed to initialize conversation session with Antigravity."
                )
                return

        if not real_convo_id:
            real_convo_id = "default"

        active_agent_runs[run_id]["conversation_id"] = real_convo_id

        # Pre-record existing transcript byte size so we DO NOT replay past turns into the stream!
        log_file = BRAIN_DIR / real_convo_id / ".system_generated" / "logs" / "transcript.jsonl"
        initial_bytes = 0
        if log_file.exists():
            try:
                initial_bytes = log_file.stat().st_size
            except Exception:
                pass

        expanded_prompt, detected_cmd = command_proc.process_prompt(prompt)
        if detected_cmd:
            logger.info(f"Slash command '{detected_cmd}' processed and expanded")
            await stream_hub.emit_thought(
                account_id=worker.account_id,
                conversation_id=real_convo_id,
                thought=f"[Workflow: {detected_cmd}] Activated specialized directive."
            )

        if attachments:
            uploaded_images = []
            uploaded_files = []
            for att in attachments:
                path = att.get("absolute_path") or att.get("path") or ""
                name = att.get("filename") or att.get("name") or Path(path).name
                mime = att.get("mime_type", "")
                if mime.startswith("image/") or path.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".webp")):
                    uploaded_images.append(path.replace("\\", "/"))
                else:
                    uploaded_files.append((name, path.replace("\\", "/")))

            metadata_parts = []
            if uploaded_images:
                metadata_parts.append(f"The user has uploaded {len(uploaded_images)} image(s):")
                for img in uploaded_images:
                    metadata_parts.append(f"- {img}")
                metadata_parts.append("You can embed this image in an artifact if you need the USER to review it.")
            if uploaded_files:
                for name, path in uploaded_files:
                    metadata_parts.append(f"@[{path}] is a [File]:\n{path}")

            if metadata_parts:
                expanded_prompt += "\n\n<ADDITIONAL_METADATA>\n" + "\n".join(metadata_parts) + "\n</ADDITIONAL_METADATA>"

        # CRITICAL: Always append autonomous execution directive to prevent agent from calling ask_question and hanging remote/mobile clients
        expanded_prompt += (
            "\n\n<AUTONOMOUS_EXECUTION_DIRECTIVE>\n"
            "CRITICAL: Do NOT pause execution by calling ask_question or waiting for interactive choice modals. "
            "Proceed autonomously by selecting the recommended/best option and implementing it immediately. "
            "State your choice and rationale in your final response.\n"
            "</AUTONOMOUS_EXECUTION_DIRECTIVE>"
        )

        # Dispatch prompt directly to Antigravity LanguageServer RPC
        send_success = cascade_client.send_user_message(
            cascade_id=real_convo_id,
            prompt=expanded_prompt,
            model_proto=proto_model
        )
        if not send_success:
            logger.warning(f"Failed to dispatch to cascade {real_convo_id}. Auto-healing: spawning fresh cascade session...")
            # Auto-healing: if LanguageServer does not recognize cascade_id (e.g. stale or restarted), spawn fresh cascade
            ws_root = workspace_path or (str(workspace_svc.active_root) if workspace_svc.active_root else str(Path.cwd()))
            new_id = cascade_client.start_cascade(workspace_path=ws_root, model_proto=proto_model)
            if new_id:
                old_convo_id = real_convo_id
                real_convo_id = new_id
                active_agent_runs[run_id]["conversation_id"] = real_convo_id
                target_project = project_name or Path(ws_root).name if ws_root else "Workspace"
                history_svc.register_active_cascade(real_convo_id, target_project, ws_root)
                await stream_hub.broadcast({
                    "type": "conversation_created",
                    "temp_id": old_convo_id,
                    "conversation_id": real_convo_id
                })
                # Re-dispatch prompt to the newly spawned cascade
                send_success = cascade_client.send_user_message(
                    cascade_id=real_convo_id,
                    prompt=expanded_prompt,
                    model_proto=proto_model
                )
                log_file = BRAIN_DIR / real_convo_id / ".system_generated" / "logs" / "transcript.jsonl"
                initial_bytes = 0

        if not send_success:
            logger.error(f"Failed to dispatch message to cascade {real_convo_id} after auto-heal")
            await stream_hub.emit_token(
                account_id=worker.account_id,
                conversation_id=real_convo_id,
                token="Antigravity session re-initialized. Please send your message again."
            )
            return

        # Live sync conversation update to Antigravity Desktop IDE via CDP
        try:
            cdp_client.sync_touch_conversation(real_convo_id, clean_prompt)
        except Exception:
            pass

        read_steps = set()
        finished = False
        current_offset = initial_bytes

        # Poll transcript file as agent executes (up to 240 * 0.25s = 60s)
        for _ in range(240):
            if log_file.exists():
                try:
                    with open(log_file, "r", encoding="utf-8", errors="replace") as f:
                        if current_offset > 0:
                            f.seek(current_offset)
                        lines = f.readlines()
                        current_offset = f.tell()

                    for line in lines:
                        line_str = line.strip()
                        if not line_str:
                            continue
                        try:
                            step = json.loads(line_str)
                        except Exception:
                            continue
                        step_idx = step.get("step_index", -1)
                        if step_idx in read_steps and step_idx != -1:
                            continue

                        if step.get("type") in ("RUN_COMMAND", "GENERIC"):
                            # A tool execution step finished
                            for tid in list(active_execution_tasks.keys()):
                                if active_execution_tasks[tid].get("conversation_id") == real_convo_id:
                                    active_execution_tasks.pop(tid, None)

                        if step.get("source") == "MODEL" and step.get("type") == "PLANNER_RESPONSE":
                            thinking = step.get("thinking", "")
                            content = step.get("content", "")
                            tool_calls = step.get("tool_calls", [])
                            status = step.get("status", "")

                            if thinking:
                                await stream_hub.emit_thought(
                                    account_id=worker.account_id,
                                    conversation_id=real_convo_id,
                                    thought=thinking
                                )

                            if tool_calls:
                                for tc in tool_calls:
                                    tool_name = tc.get("name", "tool")
                                    args = tc.get("args", {})
                                    call_id = tc.get("id", "call")
                                    await stream_hub.emit_tool_call(
                                        account_id=worker.account_id,
                                        conversation_id=real_convo_id,
                                        tool_name=tool_name,
                                        args=args,
                                        call_id=call_id
                                    )
                                    norm_name = str(tool_name).split(":")[-1]
                                    if norm_name == "run_command":
                                        cmd_val = args.get("CommandLine") if isinstance(args, dict) else ""
                                        if not cmd_val and isinstance(args, dict):
                                            cmd_val = args.get("command", "")
                                        cmd_str = str(cmd_val).strip().strip('"')
                                        if cmd_str:
                                            task_cmd_id = f"cmd_{call_id}"
                                            active_execution_tasks[task_cmd_id] = {
                                                "id": task_cmd_id,
                                                "command": cmd_str,
                                                "account_id": worker.account_id,
                                                "conversation_id": real_convo_id,
                                                "is_running": True
                                            }
                                    elif norm_name == "ask_question":
                                        parsed_q = _normalize_questions(args)
                                        tool_sum = args.get("toolSummary", "") if isinstance(args, dict) else ""
                                        tool_act = args.get("toolAction", "") if isinstance(args, dict) else ""
                                        await stream_hub.emit_question(
                                            account_id=worker.account_id,
                                            conversation_id=real_convo_id,
                                            call_id=call_id,
                                            questions=parsed_q,
                                            tool_summary=tool_sum,
                                            question_data={
                                                "questions": parsed_q,
                                                "tool_summary": tool_sum,
                                                "tool_action": tool_act
                                            }
                                        )
                                        finished = True

                            if content:
                                for w in content.split(" "):
                                    await stream_hub.emit_token(
                                        account_id=worker.account_id,
                                        conversation_id=real_convo_id,
                                        token=w + " "
                                    )
                                    await asyncio.sleep(0.01)
                                if (not tool_calls) or status == "DONE":
                                    finished = True

                            read_steps.add(step_idx)
                except Exception as ex:
                    logger.warning(f"Error reading transcript: {ex}")

                if finished:
                    break

            await asyncio.sleep(0.25)

    except Exception as e:
        logger.error(f"Error executing Antigravity agent: {e}")
        await stream_hub.emit_token(
            account_id=worker.account_id,
            conversation_id=real_convo_id or "error",
            token=f"Execution error: {e}"
        )
    finally:
        active_agent_runs.pop(run_id, None)
        for tid in list(active_execution_tasks.keys()):
            if active_execution_tasks[tid].get("conversation_id") in (real_convo_id, convo_id, "new"):
                active_execution_tasks.pop(tid, None)
        if real_convo_id:
            try:
                history_svc.touch_conversation(
                    conversation_id=real_convo_id,
                    preview=prompt[:120] if prompt else None,
                    workspace_path=workspace_path,
                    project_name=project_name
                )
            except Exception:
                pass
        await stream_hub.emit_done(
            account_id=worker.account_id,
            conversation_id=real_convo_id or "default"
        )
        await stream_hub.broadcast({
            "type": "steps_updated",
            "conversation_id": real_convo_id or "default"
        })
        # Automatically pop and dispatch next queued message if present
        if real_convo_id in conversation_message_queues and conversation_message_queues[real_convo_id]:
            next_req = conversation_message_queues[real_convo_id].pop(0)
            logger.info(f"Popping queued message for conversation {real_convo_id}: {next_req['prompt'][:30]}")
            asyncio.create_task(
                execute_real_antigravity_agent(
                    prompt=next_req["prompt"],
                    convo_id=real_convo_id,
                    worker=worker,
                    model=next_req.get("model", "flash")
                )
            )

# --- Chat & Streaming ---
@app.post("/api/chat/send")
async def send_chat(req: ChatRequest, _: bool = Depends(verify_token)):
    targets = router.resolve_target_accounts(
        conversation_id=req.conversation_id,
        requested_account_id=req.account_id
    )

    if not targets:
        raise HTTPException(status_code=503, detail="No available worker accounts in fleet")

    ws_root = req.workspace_path or (str(workspace_svc.active_root) if (workspace_svc and workspace_svc.active_root) else str(Path.cwd()))
    target_project = req.project_name or (Path(ws_root).name if Path(ws_root).name else "Workspace")
    tier, proto_model = model_discovery.resolve_model(req.model or "flash")
    project_id = history_svc.get_project_id_by_name(target_project, workspace_path=ws_root)

    convo_id = req.conversation_id
    is_new = not convo_id or convo_id.startswith("convo-") or convo_id in ("new", "default", "active")
    if is_new:
        new_cid = cascade_client.start_cascade(
            workspace_path=ws_root,
            model_proto=proto_model,
            project_id=project_id
        )
        if new_cid:
            if req.conversation_id:
                history_svc.register_alias(req.conversation_id, new_cid)
            convo_id = new_cid
            history_svc.register_active_cascade(convo_id, target_project, ws_root, project_id=project_id)
            try:
                cdp_client.sync_new_conversation(
                    cascade_id=convo_id,
                    project_name=target_project,
                    project_id=project_id,
                    workspace_path=ws_root
                )
            except Exception:
                pass
        else:
            convo_id = req.conversation_id or f"convo-{os.urandom(4).hex()}"
    else:
        convo_id = history_svc.resolve_active_convo_id(req.conversation_id)

    global active_monitored_convo_id
    active_monitored_convo_id = convo_id

    clean_prompt = req.prompt.strip()
    key = f"{convo_id}:{clean_prompt}"
    last_steered = recent_dispatched_prompts.get(key, 0)
    if time.time() - last_steered < 3.0:
        logger.info(f"Ignoring send_chat for prompt that was just steered: {clean_prompt[:30]}")
        return {
            "status": "ignored_steered",
            "conversation_id": convo_id
        }

    try:
        history_svc.touch_conversation(
            conversation_id=convo_id,
            preview=req.prompt[:120],
            workspace_path=ws_root,
            project_name=target_project
        )
    except Exception:
        pass

    for target in targets:
        asyncio.create_task(
            execute_real_antigravity_agent(
                prompt=req.prompt,
                convo_id=convo_id,
                worker=target,
                model=req.model or "flash",
                workspace_path=ws_root,
                project_name=target_project,
                attachments=req.attachments
            )
        )

    return {
        "status": "dispatched",
        "conversation_id": convo_id,
        "targeted_accounts": [w.account_id for w in targets]
    }

@app.post("/api/conversations/new")
async def create_new_conversation(req: Optional[NewConversationRequest] = None, _: bool = Depends(verify_token)):
    workspace_path = req.workspace_path if req and req.workspace_path else str(workspace_svc.active_root)
    model = req.model if req and req.model else "flash"
    project_name = req.project_name if req and req.project_name else None
    if not project_name:
        project_name = Path(workspace_path).name if workspace_path else "Antigravity"

    # Resolve genuine project UUID in Antigravity Desktop IDE
    project_id = history_svc.get_project_id_by_name(project_name, workspace_path=workspace_path)

    tier, proto_model = model_discovery.resolve_model(model)
    cascade_id = cascade_client.start_cascade(
        workspace_path=workspace_path,
        model_proto=proto_model,
        project_id=project_id
    )
    if not cascade_id:
        raise HTTPException(status_code=500, detail="Failed to initialize new Antigravity Cascade session")

    history_svc.register_active_cascade(cascade_id, project_name, workspace_path, project_id=project_id)
    try:
        history_svc.touch_conversation(
            conversation_id=cascade_id,
            title="New Conversation",
            preview="Ready for prompt",
            workspace_path=workspace_path,
            project_name=project_name
        )
    except Exception:
        pass

    # Push new conversation directly into Antigravity Desktop IDE so it appears immediately
    try:
        cdp_client.sync_new_conversation(
            cascade_id=cascade_id,
            title=f"Chat in {project_name}" if project_name else "New Conversation",
            workspace_path=workspace_path,
            project_id=project_id
        )
    except Exception:
        pass

    return {
        "status": "created",
        "conversation_id": cascade_id,
        "project_id": project_id,
        "workspace_path": workspace_path,
        "model": model,
        "proto_model": proto_model,
        "project_name": project_name
    }

@app.post("/api/chat/steer")
async def steer_chat(req: ChatSteerRequest, _: bool = Depends(verify_token)):
    worker = router.resolve(req.account_id)
    clean_prompt = req.prompt.strip()
    now = time.time()
    
    # Record recent steer dispatch for deduplication
    key = f"{req.conversation_id}:{clean_prompt}"
    recent_dispatched_prompts[key] = now

    # Purge any queued items that match this exact prompt to prevent double execution
    if req.conversation_id in conversation_message_queues:
        conversation_message_queues[req.conversation_id] = [
            q for q in conversation_message_queues[req.conversation_id]
            if q.get("prompt", "").strip() != clean_prompt
        ]

    expanded_prompt, detected_cmd = command_proc.process_prompt(req.prompt)
    success = cascade_client.send_user_message(
        cascade_id=req.conversation_id,
        prompt=expanded_prompt
    )

    try:
        cdp_client.sync_touch_conversation(req.conversation_id, clean_prompt)
    except Exception:
        pass

    await stream_hub.emit_thought(
        account_id=worker.account_id,
        conversation_id=req.conversation_id,
        thought=f"[Steer Action] {req.prompt}"
    )
    await stream_hub.broadcast({
        "type": "steer_sent",
        "conversation_id": req.conversation_id,
        "prompt": req.prompt,
        "account_id": worker.account_id
    })
    return {"status": "steered" if success else "failed"}

@app.get("/api/commands")
def list_commands(_: bool = Depends(verify_token)):
    return {
        "commands": command_proc.get_all_commands()
    }

@app.post("/api/chat/queue")
async def queue_chat(req: ChatQueueRequest, _: bool = Depends(verify_token)):
    clean_prompt = req.prompt.strip()
    key = f"{req.conversation_id}:{clean_prompt}"
    last_steered = recent_dispatched_prompts.get(key, 0)
    if time.time() - last_steered < 3.0:
        logger.info(f"Ignoring queue request for prompt that was just steered: {clean_prompt[:30]}")
        return {
            "status": "ignored_steered",
            "conversation_id": req.conversation_id,
            "queue_count": len(conversation_message_queues.get(req.conversation_id, []))
        }

    if req.conversation_id not in conversation_message_queues:
        conversation_message_queues[req.conversation_id] = []

    # Prevent duplicate identical prompts queued back-to-back
    if any(q.get("prompt", "").strip() == clean_prompt for q in conversation_message_queues[req.conversation_id]):
        return {
            "status": "already_queued",
            "conversation_id": req.conversation_id,
            "queue_count": len(conversation_message_queues[req.conversation_id])
        }

    conversation_message_queues[req.conversation_id].append({
        "prompt": req.prompt,
        "account_id": req.account_id,
        "model": req.model
    })

    await stream_hub.broadcast({
        "type": "message_queued",
        "conversation_id": req.conversation_id,
        "prompt": req.prompt,
        "queue_count": len(conversation_message_queues[req.conversation_id])
    })
    return {
        "status": "queued",
        "conversation_id": req.conversation_id,
        "queue_count": len(conversation_message_queues[req.conversation_id])
    }

@app.get("/api/chat/queue/{conversation_id}")
def get_chat_queue(conversation_id: str, _: bool = Depends(verify_token)):
    q = conversation_message_queues.get(conversation_id, [])
    return {"conversation_id": conversation_id, "queue": q, "count": len(q)}

@app.get("/api/fleet/quota")
@app.get("/api/quota")
def get_quota_endpoint(_: bool = Depends(verify_token)):
    quota_summary = model_discovery.fetch_live_quota_summary()
    return quota_summary

@app.get("/api/models")
def get_models_endpoint(_: bool = Depends(verify_token)):
    models = model_discovery.get_client_models()
    return {"models": models, "count": len(models)}

@app.post("/api/chat/model")
async def switch_chat_model(req: ModelSwitchRequest, _: bool = Depends(verify_token)):
    worker = router.resolve(req.account_id)
    tier, proto_model = model_discovery.resolve_model(req.model)
    pdir = Path(worker.profile_dir) if worker and hasattr(worker, "profile_dir") else None
    update_antigravity_model_state(pdir, proto_model)

    account_id = worker.account_id if worker else 1
    logger.info(f"Model switched to '{req.model}' (tier: {tier}, proto: {proto_model}) for Account #{account_id}")

    await stream_hub.broadcast({
        "type": "model_switched",
        "model": req.model,
        "tier": tier,
        "proto_model": proto_model,
        "account_id": account_id,
        "conversation_id": req.conversation_id
    })
    return {
        "status": "success",
        "model": req.model,
        "tier": tier,
        "proto_model": proto_model
    }

@app.post("/api/chat/stop")
async def stop_chat(_: bool = Depends(verify_token)):
    active_execution_tasks.clear()
    active_agent_runs.clear()
    for p in list(active_subprocesses):
        try:
            p.terminate()
        except Exception:
            pass
    active_subprocesses.clear()
    await stream_hub.emit_event({
        "type": "cancelled",
        "message": "Execution halted by user request"
    })
    return {"status": "stopped"}

# --- Tool Approvals ---
@app.post("/api/approvals/resolve")
async def resolve_approval(req: ApprovalResponse, _: bool = Depends(verify_token)):
    resolved = stream_hub.resolve_approval(req.call_id, req.approved)
    return {"status": "resolved" if resolved else "not_found"}

# --- Workspaces & Files ---
@app.get("/api/workspaces")
def list_workspaces(_: bool = Depends(verify_token)):
    return {
        "active_root": str(workspace_svc.active_root),
        "roots": workspace_svc.list_roots()
    }

@app.post("/api/workspaces/active")
def set_active_workspace(path: str = Query(...), _: bool = Depends(verify_token)):
    success = workspace_svc.set_active_root(path)
    if not success:
        raise HTTPException(status_code=400, detail="Invalid workspace path")
    return {"status": "success", "active_root": str(workspace_svc.active_root)}

@app.get("/api/workspaces/tree")
def get_tree(depth: int = Query(3), _: bool = Depends(verify_token)):
    return {"tree": workspace_svc.get_file_tree(max_depth=depth)}

@app.get("/api/workspaces/file")
def read_file(path: str = Query(...), _: bool = Depends(verify_token)):
    try:
        return workspace_svc.read_file(path)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="File not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/workspaces/file")
def write_file(req: FileWriteRequest, _: bool = Depends(verify_token)):
    return workspace_svc.write_file(req.path, req.content)

@app.post("/api/workspaces/command")
def run_command(req: CommandRequest, _: bool = Depends(verify_token)):
    return workspace_svc.execute_command(req.command, timeout=req.timeout or 60)

@app.get("/api/workspaces/files")
def search_workspace_files(query: str = Query(""), limit: int = Query(50), _: bool = Depends(verify_token)):
    return {"files": workspace_svc.search_files(query=query, limit=limit)}

# --- Media Upload & Serving ---
@app.post("/api/media/upload")
async def upload_media(
    file: UploadFile = File(...),
    conversation_id: Optional[str] = Form(None),
    _: bool = Depends(verify_token)
):
    target_convo = conversation_id or "shared"
    upload_dir = BRAIN_DIR / target_convo / ".user_uploaded"
    upload_dir.mkdir(parents=True, exist_ok=True)

    raw_name = Path(file.filename or "upload").name
    safe_name = re.sub(r"[^\w\-.]", "_", raw_name)
    timestamp = int(time.time() * 1000)
    saved_filename = f"media_{timestamp}_{safe_name}"
    target_path = upload_dir / saved_filename

    total_size = 0
    with open(target_path, "wb") as out_f:
        while True:
            chunk = await file.read(65536)
            if not chunk:
                break
            out_f.write(chunk)
            total_size += len(chunk)

    mime_type = file.content_type or mimetypes.guess_type(saved_filename)[0] or "application/octet-stream"

    return {
        "status": "ok",
        "filename": saved_filename,
        "original_name": raw_name,
        "size": total_size,
        "mime_type": mime_type,
        "absolute_path": str(target_path).replace("\\", "/"),
        "url": f"/api/media/file?path={urllib.parse.quote(str(target_path))}"
    }

@app.get("/api/media/file")
def get_media_file(path: str = Query(...)):
    raw_path = path.strip()
    if raw_path.startswith("file:///"):
        raw_path = raw_path[8:]
    elif raw_path.startswith("file://"):
        raw_path = raw_path[7:]

    raw_path = urllib.parse.unquote(raw_path)
    if os.name == "nt" and raw_path.startswith("/") and len(raw_path) > 2 and raw_path[2] == ":":
        raw_path = raw_path[1:]

    p = Path(raw_path)
    if not p.is_absolute() or not p.exists():
        candidates = [
            BRAIN_DIR / raw_path,
            Path.home() / ".gemini" / "antigravity" / raw_path,
            workspace_svc.active_root / raw_path,
            Path.cwd() / raw_path,
        ]
        for c in candidates:
            if c.exists() and c.is_file():
                p = c
                break

    if not p.exists() or not p.is_file():
        raise HTTPException(status_code=404, detail="Media file not found")

    mime_type, _ = mimetypes.guess_type(str(p))
    return FileResponse(str(p), media_type=mime_type or "application/octet-stream", filename=p.name)

# --- Skills ---
@app.get("/api/skills")
def list_skills(_: bool = Depends(verify_token)):
    return {
        "skills": skills_svc.list_all_skills(),
        "slash_commands": skills_svc.get_slash_commands()
    }

@app.get("/api/skills/{skill_id}")
def get_skill_detail(skill_id: str, _: bool = Depends(verify_token)):
    detail = skills_svc.get_skill_detail(skill_id)
    if not detail:
        raise HTTPException(status_code=404, detail="Skill not found")
    return detail

@app.post("/api/skills")
def create_custom_skill(req: SkillCreateRequest, _: bool = Depends(verify_token)):
    try:
        res = skills_svc.create_skill(
            name=req.name,
            description=req.description,
            instructions=req.instructions,
            source=req.source or "global"
        )
        return {"status": "created", "skill": res}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/api/skills/{skill_id}")
def update_custom_skill(skill_id: str, req: SkillUpdateRequest, _: bool = Depends(verify_token)):
    try:
        res = skills_svc.update_skill(
            skill_id=skill_id,
            description=req.description,
            instructions=req.instructions
        )
        return {"status": "updated", "skill": res}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Skill not found")
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.delete("/api/skills/{skill_id}")
def delete_custom_skill(skill_id: str, _: bool = Depends(verify_token)):
    try:
        success = skills_svc.delete_skill(skill_id)
        if not success:
            raise HTTPException(status_code=404, detail="Skill not found or could not be deleted")
        return {"status": "deleted", "skill_id": skill_id}
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/api/skills/toggle")
@app.post("/api/skills/{skill_id}/toggle")
def toggle_skill(
    skill_id: Optional[str] = None,
    name: Optional[str] = Query(None),
    enabled: bool = Query(True),
    body: Optional[Dict[str, Any]] = None,
    _: bool = Depends(verify_token)
):
    target_name = skill_id or name
    if body and "enabled" in body:
        enabled = bool(body["enabled"])
    if not target_name:
        raise HTTPException(status_code=400, detail="Skill name or ID required")
    skills_svc.toggle_skill(target_name, enabled)
    return {"status": "success", "name": target_name, "enabled": enabled}

# --- Conversation History ---
@app.get("/api/history")
async def list_history(limit: int = 50, offset: int = 0, _: bool = Depends(verify_token)):
    return {"conversations": await history_svc.list_conversations(limit=limit, offset=offset)}

@app.get("/api/history/{conversation_id}/transcript")
def get_transcript(conversation_id: str, _: bool = Depends(verify_token)):
    return {"transcript": history_svc.get_conversation_transcript(conversation_id)}

@app.get("/api/projects/grouped")
def get_projects_grouped(convo_id: Optional[str] = Query(None), project: Optional[str] = Query(None), _: bool = Depends(verify_token)):
    res = history_svc.get_projects_grouped(active_convo_id=convo_id, active_project=project)
    all_runs = list(active_agent_runs.values()) + list(active_execution_tasks.values())
    running_convo_ids = {
        t.get("conversation_id") for t in all_runs if t.get("is_running") and t.get("conversation_id")
    }
    if "projects" in res:
        for p in res["projects"]:
            for c in p.get("conversations", []):
                if c.get("id") in running_convo_ids:
                    c["status"] = "working"
                elif c.get("status") in ("working", "running", "busy") and c.get("id") not in running_convo_ids:
                    c["status"] = "done"
    return res

@app.post("/api/projects/add")
def add_project(req: ProjectAddRequest, _: bool = Depends(verify_token)):
    res = history_svc.add_custom_project(req.name, req.path)
    return {
        "status": "success",
        "id": res.get("id"),
        "name": res.get("name"),
        "path": res.get("path")
    }

@app.post("/api/projects/remove")
def remove_project(req: ProjectRemoveRequest, _: bool = Depends(verify_token)):
    history_svc.remove_project(req.name)
    return {"status": "success", "name": req.name}

@app.get("/api/conversations/{conversation_id}/steps")
def get_conversation_steps(conversation_id: str, _: bool = Depends(verify_token)):
    global active_monitored_convo_id
    resolved_id = history_svc.resolve_active_convo_id(conversation_id)
    active_monitored_convo_id = resolved_id
    steps = history_svc.get_conversation_steps(conversation_id)
    running_tasks = history_svc.get_running_tasks(conversation_id)
    allow_alias_fallback = conversation_id in ("active", "default", "new", "") or conversation_id.startswith("convo-")
    if not running_tasks and resolved_id != conversation_id and allow_alias_fallback:
        running_tasks = history_svc.get_running_tasks(resolved_id)

    # Merge any in-memory active tasks strictly for this conversation
    for t in active_execution_tasks.values():
        is_match = t.get("is_running") and (t.get("conversation_id") == conversation_id or (allow_alias_fallback and t.get("conversation_id") == resolved_id))
        if is_match:
            if not any(x.get("id") == t.get("id") for x in running_tasks):
                running_tasks.append(t)

    steps["running_tasks"] = running_tasks
    steps["active_tasks"] = running_tasks

    all_runs = [t for t in active_agent_runs.values() if t.get("conversation_id") == conversation_id or (allow_alias_fallback and t.get("conversation_id") == resolved_id)] + \
               [t for t in active_execution_tasks.values() if t.get("conversation_id") == conversation_id or (allow_alias_fallback and t.get("conversation_id") == resolved_id)]
    is_task_running = any(t.get("is_running") for t in all_runs) or bool(running_tasks)
    if is_task_running:
        steps["is_working"] = True
        if steps.get("turns"):
            steps["turns"][-1] = {**steps["turns"][-1], "is_working": True}
    return steps

@app.get("/api/conversations/active/steps")
def get_active_conversation_steps(_: bool = Depends(verify_token)):
    global active_monitored_convo_id
    active_id = history_svc.resolve_active_convo_id(active_monitored_convo_id or "")
    return get_conversation_steps(active_id, _)

@app.get("/api/steps")
def get_steps_fallback(conversation_id: str = "", _: bool = Depends(verify_token)):
    global active_monitored_convo_id
    target_id = conversation_id or active_monitored_convo_id or ""
    active_id = history_svc.resolve_active_convo_id(target_id)
    return get_conversation_steps(active_id, _)

@app.get("/api/tasks/running")
def get_running_tasks(conversation_id: str = "", _: bool = Depends(verify_token)):
    tasks = [t for t in active_execution_tasks.values() if t.get("is_running")]
    if conversation_id:
        tasks = [t for t in tasks if t.get("conversation_id") == conversation_id]
        hist_tasks = history_svc.get_running_tasks(conversation_id)
        for t in hist_tasks:
            if conversation_id in t.get("id", "") or not t.get("id"):
                if not any(x.get("id") == t.get("id") or (x.get("command") and x.get("command") == t.get("command")) for x in tasks):
                    tasks.append(t)
    return {
        "count": len(tasks),
        "tasks": tasks
    }

@app.get("/api/tasks/log")
def get_task_log(task_id: str = "", log_uri: str = "", _: bool = Depends(verify_token)):
    target_path = None
    if log_uri:
        raw_path = log_uri.replace("file:///", "").replace("file://", "").replace("/", "\\")
        target_path = Path(raw_path)
    elif task_id:
        parts = task_id.split("/")
        if len(parts) == 2:
            cid, tname = parts
            target_path = history_svc.brain_dir / cid / ".system_generated" / "tasks" / f"{tname}.log"

    if target_path and target_path.exists():
        try:
            with open(target_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
                lines = content.splitlines()
                if len(lines) > 500:
                    content = "\n".join(lines[-500:])
                return {"status": "success", "log": content}
        except Exception as e:
            return {"status": "error", "error": str(e), "log": ""}
    return {"status": "error", "error": "Log not found", "log": ""}

# --- Pairing QR Code ---
@app.get("/api/pairing/qr")
def get_pairing_qr():
    # Detect local LAN IP
    local_ip = "127.0.0.1"
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        pass

    public_url = tunnel_mgr.get_public_url()
    lan_ips = get_all_lan_ips()
    primary_ip = lan_ips[0] if lan_ips else local_ip
    port = config.get("gateway", {}).get("port", 8765)
    all_hosts = ([public_url] if public_url else []) + lan_ips
    if "127.0.0.1" not in all_hosts:
        all_hosts.append("127.0.0.1")

    pairing_payload = json.dumps({
        "host": primary_ip,
        "lan_ip": primary_ip,
        "public_url": public_url,
        "hosts": all_hosts,
        "port": port,
        "token": PAIRING_TOKEN,
        "name": "Antigravity Windows Station",
        "timestamp": int(time.time())
    })

    qr = qrcode.QRCode(box_size=8, border=2)
    qr.add_data(pairing_payload)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return Response(content=buf.getvalue(), media_type="image/png")

def get_all_lan_ips() -> List[str]:
    """
    Enumerates all active, non-loopback IPv4 addresses across all adapters
    (Wi-Fi, Ethernet, USB Tethering, Virtual adapters), prioritizing physical and tethering IPs.
    """
    import psutil
    ips = []
    try:
        stats = psutil.net_if_stats()
        addrs = psutil.net_if_addrs()

        for iface_name, iface_addrs in addrs.items():
            stat = stats.get(iface_name)
            if stat and not stat.isup:
                continue
            for addr in iface_addrs:
                if addr.family == socket.AF_INET:
                    ip = addr.address
                    if ip.startswith("127.") or ip.startswith("169.254."):
                        continue
                    if ip not in ips:
                        ips.append(ip)
    except Exception as e:
        logger.warning(f"Error enumerating LAN IPs via psutil: {e}")

    # Fallback to standard socket probe if psutil returned empty
    if not ips:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            probe_ip = s.getsockname()[0]
            s.close()
            if probe_ip not in ips and not probe_ip.startswith("127."):
                ips.append(probe_ip)
        except Exception:
            pass

    # Priority sort: USB Tethering (192.168.42.x, etc.) > Home LAN (192.168.x.x) > Class A (10.x.x.x) > Others
    def ip_priority(ip_str: str) -> int:
        if ip_str.startswith("192.168.42.") or ip_str.startswith("192.168.43.") or ip_str.startswith("192.168.44."):
            return 0  # USB tethering
        if ip_str.startswith("192.168."):
            return 1  # Standard LAN
        if ip_str.startswith("10."):
            return 2  # Private Class A
        if ip_str.startswith("172."):
            return 3  # Hyper-V / Docker / WSL
        return 4

    ips.sort(key=ip_priority)
    if not ips:
        ips = ["127.0.0.1"]
    return ips

async def udp_beacon_task():
    """
    Broadcasts UDP discovery packets on port 8766 every 1.5 seconds.
    Any Antigravity Mobile app listening on UDP 8766 will auto-discover this station.
    """
    BEACON_PORT = 8766
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setblocking(False)

    logger.info(f"Starting UDP auto-discovery beacon on port {BEACON_PORT}")
    while True:
        try:
            lan_ips = get_all_lan_ips()
            port = config.get("gateway", {}).get("port", 8765)
            beacon_data = json.dumps({
                "app": "AntigravityFleetStation",
                "version": "1.0.2",
                "port": port,
                "token": PAIRING_TOKEN,
                "hosts": lan_ips,
                "name": "Antigravity Windows Station",
                "timestamp": int(time.time())
            }).encode("utf-8")

            # 1. Global Broadcast
            try:
                sock.sendto(beacon_data, ("255.255.255.255", BEACON_PORT))
            except Exception:
                pass

            # 2. Directed Subnet Broadcasts
            for ip in lan_ips:
                parts = ip.split(".")
                if len(parts) == 4:
                    subnet_bcast = f"{parts[0]}.{parts[1]}.{parts[2]}.255"
                    try:
                        sock.sendto(beacon_data, (subnet_bcast, BEACON_PORT))
                    except Exception:
                        pass
        except Exception as e:
            logger.debug(f"UDP beacon tick error: {e}")

        await asyncio.sleep(1.5)

@app.get("/api/pairing/info")
def get_pairing_info():
    public_url = tunnel_mgr.get_public_url()
    lan_ips = get_all_lan_ips()
    primary_ip = lan_ips[0] if lan_ips else "127.0.0.1"
    port = config.get("gateway", {}).get("port", 8765)
    workers = fleet_mgr.list_workers()
    active_count = sum(1 for w in workers if w.is_active)
    auth_count = sum(1 for w in workers if w.is_registered)

    all_hosts = []
    if public_url:
        all_hosts.append(public_url)
    for lip in lan_ips:
        if lip not in all_hosts:
            all_hosts.append(lip)
    if "127.0.0.1" not in all_hosts:
        all_hosts.append("127.0.0.1")

    payload_dict = {
        "host": primary_ip,
        "lan_ip": primary_ip,
        "hosts": all_hosts,
        "public_url": public_url,
        "port": port,
        "token": PAIRING_TOKEN,
        "name": "Antigravity Windows Station",
        "timestamp": int(time.time())
    }
    return {
        "host": primary_ip,
        "lan_ip": primary_ip,
        "hosts": all_hosts,
        "public_url": public_url,
        "alt_hosts": ["127.0.0.1"] + [h for h in all_hosts if h != "127.0.0.1"],
        "port": port,
        "token": PAIRING_TOKEN,
        "url": public_url or f"http://{primary_ip}:{port}",
        "lan_url": f"http://{primary_ip}:{port}",
        "qr_payload": json.dumps(payload_dict),
        "accounts_count": fleet_mgr.count,
        "active_accounts": active_count,
        "authenticated_accounts": auth_count,
        "tunnel_status": tunnel_mgr.get_status()
    }

@app.get("/api/tunnel/status")
def get_tunnel_status():
    return tunnel_mgr.get_status()

@app.post("/api/tunnel/start")
def start_tunnel():
    started = tunnel_mgr.start()
    return {"success": started, "status": tunnel_mgr.get_status()}

@app.post("/api/tunnel/stop")
def stop_tunnel():
    tunnel_mgr.stop()
    return {"success": True, "status": tunnel_mgr.get_status()}


# --- Background Real-time Transcript Streamer ---
active_monitored_convo_id: Optional[str] = None
transcript_offsets: Dict[str, int] = {}

async def monitor_active_transcripts():
    """
    Tails the active conversation's transcript.jsonl continuously.
    Whenever Antigravity IDE (desktop or slot) generates new thoughts, tool calls,
    tokens, or finishes steps, this streams them over WebSocket to mobile in real time.
    """
    logger.info("Starting background transcript monitor for real-time live chat streaming")
    last_convo_id = None
    read_steps = set()

    while True:
        try:
            target_id = active_monitored_convo_id
            if not target_id:
                try:
                    import sqlite3
                    conn = sqlite3.connect(str(history_svc.db_path))
                    c = conn.cursor()
                    c.execute("SELECT conversation_id FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 1")
                    row = c.fetchone()
                    conn.close()
                    if row:
                        target_id = row[0]
                except Exception:
                    pass

            if not target_id:
                await asyncio.sleep(1.0)
                continue

            log_file = BRAIN_DIR / target_id / ".system_generated" / "logs" / "transcript.jsonl"
            if target_id != last_convo_id:
                last_convo_id = target_id
                read_steps.clear()
                if log_file.exists():
                    fsize = log_file.stat().st_size
                    transcript_offsets[target_id] = max(0, fsize - 25000)
                else:
                    transcript_offsets[target_id] = 0

            if log_file.exists():
                curr_offset = transcript_offsets.get(target_id, 0)
                file_size = log_file.stat().st_size

                if file_size > curr_offset:
                    with open(log_file, "r", encoding="utf-8", errors="replace") as f:
                        f.seek(curr_offset)
                        lines = f.readlines()
                        transcript_offsets[target_id] = f.tell()

                    updated = False
                    for line in lines:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            step = json.loads(line)
                        except Exception:
                            continue

                        step_idx = step.get("step_index", -1)
                        if step_idx in read_steps and step_idx != -1:
                            continue
                        if step_idx != -1:
                            read_steps.add(step_idx)

                        updated = True
                        stype = step.get("type")
                        source = step.get("source")

                        if source == "MODEL" and stype == "PLANNER_RESPONSE":
                            thinking = step.get("thinking", "")
                            content = step.get("content", "")
                            tool_calls = step.get("tool_calls", [])

                            if thinking:
                                await stream_hub.emit_thought(
                                    account_id=1,
                                    conversation_id=target_id,
                                    thought=thinking
                                )

                            if tool_calls:
                                for tc in tool_calls:
                                    t_name = str(tc.get("name", "tool")).split(":")[-1]
                                    t_args = tc.get("args", {})
                                    if isinstance(t_args, str):
                                        try:
                                            t_args = json.loads(t_args)
                                        except Exception:
                                            t_args = {}
                                    if t_name == "ask_question":
                                        parsed_q = _normalize_questions(t_args)
                                        tool_sum = t_args.get("toolSummary", "") if isinstance(t_args, dict) else ""
                                        tool_act = t_args.get("toolAction", "") if isinstance(t_args, dict) else ""
                                        await stream_hub.emit_question(
                                            account_id=1,
                                            conversation_id=target_id,
                                            call_id=tc.get("id", "call"),
                                            questions=parsed_q,
                                            tool_summary=tool_sum,
                                            question_data={
                                                "questions": parsed_q,
                                                "tool_summary": tool_sum,
                                                "tool_action": tool_act
                                            }
                                        )

                            if content:
                                await stream_hub.emit_token(
                                    account_id=1,
                                    conversation_id=target_id,
                                    token=content
                                )

                            if content and not tool_calls and step.get("status") == "DONE":
                                await stream_hub.emit_done(
                                    account_id=1,
                                    conversation_id=target_id
                                )

                    if updated:
                        await stream_hub.broadcast({
                            "type": "steps_updated",
                            "conversation_id": target_id
                        })

        except Exception as e:
            logger.debug(f"Monitor error: {e}")

        await asyncio.sleep(0.4)

@app.on_event("startup")
async def on_startup():
    asyncio.create_task(monitor_active_transcripts())
    asyncio.create_task(udp_beacon_task())
    try:
        gw_port = config.get("gateway", {}).get("port", int(os.environ.get("AGY_PORT", 8765)))
        tunnel_mgr.target_port = gw_port
        tunnel_mgr.start()
    except Exception as e:
        logger.warning(f"Could not start cloudflare tunnel on startup: {e}")

@app.on_event("shutdown")
async def on_shutdown():
    try:
        tunnel_mgr.stop()
    except Exception:
        pass
    try:
        fleet_mgr.stop_all()
    except Exception:
        pass

# --- WebSocket Streaming ---
@app.websocket("/ws/stream")
async def websocket_endpoint(websocket: WebSocket, token: Optional[str] = Query(None)):
    if REQUIRE_AUTH and token != PAIRING_TOKEN:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    await stream_hub.connect(websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            data = json.loads(raw)
            msg_type = data.get("type")

            if msg_type == "tool_approval_response":
                call_id = data.get("call_id")
                approved = data.get("approved", False)
                if call_id:
                    stream_hub.resolve_approval(call_id, approved)

            elif msg_type == "ping":
                await websocket.send_json({"type": "pong"})

    except WebSocketDisconnect:
        stream_hub.disconnect(websocket)
    except Exception as e:
        logger.warning(f"WebSocket error: {e}")
        stream_hub.disconnect(websocket)

def ensure_port_available(port: int = 8765):
    """
    Ensure port 8765 is completely available before binding.
    If an orphaned instance of antigravity_bridge or python is holding it, kill it immediately.
    """
    import os
    import sys
    import subprocess
    import time
    current_pid = os.getpid()

    # Step 1: Check using psutil
    try:
        import psutil
        for proc in psutil.process_iter(['pid', 'name']):
            if proc.info['pid'] == current_pid:
                continue
            try:
                for conn in proc.connections(kind='inet'):
                    if conn.laddr and conn.laddr.port == port:
                        logger.warning(f"Port {port} is occupied by PID {proc.info['pid']} ({proc.info['name']}). Reclaiming port...")
                        proc.kill()
                        proc.wait(timeout=2)
                        logger.info(f"Successfully killed conflicting PID {proc.info['pid']}.")
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess, Exception):
                pass
    except Exception as e:
        logger.debug(f"psutil port cleanup check skipped: {e}")

    # Step 2: On Windows, use netstat + taskkill fallback to be 100% sure
    if sys.platform == "win32":
        try:
            out = subprocess.check_output(f"netstat -ano | findstr :{port}", shell=True, text=True, errors="ignore")
            for line in out.strip().splitlines():
                parts = line.split()
                if len(parts) >= 5 and "LISTENING" in line.upper():
                    if parts[1].endswith(f":{port}"):
                        pid = parts[-1].strip()
                        if pid.isdigit() and int(pid) != current_pid and int(pid) != 0:
                            print(f"[RECLAIM] Releasing port {port} from listening PID {pid} via taskkill...", flush=True)
                            logger.warning(f"Releasing port {port} from listening PID {pid} via taskkill...")
                            subprocess.run(f"taskkill /F /PID {pid}", shell=True, capture_output=True)
                            time.sleep(0.5)
        except Exception as e:
            logger.debug(f"netstat check skipped: {e}")

    # Step 3: Brief grace period to ensure Windows TCP stack releases the port
    time.sleep(0.3)

if __name__ == "__main__":
    import uvicorn
    host = config.get("gateway", {}).get("host", "0.0.0.0")
    port = config.get("gateway", {}).get("port", 8765)
    ensure_port_available(port)
    logger.info(f"Starting Antigravity Fleet Gateway on {host}:{port}")
    uvicorn.run(app, host=host, port=port)
