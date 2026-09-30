import re
from typing import Optional, Dict, Any, List, Tuple

BUILTIN_COMMANDS: Dict[str, Dict[str, Any]] = {
    "/plan": {
        "name": "Plan",
        "description": "Formulate a multi-phase architectural plan before modifying code",
        "category": "workflow",
        "icon": "assignment_outlined",
        "directive": (
            "<SLASH_COMMAND: /plan>\n"
            "Workflow Directive: The user has explicitly invoked Planning Mode (/plan).\n"
            "You MUST operate strictly under these planning principles for this turn:\n"
            "1. Deeply analyze the codebase, requirements, architectural constraints, and dependencies.\n"
            "2. Formulate a structured, multi-phase implementation plan with clear milestones, deliverables, and risk mitigation.\n"
            "3. Create or update an implementation plan artifact (.md) in the artifacts directory.\n"
            "4. DO NOT edit or modify production code files in this turn — await user review and approval of the plan.\n"
            "5. If requirements are ambiguous or key trade-offs exist, ask clarifying questions.\n\n"
            "User Planning Request:\n"
        )
    },
    "/btw": {
        "name": "By The Way",
        "description": "Quick side question without disrupting ongoing project context or editing code",
        "category": "utility",
        "icon": "chat_bubble_outline",
        "directive": (
            "<SLASH_COMMAND: /btw>\n"
            "Workflow Directive: The user is asking an ephemeral side-channel question ('By The Way').\n"
            "Provide a direct, accurate, and concise answer immediately.\n"
            "DO NOT divert from the ongoing project context, DO NOT edit or modify code files,\n"
            "and DO NOT launch long refactoring workflows.\n\n"
            "Side Question:\n"
        )
    },
    "/browser": {
        "name": "Browser",
        "description": "Web research, URL content extraction, and browser automation",
        "category": "automation",
        "icon": "language",
        "directive": (
            "<SLASH_COMMAND: /browser>\n"
            "Workflow Directive: The user has invoked /browser mode.\n"
            "Use your available web tools (read_url_content, search_web, Playwright browser tools)\n"
            "to fetch pages, inspect the DOM, perform searches, or automate browser interactions as requested.\n\n"
            "Browser Task:\n"
        )
    },
    "/goal": {
        "name": "Goal",
        "description": "Autonomous execution loop until the objective is completely verified",
        "category": "workflow",
        "icon": "flag_outlined",
        "directive": (
            "<SLASH_COMMAND: /goal>\n"
            "Workflow Directive: The user has invoked Autonomous Goal Runner mode (/goal).\n"
            "Execute with maximum autonomy until this goal is completely achieved.\n"
            "Run necessary tests, self-heal any compilation or runtime errors, and verify thoroughly.\n"
            "Do not stop midway or leave incomplete placeholders.\n\n"
            "Autonomous Goal:\n"
        )
    },
    "/schedule": {
        "name": "Schedule",
        "description": "Set a one-time timer or recurring cron automation task",
        "category": "automation",
        "icon": "schedule",
        "directive": (
            "<SLASH_COMMAND: /schedule>\n"
            "Workflow Directive: The user wants to schedule an automated task, one-shot timer, or recurring cron job.\n"
            "Formulate and call the schedule tool with appropriate DurationSeconds or CronExpression and Prompt.\n\n"
            "Schedule Request:\n"
        )
    },
    "/grill-me": {
        "name": "Grill Me",
        "description": "Interactive design review interview to resolve trade-offs before building",
        "category": "workflow",
        "icon": "psychology_outlined",
        "directive": (
            "<SLASH_COMMAND: /grill-me>\n"
            "Workflow Directive: Perform an architectural and requirements design review.\n"
            "Evaluate technical trade-offs, present options and your recommended approach clearly in the response text, and auto-proceed autonomously without blocking on interactive question modals.\n\n"
            "Interview Topic:\n"
        )
    },
    "/boost": {
        "name": "Boost",
        "description": "Maximum cognitive depth, multi-perspective analysis, and adversarial verification",
        "category": "reasoning",
        "icon": "bolt",
        "directive": (
            "<SLASH_COMMAND: /boost>\n"
            "Workflow Directive: The user has invoked Boost Mode (/boost).\n"
            "Apply maximum reasoning depth, strategic multi-perspective planning, and rigorous verification.\n"
            "Analyze edge cases, security implications, and performance bottlenecks.\n\n"
            "Boost Task:\n"
        )
    },
    "/learn": {
        "name": "Learn",
        "description": "Persist user preference or correction into project rules for all future turns",
        "category": "memory",
        "icon": "school_outlined",
        "directive": (
            "<SLASH_COMMAND: /learn>\n"
            "Workflow Directive: The user wants to persist a learning, rule, or preference.\n"
            "Document and persist this guideline into the project's rules (e.g. GEMINI.md or AGENTS.md)\n"
            "so all future agent turns follow it consistently.\n\n"
            "Learning / Preference:\n"
        )
    }
}

class CommandProcessor:
    def __init__(self, skills_svc=None):
        self.skills_svc = skills_svc

    def get_all_commands(self) -> List[Dict[str, Any]]:
        commands = []
        for cmd, info in BUILTIN_COMMANDS.items():
            commands.append({
                "command": cmd,
                "name": info["name"],
                "description": info["description"],
                "category": info["category"],
                "icon": info["icon"],
                "is_skill": False
            })

        if self.skills_svc:
            try:
                skills = self.skills_svc.list_all_skills()
                for s in skills:
                    cmd_name = f"/{s['name']}"
                    if cmd_name not in BUILTIN_COMMANDS:
                        commands.append({
                            "command": cmd_name,
                            "name": s["name"].replace("-", " ").title(),
                            "description": s.get("description", "Custom Antigravity skill"),
                            "category": "skills",
                            "icon": "extension_outlined",
                            "is_skill": True,
                            "skill_path": s.get("path")
                        })
            except Exception:
                pass

        return commands

    def process_prompt(self, raw_prompt: str) -> Tuple[str, Optional[str]]:
        trimmed = raw_prompt.strip()
        if not trimmed.startswith("/"):
            return raw_prompt, None

        parts = trimmed.split(None, 1)
        cmd_trigger = parts[0].lower()
        content = parts[1] if len(parts) > 1 else ""

        # Check built-in commands
        if cmd_trigger in BUILTIN_COMMANDS:
            info = BUILTIN_COMMANDS[cmd_trigger]
            expanded = f"{info['directive']}{content}" if content else f"{info['directive']}(No additional arguments provided. Please execute the default {info['name']} workflow.)"
            return expanded, cmd_trigger

        # Check skills
        if self.skills_svc:
            try:
                skills = self.skills_svc.list_all_skills()
                for s in skills:
                    skill_cmd = f"/{s['name']}".lower()
                    if cmd_trigger == skill_cmd:
                        expanded = (
                            f"<SLASH_COMMAND: {cmd_trigger}>\n"
                            f"Workflow Directive: Activate specialized skill '{s['name']}' ({s.get('description', '')}).\n"
                            f"Read and follow the guidelines defined at '{s.get('path', '')}'.\n\n"
                            f"Task:\n{content if content else 'Execute according to the skill instructions.'}"
                        )
                        return expanded, cmd_trigger
            except Exception:
                pass

        # Return original if command not matched
        return raw_prompt, cmd_trigger
