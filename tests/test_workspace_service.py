import pytest
import tempfile
from pathlib import Path
from bridge.core.workspace_service import WorkspaceService

def test_workspace_file_operations():
    with tempfile.TemporaryDirectory() as tmpdir:
        ws = WorkspaceService(allowed_roots=[tmpdir])
        assert ws.set_active_root(tmpdir) is True

        test_file = Path(tmpdir) / "test.txt"
        res = ws.write_file(str(test_file), "Hello from Antigravity Bridge!")
        assert res["status"] == "success"

        read_res = ws.read_file(str(test_file))
        assert read_res["content"] == "Hello from Antigravity Bridge!"

        # File tree test
        tree = ws.get_file_tree(max_depth=2)
        assert len(tree) == 1
        assert tree[0]["name"] == "test.txt"
