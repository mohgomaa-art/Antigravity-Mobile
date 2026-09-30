import os
import re
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger("agy.proto_util")

def update_pbtxt_field(file_path: Path, field_name: str, new_value: str) -> bool:
    """
    Safely updates or inserts a top-level field in a Protobuf text (.pbtxt) file.
    Preserves all existing blocks, unknown fields, migrations, comments, and structure.
    Uses atomic temporary file replacement to ensure zero state corruption.
    """
    try:
        content = ""
        if file_path.exists():
            content = file_path.read_text(encoding="utf-8", errors="replace")

        pattern = rf"^({re.escape(field_name)}:\s*)([^\r\n]+)"
        matched = False

        new_lines = []
        for line in content.splitlines(keepends=True):
            if re.match(pattern, line):
                new_lines.append(f"{field_name}: {new_value}\n")
                matched = True
            else:
                new_lines.append(line)

        if not matched:
            # Append cleanly at end
            base = "".join(new_lines).rstrip()
            if base:
                final_content = base + f"\n{field_name}: {new_value}\n"
            else:
                final_content = f"{field_name}: {new_value}\n"
        else:
            final_content = "".join(new_lines)

        # Atomic write
        tmp_file = file_path.with_suffix(f".tmp_{os.getpid()}")
        tmp_file.write_text(final_content, encoding="utf-8")
        os.replace(tmp_file, file_path)
        return True
    except Exception as e:
        logger.error(f"Failed to update {field_name} in {file_path}: {e}")
        return False

def read_pbtxt_field(file_path: Path, field_name: str) -> Optional[str]:
    """Reads a top-level scalar field value from a .pbtxt file without modifying it."""
    if not file_path.exists():
        return None
    try:
        content = file_path.read_text(encoding="utf-8", errors="replace")
        match = re.search(rf"^{re.escape(field_name)}:\s*([^\r\n]+)", content, re.MULTILINE)
        if match:
            return match.group(1).strip().strip('"').strip("'")
    except Exception:
        pass
    return None
