import json
import logging
import asyncio
from typing import Dict, Set, Optional, Any
from fastapi import WebSocket

logger = logging.getLogger("agy.stream_hub")

class StreamHub:
    def __init__(self):
        self.active_connections: Set[WebSocket] = set()
        self.pending_approvals: Dict[str, asyncio.Future] = {}

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)
        logger.info(f"WebSocket client connected. Total clients: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        self.active_connections.discard(websocket)
        logger.info(f"WebSocket client disconnected. Total clients: {len(self.active_connections)}")

    async def broadcast(self, message: Dict[str, Any]):
        if not self.active_connections:
            return

        dead_connections = set()
        for ws in self.active_connections:
            try:
                await ws.send_json(message)
            except Exception as e:
                logger.warning(f"Failed to send to client: {e}")
                dead_connections.add(ws)

        for ws in dead_connections:
            self.active_connections.discard(ws)

    async def emit_token(self, account_id: int, conversation_id: str, token: str):
        await self.broadcast({
            "type": "token",
            "account_id": account_id,
            "conversation_id": conversation_id,
            "data": token
        })

    async def emit_thought(self, account_id: int, conversation_id: str, thought: str):
        await self.broadcast({
            "type": "thought",
            "account_id": account_id,
            "conversation_id": conversation_id,
            "data": thought
        })

    async def emit_done(self, account_id: int, conversation_id: str):
        await self.broadcast({
            "type": "done",
            "account_id": account_id,
            "conversation_id": conversation_id
        })

    async def emit_tool_call(self, account_id: int, conversation_id: str, tool_name: str, args: dict, call_id: str):
        await self.broadcast({
            "type": "tool_call",
            "account_id": account_id,
            "conversation_id": conversation_id,
            "call_id": call_id,
            "tool_name": tool_name,
            "args": args
        })

    async def emit_question(
        self,
        account_id: int,
        conversation_id: str,
        call_id: str = "call",
        questions: Optional[list] = None,
        tool_summary: str = "",
        question_data: Optional[dict] = None
    ):
        if question_data and isinstance(question_data, dict):
            questions = question_data.get("questions", questions or [])
            tool_summary = question_data.get("tool_summary", tool_summary)
        payload = {
            "type": "ask_question",
            "account_id": account_id,
            "conversation_id": conversation_id,
            "call_id": call_id,
            "questions": questions or [],
            "tool_summary": tool_summary,
            "question_data": question_data or {
                "questions": questions or [],
                "tool_summary": tool_summary
            }
        }
        await self.broadcast(payload)

    async def emit_tool_result(self, account_id: int, conversation_id: str, call_id: str, result: Any, status: str = "success"):
        await self.broadcast({
            "type": "tool_result",
            "account_id": account_id,
            "conversation_id": conversation_id,
            "call_id": call_id,
            "result": result,
            "status": status
        })

    async def request_approval(self, call_id: str, tool_name: str, args: dict, timeout_seconds: float = 60.0) -> bool:
        """Pushes an approval request to the phone and pauses execution until user responds or timeout occurs."""
        loop = asyncio.get_event_loop()
        future: asyncio.Future = loop.create_future()
        self.pending_approvals[call_id] = future

        await self.broadcast({
            "type": "tool_approval_request",
            "call_id": call_id,
            "tool_name": tool_name,
            "args": args,
            "timeout": timeout_seconds
        })

        try:
            decision = await asyncio.wait_for(future, timeout=timeout_seconds)
            return bool(decision)
        except asyncio.TimeoutError:
            logger.warning(f"Approval request {call_id} timed out. Defaulting to deny.")
            return False
        finally:
            self.pending_approvals.pop(call_id, None)

    def resolve_approval(self, call_id: str, approved: bool):
        future = self.pending_approvals.get(call_id)
        if future and not future.done():
            future.set_result(approved)
            logger.info(f"Resolved approval for {call_id}: approved={approved}")
            return True
        return False
