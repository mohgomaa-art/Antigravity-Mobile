import os
import re
import json
import shutil
import logging
from pathlib import Path
from typing import List, Dict, Any, Optional

logger = logging.getLogger("SkillsService")
FRONTMATTER_PATTERN = re.compile(r"^---\s*\n(.*?)\n---\s*\n(.*)$", re.DOTALL)

class SkillsService:
    def __init__(self, workspace_path: Optional[str] = None):
        self.workspace_path = Path(workspace_path) if workspace_path else Path.cwd()
        self.builtin_dir = Path.home() / ".gemini" / "antigravity" / "builtin" / "skills"
        self.global_dir = Path.home() / ".gemini" / "config" / "skills"
        self.state_file = Path.home() / ".gemini" / "antigravity" / "skills_state.json"
        self.enabled_skills: Dict[str, bool] = self._load_enabled_state()

    def _load_enabled_state(self) -> Dict[str, bool]:
        if self.state_file.exists():
            try:
                data = json.loads(self.state_file.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    return data
            except Exception as e:
                logger.warning(f"Failed to load skills state: {e}")
        return {}

    def _save_enabled_state(self):
        try:
            self.state_file.parent.mkdir(parents=True, exist_ok=True)
            self.state_file.write_text(json.dumps(self.enabled_skills, indent=2), encoding="utf-8")
        except Exception as e:
            logger.error(f"Failed to save skills state: {e}")

    def list_all_skills(self) -> List[Dict[str, Any]]:
        skills = []
        seen = set()

        search_dirs = [
            ("workspace", self.workspace_path / ".gemini" / "skills"),
            ("workspace", self.workspace_path / "skills"),
            ("global", self.global_dir),
            ("builtin", self.builtin_dir),
        ]

        for source_type, directory in search_dirs:
            if not directory.exists() or not directory.is_dir():
                continue

            try:
                entries = sorted(directory.iterdir(), key=lambda d: d.name.lower())
            except Exception:
                continue

            for skill_dir in entries:
                if not skill_dir.is_dir():
                    continue

                skill_file = skill_dir / "SKILL.md"
                if not skill_file.exists():
                    continue

                name = skill_dir.name
                if name in seen:
                    continue
                seen.add(name)

                try:
                    content = skill_file.read_text(encoding="utf-8", errors="replace")
                except Exception:
                    content = ""

                desc = "No description provided"
                body = content

                match = FRONTMATTER_PATTERN.match(content)
                if match:
                    frontmatter = match.group(1)
                    body = match.group(2)
                    for line in frontmatter.splitlines():
                        if line.startswith("description:"):
                            desc = line.split("description:", 1)[1].strip()
                        elif line.startswith("name:"):
                            name = line.split("name:", 1)[1].strip()

                is_enabled = self.enabled_skills.get(name, True)

                skills.append({
                    "id": skill_dir.name,
                    "name": name,
                    "description": desc,
                    "source": source_type,
                    "path": str(skill_file),
                    "is_enabled": is_enabled,
                    "is_editable": source_type != "builtin",
                    "instruction_preview": body[:300].strip() + ("..." if len(body) > 300 else "")
                })

        return skills

    def get_skill_detail(self, skill_id: str) -> Optional[Dict[str, Any]]:
        for skill in self.list_all_skills():
            if skill["id"] == skill_id or skill["name"] == skill_id:
                p = Path(skill["path"])
                try:
                    full_text = p.read_text(encoding="utf-8", errors="replace")
                except Exception as e:
                    full_text = f"Error reading skill: {e}"
                skill["full_instructions"] = full_text
                return skill
        return None

    def toggle_skill(self, skill_name: str, enabled: bool) -> bool:
        self.enabled_skills[skill_name] = enabled
        self._save_enabled_state()
        return True

    def create_skill(self, name: str, description: str, instructions: str, source: str = "global") -> Dict[str, Any]:
        clean_name = re.sub(r"[^a-zA-Z0-9_\-]", "-", name.strip().lower()).strip("-")
        if not clean_name:
            raise ValueError("Skill name must contain valid alphanumeric characters")

        if source == "workspace":
            target_dir = self.workspace_path / "skills" / clean_name
        else:
            target_dir = self.global_dir / clean_name

        target_dir.mkdir(parents=True, exist_ok=True)
        skill_file = target_dir / "SKILL.md"

        clean_desc = description.strip().replace("\n", " ")
        header = f"---\nname: {clean_name}\ndescription: {clean_desc}\n---\n\n"
        content = header + instructions.strip() + "\n"

        skill_file.write_text(content, encoding="utf-8")
        self.enabled_skills[clean_name] = True
        self._save_enabled_state()

        return {
            "id": clean_name,
            "name": clean_name,
            "description": clean_desc,
            "source": source,
            "path": str(skill_file),
            "is_enabled": True,
            "is_editable": True,
            "instruction_preview": instructions[:300].strip() + ("..." if len(instructions) > 300 else "")
        }

    def update_skill(self, skill_id: str, description: str, instructions: str) -> Dict[str, Any]:
        skill = self.get_skill_detail(skill_id)
        if not skill:
            raise FileNotFoundError(f"Skill '{skill_id}' not found")

        if skill.get("source") == "builtin":
            raise PermissionError("Builtin skills cannot be edited")

        skill_file = Path(skill["path"])
        name = skill["name"]
        clean_desc = description.strip().replace("\n", " ")
        header = f"---\nname: {name}\ndescription: {clean_desc}\n---\n\n"
        content = header + instructions.strip() + "\n"

        skill_file.write_text(content, encoding="utf-8")
        return self.get_skill_detail(skill_id) or skill

    def delete_skill(self, skill_id: str) -> bool:
        skill = self.get_skill_detail(skill_id)
        if not skill:
            return False

        if skill.get("source") == "builtin":
            raise PermissionError("Builtin skills cannot be deleted")

        skill_file = Path(skill["path"])
        skill_dir = skill_file.parent
        if skill_dir.exists() and skill_dir.is_dir():
            shutil.rmtree(skill_dir, ignore_errors=True)
            if skill["name"] in self.enabled_skills:
                del self.enabled_skills[skill["name"]]
                self._save_enabled_state()
            return True
        return False

    def get_slash_commands(self) -> List[Dict[str, str]]:
        return [
            {"command": "/goal", "description": "Run thorough, long-running overnight autonomous task until goal is verified"},
            {"command": "/plan", "description": "Multi-phase detailed planning mode before code execution"},
            {"command": "/schedule", "description": "Recurring cron job or one-time delayed background timer"},
            {"command": "/browser", "description": "Playwright web browser automation and testing"},
            {"command": "/grill-me", "description": "Interactive interview to resolve design decisions"},
            {"command": "/boost", "description": "Deep thinking, strategic perspectives, and rigorous verification"},
            {"command": "/learn", "description": "Persist new behavior and preferences for future tasks"}
        ]
