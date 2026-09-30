import pytest
import asyncio
from bridge.core.stream_hub import StreamHub

@pytest.mark.asyncio
async def test_stream_hub_approval_resolution():
    hub = StreamHub()
    
    # Request approval asynchronously
    async def request_task():
        return await hub.request_approval("call_abc123", "shell", {"command": "ls"}, timeout_seconds=5.0)

    task = asyncio.create_task(request_task())
    await asyncio.sleep(0.05)
    
    assert "call_abc123" in hub.pending_approvals
    hub.resolve_approval("call_abc123", True)

    result = await task
    assert result is True
    assert "call_abc123" not in hub.pending_approvals

@pytest.mark.asyncio
async def test_stream_hub_approval_timeout():
    hub = StreamHub()
    # Test short timeout
    result = await hub.request_approval("call_timeout", "shell", {}, timeout_seconds=0.1)
    assert result is False
